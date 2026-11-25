// SPIR-V -> C++ (8-lane SIMD via simd.hpp) -> native shared library -> dlopen.
// Structured control flow is compiled with execution masks (SIMT style):
// divergent if/else runs both sides under masks, loops iterate while any lane
// is still looping, function calls are inlined. Unsupported constructs throw and
// the driver keeps using the interpreter for that shader.
#include "jit.hpp"

#include <dlfcn.h>
#include <sys/stat.h>
#include <unistd.h>

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <set>
#include <sstream>
#include <stdexcept>
#include <unordered_map>

#include "spirv.hpp"

#ifndef JSNOW_SRC_DIR
#define JSNOW_SRC_DIR "."
#endif
#ifndef JSNOW_ICD_DIR
#define JSNOW_ICD_DIR "."
#endif

namespace jit {

namespace {
using spv::Kind;
using spv::Module;

// opcode numbers used by the generator
enum : uint16_t {
  OpUndef = 1, OpExtInst = 12, OpFunction = 54, OpFunctionParameter = 55, OpFunctionEnd = 56, OpFunctionCall = 57,
  OpVariable = 59, OpLoad = 61, OpStore = 62, OpAccessChain = 65, OpInBoundsAccessChain = 66,
  OpVectorExtractDynamic = 77, OpVectorInsertDynamic = 78, OpVectorShuffle = 79, OpCompositeConstruct = 80,
  OpCompositeExtract = 81, OpCompositeInsert = 82, OpCopyObject = 83, OpTranspose = 84, OpSampledImage = 86,
  OpImageSampleImplicitLod = 87, OpImageSampleExplicitLod = 88, OpImageSampleDrefImplicitLod = 89,
  OpImageSampleDrefExplicitLod = 90, OpImageFetch = 95, OpImageRead = 98, OpImageWrite = 99, OpImage = 100,
  OpImageQuerySizeLod = 103, OpImageQuerySize = 104, OpImageQueryLevels = 106, OpConvertFToU = 109,
  OpConvertFToS = 110, OpConvertSToF = 111, OpConvertUToF = 112, OpUConvert = 113, OpSConvert = 114,
  OpFConvert = 115, OpBitcast = 124, OpSNegate = 126, OpFNegate = 127, OpIAdd = 128, OpFAdd = 129, OpISub = 130,
  OpFSub = 131, OpIMul = 132, OpFMul = 133, OpUDiv = 134, OpSDiv = 135, OpFDiv = 136, OpUMod = 137, OpSRem = 138,
  OpSMod = 139, OpFRem = 140, OpFMod = 141, OpVectorTimesScalar = 142, OpMatrixTimesScalar = 143,
  OpVectorTimesMatrix = 144, OpMatrixTimesVector = 145, OpMatrixTimesMatrix = 146, OpOuterProduct = 147,
  OpDot = 148, OpAny = 154, OpAll = 155, OpIsNan = 156, OpIsInf = 157, OpLogicalEqual = 164,
  OpLogicalNotEqual = 165, OpLogicalOr = 166, OpLogicalAnd = 167, OpLogicalNot = 168, OpSelect = 169,
  OpIEqual = 170, OpINotEqual = 171, OpUGreaterThan = 172, OpSGreaterThan = 173, OpUGreaterThanEqual = 174,
  OpSGreaterThanEqual = 175, OpULessThan = 176, OpSLessThan = 177, OpULessThanEqual = 178, OpSLessThanEqual = 179,
  OpFOrdEqual = 180, OpFUnordEqual = 181, OpFOrdNotEqual = 182, OpFUnordNotEqual = 183, OpFOrdLessThan = 184,
  OpFUnordLessThan = 185, OpFOrdGreaterThan = 186, OpFUnordGreaterThan = 187, OpFOrdLessThanEqual = 188,
  OpFUnordLessThanEqual = 189, OpFOrdGreaterThanEqual = 190, OpFUnordGreaterThanEqual = 191,
  OpShiftRightLogical = 194, OpShiftRightArithmetic = 195, OpShiftLeftLogical = 196, OpBitwiseOr = 197,
  OpBitwiseXor = 198, OpBitwiseAnd = 199, OpNot = 200, OpDPdx = 207, OpDPdy = 208, OpFwidth = 209,
  OpDPdxFine = 210, OpDPdyFine = 211, OpFwidthFine = 212, OpDPdxCoarse = 213, OpDPdyCoarse = 214,
  OpFwidthCoarse = 215, OpControlBarrier = 224, OpMemoryBarrier = 225, OpAtomicLoad = 227, OpAtomicStore = 228,
  OpAtomicExchange = 229, OpAtomicCompareExchange = 230, OpAtomicIIncrement = 232, OpAtomicIDecrement = 233,
  OpAtomicIAdd = 234, OpAtomicISub = 235, OpAtomicSMin = 236, OpAtomicUMin = 237, OpAtomicSMax = 238,
  OpAtomicUMax = 239, OpAtomicAnd = 240, OpAtomicOr = 241, OpAtomicXor = 242, OpPhi = 245, OpLoopMerge = 246,
  OpSelectionMerge = 247, OpLabel = 248, OpBranch = 249, OpBranchConditional = 250, OpSwitch = 251, OpKill = 252,
  OpReturn = 253, OpReturnValue = 254, OpUnreachable = 255, OpLine = 8, OpNoLine = 317, OpNop = 0
};
enum Storage { UniformConstant = 0, Input = 1, Uniform = 2, Output = 3, Private = 6, Function = 7, PushConstant = 9,
               StorageBuffer = 12 };

struct Unsupported : std::runtime_error {
  using std::runtime_error::runtime_error;
};

struct Ptr {
  uint32_t var = 0, type = 0;
  int kind = 0;  // 0 storage (ctx), 1 function-local, 2 buffer, 3 push constant, 4 image var
  int off = 0;   // components (0/1) or bytes (2/3)
  std::string dyn;  // name of a vi with per-lane extra offset ("" = none)
  uint32_t matrixStride = 16;
  bool rowMajor = false;
};

struct LoopCtx {
  uint32_t header, merge, cont;
  int n;  // name suffix
};

class Gen {
 public:
  explicit Gen(const Module& m) : m_(m), W(m.words.data()) {
    blockEnd_.assign(m.bound, -1);
    for (size_t i = 0; i < m.insts.size(); ++i)
      if (m.insts[i].op == OpLabel) {
        const uint32_t lbl = W[m.insts[i].at + 1];
        size_t j = i + 1;
        while (j < m.insts.size()) {
          const uint16_t op = m.insts[j].op;
          if (op == OpBranch || op == OpBranchConditional || op == OpSwitch || op == OpReturn ||
              op == OpReturnValue || op == OpKill || op == OpUnreachable)
            break;
          ++j;
        }
        blockEnd_[lbl] = int(j);
      }
  }

  std::string run() {
    const int fn = m_.functionInst[m_.entryFunction];
    if (fn < 0) throw Unsupported("no entry");
    std::ostringstream& o = body_;
    o << "  vm M = alive;\n";
    emitFunctionBody(uint32_t(fn), "");
    std::ostringstream out;
    out << "#include \"simd.hpp\"\n#include \"jit_rt.hpp\"\n#include <cmath>\n#include <cstring>\n"
           "using namespace jsnow::simd;\nusing jsnow_jit::Ctx;\n"
           "static inline float bf(int32_t i){float f;std::memcpy(&f,&i,4);return f;}\n"
           "static inline int32_t bi(float f){int32_t i;std::memcpy(&i,&f,4);return i;}\n"
           "static inline vf F(vi a){return as_f(a);}\nstatic inline vi I(vf a){return as_i(a);}\n"
           "static inline vi B(vm a){return as_i(a);}\n"
           "static inline vi gatherS(const uint32_t* s, vi idx){return gather(s, shl<3>(idx) + iotai());}\n"
           "extern \"C\" __attribute__((visibility(\"default\"))) void jsnow_shader(Ctx* ctx) {\n"
           "  const vi LANE = iotai();\n"
           "  vm alive = cmpeq(shrv(set1i(int32_t(ctx->active)), LANE) & set1i(1), set1i(1));\n"
           "  vm killedM = as_m(set1i(0));\n"
           "  (void)LANE;\n";
    out << decl_.str() << body_.str();
    out << "  ctx->killed = uint32_t(bits(killedM));\n}\n";
    return out.str();
  }

