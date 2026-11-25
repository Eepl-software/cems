// JSNOW - CPU-only 3D renderer benchmark.
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <thread>
#include <vector>

#include "engine.hpp"
#include "png.hpp"
#include "simd.hpp"

using namespace jsnow;

namespace {

double mse(const uint32_t* a, const uint32_t* b, size_t n) {
  double se = 0;
  for (size_t i = 0; i < n; ++i)
    for (int c = 0; c < 3; ++c) {
      const int d = int((a[i] >> (8 * c)) & 0xFF) - int((b[i] >> (8 * c)) & 0xFF);
      se += d * d;
    }
  return se / (3.0 * n);
}

struct Result {
  std::string name;
  double avgMs = 0, fps = 0, p99Ms = 0, psnrDb = 0, binned = 0, submitted = 0;
  StageTimes stages;
  int frames = 0;
};

Result runConfig(ThreadPool& pool, const Scene& scene, const Options& o, int frames, int pngFrame,
                 const std::string& pngPath, bool quality) {
  using clk = std::chrono::steady_clock;
  Result r;
  r.name = o.name();
  r.frames = frames;
  {  // Warm-up (page faults, thread spin-up); not timed.
    Engine warm(pool, scene, o);
    StageTimes st;
    for (int f = 0; f < 8; ++f) warm.renderFrame(f, st);
  }
  Engine e(pool, scene, o);
  std::vector<double> frameMs;
  frameMs.reserve(frames);
  for (int f = 0; f < frames; ++f) {
    auto a = clk::now();
    const uint32_t* img = e.renderFrame(f, r.stages);
    frameMs.push_back(std::chrono::duration<double, std::milli>(clk::now() - a).count());
    r.binned += double(e.binned()) / frames;
    r.submitted += double(e.submitted()) / frames;
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
    // Untimed second pass: compare every 5th frame to the full-quality renderer.
    Options ref;
    ref.outW = o.outW; ref.outH = o.outH; ref.shadows = o.shadows; ref.pointLights = o.pointLights; ref.transparency = o.transparency; ref.bloom = o.bloom;
    ref.exposure = o.exposure;
    Engine test(pool, scene, o), reference(pool, scene, ref);
    StageTimes dummy;
    double sum = 0;
    int count = 0;
    for (int f = 0; f < frames; ++f) {
      const uint32_t* img = test.renderFrame(f, dummy);
      const uint32_t* refImg = reference.renderFrame(f, dummy);  // every frame: keeps its caches in step
      if (f % 5 == 4) {
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
  std::printf("%-20s %7.1f FPS %7.2f ms/frame (p99 %6.2f)", r.name.c_str(), r.fps, r.avgMs, r.p99Ms);
  if (r.psnrDb > 0) std::printf("  PSNR %5.1f dB", r.psnrDb);
  std::printf("  [%.0f tris submitted, %.0f binned]\n", r.submitted, r.binned);
  std::printf("    ms/frame: cull %.2f | shadow %.2f | vertex %.2f | setup+bin %.2f | raster+shade %.2f | "
              "post %.2f | reproject %.2f | compose %.2f | upscale %.2f\n",
              r.stages.cull / n, r.stages.shadow / n, r.stages.vertex / n, r.stages.setup / n,
              r.stages.raster / n, r.stages.post / n, r.stages.reproject / n, r.stages.compose / n,
              r.stages.upscale / n);
}

void usage() {
  std::printf(
      "jsnow [options]\n"
      "  --half          render at half resolution and upscale\n"
      "  --checker       draw 1/4 of the pixels per frame (rotating 2x2 pattern)\n"
      "  --reuse         reuse earlier frames via per-pixel motion vectors\n"
      "  --all           all three tricks\n"
      "  --fast          half resolution + reuse (best speed/quality trade-off)\n"
      "  --no-shadows    disable the sun's cascaded shadow maps\n"
      "  --no-lights     disable the point lights\n"
      "  --no-transparency  skip the water and glass (alpha-blended) objects\n"
      "  --no-bloom      disable HDR bloom\n"
      "  --lights N      number of point lights (default 128, max 255)\n"
      "  --exposure E    tone-mapping exposure (default 1.6)\n"
      "  --scene S       large (default: 1M tris, 3 LODs) or small (100k, session 1)\n"
      "  --bench         run baseline, each trick, all tricks and fast; print a table\n"
      "  --bench-fast    benchmark baseline and --fast only\n"
      "  --quality       also measure PSNR against the full-quality renderer (untimed)\n"
      "  --frames N      frames per run (default 300)\n"
      "  --threads N     worker threads (default: hardware concurrency)\n"
      "  --size WxH      output resolution (default 1920x1080)\n"
      "  --tex N         texture size (default 2048)\n"
      "  --png PATH      save one frame as PNG (default jsnow.png; '' to disable)\n"
      "  --png-frame K   which frame to save (default 150)\n");
}

}  // namespace

int main(int argc, char** argv) {
  Options o;
  bool bench = false, benchFast = false, quality = false;
  int frames = 300, threads = int(std::thread::hardware_concurrency()), pngFrame = 150, texSize = 2048, lights = 128;
  SceneKind kind = SceneKind::Large;
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
    else if (a == "--fast") o.half = o.reuse = true;
    else if (a == "--no-shadows") o.shadows = false;
    else if (a == "--no-lights") o.pointLights = false;
    else if (a == "--no-transparency") o.transparency = false;
    else if (a == "--no-bloom") o.bloom = false;
    else if (a == "--exposure") o.exposure = float(std::atof(next().c_str()));
    else if (a == "--bench") bench = true;
    else if (a == "--bench-fast") bench = benchFast = true;
    else if (a == "--quality") quality = true;
    else if (a == "--frames") frames = std::max(1, std::atoi(next().c_str()));
    else if (a == "--threads") threads = std::max(1, std::atoi(next().c_str()));
    else if (a == "--lights") lights = std::max(0, std::min(255, std::atoi(next().c_str())));
    else if (a == "--tex") texSize = std::max(4, std::atoi(next().c_str()));
    else if (a == "--png") png = next();
    else if (a == "--png-frame") pngFrame = std::atoi(next().c_str());
    else if (a == "--scene") {
      std::string s = next();
      if (s == "small") kind = SceneKind::Small;
      else if (s == "large") kind = SceneKind::Large;
      else { usage(); return 1; }
    } else if (a == "--size") {
      std::string s = next();
      if (std::sscanf(s.c_str(), "%dx%d", &o.outW, &o.outH) != 2) { usage(); return 1; }
    } else { usage(); return a == "--help" || a == "-h" ? 0 : 1; }
  }
  if (o.outW % 4 || o.outH % 4) {
    std::printf("output size must be a multiple of 4\n");
    return 1;
  }
  ThreadPool pool(threads);
  auto t0 = std::chrono::steady_clock::now();
  Scene scene = buildScene(pool, kind, texSize, lights);
  const double buildMs = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
  std::printf("JSNOW: scene %s: %zu tris full detail (%zu in all LODs), %zu vertices, %zu textures %dx%d, "
              "%zu point lights, built in %.0f ms\n       %dx%d, %d threads, %s, %d frames, shadows %s\n",
              scene.description.c_str(), scene.fullDetailTriangles, scene.mesh.triangleCount(),
              scene.mesh.vertexCount(), size_t(scene.textures.layers), texSize, texSize, scene.lights.size(), buildMs, o.outW, o.outH,
              threads, simd::backendName(), frames, o.shadows ? "on" : "off");

  if (!bench) {
    printResult(runConfig(pool, scene, o, frames, pngFrame, png, quality));
    return 0;
  }
  // 0 baseline, 1 half, 2 checker, 3 reuse, 4 all, 5 fast (half+reuse)
  const std::vector<int> set = benchFast ? std::vector<int>{0, 5} : std::vector<int>{0, 1, 2, 3, 4, 5};
  std::vector<Result> results;
  for (int k : set) {
    Options c = o;
    c.half = k == 1 || k == 4 || k == 5;
    c.checker = k == 2 || k == 4;
    c.reuse = k == 3 || k == 4 || k == 5;
    std::string path = png.empty() ? "" : "jsnow_" + c.name() + ".png";
    std::replace(path.begin(), path.end(), '+', '_');
    results.push_back(runConfig(pool, scene, c, frames, pngFrame, path, quality));
    printResult(results.back());
  }
  std::printf("\n| config | FPS | ms/frame | speed-up |%s\n|---|---:|---:|---:|%s\n",
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
