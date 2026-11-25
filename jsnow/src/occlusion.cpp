#include "occlusion.hpp"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdlib>

namespace jsnow {

namespace {
constexpr float kMargin = 1.0f;  // world units: coarse occluders may sit slightly above the true surface
}

OcclusionCuller::OcclusionCuller(ThreadPool& pool, const Scene& scene, int w, int h)
    : pool_(pool), scene_(scene), rast_(pool, scene), w_(w), h_(h) {
  int lw = w, lh = h;
  while (true) {
    mw_.push_back(lw); mh_.push_back(lh);
    mips_.emplace_back(size_t(lw) * lh, 0.0f);
    if (lw == 1 && lh == 1) break;
    lw = std::max(1, (lw + 1) / 2); lh = std::max(1, (lh + 1) / 2);
  }
}

void OcclusionCuller::build(const Camera& cam, StageTimes& st) {
  using clk = std::chrono::steady_clock;
  auto t0 = clk::now();
  viewProj_ = cam.viewProj;
  p11_ = cam.proj(1, 1);
  StageTimes inner;
  occluderTris_ = buildDrawList(scene_, cam.viewProj, cam.pos, lodPixelScale(cam), true, 2, draws_, nullptr, nullptr,
                                true, nullptr, true).triangles;
  PassParams pp;
  pp.viewProj = cam.viewProj;
  pp.vp = Viewport::full(w_, h_);
  pp.mode = PassMode::DepthOnly;
  Target t;
  t.w = w_; t.h = h_;
  t.depth = mips_[0].data();
  rast_.render(pp, draws_, t, inner);
  buildPyramid();
  st.cull += std::chrono::duration<double, std::milli>(clk::now() - t0).count();
}

void OcclusionCuller::buildFromDepth(const float* depth, int dw, int dh, const Camera& prev, const Camera& cur,
                                     StageTimes& st) {
  using clk = std::chrono::steady_clock;
  auto t0 = clk::now();
  viewProj_ = cur.viewProj;
  p11_ = cur.proj(1, 1);
  // 1) min-reduce the previous depth into a w_ x h_ grid (farthest sample).
  small_.assign(size_t(w_) * h_, 0.0f);
  pool_.run(h_, [&](int y, int) {
    const int ys = y * dh / h_, ye = std::max(ys + 1, (y + 1) * dh / h_);
    for (int x = 0; x < w_; ++x) {
      const int xs = x * dw / w_, xe = std::max(xs + 1, (x + 1) * dw / w_);
      float m = 1e30f;
      for (int yy = ys; yy < ye; ++yy) {
        const float* row = depth + size_t(yy) * dw;
        for (int xx = xs; xx < xe; ++xx) m = std::min(m, row[xx]);
      }
      small_[size_t(y) * w_ + x] = m;
    }
  });
  // 2) Test against the previous camera (the depth's own view): no holes. The
  //    scene is static, so the only error is one frame of camera motion; the
  //    1 m depth margin absorbs most of it.
  if (std::getenv("JSNOW_OCCLUSION_REPROJECT") == nullptr) {
    viewProj_ = prev.viewProj;
    p11_ = prev.proj(1, 1);
    mips_[0] = small_;
  } else {
    std::vector<float>& d0 = mips_[0];
    std::fill(d0.begin(), d0.end(), 0.0f);
    std::vector<uint8_t> written(size_t(w_) * h_, 0);
    const Mat4 M = cur.viewProj * prev.invView;
    const float ip00 = 1.0f / prev.proj(0, 0), ip11 = 1.0f / prev.proj(1, 1);
    for (int y = 0; y < h_; ++y)
      for (int x = 0; x < w_; ++x) {
        const float d = small_[size_t(y) * w_ + x];
        if (d <= 0.0f) continue;
        const float w = kNear / d;
        const float ndcx = (x + 0.5f) / w_ * 2 - 1, ndcy = 1 - (y + 0.5f) / h_ * 2;
        const float vx = ndcx * w * ip00, vy = ndcy * w * ip11, vz = -w;
        const float X = M(0, 0) * vx + M(0, 1) * vy + M(0, 2) * vz + M(0, 3);
        const float Y = M(1, 0) * vx + M(1, 1) * vy + M(1, 2) * vz + M(1, 3);
        const float W = M(3, 0) * vx + M(3, 1) * vy + M(3, 2) * vz + M(3, 3);
        if (W < kNear) continue;
        const int tx = int((X / W * 0.5f + 0.5f) * w_), ty = int((0.5f - Y / W * 0.5f) * h_);
        if (tx < 0 || ty < 0 || tx >= w_ || ty >= h_) continue;
        const size_t o = size_t(ty) * w_ + tx;
        const float nd = kNear / W;
        d0[o] = written[o] ? std::min(d0[o], nd) : nd;
        written[o] = 1;
      }
  }
  buildPyramid();
  st.cull += std::chrono::duration<double, std::milli>(clk::now() - t0).count();
}

void OcclusionCuller::buildPyramid() {
  for (size_t l = 1; l < mips_.size(); ++l) {
    const std::vector<float>& s = mips_[l - 1];
    std::vector<float>& d = mips_[l];
    const int sw = mw_[l - 1], sh = mh_[l - 1], dw = mw_[l], dh = mh_[l];
    for (int y = 0; y < dh; ++y)
      for (int x = 0; x < dw; ++x) {
        float m = 1e30f;
        for (int yy = 2 * y; yy <= std::min(2 * y + 1 + (y == dh - 1 ? 1 : 0), sh - 1); ++yy)
          for (int xx = 2 * x; xx <= std::min(2 * x + 1 + (x == dw - 1 ? 1 : 0), sw - 1); ++xx)
            m = std::min(m, s[size_t(yy) * sw + xx]);
        d[size_t(y) * dw + x] = m;
      }
  }
}

bool OcclusionCuller::visible(Vec3 c, float r) const {
  const Mat4& M = viewProj_;
  const float X = M(0, 0) * c.x + M(0, 1) * c.y + M(0, 2) * c.z + M(0, 3);
  const float Y = M(1, 0) * c.x + M(1, 1) * c.y + M(1, 2) * c.z + M(1, 3);
  const float W = M(3, 0) * c.x + M(3, 1) * c.y + M(3, 2) * c.z + M(3, 3);
  const float nearW = W - r;
  if (nearW <= kNear * 2) return true;
  // Conservative screen radius: project with the nearest depth.
  const float sx = (X / W * 0.5f + 0.5f) * w_, sy = (0.5f - Y / W * 0.5f) * h_;
  const float rp = r * p11_ * 0.5f * h_ / nearW * 1.1f;  // pixels (aspect handled by p11 on y; x uses same scale)
  const float rpx = r * (M(0, 0) != 0 ? std::fabs(M(0, 0)) : p11_) * 0.5f * w_ / nearW * 1.1f;
  int x0 = int(std::floor(sx - rpx)), x1 = int(std::floor(sx + rpx));
  int y0 = int(std::floor(sy - rp)), y1 = int(std::floor(sy + rp));
  if (x1 < 0 || y1 < 0 || x0 >= w_ || y0 >= h_) return true;  // off-screen: frustum culling decides
  x0 = std::max(x0, 0); y0 = std::max(y0, 0); x1 = std::min(x1, w_ - 1); y1 = std::min(y1, h_ - 1);
  // Level where the rectangle spans at most 2 texels in each direction.
  int level = 0;
  while (level + 1 < int(mips_.size()) && ((x1 >> level) - (x0 >> level) > 1 || (y1 >> level) - (y0 >> level) > 1)) ++level;
  const std::vector<float>& m = mips_[level];
  const int lw = mw_[level];
  float dmin = 1e30f;
  for (int y = y0 >> level; y <= (y1 >> level); ++y)
    for (int x = x0 >> level; x <= (x1 >> level); ++x) dmin = std::min(dmin, m[size_t(std::min(y, mh_[level] - 1)) * lw + std::min(x, lw - 1)]);
  if (dmin <= 0.0f) return true;  // sky somewhere in the footprint
  const float farOccluderW = kNear / dmin;
  return nearW <= farOccluderW + kMargin;
}

}  // namespace jsnow