 private:
  const Module& m_;
  const uint32_t* W;
  std::vector<int> blockEnd_;
  std::ostringstream decl_, body_;
  std::set<uint32_t> declared_;
  std::map<uint32_t, Ptr> ptr_;
  std::map<uint32_t, uint32_t> imageVar_;  // value id -> image variable id
  std::set<uint32_t> buffersHoisted_;
  std::vector<LoopCtx> loops_;
  int uniq_ = 0;
  int indent_ = 1;
  // function inlining
  struct CallCtx { std::string retAcc; uint32_t result; };
  std::vector<CallCtx> calls_;
  std::vector<uint32_t> pendingArgs_;

  const uint32_t* ops(int inst) const { return W + m_.insts[inst].at + 1; }
  int wc(int inst) const { return m_.insts[inst].wc; }
  uint32_t comps(uint32_t id) const { return m_.types[m_.resultType[id]].comps; }
  uint32_t tcomps(uint32_t t) const { return m_.types[t].comps; }
  bool isBoolType(uint32_t t) const {
    const spv::Type* ty = &m_.types[t];
    while (ty->kind == Kind::Vector) ty = &m_.types[ty->elem];
    return ty->kind == Kind::Bool;
  }
  std::string ind() const { return std::string(size_t(indent_) * 2, ' '); }
  std::ostringstream& o() { body_ << ind(); return body_; }

  // Declared value storage for an SSA id (or a constant).
  std::string v(uint32_t id, uint32_t k) {
    if (m_.isConst[id]) {
      const auto& c = m_.constVal[id];
      uint32_t x = k < c.size() ? c[k] : 0;
      if (isBoolType(m_.resultType[id])) x = x ? 0xFFFFFFFFu : 0;
      char b[64];
      std::snprintf(b, sizeof b, "set1i(int32_t(0x%08xu))", x);
      return b;
    }
    declare(id);
    return "v" + std::to_string(id) + "[" + std::to_string(k) + "]";
  }
  void declare(uint32_t id) {
    if (declared_.count(id)) return;
    declared_.insert(id);
    const uint32_t c = std::max(1u, comps(id));
    decl_ << "  vi v" << id << "[" << c << "];\n";
  }
  // scalar-broadcast access: operand with 1 component used by a vector op
  std::string vb(uint32_t id, uint32_t k) { return v(id, comps(id) > 1 ? k : 0); }

  std::string fresh(const char* p) { return std::string(p) + std::to_string(++uniq_); }

  const uint8_t* hoistBuffer(const spv::Variable& var) {
    if (!buffersHoisted_.count(var.id)) {
      buffersHoisted_.insert(var.id);
      if (var.storage == PushConstant) decl_ << "  const uint8_t* B" << var.id << " = ctx->push;\n";
      else decl_ << "  const uint8_t* B" << var.id << " = ctx->rt->buffer(ctx, " << var.set << ", " << var.binding << ");\n";
    }
    return nullptr;
  }

  Ptr basePtr(uint32_t id) {
    auto it = ptr_.find(id);
    if (it != ptr_.end()) return it->second;
    if (!m_.isVar[id]) throw Unsupported("unknown pointer");
    const spv::Variable& var = m_.vars[id];
    Ptr p;
    p.var = id;
    p.type = var.type;
    switch (var.storage) {
      case Uniform: case StorageBuffer: p.kind = 2; hoistBuffer(var); break;
      case PushConstant: p.kind = 3; hoistBuffer(var); break;
      case UniformConstant: p.kind = 4; break;
      case Input: case Output: case Private: p.kind = 0; break;
      default: throw Unsupported("storage class " + std::to_string(var.storage));
    }
    ptr_[id] = p;
    return p;
  }

  std::string storageExpr(const Ptr& p) {
    if (p.kind == 1) return "F" + std::to_string(p.var);
    return "ctx->storage[" + std::to_string(p.var) + "]";
  }

  // ------------------------------------------------------------ memory
  void emitLoad(uint32_t res, uint32_t ptrId) {
    Ptr p = basePtr(ptrId);
    const uint32_t c = tcomps(p.type);
    const bool isBool = isBoolType(p.type);
    if (p.kind == 4) { imageVar_[res] = p.var; return; }
    declare(res);
    if (p.kind == 0 || p.kind == 1) {
      const std::string S = storageExpr(p);
      for (uint32_t k = 0; k < c; ++k) {
        std::string e = p.dyn.empty() ? "loadui(" + S + " + " + std::to_string((p.off + int(k)) * 8) + ")"
                                      : "gatherS(" + S + ", " + p.dyn + " + set1i(" + std::to_string(p.off + int(k)) + "))";
        if (isBool && p.kind == 0) e = "B(~cmpeq(" + e + ", set1i(0)))";
        o() << v(res, k) << " = " << e << ";\n";
      }
      return;
    }
    // buffer / push constant
    std::vector<uint32_t> offs;
    spv::bufferLayout(m_, p.type, 0, p.matrixStride, p.rowMajor, offs);
    if (offs.size() < c) throw Unsupported("buffer layout");
    const std::string B = "B" + std::to_string(p.var);
    for (uint32_t k = 0; k < c; ++k) {
      const uint32_t byteOff = uint32_t(p.off) + offs[k];
      std::string e;
      if (p.dyn.empty()) {
        e = "set1i(" + B + " ? [&]{int32_t t; std::memcpy(&t, " + B + " + " + std::to_string(byteOff) + ", 4); return t;}() : 0)";
      } else {
        e = "(" + B + " ? gather(" + B + ", shr<2>(" + p.dyn + " + set1i(" + std::to_string(byteOff) + "))) : set1i(0))";
      }
      if (isBool) e = "B(~cmpeq(" + e + ", set1i(0)))";
      o() << v(res, k) << " = " << e << ";\n";
    }
  }

  void emitStore(uint32_t ptrId, uint32_t val) {
    Ptr p = basePtr(ptrId);
    const uint32_t c = tcomps(p.type);
    const bool isBool = isBoolType(p.type);
    if (p.kind == 0 || p.kind == 1) {
      const std::string S = storageExpr(p);
      for (uint32_t k = 0; k < c; ++k) {
        std::string x = v(val, k);
        if (isBool && p.kind == 0) x = "(" + x + " & set1i(1))";
        if (p.dyn.empty()) {
          const std::string addr = S + " + " + std::to_string((p.off + int(k)) * 8);
          o() << "storeui(" << addr << ", selecti(M, " << x << ", loadui(" << addr << ")));\n";
        } else {
          o() << "{ alignas(32) int32_t ix[8], vv[8]; storei(ix, " << p.dyn << " + set1i(" << (p.off + int(k))
              << ")); storei(vv, " << x << "); const int mm = bits(M); for (int l = 0; l < 8; ++l) if (mm >> l & 1) "
              << S << "[ix[l] * 8 + l] = uint32_t(vv[l]); }\n";
        }
      }
      return;
    }
    if (p.kind != 2) throw Unsupported("store to read-only storage");
    std::vector<uint32_t> offs;
    spv::bufferLayout(m_, p.type, 0, p.matrixStride, p.rowMajor, offs);
    if (offs.size() < c) throw Unsupported("buffer layout");
    const std::string B = "B" + std::to_string(p.var);
    for (uint32_t k = 0; k < c; ++k) {
      std::string x = v(val, k);
      if (isBool) x = "(" + x + " & set1i(1))";
      const uint32_t byteOff = uint32_t(p.off) + offs[k];
      o() << "if (" << B << ") { alignas(32) int32_t ox[8], vv[8]; storei(ox, "
          << (p.dyn.empty() ? std::string("set1i(0)") : p.dyn) << " + set1i(" << byteOff << ")); storei(vv, " << x
          << "); const int mm = bits(M); for (int l = 0; l < 8; ++l) if (mm >> l & 1) std::memcpy(const_cast<uint8_t*>("
          << B << ") + ox[l], &vv[l], 4); }\n";
    }
  }

