#include "shadow.hpp"

#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>

namespace jsnow {

using namespace simd;

namespace {
// Casters use coarser LODs than the camera (shadow texels are larger than pixels).
int shadowLodBias(int cascade) {
  static const int base = [] { const char* e = std::getenv("JSNOW_SHADOW_LOD"); return e ? std::atoi(e) : 1; }();
  return cascade == 0 ? base : base + 1;
}
}  // namespace

ShadowMaps::ShadowMaps(ThreadPool& pool, const Scene& scene, int size)
    : pool_(pool), scene_(scene), rast_(pool, scene), S_(size), maps_(size_t(kCascades) * size * size, 0.0f) {}

void ShadowMaps::update(const Camera& cam, Vec3 L, StageTimes& st) {
  using clk = std::chrono::steady_clock;
  auto t0 = clk::now();
  StageTimes inner;
  rendersLastUpdate = 0;
  const float th = std::tan(cam.fovy * 0.5f);
  // Light basis.
  const Vec3 fwd = L * -1.0f;
  const Vec3 right = normalize(cross(fwd, Vec3{0, 0, 1}));
  const Vec3 up = cross(right, fwd);
  float nearD = kNear;
  for (int c = 0; c < kCascades; ++c) {
    const float farD = splits_[c];
    // Bounding sphere of the frustum slice [nearD, farD].
    Vec3 corners[8];
    int k = 0;
    for (float z : {nearD, farD})
      for (int sy = -1; sy <= 1; sy += 2)
        for (int sx = -1; sx <= 1; sx += 2) {
          const Vec3 pv{sx * z * th * cam.aspect, sy * z * th, -z};
          const Mat4& I = cam.invView;
          corners[k++] = {I(0, 0) * pv.x + I(0, 1) * pv.y + I(0, 2) * pv.z + I(0, 3),
                          I(1, 0) * pv.x + I(1, 1) * pv.y + I(1, 2) * pv.z + I(1, 3),
                          I(2, 0) * pv.x + I(2, 1) * pv.y + I(2, 2) * pv.z + I(2, 3)};
        }
    Vec3 center{0, 0, 0};
    for (const Vec3& p : corners) center = center + p * 0.125f;
    float r = 0;
    for (const Vec3& p : corners) r = std::max(r, std::sqrt(dot(p - center, p - center)));
    r = std::ceil(r);  // stable size -> stable texel footprint
    static constexpr int kPeriod[kCascades] = {1, 2, 4};
    static constexpr int kPhase[kCascades] = {0, 1, 2};
    static constexpr float kMargin[kCascades] = {1.0f, 1.15f, 1.15f};
    static const bool noCache = std::getenv("JSNOW_SHADOW_NOCACHE") != nullptr;
    if (!noCache && valid_[c] && (calls_ % kPeriod[c]) != kPhase[c] % kPeriod[c]) {
      // Keep the cached map if it still contains this slice's bounding sphere
      // (measured in the light's image plane).
      const Vec3 d = center - cachedCenter_[c];
      const float dr = dot(d, right), du = dot(d, up);
      if (std::sqrt(dr * dr + du * du) + r <= cachedRadius_[c]) {
        nearD = farD * 0.9f;
        continue;
      }
    }
    r *= kMargin[c];
    r = std::ceil(r);
    ++rendersLastUpdate;
    const float texel = 2 * r / S_;
    // Snap the centre to the texel grid in light space.
    const float cr = dot(center, right), cu = dot(center, up);
    center = center + right * (std::floor(cr / texel) * texel - cr) + up * (std::floor(cu / texel) * texel - cu);
    cachedCenter_[c] = center;
    cachedRadius_[c] = r;
    valid_[c] = true;
    const float D = r + 150.0f, farZ = D + r + 60.0f;
    const Vec3 eye = center + L * D;
    const Mat4 view = lookAt(eye, center, right);  // any up not parallel to L
    Mat4 proj;
    for (float& v : proj.m) v = 0;
    proj(0, 0) = 1.0f / r;
    proj(1, 1) = 1.0f / r;
    proj(2, 2) = 1.0f / farZ;  // reversed depth: z = 1 + zview/far (1 at the eye)
    proj(2, 3) = 1.0f;
    proj(3, 3) = 1.0f;
    const Mat4 vp = proj * view;
    for (int i = 0; i < 3; ++i)
      for (int j = 0; j < 4; ++j) rows_[c][i * 4 + j] = vp(i, j);
    biasScale_[c] = texel / farZ;

    auto a = clk::now();
    buildDrawList(scene_, vp, cam.pos, lodPixelScale(cam), false, shadowLodBias(c), draws_, nullptr, &fwd, clusterCull);
    inner.cull += std::chrono::duration<double, std::milli>(clk::now() - a).count();
    PassParams pp;
    pp.viewProj = vp;
    pp.vp = Viewport::full(S_, S_);
    pp.mode = PassMode::DepthOnly;
    Target t;
    t.w = S_; t.h = S_;
    t.depth = maps_.data() + size_t(c) * S_ * S_;
    rast_.render(pp, draws_, t, inner);
    nearD = farD * 0.9f;  // overlap a little
  }
  ++calls_;
  st.shadow += std::chrono::duration<double, std::milli>(clk::now() - t0).count();
  if (std::getenv("JSNOW_SHADOW_DEBUG")) {
    static StageTimes acc;
    static int n = 0;
    acc += inner;
    if (++n % 100 == 0)
      std::fprintf(stderr, "shadow inner ms/frame: cull %.2f vertex %.2f setup %.2f raster %.2f (binned last %zu)\n",
                   acc.cull / n, acc.vertex / n, acc.setup / n, acc.raster / n, rast_.lastBinnedTriangles());
  }
}

vf ShadowMaps::sample(vf wx, vf wy, vf wz, vf viewW, vf ndl) const {
  // Cascade per lane.
  const vm in1 = viewW > set1(splits_[0] * 0.9f), in2 = viewW > set1(splits_[1] * 0.9f);
  const vm beyond = viewW > set1(splits_[2]);
  auto pick = [&](int i) {
    return select(in2, set1(rows_[2][i]), select(in1, set1(rows_[1][i]), set1(rows_[0][i])));
  };
  const vf lx = fma(pick(0), wx, fma(pick(1), wy, fma(pick(2), wz, pick(3))));
  const vf ly = fma(pick(4), wx, fma(pick(5), wy, fma(pick(6), wz, pick(7))));
  const vf lz = fma(pick(8), wx, fma(pick(9), wy, fma(pick(10), wz, pick(11))));
  const vf bscale = select(in2, set1(biasScale_[2]), select(in1, set1(biasScale_[1]), set1(biasScale_[0])));
  // Slope-scaled bias: 1.5 texels + tan(theta), capped.
  const vf nd = max(ndl, set1(0.15f));
  const vf tanT = sqrt(max(set1(1.0f) - nd * nd, zerof())) * rcp_fast(nd);
  const vf bias = bscale * (set1(1.5f) + min(tanT * set1(1.5f), set1(6.0f)));
  const vf ref = lz + bias;
  const float S = float(S_);
  const vf tx = fma(lx, set1(0.5f * S), set1(0.5f * S - 0.5f));
  const vf ty = fma(ly, set1(-0.5f * S), set1(0.5f * S - 0.5f));
  const vf fx = floor(tx), fy = floor(ty);
  const vf ax = tx - fx, ay = ty - fy;
  const vi maxI = set1i(S_ - 1), zero = set1i(0);
  const vi ix0 = mini(maxi(trunc_i(fx), zero), maxI), iy0 = mini(maxi(trunc_i(fy), zero), maxI);
  const vi ix1 = mini(ix0 + set1i(1), maxI), iy1 = mini(iy0 + set1i(1), maxI);
  const vi base = selecti(in2, set1i(2 * S_ * S_), selecti(in1, set1i(S_ * S_), zero));
  const vi r0 = base + iy0 * set1i(S_), r1 = base + iy1 * set1i(S_);
  const float* m = maps_.data();
  const vf one = set1(1.0f);
  auto lit = [&](vi idx) { return maskf(ref >= gatherf(m, idx), one); };
  const vf s00 = lit(r0 + ix0), s10 = lit(r0 + ix1), s01 = lit(r1 + ix0), s11 = lit(r1 + ix1);
  const vf top = fma(ax, s10 - s00, s00), bot = fma(ax, s11 - s01, s01);
  const vf v = fma(ay, bot - top, top);
  return select(beyond, one, v);
}

}  // namespace jsnow
