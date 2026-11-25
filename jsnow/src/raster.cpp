#include "raster.hpp"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>

namespace jsnow {

using namespace simd;

namespace {

constexpr int kChunks = 64;  // triangle chunks for setup/binning (load balancing)
constexpr uint8_t kOcFrustum = 0x1F;
constexpr uint8_t kOcClip = 0x10 | 0x20 | 0x40;  // near + guard band
constexpr float kSnap = 16.0f;                    // 4 bits of sub-pixel precision
constexpr float kEdgeBias = 1.0f / 1024.0f;       // < smallest edge-function step
constexpr int kVertexBlock = 2048;

inline float snap(float v) { return std::floor(v * kSnap + 0.5f) * (1.0f / kSnap); }

struct ShadeCtx {
  float L[3];
  float cam[3];
  const ShadowLookup* shadow;
  const TextureArray* tex;
  const int32_t* matLayer;
  const float *matR, *matG, *matB, *matSpec;
};

}  // namespace

Rasterizer::Rasterizer(ThreadPool& pool, const Scene& scene)
    : pool_(pool), scene_(scene), mesh_(scene.mesh) {
  const size_t n = mesh_.vertexCount();
  for (auto* v : {&cx_, &cy_, &cz_, &cw_, &sx_, &sy_, &sd_, &iw_}) v->resize(n);
  oc_.resize(n);
  chunks_.resize(kChunks);
  tileBufs_.resize(pool.size());
}

// ---------------------------------------------------------------- vertex stage
void Rasterizer::vertexStage(const PassParams& pp) {
  const Mat4& M = pp.viewProj;
  pool_.run(int(vblocks_.size()), [&](int b, int) {
    const uint32_t begin = vblocks_[b].first, end = vblocks_[b].second;
    const float* px = mesh_.px.data();
    const float* py = mesh_.py.data();
    const float* pz = mesh_.pz.data();
    const float ax = pp.vp.ax, bx = pp.vp.bx, ay = pp.vp.ay, by = pp.vp.by;
    // Plain SoA loop; the compiler vectorizes it.
    for (uint32_t i = begin; i < end; ++i) {
      const float x = px[i], y = py[i], z = pz[i];
      const float X = M.m[0] * x + M.m[1] * y + M.m[2] * z + M.m[3];
      const float Y = M.m[4] * x + M.m[5] * y + M.m[6] * z + M.m[7];
      const float Z = M.m[8] * x + M.m[9] * y + M.m[10] * z + M.m[11];
      const float W = M.m[12] * x + M.m[13] * y + M.m[14] * z + M.m[15];
      cx_[i] = X; cy_[i] = Y; cz_[i] = Z; cw_[i] = W;
      const float gw = kGuardBand * W;
      unsigned oc = (X < -W ? 1u : 0u) | (X > W ? 2u : 0u) | (Y < -W ? 4u : 0u) |
                    (Y > W ? 8u : 0u) | (W < kNear ? 16u : 0u) |
                    ((X < -gw || X > gw) ? 32u : 0u) | ((Y < -gw || Y > gw) ? 64u : 0u);
      oc_[i] = uint8_t(oc);
      const float iw = W >= kNear ? 1.0f / W : 0.0f;
      iw_[i] = iw;
      sd_[i] = Z * iw;
      sx_[i] = std::floor((X * iw * ax + bx) * kSnap + 0.5f) * (1.0f / kSnap);
      sy_[i] = std::floor((Y * iw * ay + by) * kSnap + 0.5f) * (1.0f / kSnap);
    }
  });
}

// ------------------------------------------------------------ triangle setup
void Rasterizer::setupTri(Chunk& ch, const SV& va, const SV& vb, const SV& vc, uint32_t mat, bool shaded) {
  float area = (vb.x - va.x) * (vc.y - va.y) - (vc.x - va.x) * (vb.y - va.y);
  if (!(area < 0.0f)) return;  // back-facing, degenerate or NaN
  // Reorder so the signed area is positive: v0 = a, v1 = c, v2 = b.
  const SV& v0 = va;
  const SV& v1 = vc;
  const SV& v2 = vb;
  area = -area;

  const float xmin = std::min({v0.x, v1.x, v2.x}), xmax = std::max({v0.x, v1.x, v2.x});
  const float ymin = std::min({v0.y, v1.y, v2.y}), ymax = std::max({v0.y, v1.y, v2.y});
  int minx = int(std::ceil(xmin - 0.5f)), maxx = int(std::floor(xmax - 0.5f));
  int miny = int(std::ceil(ymin - 0.5f)), maxy = int(std::floor(ymax - 0.5f));
  minx = std::max(minx, 0); miny = std::max(miny, 0);
  maxx = std::min(maxx, targetW_ - 1); maxy = std::min(maxy, targetH_ - 1);
  if (minx > maxx || miny > maxy) return;  // covers no pixel centre

  TriHeader& t = ch.hdr.emplace_back();
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
  plane(t.pd, v0.d, v1.d, v2.d);
  if (shaded) {
    TriAttr& a = ch.attr.emplace_back();
    a.x0 = v0.x; a.y0 = v0.y;
    plane(a.pq, v0.q, v1.q, v2.q);
    for (int k = 0; k < kAttrs; ++k) plane(a.pa[k], v0.a[k] * v0.q, v1.a[k] * v1.q, v2.a[k] * v2.q);
    a.material = mat;
  }
  for (int k = 0; k < 3; ++k) {  // top-left fill rule
    const bool topLeft = t.A[k] > 0.0f || (t.A[k] == 0.0f && t.B[k] > 0.0f);
    if (!topLeft) t.C[k] -= kEdgeBias;
  }
  t.minx = minx; t.miny = miny; t.maxx = maxx; t.maxy = maxy;

  const uint32_t id = uint32_t(ch.hdr.size() - 1);
  const int tx0 = minx / kTile, tx1 = maxx / kTile, ty0 = miny / kTile, ty1 = maxy / kTile;
  for (int ty = ty0; ty <= ty1; ++ty)
    for (int tx = tx0; tx <= tx1; ++tx) ch.bins[ty * tilesX_ + tx].push_back(id);
}

void Rasterizer::clipAndSetup(Chunk& ch, const uint32_t vi_[3], uint32_t mat, const PassParams& pp, bool shaded) {
  struct CV {
    float x, y, z, w, a[kAttrs];
  };
  auto load = [&](uint32_t i) {
    CV c{cx_[i], cy_[i], cz_[i], cw_[i],
         {mesh_.tu[i], mesh_.tv[i], mesh_.nx[i], mesh_.ny[i], mesh_.nz[i], mesh_.px[i], mesh_.py[i], mesh_.pz[i]}};
    return c;
  };
  auto lerp = [](const CV& a, const CV& b, float t) {
    CV r;
    r.x = a.x + (b.x - a.x) * t; r.y = a.y + (b.y - a.y) * t;
    r.z = a.z + (b.z - a.z) * t; r.w = a.w + (b.w - a.w) * t;
    for (int k = 0; k < kAttrs; ++k) r.a[k] = a.a[k] + (b.a[k] - a.a[k]) * t;
    return r;
  };
  CV bufA[12], bufB[12];
  CV* in = bufA;
  CV* out = bufB;
  int n = 3;
  for (int k = 0; k < 3; ++k) in[k] = load(vi_[k]);
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
      const float da = dist(a), db = dist(b);
      if (da >= 0) out[m++] = a;
      if ((da >= 0) != (db >= 0)) out[m++] = lerp(a, b, da / (da - db));
    }
    std::swap(in, out);
    n = m;
  }
  if (n < 3) return;
  SV sv[12];
  for (int k = 0; k < n; ++k) {
    const float iw = 1.0f / in[k].w;
    sv[k].x = snap(in[k].x * iw * pp.vp.ax + pp.vp.bx);
    sv[k].y = snap(in[k].y * iw * pp.vp.ay + pp.vp.by);
    sv[k].d = in[k].z * iw;
    sv[k].q = iw;
    for (int j = 0; j < kAttrs; ++j) sv[k].a[j] = in[k].a[j];
  }
  for (int k = 1; k + 1 < n; ++k) setupTri(ch, sv[0], sv[k], sv[k + 1], mat, shaded);
}

