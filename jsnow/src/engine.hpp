#pragma once
#include <memory>
#include <string>
#include <vector>

#include "math.hpp"
#include "post.hpp"
#include "raster.hpp"
#include "scene.hpp"

namespace jsnow {

struct Options {
  bool half = false;     // render at half resolution, upscale
  bool checker = false;  // 1/4 of the pixels per frame, rotating 2x2 pattern
  bool reuse = false;    // reproject earlier frames with motion vectors
  bool shadows = true;   // sun cascaded shadow maps
  int outW = 1920, outH = 1080;
  std::string name() const;
};

struct Camera {
  Mat4 view, proj, viewProj, invView;
  Vec3 pos;
  float fovy = 1.0471976f, aspect = 16.0f / 9.0f;
};
Camera cameraAt(int frame, float aspect);
Vec3 sunDirection();
float lodPixelScale(const Camera& c);

class ShadowMaps;

// Renders frames for one combination of tricks; owns all buffers and history.
class Engine {
 public:
  Engine(ThreadPool& pool, const Scene& scene, Options o);
  ~Engine();
  const uint32_t* renderFrame(int f, StageTimes& st);
  size_t binned() const { return rast_.lastBinnedTriangles(); }
  size_t submitted() const { return submitted_; }

 private:
  void renderScene(const Camera& cam, const Viewport& vp, const Target& t, StageTimes& st);

  ThreadPool& pool_;
  const Scene& scene_;
  Options o_;
  Rasterizer rast_;
  std::unique_ptr<ShadowMaps> shadows_;
  Reprojector reproj_;
  int W_, H_;
  std::vector<uint32_t> color_[2];
  std::vector<float> depth_[2];
  std::vector<uint32_t> subColor_;
  std::vector<float> subDepth_;
  std::vector<uint32_t> out_;
  std::vector<DrawItem> draws_;
  int hist_ = 0;
  size_t submitted_ = 0;
  Camera prevCam_;
};

}  // namespace jsnow
