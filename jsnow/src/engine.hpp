#pragma once
#include <memory>
#include <string>
#include <vector>

#include "math.hpp"
#include "post.hpp"
#include "raster.hpp"
#include "scene.hpp"

namespace jsnow {

class Streamer;

struct Options {
  bool half = false;     // render at half resolution, upscale
  bool checker = false;  // 1/4 of the pixels per frame, rotating 2x2 pattern
  bool reuse = false;    // reproject earlier frames with motion vectors
  bool shadows = true;   // sun cascaded shadow maps
  bool pointLights = true;
  bool transparency = true;
  bool bloom = true;
  bool taa = true;  // temporal anti-aliasing (not combined with --checker)
  bool meshlets = true;  // per-meshlet frustum + normal-cone culling
  bool occlusion = true;  // hierarchical-Z occlusion culling (needs meshlets for per-cluster tests)
  bool occlusionPrepass = false;  // occluders rasterized each frame instead of last frame's depth
  Streamer* streamer = nullptr;   // LOD streaming (scene.lodProvider must point to it)
  float exposure = 1.6f;
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
class OcclusionCuller;

// Renders frames for one combination of tricks; owns all buffers and history.
class Engine {
 public:
  Engine(ThreadPool& pool, const Scene& scene, Options o);
  ~Engine();
  const uint32_t* renderFrame(int f, StageTimes& st);
  size_t binned() const { return rast_.lastBinnedTriangles(); }
  size_t submitted() const { return submitted_; }
  const CullStats& cullStats() const { return cullStats_; }

 private:
  // Renders HDR into hdr (w x h) + depth, then tone maps into ldr.
  void renderScene(const Camera& cam, const Viewport& vp, int w, int h, std::vector<float>* hdr, float* depth,
                   uint32_t* ldr, StageTimes& st);

  ThreadPool& pool_;
  const Scene& scene_;
  Options o_;
  Rasterizer rast_;
  std::unique_ptr<ShadowMaps> shadows_;
  std::unique_ptr<OcclusionCuller> occlusion_;
  Reprojector reproj_;
  Bloom bloom_;
  int W_, H_;
  std::vector<uint32_t> color_[2];
  std::vector<float> depth_[2];
  std::vector<float> hdr_[3], subHdr_[3];  // linear HDR of the full / quarter target
  std::vector<uint32_t> subColor_;
  std::vector<uint32_t> raw_;  // tone-mapped frame before the TAA resolve
  std::vector<float> subDepth_;
  std::vector<uint32_t> out_;
  std::vector<DrawItem> draws_, transparentDraws_;
  int hist_ = 0;
  size_t submitted_ = 0;
  CullStats cullStats_;
  const float* occlusionDepth_ = nullptr;
  int occlusionW_ = 0, occlusionH_ = 0;
  bool occlusionReady_ = false;
  Camera prevCam_;
};

}  // namespace jsnow
