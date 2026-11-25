#pragma once
#include <cstdint>
#include <functional>
#include <type_traits>
#include <vector>

#include "simd.hpp"
#include "threadpool.hpp"

namespace jsnow {

// Square, power-of-two RGBA8 texture with a full mip chain (box filtered).
struct Texture {
  int size = 0, log2size = 0, levels = 0;
  std::vector<uint32_t> texels;  // all levels, level 0 first
  alignas(32) int32_t offset[16] = {};
};

// gen(x, y) returns an RGBA8 texel for level 0.
Texture makeTexture(ThreadPool& pool, int size, const std::function<uint32_t(int, int)>& gen);

// All material textures in one allocation so a group of 8 pixels can sample
// a different texture per lane. Every layer has the same size and mip layout.
struct TextureArray {
  int size = 0, log2size = 0, levels = 0, layers = 0;
  int32_t layerStride = 0;
  alignas(32) int32_t offset[16] = {};  // mip level offsets inside a layer
  std::vector<uint32_t> texels;
};
TextureArray makeTextureArray(std::vector<Texture>& textures);  // frees the inputs

// Bilinear filtering inside the nearest mip level (GL_LINEAR_MIPMAP_NEAREST),
// repeat wrapping, 8 lanes with a per-lane layer. u, v in texture repeats;
// lod = log2(level-0 texels per pixel). Returns channels in 0..255.
inline void sampleBilinear(const TextureArray& t, simd::vi layer, simd::vf u, simd::vf v, simd::vf lod,
                           simd::vf& r, simd::vf& g, simd::vf& b) {
  using namespace simd;
  const vi L = mini(maxi(trunc_i(lod + set1(0.5f)), set1i(0)), set1i(t.levels - 1));
  const vi shift = set1i(t.log2size) - L;  // log2 of the level size
  const vi sizeL = shlv(set1i(1), shift);
  const vi maskL = sizeL - set1i(1);
  const vf fs = to_f(sizeL);
  const vf x = fma(u, fs, set1(-0.5f)), y = fma(v, fs, set1(-0.5f));
  const vf fx = floor(x), fy = floor(y);
  const vf ax = x - fx, ay = y - fy;
  const vi ix0 = trunc_i(fx) & maskL, iy0 = trunc_i(fy) & maskL;
  const vi ix1 = (ix0 + set1i(1)) & maskL, iy1 = (iy0 + set1i(1)) & maskL;
  const vi base = gather(t.offset, L) + layer * set1i(t.layerStride);
  const vi row0 = base + shlv(iy0, shift), row1 = base + shlv(iy1, shift);
  const uint32_t* tx = t.texels.data();
  const vi t00 = gather(tx, row0 + ix0), t10 = gather(tx, row0 + ix1);
  const vi t01 = gather(tx, row1 + ix0), t11 = gather(tx, row1 + ix1);
  const vi m8 = set1i(255);
  auto ch = [&](vi a, vi bb, vi c, vi d, auto shiftTag) {
    constexpr int s = decltype(shiftTag)::value;
    const vf c00 = to_f(shr<s>(a) & m8), c10 = to_f(shr<s>(bb) & m8);
    const vf c01 = to_f(shr<s>(c) & m8), c11 = to_f(shr<s>(d) & m8);
    const vf top = fma(ax, c10 - c00, c00), bot = fma(ax, c11 - c01, c01);
    return fma(ay, bot - top, top);
  };
  r = ch(t00, t10, t01, t11, std::integral_constant<int, 0>{});
  g = ch(t00, t10, t01, t11, std::integral_constant<int, 8>{});
  b = ch(t00, t10, t01, t11, std::integral_constant<int, 16>{});
}

}  // namespace jsnow
