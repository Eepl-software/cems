#pragma once
#include <cstdint>
#include <string>

namespace jsnow {
// Writes an RGBA8 buffer (R in the lowest byte) as an 8-bit RGB PNG.
bool writePNG(const std::string& path, int w, int h, const uint32_t* rgba);
}
