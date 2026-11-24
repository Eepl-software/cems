// JSNOW - CPU-only 3D renderer benchmark.
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <string>
#include <thread>
#include <vector>

#include "png.hpp"
#include "post.hpp"
#include "raster.hpp"
#include "scene.hpp"

using namespace jsnow;

namespace {

struct Options {
  bool half = false;     // trick 1: render at half resolution, upscale
  bool checker = false;  // trick 2: 1/4 of the pixels per frame, rotating 2x2 pattern
  bool reuse = false;    // trick 3: reproject earlier frames with motion vectors
  int outW = 1920, outH = 1080;
  std::string name() const {
    if (!half && !checker && !reuse) return "baseline";
    std::string s;
    auto add = [&](const char* t) { s += s.empty() ? t : std::string("+") + t; };
    if (half) add("half");
    if (checker) add("checker");
    if (reuse) add("reuse");
    return s;
  }
};

struct Camera {
  Mat4 view, proj, viewProj, invView;
  Vec3 pos;
};

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
  c.view = lookAt(p, target, {0, 1, 0});
  c.proj = perspective(60.0f * 3.14159265f / 180.0f, aspect, kNear);
  c.viewProj = c.proj * c.view;
  c.invView = rigidInverse(c.view);
  return c;
}

// Renders frames for one combination of tricks; owns all buffers and history.
class Engine {
 public:
  Engine(ThreadPool& pool, const Mesh& mesh, Options o)
      : pool_(pool), o_(o), rast_(pool, mesh) {
    W_ = o.half ? o.outW / 2 : o.outW;
    H_ = o.half ? o.outH / 2 : o.outH;
    const size_t n = size_t(W_) * H_;
    for (int i = 0; i < 2; ++i) { color_[i].assign(n, kSkyColor); depth_[i].assign(n, 0.0f); }
    if (o.checker) { subColor_.resize(n / 4); subDepth_.resize(n / 4); }
    if (o.half) out_.resize(size_t(o.outW) * o.outH);
  }

