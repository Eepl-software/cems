#pragma once
// SPIR-V -> native SIMD compiler (generates C++ over simd.hpp, compiles it with the
// system C++ compiler, caches the .so on disk and dlopens it).
#include <string>

#include "jit_rt.hpp"

namespace spv { class Module; }

namespace jit {
// C++ source for the module's selected entry point, or "" with err set.
std::string generate(const spv::Module& m, std::string& err);
// Compiled entry point (cached), or nullptr with err set.
jsnow_jit::ShaderFn compile(const spv::Module& m, std::string& err);
// Runtime function table implemented by the driver.
const jsnow_jit::RT* runtime();
}  // namespace jit
