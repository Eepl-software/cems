#include "post.hpp"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#if defined(__x86_64__) || defined(_M_X64)
#include <immintrin.h>
#endif

namespace jsnow {

namespace {
constexpr int kRowBlock = 8;
// Fixed-point iterations of q = p - mv(q). Overridable with JSNOW_REPROJECT_ITERS.
int iterations() {
  static const int n = [] {
    const char* e = std::getenv("JSNOW_REPROJECT_ITERS");
    return e ? std::max(0, std::atoi(e)) : 2;
  }();
  return n;
}
#if defined(__AVX2__)
// Hardware gathers are slow on CPUs with the Gather Data Sampling microcode
// mitigation; eight scalar loads are faster there and never much slower.
template <class T>
inline __m256i gather32(const T* base, __m256i idx) {
  alignas(32) int i[8];
  _mm256_store_si256(reinterpret_cast<__m256i*>(i), idx);
  const int32_t* b = reinterpret_cast<const int32_t*>(base);
  return _mm256_setr_epi32(b[i[0]], b[i[1]], b[i[2]], b[i[3]], b[i[4]], b[i[5]], b[i[6]], b[i[7]]);
}
#endif
inline int blocks(int rows) { return (rows + kRowBlock - 1) / kRowBlock; }
}  // namespace

void Reprojector::run(ThreadPool& pool, int w, int h, const uint32_t* prevColor, const float* prevDepth,
                      const Mat4& prevInvView, const Mat4& curViewProj, float p00, float p11,
                      uint32_t* outColor, float* outDepth) {
  if (valid_.size() != size_t(w) * h) valid_.resize(size_t(w) * h);
  const Mat4 M = curViewProj * prevInvView;
  // Previous-frame pixel centre (px, py) with depth d = 1/w maps to the
  // view-space point (vx, vy, -1, d) (homogeneous, scaled by 1/w), with
  // vx = px * kx + bx, vy = py * ky + by.
  const float kx = 2.0f / (w * p00), bxv = -1.0f / p00;
  const float ky = -2.0f / (h * p11), byv = 1.0f / p11;
  // Fold the view-space mapping into the matrix: clip = Ax*px + Ay*py + Ad*d + A0.
  float Ax[4], Ay[4], Ad[4], A0[4];
  for (int r = 0; r < 4; ++r) {
    const int row = r == 3 ? 12 : r * 4;
    Ax[r] = M.m[row] * kx;
    Ay[r] = M.m[row + 1] * ky;
    Ad[r] = M.m[row + 3];
    A0[r] = M.m[row] * bxv + M.m[row + 1] * byv - M.m[row + 2];
  }
  const float hw = 0.5f * w, hh = 0.5f * h;
  uint8_t* valid = valid_.data();
  const int kIterations = iterations();

  pool.run(blocks(h), [&](int b, int) {
    const int y0 = b * kRowBlock, y1 = std::min(h, y0 + kRowBlock);
    // Scalar helper: motion of previous-frame pixel (ix, iy).
    auto motion = [&](int ix, int iy, float& cx, float& cy, float& nd) {
      const float d = std::max(prevDepth[size_t(iy) * w + ix], 1e-4f);
      const float px = ix + 0.5f, py = iy + 0.5f;
      const float X = Ax[0] * px + Ay[0] * py + Ad[0] * d + A0[0];
      const float Y = Ax[1] * px + Ay[1] * py + Ad[1] * d + A0[1];
      const float W = Ax[3] * px + Ay[3] * py + Ad[3] * d + A0[3];
      if (!(W > 1e-6f)) { cx = cy = 1e9f; nd = 0; return; }
      const float iw = 1.0f / W;
      cx = X * iw * hw + hw;
      cy = hh - Y * iw * hh;
      nd = d * iw;
    };
    auto scalarPixel = [&](int x, int y) {
      const float pcx = x + 0.5f, pcy = y + 0.5f;
      int ix = x, iy = y;
      float cx, cy, nd;
      for (int it = 0; it < kIterations; ++it) {
        motion(ix, iy, cx, cy, nd);
        const float qx = pcx - (cx - (ix + 0.5f)), qy = pcy - (cy - (iy + 0.5f));
        ix = std::clamp(int(std::floor(qx)), 0, w - 1);
        iy = std::clamp(int(std::floor(qy)), 0, h - 1);
      }
      motion(ix, iy, cx, cy, nd);
      const size_t o = size_t(y) * w + x;
      outColor[o] = prevColor[size_t(iy) * w + ix];
      outDepth[o] = nd;
      valid[o] = std::fabs(cx - pcx) <= 1.0f && std::fabs(cy - pcy) <= 1.0f;
    };
    for (int y = y0; y < y1; ++y) {
      int x = 0;
#if defined(__AVX2__) && defined(__FMA__)
      const __m256 lane = _mm256_setr_ps(0.5f, 1.5f, 2.5f, 3.5f, 4.5f, 5.5f, 6.5f, 7.5f);
      const __m256 pcy = _mm256_set1_ps(y + 0.5f);
      const __m256 vAx0 = _mm256_set1_ps(Ax[0]), vAy0 = _mm256_set1_ps(Ay[0]), vAd0 = _mm256_set1_ps(Ad[0]), vA00 = _mm256_set1_ps(A0[0]);
      const __m256 vAx1 = _mm256_set1_ps(Ax[1]), vAy1 = _mm256_set1_ps(Ay[1]), vAd1 = _mm256_set1_ps(Ad[1]), vA01 = _mm256_set1_ps(A0[1]);
      const __m256 vAx3 = _mm256_set1_ps(Ax[3]), vAy3 = _mm256_set1_ps(Ay[3]), vAd3 = _mm256_set1_ps(Ad[3]), vA03 = _mm256_set1_ps(A0[3]);
      const __m256 vhw = _mm256_set1_ps(hw), vhh = _mm256_set1_ps(hh), half = _mm256_set1_ps(0.5f);
      const __m256 minD = _mm256_set1_ps(1e-4f), eps = _mm256_set1_ps(1e-6f), one = _mm256_set1_ps(1.0f);
      const __m256 two = _mm256_set1_ps(2.0f), zero = _mm256_setzero_ps(), fw = _mm256_set1_ps(float(w));
      const __m256 maxX = _mm256_set1_ps(float(w - 1)), maxY = _mm256_set1_ps(float(h - 1));
      const __m256 absMask = _mm256_castsi256_ps(_mm256_set1_epi32(0x7FFFFFFF));
      // State of one group of 8 output pixels. Source coordinates are kept as
      // floats holding integers, so the linear index needs no integer multiply.
      struct G {
        __m256 pcx, sx, sy;  // output pixel centre x; integer source pixel
        __m256 cx, cy, nd, ok;
        __m256i idx;
      };
      auto eval = [&](G& g) {
        g.idx = _mm256_cvttps_epi32(_mm256_fmadd_ps(g.sy, fw, g.sx));
        const __m256 d = _mm256_max_ps(_mm256_castsi256_ps(gather32(prevDepth, g.idx)), minD);
        const __m256 px = _mm256_add_ps(g.sx, half), py = _mm256_add_ps(g.sy, half);
        const __m256 X = _mm256_fmadd_ps(vAx0, px, _mm256_fmadd_ps(vAy0, py, _mm256_fmadd_ps(vAd0, d, vA00)));
        const __m256 Y = _mm256_fmadd_ps(vAx1, px, _mm256_fmadd_ps(vAy1, py, _mm256_fmadd_ps(vAd1, d, vA01)));
        const __m256 W = _mm256_fmadd_ps(vAx3, px, _mm256_fmadd_ps(vAy3, py, _mm256_fmadd_ps(vAd3, d, vA03)));
        g.ok = _mm256_cmp_ps(W, eps, _CMP_GT_OQ);
        const __m256 Ws = _mm256_blendv_ps(one, W, g.ok);
        __m256 iw = _mm256_rcp_ps(Ws);
        iw = _mm256_mul_ps(iw, _mm256_fnmadd_ps(Ws, iw, two));  // one Newton step
        g.cx = _mm256_fmadd_ps(_mm256_mul_ps(X, iw), vhw, vhw);
        g.cy = _mm256_fnmadd_ps(_mm256_mul_ps(Y, iw), vhh, vhh);
        g.nd = _mm256_and_ps(_mm256_mul_ps(d, iw), g.ok);
        // Next estimate: q = p - mv = p - (c - src_centre).
        const __m256 qx = _mm256_sub_ps(g.pcx, _mm256_sub_ps(g.cx, px));
        const __m256 qy = _mm256_sub_ps(pcy, _mm256_sub_ps(g.cy, py));
        const __m256 fx = _mm256_floor_ps(qx), fy = _mm256_floor_ps(qy);
        return std::pair{_mm256_min_ps(_mm256_max_ps(fx, zero), maxX), _mm256_min_ps(_mm256_max_ps(fy, zero), maxY)};
      };
      auto finish = [&](G& g, int xs) {
        const __m256 ex = _mm256_and_ps(_mm256_sub_ps(g.cx, g.pcx), absMask);
        const __m256 ey = _mm256_and_ps(_mm256_sub_ps(g.cy, pcy), absMask);
        __m256 v = _mm256_and_ps(_mm256_cmp_ps(ex, one, _CMP_LE_OQ), _mm256_cmp_ps(ey, one, _CMP_LE_OQ));
        v = _mm256_and_ps(v, g.ok);
        const size_t o = size_t(y) * w + xs;
        _mm256_storeu_si256(reinterpret_cast<__m256i*>(outColor + o), gather32(prevColor, g.idx));
        _mm256_storeu_ps(outDepth + o, g.nd);
        const int m = _mm256_movemask_ps(v);
        for (int k = 0; k < 8; ++k) valid[o + k] = uint8_t((m >> k) & 1);
      };
      auto init = [&](G& g, int xs) {
        g.pcx = _mm256_add_ps(_mm256_set1_ps(float(xs)), lane);
        g.sx = _mm256_sub_ps(g.pcx, half);
        g.sy = _mm256_set1_ps(float(y));
      };
      // Two independent groups per loop iteration so their dependency chains overlap.
      for (; x + 16 <= w; x += 16) {
        G g0, g1;
        init(g0, x); init(g1, x + 8);
        for (int it = 0; it < kIterations; ++it) {
          auto [ax, ay] = eval(g0);
          auto [bx, by] = eval(g1);
          g0.sx = ax; g0.sy = ay; g1.sx = bx; g1.sy = by;
        }
        eval(g0); eval(g1);  // motion at the final source pixel, for the validity test
        finish(g0, x); finish(g1, x + 8);
      }
#endif
      for (; x < w; ++x) scalarPixel(x, y);
    }
  });
}

void composeInterleaved(ThreadPool& pool, int w, int h, int ox, int oy, const uint32_t* subColor,
                        const float* subDepth, const uint8_t* valid, uint32_t* color, float* depth) {
  const int sw = w / 2, sh = h / 2;
  pool.run(blocks(h), [&](int b, int) {
    const int y0 = b * kRowBlock, y1 = std::min(h, y0 + kRowBlock);
    for (int y = y0; y < y1; ++y) {
      const bool freshRow = (y & 1) == oy;
      const int j0 = std::clamp((y - oy) >> 1, 0, sh - 1);  // nearest fresh row (floor)
      const int j1 = freshRow ? j0 : std::min(j0 + 1, sh - 1);
      const size_t row = size_t(y) * w;
      const uint32_t* s0 = subColor + size_t(j0) * sw;
      const uint32_t* s1 = subColor + size_t(j1) * sw;
      const float* sd = subDepth + size_t(j0) * sw;
      for (int x = 0; x < w; ++x) {
        const int i0 = std::clamp((x - ox) >> 1, 0, sw - 1);
        if (freshRow && (x & 1) == ox) {  // rendered this frame
          color[row + x] = s0[i0];
          depth[row + x] = sd[i0];
          continue;
        }
        if (!valid[row + x]) {  // disoccluded / off-screen history: nearest fresh sample
          color[row + x] = s0[i0];
          depth[row + x] = sd[i0];
          continue;
        }
        // Valid history: clamp each channel to the range of the surrounding
        // fresh samples (removes ghosting and edge combing).
        const int i1 = (x & 1) == ox ? i0 : std::min(i0 + 1, sw - 1);
#if defined(__SSE2__) || defined(_M_X64)
        const __m128i n = _mm_setr_epi32(int(s0[i0]), int(s0[i1]), int(s1[i0]), int(s1[i1]));
        __m128i lo = _mm_min_epu8(n, _mm_shuffle_epi32(n, 0x4E));
        __m128i hi = _mm_max_epu8(n, _mm_shuffle_epi32(n, 0x4E));
        lo = _mm_min_epu8(lo, _mm_shuffle_epi32(lo, 0xB1));
        hi = _mm_max_epu8(hi, _mm_shuffle_epi32(hi, 0xB1));
        const __m128i hcol = _mm_cvtsi32_si128(int(color[row + x]));
        color[row + x] = uint32_t(_mm_cvtsi128_si32(_mm_min_epu8(_mm_max_epu8(hcol, lo), hi)));
#else
        const uint32_t nb[4] = {s0[i0], s0[i1], s1[i0], s1[i1]};
        uint32_t out = 0;
        for (int c = 0; c < 32; c += 8) {
          uint32_t lo = 255, hi = 0;
          for (uint32_t v : nb) { lo = std::min(lo, (v >> c) & 255u); hi = std::max(hi, (v >> c) & 255u); }
          out |= std::clamp((color[row + x] >> c) & 255u, lo, hi) << c;
        }
        color[row + x] = out;
#endif
      }
    }
  });
}

void scatterInterleaved(ThreadPool& pool, int w, int h, int ox, int oy, const uint32_t* subColor,
                        const float* subDepth, uint32_t* color, float* depth) {
  const int sw = w / 2, sh = h / 2;
  pool.run(blocks(sh), [&](int b, int) {
    const int y0 = b * kRowBlock, y1 = std::min(sh, y0 + kRowBlock);
    for (int j = y0; j < y1; ++j) {
      uint32_t* dc = color + size_t(2 * j + oy) * w + ox;
      const uint32_t* sc = subColor + size_t(j) * sw;
      for (int i = 0; i < sw; ++i) dc[2 * i] = sc[i];
      if (depth && subDepth) {
        float* dd = depth + size_t(2 * j + oy) * w + ox;
        const float* sd = subDepth + size_t(j) * sw;
        for (int i = 0; i < sw; ++i) dd[2 * i] = sd[i];
      }
    }
  });
}

namespace {
// (9a + 3b + 3c + d) / 16 per 8-bit channel, two channels per 32-bit lane op.
inline uint32_t mix9331(uint32_t a, uint32_t b, uint32_t c, uint32_t d) {
  const uint32_t m = 0x00FF00FFu;
  uint32_t lo = (((a & m) * 9 + (b & m) * 3 + (c & m) * 3 + (d & m) + 0x00080008u) >> 4) & m;
  uint32_t hi = ((((a >> 8) & m) * 9 + ((b >> 8) & m) * 3 + ((c >> 8) & m) * 3 + ((d >> 8) & m) +
                  0x00080008u) >> 4) & m;
  return lo | (hi << 8);
}
}  // namespace

void upscale2x(ThreadPool& pool, int w, int h, const uint32_t* src, uint32_t* dst) {
  const int W = 2 * w, H = 2 * h;
  pool.run(blocks(H), [&](int b, int) {
    const int y0 = b * kRowBlock, y1 = std::min(H, y0 + kRowBlock);
    for (int Y = y0; Y < y1; ++Y) {
      const int j = Y >> 1;
      const int j2 = (Y & 1) ? std::min(j + 1, h - 1) : std::max(j - 1, 0);
      const uint32_t* r0 = src + size_t(j) * w;   // weight 3/4
      const uint32_t* r1 = src + size_t(j2) * w;  // weight 1/4
      uint32_t* out = dst + size_t(Y) * W;
      // Even output column 2i blends source i (3/4) with i-1 (1/4),
      // odd column 2i+1 blends i (3/4) with i+1 (1/4).
      auto scalar = [&](int i) {
        const int l = std::max(i - 1, 0), r = std::min(i + 1, w - 1);
        out[2 * i] = mix9331(r0[i], r0[l], r1[i], r1[l]);
        out[2 * i + 1] = mix9331(r0[i], r0[r], r1[i], r1[r]);
      };
      int i = 0;
      scalar(i++);
#if defined(__AVX2__)
      const __m256i three = _mm256_set1_epi16(3), round = _mm256_set1_epi16(8);
      // 16-bit channels of 8 pixels: lo = pixels 0-3, hi = pixels 4-7.
      auto widen = [](const uint32_t* p, __m256i& lo, __m256i& hi) {
        const __m256i v = _mm256_loadu_si256(reinterpret_cast<const __m256i*>(p));
        lo = _mm256_cvtepu8_epi16(_mm256_castsi256_si128(v));
        hi = _mm256_cvtepu8_epi16(_mm256_extracti128_si256(v, 1));
      };
      auto vert = [&](int at, __m256i& lo, __m256i& hi) {  // 3*r0 + r1
        __m256i a0, a1, b0, b1;
        widen(r0 + at, a0, a1);
        widen(r1 + at, b0, b1);
        lo = _mm256_add_epi16(_mm256_mullo_epi16(a0, three), b0);
        hi = _mm256_add_epi16(_mm256_mullo_epi16(a1, three), b1);
      };
      auto narrow = [](__m256i lo, __m256i hi) {
        return _mm256_permute4x64_epi64(_mm256_packus_epi16(lo, hi), 0xD8);
      };
      for (; i + 9 <= w; i += 8) {
        __m256i cl, ch, ll, lh, rl, rh;
        vert(i, cl, ch);
        vert(i - 1, ll, lh);
        vert(i + 1, rl, rh);
        const __m256i c3l = _mm256_add_epi16(_mm256_mullo_epi16(cl, three), round);
        const __m256i c3h = _mm256_add_epi16(_mm256_mullo_epi16(ch, three), round);
        const __m256i even = narrow(_mm256_srli_epi16(_mm256_add_epi16(c3l, ll), 4),
                                    _mm256_srli_epi16(_mm256_add_epi16(c3h, lh), 4));
        const __m256i odd = narrow(_mm256_srli_epi16(_mm256_add_epi16(c3l, rl), 4),
                                   _mm256_srli_epi16(_mm256_add_epi16(c3h, rh), 4));
        const __m256i a = _mm256_unpacklo_epi32(even, odd), b = _mm256_unpackhi_epi32(even, odd);
        _mm256_storeu_si256(reinterpret_cast<__m256i*>(out + 2 * i), _mm256_permute2x128_si256(a, b, 0x20));
        _mm256_storeu_si256(reinterpret_cast<__m256i*>(out + 2 * i + 8), _mm256_permute2x128_si256(a, b, 0x31));
      }
#endif
      for (; i < w; ++i) scalar(i);
    }
  });
}

}  // namespace jsnow
