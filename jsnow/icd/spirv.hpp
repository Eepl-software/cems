#pragma once
// Minimal SPIR-V interpreter for the JSNOW Vulkan driver.
// Executes 8 invocations at once (vertex shader: 8 vertices; fragment shader:
// a 4x2 pixel block, so derivatives come from neighbouring lanes).
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace spv {

constexpr int L = 8;  // lanes

enum class Kind { Void, Bool, Int, Float, Vector, Matrix, Array, RuntimeArray, Struct, Pointer, Image, Sampler,
                  SampledImage, Function, Unknown };

struct Type {
  Kind kind = Kind::Unknown;
  uint32_t width = 32, sign = 0;
  uint32_t elem = 0;   // vector/matrix/array element type, pointer pointee
  uint32_t count = 0;  // vector size, matrix columns, array length
  std::vector<uint32_t> members;
  uint32_t storage = 0;
  uint32_t comps = 1;  // flattened scalar count
  uint32_t arrayStride = 0;
  // struct member layout decorations
  std::vector<uint32_t> memberOffset, memberMatrixStride;
  std::vector<uint8_t> memberRowMajor;
  std::vector<int32_t> memberBuiltIn;
  bool isFloatScalarBased = false;
};

struct Variable {
  uint32_t id = 0, type = 0, storage = 0;  // type = pointee type
  int location = -1, builtin = -1, binding = -1, set = 0;
  uint32_t initializer = 0;
};

// Description of a sampled image bound to a descriptor.
struct Texture {
  const uint8_t* data = nullptr;
  int width = 0, height = 0, levels = 1;
  std::vector<size_t> levelOffset;
  std::vector<int> levelPitch;  // bytes per row
  int format = 0;               // 0 = RGBA8 unorm, 1 = BGRA8 unorm, 2 = RGBA32F
  bool linear = true;           // mag/min filter
  bool mipLinear = false;
  int addressU = 0, addressV = 0;  // 0 repeat, 1 mirrored repeat, 2 clamp to edge
};

// Bound resources, supplied by the driver for each draw.
struct Resources {
  virtual ~Resources() = default;
  virtual const uint8_t* buffer(int set, int binding) const = 0;
  virtual const Texture* texture(int set, int binding) const = 0;
  const uint8_t* pushConstants = nullptr;
};

class Module;

// Per-thread execution state for one shader stage.
class Invocation {
 public:
  explicit Invocation(const Module& m);
  // Inputs / outputs are flattened scalar components, lane-major: [comp][lane].
  float* input(uint32_t var) { return reinterpret_cast<float*>(storage_[var].data()); }
  const float* output(uint32_t var) const { return reinterpret_cast<const float*>(storage_[var].data()); }
  void run(const Resources& res, uint8_t activeMask = 0xFF);
  uint8_t killed() const { return killed_; }
  std::string error;

 private:
  friend class Module;
  struct Ptr {
    uint32_t var = 0;
    uint32_t type = 0;  // pointee type
    int32_t off[L] = {};  // flattened component (private storage) or byte offset (buffer)
    uint32_t matrixStride = 16;
    bool rowMajor = false;
  };
  bool exec(const Resources& res, uint8_t mask, bool scalarLane, int lane);
  void resetStorage();
  const Module& m_;
  std::vector<std::vector<uint32_t>> val_;      // SSA values [comp*L + lane]
  std::vector<std::vector<uint32_t>> storage_;  // variable storage (private classes)
  std::vector<Ptr> ptr_;
  std::vector<int> isPtr_;
  uint8_t killed_ = 0;
};

class Module {
 public:
  static std::shared_ptr<Module> parse(const uint32_t* words, size_t count, std::string& err);
  // Entry point selection (by name).
  bool select(const std::string& entry);
  uint32_t entryFunction = 0;
  int executionModel = -1;  // 0 vertex, 4 fragment
  std::vector<uint32_t> interfaceVars;
  std::vector<Type> types;  // by id
  std::vector<Variable> vars;  // by id (id == 0: none)
  std::vector<uint8_t> isVar;
  std::vector<std::vector<uint32_t>> constVal;  // constants, flattened, scalar (no lanes)
  std::vector<uint8_t> isConst;
  std::vector<uint32_t> resultType;  // by id
  struct Inst {
    uint16_t op, wc;
    uint32_t at;  // index into words
  };
  std::vector<uint32_t> words;
  std::vector<Inst> insts;
  std::vector<int32_t> labelInst;     // label id -> instruction index
  std::vector<int32_t> functionInst;  // function id -> instruction index of OpFunction
  uint32_t bound = 0;
  uint32_t glslExt = 0;
  // Helpers for the driver.
  int findBuiltinOutputComp(int builtin, uint32_t& var) const;  // returns component offset
  std::vector<std::pair<int, uint32_t>> locationVars(uint32_t storage) const;  // (location, var id)
  int findBuiltinInput(int builtin) const;
  std::vector<std::string> unsupported;  // opcodes seen at parse time that exec() does not handle

 private:
  void computeComps(uint32_t id);
};

}  // namespace spv
