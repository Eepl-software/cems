#pragma once
#include <vector>

#include "engine.hpp"
#include "raster.hpp"

namespace jsnow {

// Hierarchical-Z occlusion culling. Each frame the occluders (terrain chunks,
// towers) are drawn at their coarsest LOD into a small depth buffer
// (depth-only raster), reduced into a min-depth (= farthest) mip pyramid, and
// object / meshlet bounding spheres are tested against it.
class OcclusionCuller {
 public:
  OcclusionCuller(ThreadPool& pool, const Scene& scene, int w = 480, int h = 272);
  // Occluder pre-pass: coarsest-LOD occluders rasterized into the small buffer.
  void build(const Camera& cam, StageTimes& st);
  // Previous-frame depth (stored as near/w, dw x dh) reduced with min over
  // blocks to the small buffer, re-projected into the current camera (holes =
  // no occluder, so the test stays conservative). No extra raster pass.
  void buildFromDepth(const float* depth, int dw, int dh, const Camera& prev, const Camera& cur, StageTimes& st);
  // True if the sphere may be visible (conservative).
  bool visible(Vec3 c, float r) const;
  size_t occluderTriangles() const { return occluderTris_; }

 private:
  ThreadPool& pool_;
  const Scene& scene_;
  Rasterizer rast_;
  int w_, h_;
  std::vector<std::vector<float>> mips_;  // reversed depth (near / w), min over each texel footprint
  std::vector<int> mw_, mh_;
  std::vector<DrawItem> draws_;
  Mat4 viewProj_;
  float p11_ = 1;
  size_t occluderTris_ = 0;
  std::vector<float> small_;
  void buildPyramid();
};

}  // namespace jsnow
