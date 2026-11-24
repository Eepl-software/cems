#include "png.hpp"

#include <algorithm>
#include <cstdio>
#include <vector>
#ifdef JSNOW_HAVE_ZLIB
#include <zlib.h>
#endif

namespace jsnow {

namespace {
uint32_t crcTable[256];
void initCrc() {
  for (uint32_t n = 0; n < 256; ++n) {
    uint32_t c = n;
    for (int k = 0; k < 8; ++k) c = (c & 1) ? 0xEDB88320u ^ (c >> 1) : c >> 1;
    crcTable[n] = c;
  }
}
uint32_t crc(const uint8_t* p, size_t n, uint32_t c = 0xFFFFFFFFu) {
  for (size_t i = 0; i < n; ++i) c = crcTable[(c ^ p[i]) & 0xFF] ^ (c >> 8);
  return c;
}
void put32(std::vector<uint8_t>& v, uint32_t x) {
  for (int s = 24; s >= 0; s -= 8) v.push_back(uint8_t(x >> s));
}
void chunk(std::vector<uint8_t>& out, const char* type, const std::vector<uint8_t>& data) {
  put32(out, uint32_t(data.size()));
  size_t start = out.size();
  out.insert(out.end(), type, type + 4);
  out.insert(out.end(), data.begin(), data.end());
  put32(out, crc(out.data() + start, out.size() - start) ^ 0xFFFFFFFFu);
}

// zlib stream made of uncompressed (stored) deflate blocks: no dependency.
[[maybe_unused]] std::vector<uint8_t> zlibStored(const std::vector<uint8_t>& raw) {
  std::vector<uint8_t> z = {0x78, 0x01};
  size_t pos = 0;
  do {
    size_t len = std::min<size_t>(65535, raw.size() - pos);
    bool last = pos + len == raw.size();
    z.push_back(last ? 1 : 0);
    z.push_back(uint8_t(len)); z.push_back(uint8_t(len >> 8));
    z.push_back(uint8_t(~len)); z.push_back(uint8_t(~len >> 8));
    z.insert(z.end(), raw.begin() + pos, raw.begin() + pos + len);
    pos += len;
  } while (pos < raw.size());
  uint32_t a = 1, b = 0;
  for (uint8_t c : raw) { a = (a + c) % 65521; b = (b + a) % 65521; }
  put32(z, (b << 16) | a);
  return z;
}
}  // namespace

bool writePNG(const std::string& path, int w, int h, const uint32_t* rgba) {
  initCrc();
  std::vector<uint8_t> raw;
  raw.reserve(size_t(h) * (1 + 3 * size_t(w)));
  for (int y = 0; y < h; ++y) {
    raw.push_back(0);  // filter: none
    for (int x = 0; x < w; ++x) {
      uint32_t p = rgba[size_t(y) * w + x];
      raw.push_back(uint8_t(p)); raw.push_back(uint8_t(p >> 8)); raw.push_back(uint8_t(p >> 16));
    }
  }
  std::vector<uint8_t> idat;
#ifdef JSNOW_HAVE_ZLIB
  uLongf len = compressBound(uLong(raw.size()));
  idat.resize(len);
  if (compress2(idat.data(), &len, raw.data(), uLong(raw.size()), 6) != Z_OK) return false;
  idat.resize(len);
#else
  idat = zlibStored(raw);
#endif
  std::vector<uint8_t> out = {0x89, 'P', 'N', 'G', '\r', '\n', 0x1A, '\n'};
  std::vector<uint8_t> ihdr;
  put32(ihdr, uint32_t(w)); put32(ihdr, uint32_t(h));
  ihdr.insert(ihdr.end(), {8, 2, 0, 0, 0});  // 8-bit RGB
  chunk(out, "IHDR", ihdr);
  chunk(out, "IDAT", idat);
  chunk(out, "IEND", {});
  FILE* f = std::fopen(path.c_str(), "wb");
  if (!f) return false;
  bool ok = std::fwrite(out.data(), 1, out.size(), f) == out.size();
  return std::fclose(f) == 0 && ok;
}

}  // namespace jsnow
