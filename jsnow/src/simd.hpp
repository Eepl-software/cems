#pragma once
// 8-lane SIMD wrapper. Every kernel in JSNOW is written once against these
// types; the backend is chosen at compile time:
//   AVX2+FMA  -> one 256-bit register per value
//   NEON      -> two 128-bit registers per value (AArch64 / Apple Silicon)
//   otherwise -> plain arrays (portable reference)
#include <cstdint>
#include <cstring>

#if defined(__AVX2__) && defined(__FMA__) && !defined(JSNOW_FORCE_SCALAR)
#define JSNOW_SIMD_AVX2 1
#include <immintrin.h>
#elif (defined(__ARM_NEON) || defined(__ARM_NEON__)) && defined(__aarch64__) && !defined(JSNOW_FORCE_SCALAR)
#define JSNOW_SIMD_NEON 1
#include <arm_neon.h>
#else
#define JSNOW_SIMD_SCALAR 1
#include <cmath>
#endif

namespace jsnow::simd {

constexpr int kLanes = 8;

#if defined(JSNOW_SIMD_AVX2)
inline const char* backendName() { return "AVX2+FMA"; }
struct vf { __m256 v; };
struct vi { __m256i v; };
struct vm { __m256 v; };  // all-ones / all-zeros lanes

inline vf set1(float a) { return {_mm256_set1_ps(a)}; }
inline vf zerof() { return {_mm256_setzero_ps()}; }
inline vf load(const float* p) { return {_mm256_load_ps(p)}; }
inline vf loadu(const float* p) { return {_mm256_loadu_ps(p)}; }
inline void store(float* p, vf a) { _mm256_store_ps(p, a.v); }
inline void storeu(float* p, vf a) { _mm256_storeu_ps(p, a.v); }
inline vf iotaf() { return {_mm256_setr_ps(0, 1, 2, 3, 4, 5, 6, 7)}; }
inline vf operator+(vf a, vf b) { return {_mm256_add_ps(a.v, b.v)}; }
inline vf operator-(vf a, vf b) { return {_mm256_sub_ps(a.v, b.v)}; }
inline vf operator*(vf a, vf b) { return {_mm256_mul_ps(a.v, b.v)}; }
inline vf operator/(vf a, vf b) { return {_mm256_div_ps(a.v, b.v)}; }
inline vf fma(vf a, vf b, vf c) { return {_mm256_fmadd_ps(a.v, b.v, c.v)}; }   // a*b+c
inline vf fnma(vf a, vf b, vf c) { return {_mm256_fnmadd_ps(a.v, b.v, c.v)}; } // c-a*b
inline vf min(vf a, vf b) { return {_mm256_min_ps(a.v, b.v)}; }
inline vf max(vf a, vf b) { return {_mm256_max_ps(a.v, b.v)}; }
inline vf sqrt(vf a) { return {_mm256_sqrt_ps(a.v)}; }
inline vf rsqrt_fast(vf a) { return {_mm256_rsqrt_ps(a.v)}; }
inline vf rcp_fast(vf a) { return {_mm256_rcp_ps(a.v)}; }
inline vf floor(vf a) { return {_mm256_floor_ps(a.v)}; }
inline vf abs(vf a) { return {_mm256_and_ps(a.v, _mm256_castsi256_ps(_mm256_set1_epi32(0x7FFFFFFF)))}; }
inline vm operator>(vf a, vf b) { return {_mm256_cmp_ps(a.v, b.v, _CMP_GT_OQ)}; }
inline vm operator>=(vf a, vf b) { return {_mm256_cmp_ps(a.v, b.v, _CMP_GE_OQ)}; }
inline vm operator<(vf a, vf b) { return {_mm256_cmp_ps(a.v, b.v, _CMP_LT_OQ)}; }
inline vm operator<=(vf a, vf b) { return {_mm256_cmp_ps(a.v, b.v, _CMP_LE_OQ)}; }
inline vm operator&(vm a, vm b) { return {_mm256_and_ps(a.v, b.v)}; }
inline vm operator|(vm a, vm b) { return {_mm256_or_ps(a.v, b.v)}; }
inline vm andnot(vm a, vm b) { return {_mm256_andnot_ps(a.v, b.v)}; }  // ~a & b
inline int bits(vm m) { return _mm256_movemask_ps(m.v); }
inline vm alltrue() { return {_mm256_castsi256_ps(_mm256_set1_epi32(-1))}; }
inline vm signmask(vf a) { return {_mm256_castsi256_ps(_mm256_srai_epi32(_mm256_castps_si256(a.v), 31))}; }
inline vf select(vm m, vf a, vf b) { return {_mm256_blendv_ps(b.v, a.v, m.v)}; }
inline vf maskf(vm m, vf a) { return {_mm256_and_ps(m.v, a.v)}; }

inline vi set1i(int32_t a) { return {_mm256_set1_epi32(a)}; }
inline vi loadi(const void* p) { return {_mm256_load_si256(static_cast<const __m256i*>(p))}; }
inline vi loadui(const void* p) { return {_mm256_loadu_si256(static_cast<const __m256i*>(p))}; }
inline void storei(void* p, vi a) { _mm256_store_si256(static_cast<__m256i*>(p), a.v); }
inline void storeui(void* p, vi a) { _mm256_storeu_si256(static_cast<__m256i*>(p), a.v); }
inline vi iotai() { return {_mm256_setr_epi32(0, 1, 2, 3, 4, 5, 6, 7)}; }
inline vi operator+(vi a, vi b) { return {_mm256_add_epi32(a.v, b.v)}; }
inline vi operator-(vi a, vi b) { return {_mm256_sub_epi32(a.v, b.v)}; }
inline vi operator*(vi a, vi b) { return {_mm256_mullo_epi32(a.v, b.v)}; }
inline vi operator&(vi a, vi b) { return {_mm256_and_si256(a.v, b.v)}; }
inline vi operator|(vi a, vi b) { return {_mm256_or_si256(a.v, b.v)}; }
template <int n> inline vi shl(vi a) { return {_mm256_slli_epi32(a.v, n)}; }
template <int n> inline vi shr(vi a) { return {_mm256_srli_epi32(a.v, n)}; }
inline vi shlv(vi a, vi n) { return {_mm256_sllv_epi32(a.v, n.v)}; }
inline vi shrv(vi a, vi n) { return {_mm256_srlv_epi32(a.v, n.v)}; }
inline vi mini(vi a, vi b) { return {_mm256_min_epi32(a.v, b.v)}; }
inline vm cmpeq(vi a, vi b) { return {_mm256_castsi256_ps(_mm256_cmpeq_epi32(a.v, b.v))}; }
// Per-byte unsigned ops on packed RGBA8.
inline vi minu8(vi a, vi b) { return {_mm256_min_epu8(a.v, b.v)}; }
inline vi maxu8(vi a, vi b) { return {_mm256_max_epu8(a.v, b.v)}; }
inline vi avgu8(vi a, vi b) { return {_mm256_avg_epu8(a.v, b.v)}; }  // (a+b+1)>>1
inline vi maxi(vi a, vi b) { return {_mm256_max_epi32(a.v, b.v)}; }
inline vi trunc_i(vf a) { return {_mm256_cvttps_epi32(a.v)}; }
inline vf to_f(vi a) { return {_mm256_cvtepi32_ps(a.v)}; }
inline vi as_i(vf a) { return {_mm256_castps_si256(a.v)}; }
inline vf as_f(vi a) { return {_mm256_castsi256_ps(a.v)}; }
inline vi as_i(vm a) { return {_mm256_castps_si256(a.v)}; }
inline vi selecti(vm m, vi a, vi b) {
  return {_mm256_castps_si256(_mm256_blendv_ps(_mm256_castsi256_ps(b.v), _mm256_castsi256_ps(a.v), m.v))};
}
inline void lanes(vi a, int32_t* out) { _mm256_storeu_si256(reinterpret_cast<__m256i*>(out), a.v); }
inline vi fromLanes(const int32_t* l) { return {_mm256_loadu_si256(reinterpret_cast<const __m256i*>(l))}; }

#elif defined(JSNOW_SIMD_NEON)
inline const char* backendName() { return "NEON"; }
struct vf { float32x4_t a, b; };
struct vi { int32x4_t a, b; };
struct vm { uint32x4_t a, b; };

inline vf set1(float x) { return {vdupq_n_f32(x), vdupq_n_f32(x)}; }
inline vf zerof() { return set1(0.0f); }
inline vf load(const float* p) { return {vld1q_f32(p), vld1q_f32(p + 4)}; }
inline vf loadu(const float* p) { return load(p); }
inline void store(float* p, vf x) { vst1q_f32(p, x.a); vst1q_f32(p + 4, x.b); }
inline void storeu(float* p, vf x) { store(p, x); }
inline vf iotaf() {
  static const float k[8] = {0, 1, 2, 3, 4, 5, 6, 7};
  return load(k);
}
#define JSNOW_F2(op) {op(x.a, y.a), op(x.b, y.b)}
inline vf operator+(vf x, vf y) { return JSNOW_F2(vaddq_f32); }
inline vf operator-(vf x, vf y) { return JSNOW_F2(vsubq_f32); }
inline vf operator*(vf x, vf y) { return JSNOW_F2(vmulq_f32); }
inline vf operator/(vf x, vf y) { return JSNOW_F2(vdivq_f32); }
inline vf fma(vf x, vf y, vf z) { return {vfmaq_f32(z.a, x.a, y.a), vfmaq_f32(z.b, x.b, y.b)}; }
inline vf fnma(vf x, vf y, vf z) { return {vfmsq_f32(z.a, x.a, y.a), vfmsq_f32(z.b, x.b, y.b)}; }
inline vf min(vf x, vf y) { return JSNOW_F2(vminq_f32); }
inline vf max(vf x, vf y) { return JSNOW_F2(vmaxq_f32); }
inline vf sqrt(vf x) { return {vsqrtq_f32(x.a), vsqrtq_f32(x.b)}; }
inline vf rsqrt_fast(vf x) {
  float32x4_t ea = vrsqrteq_f32(x.a), eb = vrsqrteq_f32(x.b);
  ea = vmulq_f32(ea, vrsqrtsq_f32(vmulq_f32(x.a, ea), ea));  // one step: ~12 bits like rsqrtps
  eb = vmulq_f32(eb, vrsqrtsq_f32(vmulq_f32(x.b, eb), eb));
  return {ea, eb};
}
inline vf rcp_fast(vf x) {
  float32x4_t ea = vrecpeq_f32(x.a), eb = vrecpeq_f32(x.b);
  ea = vmulq_f32(ea, vrecpsq_f32(x.a, ea));
  eb = vmulq_f32(eb, vrecpsq_f32(x.b, eb));
  return {ea, eb};
}
inline vf floor(vf x) { return {vrndmq_f32(x.a), vrndmq_f32(x.b)}; }
inline vf abs(vf x) { return {vabsq_f32(x.a), vabsq_f32(x.b)}; }
inline vm operator>(vf x, vf y) { return JSNOW_F2(vcgtq_f32); }
inline vm operator>=(vf x, vf y) { return JSNOW_F2(vcgeq_f32); }
inline vm operator<(vf x, vf y) { return JSNOW_F2(vcltq_f32); }
inline vm operator<=(vf x, vf y) { return JSNOW_F2(vcleq_f32); }
inline vm operator&(vm x, vm y) { return JSNOW_F2(vandq_u32); }
inline vm operator|(vm x, vm y) { return JSNOW_F2(vorrq_u32); }
inline vm andnot(vm x, vm y) { return {vbicq_u32(y.a, x.a), vbicq_u32(y.b, x.b)}; }
inline vm alltrue() { return {vdupq_n_u32(~0u), vdupq_n_u32(~0u)}; }
inline int bits(vm m) {
  static const int32_t sh[4] = {0, 1, 2, 3};
  const int32x4_t s = vld1q_s32(sh);
  uint32x4_t la = vshlq_u32(vshrq_n_u32(m.a, 31), s);
  uint32x4_t lb = vshlq_u32(vshrq_n_u32(m.b, 31), s);
  return int(vaddvq_u32(la) | (vaddvq_u32(lb) << 4));
}
inline vm signmask(vf x) {
  return {vreinterpretq_u32_s32(vshrq_n_s32(vreinterpretq_s32_f32(x.a), 31)),
          vreinterpretq_u32_s32(vshrq_n_s32(vreinterpretq_s32_f32(x.b), 31))};
}
inline vf select(vm m, vf x, vf y) { return {vbslq_f32(m.a, x.a, y.a), vbslq_f32(m.b, x.b, y.b)}; }
inline vf maskf(vm m, vf x) { return select(m, x, zerof()); }

inline vi set1i(int32_t x) { return {vdupq_n_s32(x), vdupq_n_s32(x)}; }
inline vi loadi(const void* p) {
  const int32_t* q = static_cast<const int32_t*>(p);
  return {vld1q_s32(q), vld1q_s32(q + 4)};
}
inline vi loadui(const void* p) { return loadi(p); }
inline void storei(void* p, vi x) {
  int32_t* q = static_cast<int32_t*>(p);
  vst1q_s32(q, x.a); vst1q_s32(q + 4, x.b);
}
inline void storeui(void* p, vi x) { storei(p, x); }
inline vi iotai() {
  static const int32_t k[8] = {0, 1, 2, 3, 4, 5, 6, 7};
  return loadi(k);
}
inline vi operator+(vi x, vi y) { return JSNOW_F2(vaddq_s32); }
inline vi operator-(vi x, vi y) { return JSNOW_F2(vsubq_s32); }
inline vi operator*(vi x, vi y) { return JSNOW_F2(vmulq_s32); }
inline vi operator&(vi x, vi y) { return JSNOW_F2(vandq_s32); }
inline vi operator|(vi x, vi y) { return JSNOW_F2(vorrq_s32); }
template <int n> inline vi shl(vi x) { return {vshlq_n_s32(x.a, n), vshlq_n_s32(x.b, n)}; }
template <int n> inline vi shr(vi x) {
  return {vreinterpretq_s32_u32(vshrq_n_u32(vreinterpretq_u32_s32(x.a), n)),
          vreinterpretq_s32_u32(vshrq_n_u32(vreinterpretq_u32_s32(x.b), n))};
}
inline vi shlv(vi x, vi n) {
  return {vreinterpretq_s32_u32(vshlq_u32(vreinterpretq_u32_s32(x.a), n.a)),
          vreinterpretq_s32_u32(vshlq_u32(vreinterpretq_u32_s32(x.b), n.b))};
}
inline vi shrv(vi x, vi n) {
  return {vreinterpretq_s32_u32(vshlq_u32(vreinterpretq_u32_s32(x.a), vnegq_s32(n.a))),
          vreinterpretq_s32_u32(vshlq_u32(vreinterpretq_u32_s32(x.b), vnegq_s32(n.b)))};
}
inline vi mini(vi x, vi y) { return JSNOW_F2(vminq_s32); }
inline vm cmpeq(vi x, vi y) { return JSNOW_F2(vceqq_s32); }
#define JSNOW_U8(op)                                                                      \
  {vreinterpretq_s32_u8(op(vreinterpretq_u8_s32(x.a), vreinterpretq_u8_s32(y.a))),     \
   vreinterpretq_s32_u8(op(vreinterpretq_u8_s32(x.b), vreinterpretq_u8_s32(y.b)))}
inline vi minu8(vi x, vi y) { return JSNOW_U8(vminq_u8); }
inline vi maxu8(vi x, vi y) { return JSNOW_U8(vmaxq_u8); }
inline vi avgu8(vi x, vi y) { return JSNOW_U8(vrhaddq_u8); }
#undef JSNOW_U8
inline vi maxi(vi x, vi y) { return JSNOW_F2(vmaxq_s32); }
inline vi trunc_i(vf x) { return {vcvtq_s32_f32(x.a), vcvtq_s32_f32(x.b)}; }
inline vf to_f(vi x) { return {vcvtq_f32_s32(x.a), vcvtq_f32_s32(x.b)}; }
inline vi as_i(vf x) { return {vreinterpretq_s32_f32(x.a), vreinterpretq_s32_f32(x.b)}; }
inline vf as_f(vi x) { return {vreinterpretq_f32_s32(x.a), vreinterpretq_f32_s32(x.b)}; }
inline vi as_i(vm x) { return {vreinterpretq_s32_u32(x.a), vreinterpretq_s32_u32(x.b)}; }
inline vi selecti(vm m, vi x, vi y) { return {vbslq_s32(m.a, x.a, y.a), vbslq_s32(m.b, x.b, y.b)}; }
inline void lanes(vi x, int32_t* out) { storei(out, x); }
inline vi fromLanes(const int32_t* l) { return loadi(l); }
#undef JSNOW_F2

#else  // scalar reference backend
inline const char* backendName() { return "scalar"; }
struct vf { float l[8]; };
struct vi { int32_t l[8]; };
struct vm { uint32_t l[8]; };
#define JSNOW_MAP(T, expr) T r; for (int i = 0; i < 8; ++i) r.l[i] = (expr); return r
inline vf set1(float a) { JSNOW_MAP(vf, a); }
inline vf zerof() { return set1(0.0f); }
inline vf load(const float* p) { vf r; std::memcpy(r.l, p, 32); return r; }
inline vf loadu(const float* p) { return load(p); }
inline void store(float* p, vf a) { std::memcpy(p, a.l, 32); }
inline void storeu(float* p, vf a) { store(p, a); }
inline vf iotaf() { JSNOW_MAP(vf, float(i)); }
inline vf operator+(vf a, vf b) { JSNOW_MAP(vf, a.l[i] + b.l[i]); }
inline vf operator-(vf a, vf b) { JSNOW_MAP(vf, a.l[i] - b.l[i]); }
inline vf operator*(vf a, vf b) { JSNOW_MAP(vf, a.l[i] * b.l[i]); }
inline vf operator/(vf a, vf b) { JSNOW_MAP(vf, a.l[i] / b.l[i]); }
inline vf fma(vf a, vf b, vf c) { JSNOW_MAP(vf, a.l[i] * b.l[i] + c.l[i]); }
inline vf fnma(vf a, vf b, vf c) { JSNOW_MAP(vf, c.l[i] - a.l[i] * b.l[i]); }
inline vf min(vf a, vf b) { JSNOW_MAP(vf, a.l[i] < b.l[i] ? a.l[i] : b.l[i]); }
inline vf max(vf a, vf b) { JSNOW_MAP(vf, a.l[i] > b.l[i] ? a.l[i] : b.l[i]); }
inline vf sqrt(vf a) { JSNOW_MAP(vf, std::sqrt(a.l[i])); }
inline vf rsqrt_fast(vf a) { JSNOW_MAP(vf, 1.0f / std::sqrt(a.l[i])); }
inline vf rcp_fast(vf a) { JSNOW_MAP(vf, 1.0f / a.l[i]); }
inline vf floor(vf a) { JSNOW_MAP(vf, std::floor(a.l[i])); }
inline vf abs(vf a) { JSNOW_MAP(vf, std::fabs(a.l[i])); }
inline vm operator>(vf a, vf b) { JSNOW_MAP(vm, a.l[i] > b.l[i] ? ~0u : 0u); }
inline vm operator>=(vf a, vf b) { JSNOW_MAP(vm, a.l[i] >= b.l[i] ? ~0u : 0u); }
inline vm operator<(vf a, vf b) { JSNOW_MAP(vm, a.l[i] < b.l[i] ? ~0u : 0u); }
inline vm operator<=(vf a, vf b) { JSNOW_MAP(vm, a.l[i] <= b.l[i] ? ~0u : 0u); }
inline vm operator&(vm a, vm b) { JSNOW_MAP(vm, a.l[i] & b.l[i]); }
inline vm operator|(vm a, vm b) { JSNOW_MAP(vm, a.l[i] | b.l[i]); }
inline vm andnot(vm a, vm b) { JSNOW_MAP(vm, ~a.l[i] & b.l[i]); }
inline vm alltrue() { JSNOW_MAP(vm, ~0u); }
inline int bits(vm m) { int r = 0; for (int i = 0; i < 8; ++i) r |= int(m.l[i] >> 31) << i; return r; }
inline vm signmask(vf a) {
  vm r;
  for (int i = 0; i < 8; ++i) { uint32_t u; std::memcpy(&u, &a.l[i], 4); r.l[i] = (u >> 31) ? ~0u : 0u; }
  return r;
}
inline vf select(vm m, vf a, vf b) { JSNOW_MAP(vf, (m.l[i] >> 31) ? a.l[i] : b.l[i]); }
inline vf maskf(vm m, vf a) { return select(m, a, zerof()); }
inline vi set1i(int32_t a) { JSNOW_MAP(vi, a); }
inline vi loadi(const void* p) { vi r; std::memcpy(r.l, p, 32); return r; }
inline vi loadui(const void* p) { return loadi(p); }
inline void storei(void* p, vi a) { std::memcpy(p, a.l, 32); }
inline void storeui(void* p, vi a) { storei(p, a); }
inline vi iotai() { JSNOW_MAP(vi, i); }
inline vi operator+(vi a, vi b) { JSNOW_MAP(vi, int32_t(uint32_t(a.l[i]) + uint32_t(b.l[i]))); }
inline vi operator-(vi a, vi b) { JSNOW_MAP(vi, int32_t(uint32_t(a.l[i]) - uint32_t(b.l[i]))); }
inline vi operator*(vi a, vi b) { JSNOW_MAP(vi, int32_t(uint32_t(a.l[i]) * uint32_t(b.l[i]))); }
inline vi operator&(vi a, vi b) { JSNOW_MAP(vi, a.l[i] & b.l[i]); }
inline vi operator|(vi a, vi b) { JSNOW_MAP(vi, a.l[i] | b.l[i]); }
template <int n> inline vi shl(vi a) { JSNOW_MAP(vi, int32_t(uint32_t(a.l[i]) << n)); }
template <int n> inline vi shr(vi a) { JSNOW_MAP(vi, int32_t(uint32_t(a.l[i]) >> n)); }
inline vi shlv(vi a, vi n) { JSNOW_MAP(vi, n.l[i] > 31 ? 0 : int32_t(uint32_t(a.l[i]) << n.l[i])); }
inline vi shrv(vi a, vi n) { JSNOW_MAP(vi, n.l[i] > 31 ? 0 : int32_t(uint32_t(a.l[i]) >> n.l[i])); }
inline vi mini(vi a, vi b) { JSNOW_MAP(vi, a.l[i] < b.l[i] ? a.l[i] : b.l[i]); }
inline vm cmpeq(vi a, vi b) { JSNOW_MAP(vm, a.l[i] == b.l[i] ? ~0u : 0u); }
template <class F> inline vi bytewise(vi a, vi b, F f) {
  vi r;
  for (int i = 0; i < 8; ++i) {
    uint32_t o = 0;
    for (int k = 0; k < 32; k += 8) o |= uint32_t(f((uint32_t(a.l[i]) >> k) & 255u, (uint32_t(b.l[i]) >> k) & 255u)) << k;
    r.l[i] = int32_t(o);
  }
  return r;
}
inline vi minu8(vi a, vi b) { return bytewise(a, b, [](uint32_t x, uint32_t y) { return x < y ? x : y; }); }
inline vi maxu8(vi a, vi b) { return bytewise(a, b, [](uint32_t x, uint32_t y) { return x > y ? x : y; }); }
inline vi avgu8(vi a, vi b) { return bytewise(a, b, [](uint32_t x, uint32_t y) { return (x + y + 1) >> 1; }); }
inline vi maxi(vi a, vi b) { JSNOW_MAP(vi, a.l[i] > b.l[i] ? a.l[i] : b.l[i]); }
inline vi trunc_i(vf a) {
  JSNOW_MAP(vi, (a.l[i] > -2147483648.0f && a.l[i] < 2147483648.0f) ? int32_t(a.l[i]) : INT32_MIN);
}
inline vf to_f(vi a) { JSNOW_MAP(vf, float(a.l[i])); }
inline vi as_i(vf a) { vi r; std::memcpy(r.l, a.l, 32); return r; }
inline vf as_f(vi a) { vf r; std::memcpy(r.l, a.l, 32); return r; }
inline vi as_i(vm a) { vi r; std::memcpy(r.l, a.l, 32); return r; }
inline vi selecti(vm m, vi a, vi b) { JSNOW_MAP(vi, (m.l[i] >> 31) ? a.l[i] : b.l[i]); }
inline void lanes(vi a, int32_t* out) { std::memcpy(out, a.l, 32); }
inline vi fromLanes(const int32_t* l) { return loadi(l); }
#undef JSNOW_MAP
#endif

// ---- helpers shared by all backends ----
inline vf rcp(vf a) {  // ~23-bit reciprocal: estimate + Newton step
  vf r = rcp_fast(a);
  return r * fnma(a, r, set1(2.0f));
}
inline vf rsqrt(vf a) {  // ~23-bit: estimate + Newton step
  vf r = rsqrt_fast(a);
  return r * fnma(set1(0.5f) * a, r * r, set1(1.5f));
}
inline vf clamp(vf a, vf lo, vf hi) { return min(max(a, lo), hi); }
inline vm operator~(vm a) { return andnot(a, alltrue()); }
// Lane-wise 32-bit loads from base[idx] (manual "gather": faster than vpgather
// on many x86 parts and the only option on NEON).
inline vi gather(const void* base, vi idx) {
#if defined(JSNOW_SIMD_AVX2) && defined(JSNOW_HW_GATHER)
  return {_mm256_i32gather_epi32(static_cast<const int*>(base), idx.v, 4)};
#endif
  alignas(32) int32_t i[8], r[8];
  lanes(idx, i);
  const int32_t* b = static_cast<const int32_t*>(base);
  for (int k = 0; k < 8; ++k) r[k] = b[i[k]];
  return fromLanes(r);
}
inline vf gatherf(const float* base, vi idx) { return as_f(gather(base, idx)); }
// Approximate log2 for x > 0 (max error ~0.09): exponent + linear mantissa.
inline vf log2_fast(vf x) {
  vi b = as_i(x);
  vf e = to_f(shr<23>(b) & set1i(255)) - set1(127.0f);
  vf m = as_f((b & set1i(0x007FFFFF)) | set1i(0x3F800000));  // [1,2)
  return e + (m - set1(1.0f));
}

}  // namespace jsnow::simd
