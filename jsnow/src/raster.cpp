#include "raster.hpp"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdlib>
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
  const float *matR, *matG, *matB, *matRough, *matMetal;
  // point lights
  const float *lx, *ly, *lz, *lr, *lcr, *lcg, *lcb;
};

}  // namespace

Rasterizer::Rasterizer(ThreadPool& pool, const Scene& scene)
    : pool_(pool), scene_(scene), mesh_(scene.mesh) {
  const size_t n = mesh_.vertexCount();
  for (auto* v : {&cx_, &cy_, &cz_, &cw_, &sx_, &sy_, &sd_, &iw_}) v->resize(n);
  oc_.resize(n);
  chunks_.resize(2 * kChunks);  // [0, kChunks) opaque, [kChunks, 2 kChunks) transparent
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
  t.vtx[0] = v0.vid; t.vtx[1] = v1.vid; t.vtx[2] = v2.vid;
  t.material = mat;
  t.invArea = inv;
  t.attrIdx = -1;
  if (shaded && (v0.vid == UINT32_MAX || v1.vid == UINT32_MAX || v2.vid == UINT32_MAX)) {
    t.attrIdx = int32_t(ch.attr.size());
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

// Same plane math as setupTri (bit-identical), run only for visible triangles.
void Rasterizer::buildAttr(const TriHeader& t, TriAttr& a) const {
  const float inv = t.invArea;
  auto plane = [&](float* p, float a0, float a1, float a2) {
    p[0] = a0;
    p[1] = (a0 * t.A[0] + a1 * t.A[1] + a2 * t.A[2]) * inv;
    p[2] = (a0 * t.B[0] + a1 * t.B[1] + a2 * t.B[2]) * inv;
  };
  const uint32_t* v = t.vtx;
  const float q0 = iw_[v[0]], q1 = iw_[v[1]], q2 = iw_[v[2]];
  a.x0 = t.x0; a.y0 = t.y0;
  plane(a.pq, q0, q1, q2);
  const float* src[kAttrs] = {mesh_.tu.data(), mesh_.tv.data(), mesh_.nx.data(), mesh_.ny.data(),
                              mesh_.nz.data(), mesh_.px.data(), mesh_.py.data(), mesh_.pz.data()};
  for (int k = 0; k < kAttrs; ++k) plane(a.pa[k], src[k][v[0]] * q0, src[k][v[1]] * q1, src[k][v[2]] * q2);
  a.material = t.material;
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
    sv[k].vid = UINT32_MAX;
    for (int j = 0; j < kAttrs; ++j) sv[k].a[j] = in[k].a[j];
  }
  for (int k = 1; k + 1 < n; ++k) setupTri(ch, sv[0], sv[k], sv[k + 1], mat, shaded);
}

void Rasterizer::setupChunk(int cIndex, const PassParams& pp, const std::vector<DrawItem>& draws,
                            const std::vector<uint64_t>& triPrefix_) {
  Chunk& ch = chunks_[cIndex];
  ch.hdr.clear();
  ch.attr.clear();
  for (int t = 0; t < tilesX_ * tilesY_; ++t) ch.bins[t].clear();
  const int c = cIndex % kChunks;
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
        s[k].vid = i;  // attributes are fetched lazily at shading time
      }
      setupTri(ch, s[0], s[1], s[2], mat, shaded);
    }
    ++d;
  }
}

