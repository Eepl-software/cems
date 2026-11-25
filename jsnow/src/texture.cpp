#include "texture.hpp"

#include <algorithm>

namespace jsnow {

Texture makeTexture(ThreadPool& pool, int size, const std::function<uint32_t(int, int)>& gen) {
  Texture t;
  t.size = size;
  while ((1 << t.log2size) < size) ++t.log2size;
  t.levels = t.log2size + 1;
  size_t total = 0;
  for (int l = 0; l < t.levels; ++l) {
    t.offset[l] = int32_t(total);
    total += size_t(size >> l) * size_t(size >> l);
  }
  t.texels.resize(total);
  uint32_t* L0 = t.texels.data();
  pool.run(size, [&](int y, int) {
    for (int x = 0; x < size; ++x) L0[size_t(y) * size + x] = gen(x, y);
  });
  for (int l = 1; l < t.levels; ++l) {
    const int s = size >> l, ps = s * 2;
    const uint32_t* src = t.texels.data() + t.offset[l - 1];
    uint32_t* dst = t.texels.data() + t.offset[l];
    pool.run(s, [&](int y, int) {
      for (int x = 0; x < s; ++x) {
        const uint32_t p[4] = {src[(2 * y) * ps + 2 * x], src[(2 * y) * ps + 2 * x + 1],
                               src[(2 * y + 1) * ps + 2 * x], src[(2 * y + 1) * ps + 2 * x + 1]};
        uint32_t out = 0;
        for (int c = 0; c < 32; c += 8) {
          uint32_t sum = 2;
          for (uint32_t q : p) sum += (q >> c) & 255u;
          out |= (sum >> 2) << c;
        }
        dst[y * s + x] = out;
      }
    });
  }
  return t;
}

}  // namespace jsnow