  void emitAccessChain(int inst) {
    const uint32_t* a = ops(inst);
    Ptr p = basePtr(a[2]);
    const bool buf = p.kind == 2 || p.kind == 3;
    for (int k = 3; k < wc(inst) - 1; ++k) {
      const uint32_t ix = a[k];
      const spv::Type& t = m_.types[p.type];
      const bool constIdx = m_.isConst[ix] != 0;
      const int32_t cidx = constIdx ? int32_t(m_.constVal[ix][0]) : 0;
      if (t.kind == Kind::Struct) {
        if (!constIdx) throw Unsupported("dynamic struct index");
        if (buf) {
          p.off += int(t.memberOffset[cidx]);
          p.matrixStride = t.memberMatrixStride[cidx];
          p.rowMajor = t.memberRowMajor[cidx] != 0;
        } else {
          for (int q = 0; q < cidx; ++q) p.off += int(m_.types[t.members[q]].comps);
        }
        p.type = t.members[cidx];
        continue;
      }
      uint32_t step;
      if (buf) {
        if (t.kind == Kind::Array || t.kind == Kind::RuntimeArray) step = t.arrayStride;
        else if (t.kind == Kind::Matrix) step = p.rowMajor ? 4 : p.matrixStride;
        else step = 4;
      } else {
        step = m_.types[t.elem].comps;
      }
      if (constIdx) {
        p.off += cidx * int(step);
      } else {
        const std::string nd = fresh("pd");
        o() << "const vi " << nd << " = " << (p.dyn.empty() ? std::string("set1i(0)") : p.dyn) << " + " << v(ix, 0)
            << " * set1i(" << step << ");\n";
        p.dyn = nd;
      }
      p.type = t.elem;
    }
    ptr_[a[1]] = p;
  }

  // ------------------------------------------------------------ helpers
  void perLane(uint32_t res, const std::vector<uint32_t>& args, const std::string& expr) {
    // expr uses a0..a3 (int32 lanes) and must produce an int32 r
    declare(res);
    const uint32_t c = comps(res);
    for (uint32_t k = 0; k < c; ++k) {
      o() << "{ alignas(32) int32_t a0[8], a1[8], a2[8], a3[8], rr[8];";
      for (size_t i = 0; i < args.size(); ++i) o() << " storei(a" << i << ", " << vb(args[i], k) << ");";
      body_ << " for (int l = 0; l < 8; ++l) { int32_t r; " << expr << " rr[l] = r; } " << v(res, k)
            << " = loadi(rr); }\n";
    }
  }

  void elementwise(int inst) {
    const uint32_t* a = ops(inst);
    const uint16_t op = m_.insts[inst].op;
    const uint32_t res = a[1];
    const uint32_t x = a[2], y = wc(inst) > 4 ? a[3] : 0;
    declare(res);
    const uint32_t c = comps(res);
    auto F2 = [&](const char* fop) {
      for (uint32_t k = 0; k < c; ++k)
        o() << v(res, k) << " = I(F(" << vb(x, k) << ") " << fop << " F(" << vb(y, k) << "));\n";
    };
    auto I2 = [&](const char* iop) {
      for (uint32_t k = 0; k < c; ++k) o() << v(res, k) << " = " << vb(x, k) << " " << iop << " " << vb(y, k) << ";\n";
    };
    auto FC = [&](const char* cmp, bool neg) {
      for (uint32_t k = 0; k < c; ++k)
        o() << v(res, k) << " = " << (neg ? "(" : "") << "B(F(" << vb(x, k) << ") " << cmp << " F(" << vb(y, k) << "))"
            << (neg ? " ^ set1i(-1))" : "") << ";\n";
    };
    switch (op) {
      case OpFAdd: F2("+"); return;
      case OpFSub: F2("-"); return;
      case OpFMul: F2("*"); return;
      case OpFDiv: F2("/"); return;
      case OpIAdd: I2("+"); return;
      case OpISub: I2("-"); return;
      case OpIMul: I2("*"); return;
      case OpBitwiseAnd: case OpLogicalAnd: I2("&"); return;
      case OpBitwiseOr: case OpLogicalOr: I2("|"); return;
      case OpBitwiseXor: case OpLogicalNotEqual: I2("^"); return;
      case OpLogicalEqual: for (uint32_t k = 0; k < c; ++k) o() << v(res, k) << " = " << vb(x, k) << " ^ " << vb(y, k) << " ^ set1i(-1);\n"; return;
      case OpNot: case OpLogicalNot: for (uint32_t k = 0; k < c; ++k) o() << v(res, k) << " = " << v(x, k) << " ^ set1i(-1);\n"; return;
      case OpFNegate: for (uint32_t k = 0; k < c; ++k) o() << v(res, k) << " = " << v(x, k) << " ^ set1i(int32_t(0x80000000u));\n"; return;
      case OpSNegate: for (uint32_t k = 0; k < c; ++k) o() << v(res, k) << " = set1i(0) - " << v(x, k) << ";\n"; return;
      case OpConvertSToF: for (uint32_t k = 0; k < c; ++k) o() << v(res, k) << " = I(to_f(" << v(x, k) << "));\n"; return;
      case OpConvertFToS: for (uint32_t k = 0; k < c; ++k) o() << v(res, k) << " = trunc_i(F(" << v(x, k) << "));\n"; return;
      case OpBitcast: case OpUConvert: case OpSConvert: case OpFConvert:
        for (uint32_t k = 0; k < c; ++k) o() << v(res, k) << " = " << v(x, k) << ";\n";
        return;
      case OpIEqual: for (uint32_t k = 0; k < c; ++k) o() << v(res, k) << " = B(cmpeq(" << vb(x, k) << ", " << vb(y, k) << "));\n"; return;
      case OpINotEqual: for (uint32_t k = 0; k < c; ++k) o() << v(res, k) << " = B(cmpeq(" << vb(x, k) << ", " << vb(y, k) << ")) ^ set1i(-1);\n"; return;
      case OpSGreaterThan: for (uint32_t k = 0; k < c; ++k) o() << v(res, k) << " = B(cmpgt(" << vb(x, k) << ", " << vb(y, k) << "));\n"; return;
      case OpSLessThan: for (uint32_t k = 0; k < c; ++k) o() << v(res, k) << " = B(cmpgt(" << vb(y, k) << ", " << vb(x, k) << "));\n"; return;
      case OpSGreaterThanEqual: for (uint32_t k = 0; k < c; ++k) o() << v(res, k) << " = B(cmpgt(" << vb(y, k) << ", " << vb(x, k) << ")) ^ set1i(-1);\n"; return;
      case OpSLessThanEqual: for (uint32_t k = 0; k < c; ++k) o() << v(res, k) << " = B(cmpgt(" << vb(x, k) << ", " << vb(y, k) << ")) ^ set1i(-1);\n"; return;
      case OpFOrdLessThan: FC("<", false); return;
      case OpFOrdGreaterThan: FC(">", false); return;
      case OpFOrdLessThanEqual: FC("<=", false); return;
      case OpFOrdGreaterThanEqual: FC(">=", false); return;
      case OpFUnordGreaterThanEqual: FC("<", true); return;
      case OpFUnordLessThanEqual: FC(">", true); return;
      case OpFUnordGreaterThan: FC("<=", true); return;
      case OpFUnordLessThan: FC(">=", true); return;
      case OpShiftLeftLogical: for (uint32_t k = 0; k < c; ++k) o() << v(res, k) << " = shlv(" << vb(x, k) << ", " << vb(y, k) << " & set1i(31));\n"; return;
      case OpShiftRightLogical: for (uint32_t k = 0; k < c; ++k) o() << v(res, k) << " = shrv(" << vb(x, k) << ", " << vb(y, k) << " & set1i(31));\n"; return;
      default: break;
    }
    // Scalar per-lane fallback (still native code).
    std::vector<uint32_t> args{x};
    if (y) args.push_back(y);
    std::string e;
    switch (op) {
      case OpConvertFToU: e = "r = int32_t(uint32_t(std::fmax(0.0f, bf(a0[l]))));"; break;
      case OpConvertUToF: e = "r = bi(float(uint32_t(a0[l])));"; break;
      case OpUDiv: e = "r = a1[l] ? int32_t(uint32_t(a0[l]) / uint32_t(a1[l])) : 0;"; break;
      case OpSDiv: e = "r = a1[l] ? a0[l] / a1[l] : 0;"; break;
      case OpUMod: e = "r = a1[l] ? int32_t(uint32_t(a0[l]) % uint32_t(a1[l])) : 0;"; break;
      case OpSRem: e = "r = a1[l] ? a0[l] % a1[l] : 0;"; break;
      case OpSMod: e = "r = a1[l] ? ((a0[l] % a1[l]) + a1[l]) % a1[l] : 0;"; break;
      case OpFRem: e = "r = bi(std::fmod(bf(a0[l]), bf(a1[l])));"; break;
      case OpFMod: e = "{ float X = bf(a0[l]), Y = bf(a1[l]); r = bi(X - Y * std::floor(X / Y)); }"; break;
      case OpIsNan: e = "r = std::isnan(bf(a0[l])) ? -1 : 0;"; break;
      case OpIsInf: e = "r = std::isinf(bf(a0[l])) ? -1 : 0;"; break;
      case OpUGreaterThan: e = "r = uint32_t(a0[l]) > uint32_t(a1[l]) ? -1 : 0;"; break;
      case OpUGreaterThanEqual: e = "r = uint32_t(a0[l]) >= uint32_t(a1[l]) ? -1 : 0;"; break;
      case OpULessThan: e = "r = uint32_t(a0[l]) < uint32_t(a1[l]) ? -1 : 0;"; break;
      case OpULessThanEqual: e = "r = uint32_t(a0[l]) <= uint32_t(a1[l]) ? -1 : 0;"; break;
      case OpFOrdEqual: e = "r = bf(a0[l]) == bf(a1[l]) ? -1 : 0;"; break;
      case OpFUnordEqual: e = "r = !(bf(a0[l]) != bf(a1[l])) ? -1 : 0;"; break;
      case OpFOrdNotEqual: e = "{ float X = bf(a0[l]), Y = bf(a1[l]); r = (X != Y && X == X && Y == Y) ? -1 : 0; }"; break;
      case OpFUnordNotEqual: e = "r = bf(a0[l]) != bf(a1[l]) ? -1 : 0;"; break;
      case OpShiftRightArithmetic: e = "r = a0[l] >> (a1[l] & 31);"; break;
      default: throw Unsupported("opcode " + std::to_string(op));
    }
    perLane(res, args, e);
  }