// ------------------------------------------------------------- rasterization
namespace {

inline vf plane8(const float* p, vf x, vf y) { return fma(set1(p[1]), x, fma(set1(p[2]), y, set1(p[0]))); }

// G-buffer of 8 pixels, resolved from the visibility buffer. In this
// tile-based deferred design it never leaves registers/L1: the lighting pass
// consumes it straight after the resolve (the CPU analogue of on-chip tile
// memory on mobile GPUs).
struct GBuf {
  vf ar, ag, ab;     // linear albedo
  vf nx, ny, nz;     // unit normal
  vf wx, wy, wz, w;  // world position, view depth
  vf rough, metal;
  vm sky;
};

// Resolve: the attributes of every distinct triangle in the group are
// evaluated once for all lanes and merged per lane; then one texture fetch per
// pixel with a per-lane material.
template <class AttrOf>
inline GBuf resolveGroup(vi ids, vf x, vf y, const ShadeCtx& s, const AttrOf& attrOf) {
  alignas(32) int32_t idl[8];
  lanes(ids, idl);
  GBuf g;
  g.sky = cmpeq(ids, set1i(-1));
  int remaining = ~bits(g.sky) & 0xFF;
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
  vf r, gg, b;
  sampleBilinear(*s.tex, gather(s.matLayer, MAT), U, V, LOD, r, gg, b);
  // Textures are sRGB-ish: approximate decode with gamma 2 (x^2).
  const vf k = set1(1.0f / 255.0f);
  r = r * k; gg = gg * k; b = b * k;
  g.ar = r * r * gatherf(s.matR, MAT);
  g.ag = gg * gg * gatherf(s.matG, MAT);
  g.ab = b * b * gatherf(s.matB, MAT);
  const vf rn = rsqrt_fast(fma(NX, NX, fma(NY, NY, NZ * NZ)));
  g.nx = NX * rn; g.ny = NY * rn; g.nz = NZ * rn;
  g.wx = WX; g.wy = WY; g.wz = WZ; g.w = W;
  g.rough = gatherf(s.matRough, MAT);
  g.metal = gatherf(s.matMetal, MAT);
  return g;
}

// Cook-Torrance GGX specular + Lambert diffuse for one light direction.
// Returns (diffuse+specular) * radiance * n.l per channel, accumulated into o*.
struct PBRPixel {
  vf nx, ny, nz, vx, vy, vz, nv;
  vf dr, dg, db;     // diffuse colour / pi
  vf f0r, f0g, f0b;  // specular reflectance at normal incidence
  vf a2, k;          // GGX alpha^2, Smith k
};

inline void addLight(const PBRPixel& p, vf lx, vf ly, vf lz, vf cr, vf cg, vf cb, vf& orr, vf& og, vf& ob) {
  const vf one = set1(1.0f);
  const vf nl = max(fma(p.nx, lx, fma(p.ny, ly, p.nz * lz)), zerof());
  vf hx = lx + p.vx, hy = ly + p.vy, hz = lz + p.vz;
  const vf rh = rsqrt_fast(max(fma(hx, hx, fma(hy, hy, hz * hz)), set1(1e-8f)));
  hx = hx * rh; hy = hy * rh; hz = hz * rh;
  const vf nh = max(fma(p.nx, hx, fma(p.ny, hy, p.nz * hz)), zerof());
  const vf vh = max(fma(p.vx, hx, fma(p.vy, hy, p.vz * hz)), zerof());
  const vf dd = fma(nh * nh, p.a2 - one, one);
  const vf D = p.a2 * rcp_fast(set1(3.14159265f) * dd * dd);
  const vf omk = one - p.k;
  const vf Vis = rcp_fast(set1(4.0f) * fma(nl, omk, p.k) * fma(p.nv, omk, p.k));
  const vf fc = one - vh, fc2 = fc * fc, f5 = fc2 * fc2 * fc;  // Schlick
  const vf spec = D * Vis;
  const vf Fr = fma(one - p.f0r, f5, p.f0r), Fg = fma(one - p.f0g, f5, p.f0g), Fb = fma(one - p.f0b, f5, p.f0b);
  orr = fma(fma(Fr, spec, p.dr * (one - Fr)) * cr, nl, orr);
  og = fma(fma(Fg, spec, p.dg * (one - Fg)) * cg, nl, og);
  ob = fma(fma(Fb, spec, p.db * (one - Fb)) * cb, nl, ob);
}

// Lighting pass for 8 pixels: sun (shadowed) + hemisphere ambient + the
// point lights of this 16x16 sub-tile. Writes linear HDR radiance.
inline void lightGroup(const GBuf& g, const ShadeCtx& s, const uint8_t* lightList, int lightCount, vf& orr,
                       vf& og, vf& ob) {
  const vf one = set1(1.0f);
  PBRPixel p;
  p.nx = g.nx; p.ny = g.ny; p.nz = g.nz;
  vf vx = set1(s.cam[0]) - g.wx, vy = set1(s.cam[1]) - g.wy, vz = set1(s.cam[2]) - g.wz;
  const vf rv = rsqrt_fast(fma(vx, vx, fma(vy, vy, vz * vz)));
  p.vx = vx * rv; p.vy = vy * rv; p.vz = vz * rv;
  p.nv = max(fma(p.nx, p.vx, fma(p.ny, p.vy, p.nz * p.vz)), set1(1e-3f));
  const vf invPi = set1(0.31830989f), dielectric = set1(0.04f);
  const vf diff = (one - g.metal) * invPi;
  p.dr = g.ar * diff; p.dg = g.ag * diff; p.db = g.ab * diff;
  p.f0r = fma(g.metal, g.ar - dielectric, dielectric);
  p.f0g = fma(g.metal, g.ag - dielectric, dielectric);
  p.f0b = fma(g.metal, g.ab - dielectric, dielectric);
  const vf a = max(g.rough * g.rough, set1(0.02f));
  p.a2 = a * a;
  const vf r1 = g.rough + one;
  p.k = r1 * r1 * set1(0.125f);
  // Ambient: hemisphere sky irradiance on the diffuse part + a little sky specular.
  const vf hemi = fma(g.ny, set1(0.5f), set1(0.5f));
  const vf ad = hemi * (one - g.metal), as = hemi * set1(0.5f);
  orr = fma(g.ar * ad, set1(kSkyColor[0]), p.f0r * as * set1(kSkyColor[0]));
  og = fma(g.ag * ad, set1(kSkyColor[1]), p.f0g * as * set1(kSkyColor[1]));
  ob = fma(g.ab * ad, set1(kSkyColor[2]), p.f0b * as * set1(kSkyColor[2]));
  // Sun.
  const vf Lx = set1(s.L[0]), Ly = set1(s.L[1]), Lz = set1(s.L[2]);
  const vf ndl = fma(g.nx, Lx, fma(g.ny, Ly, g.nz * Lz));
  const vm litMask = andnot(g.sky, ndl > zerof());
  if (bits(litMask)) {
    vf lit = one;
    if (s.shadow) lit = s.shadow->sample(g.wx, g.wy, g.wz, g.w, max(ndl, zerof()));
    addLight(p, Lx, Ly, Lz, set1(kSunColor[0]) * lit, set1(kSunColor[1]) * lit, set1(kSunColor[2]) * lit, orr, og, ob);
  }
  // Point lights (inverse square with a smooth window to zero at the radius).
  for (int i = 0; i < lightCount; ++i) {
    const int li = lightList[i];
    vf dx = set1(s.lx[li]) - g.wx, dy = set1(s.ly[li]) - g.wy, dz = set1(s.lz[li]) - g.wz;
    const vf d2 = fma(dx, dx, fma(dy, dy, dz * dz));
    const float r = s.lr[li];
    const vf x = d2 * set1(1.0f / (r * r));
    const vm in = andnot(g.sky, x < one);
    if (!bits(in)) continue;
    const vf win = max(one - x * x, zerof());
    const vf att = maskf(in, win * win * rcp_fast(d2 + set1(1.0f)));
    const vf il = rsqrt_fast(max(d2, set1(1e-6f)));
    dx = dx * il; dy = dy * il; dz = dz * il;
    addLight(p, dx, dy, dz, set1(s.lcr[li]) * att, set1(s.lcg[li]) * att, set1(s.lcb[li]) * att, orr, og, ob);
  }
  orr = select(g.sky, set1(kSkyColor[0]), orr);
  og = select(g.sky, set1(kSkyColor[1]), og);
  ob = select(g.sky, set1(kSkyColor[2]), ob);
}

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

namespace {
// Calls f(offset, x, y, mask) for every 8-px group of the tile where the
// triangle covers pixels in front of the stored depth (no depth write).
template <class F>
void forEachCovered(const TriHeader& t, const float* depth, int tileX, int tileY, const F& f) {
  const int x0 = std::max(t.minx, tileX), x1 = std::min(t.maxx, tileX + kTile - 1);
  const int y0 = std::max(t.miny, tileY), y1 = std::min(t.maxy, tileY + kTile - 1);
  if (x0 > x1 || y0 > y1) return;
  const int cxs = x0 & ~7;
  for (int y = y0; y <= y1; ++y) {
    const float fy = float(y) + 0.5f - t.y0;
    for (int cx = cxs; cx <= x1; cx += 8) {
      const vf px = set1(float(cx) + 0.5f) + iotaf();
      const vf fx = px - set1(t.x0);
      const vf e0 = fma(set1(t.A[0]), fx, set1(t.B[0] * fy + t.C[0]));
      const vf e1 = fma(set1(t.A[1]), fx, set1(t.B[1] * fy + t.C[1]));
      const vf e2 = fma(set1(t.A[2]), fx, set1(t.B[2] * fy + t.C[2]));
      const vm outside = signmask(as_f(as_i(e0) | as_i(e1) | as_i(e2)));
      if (bits(outside) == 0xFF) continue;
      const int o = (y - tileY) * kTile + (cx - tileX);
      const vf z = fma(set1(t.pd[1]), fx, set1(t.pd[0] + t.pd[2] * fy));
      const vm m = andnot(outside, z > load(depth + o));
      if (bits(m)) f(o, px, set1(float(y) + 0.5f), m);
    }
  }
}
}  // namespace

void Rasterizer::rasterTile(int tile, int tid, const Target& tg, const PassParams& pp) {
  TileBuf& tb = tileBufs_[tid];
  const bool shaded = pp.mode == PassMode::Shaded;
  std::fill(std::begin(tb.depth), std::end(tb.depth), 0.0f);
  if (shaded) std::fill(std::begin(tb.id), std::end(tb.id), 0xFFFFFFFFu);
  const int tileX = (tile % tilesX_) * kTile, tileY = (tile / tilesX_) * kTile;
  // Shaded: the visibility buffer stores an index into this tile's triangle list.
  static thread_local std::vector<const TriHeader*> list;
  static thread_local std::vector<const TriAttr*> listAttr;
  static thread_local std::vector<TriAttr> cache;
  static thread_local std::vector<uint8_t> done;
  list.clear();
  listAttr.clear();
  for (size_t c = 0; c < size_t(kChunks); ++c) {
    const Chunk& ch = chunks_[c];
    for (uint32_t id : ch.bins[tile]) {
      const TriHeader& h = ch.hdr[id];
      if (shaded) {
        drawTri<true>(h, uint32_t(list.size()), tb.depth, tb.id, tileX, tileY);
        list.push_back(&h);
        listAttr.push_back(h.attrIdx >= 0 ? &ch.attr[h.attrIdx] : nullptr);
      } else {
        drawTri<false>(h, 0, tb.depth, nullptr, tileX, tileY);
      }
    }
  }
  const int w = std::min(kTile, tg.w - tileX), h = std::min(kTile, tg.h - tileY);
  if (shaded) {
    const ShadeCtx s{{pp.sunDir.x, pp.sunDir.y, pp.sunDir.z}, {pp.camPos.x, pp.camPos.y, pp.camPos.z}, pp.shadow,
                     &scene_.textures, matLayer_.data(), matR_.data(), matG_.data(), matB_.data(),
                     matRough_.data(), matMetal_.data(), lx_.data(), ly_.data(), lz_.data(), lr_.data(),
                     lcr_.data(), lcg_.data(), lcb_.data()};
    if (cache.size() < list.size()) cache.resize(list.size());
    done.assign(list.size(), 0);
    auto attrOf = [&](uint32_t k) -> const TriAttr& {
      if (listAttr[k]) return *listAttr[k];
      if (!done[k]) { buildAttr(*list[k], cache[k]); done[k] = 1; }
      return cache[k];
    };
    // Tiled light culling: 16x16 sub-tiles, screen rectangle + view-depth range.
    constexpr int kSub = 16, kSubs = kTile / kSub;
    uint8_t subList[kSubs * kSubs][256];
    int subCount[kSubs * kSubs] = {};
    const int nLights = pp.pointLights ? int(lx_.size()) : 0;
    if (nLights) {
      for (int sy = 0; sy < kSubs; ++sy)
        for (int sx = 0; sx < kSubs; ++sx) {
          const int x0 = tileX + sx * kSub, y0 = tileY + sy * kSub;
          if (x0 >= tg.w || y0 >= tg.h) continue;
          float dmin = 1e30f, dmax = 0.0f;
          for (int yy = 0; yy < kSub; ++yy)
            for (int xx = 0; xx < kSub; ++xx) {
              const float d = tb.depth[(sy * kSub + yy) * kTile + sx * kSub + xx];
              dmin = std::min(dmin, d); dmax = std::max(dmax, d);
            }
          if (dmax <= 0.0f) continue;  // all sky
          const float wmin = kNear / dmax, wmax = dmin > 0.0f ? kNear / dmin : 1e30f;
          int& n = subCount[sy * kSubs + sx];
          for (int i = 0; i < nLights && n < 256; ++i) {
            if (lmaxx_[i] < x0 || lminx_[i] > x0 + kSub - 1 || lmaxy_[i] < y0 || lminy_[i] > y0 + kSub - 1) continue;
            if (lviewW_[i] + lr_[i] < wmin || lviewW_[i] - lr_[i] > wmax) continue;
            subList[sy * kSubs + sx][n++] = uint8_t(i);
          }
        }
    }
    for (int y = 0; y < h; ++y) {
      const vf py = set1(float(tileY + y) + 0.5f);
      for (int gx = 0; gx < w; gx += 8) {
        const int o = y * kTile + gx;
        const vi ids = loadi(tb.id + o);
        vf r, g, b;
        if (bits(cmpeq(ids, set1i(-1))) == 0xFF) {
          r = set1(kSkyColor[0]); g = set1(kSkyColor[1]); b = set1(kSkyColor[2]);
        } else {
          const GBuf gb = resolveGroup(ids, set1(float(tileX + gx) + 0.5f) + iotaf(), py, s, attrOf);
          const int sub = (y / kSub) * kSubs + gx / kSub;
          lightGroup(gb, s, subList[sub], subCount[sub], r, g, b);
        }
        store(tb.hdr[0] + o, r); store(tb.hdr[1] + o, g); store(tb.hdr[2] + o, b);
      }
    }
    // ---- transparent geometry: back-to-front, forward shaded, alpha blended ----
    if (hasTransparent_) {
      struct TEntry { float key; const TriHeader* h; const TriAttr* pre; };
      static thread_local std::vector<TEntry> tl;
      tl.clear();
      for (int c = kChunks; c < 2 * kChunks; ++c)
        for (uint32_t id : chunks_[c].bins[tile]) {
          const TriHeader& t = chunks_[c].hdr[id];
          const float cx = 0.5f * (t.minx + t.maxx) + 0.5f - t.x0, cy = 0.5f * (t.miny + t.maxy) + 0.5f - t.y0;
          tl.push_back({t.pd[0] + t.pd[1] * cx + t.pd[2] * cy, &t,  // reversed depth: small = far
                        t.attrIdx >= 0 ? &chunks_[c].attr[t.attrIdx] : nullptr});
        }
      std::sort(tl.begin(), tl.end(), [](const TEntry& a, const TEntry& b) { return a.key < b.key; });
      TriAttr ta;
      for (const TEntry& e : tl) {
        const TriHeader& t = *e.h;
        if (e.pre) ta = *e.pre; else buildAttr(t, ta);
        const float alpha = matAlpha_[t.material];
        auto single = [&](uint32_t) -> const TriAttr& { return ta; };
        forEachCovered(t, tb.depth, tileX, tileY, [&](int o, vf x, vf y, vm m) {
          const GBuf gb = resolveGroup(selecti(m, set1i(0), set1i(-1)), x, y, s, single);
          const int sub = ((o / kTile) / kSub) * kSubs + (o % kTile) / kSub;
          vf r, g, b;
          lightGroup(gb, s, subList[sub], subCount[sub], r, g, b);
          const vf a = maskf(m, set1(alpha));
          float* hr = tb.hdr[0] + o; float* hg = tb.hdr[1] + o; float* hb = tb.hdr[2] + o;
          store(hr, fma(a, r - load(hr), load(hr)));
          store(hg, fma(a, g - load(hg), load(hg)));
          store(hb, fma(a, b - load(hb), load(hb)));
        });
      }
    }
  }
  for (int y = 0; y < h; ++y) {
    if (tg.hdr[0])
      for (int c = 0; c < 3; ++c)
        std::memcpy(tg.hdr[c] + size_t(tileY + y) * tg.w + tileX, tb.hdr[c] + y * kTile, w * sizeof(float));
    if (tg.depth)
      std::memcpy(tg.depth + size_t(tileY + y) * tg.w + tileX, tb.depth + y * kTile, w * sizeof(float));
  }
}

// Point lights: view depth and a conservative screen rectangle per light
// (projected corners of the sphere's bounding box; full screen when it
// reaches behind the near plane).
void Rasterizer::prepareLights(const PassParams& pp, int w, int h) {
  const auto& L = scene_.lights;
  const size_t n = L.size();
  for (auto* v : {&lx_, &ly_, &lz_, &lr_, &lcr_, &lcg_, &lcb_, &lviewW_}) v->resize(n);
  for (auto* v : {&lminx_, &lminy_, &lmaxx_, &lmaxy_}) v->resize(n);
  const Mat4& M = pp.viewProj;
  for (size_t i = 0; i < n; ++i) {
    const PointLight& l = L[i];
    lx_[i] = l.pos.x; ly_[i] = l.pos.y; lz_[i] = l.pos.z; lr_[i] = l.radius;
    lcr_[i] = l.color[0]; lcg_[i] = l.color[1]; lcb_[i] = l.color[2];
    lviewW_[i] = -(pp.view(2, 0) * l.pos.x + pp.view(2, 1) * l.pos.y + pp.view(2, 2) * l.pos.z + pp.view(2, 3));
    float x0 = 1e30f, y0 = 1e30f, x1 = -1e30f, y1 = -1e30f;
    bool behind = false;
    for (int c = 0; c < 8; ++c) {
      const float px = l.pos.x + ((c & 1) ? l.radius : -l.radius);
      const float py = l.pos.y + ((c & 2) ? l.radius : -l.radius);
      const float pz = l.pos.z + ((c & 4) ? l.radius : -l.radius);
      const float X = M(0, 0) * px + M(0, 1) * py + M(0, 2) * pz + M(0, 3);
      const float Y = M(1, 0) * px + M(1, 1) * py + M(1, 2) * pz + M(1, 3);
      const float W = M(3, 0) * px + M(3, 1) * py + M(3, 2) * pz + M(3, 3);
      if (W < kNear) { behind = true; break; }
      const float sx = X / W * pp.vp.ax + pp.vp.bx, sy = Y / W * pp.vp.ay + pp.vp.by;
      x0 = std::min(x0, sx); x1 = std::max(x1, sx); y0 = std::min(y0, sy); y1 = std::max(y1, sy);
    }
    if (behind) { x0 = 0; y0 = 0; x1 = float(w); y1 = float(h); }
    lminx_[i] = int(std::max(-1.0f, std::floor(x0))); lmaxx_[i] = int(std::min(float(w), std::ceil(x1)));
    lminy_[i] = int(std::max(-1.0f, std::floor(y0))); lmaxy_[i] = int(std::min(float(h), std::ceil(y1)));
    if (lviewW_[i] + l.radius < kNear) { lminx_[i] = w + 1; lmaxx_[i] = -2; }  // entirely behind
  }
}

void Rasterizer::render(const PassParams& pp, const std::vector<DrawItem>& draws, const Target& tg,
                        StageTimes& times, const std::vector<DrawItem>* transparent) {
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
      matRough_.push_back(m.roughness);
      matMetal_.push_back(m.metallic);
      matAlpha_.push_back(m.alpha);
    }
  }
  if (pp.mode == PassMode::Shaded) prepareLights(pp, tg.w, tg.h);
  vblocks_.clear();
  triPrefix_.assign(1, 0);
  triPrefixT_.assign(1, 0);
  hasTransparent_ = transparent && !transparent->empty() && pp.mode == PassMode::Shaded;
  auto addDraws = [&](const std::vector<DrawItem>& list, std::vector<uint64_t>& prefix) {
    for (const DrawItem& d : list) {
      for (uint32_t v = 0; v < d.r.vertexCount; v += kVertexBlock)
        vblocks_.push_back({d.r.firstVertex + v, d.r.firstVertex + std::min(d.r.vertexCount, v + kVertexBlock)});
      prefix.push_back(prefix.back() + d.r.indexCount / 3);
    }
  };
  addDraws(draws, triPrefix_);
  if (hasTransparent_) addDraws(*transparent, triPrefixT_);
  auto t0 = clk::now();
  vertexStage(pp);
  auto t1 = clk::now();
  if (hasTransparent_)
    pool_.run(2 * kChunks, [&](int c, int) {
      if (c < kChunks) setupChunk(c, pp, draws, triPrefix_);
      else setupChunk(c, pp, *transparent, triPrefixT_);
    });
  else
    pool_.run(kChunks, [&](int c, int) { setupChunk(c, pp, draws, triPrefix_); });
  auto t2 = clk::now();
  // Largest tiles first: shortens the tail where some threads idle at the end.
  const int nt = tilesX_ * tilesY_;
  tileOrder_.resize(nt);
  tileCost_.assign(nt, 0);
  for (int c = 0; c < (hasTransparent_ ? 2 : 1) * kChunks; ++c)
    for (int t = 0; t < nt; ++t) tileCost_[t] += uint32_t(chunks_[c].bins[t].size());
  for (int t = 0; t < nt; ++t) tileOrder_[t] = t;
  std::sort(tileOrder_.begin(), tileOrder_.end(), [&](int a, int b) { return tileCost_[a] > tileCost_[b]; });
  pool_.run(nt, [&](int i, int tid) { rasterTile(tileOrder_[i], tid, tg, pp); });
  auto t3 = clk::now();
  binned_ = 0;
  for (int c = 0; c < (hasTransparent_ ? 2 : 1) * kChunks; ++c) binned_ += chunks_[c].hdr.size();
  times.vertex += ms(t0, t1);
  times.setup += ms(t1, t2);
  times.raster += ms(t2, t3);
}

}  // namespace jsnow
