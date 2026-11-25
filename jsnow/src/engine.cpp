#include "engine.hpp"

#include <chrono>
#include <cmath>

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

Vec3 sunDirection() { return normalize(Vec3{0.45f, 0.75f, 0.3f}); }

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
  for (int i = 0; i < 2; ++i) { color_[i].assign(n, kSkyColor); depth_[i].assign(n, 0.0f); }
  if (o.checker) { subColor_.resize(n / 4); subDepth_.resize(n / 4); }
  if (o.half) out_.resize(size_t(o.outW) * o.outH);
}

class ShadowMaps {};  // implemented in A3
Engine::~Engine() = default;

void Engine::renderScene(const Camera& cam, const Viewport& vp, const Target& t, StageTimes& st) {
  auto a = clk::now();
  submitted_ = buildDrawList(scene_, cam.viewProj, cam.pos, true, 0, draws_).triangles;
  st.cull += ms(a, clk::now());
  PassParams pp;
  pp.viewProj = cam.viewProj;
  pp.vp = vp;
  pp.mode = PassMode::Shaded;
  pp.camPos = cam.pos;
  pp.sunDir = sunDirection();
  pp.shadow = nullptr;
  rast_.render(pp, draws_, t, st);
}

const uint32_t* Engine::renderFrame(int f, StageTimes& st) {
  const Camera cam = cameraAt(f, float(o_.outW) / float(o_.outH));
  const bool temporal = o_.checker || o_.reuse;
  const int cur = (o_.reuse && f > 0) ? (hist_ ^ 1) : hist_;
  const bool needDepth = o_.reuse;
  auto renderFull = [&](int i) {
    Target t{W_, H_, color_[i].data(), needDepth ? depth_[i].data() : nullptr};
    renderScene(cam, Viewport::full(W_, H_), t, st);
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
    Target t{W_ / 2, H_ / 2, subColor_.data(), needDepth ? subDepth_.data() : nullptr};
    renderScene(cam, Viewport::interleaved(W_, H_, ox, oy), t, st);
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
