#include "raster.hpp"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>

#if defined(__AVX2__) && defined(__FMA__)
#include <immintrin.h>
#define JSNOW_AVX2 1
#endif

namespace jsnow {

namespace {

constexpr int kChunks = 64;  // triangle chunks for setup/binning (load balancing)
constexpr uint8_t kOcFrustum = 0x1F;
constexpr uint8_t kOcNear = 0x10;
constexpr uint8_t kOcClip = 0x10 | 0x20 | 0x40;  // near + guard band
constexpr float kSnap = 16.0f;                    // 4 bits of sub-pixel precision
constexpr float kEdgeBias = 1.0f / 1024.0f;       // < smallest edge-function step

inline float snap(float v) { return std::floor(v * kSnap + 0.5f) * (1.0f / kSnap); }

struct Shading {
  float L[3];
};

}  // namespace

Rasterizer::Rasterizer(ThreadPool& pool, const Mesh& mesh) : pool_(pool), mesh_(mesh) {
  size_t n = mesh.vertexCount();
  for (auto* v : {&cx_, &cy_, &cw_, &sx_, &sy_, &iw_, &hx_, &hy_, &hz_}) v->resize(n);
  oc_.resize(n);
  chunks_.resize(kChunks);
  for (auto& c : chunks_) c.tris.reserve(mesh.triangleCount() / kChunks * 2 + 64);
  tileBufs_.resize(pool.size());
}

// ---------------------------------------------------------------- vertex stage
void Rasterizer::vertexStage(const FrameParams& fp) {
  const int n = int(mesh_.vertexCount());
  const int block = 4096;
  const Mat4& M = fp.viewProj;
  pool_.run((n + block - 1) / block, [&](int b, int) {
    const int begin = b * block, end = std::min(n, begin + block);
    const float* px = mesh_.px.data();
    const float* py = mesh_.py.data();
    const float* pz = mesh_.pz.data();
    const float ax = fp.vp.ax, bx = fp.vp.bx, ay = fp.vp.ay, by = fp.vp.by;
    const float Lx = fp.lightDir.x, Ly = fp.lightDir.y, Lz = fp.lightDir.z;
    const float ex = fp.camPos.x, ey = fp.camPos.y, ez = fp.camPos.z;
    // Plain SoA loop; the compiler vectorizes it with AVX2.
    for (int i = begin; i < end; ++i) {
      const float x = px[i], y = py[i], z = pz[i];
      const float X = M.m[0] * x + M.m[1] * y + M.m[2] * z + M.m[3];
      const float Y = M.m[4] * x + M.m[5] * y + M.m[6] * z + M.m[7];
      const float W = M.m[12] * x + M.m[13] * y + M.m[14] * z + M.m[15];
      cx_[i] = X; cy_[i] = Y; cw_[i] = W;
      const float gw = kGuardBand * W;
      unsigned oc = (X < -W ? 1u : 0u) | (X > W ? 2u : 0u) | (Y < -W ? 4u : 0u) |
                    (Y > W ? 8u : 0u) | (W < kNear ? 16u : 0u) |
                    ((X < -gw || X > gw) ? 32u : 0u) | ((Y < -gw || Y > gw) ? 64u : 0u);
      oc_[i] = uint8_t(oc);
      const float iw = W >= kNear ? 1.0f / W : 0.0f;
      iw_[i] = iw;
      sx_[i] = std::floor((X * iw * ax + bx) * kSnap + 0.5f) * (1.0f / kSnap);
      sy_[i] = std::floor((Y * iw * ay + by) * kSnap + 0.5f) * (1.0f / kSnap);
      // Blinn-Phong half vector (view dependent -> recomputed every frame).
      float vx = ex - x, vy = ey - y, vz = ez - z;
      float il = 1.0f / std::sqrt(vx * vx + vy * vy + vz * vz);
      float hx = Lx + vx * il, hy = Ly + vy * il, hz = Lz + vz * il;
      float ih = 1.0f / std::sqrt(hx * hx + hy * hy + hz * hz);
      hx_[i] = hx * ih; hy_[i] = hy * ih; hz_[i] = hz * ih;
    }
  });
}

// ------------------------------------------------------------ triangle setup
void Rasterizer::setupTri(Chunk& ch, const ScreenVert& va, const ScreenVert& vb,
                          const ScreenVert& vc, const float alb[3]) {
  float area = (vb.x - va.x) * (vc.y - va.y) - (vc.x - va.x) * (vb.y - va.y);
  if (!(area < 0.0f)) return;  // back-facing, degenerate or NaN
  // Reorder so the signed area is positive: v0 = a, v1 = c, v2 = b.
  const ScreenVert& v0 = va;
  const ScreenVert& v1 = vc;
  const ScreenVert& v2 = vb;
  area = -area;

  const float xmin = std::min({v0.x, v1.x, v2.x}), xmax = std::max({v0.x, v1.x, v2.x});
  const float ymin = std::min({v0.y, v1.y, v2.y}), ymax = std::max({v0.y, v1.y, v2.y});
  // Pixel centres are at k + 0.5.
  int minx = int(std::ceil(xmin - 0.5f)), maxx = int(std::floor(xmax - 0.5f));
  int miny = int(std::ceil(ymin - 0.5f)), maxy = int(std::floor(ymax - 0.5f));
  minx = std::max(minx, 0); miny = std::max(miny, 0);
  maxx = std::min(maxx, targetW_ - 1); maxy = std::min(maxy, targetH_ - 1);
  if (minx > maxx || miny > maxy) return;  // covers no pixel centre

  Tri& t = ch.tris.emplace_back();
  t.x0 = v0.x; t.y0 = v0.y;
  t.A[0] = v1.y - v2.y; t.B[0] = v2.x - v1.x;
  t.A[1] = v2.y - v0.y; t.B[1] = v0.x - v2.x;
  t.A[2] = v0.y - v1.y; t.B[2] = v1.x - v0.x;
  t.C[0] = t.A[0] * (v0.x - v1.x) + t.B[0] * (v0.y - v1.y);
  t.C[1] = 0.0f; t.C[2] = 0.0f;
  const float inv = 1.0f / area;
  auto plane = [&](float* p, float a0, float a1, float a2) {
    p[0] = a0;
    p[1] = (a0 * t.A[0] + a1 * t.A[1] + a2 * t.A[2]) * inv;
    p[2] = (a0 * t.B[0] + a1 * t.B[1] + a2 * t.B[2]) * inv;
  };
  plane(t.pz, v0.iw, v1.iw, v2.iw);
  for (int k = 0; k < 3; ++k) {
    plane(t.pn[k], v0.n[k], v1.n[k], v2.n[k]);
    plane(t.ph[k], v0.h[k], v1.h[k], v2.h[k]);
  }
  // Top-left fill rule: pixels exactly on a non top-left edge are excluded.
  for (int k = 0; k < 3; ++k) {
    bool topLeft = t.A[k] > 0.0f || (t.A[k] == 0.0f && t.B[k] > 0.0f);
    if (!topLeft) t.C[k] -= kEdgeBias;
  }
  t.minx = minx; t.miny = miny; t.maxx = maxx; t.maxy = maxy;
  t.alb[0] = alb[0]; t.alb[1] = alb[1]; t.alb[2] = alb[2];

  const uint32_t id = uint32_t(ch.tris.size() - 1);
  const int tx0 = minx / kTile, tx1 = maxx / kTile, ty0 = miny / kTile, ty1 = maxy / kTile;
  for (int ty = ty0; ty <= ty1; ++ty)
    for (int tx = tx0; tx <= tx1; ++tx) ch.bins[ty * tilesX_ + tx].push_back(id);
}

void Rasterizer::clipAndSetup(Chunk& ch, uint32_t i0, uint32_t i1, uint32_t i2,
                              const float alb[3], const FrameParams& fp) {
  struct CV {
    float x, y, w, n[3], h[3];
  };
  auto load = [&](uint32_t i) {
    return CV{cx_[i], cy_[i], cw_[i], {mesh_.nx[i], mesh_.ny[i], mesh_.nz[i]}, {hx_[i], hy_[i], hz_[i]}};
  };
  auto lerp = [](const CV& a, const CV& b, float t) {
    CV r;
    r.x = a.x + (b.x - a.x) * t; r.y = a.y + (b.y - a.y) * t; r.w = a.w + (b.w - a.w) * t;
    for (int k = 0; k < 3; ++k) {
      r.n[k] = a.n[k] + (b.n[k] - a.n[k]) * t;
      r.h[k] = a.h[k] + (b.h[k] - a.h[k]) * t;
    }
    return r;
  };
  CV bufA[12], bufB[12];
  CV* in = bufA;
  CV* out = bufB;
  int n = 3;
  in[0] = load(i0); in[1] = load(i1); in[2] = load(i2);
  const float G = kGuardBand;
  for (int p = 0; p < 5 && n >= 3; ++p) {
    auto dist = [&](const CV& v) {
      switch (p) {
        case 0: return v.w - kNear;
        case 1: return G * v.w - v.x;
        case 2: return G * v.w + v.x;
        case 3: return G * v.w - v.y;
        default: return G * v.w + v.y;
      }
    };
    int m = 0;
    for (int k = 0; k < n; ++k) {
      const CV& a = in[k];
      const CV& b = in[(k + 1) % n];
      float da = dist(a), db = dist(b);
      if (da >= 0) out[m++] = a;
      if ((da >= 0) != (db >= 0)) out[m++] = lerp(a, b, da / (da - db));
    }
    std::swap(in, out);
    n = m;
  }
  if (n < 3) return;
  ScreenVert sv[12];
  for (int k = 0; k < n; ++k) {
    const float iw = 1.0f / in[k].w;
    sv[k].x = snap(in[k].x * iw * fp.vp.ax + fp.vp.bx);
    sv[k].y = snap(in[k].y * iw * fp.vp.ay + fp.vp.by);
    sv[k].iw = iw;
    for (int j = 0; j < 3; ++j) { sv[k].n[j] = in[k].n[j]; sv[k].h[j] = in[k].h[j]; }
  }
  for (int k = 1; k + 1 < n; ++k) setupTri(ch, sv[0], sv[k], sv[k + 1], alb);
}

void Rasterizer::setupChunk(int c, const FrameParams& fp) {
  Chunk& ch = chunks_[c];
  ch.tris.clear();
  for (auto& b : ch.bins) b.clear();
  const int N = int(mesh_.triangleCount());
  const int begin = int(int64_t(N) * c / kChunks), end = int(int64_t(N) * (c + 1) / kChunks);
  const uint32_t* idx = mesh_.idx.data();
  const float* sx = sx_.data();
  const float* sy = sy_.data();
  for (int t = begin; t < end; ++t) {
    const uint32_t i0 = idx[3 * t], i1 = idx[3 * t + 1], i2 = idx[3 * t + 2];
    const uint8_t o0 = oc_[i0], o1 = oc_[i1], o2 = oc_[i2];
    if (o0 & o1 & o2 & kOcFrustum) continue;  // trivially outside one frustum plane
    const float alb[3] = {mesh_.ar[t], mesh_.ag[t], mesh_.ab[t]};
    if ((o0 | o1 | o2) & kOcClip) {
      clipAndSetup(ch, i0, i1, i2, alb, fp);
      continue;
    }
    // Early back-face rejection before gathering attributes.
    const float area = (sx[i1] - sx[i0]) * (sy[i2] - sy[i0]) - (sx[i2] - sx[i0]) * (sy[i1] - sy[i0]);
    if (!(area < 0.0f)) continue;
    auto sv = [&](uint32_t i) {
      return ScreenVert{sx[i], sy[i], iw_[i], {mesh_.nx[i], mesh_.ny[i], mesh_.nz[i]}, {hx_[i], hy_[i], hz_[i]}};
    };
    setupTri(ch, sv(i0), sv(i1), sv(i2), alb);
  }
  (void)kOcNear;
}

// ------------------------------------------------------------- rasterization
namespace {

#ifdef JSNOW_AVX2
inline __m256 plane8(const float* p, __m256 x, __m256 y) {
  return _mm256_fmadd_ps(_mm256_set1_ps(p[1]), x, _mm256_fmadd_ps(_mm256_set1_ps(p[2]), y, _mm256_set1_ps(p[0])));
}

inline __m256i shade8(const Tri& t, __m256 x, __m256 y, const Shading& s) {
  __m256 nx = plane8(t.pn[0], x, y), ny = plane8(t.pn[1], x, y), nz = plane8(t.pn[2], x, y);
  __m256 hx = plane8(t.ph[0], x, y), hy = plane8(t.ph[1], x, y), hz = plane8(t.ph[2], x, y);
  __m256 rn = _mm256_rsqrt_ps(_mm256_fmadd_ps(nx, nx, _mm256_fmadd_ps(ny, ny, _mm256_mul_ps(nz, nz))));
  nx = _mm256_mul_ps(nx, rn); ny = _mm256_mul_ps(ny, rn); nz = _mm256_mul_ps(nz, rn);
  __m256 rh = _mm256_rsqrt_ps(_mm256_fmadd_ps(hx, hx, _mm256_fmadd_ps(hy, hy, _mm256_mul_ps(hz, hz))));
  const __m256 zero = _mm256_setzero_ps();
  __m256 ndl = _mm256_fmadd_ps(nx, _mm256_set1_ps(s.L[0]),
                _mm256_fmadd_ps(ny, _mm256_set1_ps(s.L[1]), _mm256_mul_ps(nz, _mm256_set1_ps(s.L[2]))));
  ndl = _mm256_max_ps(ndl, zero);
  __m256 ndh = _mm256_mul_ps(_mm256_fmadd_ps(nx, hx, _mm256_fmadd_ps(ny, hy, _mm256_mul_ps(nz, hz))), rh);
  ndh = _mm256_max_ps(ndh, zero);
  __m256 sp = _mm256_mul_ps(ndh, ndh);  // ^2
  sp = _mm256_mul_ps(sp, sp);           // ^4
  sp = _mm256_mul_ps(sp, sp);           // ^8
  sp = _mm256_mul_ps(sp, sp);           // ^16
  sp = _mm256_mul_ps(sp, sp);           // ^32
  sp = _mm256_mul_ps(sp, _mm256_set1_ps(0.35f * 255.0f));
  // Hemisphere ambient + warm directional light.
  __m256 amb = _mm256_fmadd_ps(ny, _mm256_set1_ps(0.08f), _mm256_set1_ps(0.16f));
  __m256 lr = _mm256_fmadd_ps(ndl, _mm256_set1_ps(1.00f), amb);
  __m256 lg = _mm256_fmadd_ps(ndl, _mm256_set1_ps(0.94f), amb);
  __m256 lb = _mm256_fmadd_ps(ndl, _mm256_set1_ps(0.82f), amb);
  const __m256 k255 = _mm256_set1_ps(255.0f);
  __m256 r = _mm256_fmadd_ps(lr, _mm256_set1_ps(t.alb[0] * 255.0f), sp);
  __m256 g = _mm256_fmadd_ps(lg, _mm256_set1_ps(t.alb[1] * 255.0f), sp);
  __m256 b = _mm256_fmadd_ps(lb, _mm256_set1_ps(t.alb[2] * 255.0f), sp);
  __m256i ri = _mm256_cvttps_epi32(_mm256_min_ps(r, k255));
  __m256i gi = _mm256_cvttps_epi32(_mm256_min_ps(g, k255));
  __m256i bi = _mm256_cvttps_epi32(_mm256_min_ps(b, k255));
  __m256i c = _mm256_or_si256(ri, _mm256_slli_epi32(gi, 8));
  c = _mm256_or_si256(c, _mm256_slli_epi32(bi, 16));
  return _mm256_or_si256(c, _mm256_set1_epi32(int(0xFF000000u)));
}

// Rasterizes one triangle into a 64x64 tile, 8 pixels per step.
void drawTri(const Tri& t, float* depth, uint32_t* color, int tileX, int tileY, const Shading& s) {
  const int x0 = std::max(t.minx, tileX), x1 = std::min(t.maxx, tileX + kTile - 1);
  const int y0 = std::max(t.miny, tileY), y1 = std::min(t.maxy, tileY + kTile - 1);
  if (x0 > x1 || y0 > y1) return;
  const int cxs = x0 & ~7;
  const int nch = ((x1 - cxs) >> 3) + 1;
  const float fx = float(cxs) + 0.5f - t.x0;
  const float fy = float(y0) + 0.5f - t.y0;
  const __m256 lane = _mm256_setr_ps(0, 1, 2, 3, 4, 5, 6, 7);
  const __m256 X = _mm256_add_ps(_mm256_set1_ps(fx), lane);
  __m256 er[3], estep[3], ey[3];
  for (int k = 0; k < 3; ++k) {
    er[k] = _mm256_fmadd_ps(_mm256_set1_ps(t.A[k]), X, _mm256_set1_ps(t.B[k] * fy + t.C[k]));
    estep[k] = _mm256_set1_ps(8.0f * t.A[k]);
    ey[k] = _mm256_set1_ps(t.B[k]);
  }
  __m256 zr = _mm256_fmadd_ps(_mm256_set1_ps(t.pz[1]), X, _mm256_set1_ps(t.pz[0] + t.pz[2] * fy));
  const __m256 zstep = _mm256_set1_ps(8.0f * t.pz[1]), zy = _mm256_set1_ps(t.pz[2]);
  const __m256 eight = _mm256_set1_ps(8.0f), zero = _mm256_setzero_ps();
  float py = fy;
  for (int y = y0; y <= y1; ++y, py += 1.0f) {
    __m256 e0 = er[0], e1 = er[1], e2 = er[2], z = zr, xv = X;
    float* drow = depth + (y - tileY) * kTile + (cxs - tileX);
    uint32_t* crow = color + (y - tileY) * kTile + (cxs - tileX);
    for (int c = 0; c < nch; ++c) {
      // Sign bit set in any edge -> outside.
      const __m256 out = _mm256_or_ps(e0, _mm256_or_ps(e1, e2));
      if (_mm256_movemask_ps(out) != 0xFF) {
        const __m256 d = _mm256_load_ps(drow + 8 * c);
        const __m256 m = _mm256_blendv_ps(_mm256_cmp_ps(z, d, _CMP_GT_OQ), zero, out);
        const int mm = _mm256_movemask_ps(m);
        if (mm) {
          _mm256_store_ps(drow + 8 * c, _mm256_blendv_ps(d, z, m));
          const __m256i col = shade8(t, xv, _mm256_set1_ps(py), s);
          __m256i* cp = reinterpret_cast<__m256i*>(crow + 8 * c);
          const __m256i old = _mm256_load_si256(cp);
          _mm256_store_si256(cp, _mm256_castps_si256(_mm256_blendv_ps(
                                     _mm256_castsi256_ps(old), _mm256_castsi256_ps(col), m)));
        }
      }
      e0 = _mm256_add_ps(e0, estep[0]); e1 = _mm256_add_ps(e1, estep[1]); e2 = _mm256_add_ps(e2, estep[2]);
      z = _mm256_add_ps(z, zstep);
      xv = _mm256_add_ps(xv, eight);
    }
    er[0] = _mm256_add_ps(er[0], ey[0]); er[1] = _mm256_add_ps(er[1], ey[1]); er[2] = _mm256_add_ps(er[2], ey[2]);
    zr = _mm256_add_ps(zr, zy);
  }
}
#else
// Portable scalar fallback (same math, one pixel at a time).
void drawTri(const Tri& t, float* depth, uint32_t* color, int tileX, int tileY, const Shading& s) {
  const int x0 = std::max(t.minx, tileX), x1 = std::min(t.maxx, tileX + kTile - 1);
  const int y0 = std::max(t.miny, tileY), y1 = std::min(t.maxy, tileY + kTile - 1);
  for (int y = y0; y <= y1; ++y)
    for (int x = x0; x <= x1; ++x) {
      const float fx = x + 0.5f - t.x0, fy = y + 0.5f - t.y0;
      bool in = true;
      for (int k = 0; k < 3; ++k) in &= (t.A[k] * fx + t.B[k] * fy + t.C[k]) >= 0.0f;
      if (!in) continue;
      const float z = t.pz[0] + t.pz[1] * fx + t.pz[2] * fy;
      float& d = depth[(y - tileY) * kTile + (x - tileX)];
      if (!(z > d)) continue;
      d = z;
      auto pl = [&](const float* p) { return p[0] + p[1] * fx + p[2] * fy; };
      float n[3] = {pl(t.pn[0]), pl(t.pn[1]), pl(t.pn[2])}, h[3] = {pl(t.ph[0]), pl(t.ph[1]), pl(t.ph[2])};
      float rn = 1.0f / std::sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2]);
      float rh = 1.0f / std::sqrt(h[0] * h[0] + h[1] * h[1] + h[2] * h[2]);
      for (float& v : n) v *= rn;
      float ndl = std::max(0.0f, n[0] * s.L[0] + n[1] * s.L[1] + n[2] * s.L[2]);
      float ndh = std::max(0.0f, (n[0] * h[0] + n[1] * h[1] + n[2] * h[2]) * rh);
      float sp = std::pow(ndh, 32.0f) * 0.35f * 255.0f;
      float amb = 0.16f + 0.08f * n[1];
      const float lc[3] = {1.0f, 0.94f, 0.82f};
      uint32_t out = 0xFF000000u;
      for (int k = 0; k < 3; ++k) {
        float v = std::min(255.0f, (ndl * lc[k] + amb) * t.alb[k] * 255.0f + sp);
        out |= uint32_t(int(v)) << (8 * k);
      }
      color[(y - tileY) * kTile + (x - tileX)] = out;
    }
}
#endif

}  // namespace