  void extInst(int inst) {
    const uint32_t* a = ops(inst);
    if (a[2] != m_.glslExt) throw Unsupported("ext inst set");
    const uint32_t res = a[1], e = a[3];
    declare(res);
    const uint32_t c = comps(res);
    auto arg = [&](int i) { return a[4 + i]; };
    auto F1 = [&](const std::string& f) {  // vf expression of "x"
      for (uint32_t k = 0; k < c; ++k) {
        std::string ex = f;
        for (size_t p; (p = ex.find("$0")) != std::string::npos;) ex.replace(p, 2, "F(" + vb(arg(0), k) + ")");
        for (size_t p; (p = ex.find("$1")) != std::string::npos;) ex.replace(p, 2, "F(" + vb(arg(1), k) + ")");
        for (size_t p; (p = ex.find("$2")) != std::string::npos;) ex.replace(p, 2, "F(" + vb(arg(2), k) + ")");
        o() << v(res, k) << " = I(" << ex << ");\n";
      }
    };
    auto scalarFn = [&](const char* fn, int nargs) {
      std::vector<uint32_t> args;
      for (int i = 0; i < nargs; ++i) args.push_back(arg(i));
      std::string ex = std::string("r = bi(") + fn + "(bf(a0[l])" + (nargs > 1 ? ", bf(a1[l])" : "") + "));";
      perLane(res, args, ex);
    };
    switch (e) {
      case 4: F1("abs($0)"); return;
      case 8: F1("floor($0)"); return;
      case 9: F1("zerof() - floor(zerof() - $0)"); return;
      case 10: F1("$0 - floor($0)"); return;
      case 31: F1("sqrt($0)"); return;
      case 32: F1("set1(1.0f) / sqrt($0)"); return;
      case 37: case 79: F1("min($0, $1)"); return;
      case 40: case 80: F1("max($0, $1)"); return;
      case 43: case 81: F1("min(max($0, $1), $2)"); return;
      case 46: F1("fma($2, $1 - $0, $0)"); return;
      case 48: F1("select($1 < $0, zerof(), set1(1.0f))"); return;
      case 49: F1("[&]{ vf t = clamp(($2 - $0) / ($1 - $0), zerof(), set1(1.0f)); return t * t * fnma(set1(2.0f), t, set1(3.0f)); }()"); return;
      case 50: F1("fma($0, $1, $2)"); return;
      case 11: F1("$0 * set1(0.017453292f)"); return;
      case 12: F1("$0 * set1(57.29578f)"); return;
      case 1: case 2: scalarFn("std::nearbyint", 1); return;
      case 3: scalarFn("std::trunc", 1); return;
      case 6: perLane(res, {arg(0)}, "{ float X = bf(a0[l]); r = bi(X > 0 ? 1.0f : X < 0 ? -1.0f : 0.0f); }"); return;
      case 13: scalarFn("std::sin", 1); return;
      case 14: scalarFn("std::cos", 1); return;
      case 15: scalarFn("std::tan", 1); return;
      case 16: scalarFn("std::asin", 1); return;
      case 17: scalarFn("std::acos", 1); return;
      case 18: scalarFn("std::atan", 1); return;
      case 25: scalarFn("std::atan2", 2); return;
      case 26: scalarFn("std::pow", 2); return;
      case 27: scalarFn("std::exp", 1); return;
      case 28: scalarFn("std::log", 1); return;
      case 29: scalarFn("std::exp2", 1); return;
      case 30: scalarFn("std::log2", 1); return;
      case 5: perLane(res, {arg(0)}, "r = a0[l] < 0 ? -a0[l] : a0[l];"); return;
      case 38: perLane(res, {arg(0), arg(1)}, "r = int32_t(std::min(uint32_t(a0[l]), uint32_t(a1[l])));"); return;
      case 39: for (uint32_t k = 0; k < c; ++k) o() << v(res, k) << " = mini(" << vb(arg(0), k) << ", " << vb(arg(1), k) << ");\n"; return;
      case 41: perLane(res, {arg(0), arg(1)}, "r = int32_t(std::max(uint32_t(a0[l]), uint32_t(a1[l])));"); return;
      case 42: for (uint32_t k = 0; k < c; ++k) o() << v(res, k) << " = maxi(" << vb(arg(0), k) << ", " << vb(arg(1), k) << ");\n"; return;
      case 44: perLane(res, {arg(0), arg(1), arg(2)}, "r = int32_t(std::min(std::max(uint32_t(a0[l]), uint32_t(a1[l])), uint32_t(a2[l])));"); return;
      case 45: for (uint32_t k = 0; k < c; ++k) o() << v(res, k) << " = mini(maxi(" << vb(arg(0), k) << ", " << vb(arg(1), k) << "), " << vb(arg(2), k) << ");\n"; return;
      case 66: case 67: {  // Length, Distance
        const uint32_t n = comps(arg(0));
        std::string s = "zerof()";
        for (uint32_t k = 0; k < n; ++k) {
          const std::string d = e == 66 ? "F(" + v(arg(0), k) + ")" : "(F(" + v(arg(0), k) + ") - F(" + v(arg(1), k) + "))";
          s = "fma(" + d + ", " + d + ", " + s + ")";
        }
        o() << v(res, 0) << " = I(sqrt(" << s << "));\n";
        return;
      }
      case 68: {  // Cross
        auto X = [&](int i, int k) { return "F(" + v(arg(i), uint32_t(k)) + ")"; };
        o() << v(res, 0) << " = I(" << X(0, 1) << " * " << X(1, 2) << " - " << X(0, 2) << " * " << X(1, 1) << ");\n";
        o() << v(res, 1) << " = I(" << X(0, 2) << " * " << X(1, 0) << " - " << X(0, 0) << " * " << X(1, 2) << ");\n";
        o() << v(res, 2) << " = I(" << X(0, 0) << " * " << X(1, 1) << " - " << X(0, 1) << " * " << X(1, 0) << ");\n";
        return;
      }
      case 69: {  // Normalize
        std::string s = "zerof()";
        for (uint32_t k = 0; k < c; ++k) s = "fma(F(" + v(arg(0), k) + "), F(" + v(arg(0), k) + "), " + s + ")";
        const std::string n = fresh("nrm");
        o() << "const vf " << n << " = select(" << s << " > zerof(), set1(1.0f) / sqrt(" << s << "), zerof());\n";
        for (uint32_t k = 0; k < c; ++k) o() << v(res, k) << " = I(F(" << v(arg(0), k) << ") * " << n << ");\n";
        return;
      }
      case 71: {  // Reflect
        std::string d = "zerof()";
        for (uint32_t k = 0; k < c; ++k) d = "fma(F(" + v(arg(0), k) + "), F(" + v(arg(1), k) + "), " + d + ")";
        const std::string n = fresh("dot");
        o() << "const vf " << n << " = " << d << ";\n";
        for (uint32_t k = 0; k < c; ++k)
          o() << v(res, k) << " = I(F(" << v(arg(0), k) << ") - set1(2.0f) * " << n << " * F(" << v(arg(1), k) << "));\n";
        return;
      }
      case 33: case 34: {  // Determinant, MatrixInverse via runtime
        const uint32_t n2 = comps(arg(0)), n = n2 == 4 ? 2 : n2 == 9 ? 3 : 4;
        const std::string t = fresh("mi");
        o() << "{ alignas(32) uint32_t " << t << "i[16*8], " << t << "o[17*8];";
        for (uint32_t k = 0; k < n2; ++k) body_ << " storei(" << t << "i + " << k * 8 << ", " << v(arg(0), k) << ");";
        body_ << " ctx->rt->matrixInverse(" << t << "i, " << t << "o, " << n << ", 8);";
        if (e == 34) for (uint32_t k = 0; k < n2; ++k) body_ << " " << v(res, k) << " = loadi(" << t << "o + " << k * 8 << ");";
        else body_ << " " << v(res, 0) << " = loadi(" << t << "o + " << n2 * 8 << ");";
        body_ << " }\n";
        return;
      }
      default: throw Unsupported("GLSL.std.450 " + std::to_string(e));
    }
  }