void Rasterizer::setupChunk(int c, const PassParams& pp, const std::vector<DrawItem>& draws) {
  Chunk& ch = chunks_[c];
  ch.hdr.clear();
  ch.attr.clear();
  for (int t = 0; t < tilesX_ * tilesY_; ++t) ch.bins[t].clear();
  const uint64_t T = triPrefix_.back();
  uint64_t g = T * c / kChunks;
  const uint64_t gEnd = T * (c + 1) / kChunks;
  if (g >= gEnd) return;
  size_t d = std::upper_bound(triPrefix_.begin(), triPrefix_.end(), g) - triPrefix_.begin() - 1;
  const bool shaded = pp.mode == PassMode::Shaded;
  const uint32_t* idx = mesh_.idx.data();
  const float* sx = sx_.data();
  const float* sy = sy_.data();
  while (g < gEnd) {
    const uint64_t drawEnd = std::min<uint64_t>(gEnd, triPrefix_[d + 1]);
    const uint32_t triBase = draws[d].r.firstIndex / 3;
    for (; g < drawEnd; ++g) {
      const uint32_t t = triBase + uint32_t(g - triPrefix_[d]);
      const uint32_t v[3] = {idx[3 * t], idx[3 * t + 1], idx[3 * t + 2]};
      const uint8_t o0 = oc_[v[0]], o1 = oc_[v[1]], o2 = oc_[v[2]];
      if (o0 & o1 & o2 & kOcFrustum) continue;  // outside one frustum plane
      const uint32_t mat = mesh_.triMat[t];
      if ((o0 | o1 | o2) & kOcClip) {
        clipAndSetup(ch, v, mat, pp, shaded);
        continue;
      }
      const float area = (sx[v[1]] - sx[v[0]]) * (sy[v[2]] - sy[v[0]]) - (sx[v[2]] - sx[v[0]]) * (sy[v[1]] - sy[v[0]]);
      if (!(area < 0.0f)) continue;  // early back-face rejection
      SV s[3];
      for (int k = 0; k < 3; ++k) {
        const uint32_t i = v[k];
        s[k].x = sx[i]; s[k].y = sy[i]; s[k].d = sd_[i]; s[k].q = iw_[i];
        if (shaded) {
          s[k].a[0] = mesh_.tu[i]; s[k].a[1] = mesh_.tv[i];
          s[k].a[2] = mesh_.nx[i]; s[k].a[3] = mesh_.ny[i]; s[k].a[4] = mesh_.nz[i];
          s[k].a[5] = mesh_.px[i]; s[k].a[6] = mesh_.py[i]; s[k].a[7] = mesh_.pz[i];
        }
      }
      setupTri(ch, s[0], s[1], s[2], mat, shaded);
    }
    ++d;
  }
}