void Rasterizer::rasterTile(int tile, int tid, const Target& tg, const FrameParams& fp) {
  TileBuf& tb = tileBufs_[tid];
  std::fill(std::begin(tb.depth), std::end(tb.depth), 0.0f);
  std::fill(std::begin(tb.color), std::end(tb.color), kSkyColor);
  const int tileX = (tile % tilesX_) * kTile, tileY = (tile / tilesX_) * kTile;
  Shading s{{fp.lightDir.x, fp.lightDir.y, fp.lightDir.z}};
  for (const Chunk& ch : chunks_)
    for (uint32_t id : ch.bins[tile]) drawTri(ch.tris[id], tb.depth, tb.color, tileX, tileY, s);
  const int w = std::min(kTile, tg.w - tileX), h = std::min(kTile, tg.h - tileY);
  for (int y = 0; y < h; ++y) {
    std::memcpy(tg.color + size_t(tileY + y) * tg.w + tileX, tb.color + y * kTile, w * sizeof(uint32_t));
    if (tg.depth)
      std::memcpy(tg.depth + size_t(tileY + y) * tg.w + tileX, tb.depth + y * kTile, w * sizeof(float));
  }
}

void Rasterizer::render(const FrameParams& fp, const Target& tg, StageTimes& times) {
  using clk = std::chrono::steady_clock;
  auto ms = [](clk::time_point a, clk::time_point b) {
    return std::chrono::duration<double, std::milli>(b - a).count();
  };
  if (tg.w != targetW_ || tg.h != targetH_) {
    targetW_ = tg.w; targetH_ = tg.h;
    tilesX_ = (tg.w + kTile - 1) / kTile;
    tilesY_ = (tg.h + kTile - 1) / kTile;
    for (auto& c : chunks_) c.bins.assign(tilesX_ * tilesY_, {});
  }
  auto t0 = clk::now();
  vertexStage(fp);
  auto t1 = clk::now();
  pool_.run(kChunks, [&](int c, int) { setupChunk(c, fp); });
  auto t2 = clk::now();
  pool_.run(tilesX_ * tilesY_, [&](int tile, int tid) { rasterTile(tile, tid, tg, fp); });
  auto t3 = clk::now();
  binned_ = 0;
  for (auto& c : chunks_) binned_ += c.tris.size();
  times.vertex += ms(t0, t1);
  times.setup += ms(t1, t2);
  times.raster += ms(t2, t3);
}

}  // namespace jsnow
