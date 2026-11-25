#include "spirv.hpp"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <map>

namespace spv {

namespace {
// Opcodes (SPIR-V 1.x)
enum Op : uint16_t {
  OpUndef = 1, OpName = 5, OpMemberName = 6, OpExtInstImport = 11, OpExtInst = 12, OpEntryPoint = 15,
  OpExecutionMode = 16, OpTypeVoid = 19, OpTypeBool = 20, OpTypeInt = 21, OpTypeFloat = 22, OpTypeVector = 23,
  OpTypeMatrix = 24, OpTypeImage = 25, OpTypeSampler = 26, OpTypeSampledImage = 27, OpTypeArray = 28,
  OpTypeRuntimeArray = 29, OpTypeStruct = 30, OpTypePointer = 32, OpTypeFunction = 33, OpConstantTrue = 41,
  OpConstantFalse = 42, OpConstant = 43, OpConstantComposite = 44, OpConstantNull = 46, OpSpecConstantTrue = 48,
  OpSpecConstantFalse = 49, OpSpecConstant = 50, OpSpecConstantComposite = 51, OpFunction = 54,
  OpFunctionParameter = 55, OpFunctionEnd = 56, OpFunctionCall = 57, OpVariable = 59, OpLoad = 61, OpStore = 62,
  OpCopyMemory = 63, OpAccessChain = 65, OpInBoundsAccessChain = 66, OpDecorate = 71, OpMemberDecorate = 72,
  OpVectorExtractDynamic = 77, OpVectorInsertDynamic = 78, OpVectorShuffle = 79, OpCompositeConstruct = 80,
  OpCompositeExtract = 81, OpCompositeInsert = 82, OpCopyObject = 83, OpTranspose = 84, OpSampledImage = 86,
  OpImageSampleImplicitLod = 87, OpImageSampleExplicitLod = 88, OpImageSampleDrefImplicitLod = 89,
  OpImageSampleDrefExplicitLod = 90, OpImageFetch = 95, OpImage = 100, OpImageQuerySizeLod = 103,
  OpImageQuerySize = 104, OpImageQueryLevels = 106,
  OpConvertFToU = 109, OpConvertFToS = 110, OpConvertSToF = 111, OpConvertUToF = 112, OpUConvert = 113,
  OpSConvert = 114, OpFConvert = 115, OpBitcast = 124, OpSNegate = 126, OpFNegate = 127, OpIAdd = 128,
  OpFAdd = 129, OpISub = 130, OpFSub = 131, OpIMul = 132, OpFMul = 133, OpUDiv = 134, OpSDiv = 135, OpFDiv = 136,
  OpUMod = 137, OpSRem = 138, OpSMod = 139, OpFRem = 140, OpFMod = 141, OpVectorTimesScalar = 142,
  OpMatrixTimesScalar = 143, OpVectorTimesMatrix = 144, OpMatrixTimesVector = 145, OpMatrixTimesMatrix = 146,
  OpOuterProduct = 147, OpDot = 148, OpAny = 154, OpAll = 155, OpIsNan = 156, OpIsInf = 157,
  OpLogicalEqual = 164, OpLogicalNotEqual = 165, OpLogicalOr = 166, OpLogicalAnd = 167, OpLogicalNot = 168,
  OpSelect = 169, OpIEqual = 170, OpINotEqual = 171, OpUGreaterThan = 172, OpSGreaterThan = 173,
  OpUGreaterThanEqual = 174, OpSGreaterThanEqual = 175, OpULessThan = 176, OpSLessThan = 177,
  OpULessThanEqual = 178, OpSLessThanEqual = 179, OpFOrdEqual = 180, OpFUnordEqual = 181, OpFOrdNotEqual = 182,
  OpFUnordNotEqual = 183, OpFOrdLessThan = 184, OpFUnordLessThan = 185, OpFOrdGreaterThan = 186,
  OpFUnordGreaterThan = 187, OpFOrdLessThanEqual = 188, OpFUnordLessThanEqual = 189, OpFOrdGreaterThanEqual = 190,
  OpFUnordGreaterThanEqual = 191, OpShiftRightLogical = 194, OpShiftRightArithmetic = 195,
  OpShiftLeftLogical = 196, OpBitwiseOr = 197, OpBitwiseXor = 198, OpBitwiseAnd = 199, OpNot = 200,
  OpDPdx = 207, OpDPdy = 208, OpFwidth = 209, OpDPdxFine = 210, OpDPdyFine = 211, OpFwidthFine = 212,
  OpDPdxCoarse = 213, OpDPdyCoarse = 214, OpFwidthCoarse = 215, OpPhi = 245, OpLoopMerge = 246,
  OpSelectionMerge = 247, OpLabel = 248, OpBranch = 249, OpBranchConditional = 250, OpSwitch = 251, OpKill = 252,
  OpReturn = 253, OpReturnValue = 254, OpUnreachable = 255, OpNop = 0, OpLine = 8, OpNoLine = 317,
  OpModuleProcessed = 330, OpString = 7, OpSource = 3, OpSourceExtension = 4, OpExtension = 10,
  OpMemoryModel = 14, OpCapability = 17, OpSourceContinued = 2
};
enum Storage { UniformConstant = 0, Input = 1, Uniform = 2, Output = 3, Private = 6, Function = 7, PushConstant = 9,
               StorageBuffer = 12 };
enum Dec { DecSpecId = 1, DecRowMajor = 4, DecColMajor = 5, DecArrayStride = 6, DecMatrixStride = 7, DecBuiltIn = 11,
           DecLocation = 30, DecBinding = 33, DecDescriptorSet = 34, DecOffset = 35 };

inline float f(uint32_t u) { float x; std::memcpy(&x, &u, 4); return x; }
inline uint32_t u(float x) { uint32_t v; std::memcpy(&v, &x, 4); return v; }
inline bool isBufferStorage(uint32_t s) { return s == Uniform || s == StorageBuffer || s == PushConstant; }

std::string readString(const uint32_t* w, size_t maxWords) {
  std::string s;
  for (size_t i = 0; i < maxWords * 4; ++i) {
    const char c = char((w[i / 4] >> (8 * (i % 4))) & 0xFF);
    if (!c) break;
    s += c;
  }
  return s;
}
}  // namespace

// --------------------------------------------------------------------- parse
void Module::computeComps(uint32_t id) {
  Type& t = types[id];
  switch (t.kind) {
    case Kind::Vector: case Kind::Matrix: case Kind::Array:
      t.comps = t.count * types[t.elem].comps;
      t.isFloatScalarBased = types[t.elem].isFloatScalarBased;
      break;
    case Kind::Struct: {
      t.comps = 0;
      for (uint32_t m : t.members) t.comps += types[m].comps;
      break;
    }
    case Kind::Float: t.comps = 1; t.isFloatScalarBased = true; break;
    case Kind::RuntimeArray: t.comps = types[t.elem].comps; break;
    default: t.comps = 1; break;
  }
}

std::shared_ptr<Module> Module::parse(const uint32_t* w, size_t count, std::string& err) {
  if (count < 5 || w[0] != 0x07230203u) { err = "bad SPIR-V magic"; return nullptr; }
  auto m = std::make_shared<Module>();
  m->words.assign(w, w + count);
  m->bound = w[3];
  const uint32_t B = m->bound;
  m->types.resize(B);
  m->vars.resize(B);
  m->isVar.assign(B, 0);
  m->constVal.resize(B);
  m->isConst.assign(B, 0);
  m->resultType.assign(B, 0);
  m->labelInst.assign(B, -1);
  m->functionInst.assign(B, -1);
  m->specId.assign(B, -1);
  std::map<uint32_t, std::vector<std::pair<uint32_t, uint32_t>>> dec;  // id -> (decoration, value)
  std::map<std::pair<uint32_t, uint32_t>, std::vector<std::pair<uint32_t, uint32_t>>> mdec;
  struct EP { int model; uint32_t fn; std::string name; std::vector<uint32_t> iface; };
  std::vector<EP> eps;
  size_t i = 5;
  while (i < count) {
    const uint16_t op = uint16_t(w[i] & 0xFFFF), wc = uint16_t(w[i] >> 16);
    if (wc == 0 || i + wc > count) { err = "truncated instruction"; return nullptr; }
    const uint32_t* a = w + i + 1;  // operands
    m->insts.push_back({op, wc, uint32_t(i)});
    const int idx = int(m->insts.size()) - 1;
    auto decOf = [&](uint32_t id, uint32_t d, uint32_t def) {
      for (auto& p : dec[id]) if (p.first == d) return p.second;
      return def;
    };
    switch (op) {
      case OpExtInstImport: if (readString(a + 1, wc - 2) == "GLSL.std.450") m->glslExt = a[0]; break;
      case OpEntryPoint: {
        EP e;
        e.model = int(a[0]);
        e.fn = a[1];
        e.name = readString(a + 2, wc - 3);
        const size_t nameWords = (e.name.size() + 4) / 4;
        for (size_t k = 2 + nameWords; k < size_t(wc - 1); ++k) e.iface.push_back(a[k]);
        eps.push_back(e);
        break;
      }
      case OpDecorate: dec[a[0]].push_back({a[1], wc > 3 ? a[2] : 0}); break;
      case OpMemberDecorate: mdec[{a[0], a[1]}].push_back({a[2], wc > 4 ? a[3] : 0}); break;
      case OpTypeVoid: m->types[a[0]].kind = Kind::Void; break;
      case OpTypeBool: m->types[a[0]].kind = Kind::Bool; break;
      case OpTypeInt: m->types[a[0]].kind = Kind::Int; m->types[a[0]].width = a[1]; m->types[a[0]].sign = a[2]; break;
      case OpTypeFloat: m->types[a[0]].kind = Kind::Float; m->types[a[0]].width = a[1]; break;
      case OpTypeVector: case OpTypeMatrix: {
        Type& t = m->types[a[0]];
        t.kind = op == OpTypeVector ? Kind::Vector : Kind::Matrix;
        t.elem = a[1]; t.count = a[2];
        break;
      }
      case OpTypeImage: m->types[a[0]].kind = Kind::Image; break;
      case OpTypeSampler: m->types[a[0]].kind = Kind::Sampler; break;
      case OpTypeSampledImage: m->types[a[0]].kind = Kind::SampledImage; break;
      case OpTypeArray: case OpTypeRuntimeArray: {
        Type& t = m->types[a[0]];
        t.kind = op == OpTypeArray ? Kind::Array : Kind::RuntimeArray;
        t.elem = a[1];
        t.count = op == OpTypeArray ? m->constVal[a[2]].at(0) : 1;
        t.arrayStride = decOf(a[0], DecArrayStride, 0);
        break;
      }
      case OpTypeStruct: {
        Type& t = m->types[a[0]];
        t.kind = Kind::Struct;
        for (int k = 1; k < wc - 1; ++k) {
          t.members.push_back(a[k]);
          uint32_t off = 0, ms = 16; uint8_t rm = 0; int32_t bi = -1;
          for (auto& p : mdec[{a[0], uint32_t(k - 1)}]) {
            if (p.first == DecOffset) off = p.second;
            if (p.first == DecMatrixStride) ms = p.second;
            if (p.first == DecRowMajor) rm = 1;
            if (p.first == DecBuiltIn) bi = int32_t(p.second);
          }
          t.memberOffset.push_back(off); t.memberMatrixStride.push_back(ms);
          t.memberRowMajor.push_back(rm); t.memberBuiltIn.push_back(bi);
        }
        break;
      }
      case OpTypePointer: {
        Type& t = m->types[a[0]];
        t.kind = Kind::Pointer; t.storage = a[1]; t.elem = a[2];
        break;
      }
      case OpTypeFunction: m->types[a[0]].kind = Kind::Function; break;
      case OpConstant: case OpSpecConstant:
        if (op == OpSpecConstant) m->specId[a[1]] = int32_t(decOf(a[1], DecSpecId, uint32_t(-1)));
        m->resultType[a[1]] = a[0];
        m->isConst[a[1]] = 1;
        m->constVal[a[1]] = {a[2]};
        break;
      case OpConstantTrue: case OpConstantFalse: case OpSpecConstantTrue: case OpSpecConstantFalse:
        if (op == OpSpecConstantTrue || op == OpSpecConstantFalse) m->specId[a[1]] = int32_t(decOf(a[1], DecSpecId, uint32_t(-1)));
        m->resultType[a[1]] = a[0];
        m->isConst[a[1]] = 1;
        m->constVal[a[1]] = {uint32_t(op == OpConstantTrue || op == OpSpecConstantTrue)};
        break;
      case OpConstantComposite: case OpSpecConstantComposite: {
        m->resultType[a[1]] = a[0];
        m->isConst[a[1]] = 1;
        std::vector<uint32_t> v;
        for (int k = 2; k < wc - 1; ++k) v.insert(v.end(), m->constVal[a[k]].begin(), m->constVal[a[k]].end());
        m->constVal[a[1]] = v;
        break;
      }
      case OpConstantNull:
        m->resultType[a[1]] = a[0];
        m->isConst[a[1]] = 1;
        m->constVal[a[1]].assign(m->types[a[0]].comps, 0);
        break;
      case OpVariable: {
        m->resultType[a[1]] = a[0];
        if (a[2] != Function) {
          Variable& v = m->vars[a[1]];
          v.id = a[1]; v.type = m->types[a[0]].elem; v.storage = a[2];
          v.initializer = wc > 4 ? a[3] : 0;
          v.location = int(decOf(a[1], DecLocation, uint32_t(-1)));
          v.builtin = int(decOf(a[1], DecBuiltIn, uint32_t(-1)));
          v.binding = int(decOf(a[1], DecBinding, uint32_t(-1)));
          v.set = int(decOf(a[1], DecDescriptorSet, 0));
          m->isVar[a[1]] = 1;
        }
        break;
      }
      case OpFunction: m->functionInst[a[1]] = idx; m->resultType[a[1]] = a[0]; break;
      case OpLabel: m->labelInst[a[0]] = idx; break;
      default:
        break;
    }
    // Result type for value-producing instructions (type, result) layout.
    switch (op) {
      case OpExtInst: case OpFunctionParameter: case OpFunctionCall: case OpLoad: case OpAccessChain:
      case OpInBoundsAccessChain: case OpVectorExtractDynamic: case OpVectorInsertDynamic: case OpVectorShuffle:
      case OpCompositeConstruct: case OpCompositeExtract: case OpCompositeInsert: case OpCopyObject: case OpTranspose:
      case OpSampledImage: case OpImageSampleImplicitLod: case OpImageSampleExplicitLod: case OpImageFetch:
      case OpImageSampleDrefImplicitLod: case OpImageSampleDrefExplicitLod: case OpImageQuerySizeLod:
      case OpImageQuerySize: case OpImageQueryLevels:
      case OpImage: case OpPhi: case OpUndef: case OpSelect:
        m->resultType[a[1]] = a[0];
        break;
      default:
        if (op >= OpConvertFToU && op <= OpFwidthCoarse) m->resultType[a[1]] = a[0];
        break;
    }
    // computeComps once a type is complete
    if (op >= OpTypeVoid && op <= OpTypeFunction) m->computeComps(a[0]);
    i += wc;
  }
  if (eps.empty()) { err = "no entry point"; return nullptr; }
  m->entryFunction = eps[0].fn;
  m->executionModel = eps[0].model;
  m->interfaceVars = eps[0].iface;
  return m;
}

bool Module::select(const std::string&) { return entryFunction != 0; }

void Module::specialize(const std::vector<std::array<uint32_t, 3>>& entries, const uint8_t* data) {
  for (uint32_t id = 0; id < bound; ++id) {
    if (specId[id] < 0) continue;
    for (const auto& e : entries)
      if (int32_t(e[0]) == specId[id]) {
        uint32_t v = 0;
        if (e[2] == 1) v = data[e[1]] != 0;  // VkBool32 may be given as 1 byte
        else std::memcpy(&v, data + e[1], std::min<uint32_t>(4, e[2]));
        if (types[resultType[id]].kind == Kind::Bool) v = v != 0;
        constVal[id] = {v};
      }
  }
  // Re-derive composite spec constants from their (possibly patched) parts.
  const uint32_t* w = words.data();
  for (const Inst& in : insts)
    if (in.op == OpSpecConstantComposite) {
      const uint32_t* a = w + in.at + 1;
      std::vector<uint32_t> v;
      for (int k = 2; k < in.wc - 1; ++k) v.insert(v.end(), constVal[a[k]].begin(), constVal[a[k]].end());
      constVal[a[1]] = v;
    }
}

int Module::findBuiltinOutputComp(int builtin, uint32_t& var) const {
  for (uint32_t id = 0; id < bound; ++id) {
    if (!isVar[id] || vars[id].storage != Output) continue;
    if (vars[id].builtin == builtin) { var = id; return 0; }
    const Type& t = types[vars[id].type];
    if (t.kind == Kind::Struct) {
      uint32_t off = 0;
      for (size_t k = 0; k < t.members.size(); ++k) {
        if (t.memberBuiltIn[k] == builtin) { var = id; return int(off); }
        off += types[t.members[k]].comps;
      }
    }
  }
  return -1;
}

int Module::findBuiltinInput(int builtin) const {
  for (uint32_t id = 0; id < bound; ++id)
    if (isVar[id] && vars[id].storage == Input && vars[id].builtin == builtin) return int(id);
  return -1;
}

std::vector<std::pair<int, uint32_t>> Module::locationVars(uint32_t storage) const {
  std::vector<std::pair<int, uint32_t>> r;
  for (uint32_t id = 0; id < bound; ++id)
    if (isVar[id] && vars[id].storage == storage && vars[id].location >= 0) r.push_back({vars[id].location, id});
  std::sort(r.begin(), r.end());
  return r;
}

// ----------------------------------------------------------------- execute
Invocation::Invocation(const Module& m) : m_(m) {
  val_.resize(m.bound);
  storage_.resize(m.bound);
  ptr_.resize(m.bound);
  isPtr_.assign(m.bound, 0);
  for (uint32_t id = 0; id < m.bound; ++id) {
    if (m.isConst[id]) {
      const auto& c = m.constVal[id];
      val_[id].resize(c.size() * L);
      for (size_t k = 0; k < c.size(); ++k)
        for (int l = 0; l < L; ++l) val_[id][k * L + l] = c[k];
    }
    if (m.isVar[id]) {
      const Variable& v = m.vars[id];
      if (!isBufferStorage(v.storage) && v.storage != UniformConstant)
        storage_[id].assign(size_t(m.types[v.type].comps) * L, 0);
      ptr_[id].var = id;
      ptr_[id].type = v.type;
      isPtr_[id] = 1;
    }
  }
}

void Invocation::resetStorage() {
  for (uint32_t id = 0; id < m_.bound; ++id)
    if (m_.isVar[id] && m_.vars[id].storage != Input && !storage_[id].empty()) {
      std::fill(storage_[id].begin(), storage_[id].end(), 0u);
      if (m_.vars[id].initializer) {
        const auto& c = m_.constVal[m_.vars[id].initializer];
        for (size_t k = 0; k < c.size(); ++k)
          for (int l = 0; l < L; ++l) storage_[id][k * L + l] = c[k];
      }
    }
}

void Invocation::run(const Resources& res, uint8_t activeMask) {
  killed_ = 0;
  resetStorage();
  if (exec(res, activeMask, false, 0)) return;
  if (!error.empty()) return;
  // Divergent control flow: re-run one lane at a time.
  killed_ = 0;
  resetStorage();
  for (int l = 0; l < L; ++l)
    if (activeMask & (1 << l)) {
      if (!exec(res, uint8_t(1 << l), true, l)) return;
    }
}

namespace {
// Byte offsets of every flattened component of `type` inside a buffer.
void layout(const Module& m, uint32_t type, uint32_t base, uint32_t matrixStride, bool rowMajor,
            std::vector<uint32_t>& out) {
  const Type& t = m.types[type];
  switch (t.kind) {
    case Kind::Vector:
      for (uint32_t i = 0; i < t.count; ++i) out.push_back(base + 4 * i);
      break;
    case Kind::Matrix: {
      const uint32_t rows = m.types[t.elem].count;
      for (uint32_t c = 0; c < t.count; ++c)
        for (uint32_t r = 0; r < rows; ++r)
          out.push_back(base + (rowMajor ? r * matrixStride + c * 4 : c * matrixStride + r * 4));
      break;
    }
    case Kind::Array: case Kind::RuntimeArray:
      for (uint32_t i = 0; i < t.count; ++i) layout(m, t.elem, base + i * t.arrayStride, matrixStride, rowMajor, out);
      break;
    case Kind::Struct:
      for (size_t k = 0; k < t.members.size(); ++k)
        layout(m, t.members[k], base + t.memberOffset[k], t.memberMatrixStride[k], t.memberRowMajor[k] != 0, out);
      break;
    default:
      out.push_back(base);
      break;
  }
}

float sampleTexture(const Texture& tx, float s, float t, float lod, int ch) {
  const int level = std::clamp(int(std::floor(lod + 0.5f)), 0, tx.levels - 1);
  const int w = std::max(1, tx.width >> level), h = std::max(1, tx.height >> level);
  auto wrap = [](int i, int n, int mode) {
    if (mode == 2) return std::clamp(i, 0, n - 1);
    if (mode == 1) { const int p = ((i % (2 * n)) + 2 * n) % (2 * n); return p < n ? p : 2 * n - 1 - p; }
    return ((i % n) + n) % n;
  };
  auto texel = [&](int x, int y) {
    x = wrap(x, w, tx.addressU); y = wrap(y, h, tx.addressV);
    const uint8_t* row = tx.data + tx.levelOffset[level] + size_t(y) * tx.levelPitch[level];
    switch (tx.format) {
      case 2: { float v; std::memcpy(&v, row + x * 16 + ch * 4, 4); return v; }
      case 3: { uint16_t v; std::memcpy(&v, row + x * 2, 2); return ch == 3 ? 1.0f : v / 65535.0f; }
      case 4: { float v; std::memcpy(&v, row + x * 4, 4); return ch == 3 ? 1.0f : v; }
      case 5: { uint32_t v; std::memcpy(&v, row + x * 4, 4); return ch == 3 ? 1.0f : (v & 0xFFFFFF) / 16777215.0f; }
      case 6: return ch == 0 ? row[x] / 255.0f : ch == 3 ? 1.0f : 0.0f;
      case 8: return ch < 2 ? row[x * 2 + ch] / 255.0f : ch == 3 ? 1.0f : 0.0f;
      case 7: {
        uint16_t h; std::memcpy(&h, row + x * 8 + ch * 2, 2);
        const uint32_t sgn = (h >> 15) & 1, e = (h >> 10) & 31, mnt = h & 1023;
        float r = e == 0 ? std::ldexp(float(mnt), -24) : e == 31 ? (mnt ? NAN : INFINITY) : std::ldexp(float(mnt | 1024), int(e) - 25);
        return sgn ? -r : r;
      }
      default: break;
    }
    int c = ch;
    if (tx.format == 1 && ch < 3) c = 2 - ch;  // BGRA
    return row[x * 4 + c] * (1.0f / 255.0f);
  };
  if (!tx.linear || lod > 0.5f && false) {
    return texel(int(std::floor(s * w)), int(std::floor(t * h)));
  }
  const float x = s * w - 0.5f, y = t * h - 0.5f;
  const int x0 = int(std::floor(x)), y0 = int(std::floor(y));
  const float ax = x - x0, ay = y - y0;
  const float a = texel(x0, y0), b = texel(x0 + 1, y0), c = texel(x0, y0 + 1), d = texel(x0 + 1, y0 + 1);
  const float top = a + (b - a) * ax, bot = c + (d - c) * ax;
  return top + (bot - top) * ay;
}
}  // namespace

bool Invocation::exec(const Resources& res, uint8_t mask, bool scalar, int lane) {
  const Module& m = m_;
  const uint32_t* W = m.words.data();
  struct Frame { int ret; uint32_t result; uint32_t prevBlock, curBlock; };
  std::vector<Frame> stack;
  int pc = m.functionInst[m.entryFunction];
  if (pc < 0) { error = "entry function not found"; return false; }
  uint32_t prevBlock = 0, curBlock = 0;
  std::vector<uint32_t> pendingArgs;
  size_t argPos = 0;
  auto lanesOf = [&](uint32_t id, std::vector<uint32_t>& v) -> std::vector<uint32_t>& { (void)id; return v; };
  (void)lanesOf;
  auto ensure = [&](uint32_t id) -> std::vector<uint32_t>& {
    auto& v = val_[id];
    const size_t n = size_t(m.types[m.resultType[id]].comps) * L;
    if (v.size() != n) v.assign(n, 0);
    return v;
  };
  auto comps = [&](uint32_t id) { return m.types[m.resultType[id]].comps; };
  auto scalarKind = [&](uint32_t typeId) {
    const Type* t = &m.types[typeId];
    while (t->kind == Kind::Vector || t->kind == Kind::Matrix || t->kind == Kind::Array) t = &m.types[t->elem];
    return t->kind == Kind::Int ? (t->sign ? 1 : 2) : t->kind == Kind::Bool ? 3 : 0;  // 0 float, 1 sint, 2 uint, 3 bool
  };
  auto laneBool = [&](uint32_t id, int l) { return val_[id][l] != 0; };
  auto uniformBool = [&](uint32_t id, bool& value) {
    if (scalar) { value = laneBool(id, lane); return true; }
    int seen = -1;
    for (int l = 0; l < L; ++l)
      if (mask & (1 << l)) {
        const int b = laneBool(id, l) ? 1 : 0;
        if (seen < 0) seen = b; else if (seen != b) return false;
      }
    value = seen == 1;
    return true;
  };
  const int n = int(m.insts.size());
  for (++pc; pc < n; ++pc) {
    const auto& in = m.insts[pc];
    const uint32_t* a = W + in.at + 1;
    const int wc = in.wc;
    switch (in.op) {
      case OpLabel: prevBlock = curBlock; curBlock = a[0]; break;
      case OpNop: case OpLine: case OpNoLine: case OpSelectionMerge: case OpLoopMerge: case OpName: break;
      case OpFunctionParameter: {
        const uint32_t id = a[1];
        const uint32_t src = argPos < pendingArgs.size() ? pendingArgs[argPos++] : 0;
        if (isPtr_[src]) { ptr_[id] = ptr_[src]; isPtr_[id] = 1; }
        else { ensure(id) = val_[src]; }
        break;
      }
      case OpVariable: {  // Function storage
        const uint32_t id = a[1];
        const uint32_t pointee = m.types[a[0]].elem;
        storage_[id].assign(size_t(m.types[pointee].comps) * L, 0);
        if (wc > 4) {
          const auto& c = val_[a[3]];
          if (!c.empty()) storage_[id] = c;
        }
        ptr_[id] = Ptr{};
        ptr_[id].var = id;
        ptr_[id].type = pointee;
        isPtr_[id] = 1;
        break;
      }
      case OpAccessChain: case OpInBoundsAccessChain: {
        const uint32_t id = a[1];
        Ptr p = ptr_[a[2]];
        const Variable* var = m.isVar[p.var] ? &m.vars[p.var] : nullptr;
        const bool buf = var && isBufferStorage(var->storage);
        for (int k = 3; k < wc - 1; ++k) {
          const uint32_t ix = a[k];
          const Type& t = m.types[p.type];
          int32_t idx[L];
          for (int l = 0; l < L; ++l) idx[l] = int32_t(val_[ix].empty() ? 0 : val_[ix][l]);
          if (t.kind == Kind::Struct) {
            const uint32_t mi = uint32_t(idx[0]);
            if (buf) {
              for (int l = 0; l < L; ++l) p.off[l] += int32_t(t.memberOffset[mi]);
              p.matrixStride = t.memberMatrixStride[mi];
              p.rowMajor = t.memberRowMajor[mi] != 0;
            } else {
              uint32_t o = 0;
              for (uint32_t q = 0; q < mi; ++q) o += m.types[t.members[q]].comps;
              for (int l = 0; l < L; ++l) p.off[l] += int32_t(o);
            }
            p.type = t.members[mi];
          } else {
            uint32_t step;
            if (buf) {
              if (t.kind == Kind::Array || t.kind == Kind::RuntimeArray) step = t.arrayStride;
              else if (t.kind == Kind::Matrix) step = p.rowMajor ? 4 : p.matrixStride;
              else step = 4;
            } else {
              step = m.types[t.elem].comps;
            }
            for (int l = 0; l < L; ++l) p.off[l] += idx[l] * int32_t(step);
            p.type = t.elem;
          }
        }
        ptr_[id] = p;
        isPtr_[id] = 1;
        break;
      }
      case OpLoad: {
        const uint32_t id = a[1];
        const Ptr& p = ptr_[a[2]];
        const Variable* var = m.isVar[p.var] ? &m.vars[p.var] : nullptr;
        auto& v = ensure(id);
        const uint32_t c = m.types[p.type].comps;
        if (var && var->storage == UniformConstant) {
          for (int l = 0; l < L; ++l) v[l] = p.var;
        } else if (var && isBufferStorage(var->storage)) {
          const uint8_t* base = var->storage == PushConstant ? res.pushConstants : res.buffer(var->set, var->binding);
          std::vector<uint32_t> offs;
          layout(m, p.type, 0, p.matrixStride, p.rowMajor, offs);
          for (uint32_t k = 0; k < c; ++k)
            for (int l = 0; l < L; ++l) {
              uint32_t x = 0;
              if (base) std::memcpy(&x, base + p.off[l] + offs[k], 4);
              v[k * L + l] = x;
            }
        } else {
          const auto& s = storage_[p.var];
          for (uint32_t k = 0; k < c; ++k)
            for (int l = 0; l < L; ++l) v[k * L + l] = s[size_t(p.off[l] + k) * L + l];
        }
        break;
      }
      case OpStore: {
        const Ptr& p = ptr_[a[0]];
        const auto& v = val_[a[1]];
        const Variable* var = m.isVar[p.var] ? &m.vars[p.var] : nullptr;
        if (var && (isBufferStorage(var->storage) || var->storage == UniformConstant)) {
          error = "store to buffer memory not supported";
          return false;
        }
        auto& s = storage_[p.var];
        const uint32_t c = m.types[p.type].comps;
        for (uint32_t k = 0; k < c; ++k)
          for (int l = 0; l < L; ++l)
            if (mask & (1 << l)) s[size_t(p.off[l] + k) * L + l] = v[k * L + l];
        break;
      }
      case OpCompositeExtract: {
        const uint32_t id = a[1];
        uint32_t t = m.resultType[a[2]], off = 0;
        for (int k = 3; k < wc - 1; ++k) {
          const Type& tt = m.types[t];
          const uint32_t ix = a[k];
          if (tt.kind == Kind::Struct) {
            for (uint32_t q = 0; q < ix; ++q) off += m.types[tt.members[q]].comps;
            t = tt.members[ix];
          } else {
            off += ix * m.types[tt.elem].comps;
            t = tt.elem;
          }
        }
        auto& v = ensure(id);
        const auto& src = val_[a[2]];
        std::copy(src.begin() + size_t(off) * L, src.begin() + size_t(off + m.types[t].comps) * L, v.begin());
        break;
      }
      case OpCompositeInsert: {
        const uint32_t id = a[1];
        auto& v = ensure(id);
        v = val_[a[3]];
        uint32_t t = m.resultType[a[3]], off = 0;
        for (int k = 4; k < wc - 1; ++k) {
          const Type& tt = m.types[t];
          const uint32_t ix = a[k];
          if (tt.kind == Kind::Struct) {
            for (uint32_t q = 0; q < ix; ++q) off += m.types[tt.members[q]].comps;
            t = tt.members[ix];
          } else {
            off += ix * m.types[tt.elem].comps;
            t = tt.elem;
          }
        }
        const auto& obj = val_[a[2]];
        std::copy(obj.begin(), obj.end(), v.begin() + size_t(off) * L);
        break;
      }
      case OpCompositeConstruct: {
        const uint32_t id = a[1];
        auto& v = ensure(id);
        size_t o = 0;
        for (int k = 2; k < wc - 1; ++k) {
          const auto& src = val_[a[k]];
          std::copy(src.begin(), src.end(), v.begin() + o);
          o += src.size();
        }
        break;
      }
      case OpVectorShuffle: {
        const uint32_t id = a[1];
        auto& v = ensure(id);
        const auto& v1 = val_[a[2]];
        const auto& v2 = val_[a[3]];
        const uint32_t n1 = uint32_t(v1.size() / L);
        for (int k = 4; k < wc - 1; ++k) {
          const uint32_t s = a[k];
          for (int l = 0; l < L; ++l)
            v[size_t(k - 4) * L + l] = s == 0xFFFFFFFFu ? 0 : s < n1 ? v1[s * L + l] : v2[(s - n1) * L + l];
        }
        break;
      }
      case OpVectorExtractDynamic: {
        auto& v = ensure(a[1]);
        for (int l = 0; l < L; ++l) v[l] = val_[a[2]][size_t(val_[a[3]][l]) * L + l];
        break;
      }
      case OpVectorInsertDynamic: {
        auto& v = ensure(a[1]);
        v = val_[a[2]];
        for (int l = 0; l < L; ++l) v[size_t(val_[a[4]][l]) * L + l] = val_[a[3]][l];
        break;
      }
      case OpCopyObject: ensure(a[1]) = val_[a[2]]; break;
      case OpUndef: ensure(a[1]); break;
      case OpSampledImage: case OpImage: {
        auto& v = ensure(a[1]);
        for (int l = 0; l < L; ++l) v[l] = val_[a[2]][l];
        break;
      }
      case OpImageSampleImplicitLod: case OpImageSampleExplicitLod: {
        const uint32_t id = a[1];
        auto& v = ensure(id);
        const Variable& var = m.vars[val_[a[2]][0]];
        const Texture* tx = res.texture(var.set, var.binding);
        const auto& c = val_[a[3]];
        float lodv[L] = {};
        if (in.op == OpImageSampleExplicitLod && wc > 5) {
          for (int l = 0; l < L; ++l) lodv[l] = f(val_[a[5]][l]);
        } else if (tx) {
          // Derivatives from the 4x2 lane block.
          for (int l = 0; l < L; ++l) {
            const int x0 = l & ~1, y0 = l & ~4;
            const float dsx = (f(c[x0 | 1]) - f(c[x0])) * tx->width, dtx = (f(c[L + (x0 | 1)]) - f(c[L + x0])) * tx->height;
            const float dsy = (f(c[y0 | 4]) - f(c[y0])) * tx->width, dty = (f(c[L + (y0 | 4)]) - f(c[L + y0])) * tx->height;
            const float rho = std::max(dsx * dsx + dtx * dtx, dsy * dsy + dty * dty);
            lodv[l] = 0.5f * std::log2(std::max(rho, 1e-12f));
          }
        }
        for (int l = 0; l < L; ++l)
          for (int ch = 0; ch < 4; ++ch)
            v[size_t(ch) * L + l] = u(tx ? sampleTexture(*tx, f(c[l]), f(c[L + l]), lodv[l], ch) : (ch == 3 ? 1.0f : 0.0f));
        break;
      }
      case OpImageQuerySizeLod: case OpImageQuerySize: case OpImageQueryLevels: {
        auto& v = ensure(a[1]);
        const Variable& var = m.vars[val_[a[2]][0]];
        const Texture* tx = res.texture(var.set, var.binding);
        const int lod = in.op == OpImageQuerySizeLod ? int(val_[a[3]][0]) : 0;
        const uint32_t c = comps(a[1]);
        for (int l = 0; l < L; ++l) {
          if (in.op == OpImageQueryLevels) { v[l] = tx ? uint32_t(tx->levels) : 1; continue; }
          const uint32_t w2 = tx ? uint32_t(std::max(1, tx->width >> lod)) : 1, h2 = tx ? uint32_t(std::max(1, tx->height >> lod)) : 1;
          v[l] = w2;
          if (c > 1) v[L + l] = h2;
          for (uint32_t k = 2; k < c; ++k) v[k * L + l] = 1;
        }
        break;
      }
      case OpImageSampleDrefImplicitLod: case OpImageSampleDrefExplicitLod: {
        // Depth comparison with 2x2 bilinear PCF.
        auto& v = ensure(a[1]);
        const Variable& var = m.vars[val_[a[2]][0]];
        const Texture* tx = res.texture(var.set, var.binding);
        const auto& c = val_[a[3]];
        const auto& dref = val_[a[4]];
        for (int l = 0; l < L; ++l) {
          float r = 1.0f;
          if (tx) {
            const float s0 = f(c[l]), t0 = f(c[L + l]), ref = f(dref[l]);
            const float x = s0 * tx->width - 0.5f, y = t0 * tx->height - 0.5f;
            const int x0 = int(std::floor(x)), y0 = int(std::floor(y));
            const float ax = x - x0, ay = y - y0;
            auto cmp = [&](int xx, int yy) {
              if (xx < 0 || yy < 0 || xx >= tx->width || yy >= tx->height) return tx->borderOne;
              const float d = sampleTexture(*tx, (xx + 0.5f) / tx->width, (yy + 0.5f) / tx->height, 0.0f, 0);
              switch (tx->compareOp) {
                case 1: return ref < d ? 1.0f : 0.0f;
                case 2: return ref == d ? 1.0f : 0.0f;
                case 3: return ref <= d ? 1.0f : 0.0f;
                case 4: return ref > d ? 1.0f : 0.0f;
                case 6: return ref >= d ? 1.0f : 0.0f;
                case 7: return 1.0f;
                default: return 0.0f;
              }
            };
            const float t1 = cmp(x0, y0) + (cmp(x0 + 1, y0) - cmp(x0, y0)) * ax;
            const float b1 = cmp(x0, y0 + 1) + (cmp(x0 + 1, y0 + 1) - cmp(x0, y0 + 1)) * ax;
            r = t1 + (b1 - t1) * ay;
          }
          v[l] = u(r);
        }
        break;
      }
      case OpDPdx: case OpDPdxFine: case OpDPdxCoarse: case OpDPdy: case OpDPdyFine: case OpDPdyCoarse:
      case OpFwidth: case OpFwidthFine: case OpFwidthCoarse: {
        auto& v = ensure(a[1]);
        const auto& s = val_[a[2]];
        const bool isX = in.op == OpDPdx || in.op == OpDPdxFine || in.op == OpDPdxCoarse;
        const bool isW = in.op == OpFwidth || in.op == OpFwidthFine || in.op == OpFwidthCoarse;
        const uint32_t c = comps(a[1]);
        for (uint32_t k = 0; k < c; ++k)
          for (int l = 0; l < L; ++l) {
            const int x0 = l & ~1, y0 = l & ~4;
            const float dx = f(s[k * L + (x0 | 1)]) - f(s[k * L + x0]);
            const float dy = f(s[k * L + (y0 | 4)]) - f(s[k * L + y0]);
            v[k * L + l] = u(isW ? std::fabs(dx) + std::fabs(dy) : isX ? dx : dy);
          }
        break;
      }
      case OpVectorTimesScalar: case OpMatrixTimesScalar: {
        auto& v = ensure(a[1]);
        const auto& x = val_[a[2]];
        const auto& s = val_[a[3]];
        const uint32_t c = comps(a[1]);
        for (uint32_t k = 0; k < c; ++k)
          for (int l = 0; l < L; ++l) v[k * L + l] = u(f(x[k * L + l]) * f(s[l]));
        break;
      }
      case OpMatrixTimesVector: {
        auto& v = ensure(a[1]);
        const auto& mt = val_[a[2]];
        const auto& x = val_[a[3]];
        const uint32_t rows = comps(a[1]), cols = uint32_t(x.size() / L);
        for (uint32_t r = 0; r < rows; ++r)
          for (int l = 0; l < L; ++l) {
            float s = 0;
            for (uint32_t c = 0; c < cols; ++c) s += f(mt[(c * rows + r) * L + l]) * f(x[c * L + l]);
            v[r * L + l] = u(s);
          }
        break;
      }
      case OpVectorTimesMatrix: {
        auto& v = ensure(a[1]);
        const auto& x = val_[a[2]];
        const auto& mt = val_[a[3]];
        const uint32_t rows = uint32_t(x.size() / L), cols = comps(a[1]);
        for (uint32_t c = 0; c < cols; ++c)
          for (int l = 0; l < L; ++l) {
            float s = 0;
            for (uint32_t r = 0; r < rows; ++r) s += f(x[r * L + l]) * f(mt[(c * rows + r) * L + l]);
            v[c * L + l] = u(s);
          }
        break;
      }
      case OpMatrixTimesMatrix: {
        auto& v = ensure(a[1]);
        const auto& A = val_[a[2]];
        const auto& Bm = val_[a[3]];
        const Type& rt = m.types[m.resultType[a[1]]];
        const uint32_t rows = m.types[rt.elem].count, cols = rt.count;
        const uint32_t inner = uint32_t(A.size() / L) / rows;
        for (uint32_t j = 0; j < cols; ++j)
          for (uint32_t r = 0; r < rows; ++r)
            for (int l = 0; l < L; ++l) {
              float s = 0;
              for (uint32_t k = 0; k < inner; ++k) s += f(A[(k * rows + r) * L + l]) * f(Bm[(j * inner + k) * L + l]);
              v[(j * rows + r) * L + l] = u(s);
            }
        break;
      }
      case OpTranspose: {
        auto& v = ensure(a[1]);
        const auto& A = val_[a[2]];
        const Type& rt = m.types[m.resultType[a[1]]];
        const uint32_t rows = m.types[rt.elem].count, cols = rt.count;  // result
        for (uint32_t j = 0; j < cols; ++j)
          for (uint32_t r = 0; r < rows; ++r)
            for (int l = 0; l < L; ++l) v[(j * rows + r) * L + l] = A[(r * cols + j) * L + l];
        break;
      }
      case OpDot: {
        auto& v = ensure(a[1]);
        const auto& x = val_[a[2]];
        const auto& y = val_[a[3]];
        const uint32_t c = uint32_t(x.size() / L);
        for (int l = 0; l < L; ++l) {
          float s = 0;
          for (uint32_t k = 0; k < c; ++k) s += f(x[k * L + l]) * f(y[k * L + l]);
          v[l] = u(s);
        }
        break;
      }
      case OpSelect: {
        auto& v = ensure(a[1]);
        const auto& cnd = val_[a[2]];
        const auto& x = val_[a[3]];
        const auto& y = val_[a[4]];
        const uint32_t c = comps(a[1]);
        const bool vecCond = cnd.size() > size_t(L);
        for (uint32_t k = 0; k < c; ++k)
          for (int l = 0; l < L; ++l) v[k * L + l] = cnd[(vecCond ? k : 0) * L + l] ? x[k * L + l] : y[k * L + l];
        break;
      }
      case OpAny: case OpAll: {
        auto& v = ensure(a[1]);
        const auto& x = val_[a[2]];
        const uint32_t c = uint32_t(x.size() / L);
        for (int l = 0; l < L; ++l) {
          bool r = in.op == OpAll;
          for (uint32_t k = 0; k < c; ++k) r = in.op == OpAll ? (r && x[k * L + l]) : (r || x[k * L + l]);
          v[l] = r;
        }
        break;
      }
      case OpExtInst: {
        if (a[2] != m.glslExt) { error = "unsupported extended instruction set"; return false; }
        auto& v = ensure(a[1]);
        const uint32_t e = a[3];
        const uint32_t c = comps(a[1]);
        auto arg = [&](int i) -> const std::vector<uint32_t>& { return val_[a[4 + i]]; };
        const int sk = scalarKind(m.resultType[a[1]]);
        switch (e) {
          case 66: case 67: {  // Length, Distance
            const auto& x = arg(0);
            const uint32_t n2 = uint32_t(x.size() / L);
            for (int l = 0; l < L; ++l) {
              float s = 0;
              for (uint32_t k = 0; k < n2; ++k) {
                const float d = f(x[k * L + l]) - (e == 67 ? f(arg(1)[k * L + l]) : 0.0f);
                s += d * d;
              }
              v[l] = u(std::sqrt(s));
            }
            break;
          }
          case 68: {  // Cross
            const auto& x = arg(0);
            const auto& y = arg(1);
            for (int l = 0; l < L; ++l) {
              const float ax = f(x[l]), ay = f(x[L + l]), az = f(x[2 * L + l]);
              const float bx = f(y[l]), by = f(y[L + l]), bz = f(y[2 * L + l]);
              v[l] = u(ay * bz - az * by); v[L + l] = u(az * bx - ax * bz); v[2 * L + l] = u(ax * by - ay * bx);
            }
            break;
          }
          case 69: {  // Normalize
            const auto& x = arg(0);
            for (int l = 0; l < L; ++l) {
              float s = 0;
              for (uint32_t k = 0; k < c; ++k) s += f(x[k * L + l]) * f(x[k * L + l]);
              const float inv = s > 0 ? 1.0f / std::sqrt(s) : 0.0f;
              for (uint32_t k = 0; k < c; ++k) v[k * L + l] = u(f(x[k * L + l]) * inv);
            }
            break;
          }
          case 33: case 34: {  // Determinant, MatrixInverse (column-major, n = 2..4)
            const auto& M = arg(0);
            const uint32_t n = e == 34 ? uint32_t(std::lround(std::sqrt(double(c)))) : uint32_t(std::lround(std::sqrt(double(M.size() / L))));
            for (int l = 0; l < L; ++l) {
              double A[4][8] = {};
              for (uint32_t col = 0; col < n; ++col)
                for (uint32_t row = 0; row < n; ++row) { A[row][col] = f(M[(col * n + row) * L + l]); A[row][n + col] = row == col; }
              double det = 1;
              for (uint32_t i2 = 0; i2 < n; ++i2) {  // Gauss-Jordan with partial pivoting
                uint32_t piv = i2;
                for (uint32_t r2 = i2 + 1; r2 < n; ++r2) if (std::fabs(A[r2][i2]) > std::fabs(A[piv][i2])) piv = r2;
                if (piv != i2) { for (uint32_t k2 = 0; k2 < 2 * n; ++k2) std::swap(A[i2][k2], A[piv][k2]); det = -det; }
                const double d = A[i2][i2];
                det *= d;
                if (d == 0) continue;
                for (uint32_t k2 = 0; k2 < 2 * n; ++k2) A[i2][k2] /= d;
                for (uint32_t r2 = 0; r2 < n; ++r2)
                  if (r2 != i2) {
                    const double fct = A[r2][i2];
                    for (uint32_t k2 = 0; k2 < 2 * n; ++k2) A[r2][k2] -= fct * A[i2][k2];
                  }
              }
              if (e == 33) v[l] = u(float(det));
              else
                for (uint32_t col = 0; col < n; ++col)
                  for (uint32_t row = 0; row < n; ++row) v[(col * n + row) * L + l] = u(float(A[row][n + col]));
            }
            break;
          }
          case 71: {  // Reflect: I - 2 dot(N, I) N
            const auto& I = arg(0);
            const auto& N = arg(1);
            for (int l = 0; l < L; ++l) {
              float d = 0;
              for (uint32_t k = 0; k < c; ++k) d += f(I[k * L + l]) * f(N[k * L + l]);
              for (uint32_t k = 0; k < c; ++k) v[k * L + l] = u(f(I[k * L + l]) - 2 * d * f(N[k * L + l]));
            }
            break;
          }
          default: {
            for (uint32_t k = 0; k < c; ++k)
              for (int l = 0; l < L; ++l) {
                const size_t i0 = size_t(k) * L + l;
                auto F = [&](int ai) { const auto& x = arg(ai); return f(x[x.size() > size_t(L) ? i0 : size_t(l)]); };
                auto I = [&](int ai) { const auto& x = arg(ai); return int32_t(x[x.size() > size_t(L) ? i0 : size_t(l)]); };
                float r = 0;
                int32_t ri = 0;
                bool isInt = false;
                switch (e) {
                  case 1: case 2: r = std::nearbyint(F(0)); break;
                  case 3: r = std::trunc(F(0)); break;
                  case 4: r = std::fabs(F(0)); break;
                  case 5: ri = std::abs(I(0)); isInt = true; break;
                  case 6: r = F(0) > 0 ? 1.0f : F(0) < 0 ? -1.0f : 0.0f; break;
                  case 8: r = std::floor(F(0)); break;
                  case 9: r = std::ceil(F(0)); break;
                  case 10: r = F(0) - std::floor(F(0)); break;
                  case 11: r = F(0) * 0.017453292f; break;
                  case 12: r = F(0) * 57.29578f; break;
                  case 13: r = std::sin(F(0)); break;
                  case 14: r = std::cos(F(0)); break;
                  case 15: r = std::tan(F(0)); break;
                  case 16: r = std::asin(F(0)); break;
                  case 17: r = std::acos(F(0)); break;
                  case 18: r = std::atan(F(0)); break;
                  case 25: r = std::atan2(F(0), F(1)); break;
                  case 26: r = std::pow(F(0), F(1)); break;
                  case 27: r = std::exp(F(0)); break;
                  case 28: r = std::log(F(0)); break;
                  case 29: r = std::exp2(F(0)); break;
                  case 30: r = std::log2(F(0)); break;
                  case 31: r = std::sqrt(F(0)); break;
                  case 32: r = 1.0f / std::sqrt(F(0)); break;
                  case 37: case 79: r = std::fmin(F(0), F(1)); break;
                  case 40: case 80: r = std::fmax(F(0), F(1)); break;
                  case 38: ri = int32_t(std::min(uint32_t(I(0)), uint32_t(I(1)))); isInt = true; break;
                  case 39: ri = std::min(I(0), I(1)); isInt = true; break;
                  case 41: ri = int32_t(std::max(uint32_t(I(0)), uint32_t(I(1)))); isInt = true; break;
                  case 42: ri = std::max(I(0), I(1)); isInt = true; break;
                  case 43: case 81: r = std::fmin(std::fmax(F(0), F(1)), F(2)); break;
                  case 44: ri = int32_t(std::min(std::max(uint32_t(I(0)), uint32_t(I(1))), uint32_t(I(2)))); isInt = true; break;
                  case 45: ri = std::min(std::max(I(0), I(1)), I(2)); isInt = true; break;
                  case 46: r = F(0) + (F(1) - F(0)) * F(2); break;
                  case 48: r = F(1) < F(0) ? 0.0f : 1.0f; break;
                  case 49: {
                    const float t = std::clamp((F(2) - F(0)) / (F(1) - F(0)), 0.0f, 1.0f);
                    r = t * t * (3 - 2 * t);
                    break;
                  }
                  case 50: r = F(0) * F(1) + F(2); break;
                  default:
                    error = "unsupported GLSL.std.450 instruction " + std::to_string(e);
                    return false;
                }
                (void)sk;
                v[i0] = isInt ? uint32_t(ri) : u(r);
              }
            break;
          }
        }
        break;
      }
      case OpPhi: {
        auto& v = ensure(a[1]);
        for (int k = 2; k + 1 < wc - 1; k += 2)
          if (a[k + 1] == prevBlock) { v = val_[a[k]]; break; }
        break;
      }
      case OpBranch: pc = m.labelInst[a[0]] - 1; break;
      case OpBranchConditional: {
        bool b;
        if (!uniformBool(a[0], b)) return false;  // divergent: caller re-runs per lane
        pc = m.labelInst[b ? a[1] : a[2]] - 1;
        break;
      }
      case OpSwitch: {
        // Selector must be uniform across active lanes.
        int32_t sel = 0;
        bool first = true;
        for (int l = 0; l < L; ++l)
          if ((scalar && l == lane) || (!scalar && (mask & (1 << l)))) {
            const int32_t s = int32_t(val_[a[0]][l]);
            if (first) { sel = s; first = false; } else if (s != sel) return false;
          }
        uint32_t target = a[1];
        for (int k = 2; k + 1 < wc - 1; k += 2) if (int32_t(a[k]) == sel) target = a[k + 1];
        pc = m.labelInst[target] - 1;
        break;
      }
      case OpKill:
        killed_ |= mask;
        return true;
      case OpReturn: case OpReturnValue: case OpUnreachable:
        if (stack.empty()) return true;
        if (in.op == OpReturnValue && stack.back().result) ensure(stack.back().result) = val_[a[0]];
        pc = stack.back().ret;
        prevBlock = stack.back().prevBlock;
        curBlock = stack.back().curBlock;
        stack.pop_back();
        break;
      case OpFunctionCall: {
        pendingArgs.assign(a + 3, a + wc - 1);
        argPos = 0;
        stack.push_back({pc, m.types[a[0]].kind == Kind::Void ? 0u : a[1], prevBlock, curBlock});
        pc = m.functionInst[a[2]];
        break;
      }
      case OpFunctionEnd:
        if (stack.empty()) return true;
        pc = stack.back().ret;
        stack.pop_back();
        break;
      default: {
        // Element-wise unary / binary arithmetic, conversions and comparisons.
        const uint16_t op = in.op;
        if (op < OpConvertFToU || op > OpNot) {
          error = "unsupported opcode " + std::to_string(op);
          return false;
        }
        auto& v = ensure(a[1]);
        const uint32_t c = comps(a[1]);
        const auto& x = val_[a[2]];
        const std::vector<uint32_t>* yp = wc > 4 ? &val_[a[3]] : nullptr;
        for (uint32_t k = 0; k < c; ++k)
          for (int l = 0; l < L; ++l) {
            const size_t i0 = size_t(k) * L + l;
            const uint32_t X = x[i0];
            const uint32_t Y = yp ? (*yp)[yp->size() > size_t(L) ? i0 : size_t(l)] : 0;
            const float fx = f(X), fy = f(Y);
            const int32_t sx = int32_t(X), sy = int32_t(Y);
            uint32_t r = 0;
            switch (op) {
              case OpConvertFToU: r = uint32_t(std::max(0.0f, fx)); break;
              case OpConvertFToS: r = uint32_t(int32_t(fx)); break;
              case OpConvertSToF: r = u(float(sx)); break;
              case OpConvertUToF: r = u(float(X)); break;
              case OpUConvert: case OpSConvert: case OpFConvert: case OpBitcast: r = X; break;
              case OpSNegate: r = uint32_t(-sx); break;
              case OpFNegate: r = u(-fx); break;
              case OpIAdd: r = X + Y; break;
              case OpFAdd: r = u(fx + fy); break;
              case OpISub: r = X - Y; break;
              case OpFSub: r = u(fx - fy); break;
              case OpIMul: r = X * Y; break;
              case OpFMul: r = u(fx * fy); break;
              case OpUDiv: r = Y ? X / Y : 0; break;
              case OpSDiv: r = sy ? uint32_t(sx / sy) : 0; break;
              case OpFDiv: r = u(fx / fy); break;
              case OpUMod: r = Y ? X % Y : 0; break;
              case OpSRem: r = sy ? uint32_t(sx % sy) : 0; break;
              case OpSMod: r = sy ? uint32_t(((sx % sy) + sy) % sy) : 0; break;
              case OpFRem: r = u(std::fmod(fx, fy)); break;
              case OpFMod: r = u(fx - fy * std::floor(fx / fy)); break;
              case OpIsNan: r = std::isnan(fx); break;
              case OpIsInf: r = std::isinf(fx); break;
              case OpLogicalEqual: r = (X != 0) == (Y != 0); break;
              case OpLogicalNotEqual: r = (X != 0) != (Y != 0); break;
              case OpLogicalOr: r = X || Y; break;
              case OpLogicalAnd: r = X && Y; break;
              case OpLogicalNot: r = !X; break;
              case OpIEqual: r = X == Y; break;
              case OpINotEqual: r = X != Y; break;
              case OpUGreaterThan: r = X > Y; break;
              case OpSGreaterThan: r = sx > sy; break;
              case OpUGreaterThanEqual: r = X >= Y; break;
              case OpSGreaterThanEqual: r = sx >= sy; break;
              case OpULessThan: r = X < Y; break;
              case OpSLessThan: r = sx < sy; break;
              case OpULessThanEqual: r = X <= Y; break;
              case OpSLessThanEqual: r = sx <= sy; break;
              case OpFOrdEqual: r = fx == fy; break;
              case OpFUnordEqual: r = !(fx != fy); break;
              case OpFOrdNotEqual: r = fx != fy && !std::isnan(fx) && !std::isnan(fy); break;
              case OpFUnordNotEqual: r = fx != fy; break;
              case OpFOrdLessThan: r = fx < fy; break;
              case OpFUnordLessThan: r = !(fx >= fy); break;
              case OpFOrdGreaterThan: r = fx > fy; break;
              case OpFUnordGreaterThan: r = !(fx <= fy); break;
              case OpFOrdLessThanEqual: r = fx <= fy; break;
              case OpFUnordLessThanEqual: r = !(fx > fy); break;
              case OpFOrdGreaterThanEqual: r = fx >= fy; break;
              case OpFUnordGreaterThanEqual: r = !(fx < fy); break;
              case OpShiftRightLogical: r = X >> (Y & 31); break;
              case OpShiftRightArithmetic: r = uint32_t(sx >> (Y & 31)); break;
              case OpShiftLeftLogical: r = X << (Y & 31); break;
              case OpBitwiseOr: r = X | Y; break;
              case OpBitwiseXor: r = X ^ Y; break;
              case OpBitwiseAnd: r = X & Y; break;
              case OpNot: r = ~X; break;
              default:
                error = "unsupported opcode " + std::to_string(op);
                return false;
            }
            v[i0] = r;
          }
        break;
      }
    }
  }
  return true;
}

}  // namespace spv