  // ------------------------------------------------------------ control flow
  void assignPhis(uint32_t from, uint32_t to, const std::string& mask) {
    const int li = m_.labelInst[to];
    std::vector<std::pair<uint32_t, uint32_t>> moves;  // (phi, source)
    for (int i = li + 1; i < int(m_.insts.size()) && m_.insts[i].op == OpPhi; ++i) {
      const uint32_t* a = ops(i);
      for (int k = 2; k + 1 < wc(i) - 1; k += 2)
        if (a[k + 1] == from) moves.push_back({a[1], a[k]});
    }
    if (moves.empty()) return;
    if (moves.size() == 1) {
      const uint32_t res = moves[0].first, src = moves[0].second;
      for (uint32_t q = 0; q < comps(res); ++q)
        o() << v(res, q) << " = selecti(" << mask << ", " << v(src, q) << ", " << v(res, q) << ");\n";
      return;
    }
    // parallel copy: read every source before writing any phi
    o() << "{\n";
    for (size_t j = 0; j < moves.size(); ++j)
      for (uint32_t q = 0; q < comps(moves[j].first); ++q)
        o() << "  const vi t" << j << "_" << q << " = " << v(moves[j].second, q) << ";\n";
    for (size_t j = 0; j < moves.size(); ++j)
      for (uint32_t q = 0; q < comps(moves[j].first); ++q)
        o() << "  " << v(moves[j].first, q) << " = selecti(" << mask << ", t" << j << "_" << q << ", " << v(moves[j].first, q) << ");\n";
    o() << "}\n";
  }

  // Lanes `mask` jump to a loop's merge/continue/header block: record them. Phis are handled by the caller.
  bool loopTarget(uint32_t to, const std::string& mask) {
    for (auto it = loops_.rbegin(); it != loops_.rend(); ++it) {
      const std::string n = std::to_string(it->n);
      if (to == it->merge) { o() << "BM" << n << " = BM" << n << " | " << mask << ";\n"; return true; }
      if (to == it->cont && it->cont != it->header) { o() << "CM" << n << " = CM" << n << " | " << mask << ";\n"; return true; }
      if (to == it->header) { o() << "NL" << n << " = NL" << n << " | " << mask << ";\n"; return true; }
      break;  // only the innermost loop may be targeted directly
    }
    return false;
  }

  // Edge from block `from` to `to` for lanes `mask`. Returns true if the path continues into `to`.
  bool edge(uint32_t from, uint32_t to, const std::string& mask, uint32_t stop, const std::string& stopAcc) {
    assignPhis(from, to, mask);
    if (loopTarget(to, mask)) return false;
    if (to == stop) {
      if (!stopAcc.empty()) o() << stopAcc << " = " << stopAcc << " | " << mask << ";\n";
      return false;
    }
    return true;
  }

  void emitInstructions(uint32_t label, bool& isLoopHeader, uint32_t& merge, uint32_t& cont, bool& selection) {
    isLoopHeader = false; selection = false; merge = 0; cont = 0;
    const int li = m_.labelInst[label];
    for (int i = li + 1; i < blockEnd_[label]; ++i) {
      const uint16_t op = m_.insts[i].op;
      const uint32_t* a = ops(i);
      switch (op) {
        case OpPhi: declare(a[1]); break;  // assigned on incoming edges
        case OpLoopMerge: isLoopHeader = true; merge = a[0]; cont = a[1]; break;
        case OpSelectionMerge: selection = true; merge = a[0]; break;
        default: emitInst(i); break;
      }
    }
  }

  // Walks a structured path from `start` until `stop` (or until all lanes leave).
  void emitFrom(uint32_t start, uint32_t stop, const std::string& stopAcc, bool skipLoopAt = false) {
    uint32_t cur = start;
    bool firstSkip = skipLoopAt;
    for (int guard = 0; guard < 100000; ++guard) {
      if (cur == stop) return;
      bool loopHdr, sel;
      uint32_t merge, cont;
      // Detect loop header without emitting yet.
      bool hdr = false;
      uint32_t hMerge = 0, hCont = 0;
      for (int i = m_.labelInst[cur] + 1; i < blockEnd_[cur]; ++i)
        if (m_.insts[i].op == OpLoopMerge) { hdr = true; hMerge = ops(i)[0]; hCont = ops(i)[1]; }
      if (hdr && !firstSkip) {
        emitLoop(cur, hMerge, hCont);
        cur = hMerge;
        if (loopTarget(cur, "M")) return;
        if (cur == stop) {
          if (!stopAcc.empty()) o() << stopAcc << " = " << stopAcc << " | M;\n";
          return;
        }
        continue;
      }
      firstSkip = false;
      emitInstructions(cur, loopHdr, merge, cont, sel);
      const int ti = blockEnd_[cur];
      const uint16_t top = m_.insts[ti].op;
      const uint32_t* a = ops(ti);
      if (top == OpBranch) {
        if (!edge(cur, a[0], "M", stop, stopAcc)) return;
        cur = a[0];
        continue;
      }
      if (top == OpBranchConditional) {
        const std::string c = fresh("c");
        o() << "const vm " << c << " = as_m(" << v(a[0], 0) << ");\n";
        const std::string mt = fresh("mt"), mf = fresh("mf");
        o() << "const vm " << mt << " = M & " << c << ", " << mf << " = andnot(" << c << ", M);\n";
        if (sel && !loopHdr) {
          const std::string acc = fresh("R");
          o() << "vm " << acc << " = as_m(set1i(0));\n";
          for (int side = 0; side < 2; ++side) {
            const uint32_t tgt = side ? a[2] : a[1];
            const std::string sm = side ? mf : mt;
            if (tgt == merge) { edge(cur, tgt, sm, merge, acc); continue; }
            o() << "if (bits(" << sm << ")) {\n";
            ++indent_;
            o() << "vm M = " << sm << ";\n";
            if (edge(cur, tgt, "M", merge, acc)) emitFrom(tgt, merge, acc);
            --indent_;
            o() << "}\n";
          }
          o() << "M = " << acc << " & alive;\n";
          if (loopTarget(merge, "M")) return;
          if (merge == stop) {
            if (!stopAcc.empty()) o() << stopAcc << " = " << stopAcc << " | M;\n";
            return;
          }
          cur = merge;
          continue;
        }
        // Loop-control branch: one or both sides leave (break / continue / back edge).
        std::vector<std::pair<uint32_t, std::string>> normal;
        for (int side = 0; side < 2; ++side) {
          const uint32_t tgt = side ? a[2] : a[1];
          const std::string sm = side ? mf : mt;
          if (edge(cur, tgt, sm, stop, stopAcc)) normal.push_back({tgt, sm});
        }
        if (normal.empty()) return;
        if (normal.size() == 2) {
          if (normal[0].first != normal[1].first) throw Unsupported("unstructured conditional branch");
          cur = normal[0].first;
          continue;
        }
        o() << "M = " << normal[0].second << ";\n";
        cur = normal[0].first;
        continue;
      }
      if (top == OpSwitch) {
        if (!sel) throw Unsupported("switch without merge");
        const std::string acc = fresh("R"), done = fresh("sd");
        o() << "vm " << acc << " = as_m(set1i(0)); vm " << done << " = as_m(set1i(0));\n";
        std::vector<std::pair<uint32_t, uint32_t>> cases;
        for (int k = 2; k + 1 < wc(ti) - 1; k += 2) cases.push_back({a[k], a[k + 1]});
        for (auto& cs : cases) {
          const std::string cm = fresh("cm");
          o() << "const vm " << cm << " = M & cmpeq(" << v(a[0], 0) << ", set1i(int32_t(" << cs.first << "u)));\n";
          o() << done << " = " << done << " | " << cm << ";\n";
          o() << "if (bits(" << cm << ")) {\n";
          ++indent_;
          o() << "vm M = " << cm << ";\n";
          if (edge(cur, cs.second, "M", merge, acc)) emitFrom(cs.second, merge, acc);
          --indent_;
          o() << "}\n";
        }
        const std::string dm = fresh("dm");
        o() << "const vm " << dm << " = andnot(" << done << ", M);\n";
        o() << "if (bits(" << dm << ")) {\n";
        ++indent_;
        o() << "vm M = " << dm << ";\n";
        if (edge(cur, a[1], "M", merge, acc)) emitFrom(a[1], merge, acc);
        --indent_;
        o() << "}\nM = " << acc << " & alive;\n";
        if (loopTarget(merge, "M")) return;
        if (merge == stop) {
          if (!stopAcc.empty()) o() << stopAcc << " = " << stopAcc << " | M;\n";
          return;
        }
        cur = merge;
        continue;
      }
      if (top == OpReturn || top == OpReturnValue) {
        if (!calls_.empty()) {
          CallCtx& cc = calls_.back();
          if (top == OpReturnValue && cc.result)
            for (uint32_t q = 0; q < comps(cc.result); ++q)
              o() << v(cc.result, q) << " = selecti(M, " << v(a[0], q) << ", " << v(cc.result, q) << ");\n";
          o() << cc.retAcc << " = " << cc.retAcc << " | M;\n";
          o() << "alive = andnot(M, alive);\n";
        } else {
          o() << "alive = andnot(M, alive);\n";
        }
        return;
      }
      if (top == OpKill) {
        o() << "killedM = killedM | M; alive = andnot(M, alive);\n";
        return;
      }
      if (top == OpUnreachable) return;
      throw Unsupported("terminator " + std::to_string(top));
    }
    throw Unsupported("control flow too deep");
  }

