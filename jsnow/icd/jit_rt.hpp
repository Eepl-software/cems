#pragma once
// Interface between JIT-compiled shaders and the JSNOW driver. Generated code
// only sees this header and simd.hpp; everything else is reached through the
// function table (the driver is loaded RTLD_LOCAL, so its symbols are not
// visible to the dlopen'ed shader libraries).
#include <cstdint>

namespace jsnow_jit {

struct Ctx;
struct RT {
  const uint8_t* (*buffer)(const Ctx*, int set, int binding);
  // Texture sampling for 8 lanes. coord: [ncoord][8] float bits. lod: [8] or null
  // (implicit LOD from the 4x2 lane block). ref: [8] or null (depth compare).
  void (*sample)(const Ctx*, int set, int binding, const uint32_t* coord, int ncoord, const uint32_t* lod,
                 const uint32_t* ref, uint32_t* out /*[4][8]*/);
  void (*imageRead)(const Ctx*, int set, int binding, const uint32_t* coord, int ncoord, uint32_t* out /*[4][8]*/);
  void (*imageWrite)(const Ctx*, int set, int binding, const uint32_t* coord, int ncoord, const uint32_t* texel,
                     int ntexel, uint32_t laneMask);
  void (*querySize)(const Ctx*, int set, int binding, int lod, uint32_t* out /*[3]*/, int* levels);
  uint32_t (*atomic)(int op, uint32_t* addr, uint32_t a, uint32_t b);
  void (*matrixInverse)(const uint32_t* in, uint32_t* out, int n, int lanes);  // [n*n][8]
};

struct Ctx {
  uint32_t* const* storage;  // per SPIR-V variable id: [component][8 lanes]
  const void* res;           // spv::Resources
  const RT* rt;
  const uint8_t* push;
  const int32_t* fragX;
  const int32_t* fragY;
  uint32_t active;  // lane mask on entry
  uint32_t killed;  // lane mask written by the shader (OpKill)
};

typedef void (*ShaderFn)(Ctx*);

}  // namespace jsnow_jit
