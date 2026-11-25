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

// Trick 1: 2x bilinear upscale, w x h -> 2w x 2h.
void upscale2x(ThreadPool& pool, int w, int h, const uint32_t* src, uint32_t* dst);

}  // namespace jsnow
