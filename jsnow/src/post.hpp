#pragma once
#include <cstdint>
#include <vector>

#include "math.hpp"
#include "threadpool.hpp"

namespace jsnow {

// Trick 3: reuse the previous frame. Each previous-frame pixel q has a motion
// vector mv(q) (prev -> current screen position) given by its depth and the two
// camera matrices (the scene is static, so camera motion is the only motion).
// The current frame is rebuilt by a gather: every output pixel p solves
// q + mv(q) = p by fixed-point iteration, evaluating mv on the fly from the
// previous depth buffer (one pass, AVX2 gathers, no motion-vector buffer
// round trip through memory). Pixels whose solution does not land within one
// pixel of p (disocclusions, off-screen sources) are flagged invalid.
class Reprojector {
 public:
  void run(ThreadPool& pool, int w, int h, const uint32_t* prevColor, const float* prevDepth,
           const Mat4& prevInvView, const Mat4& curViewProj, float p00, float p11, float depthScale,
           uint32_t* outColor, float* outDepth);
  // 1 where the history sample passed the motion-vector consistency check.
  const uint8_t* valid() const { return valid_.data(); }

 private:
  std::vector<uint8_t> valid_;
};

// Tricks 2+3 together: like scatterInterleaved, and additionally replaces
// history pixels flagged invalid by the nearest freshly rendered sample.
void composeInterleaved(ThreadPool& pool, int w, int h, int ox, int oy, const uint32_t* subColor,
                        const float* subDepth, const uint8_t* valid, uint32_t* color, float* depth);

// Trick 2: write a half-size image into phase (ox, oy) of the 2x2 pattern.
void scatterInterleaved(ThreadPool& pool, int w, int h, int ox, int oy, const uint32_t* subColor,
                        const float* subDepth, uint32_t* color, float* depth);

// HDR bloom: bright-pass + 4x4 downsample to quarter resolution, a chain of
// half-size levels each blurred with a separable 5-tap Gaussian, then
// upsampled and accumulated back into level 0 (quarter resolution).
class Bloom {
 public:
  static constexpr int kLevels = 5;
  // factor: first downsample (power of two); choose it so level 0 is 1/4 of
  // the *output* resolution whatever the internal resolution is.
  void run(ThreadPool& pool, int w, int h, const float* const hdr[3], float threshold, int factor = 4);
  int factor() const { return factor_; }
  // Fused path: allocate level 0 for (w, h, factor) and return its planes so
  // the rasterizer can fill it per tile; then call runFromLevel0().
  float* level0(int c, int w, int h, int factor);
  void runFromLevel0(ThreadPool& pool);
  const float* plane(int c) const { return lv_[0].p[c].data(); }
  int width() const { return lv_[0].w; }
  int height() const { return lv_[0].h; }

 private:
  struct Level {
    int w = 0, h = 0;
    std::vector<float> p[3], tmp[3];
  };
  void allocate(int w, int h, int factor);
  Level lv_[kLevels];
  int factor_ = 4;
};

// HDR -> display: optional bloom (bilinear upsample of the low-res bloom,
// scaled by bloomStrength), exposure, ACES filmic curve (Narkowicz fit), gamma-2 encode.
void tonemap(ThreadPool& pool, int w, int h, const float* const hdr[3], float exposure, uint32_t* out,
             const Bloom* bloom = nullptr, float bloomStrength = 0.0f);

// Temporal anti-aliasing resolve (w x h, RGBA8). Each pixel is unprojected
// with its depth (stored as depthScale / w) and the current camera, reprojected
// into the previous frame (history = previous displayed image), sampled
// bilinearly, clamped to the 3x3 neighbourhood of the current frame and blended
// 1/8 current + 7/8 history. (jx, jy) is this frame's sub-pixel jitter.
void taaResolve(ThreadPool& pool, int w, int h, const uint32_t* cur, const uint32_t* hist, const float* depth,
                const Mat4& curInvView, const Mat4& prevViewProj, float p00, float p11, float depthScale,
                float jx, float jy, uint32_t* out);

// Trick 1: 2x bilinear upscale, w x h -> 2w x 2h.
void upscale2x(ThreadPool& pool, int w, int h, const uint32_t* src, uint32_t* dst);

}  // namespace jsnow