  void emitLoop(uint32_t header, uint32_t merge, uint32_t cont) {
    const int n = ++uniq_;
    const std::string s = std::to_string(n);
    o() << "{ // loop " << header << "\n";
    ++indent_;
    o() << "vm LM" << s << " = M, BM" << s << " = as_m(set1i(0));\n";
    o() << "for (int it" << s << " = 0; it" << s << " < 1000000; ++it" << s << ") {\n";
    ++indent_;
    o() << "vm M = LM" << s << "; vm CM" << s << " = as_m(set1i(0)), NL" << s << " = as_m(set1i(0));\n";
    loops_.push_back({header, merge, cont, n});
    emitFrom(header, 0, "", true);
    if (cont != header) {
      o() << "if (bits(CM" << s << ")) {\n";
      ++indent_;
      o() << "vm M = CM" << s << " & alive;\n";
      emitFrom(cont, header, "", false);
      --indent_;
      o() << "}\n";
    } else {
      o() << "NL" << s << " = NL" << s << " | CM" << s << ";\n";
    }
    loops_.pop_back();
    o() << "LM" << s << " = NL" << s << " & alive;\n";
    o() << "if (!bits(LM" << s << ")) break;\n";
    --indent_;
    o() << "}\n";
    o() << "M = BM" << s << " & alive;\n";
    --indent_;
    o() << "}\n";
  }

  void emitFunctionBody(uint32_t fnInst, const std::string&) {
    // parameters
    int i = int(fnInst) + 1;
    size_t argi = 0;
    for (; i < int(m_.insts.size()) && m_.insts[i].op == OpFunctionParameter; ++i) {
      const uint32_t* a = ops(i);
      if (argi < pendingArgs_.size()) {
        const uint32_t src = pendingArgs_[argi++];
        if (imageVar_.count(src)) {
          imageVar_[a[1]] = imageVar_[src];
        } else if (m_.types[a[0]].kind == Kind::Pointer) {
          ptr_[a[1]] = basePtr(src);
        } else {
          declare(a[1]);
          for (uint32_t q = 0; q < comps(a[1]); ++q) o() << v(a[1], q) << " = " << v(src, q) << ";\n";
        }
      }
    }
    // first label
    while (i < int(m_.insts.size()) && m_.insts[i].op != OpLabel) ++i;
    const uint32_t first = W[m_.insts[i].at + 1];
    // function-local variables (all OpVariable in the first block)
    for (int j = i + 1; j < blockEnd_[first]; ++j)
      if (m_.insts[j].op == OpVariable) {
        const uint32_t* a = ops(j);
        const uint32_t pointee = m_.types[a[0]].elem;
        const uint32_t c = std::max(1u, tcomps(pointee));
        if (declared_.insert(0x80000000u | a[1]).second)
          decl_ << "  alignas(32) uint32_t F" << a[1] << "[" << c * 8 << "] = {};\n";
        Ptr p;
        p.var = a[1]; p.type = pointee; p.kind = 1;
        ptr_[a[1]] = p;
        if (wc(j) > 4) {  // initializer
          for (uint32_t q = 0; q < c; ++q) o() << "storei(F" << a[1] << " + " << q * 8 << ", " << v(a[3], q) << ");\n";
        }
      }
    emitFrom(first, 0, "");
  }

