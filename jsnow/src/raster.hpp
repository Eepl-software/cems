#pragma once
#include <cstdint>
#include <vector>

#include "math.hpp"
#include "scene.hpp"
#include "simd.hpp"
#include "threadpool.hpp"

namespace jsnow {

constexpr int kTile = 64;
constexpr float kNear = 0.1f;       // near plane distance (must match the projection)
constexpr float kGuardBand = 4.0f;  // clip-space guard band, in multiples of the viewport

// Maps NDC to target pixel coordinates: px = ndcX*ax + bx, py = ndcY*ay + by.
struct Viewport {
  float ax, bx, ay, by;
  static Viewport full(int w, int h) { return {w * 0.5f, w * 0.5f, -h * 0.5f, h * 0.5f}; }
  // Half-size target sampling full-grid pixels (2i+ox, 2j+oy) of a w x h image.
  static Viewport interleaved(int w, int h, int ox, int oy) {
    return {w * 0.25f, (w * 0.5f - ox + 0.5f) * 0.5f, -h * 0.25f, (h * 0.5f - oy + 0.5f) * 0.5f};
  }
};

struct Target {
  int w = 0, h = 0;
  uint32_t* color = nullptr;  // RGBA8, may be null (depth-only passes)
  float* depth = nullptr;     // z/w, reversed (larger = closer, 0 = far/sky); may be null
};

struct StageTimes {
  double cull = 0, shadow = 0, vertex = 0, setup = 0, raster = 0, reproject = 0, compose = 0, upscale = 0;
  StageTimes& operator+=(const StageTimes& o) {
    cull += o.cull; shadow += o.shadow; vertex += o.vertex; setup += o.setup; raster += o.raster;
    reproject += o.reproject; compose += o.compose; upscale += o.upscale;
    return *this;
  }
  double rasterTotal() const { return vertex + setup + raster; }
};

constexpr uint32_t kSkyColor = 0xFFE0B080u;  // RGBA (128,176,224)

// Per-pixel sun shadow lookup, implemented by the shadow module (A3).
struct ShadowLookup {
  virtual ~ShadowLookup() = default;
  // Returns the lit fraction (0..1) for 8 world positions with view depth w.
  virtual simd::vf sample(simd::vf wx, simd::vf wy, simd::vf wz, simd::vf viewW, simd::vf ndl) const = 0;
};

enum class PassMode { Shaded, DepthOnly };

struct PassParams {
  Mat4 viewProj;
  Viewport vp;
  PassMode mode = PassMode::Shaded;
  Vec3 camPos;
  Vec3 sunDir;  // unit vector towards the sun
  const ShadowLookup* shadow = nullptr;
};

constexpr int kAttrs = 8;  // u, v, nx, ny, nz, wx, wy, wz

// Edge/depth part of a set-up triangle (all that depth-only passes need).
struct alignas(16) TriHeader {
  float A[3], B[3], C[3];  // edge functions relative to (x0, y0)
  float x0, y0;
  int minx, miny, maxx, maxy;  // inclusive pixel bbox, clamped to target
  float pd[3];                 // depth plane z/w: value at (x0,y0), d/dx, d/dy
  // Shaded passes: attribute planes are built lazily, per tile, only for
  // triangles that win at least one pixel (from these vertex indices).
  uint32_t vtx[3];   // mesh vertices in v0, v1, v2 order
  uint32_t material;
  int32_t attrIdx;   // >= 0: clipped triangle, planes precomputed in Chunk::attr
  float invArea;
};
// Perspective-correct attribute planes: q = 1/w and attr*q.
struct TriAttr {
  float x0, y0;  // plane origin (copy of the header's, so shading never touches headers)
  float pq[3];
  float pa[kAttrs][3];
  uint32_t material;
};

class Rasterizer {
 public:
  Rasterizer(ThreadPool& pool, const Scene& scene);
  void render(const PassParams& pp, const std::vector<DrawItem>& draws, const Target& t, StageTimes& times);
  size_t lastBinnedTriangles() const { return binned_; }

 private:
  struct SV {  // screen-space vertex
    float x, y, d, q, a[kAttrs];
    uint32_t vid;  // mesh vertex, or UINT32_MAX for vertices created by clipping
  };
  struct alignas(64) Chunk {  // own cache line: avoids false sharing between setup threads
    std::vector<TriHeader> hdr;
    std::vector<TriAttr> attr;
    std::vector<std::vector<uint32_t>> bins;
  };
  void vertexStage(const PassParams& pp);
  void setupChunk(int c, const PassParams& pp, const std::vector<DrawItem>& draws);
  void setupTri(Chunk& ch, const SV& a, const SV& b, const SV& c, uint32_t mat, bool shaded);
  void clipAndSetup(Chunk& ch, const uint32_t v[3], uint32_t mat, const PassParams& pp, bool shaded);
  void rasterTile(int tile, int tid, const Target& t, const PassParams& pp);
  void buildAttr(const TriHeader& h, TriAttr& a) const;

  ThreadPool& pool_;
  const Scene& scene_;
  const Mesh& mesh_;
  std::vector<float> cx_, cy_, cz_, cw_, sx_, sy_, sd_, iw_;
  std::vector<uint8_t> oc_;
  std::vector<std::pair<uint32_t, uint32_t>> vblocks_;  // vertex ranges this pass
  std::vector<uint64_t> triPrefix_;                     // triangle prefix sum over draws
  std::vector<Chunk> chunks_;
  int tilesX_ = 0, tilesY_ = 0, targetW_ = 0, targetH_ = 0;
  struct TileBuf {
    alignas(64) float depth[kTile * kTile];
    alignas(64) uint32_t color[kTile * kTile];
    alignas(64) uint32_t id[kTile * kTile];  // visibility buffer: index into the tile triangle list
  };
  std::vector<TileBuf> tileBufs_;
  // Material table in SoA form for per-lane gathers while shading.
  std::vector<int32_t> matLayer_;
  std::vector<float> matR_, matG_, matB_, matSpec_;
  size_t binned_ = 0;
};

}  // namespace jsnow