// ------------------------------------------------------------- rasterization
namespace {

inline vf plane8(const float* p, vf x, vf y) { return fma(set1(p[1]), x, fma(set1(p[2]), y, set1(p[0]))); }

// Deferred shading of 8 pixels of a tile from its visibility buffer: the
// attributes of every distinct triangle in the group are evaluated once for
// all lanes and merged per lane; texture, shadow and lighting then run once
// per pixel with full lane utilisation.
template <class AttrOf>
inline vi shadeGroup(vi ids, vf x, vf y, const ShadeCtx& s, const AttrOf& attrOf) {
  alignas(32) int32_t idl[8];
  lanes(ids, idl);
  const vm sky = cmpeq(ids, set1i(-1));
  int remaining = ~bits(sky) & 0xFF;
  vf W = set1(1.0f), U = zerof(), V = zerof(), LOD = zerof();
  vf NX = zerof(), NY = set1(1.0f), NZ = zerof(), WX = zerof(), WY = zerof(), WZ = zerof();
  vi MAT = set1i(0);
  const float ts2 = float(s.tex->size) * float(s.tex->size);
  while (remaining) {
    const int k = __builtin_ctz(unsigned(remaining));
    const vm m = cmpeq(ids, set1i(idl[k]));
    remaining &= ~bits(m);
    const TriAttr& t = attrOf(uint32_t(idl[k]));
    const vf fx = x - set1(t.x0), fy = y - set1(t.y0);
    const vf q = plane8(t.pq, fx, fy);
    const vf w = rcp(q);
    const vf u = plane8(t.pa[0], fx, fy) * w, v = plane8(t.pa[1], fx, fy) * w;
    // Screen-space UV derivatives of u = U/Q: du/dx = (dU/dx - u dQ/dx) / Q.
    const vf qx = set1(t.pq[1]), qy = set1(t.pq[2]);
    const vf dudx = fnma(u, qx, set1(t.pa[0][1])) * w, dvdx = fnma(v, qx, set1(t.pa[1][1])) * w;
    const vf dudy = fnma(u, qy, set1(t.pa[0][2])) * w, dvdy = fnma(v, qy, set1(t.pa[1][2])) * w;
    const vf rho2 = max(fma(dudx, dudx, dvdx * dvdx), fma(dudy, dudy, dvdy * dvdy)) * set1(ts2);
    W = select(m, w, W); U = select(m, u, U); V = select(m, v, V);
    LOD = select(m, set1(0.5f) * log2_fast(max(rho2, set1(1e-12f))), LOD);
    NX = select(m, plane8(t.pa[2], fx, fy), NX);
    NY = select(m, plane8(t.pa[3], fx, fy), NY);
    NZ = select(m, plane8(t.pa[4], fx, fy), NZ);
    WX = select(m, plane8(t.pa[5], fx, fy) * w, WX);
    WY = select(m, plane8(t.pa[6], fx, fy) * w, WY);
    WZ = select(m, plane8(t.pa[7], fx, fy) * w, WZ);
    MAT = selecti(m, set1i(int32_t(t.material)), MAT);
  }
  vf r, g, b;
  sampleBilinear(*s.tex, gather(s.matLayer, MAT), U, V, LOD, r, g, b);
  const vf rn = rsqrt_fast(fma(NX, NX, fma(NY, NY, NZ * NZ)));
  const vf nx = NX * rn, ny = NY * rn, nz = NZ * rn;
  const vf Lx = set1(s.L[0]), Ly = set1(s.L[1]), Lz = set1(s.L[2]);
  const vf ndl = max(fma(nx, Lx, fma(ny, Ly, nz * Lz)), zerof());
  vf lit = set1(1.0f);
  if (s.shadow) lit = s.shadow->sample(WX, WY, WZ, W, ndl);
  const vf vx = set1(s.cam[0]) - WX, vy = set1(s.cam[1]) - WY, vz = set1(s.cam[2]) - WZ;
  const vf rv = rsqrt_fast(fma(vx, vx, fma(vy, vy, vz * vz)));
  const vf hx = fma(vx, rv, Lx), hy = fma(vy, rv, Ly), hz = fma(vz, rv, Lz);
  const vf rh = rsqrt_fast(fma(hx, hx, fma(hy, hy, hz * hz)));
  vf ndh = max(fma(nx, hx, fma(ny, hy, nz * hz)) * rh, zerof());
  ndh = ndh * ndh; ndh = ndh * ndh; ndh = ndh * ndh; ndh = ndh * ndh; ndh = ndh * ndh;  // ^32
  const vf sp = ndh * lit * gatherf(s.matSpec, MAT) * set1(255.0f);
  const vf direct = ndl * lit;
  const vf amb = fma(ny, set1(0.08f), set1(0.16f));
  const vf tr = gatherf(s.matR, MAT), tg = gatherf(s.matG, MAT), tb = gatherf(s.matB, MAT);
  const vf k255 = set1(255.0f);
  const vi ri = trunc_i(min(fma(r * tr, fma(direct, set1(1.00f), amb), sp), k255));
  const vi gi = trunc_i(min(fma(g * tg, fma(direct, set1(0.94f), amb), sp), k255));
  const vi bi = trunc_i(min(fma(b * tb, fma(direct, set1(0.82f), amb), sp), k255));
  const vi col = ri | shl<8>(gi) | shl<16>(bi) | set1i(int32_t(0xFF000000u));
  return selecti(sky, set1i(int32_t(kSkyColor)), col);
}

// Rasterizes one triangle into a 64x64 tile, 8 pixels per step.
// Shaded passes only record the winning triangle id (visibility buffer).
template <bool kShaded>
void drawTri(const TriHeader& t, uint32_t triId, float* depth, uint32_t* ids, int tileX, int tileY) {
  const int x0 = std::max(t.minx, tileX), x1 = std::min(t.maxx, tileX + kTile - 1);
  const int y0 = std::max(t.miny, tileY), y1 = std::min(t.maxy, tileY + kTile - 1);
  if (x0 > x1 || y0 > y1) return;
  const int cxs = x0 & ~7;
  const int nch = ((x1 - cxs) >> 3) + 1;
  const float fx = float(cxs) + 0.5f - t.x0;
  const float fy = float(y0) + 0.5f - t.y0;
  const vf X = set1(fx) + iotaf();
  vf er[3], estep[3], ey[3];
  for (int k = 0; k < 3; ++k) {
    er[k] = fma(set1(t.A[k]), X, set1(t.B[k] * fy + t.C[k]));
    estep[k] = set1(8.0f * t.A[k]);
    ey[k] = set1(t.B[k]);
  }
  vf zr = fma(set1(t.pd[1]), X, set1(t.pd[0] + t.pd[2] * fy));
  const vf zstep = set1(8.0f * t.pd[1]), zy = set1(t.pd[2]);
  for (int y = y0; y <= y1; ++y) {
    vf e0 = er[0], e1 = er[1], e2 = er[2], z = zr;
    float* drow = depth + (y - tileY) * kTile + (cxs - tileX);
    uint32_t* irow = ids + (y - tileY) * kTile + (cxs - tileX);
    for (int c = 0; c < nch; ++c) {
      // Sign bit set in any edge -> outside.
      const vm outside = signmask(as_f(as_i(e0) | as_i(e1) | as_i(e2)));
      if (bits(outside) != 0xFF) {
        const vf d = load(drow + 8 * c);
        const vm m = andnot(outside, z > d);
        if (bits(m)) {
          store(drow + 8 * c, select(m, z, d));
          if constexpr (kShaded) storei(irow + 8 * c, selecti(m, set1i(int32_t(triId)), loadi(irow + 8 * c)));
        }
      }
      e0 = e0 + estep[0]; e1 = e1 + estep[1]; e2 = e2 + estep[2];
      z = z + zstep;
    }
    er[0] = er[0] + ey[0]; er[1] = er[1] + ey[1]; er[2] = er[2] + ey[2];
    zr = zr + zy;
  }
}

}  // namespace