  void emitInst(int i) {
    const uint16_t op = m_.insts[i].op;
    const uint32_t* a = ops(i);
    switch (op) {
      case OpNop: case OpLine: case OpNoLine: case OpVariable: case OpControlBarrier: case OpMemoryBarrier: return;
      case OpLoad: emitLoad(a[1], a[2]); return;
      case OpStore: emitStore(a[0], a[1]); return;
      case OpAccessChain: case OpInBoundsAccessChain: emitAccessChain(i); return;
      case OpUndef: declare(a[1]); return;
      case OpCopyObject:
        if (imageVar_.count(a[2])) { imageVar_[a[1]] = imageVar_[a[2]]; return; }
        if (ptr_.count(a[2])) { ptr_[a[1]] = ptr_[a[2]]; return; }
        declare(a[1]);
        for (uint32_t q = 0; q < comps(a[1]); ++q) o() << v(a[1], q) << " = " << v(a[2], q) << ";\n";
        return;
      case OpSampledImage: case OpImage:
        if (!imageVar_.count(a[2])) throw Unsupported("image value");
        imageVar_[a[1]] = imageVar_[a[2]];
        return;
      case OpCompositeConstruct: {
        declare(a[1]);
        uint32_t k = 0;
        for (int j = 2; j < wc(i) - 1; ++j)
          for (uint32_t q = 0; q < comps(a[j]); ++q) o() << v(a[1], k++) << " = " << v(a[j], q) << ";\n";
        return;
      }
      case OpCompositeExtract: case OpCompositeInsert: {
        const bool ins = op == OpCompositeInsert;
        const uint32_t comp = ins ? a[3] : a[2];
        uint32_t t = m_.resultType[comp], off = 0;
        for (int k = ins ? 4 : 3; k < wc(i) - 1; ++k) {
          const spv::Type& tt = m_.types[t];
          const uint32_t ix = a[k];
          if (tt.kind == Kind::Struct) {
            for (uint32_t q = 0; q < ix; ++q) off += m_.types[tt.members[q]].comps;
            t = tt.members[ix];
          } else {
            off += ix * m_.types[tt.elem].comps;
            t = tt.elem;
          }
        }
        declare(a[1]);
        if (!ins) {
          for (uint32_t q = 0; q < m_.types[t].comps; ++q) o() << v(a[1], q) << " = " << v(comp, off + q) << ";\n";
        } else {
          for (uint32_t q = 0; q < comps(a[1]); ++q) o() << v(a[1], q) << " = " << v(comp, q) << ";\n";
          for (uint32_t q = 0; q < m_.types[t].comps; ++q) o() << v(a[1], off + q) << " = " << v(a[2], q) << ";\n";
        }
        return;
      }
      case OpVectorShuffle: {
        declare(a[1]);
        const uint32_t n1 = comps(a[2]);
        for (int k = 4; k < wc(i) - 1; ++k) {
          const uint32_t s = a[k];
          o() << v(a[1], uint32_t(k - 4)) << " = " << (s == 0xFFFFFFFFu ? std::string("set1i(0)") : s < n1 ? v(a[2], s) : v(a[3], s - n1)) << ";\n";
        }
        return;
      }
      case OpVectorExtractDynamic: {
        declare(a[1]);
        const uint32_t n = comps(a[2]);
        o() << v(a[1], 0) << " = " << v(a[2], 0) << ";\n";
        for (uint32_t q = 1; q < n; ++q)
          o() << v(a[1], 0) << " = selecti(cmpeq(" << v(a[3], 0) << ", set1i(" << q << ")), " << v(a[2], q) << ", " << v(a[1], 0) << ");\n";
        return;
      }
      case OpVectorInsertDynamic: {
        declare(a[1]);
        for (uint32_t q = 0; q < comps(a[1]); ++q)
          o() << v(a[1], q) << " = selecti(cmpeq(" << v(a[4], 0) << ", set1i(" << q << ")), " << v(a[3], 0) << ", " << v(a[2], q) << ");\n";
        return;
      }
      case OpVectorTimesScalar: case OpMatrixTimesScalar:
        declare(a[1]);
        for (uint32_t q = 0; q < comps(a[1]); ++q) o() << v(a[1], q) << " = I(F(" << v(a[2], q) << ") * F(" << v(a[3], 0) << "));\n";
        return;
      case OpMatrixTimesVector: {
        declare(a[1]);
        const uint32_t rows = comps(a[1]), cols = comps(a[3]);
        for (uint32_t r = 0; r < rows; ++r) {
          std::string s = "zerof()";
          for (uint32_t c = 0; c < cols; ++c) s = "fma(F(" + v(a[2], c * rows + r) + "), F(" + v(a[3], c) + "), " + s + ")";
          o() << v(a[1], r) << " = I(" << s << ");\n";
        }
        return;
      }
      case OpVectorTimesMatrix: {
        declare(a[1]);
        const uint32_t rows = comps(a[2]), cols = comps(a[1]);
        for (uint32_t c = 0; c < cols; ++c) {
          std::string s = "zerof()";
          for (uint32_t r = 0; r < rows; ++r) s = "fma(F(" + v(a[2], r) + "), F(" + v(a[3], c * rows + r) + "), " + s + ")";
          o() << v(a[1], c) << " = I(" << s << ");\n";
        }
        return;
      }
      case OpMatrixTimesMatrix: {
        declare(a[1]);
        const spv::Type& rt = m_.types[m_.resultType[a[1]]];
        const uint32_t rows = m_.types[rt.elem].count, cols = rt.count, inner = comps(a[2]) / rows;
        for (uint32_t j = 0; j < cols; ++j)
          for (uint32_t r = 0; r < rows; ++r) {
            std::string s = "zerof()";
            for (uint32_t k = 0; k < inner; ++k) s = "fma(F(" + v(a[2], k * rows + r) + "), F(" + v(a[3], j * inner + k) + "), " + s + ")";
            o() << v(a[1], j * rows + r) << " = I(" << s << ");\n";
          }
        return;
      }
      case OpTranspose: {
        declare(a[1]);
        const spv::Type& rt = m_.types[m_.resultType[a[1]]];
        const uint32_t rows = m_.types[rt.elem].count, cols = rt.count;
        for (uint32_t j = 0; j < cols; ++j)
          for (uint32_t r = 0; r < rows; ++r) o() << v(a[1], j * rows + r) << " = " << v(a[2], r * cols + j) << ";\n";
        return;
      }
      case OpOuterProduct: {
        declare(a[1]);
        const uint32_t rows = comps(a[2]), cols = comps(a[3]);
        for (uint32_t j = 0; j < cols; ++j)
          for (uint32_t r = 0; r < rows; ++r) o() << v(a[1], j * rows + r) << " = I(F(" << v(a[2], r) << ") * F(" << v(a[3], j) << "));\n";
        return;
      }
      case OpDot: {
        declare(a[1]);
        std::string s = "zerof()";
        for (uint32_t k = 0; k < comps(a[2]); ++k) s = "fma(F(" + v(a[2], k) + "), F(" + v(a[3], k) + "), " + s + ")";
        o() << v(a[1], 0) << " = I(" << s << ");\n";
        return;
      }
      case OpSelect: {
        declare(a[1]);
        const bool vecCond = comps(a[2]) > 1;
        for (uint32_t q = 0; q < comps(a[1]); ++q)
          o() << v(a[1], q) << " = selecti(as_m(" << v(a[2], vecCond ? q : 0) << "), " << v(a[3], q) << ", " << v(a[4], q) << ");\n";
        return;
      }
      case OpAny: case OpAll: {
        declare(a[1]);
        std::string s = v(a[2], 0);
        for (uint32_t k = 1; k < comps(a[2]); ++k) s = "(" + s + (op == OpAny ? " | " : " & ") + v(a[2], k) + ")";
        o() << v(a[1], 0) << " = " << s << ";\n";
        return;
      }
      case OpExtInst: extInst(i); return;
      case OpDPdx: case OpDPdxFine: case OpDPdxCoarse: case OpDPdy: case OpDPdyFine: case OpDPdyCoarse:
      case OpFwidth: case OpFwidthFine: case OpFwidthCoarse: {
        const bool isX = op == OpDPdx || op == OpDPdxFine || op == OpDPdxCoarse;
        const bool isW = op == OpFwidth || op == OpFwidthFine || op == OpFwidthCoarse;
        declare(a[1]);
        for (uint32_t q = 0; q < comps(a[1]); ++q) {
          o() << "{ alignas(32) float s[8], d[8]; store(s, F(" << v(a[2], q) << ")); for (int l = 0; l < 8; ++l) { "
              << "const int x0 = l & ~1, y0 = l & ~4; const float dx = s[x0 | 1] - s[x0], dy = s[y0 | 4] - s[y0]; d[l] = "
              << (isW ? "std::fabs(dx) + std::fabs(dy)" : isX ? "dx" : "dy") << "; } " << v(a[1], q) << " = I(load(d)); }\n";
        }
        return;
      }
      case OpImageSampleImplicitLod: case OpImageSampleExplicitLod: case OpImageSampleDrefImplicitLod:
      case OpImageSampleDrefExplicitLod: {
        const bool dref = op == OpImageSampleDrefImplicitLod || op == OpImageSampleDrefExplicitLod;
        const bool expl = op == OpImageSampleExplicitLod || op == OpImageSampleDrefExplicitLod;
        if (!imageVar_.count(a[2])) throw Unsupported("sample of unknown image");
        const spv::Variable& var = m_.vars[imageVar_[a[2]]];
        declare(a[1]);
        const uint32_t nc = comps(a[3]);
        const int lodArg = dref ? 6 : 5;  // operands: mask then Lod
        const bool hasLod = expl && wc(i) > lodArg + 1;
        o() << "{ alignas(32) uint32_t co[4*8], lo[8], rf[8], out[4*8];";
        for (uint32_t k = 0; k < std::min(nc, 4u); ++k) body_ << " storei(co + " << k * 8 << ", " << v(a[3], k) << ");";
        if (hasLod) body_ << " storei(lo, " << v(a[lodArg], 0) << ");";
        if (dref) body_ << " storei(rf, " << v(a[4], 0) << ");";
        body_ << " ctx->rt->sample(ctx, " << var.set << ", " << var.binding << ", co, " << nc << ", "
              << (hasLod ? "lo" : "nullptr") << ", " << (dref ? "rf" : "nullptr") << ", out);";
        for (uint32_t k = 0; k < comps(a[1]); ++k) body_ << " " << v(a[1], k) << " = loadi(out + " << k * 8 << ");";
        body_ << " }\n";
        return;
      }
      case OpImageRead: case OpImageFetch: {
        if (!imageVar_.count(a[2])) throw Unsupported("read of unknown image");
        const spv::Variable& var = m_.vars[imageVar_[a[2]]];
        declare(a[1]);
        const uint32_t nc = comps(a[3]);
        o() << "{ alignas(32) uint32_t co[4*8], out[4*8];";
        for (uint32_t k = 0; k < std::min(nc, 4u); ++k) body_ << " storei(co + " << k * 8 << ", " << v(a[3], k) << ");";
        body_ << " ctx->rt->imageRead(ctx, " << var.set << ", " << var.binding << ", co, " << nc << ", out);";
        for (uint32_t k = 0; k < std::min(comps(a[1]), 4u); ++k) body_ << " " << v(a[1], k) << " = loadi(out + " << k * 8 << ");";
        body_ << " }\n";
        return;
      }
      case OpImageWrite: {
        if (!imageVar_.count(a[0])) throw Unsupported("write of unknown image");
        const spv::Variable& var = m_.vars[imageVar_[a[0]]];
        const uint32_t nc = comps(a[1]), nt = comps(a[2]);
        o() << "{ alignas(32) uint32_t co[4*8], tx[4*8];";
        for (uint32_t k = 0; k < std::min(nc, 4u); ++k) body_ << " storei(co + " << k * 8 << ", " << v(a[1], k) << ");";
        for (uint32_t k = 0; k < std::min(nt, 4u); ++k) body_ << " storei(tx + " << k * 8 << ", " << v(a[2], k) << ");";
        body_ << " ctx->rt->imageWrite(ctx, " << var.set << ", " << var.binding << ", co, " << nc << ", tx, " << nt
              << ", uint32_t(bits(M)));";
        body_ << " }\n";
        return;
      }
      case OpImageQuerySizeLod: case OpImageQuerySize: case OpImageQueryLevels: {
        if (!imageVar_.count(a[2])) throw Unsupported("query of unknown image");
        const spv::Variable& var = m_.vars[imageVar_[a[2]]];
        declare(a[1]);
        o() << "{ uint32_t sz[3]; int lv = 1; alignas(32) int32_t lq[8] = {}; ";
        if (op == OpImageQuerySizeLod) body_ << "storei(lq, " << v(a[3], 0) << "); ";
        body_ << "ctx->rt->querySize(ctx, " << var.set << ", " << var.binding << ", lq[0], sz, &lv);";
        if (op == OpImageQueryLevels) body_ << " " << v(a[1], 0) << " = set1i(lv);";
        else for (uint32_t k = 0; k < std::min(comps(a[1]), 3u); ++k) body_ << " " << v(a[1], k) << " = set1i(int32_t(sz[" << k << "]));";
        body_ << " }\n";
        return;
      }
      case OpAtomicLoad: case OpAtomicStore: case OpAtomicExchange: case OpAtomicCompareExchange:
      case OpAtomicIIncrement: case OpAtomicIDecrement: case OpAtomicIAdd: case OpAtomicISub: case OpAtomicSMin:
      case OpAtomicUMin: case OpAtomicSMax: case OpAtomicUMax: case OpAtomicAnd: case OpAtomicOr: case OpAtomicXor: {
        const bool isStore = op == OpAtomicStore;
        Ptr p = basePtr(isStore ? a[0] : a[2]);
        if (p.kind != 2) throw Unsupported("atomic on non-buffer memory");
        const std::string B = "B" + std::to_string(p.var);
        std::string A = "set1i(0)", Bv = "set1i(0)";
        if (op == OpAtomicStore) A = v(a[3], 0);
        else if (op == OpAtomicCompareExchange) { A = v(a[6], 0); Bv = v(a[7], 0); }
        else if (op != OpAtomicLoad && op != OpAtomicIIncrement && op != OpAtomicIDecrement) A = v(a[5], 0);
        if (!isStore) declare(a[1]);
        o() << "if (" << B << ") { alignas(32) int32_t ox[8], va[8], vb2[8], rr[8] = {}; storei(ox, "
            << (p.dyn.empty() ? std::string("set1i(0)") : p.dyn) << " + set1i(" << p.off << ")); storei(va, " << A
            << "); storei(vb2, " << Bv << "); const int mm = bits(M); for (int l = 0; l < 8; ++l) if (mm >> l & 1) rr[l] = int32_t(ctx->rt->atomic("
            << op << ", reinterpret_cast<uint32_t*>(const_cast<uint8_t*>(" << B << ") + ox[l]), uint32_t(va[l]), uint32_t(vb2[l])));";
        if (!isStore) body_ << " " << v(a[1], 0) << " = loadi(rr);";
        body_ << " }\n";
        return;
      }
      case OpFunctionCall: {
        const uint32_t fn = a[2];
        const int fi = m_.functionInst[fn];
        if (fi < 0) throw Unsupported("call target");
        if (calls_.size() > 16) throw Unsupported("call depth");
        const std::string acc = fresh("RA");
        const uint32_t result = m_.types[a[0]].kind == Kind::Void ? 0u : a[1];
        if (result) declare(result);
        o() << "{ vm " << acc << " = as_m(set1i(0)); vm Mcall = M; const vm aliveCall" << uniq_ << " = alive;\n";
        const int saveId = uniq_;
        ++indent_;
        o() << "{ vm M = Mcall;\n";
        ++indent_;
        pendingArgs_.assign(a + 3, a + wc(i) - 1);
        calls_.push_back({acc, result});
        emitFunctionBody(uint32_t(fi), "");
        calls_.pop_back();
        --indent_;
        o() << "}\n";
        o() << "alive = andnot(killedM, aliveCall" << saveId << ");\n";
        o() << "M = " << acc << " & alive;\n";
        --indent_;
        o() << "}\n";
        return;
      }
      default:
        if (op >= OpConvertFToU && op <= OpNot) { elementwise(i); return; }
        throw Unsupported("opcode " + std::to_string(op));
    }
  }
};

uint64_t fnv1a(const std::string& s) {
  uint64_t h = 1469598103934665603ull;
  for (unsigned char c : s) { h ^= c; h *= 1099511628211ull; }
  return h;
}

std::string cacheDir() {
  if (const char* d = std::getenv("JSNOW_JIT_CACHE")) return d;
  if (const char* h = std::getenv("HOME")) return std::string(h) + "/.cache/jsnow-jit";
  return "/tmp/jsnow-jit";
}

}  // namespace

std::string generate(const spv::Module& m, std::string& err) {
  try {
    Gen g(m);
    return g.run();
  } catch (const std::exception& e) {
    err = e.what();
    return {};
  }
}

jsnow_jit::ShaderFn compile(const spv::Module& m, std::string& err) {
  const std::string src = generate(m, err);
  if (src.empty()) return nullptr;
  const std::string dir = cacheDir();
  mkdir((dir.substr(0, dir.rfind('/'))).c_str(), 0755);
  mkdir(dir.c_str(), 0755);
  char name[64];
#if defined(__aarch64__)
  const char* arch = "a64";
  const char* flags = "";
#else
  const char* arch = "x64";
  const char* flags = "-mavx2 -mfma";
#endif
  std::snprintf(name, sizeof name, "%016llx_%s", (unsigned long long)fnv1a(src), arch);
  const std::string base = dir + "/" + name, so = base + ".so", cpp = base + ".cpp";
  if (access(so.c_str(), R_OK) != 0) {
    if (FILE* f = std::fopen(cpp.c_str(), "w")) { std::fputs(src.c_str(), f); std::fclose(f); }
    else { err = "cannot write " + cpp; return nullptr; }
    const char* cxx = std::getenv("JSNOW_JIT_CXX");
    std::string cmd = std::string(cxx ? cxx : "c++") + " -std=c++17 -O2 -fPIC -shared -fvisibility=hidden " + flags +
                      " -I" JSNOW_SRC_DIR " -I" JSNOW_ICD_DIR " -o " + so + ".tmp " + cpp + " 2> " + base + ".log && mv " +
                      so + ".tmp " + so;
    if (std::system(cmd.c_str()) != 0) { err = "compile failed, see " + base + ".log"; return nullptr; }
  }
  void* h = dlopen(so.c_str(), RTLD_NOW | RTLD_LOCAL);
  if (!h) { err = dlerror(); return nullptr; }
  auto fn = reinterpret_cast<jsnow_jit::ShaderFn>(dlsym(h, "jsnow_shader"));
  if (!fn) err = "symbol missing";
  return fn;
}

}  // namespace jit
