#include "post.hpp"

#include "simd.hpp"

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
inline int blocks(int rows) { return (rows + kRowBlock - 1) / kRowBlock; }
}  // namespace

void Reprojector::run(ThreadPool& pool, int w, int h, const uint32_t* prevColor, const float* prevDepth,
                      const Mat4& prevInvView, const Mat4& curViewProj, float p00, float p11, float depthScale,
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
    Ad[r] = M.m[row + 3] / depthScale;  // stored depth = depthScale / w
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
#if !defined(JSNOW_SIMD_SCALAR)
      using namespace simd;
      const vf lane = iotaf() + set1(0.5f);
      const vf pcy = set1(y + 0.5f);
      const vf vAx0 = set1(Ax[0]), vAy0 = set1(Ay[0]), vAd0 = set1(Ad[0]), vA00 = set1(A0[0]);
      const vf vAx1 = set1(Ax[1]), vAy1 = set1(Ay[1]), vAd1 = set1(Ad[1]), vA01 = set1(A0[1]);
      const vf vAx3 = set1(Ax[3]), vAy3 = set1(Ay[3]), vAd3 = set1(Ad[3]), vA03 = set1(A0[3]);
      const vf vhw = set1(hw), vhh = set1(hh), half = set1(0.5f);
      const vf minD = set1(1e-4f), eps = set1(1e-6f), one = set1(1.0f);
      const vf zero = zerof(), fw = set1(float(w));
      const vf maxX = set1(float(w - 1)), maxY = set1(float(h - 1));
      // State of one group of 8 output pixels. Source coordinates are kept as
      // floats holding integers, so the linear index needs no integer multiply.
      struct G {
        vf pcx, sx, sy;  // output pixel centre x; integer source pixel
        vf cx, cy, nd;
        vm ok;
        vi idx;
      };
      auto eval = [&](G& g) {
        g.idx = trunc_i(fma(g.sy, fw, g.sx));
        const vf d = max(gatherf(prevDepth, g.idx), minD);
        const vf px = g.sx + half, py = g.sy + half;
        const vf X = fma(vAx0, px, fma(vAy0, py, fma(vAd0, d, vA00)));
        const vf Y = fma(vAx1, px, fma(vAy1, py, fma(vAd1, d, vA01)));
        const vf W = fma(vAx3, px, fma(vAy3, py, fma(vAd3, d, vA03)));
        g.ok = W > eps;
        const vf iw = rcp(select(g.ok, W, one));
        g.cx = fma(X * iw, vhw, vhw);
        g.cy = fnma(Y * iw, vhh, vhh);
        g.nd = maskf(g.ok, d * iw);
        // Next estimate: q = p - mv = p - (c - src_centre).
        const vf qx = g.pcx - (g.cx - px), qy = pcy - (g.cy - py);
        return std::pair{clamp(floor(qx), zero, maxX), clamp(floor(qy), zero, maxY)};
      };
      auto finish = [&](G& g, int xs) {
        const vm v = (abs(g.cx - g.pcx) <= one) & (abs(g.cy - pcy) <= one) & g.ok;
        const size_t o = size_t(y) * w + xs;
        storeui(outColor + o, gather(prevColor, g.idx));
        storeu(outDepth + o, g.nd);
        const int m = bits(v);
        for (int k = 0; k < 8; ++k) valid[o + k] = uint8_t((m >> k) & 1);
      };
      auto init = [&](G& g, int xs) {
        g.pcx = set1(float(xs)) + lane;
        g.sx = g.pcx - half;
        g.sy = set1(float(y));
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

void tonemap(ThreadPool& pool, int w, int h, const float* const hdr[3], float exposure, uint32_t* out) {
  using namespace simd;
  const size_t n = size_t(w) * h;
  const int blocksN = int((n + 16383) / 16384);
  pool.run(blocksN, [&](int b, int) {
    const size_t i0 = size_t(b) * 16384, i1 = std::min(n, i0 + 16384);
    size_t i = i0;
    auto aces = [](vf x) {
      const vf num = x * fma(x, set1(2.51f), set1(0.03f));
      const vf den = fma(x, fma(x, set1(2.43f), set1(0.59f)), set1(0.14f));
      return clamp(num / den, zerof(), set1(1.0f));
    };
    const vf e = set1(exposure), k = set1(255.0f), half = set1(0.5f);
    for (; i + 8 <= i1; i += 8) {
      const vi r = trunc_i(fma(sqrt(aces(loadu(hdr[0] + i) * e)), k, half));
      const vi g = trunc_i(fma(sqrt(aces(loadu(hdr[1] + i) * e)), k, half));
      const vi bb = trunc_i(fma(sqrt(aces(loadu(hdr[2] + i) * e)), k, half));
      storeui(out + i, r | shl<8>(g) | shl<16>(bb) | set1i(int32_t(0xFF000000u)));
    }
    for (; i < i1; ++i) {
      uint32_t px = 0xFF000000u;
      for (int c = 0; c < 3; ++c) {
        const float x = hdr[c][i] * exposure;
        const float y = std::clamp(x * (2.51f * x + 0.03f) / (x * (2.43f * x + 0.59f) + 0.14f), 0.0f, 1.0f);
        px |= uint32_t(std::sqrt(y) * 255.0f + 0.5f) << (8 * c);
      }
      out[i] = px;
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
