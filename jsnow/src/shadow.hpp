#pragma once
#include <vector>

#include "engine.hpp"
#include "raster.hpp"

namespace jsnow {

// Sun shadows: 3 cascades, each a size x size depth map rendered from an
// orthographic light camera fitted to a bounding sphere of a slice of the view
// frustum (texel-snapped so the map does not shimmer while the camera moves).
// Lookup: per-lane cascade selection by view depth, 2x2 bilinear PCF,
// slope-scaled depth bias.
class ShadowMaps final : public ShadowLookup {
 public:
  static constexpr int kCascades = 3;
  ShadowMaps(ThreadPool& pool, const Scene& scene, int size = 1024);
  // Cascade c is re-rendered every kPeriod[c] calls (staggered), or earlier if
  // its cached map no longer covers the current frustum slice.
  void update(const Camera& cam, Vec3 sunDir, StageTimes& st);
  simd::vf sample(simd::vf wx, simd::vf wy, simd::vf wz, simd::vf viewW, simd::vf ndl) const override;
  const float* map(int c) const { return maps_.data() + size_t(c) * S_ * S_; }
  int size() const { return S_; }

 private:
  ThreadPool& pool_;
  const Scene& scene_;
  Rasterizer rast_;
  int S_;
  std::vector<float> maps_;
  std::vector<DrawItem> draws_;
  float splits_[kCascades] = {22.0f, 65.0f, 230.0f};
  float rows_[kCascades][12];  // light clip x, y, z rows (affine) per cascade
  float biasScale_[kCascades];  // depth units per shadow texel
  Vec3 cachedCenter_[kCascades];
  float cachedRadius_[kCascades] = {0, 0, 0};
  bool valid_[kCascades] = {false, false, false};
  int calls_ = 0;
 public:
  int rendersLastUpdate = 0;
};

}  // namespace jsnow
