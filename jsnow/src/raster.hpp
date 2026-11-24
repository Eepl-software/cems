#pragma once
#include <cstdint>
#include <vector>

#include "math.hpp"
#include "scene.hpp"
#include "threadpool.hpp"

namespace jsnow {

constexpr int kTile = 64;
constexpr float kNear = 0.1f;      // near plane distance (must match the projection)
constexpr float kGuardBand = 4.0f;  // clip-space guard band, in multiples of the viewport

// Maps NDC to target pixel coordinates: px = ndcX*ax + bx, py = ndcY*ay + by.
// A plain full-frame viewport is {W/2, W/2, -H/2, H/2}; the 2x2 interleaved
// mode uses a half-size target whose pixel centres land on one phase of the
// full-resolution grid.
struct Viewport {
  float ax, bx, ay, by;
  static Viewport full(int w, int h) { return {w * 0.5f, w * 0.5f, -h * 0.5f, h * 0.5f}; }
  // Half-size target sampling full-grid pixels (2i+ox, 2j+oy) of a w x h image.
  static Viewport interleaved(int w, int h, int ox, int oy) {
    return {w * 0.25f, (w * 0.5f - ox + 0.5f) * 0.5f, -h * 0.25f, (h * 0.5f - oy + 0.5f) * 0.5f};
  }
};

struct FrameParams {
  Mat4 viewProj;
  Vec3 camPos;
  Vec3 lightDir;  // unit vector towards the light
  Viewport vp;
};

struct Target {
  int w = 0, h = 0;
  uint32_t* color = nullptr;  // RGBA8, w*h
  float* depth = nullptr;     // 1/w (0 = sky), w*h; may be null
};

struct StageTimes {
  double vertex = 0, setup = 0, raster = 0, reproject = 0, compose = 0, upscale = 0;
  StageTimes& operator+=(const StageTimes& o) {
    vertex += o.vertex; setup += o.setup; raster += o.raster;
    reproject += o.reproject; compose += o.compose; upscale += o.upscale;
    return *this;
  }
};

constexpr uint32_t kSkyColor = 0xFFE0B080u;  // ABGR in memory order RGBA -> (128,176,224)

// Per-triangle setup result consumed by the tile rasterizer.
struct alignas(32) Tri {
  float A[3], B[3], C[3];  // edge functions relative to (x0, y0)
  float x0, y0;
  int minx, miny, maxx, maxy;  // inclusive pixel bbox, clamped to target
  float pz[3];                 // 1/w plane: value at (x0,y0), d/dx, d/dy
  float pn[3][3];              // normal planes
  float ph[3][3];              // half-vector planes
  float alb[3];
};

class Rasterizer {
 public:
  Rasterizer(ThreadPool& pool, const Mesh& mesh);
  void render(const FrameParams& fp, const Target& t, StageTimes& times);
  size_t lastBinnedTriangles() const { return binned_; }

 private:
  struct ScreenVert {
    float x, y, iw;
    float n[3], h[3];
  };
  struct alignas(64) Chunk {  // own cache line: avoids false sharing between setup threads
    std::vector<Tri> tris;
    std::vector<std::vector<uint32_t>> bins;
  };
  void vertexStage(const FrameParams& fp);
  void setupChunk(int c, const FrameParams& fp);
  void setupTri(Chunk& ch, const ScreenVert& a, const ScreenVert& b, const ScreenVert& c,
                const float alb[3]);
  void clipAndSetup(Chunk& ch, uint32_t i0, uint32_t i1, uint32_t i2, const float alb[3],
                    const FrameParams& fp);
  void rasterTile(int tile, int tid, const Target& t, const FrameParams& fp);

  ThreadPool& pool_;
  const Mesh& mesh_;
  // Per-frame vertex outputs (SoA).
  std::vector<float> cx_, cy_, cw_, sx_, sy_, iw_, hx_, hy_, hz_;
  std::vector<uint8_t> oc_;
  std::vector<Chunk> chunks_;
  int tilesX_ = 0, tilesY_ = 0, targetW_ = 0, targetH_ = 0;
  // Per-thread tile scratch buffers (color + depth).
  struct TileBuf {
    alignas(64) float depth[kTile * kTile];
    alignas(64) uint32_t color[kTile * kTile];
  };
  std::vector<TileBuf> tileBufs_;
  size_t binned_ = 0;
};

}  // namespace jsnow