void Rasterizer::rasterTile(int tile, int tid, const Target& tg, const PassParams& pp) {
  TileBuf& tb = tileBufs_[tid];
  const bool shaded = pp.mode == PassMode::Shaded;
  std::fill(std::begin(tb.depth), std::end(tb.depth), 0.0f);
  if (shaded) std::fill(std::begin(tb.id), std::end(tb.id), 0xFFFFFFFFu);
  const int tileX = (tile % tilesX_) * kTile, tileY = (tile / tilesX_) * kTile;
  for (size_t c = 0; c < chunks_.size(); ++c) {
    const Chunk& ch = chunks_[c];
    for (uint32_t id : ch.bins[tile]) {
      if (shaded) drawTri<true>(ch.hdr[id], uint32_t(c << 24) | id, tb.depth, tb.id, tileX, tileY);
      else drawTri<false>(ch.hdr[id], 0, tb.depth, nullptr, tileX, tileY);
    }
  }
  const int w = std::min(kTile, tg.w - tileX), h = std::min(kTile, tg.h - tileY);
  if (shaded) {
    const ShadeCtx s{{pp.sunDir.x, pp.sunDir.y, pp.sunDir.z}, {pp.camPos.x, pp.camPos.y, pp.camPos.z}, pp.shadow,
                     &scene_.textures, matLayer_.data(), matR_.data(), matG_.data(), matB_.data(), matSpec_.data()};
    auto attrOf = [&](uint32_t id) -> const TriAttr& { return chunks_[id >> 24].attr[id & 0xFFFFFF]; };
    for (int y = 0; y < h; ++y) {
      const vf py = set1(float(tileY + y) + 0.5f);
      for (int gx = 0; gx < w; gx += 8) {
        const int o = y * kTile + gx;
        const vi ids = loadi(tb.id + o);
        vi col;
        if (bits(cmpeq(ids, set1i(-1))) == 0xFF) col = set1i(int32_t(kSkyColor));
        else col = shadeGroup(ids, set1(float(tileX + gx) + 0.5f) + iotaf(), py, s, attrOf);
        storei(tb.color + o, col);
      }
    }
  }
  for (int y = 0; y < h; ++y) {
    if (tg.color)
      std::memcpy(tg.color + size_t(tileY + y) * tg.w + tileX, tb.color + y * kTile, w * sizeof(uint32_t));
    if (tg.depth)
      std::memcpy(tg.depth + size_t(tileY + y) * tg.w + tileX, tb.depth + y * kTile, w * sizeof(float));
  }
}

