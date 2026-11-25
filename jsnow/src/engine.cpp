#include "engine.hpp"

#include "shadow.hpp"

#include <chrono>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>

namespace jsnow {

namespace {
using clk = std::chrono::steady_clock;
double ms(clk::time_point a, clk::time_point b) { return std::chrono::duration<double, std::milli>(b - a).count(); }
}  // namespace

std::string Options::name() const {
  if (!half && !checker && !reuse) return "baseline";
  if (half && reuse && !checker) return "fast";
  std::string s;
  auto add = [&](const char* t) { s += s.empty() ? t : std::string("+") + t; };
  if (half) add("half");
  if (checker) add("checker");
  if (reuse) add("reuse");
  return s;
}

float lodPixelScale(const Camera& c) { return 1080.0f / (2.0f * std::tan(c.fovy * 0.5f)); }

Vec3 sunDirection() { return normalize(Vec3{0.62f, 0.42f, 0.32f}); }

// Deterministic fly-over: 60 Hz time steps.
Camera cameraAt(int frame, float aspect) {
  const float t = frame / 60.0f;
  const float th = 0.25f + 0.35f * t;
  const float R = 75.0f;
  Vec3 p{R * std::cos(th), 0.0f, R * std::sin(th)};
  p.y = terrainHeight(p.x, p.z) + 32.0f + 3.0f * std::sin(1.3f * t);
  Vec3 tangent{-std::sin(th), 0.0f, std::cos(th)};
  // Look across the terrain centre, slightly ahead of the direction of travel.
  Vec3 target = Vec3{0.0f, -4.0f, 0.0f} + tangent * 12.0f;
  Camera c;
  c.pos = p;
  c.aspect = aspect;
  c.view = lookAt(p, target, {0, 1, 0});
  c.proj = perspective(c.fovy, aspect, kNear);
  c.viewProj = c.proj * c.view;
  c.invView = rigidInverse(c.view);
  return c;
}

Engine::Engine(ThreadPool& pool, const Scene& scene, Options o)
    : pool_(pool), scene_(scene), o_(o), rast_(pool, scene) {
  W_ = o.half ? o.outW / 2 : o.outW;
  H_ = o.half ? o.outH / 2 : o.outH;
  const size_t n = size_t(W_) * H_;
  for (int i = 0; i < 2; ++i) { color_[i].assign(n, 0xFF000000u); depth_[i].assign(n, 0.0f); }
  for (auto& p : hdr_) p.resize(n);
  if (o.checker) {
    subColor_.resize(n / 4); subDepth_.resize(n / 4);
    for (auto& p : subHdr_) p.resize(n / 4);
  }
  if (o.half) out_.resize(size_t(o.outW) * o.outH);
  if (o.taa && !o.checker) raw_.resize(n);
  if (o.shadows) {
    shadows_ = std::make_unique<ShadowMaps>(pool, scene);
    shadows_->clusterCull = o.meshlets;
  }
}

Engine::~Engine() = default;

void Engine::renderScene(const Camera& cam, const Viewport& vp, int w, int h, std::vector<float>* hdr, float* depth,
                         uint32_t* ldr, StageTimes& st) {
  auto a = clk::now();
  cullStats_ = buildDrawList(scene_, cam.viewProj, cam.pos, lodPixelScale(cam), true, 0, draws_,
                             o_.transparency ? &transparentDraws_ : nullptr, nullptr, o_.meshlets);
  submitted_ = cullStats_.triangles;
  st.cull += ms(a, clk::now());
  if (shadows_) shadows_->update(cam, sunDirection(), st);
  PassParams pp;
  pp.viewProj = cam.viewProj;
  pp.view = cam.view;
  pp.vp = vp;
  pp.mode = PassMode::Shaded;
  pp.camPos = cam.pos;
  pp.sunDir = sunDirection();
  pp.shadow = shadows_.get();
  pp.pointLights = o_.pointLights;
  Target t;
  t.w = w; t.h = h;
  for (int c = 0; c < 3; ++c) t.hdr[c] = hdr[c].data();
  t.depth = depth;
  // Bloom level 0 at 1/4 of the output resolution for every internal resolution.
  const int bloomFactor = std::max(1, 4 * w / o_.outW);
  const bool fusedBloom = o_.bloom && w % bloomFactor == 0 && h % bloomFactor == 0;
  if (fusedBloom) {
    for (int c = 0; c < 3; ++c) t.bright[c] = bloom_.level0(c, w, h, bloomFactor);
    t.brightFactor = bloomFactor;
    t.brightThreshold = 1.0f;
  }
  rast_.render(pp, draws_, t, st, &transparentDraws_);
  a = clk::now();
  const float* planes[3] = {hdr[0].data(), hdr[1].data(), hdr[2].data()};
  if (o_.bloom) {
    if (fusedBloom) bloom_.runFromLevel0(pool_);
    else bloom_.run(pool_, w, h, planes, 1.0f, bloomFactor);
    if (std::getenv("JSNOW_BLOOM_DEBUG")) {
      static double acc = 0; static int n = 0;
      acc += ms(a, clk::now());
      if (++n % 50 == 0) std::fprintf(stderr, "bloom chain %.2f ms\n", acc / n);
    }
    tonemap(pool_, w, h, planes, o_.exposure, ldr, &bloom_, 0.35f);
  } else {
    tonemap(pool_, w, h, planes, o_.exposure, ldr);
  }
  st.post += ms(a, clk::now());
}

const uint32_t* Engine::renderFrame(int f, StageTimes& st) {
  const Camera cam = cameraAt(f, float(o_.outW) / float(o_.outH));
  const bool temporal = o_.checker || o_.reuse;
  const bool taa = o_.taa && !o_.checker;
  const int cur = ((o_.reuse || taa) && f > 0) ? (hist_ ^ 1) : hist_;
  const bool needDepth = o_.reuse || taa;
  auto renderFull = [&](int i) {
    if (!taa) {
      renderScene(cam, Viewport::full(W_, H_), W_, H_, hdr_, needDepth ? depth_[i].data() : nullptr, color_[i].data(), st);
      return;
    }
    // Sub-pixel jitter from the Halton(2,3) sequence, 8-frame cycle.
    auto halton = [](int i, int b) { float f = 1, r = 0; for (; i > 0; i /= b) { f /= b; r += f * (i % b); } return r; };
    const float jx = halton((f & 7) + 1, 2) - 0.5f, jy = halton((f & 7) + 1, 3) - 0.5f;
    Viewport vp = Viewport::full(W_, H_);
    vp.bx += jx;
    vp.by += jy;
    renderScene(cam, vp, W_, H_, hdr_, depth_[i].data(), raw_.data(), st);
    auto a = clk::now();
    if (f == 0) std::copy(raw_.begin(), raw_.end(), color_[i].begin());
    else taaResolve(pool_, W_, H_, raw_.data(), color_[hist_].data(), depth_[i].data(), cam.invView, prevCam_.viewProj,
                    cam.proj(0, 0), cam.proj(1, 1), kNear, jx, jy, color_[i].data());
    st.post += ms(a, clk::now());
  };
  auto reproject = [&](int from, int to) {
    auto a = clk::now();
    reproj_.run(pool_, W_, H_, color_[from].data(), depth_[from].data(), prevCam_.invView, cam.viewProj,
                cam.proj(0, 0), cam.proj(1, 1), kNear, color_[to].data(), depth_[to].data());
    st.reproject += ms(a, clk::now());
  };
  auto renderQuarter = [&](int into) {
    static const int kPattern[4][2] = {{0, 0}, {1, 1}, {1, 0}, {0, 1}};
    const int ox = kPattern[f & 3][0], oy = kPattern[f & 3][1];
    renderScene(cam, Viewport::interleaved(W_, H_, ox, oy), W_ / 2, H_ / 2, subHdr_,
                needDepth ? subDepth_.data() : nullptr, subColor_.data(), st);
    auto a = clk::now();
    if (o_.reuse)  // fresh samples + valid history; invalid history -> nearest fresh sample
      composeInterleaved(pool_, W_, H_, ox, oy, subColor_.data(), subDepth_.data(), reproj_.valid(),
                         color_[into].data(), depth_[into].data());
    else
      scatterInterleaved(pool_, W_, H_, ox, oy, subColor_.data(), nullptr, color_[into].data(), nullptr);
    st.compose += ms(a, clk::now());
  };

  if (!temporal || f == 0) {
    renderFull(cur);  // also bootstraps the history for temporal modes
  } else if (!o_.checker) {
    if (f % 2 == 0) renderFull(cur); else reproject(hist_, cur);
  } else if (!o_.reuse) {
    renderQuarter(cur);
  } else {
    reproject(hist_, cur);
    renderQuarter(cur);
  }
  hist_ = cur;
  prevCam_ = cam;

  const uint32_t* result = color_[cur].data();
  if (o_.half) {
    auto a = clk::now();
    upscale2x(pool_, W_, H_, result, out_.data());
    st.upscale += ms(a, clk::now());
    result = out_.data();
  }
  return result;
}

}  // namespace jsnow