  const uint32_t* renderFrame(int f, StageTimes& st) {
    using clk = std::chrono::steady_clock;
    auto ms = [](clk::time_point a, clk::time_point b) {
      return std::chrono::duration<double, std::milli>(b - a).count();
    };
    const Camera cam = cameraAt(f, float(o_.outW) / float(o_.outH));
    FrameParams fp;
    fp.viewProj = cam.viewProj;
    fp.camPos = cam.pos;
    fp.lightDir = normalize(Vec3{0.45f, 0.75f, 0.3f});
    fp.vp = Viewport::full(W_, H_);

    const bool temporal = o_.checker || o_.reuse;
    const int cur = (o_.reuse && f > 0) ? (hist_ ^ 1) : hist_;
    const bool needDepth = o_.reuse;
    auto renderFull = [&](int i) {
      Target t{W_, H_, color_[i].data(), needDepth ? depth_[i].data() : nullptr};
      rast_.render(fp, t, st);
    };
    auto reproject = [&](int from, int to) {
      auto a = clk::now();
      reproj_.run(pool_, W_, H_, color_[from].data(), depth_[from].data(), prevCam_.invView,
                  cam.viewProj, cam.proj(0, 0), cam.proj(1, 1), color_[to].data(), depth_[to].data());
      st.reproject += ms(a, clk::now());
    };
    auto renderQuarter = [&](int into) {
      static const int kPattern[4][2] = {{0, 0}, {1, 1}, {1, 0}, {0, 1}};
      const int ox = kPattern[f & 3][0], oy = kPattern[f & 3][1];
      fp.vp = Viewport::interleaved(W_, H_, ox, oy);
      Target t{W_ / 2, H_ / 2, subColor_.data(), needDepth ? subDepth_.data() : nullptr};
      rast_.render(fp, t, st);
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
      // Reuse only: full render every other frame, reprojection in between.
      if (f % 2 == 0) renderFull(cur); else reproject(hist_, cur);
    } else if (!o_.reuse) {
      renderQuarter(cur);  // stale pixels stay where they were
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
  size_t binned() const { return rast_.lastBinnedTriangles(); }
  int internalW() const { return W_; }
  int internalH() const { return H_; }

 private:
  ThreadPool& pool_;
  Options o_;
  Rasterizer rast_;
  Reprojector reproj_;
  int W_, H_;
  std::vector<uint32_t> color_[2];
  std::vector<float> depth_[2];
  std::vector<uint32_t> subColor_;
  std::vector<float> subDepth_;
  std::vector<uint32_t> out_;
  int hist_ = 0;
  Camera prevCam_;
};

double mse(const uint32_t* a, const uint32_t* b, size_t n) {
  double se = 0;
  for (size_t i = 0; i < n; ++i)
    for (int c = 0; c < 3; ++c) {
      int d = int((a[i] >> (8 * c)) & 0xFF) - int((b[i] >> (8 * c)) & 0xFF);
      se += d * d;
    }
  return se / (3.0 * n);
}

struct Result {
  std::string name;
  double avgMs = 0, fps = 0, p99Ms = 0, psnrDb = 0, binned = 0;
  StageTimes stages;
  int frames = 0;
};

Result runConfig(ThreadPool& pool, const Mesh& mesh, const Options& o, int frames, int pngFrame,
                 const std::string& pngPath, bool quality) {
  using clk = std::chrono::steady_clock;
  Result r;
  r.name = o.name();
  r.frames = frames;
  {  // Warm-up (page faults, thread spin-up); not timed.
    Engine warm(pool, mesh, o);
    StageTimes st;
    for (int f = 0; f < 8; ++f) warm.renderFrame(f, st);
  }
  Engine e(pool, mesh, o);
  std::vector<double> frameMs;
  frameMs.reserve(frames);
  for (int f = 0; f < frames; ++f) {
    auto a = clk::now();
    const uint32_t* img = e.renderFrame(f, r.stages);
    r.binned += double(e.binned()) / frames;
    frameMs.push_back(std::chrono::duration<double, std::milli>(clk::now() - a).count());
    if (f == pngFrame && !pngPath.empty()) {
      if (writePNG(pngPath, o.outW, o.outH, img)) std::printf("  saved frame %d -> %s\n", f, pngPath.c_str());
      else std::printf("  failed to write %s\n", pngPath.c_str());
    }
  }
  double total = 0;
  for (double m : frameMs) total += m;
  r.avgMs = total / frames;
  r.fps = 1000.0 / r.avgMs;
  std::vector<double> sorted = frameMs;
  std::sort(sorted.begin(), sorted.end());
  r.p99Ms = sorted[std::min(sorted.size() - 1, size_t(sorted.size() * 0.99))];

  if (quality) {
    // Untimed second pass: compare every 5th frame to a full-resolution reference.
    Options ref;
    ref.outW = o.outW; ref.outH = o.outH;
    Engine test(pool, mesh, o), reference(pool, mesh, ref);
    StageTimes dummy;
    double sum = 0;
    int count = 0;
    for (int f = 0; f < frames; ++f) {
      const uint32_t* img = test.renderFrame(f, dummy);
      if (f % 5 == 4) {
        const uint32_t* refImg = reference.renderFrame(f, dummy);
        sum += mse(img, refImg, size_t(o.outW) * o.outH);
        ++count;
      }
    }
    const double m = count ? sum / count : 0;  // PSNR of the mean squared error
    r.psnrDb = m <= 0 ? 99.0 : 10.0 * std::log10(255.0 * 255.0 / m);
  }
  return r;
}

void printResult(const Result& r) {
  const double n = r.frames;
  std::printf("%-22s %8.1f FPS %8.2f ms/frame (p99 %6.2f)", r.name.c_str(), r.fps, r.avgMs, r.p99Ms);
  if (r.psnrDb > 0) std::printf("  PSNR %5.1f dB", r.psnrDb);
  std::printf("  [%.0f tris binned/raster pass]", r.binned);
  std::printf("\n    stages ms/frame: vertex %.2f | setup+bin %.2f | raster %.2f | reproject %.2f | "
              "scatter %.2f | upscale %.2f\n",
              r.stages.vertex / n, r.stages.setup / n, r.stages.raster / n, r.stages.reproject / n,
              r.stages.compose / n, r.stages.upscale / n);
}

void usage() {
  std::printf(
      "jsnow [options]\n"
      "  --half          trick 1: render at half resolution and upscale\n"
      "  --checker       trick 2: draw 1/4 of the pixels per frame (rotating 2x2 pattern)\n"
      "  --reuse         trick 3: reuse earlier frames via per-pixel motion vectors\n"
      "  --all           all three tricks\n"
      "  --bench         run baseline, each trick, and all tricks; print a table\n"
      "  --quality       also measure PSNR against the full-quality renderer (untimed)\n"
      "  --frames N      frames per run (default 300)\n"
      "  --threads N     worker threads (default: hardware concurrency)\n"
      "  --size WxH      output resolution (default 1920x1080)\n"
      "  --png PATH      save one frame as PNG (default jsnow.png; '' to disable)\n"
      "  --png-frame K   which frame to save (default 150)\n");
}

}  // namespace

int main(int argc, char** argv) {
  Options o;
  bool bench = false, quality = false;
  int frames = 300, threads = int(std::thread::hardware_concurrency()), pngFrame = 150;
  std::string png = "jsnow.png";
  for (int i = 1; i < argc; ++i) {
    std::string a = argv[i];
    auto next = [&]() -> std::string {
      if (i + 1 >= argc) { usage(); std::exit(1); }
      return argv[++i];
    };
    if (a == "--half") o.half = true;
    else if (a == "--checker") o.checker = true;
    else if (a == "--reuse") o.reuse = true;
    else if (a == "--all") o.half = o.checker = o.reuse = true;
    else if (a == "--bench") bench = true;
    else if (a == "--quality") quality = true;
    else if (a == "--frames") frames = std::max(1, std::atoi(next().c_str()));
    else if (a == "--threads") threads = std::max(1, std::atoi(next().c_str()));
    else if (a == "--png") png = next();
    else if (a == "--png-frame") pngFrame = std::atoi(next().c_str());
    else if (a == "--size") {
      std::string s = next();
      if (std::sscanf(s.c_str(), "%dx%d", &o.outW, &o.outH) != 2) { usage(); return 1; }
    } else { usage(); return a == "--help" || a == "-h" ? 0 : 1; }
  }
  if (o.outW % 4 || o.outH % 4) {
    std::printf("output size must be a multiple of 4\n");
    return 1;
  }
#if defined(__AVX2__)
  const char* isa = "AVX2+FMA";
#else
  const char* isa = "scalar";
#endif
  Mesh mesh = buildScene();
  std::printf("JSNOW: %zu triangles, %zu vertices, %dx%d, %d threads, %s, %d frames\n",
              mesh.triangleCount(), mesh.vertexCount(), o.outW, o.outH, threads, isa, frames);
  ThreadPool pool(threads);

  if (!bench) {
    Result r = runConfig(pool, mesh, o, frames, pngFrame, png, quality);
    printResult(r);
    return 0;
  }
  std::vector<Options> configs;
  for (int k = 0; k < 5; ++k) {
    Options c;
    c.outW = o.outW; c.outH = o.outH;
    c.half = k == 1 || k == 4;
    c.checker = k == 2 || k == 4;
    c.reuse = k == 3 || k == 4;
    configs.push_back(c);
  }
  std::vector<Result> results;
  for (const Options& c : configs) {
    std::string path = png.empty() ? "" : "jsnow_" + c.name() + ".png";
    std::replace(path.begin(), path.end(), '+', '_');
    results.push_back(runConfig(pool, mesh, c, frames, pngFrame, path, quality));
    printResult(results.back());
  }
  std::printf("\n| trick | FPS | ms/frame | speed-up |%s\n|---|---:|---:|---:|%s\n",
              quality ? " PSNR vs baseline |" : "", quality ? "---:|" : "");
  for (const Result& r : results) {
    std::printf("| %s | %.1f | %.2f | %.2fx |", r.name.c_str(), r.fps, r.avgMs, results[0].avgMs / r.avgMs);
    if (quality) {
      if (r.name == "baseline") std::printf(" ref |");
      else std::printf(" %.1f dB |", r.psnrDb);
    }
    std::printf("\n");
  }
  return 0;
}