void Rasterizer::render(const PassParams& pp, const std::vector<DrawItem>& draws, const Target& tg,
                        StageTimes& times) {
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
  if (matLayer_.size() != scene_.materials.size()) {
    for (const Material& m : scene_.materials) {
      matLayer_.push_back(m.texture);
      matR_.push_back(m.tint[0]); matG_.push_back(m.tint[1]); matB_.push_back(m.tint[2]);
      matSpec_.push_back(m.specular);
    }
  }
  vblocks_.clear();
  triPrefix_.assign(1, 0);
  for (const DrawItem& d : draws) {
    for (uint32_t v = 0; v < d.r.vertexCount; v += kVertexBlock)
      vblocks_.push_back({d.r.firstVertex + v, d.r.firstVertex + std::min(d.r.vertexCount, v + kVertexBlock)});
    triPrefix_.push_back(triPrefix_.back() + d.r.indexCount / 3);
  }
  auto t0 = clk::now();
  vertexStage(pp);
  auto t1 = clk::now();
  pool_.run(kChunks, [&](int c, int) { setupChunk(c, pp, draws); });
  auto t2 = clk::now();
  pool_.run(tilesX_ * tilesY_, [&](int tile, int tid) { rasterTile(tile, tid, tg, pp); });
  auto t3 = clk::now();
  binned_ = 0;
  for (auto& c : chunks_) binned_ += c.hdr.size();
  times.vertex += ms(t0, t1);
  times.setup += ms(t1, t2);
  times.raster += ms(t2, t3);
}

}  // namespace jsnow
