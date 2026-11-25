// JSNOW Vulkan ICD: a CPU-only Vulkan 1.0 driver (subset).
// Loader interface version 2 (the loader owns WSI surfaces).
#define VK_USE_PLATFORM_XCB_KHR 1
#include <xcb/xcb.h>
#include <vulkan/vk_icd.h>
#include <vulkan/vulkan.h>
#include <xcb/xcb.h>

#include <algorithm>
#include <array>
#include <thread>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

#include "../src/threadpool.hpp"
#include "spirv.hpp"

#define JSNOW_EXPORT extern "C" __attribute__((visibility("default")))

namespace icd {

// ------------------------------------------------------------------ logging
std::mutex gLogMutex;
std::vector<std::string> gMissing;  // unsupported features hit at runtime (deduplicated)
void missing(const std::string& what) {
  std::lock_guard<std::mutex> lk(gLogMutex);
  if (std::find(gMissing.begin(), gMissing.end(), what) != gMissing.end()) return;
  gMissing.push_back(what);
  std::fprintf(stderr, "[jsnow-icd] unsupported: %s\n", what.c_str());
}
struct MissingReport {
  ~MissingReport() {
    if (const char* p = std::getenv("JSNOW_ICD_MISSING_LOG")) {
      if (FILE* f = std::fopen(p, "a")) {
        for (auto& s : gMissing) std::fprintf(f, "%s\n", s.c_str());
        std::fclose(f);
      }
    }
  }
} gMissingReport;

// ------------------------------------------------------------------ objects
struct Instance { VK_LOADER_DATA ld; struct PhysicalDevice* pd; };
struct PhysicalDevice { VK_LOADER_DATA ld; Instance* inst; };
struct Queue;
struct Device {
  VK_LOADER_DATA ld;
  Queue* queue;
  std::unique_ptr<jsnow::ThreadPool> pool;
};
struct Queue { VK_LOADER_DATA ld; Device* dev; };

struct Memory { uint8_t* data = nullptr; VkDeviceSize size = 0; };
struct Buffer { VkDeviceSize size = 0; Memory* mem = nullptr; VkDeviceSize offset = 0;
  uint8_t* ptr() const { return mem ? mem->data + offset : nullptr; } };

int formatSize(VkFormat f) {
  switch (f) {
    case VK_FORMAT_R8G8B8A8_UNORM: case VK_FORMAT_R8G8B8A8_SRGB: case VK_FORMAT_B8G8R8A8_UNORM:
    case VK_FORMAT_B8G8R8A8_SRGB: case VK_FORMAT_D32_SFLOAT: case VK_FORMAT_R32_SFLOAT: case VK_FORMAT_R32_UINT:
    case VK_FORMAT_R32_SINT: case VK_FORMAT_D24_UNORM_S8_UINT: case VK_FORMAT_X8_D24_UNORM_PACK32:
    case VK_FORMAT_A8B8G8R8_UNORM_PACK32:
      return 4;
    case VK_FORMAT_D16_UNORM: case VK_FORMAT_R8G8_UNORM: return 2;
    case VK_FORMAT_R8_UNORM: return 1;
    case VK_FORMAT_R32G32_SFLOAT: case VK_FORMAT_D32_SFLOAT_S8_UINT: return 8;
    case VK_FORMAT_R32G32B32_SFLOAT: return 12;
    case VK_FORMAT_R32G32B32A32_SFLOAT: return 16;
    default: return 0;
  }
}
bool isDepth(VkFormat f) {
  return f == VK_FORMAT_D16_UNORM || f == VK_FORMAT_D32_SFLOAT || f == VK_FORMAT_D24_UNORM_S8_UINT ||
         f == VK_FORMAT_X8_D24_UNORM_PACK32 || f == VK_FORMAT_D32_SFLOAT_S8_UINT;
}

struct Image {
  VkFormat format = VK_FORMAT_UNDEFINED;
  uint32_t w = 1, h = 1, levels = 1, layers = 1;
  int bpp = 4;
  Memory* mem = nullptr;
  VkDeviceSize offset = 0;
  std::vector<VkDeviceSize> levelOffset;  // within a layer
  VkDeviceSize layerSize = 0, size = 0;
  std::unique_ptr<uint8_t[]> own;  // swapchain images
  uint8_t* base() const { return own ? own.get() : mem ? mem->data + offset : nullptr; }
  uint32_t pitch(uint32_t level) const { return std::max(1u, w >> level) * bpp; }
  uint8_t* at(uint32_t level, uint32_t layer, uint32_t x, uint32_t y) const {
    return base() + layer * layerSize + levelOffset[level] + size_t(y) * pitch(level) + size_t(x) * bpp;
  }
  void init() {
    bpp = formatSize(format);
    levelOffset.clear();
    VkDeviceSize o = 0;
    for (uint32_t l = 0; l < levels; ++l) {
      levelOffset.push_back(o);
      o += VkDeviceSize(std::max(1u, w >> l)) * std::max(1u, h >> l) * bpp;
    }
    layerSize = (o + 15) & ~VkDeviceSize(15);
    size = layerSize * layers;
  }
};
struct ImageView { Image* img; VkFormat format; uint32_t baseLevel, levels, baseLayer; };
struct Sampler { VkSamplerCreateInfo ci; };
struct ShaderModule { std::shared_ptr<spv::Module> mod; };
struct DescriptorSetLayout { std::vector<VkDescriptorSetLayoutBinding> bindings; };
struct Descriptor {
  VkDescriptorType type = VK_DESCRIPTOR_TYPE_MAX_ENUM;
  Buffer* buf = nullptr; VkDeviceSize offset = 0, range = 0;
  ImageView* view = nullptr; Sampler* sampler = nullptr;
  spv::Texture tex;  // prepared on update
};
struct DescriptorSet { std::vector<Descriptor> b; };
struct DescriptorPool { std::vector<DescriptorSet*> sets; };
struct PipelineLayout { std::vector<DescriptorSetLayout*> sets; };
struct RenderPass {
  std::vector<VkAttachmentDescription> att;
  std::vector<uint32_t> color;  // attachment indices of subpass 0
  int depth = -1;
};
struct Framebuffer { std::vector<ImageView*> views; uint32_t w, h; };
struct Pipeline {
  std::shared_ptr<spv::Module> vs, fs;
  std::vector<VkVertexInputBindingDescription> bindings;
  std::vector<VkVertexInputAttributeDescription> attrs;
  VkPrimitiveTopology topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
  VkCullModeFlags cull = VK_CULL_MODE_NONE;
  VkFrontFace front = VK_FRONT_FACE_COUNTER_CLOCKWISE;
  bool depthTest = false, depthWrite = false;
  VkCompareOp depthOp = VK_COMPARE_OP_LESS;
  VkPipelineColorBlendAttachmentState blend{};
  bool hasBlend = false;
  VkViewport viewport{};
  VkRect2D scissor{};
  bool dynViewport = false, dynScissor = false;
};
struct Fence { bool signaled = false; };
struct Semaphore { int dummy; };
struct CommandPool { int dummy; };

struct Exec;
struct CommandBuffer {
  VK_LOADER_DATA ld;
  std::vector<std::function<void(Exec&)>> cmds;
};

struct Swapchain {
  VkIcdSurfaceXcb* surf = nullptr;
  std::vector<Image*> images;
  uint32_t next = 0;
  xcb_gcontext_t gc = 0;
  uint64_t presented = 0;
};

template <class T, class H> T* to(H h) { return reinterpret_cast<T*>(h); }
template <class H, class T> H from(T* p) { return reinterpret_cast<H>(p); }

// --------------------------------------------------------------- execution
struct Exec : spv::Resources {
  Device* dev = nullptr;
  RenderPass* rp = nullptr;
  Framebuffer* fb = nullptr;
  VkRect2D area{};
  Pipeline* pipe = nullptr;
  DescriptorSet* sets[8] = {};
  std::vector<uint32_t> dynOffsets[8];
  struct VB { Buffer* b = nullptr; VkDeviceSize off = 0; } vbs[16];
  Buffer* ib = nullptr;
  VkDeviceSize ibOff = 0;
  VkIndexType ibType = VK_INDEX_TYPE_UINT16;
  VkViewport vp{};
  VkRect2D scissor{};
  uint8_t push[256] = {};
  const uint8_t* buffer(int set, int binding) const override {
    if (set < 0 || set >= 8 || !sets[set] || binding < 0 || size_t(binding) >= sets[set]->b.size()) return nullptr;
    const Descriptor& d = sets[set]->b[binding];
    if (!d.buf) return nullptr;
    VkDeviceSize off = d.offset;
    if (d.type == VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC || d.type == VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC) {
      // dynamic offsets are consumed in binding order
      int k = 0;
      for (int i = 0; i < binding; ++i) {
        const auto t = sets[set]->b[i].type;
        if (t == VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC || t == VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC) ++k;
      }
      if (size_t(k) < dynOffsets[set].size()) off += dynOffsets[set][k];
    }
    return d.buf->ptr() + off;
  }
  const spv::Texture* texture(int set, int binding) const override {
    if (set < 0 || set >= 8 || !sets[set] || binding < 0 || size_t(binding) >= sets[set]->b.size()) return nullptr;
    const Descriptor& d = sets[set]->b[binding];
    return d.view ? &d.tex : nullptr;
  }
};

void prepareTexture(Descriptor& d) {
  if (!d.view) return;
  Image* im = d.view->img;
  spv::Texture& t = d.tex;
  t.data = im->base() + d.view->baseLayer * im->layerSize;
  t.width = int(std::max(1u, im->w >> d.view->baseLevel));
  t.height = int(std::max(1u, im->h >> d.view->baseLevel));
  t.levels = int(d.view->levels);
  t.levelOffset.clear(); t.levelPitch.clear();
  for (uint32_t l = d.view->baseLevel; l < im->levels; ++l) {
    t.levelOffset.push_back(im->levelOffset[l]);
    t.levelPitch.push_back(int(im->pitch(l)));
  }
  const VkFormat f = d.view->format;
  t.format = (f == VK_FORMAT_B8G8R8A8_UNORM || f == VK_FORMAT_B8G8R8A8_SRGB) ? 1
             : f == VK_FORMAT_R32G32B32A32_SFLOAT ? 2 : 0;
  if (formatSize(f) != 4 && t.format != 2) missing("texture format " + std::to_string(int(f)));
  if (d.sampler) {
    t.linear = d.sampler->ci.magFilter == VK_FILTER_LINEAR;
    auto am = [](VkSamplerAddressMode m) {
      return m == VK_SAMPLER_ADDRESS_MODE_MIRRORED_REPEAT ? 1
             : (m == VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE || m == VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER) ? 2 : 0;
    };
    t.addressU = am(d.sampler->ci.addressModeU);
    t.addressV = am(d.sampler->ci.addressModeV);
  }
}

// Colour / depth attachment access.
void writeColor(VkFormat f, uint8_t* p, const float c[4]) {
  auto q = [](float v) { return uint8_t(std::clamp(v, 0.0f, 1.0f) * 255.0f + 0.5f); };
  switch (f) {
    case VK_FORMAT_B8G8R8A8_UNORM: case VK_FORMAT_B8G8R8A8_SRGB:
      p[0] = q(c[2]); p[1] = q(c[1]); p[2] = q(c[0]); p[3] = q(c[3]); break;
    case VK_FORMAT_R8G8B8A8_UNORM: case VK_FORMAT_R8G8B8A8_SRGB: case VK_FORMAT_A8B8G8R8_UNORM_PACK32:
      p[0] = q(c[0]); p[1] = q(c[1]); p[2] = q(c[2]); p[3] = q(c[3]); break;
    case VK_FORMAT_R32G32B32A32_SFLOAT: std::memcpy(p, c, 16); break;
    case VK_FORMAT_R32_SFLOAT: std::memcpy(p, c, 4); break;
    default: break;
  }
}
void readColor(VkFormat f, const uint8_t* p, float c[4]) {
  switch (f) {
    case VK_FORMAT_B8G8R8A8_UNORM: case VK_FORMAT_B8G8R8A8_SRGB:
      c[0] = p[2] / 255.0f; c[1] = p[1] / 255.0f; c[2] = p[0] / 255.0f; c[3] = p[3] / 255.0f; break;
    case VK_FORMAT_R32G32B32A32_SFLOAT: std::memcpy(c, p, 16); break;
    default:
      c[0] = p[0] / 255.0f; c[1] = p[1] / 255.0f; c[2] = p[2] / 255.0f; c[3] = p[3] / 255.0f; break;
  }
}
float readDepth(VkFormat f, const uint8_t* p) {
  if (f == VK_FORMAT_D16_UNORM) { uint16_t v; std::memcpy(&v, p, 2); return v / 65535.0f; }
  if (f == VK_FORMAT_D24_UNORM_S8_UINT || f == VK_FORMAT_X8_D24_UNORM_PACK32) {
    uint32_t v; std::memcpy(&v, p, 4); return (v & 0xFFFFFF) / 16777215.0f;
  }
  float v; std::memcpy(&v, p, 4); return v;
}
void writeDepth(VkFormat f, uint8_t* p, float d) {
  d = std::clamp(d, 0.0f, 1.0f);
  if (f == VK_FORMAT_D16_UNORM) { uint16_t v = uint16_t(d * 65535.0f + 0.5f); std::memcpy(p, &v, 2); return; }
  if (f == VK_FORMAT_D24_UNORM_S8_UINT || f == VK_FORMAT_X8_D24_UNORM_PACK32) {
    uint32_t v; std::memcpy(&v, p, 4); v = (v & 0xFF000000u) | uint32_t(d * 16777215.0f + 0.5f); std::memcpy(p, &v, 4);
    return;
  }
  std::memcpy(p, &d, 4);
}
bool depthPass(VkCompareOp op, float z, float d) {
  switch (op) {
    case VK_COMPARE_OP_NEVER: return false;
    case VK_COMPARE_OP_LESS: return z < d;
    case VK_COMPARE_OP_EQUAL: return z == d;
    case VK_COMPARE_OP_LESS_OR_EQUAL: return z <= d;
    case VK_COMPARE_OP_GREATER: return z > d;
    case VK_COMPARE_OP_NOT_EQUAL: return z != d;
    case VK_COMPARE_OP_GREATER_OR_EQUAL: return z >= d;
    default: return true;
  }
}
float blendFactor(VkBlendFactor f, const float s[4], const float d[4], int ch) {
  switch (f) {
    case VK_BLEND_FACTOR_ZERO: return 0;
    case VK_BLEND_FACTOR_ONE: return 1;
    case VK_BLEND_FACTOR_SRC_COLOR: return s[ch];
    case VK_BLEND_FACTOR_ONE_MINUS_SRC_COLOR: return 1 - s[ch];
    case VK_BLEND_FACTOR_DST_COLOR: return d[ch];
    case VK_BLEND_FACTOR_ONE_MINUS_DST_COLOR: return 1 - d[ch];
    case VK_BLEND_FACTOR_SRC_ALPHA: return s[3];
    case VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA: return 1 - s[3];
    case VK_BLEND_FACTOR_DST_ALPHA: return d[3];
    case VK_BLEND_FACTOR_ONE_MINUS_DST_ALPHA: return 1 - d[3];
    default: missing("blend factor " + std::to_string(int(f))); return 1;
  }
}

// One post-viewport vertex: screen x, y, z, 1/w and the varyings divided by w.
struct SVert { float x, y, z, q; };

void drawPrimitives(Exec& ex, const std::vector<uint32_t>& vertexIds, uint32_t instance);

void cmdDraw(Exec& ex, uint32_t count, uint32_t instances, uint32_t first, uint32_t firstInstance, bool indexed,
             int32_t vertexOffset) {
  if (!ex.pipe || !ex.fb) return;
  std::vector<uint32_t> ids(count);
  if (indexed) {
    const uint8_t* ib = ex.ib ? ex.ib->ptr() + ex.ibOff : nullptr;
    if (!ib) return;
    for (uint32_t i = 0; i < count; ++i) {
      uint32_t v;
      if (ex.ibType == VK_INDEX_TYPE_UINT16) { uint16_t s; std::memcpy(&s, ib + 2 * (first + i), 2); v = s; }
      else std::memcpy(&v, ib + 4 * (first + i), 4);
      ids[i] = uint32_t(int32_t(v) + vertexOffset);
    }
  } else {
    for (uint32_t i = 0; i < count; ++i) ids[i] = first + i;
  }
  for (uint32_t inst = 0; inst < instances; ++inst) drawPrimitives(ex, ids, firstInstance + inst);
}

void drawPrimitives(Exec& ex, const std::vector<uint32_t>& ids, uint32_t instance) {
  Pipeline& P = *ex.pipe;
  if (!P.vs || !P.fs) return;
  const spv::Module& vs = *P.vs;
  const spv::Module& fs = *P.fs;
  // ---- vertex shading (unique vertex ids, 8 per batch) ----
  std::vector<uint32_t> uniq = ids;
  std::sort(uniq.begin(), uniq.end());
  uniq.erase(std::unique(uniq.begin(), uniq.end()), uniq.end());
  std::unordered_map<uint32_t, uint32_t> slot;
  slot.reserve(uniq.size() * 2);
  for (uint32_t i = 0; i < uniq.size(); ++i) slot[uniq[i]] = i;
  uint32_t posVar = 0;
  const int posComp = vs.findBuiltinOutputComp(0, posVar);  // BuiltIn Position
  const auto vsOut = vs.locationVars(3);
  const auto vsIn = vs.locationVars(1);
  const int vidVar = vs.findBuiltinInput(42), iidVar = vs.findBuiltinInput(43);
  std::vector<uint32_t> outComps;
  uint32_t K = 0;  // varying floats per vertex
  for (auto& o : vsOut) { outComps.push_back(vs.types[vs.vars[o.second].type].comps); K += outComps.back(); }
  const uint32_t stride = 4 + K;
  std::vector<float> vout(uniq.size() * stride, 0.0f);
  {
    spv::Invocation inv(vs);
    for (size_t b = 0; b < uniq.size(); b += 8) {
      const int n = int(std::min<size_t>(8, uniq.size() - b));
      if (vidVar >= 0) {
        int32_t* v = reinterpret_cast<int32_t*>(inv.input(uint32_t(vidVar)));
        for (int l = 0; l < 8; ++l) v[l] = int32_t(uniq[b + std::min(l, n - 1)]);
      }
      if (iidVar >= 0) {
        int32_t* v = reinterpret_cast<int32_t*>(inv.input(uint32_t(iidVar)));
        for (int l = 0; l < 8; ++l) v[l] = int32_t(instance);
      }
      for (auto& in : vsIn) {
        const auto* attr = [&]() -> const VkVertexInputAttributeDescription* {
          for (auto& a : P.attrs) if (int(a.location) == in.first) return &a;
          return nullptr;
        }();
        float* dst = inv.input(in.second);
        const uint32_t nc = vs.types[vs.vars[in.second].type].comps;
        for (uint32_t c = 0; c < nc; ++c)
          for (int l = 0; l < 8; ++l) dst[c * 8 + l] = c == 3 ? 1.0f : 0.0f;
        if (!attr) continue;
        const VkVertexInputBindingDescription* bd = nullptr;
        for (auto& bb : P.bindings) if (bb.binding == attr->binding) bd = &bb;
        if (!bd || !ex.vbs[attr->binding].b) continue;
        const uint8_t* base = ex.vbs[attr->binding].b->ptr() + ex.vbs[attr->binding].off + attr->offset;
        for (int l = 0; l < 8; ++l) {
          const uint32_t idx = bd->inputRate == VK_VERTEX_INPUT_RATE_INSTANCE ? instance : uniq[b + std::min(l, n - 1)];
          const uint8_t* p = base + size_t(idx) * bd->stride;
          float c4[4] = {0, 0, 0, 1};
          switch (attr->format) {
            case VK_FORMAT_R32_SFLOAT: std::memcpy(c4, p, 4); break;
            case VK_FORMAT_R32G32_SFLOAT: std::memcpy(c4, p, 8); break;
            case VK_FORMAT_R32G32B32_SFLOAT: std::memcpy(c4, p, 12); break;
            case VK_FORMAT_R32G32B32A32_SFLOAT: std::memcpy(c4, p, 16); break;
            case VK_FORMAT_R8G8B8A8_UNORM: for (int c = 0; c < 4; ++c) c4[c] = p[c] / 255.0f; break;
            case VK_FORMAT_B8G8R8A8_UNORM: for (int c = 0; c < 4; ++c) c4[c] = p[c == 3 ? 3 : 2 - c] / 255.0f; break;
            default: missing("vertex format " + std::to_string(int(attr->format))); break;
          }
          for (uint32_t c = 0; c < std::min(nc, 4u); ++c) dst[c * 8 + l] = c4[c];
        }
      }
      inv.run(ex, 0xFF);
      if (!inv.error.empty()) { missing("vertex shader: " + inv.error); return; }
      for (int l = 0; l < n; ++l) {
        float* o = vout.data() + (b + l) * stride;
        if (posComp >= 0) for (int c = 0; c < 4; ++c) o[c] = inv.output(posVar)[(posComp + c) * 8 + l];
        uint32_t k = 4;
        for (size_t i = 0; i < vsOut.size(); ++i)
          for (uint32_t c = 0; c < outComps[i]; ++c) o[k++] = inv.output(vsOut[i].second)[c * 8 + l];
      }
    }
  }
  // ---- primitive assembly + clipping (z >= 0, z <= w, guard band) ----
  struct Tri { std::vector<float> v[3]; };
  std::vector<std::array<std::vector<float>, 3>> tris;
  auto vtx = [&](uint32_t i) { const float* p = vout.data() + size_t(slot[ids[i]]) * stride; return std::vector<float>(p, p + stride); };
  std::vector<std::array<uint32_t, 3>> prims;
  if (P.topology == VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST) {
    for (size_t i = 0; i + 2 < ids.size(); i += 3) prims.push_back({uint32_t(i), uint32_t(i + 1), uint32_t(i + 2)});
  } else if (P.topology == VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP) {
    for (size_t i = 0; i + 2 < ids.size(); ++i)
      prims.push_back((i & 1) ? std::array<uint32_t, 3>{uint32_t(i + 1), uint32_t(i), uint32_t(i + 2)}
                              : std::array<uint32_t, 3>{uint32_t(i), uint32_t(i + 1), uint32_t(i + 2)});
  } else if (P.topology == VK_PRIMITIVE_TOPOLOGY_TRIANGLE_FAN) {
    for (size_t i = 1; i + 1 < ids.size(); ++i) prims.push_back({0, uint32_t(i), uint32_t(i + 1)});
  } else {
    missing("primitive topology " + std::to_string(int(P.topology)));
    return;
  }
  const VkViewport vp = P.dynViewport ? ex.vp : P.viewport;
  const VkRect2D sc = P.dynScissor ? ex.scissor : P.scissor;
  struct STri { SVert v[3]; std::vector<float> var[3]; bool front; };
  std::vector<STri> stris;
  for (auto& pr : prims) {
    std::vector<std::vector<float>> poly = {vtx(pr[0]), vtx(pr[1]), vtx(pr[2])};
    for (int plane = 0; plane < 6 && poly.size() >= 3; ++plane) {
      auto dist = [&](const std::vector<float>& v) {
        const float G = 64.0f;
        switch (plane) {
          case 0: return v[2];             // z >= 0
          case 1: return v[3] - v[2];      // z <= w
          case 2: return G * v[3] - v[0];
          case 3: return G * v[3] + v[0];
          case 4: return G * v[3] - v[1];
          default: return G * v[3] + v[1];
        }
      };
      std::vector<std::vector<float>> out;
      for (size_t k = 0; k < poly.size(); ++k) {
        const auto& a = poly[k];
        const auto& b = poly[(k + 1) % poly.size()];
        const float da = dist(a), db = dist(b);
        if (da >= 0) out.push_back(a);
        if ((da >= 0) != (db >= 0)) {
          const float t = da / (da - db);
          std::vector<float> c(stride);
          for (uint32_t j = 0; j < stride; ++j) c[j] = a[j] + (b[j] - a[j]) * t;
          out.push_back(c);
        }
      }
      poly.swap(out);
    }
    if (poly.size() < 3) continue;
    std::vector<SVert> sv(poly.size());
    for (size_t k = 0; k < poly.size(); ++k) {
      const float q = 1.0f / poly[k][3];
      sv[k] = {vp.x + (poly[k][0] * q + 1) * vp.width * 0.5f, vp.y + (poly[k][1] * q + 1) * vp.height * 0.5f,
               vp.minDepth + poly[k][2] * q * (vp.maxDepth - vp.minDepth), q};
    }
    for (size_t k = 1; k + 1 < poly.size(); ++k) {
      STri t;
      const size_t idx[3] = {0, k, k + 1};
      for (int j = 0; j < 3; ++j) {
        t.v[j] = sv[idx[j]];
        t.var[j].assign(poly[idx[j]].begin() + 4, poly[idx[j]].end());
        for (float& x : t.var[j]) x *= sv[idx[j]].q;  // perspective-correct: interpolate var/w
      }
      // Vulkan area with y down: a = -1/2 sum(x_i y_{i+1} - x_{i+1} y_i); CCW front if a > 0.
      float a = 0;
      for (int j = 0; j < 3; ++j) a += t.v[j].x * t.v[(j + 1) % 3].y - t.v[(j + 1) % 3].x * t.v[j].y;
      a *= -0.5f;
      if (a == 0) continue;
      t.front = P.front == VK_FRONT_FACE_COUNTER_CLOCKWISE ? a > 0 : a < 0;
      if ((P.cull & VK_CULL_MODE_FRONT_BIT) && t.front) continue;
      if ((P.cull & VK_CULL_MODE_BACK_BIT) && !t.front) continue;
      stris.push_back(std::move(t));
    }
  }
  if (stris.empty()) return;
  // ---- rasterization: horizontal bands per thread, 4x2 pixel blocks ----
  RenderPass& rp = *ex.rp;
  ImageView* colorView = rp.color.empty() ? nullptr : ex.fb->views[rp.color[0]];
  ImageView* depthView = rp.depth >= 0 ? ex.fb->views[rp.depth] : nullptr;
  int x0 = std::max<int>(ex.area.offset.x, sc.offset.x), y0 = std::max<int>(ex.area.offset.y, sc.offset.y);
  int x1 = std::min<int>(ex.area.offset.x + int(ex.area.extent.width), sc.offset.x + int(sc.extent.width));
  int y1 = std::min<int>(ex.area.offset.y + int(ex.area.extent.height), sc.offset.y + int(sc.extent.height));
  x1 = std::min<int>(x1, int(ex.fb->w)); y1 = std::min<int>(y1, int(ex.fb->h));
  if (x0 >= x1 || y0 >= y1) return;
  const auto fsIn = fs.locationVars(1);
  const auto fsOut = fs.locationVars(3);
  const int fragCoordVar = fs.findBuiltinInput(15), frontVar = fs.findBuiltinInput(17);
  // Map fragment inputs to vertex outputs by location.
  std::vector<std::pair<uint32_t, uint32_t>> inMap;  // (fs var, offset into varyings)
  for (auto& fi : fsIn) {
    uint32_t off = 0;
    bool found = false;
    for (size_t i = 0; i < vsOut.size(); ++i) {
      if (vsOut[i].first == fi.first) { found = true; break; }
      off += outComps[i];
    }
    if (found) inMap.push_back({fi.second, off});
  }
  const int bands = std::max(1, std::min(ex.dev->pool->size() * 4, (y1 - y0 + 7) / 8));
  ex.dev->pool->run(bands, [&](int band, int) {
    const int by0 = y0 + (y1 - y0) * band / bands, by1 = y0 + (y1 - y0) * (band + 1) / bands;
    if (by0 >= by1) return;
    spv::Invocation inv(fs);
    for (const STri& t : stris) {
      const SVert& A = t.v[0]; const SVert& B = t.v[1]; const SVert& C = t.v[2];
      float area = (B.x - A.x) * (C.y - A.y) - (C.x - A.x) * (B.y - A.y);
      const float inv2 = 1.0f / area;
      const float minxf = std::min({A.x, B.x, C.x}), maxxf = std::max({A.x, B.x, C.x});
      const float minyf = std::min({A.y, B.y, C.y}), maxyf = std::max({A.y, B.y, C.y});
      int bx0 = std::max(x0, int(std::floor(minxf))), bx1 = std::min(x1 - 1, int(std::ceil(maxxf)));
      int yy0 = std::max(by0, int(std::floor(minyf))), yy1 = std::min(by1 - 1, int(std::ceil(maxyf)));
      if (bx0 > bx1 || yy0 > yy1) continue;
      bx0 &= ~3;
      yy0 &= ~1;
      // Edge functions (sign-normalised so inside >= 0).
      auto edge = [&](const SVert& p, const SVert& q, float x, float y) { return ((q.x - p.x) * (y - p.y) - (q.y - p.y) * (x - p.x)) * inv2; };
      for (int y = yy0; y <= yy1; y += 2)
        for (int x = bx0; x <= bx1; x += 4) {
          float l0[8], l1[8], l2[8];
          uint8_t cover = 0;
          for (int l = 0; l < 8; ++l) {
            const float px = x + (l & 3) + 0.5f, py = y + (l >> 2) + 0.5f;
            l0[l] = edge(B, C, px, py); l1[l] = edge(C, A, px, py); l2[l] = edge(A, B, px, py);
            const int X = x + (l & 3), Y = y + (l >> 2);
            if (l0[l] >= 0 && l1[l] >= 0 && l2[l] >= 0 && X >= x0 && X < x1 && Y >= by0 && Y < by1) cover |= 1 << l;
          }
          if (!cover) continue;
          float z[8], qn[8];
          for (int l = 0; l < 8; ++l) {
            z[l] = l0[l] * A.z + l1[l] * B.z + l2[l] * C.z;
            qn[l] = l0[l] * A.q + l1[l] * B.q + l2[l] * C.q;
          }
          // Early depth test.
          uint8_t pass = cover;
          if (depthView && P.depthTest)
            for (int l = 0; l < 8; ++l)
              if (pass & (1 << l)) {
                const uint8_t* dp = depthView->img->at(0, depthView->baseLayer, x + (l & 3), y + (l >> 2));
                if (!depthPass(P.depthOp, z[l], readDepth(depthView->format, dp))) pass &= uint8_t(~(1 << l));
              }
          if (!pass) continue;
          for (auto& im : inMap) {
            float* dst = inv.input(im.first);
            const uint32_t nc = fs.types[fs.vars[im.first].type].comps;
            for (uint32_t c = 0; c < nc; ++c)
              for (int l = 0; l < 8; ++l) {
                const float w = 1.0f / qn[l];
                dst[c * 8 + l] = (l0[l] * t.var[0][im.second + c] + l1[l] * t.var[1][im.second + c] +
                                  l2[l] * t.var[2][im.second + c]) * w;
              }
          }
          if (fragCoordVar >= 0) {
            float* fc = inv.input(uint32_t(fragCoordVar));
            for (int l = 0; l < 8; ++l) {
              fc[l] = x + (l & 3) + 0.5f; fc[8 + l] = y + (l >> 2) + 0.5f; fc[16 + l] = z[l]; fc[24 + l] = qn[l];
            }
          }
          if (frontVar >= 0) {
            uint32_t* ff = reinterpret_cast<uint32_t*>(inv.input(uint32_t(frontVar)));
            for (int l = 0; l < 8; ++l) ff[l] = t.front;
          }
          inv.run(ex, 0xFF);  // helper lanes run too (derivatives)
          if (!inv.error.empty()) { missing("fragment shader: " + inv.error); return; }
          pass &= uint8_t(~inv.killed());
          for (int l = 0; l < 8; ++l) {
            if (!(pass & (1 << l))) continue;
            const int X = x + (l & 3), Y = y + (l >> 2);
            if (depthView && P.depthWrite)
              writeDepth(depthView->format, depthView->img->at(0, depthView->baseLayer, X, Y), z[l]);
            if (colorView && !fsOut.empty()) {
              float c[4];
              for (int ch = 0; ch < 4; ++ch) c[ch] = inv.output(fsOut[0].second)[ch * 8 + l];
              uint8_t* cp = colorView->img->at(colorView->baseLevel, colorView->baseLayer, X, Y);
              if (P.hasBlend && P.blend.blendEnable) {
                float d[4];
                readColor(colorView->format, cp, d);
                float o[4];
                for (int ch = 0; ch < 4; ++ch) {
                  const bool alpha = ch == 3;
                  const float sf = blendFactor(alpha ? P.blend.srcAlphaBlendFactor : P.blend.srcColorBlendFactor, c, d, ch);
                  const float df = blendFactor(alpha ? P.blend.dstAlphaBlendFactor : P.blend.dstColorBlendFactor, c, d, ch);
                  o[ch] = c[ch] * sf + d[ch] * df;  // VK_BLEND_OP_ADD
                }
                std::memcpy(c, o, sizeof o);
              }
              writeColor(colorView->format, cp, c);
            }
          }
        }
    }
  });
}

void clearAttachment(ImageView* v, const VkClearValue& cv, const VkRect2D& r) {
  Image* im = v->img;
  for (uint32_t y = r.offset.y; y < r.offset.y + r.extent.height && y < im->h; ++y)
    for (uint32_t x = r.offset.x; x < r.offset.x + r.extent.width && x < im->w; ++x) {
      uint8_t* p = im->at(v->baseLevel, v->baseLayer, x, y);
      if (isDepth(v->format)) writeDepth(v->format, p, cv.depthStencil.depth);
      else writeColor(v->format, p, cv.color.float32);
    }
}

// ----------------------------------------------------------- present (xcb)
void present(Swapchain* sc, Image* im) {
  static const bool skip = std::getenv("JSNOW_ICD_NO_PRESENT") != nullptr;
  ++sc->presented;
  if (const char* dump = std::getenv("JSNOW_ICD_DUMP")) {  // "path.ppm:frame"
    std::string s(dump);
    const size_t c = s.rfind(':');
    const uint64_t frame = c == std::string::npos ? 1 : std::strtoull(s.c_str() + c + 1, nullptr, 10);
    if (sc->presented == frame) {
      if (FILE* f = std::fopen(s.substr(0, c).c_str(), "wb")) {
        std::fprintf(f, "P6\n%u %u\n255\n", im->w, im->h);
        for (uint32_t y = 0; y < im->h; ++y)
          for (uint32_t x = 0; x < im->w; ++x) {
            float col[4];
            readColor(im->format, im->at(0, 0, x, y), col);
            const uint8_t rgb[3] = {uint8_t(col[0] * 255 + 0.5f), uint8_t(col[1] * 255 + 0.5f), uint8_t(col[2] * 255 + 0.5f)};
            std::fwrite(rgb, 1, 3, f);
          }
        std::fclose(f);
      }
    }
  }
  if (skip || !sc->surf || !sc->surf->connection) return;
  xcb_connection_t* conn = sc->surf->connection;
  if (!sc->gc) {
    sc->gc = xcb_generate_id(conn);
    xcb_create_gc(conn, sc->gc, sc->surf->window, 0, nullptr);
  }
  xcb_get_geometry_reply_t* g = xcb_get_geometry_reply(conn, xcb_get_geometry(conn, sc->surf->window), nullptr);
  const uint8_t depth = g ? g->depth : 24;
  free(g);
  const uint32_t maxReq = xcb_get_maximum_request_length(conn) * 4;
  const uint32_t rowBytes = im->w * 4;
  const uint32_t rowsPer = std::max(1u, (maxReq - 64) / rowBytes);
  for (uint32_t y = 0; y < im->h; y += rowsPer) {
    const uint32_t rows = std::min(rowsPer, im->h - y);
    xcb_put_image(conn, XCB_IMAGE_FORMAT_Z_PIXMAP, sc->surf->window, sc->gc, uint16_t(im->w), uint16_t(rows), 0,
                  int16_t(y), 0, depth, rows * rowBytes, im->at(0, 0, 0, y));
  }
  xcb_flush(conn);
}

}  // namespace icd

using namespace icd;

// =================================================================== API
#define VKAPI extern "C" VKAPI_ATTR
static const VkExtensionProperties kInstanceExts[] = {{VK_KHR_SURFACE_EXTENSION_NAME, 25},
                                                      {VK_KHR_XCB_SURFACE_EXTENSION_NAME, 6}};
static const VkExtensionProperties kDeviceExts[] = {{VK_KHR_SWAPCHAIN_EXTENSION_NAME, 70}};

template <class T>
static VkResult fillArray(uint32_t* count, T* out, const T* src, uint32_t n) {
  if (!out) { *count = n; return VK_SUCCESS; }
  const uint32_t k = std::min(*count, n);
  for (uint32_t i = 0; i < k; ++i) out[i] = src[i];
  *count = k;
  return k < n ? VK_INCOMPLETE : VK_SUCCESS;
}

VKAPI VkResult VKAPI_CALL jsnow_EnumerateInstanceExtensionProperties(const char*, uint32_t* c, VkExtensionProperties* p) {
  return fillArray(c, p, kInstanceExts, 2);
}
VKAPI VkResult VKAPI_CALL jsnow_EnumerateInstanceVersion(uint32_t* v) { *v = VK_API_VERSION_1_1; return VK_SUCCESS; }
VKAPI VkResult VKAPI_CALL jsnow_CreateInstance(const VkInstanceCreateInfo*, const VkAllocationCallbacks*, VkInstance* out) {
  auto* inst = new Instance();
  set_loader_magic_value(inst);
  inst->pd = new PhysicalDevice();
  set_loader_magic_value(inst->pd);
  inst->pd->inst = inst;
  *out = from<VkInstance>(inst);
  return VK_SUCCESS;
}
VKAPI void VKAPI_CALL jsnow_DestroyInstance(VkInstance i, const VkAllocationCallbacks*) {
  if (!i) return;
  delete to<Instance>(i)->pd;
  delete to<Instance>(i);
}
VKAPI VkResult VKAPI_CALL jsnow_EnumeratePhysicalDevices(VkInstance i, uint32_t* c, VkPhysicalDevice* p) {
  VkPhysicalDevice pd = from<VkPhysicalDevice>(to<Instance>(i)->pd);
  return fillArray(c, p, &pd, 1);
}
VKAPI void VKAPI_CALL jsnow_GetPhysicalDeviceProperties(VkPhysicalDevice, VkPhysicalDeviceProperties* p) {
  std::memset(p, 0, sizeof *p);
  p->apiVersion = VK_API_VERSION_1_1;
  p->driverVersion = 1;
  p->vendorID = 0x10005;  // VK_VENDOR_ID_MESA-like placeholder
  p->deviceID = 1;
  p->deviceType = VK_PHYSICAL_DEVICE_TYPE_CPU;
  std::snprintf(p->deviceName, sizeof p->deviceName, "JSNOW CPU renderer");
  VkPhysicalDeviceLimits& L = p->limits;
  L.maxImageDimension1D = L.maxImageDimension2D = 8192; L.maxImageDimension3D = 256; L.maxImageDimensionCube = 8192;
  L.maxImageArrayLayers = 256; L.maxTexelBufferElements = 1 << 20; L.maxUniformBufferRange = 65536;
  L.maxStorageBufferRange = 1u << 27; L.maxPushConstantsSize = 128; L.maxMemoryAllocationCount = 4096;
  L.maxSamplerAllocationCount = 4000; L.bufferImageGranularity = 1; L.maxBoundDescriptorSets = 8;
  L.maxPerStageDescriptorSamplers = 16; L.maxPerStageDescriptorUniformBuffers = 12;
  L.maxPerStageDescriptorStorageBuffers = 4; L.maxPerStageDescriptorSampledImages = 16;
  L.maxPerStageDescriptorStorageImages = 4; L.maxPerStageDescriptorInputAttachments = 4; L.maxPerStageResources = 64;
  L.maxDescriptorSetSamplers = 96; L.maxDescriptorSetUniformBuffers = 72; L.maxDescriptorSetUniformBuffersDynamic = 8;
  L.maxDescriptorSetStorageBuffers = 24; L.maxDescriptorSetStorageBuffersDynamic = 4;
  L.maxDescriptorSetSampledImages = 96; L.maxDescriptorSetStorageImages = 24; L.maxDescriptorSetInputAttachments = 4;
  L.maxVertexInputAttributes = 16; L.maxVertexInputBindings = 16; L.maxVertexInputAttributeOffset = 2047;
  L.maxVertexInputBindingStride = 2048; L.maxVertexOutputComponents = 64; L.maxFragmentInputComponents = 64;
  L.maxFragmentOutputAttachments = 4; L.maxFragmentCombinedOutputResources = 4; L.maxComputeSharedMemorySize = 16384;
  L.maxComputeWorkGroupCount[0] = L.maxComputeWorkGroupCount[1] = L.maxComputeWorkGroupCount[2] = 65535;
  L.maxComputeWorkGroupInvocations = 128;
  L.maxComputeWorkGroupSize[0] = L.maxComputeWorkGroupSize[1] = 128; L.maxComputeWorkGroupSize[2] = 64;
  L.subPixelPrecisionBits = 4; L.subTexelPrecisionBits = 4; L.mipmapPrecisionBits = 4; L.maxDrawIndexedIndexValue = ~0u;
  L.maxDrawIndirectCount = 1; L.maxSamplerLodBias = 2; L.maxSamplerAnisotropy = 1; L.maxViewports = 1;
  L.maxViewportDimensions[0] = L.maxViewportDimensions[1] = 8192; L.viewportBoundsRange[0] = -16384;
  L.viewportBoundsRange[1] = 16384; L.minMemoryMapAlignment = 64; L.minTexelBufferOffsetAlignment = 16;
  L.minUniformBufferOffsetAlignment = 16; L.minStorageBufferOffsetAlignment = 16; L.maxTexelOffset = 7;
  L.minTexelOffset = -8; L.maxFramebufferWidth = L.maxFramebufferHeight = 8192; L.maxFramebufferLayers = 256;
  L.framebufferColorSampleCounts = L.framebufferDepthSampleCounts = L.framebufferNoAttachmentsSampleCounts =
      VK_SAMPLE_COUNT_1_BIT;
  L.maxColorAttachments = 4; L.sampledImageColorSampleCounts = L.sampledImageDepthSampleCounts =
      L.storageImageSampleCounts = VK_SAMPLE_COUNT_1_BIT;
  L.maxSampleMaskWords = 1; L.maxClipDistances = 8; L.maxCullDistances = 8; L.maxCombinedClipAndCullDistances = 8;
  L.discreteQueuePriorities = 2; L.pointSizeRange[0] = L.pointSizeRange[1] = 1; L.lineWidthRange[0] = 1;
  L.lineWidthRange[1] = 1; L.optimalBufferCopyOffsetAlignment = 1; L.optimalBufferCopyRowPitchAlignment = 1;
  L.nonCoherentAtomSize = 64; L.maxGeometryOutputVertices = 0; L.maxTessellationGenerationLevel = 0;
  L.timestampPeriod = 1;
}
VKAPI void VKAPI_CALL jsnow_GetPhysicalDeviceQueueFamilyProperties(VkPhysicalDevice, uint32_t* c, VkQueueFamilyProperties* p) {
  VkQueueFamilyProperties q{};
  q.queueFlags = VK_QUEUE_GRAPHICS_BIT | VK_QUEUE_COMPUTE_BIT | VK_QUEUE_TRANSFER_BIT;
  q.queueCount = 1;
  q.minImageTransferGranularity = {1, 1, 1};
  fillArray(c, p, &q, 1);
}
VKAPI void VKAPI_CALL jsnow_GetPhysicalDeviceFeatures(VkPhysicalDevice, VkPhysicalDeviceFeatures* f) {
  std::memset(f, 0, sizeof *f);
  f->fullDrawIndexUint32 = VK_TRUE;
}
VKAPI void VKAPI_CALL jsnow_GetPhysicalDeviceMemoryProperties(VkPhysicalDevice, VkPhysicalDeviceMemoryProperties* m) {
  std::memset(m, 0, sizeof *m);
  m->memoryTypeCount = 1;
  m->memoryTypes[0].propertyFlags = VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT | VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT |
                                    VK_MEMORY_PROPERTY_HOST_COHERENT_BIT | VK_MEMORY_PROPERTY_HOST_CACHED_BIT;
  m->memoryTypes[0].heapIndex = 0;
  m->memoryHeapCount = 1;
  m->memoryHeaps[0].size = VkDeviceSize(4) << 30;
  m->memoryHeaps[0].flags = VK_MEMORY_HEAP_DEVICE_LOCAL_BIT;
}
VKAPI void VKAPI_CALL jsnow_GetPhysicalDeviceFormatProperties(VkPhysicalDevice, VkFormat f, VkFormatProperties* p) {
  std::memset(p, 0, sizeof *p);
  const VkFormatFeatureFlags color = VK_FORMAT_FEATURE_SAMPLED_IMAGE_BIT | VK_FORMAT_FEATURE_COLOR_ATTACHMENT_BIT |
                                     VK_FORMAT_FEATURE_COLOR_ATTACHMENT_BLEND_BIT | VK_FORMAT_FEATURE_BLIT_SRC_BIT |
                                     VK_FORMAT_FEATURE_BLIT_DST_BIT | VK_FORMAT_FEATURE_SAMPLED_IMAGE_FILTER_LINEAR_BIT |
                                     VK_FORMAT_FEATURE_TRANSFER_SRC_BIT | VK_FORMAT_FEATURE_TRANSFER_DST_BIT;
  switch (f) {
    case VK_FORMAT_R8G8B8A8_UNORM: case VK_FORMAT_R8G8B8A8_SRGB: case VK_FORMAT_B8G8R8A8_UNORM:
    case VK_FORMAT_B8G8R8A8_SRGB:
      p->linearTilingFeatures = p->optimalTilingFeatures = color;
      p->bufferFeatures = VK_FORMAT_FEATURE_VERTEX_BUFFER_BIT;
      break;
    case VK_FORMAT_R32G32B32A32_SFLOAT:
      p->linearTilingFeatures = p->optimalTilingFeatures = color;
      p->bufferFeatures = VK_FORMAT_FEATURE_VERTEX_BUFFER_BIT;
      break;
    case VK_FORMAT_R32_SFLOAT: case VK_FORMAT_R32G32_SFLOAT: case VK_FORMAT_R32G32B32_SFLOAT:
      p->bufferFeatures = VK_FORMAT_FEATURE_VERTEX_BUFFER_BIT;
      break;
    case VK_FORMAT_D16_UNORM: case VK_FORMAT_D32_SFLOAT: case VK_FORMAT_D24_UNORM_S8_UINT:
      p->optimalTilingFeatures = VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT | VK_FORMAT_FEATURE_TRANSFER_SRC_BIT |
                                 VK_FORMAT_FEATURE_TRANSFER_DST_BIT;
      p->linearTilingFeatures = p->optimalTilingFeatures;
      break;
    default: break;
  }
}
VKAPI VkResult VKAPI_CALL jsnow_GetPhysicalDeviceImageFormatProperties(VkPhysicalDevice pd, VkFormat f, VkImageType,
                                                                     VkImageTiling, VkImageUsageFlags,
                                                                     VkImageCreateFlags, VkImageFormatProperties* p) {
  VkFormatProperties fp;
  jsnow_GetPhysicalDeviceFormatProperties(pd, f, &fp);
  if (!fp.optimalTilingFeatures) return VK_ERROR_FORMAT_NOT_SUPPORTED;
  p->maxExtent = {8192, 8192, 1};
  p->maxMipLevels = 14;
  p->maxArrayLayers = 256;
  p->sampleCounts = VK_SAMPLE_COUNT_1_BIT;
  p->maxResourceSize = VkDeviceSize(1) << 31;
  return VK_SUCCESS;
}
VKAPI void VKAPI_CALL jsnow_GetPhysicalDeviceSparseImageFormatProperties(VkPhysicalDevice, VkFormat, VkImageType, VkSampleCountFlagBits, VkImageUsageFlags, VkImageTiling, uint32_t* c, VkSparseImageFormatProperties*) {
  *c = 0;
}
VKAPI VkResult VKAPI_CALL jsnow_EnumerateDeviceExtensionProperties(VkPhysicalDevice, const char*, uint32_t* c, VkExtensionProperties* p) {
  return fillArray(c, p, kDeviceExts, 1);
}
VKAPI VkResult VKAPI_CALL jsnow_EnumerateDeviceLayerProperties(VkPhysicalDevice, uint32_t* c, VkLayerProperties*) {
  *c = 0;
  return VK_SUCCESS;
}
VKAPI VkResult VKAPI_CALL jsnow_CreateDevice(VkPhysicalDevice, const VkDeviceCreateInfo*, const VkAllocationCallbacks*, VkDevice* out) {
  auto* d = new Device();
  set_loader_magic_value(d);
  d->queue = new Queue();
  set_loader_magic_value(d->queue);
  d->queue->dev = d;
  int threads = int(std::thread::hardware_concurrency());
  if (const char* t = std::getenv("JSNOW_ICD_THREADS")) threads = std::max(1, std::atoi(t));
  d->pool = std::make_unique<jsnow::ThreadPool>(threads);
  *out = from<VkDevice>(d);
  return VK_SUCCESS;
}
VKAPI void VKAPI_CALL jsnow_DestroyDevice(VkDevice d, const VkAllocationCallbacks*) {
  if (!d) return;
  delete to<Device>(d)->queue;
  delete to<Device>(d);
}
VKAPI void VKAPI_CALL jsnow_GetDeviceQueue(VkDevice d, uint32_t, uint32_t, VkQueue* q) { *q = from<VkQueue>(to<Device>(d)->queue); }
VKAPI VkResult VKAPI_CALL jsnow_DeviceWaitIdle(VkDevice) { return VK_SUCCESS; }
VKAPI VkResult VKAPI_CALL jsnow_QueueWaitIdle(VkQueue) { return VK_SUCCESS; }

// --- memory, buffers, images ---
VKAPI VkResult VKAPI_CALL jsnow_AllocateMemory(VkDevice, const VkMemoryAllocateInfo* ci, const VkAllocationCallbacks*, VkDeviceMemory* out) {
  auto* m = new Memory();
  m->size = ci->allocationSize;
  m->data = static_cast<uint8_t*>(std::aligned_alloc(64, (ci->allocationSize + 63) & ~VkDeviceSize(63)));
  if (!m->data) { delete m; return VK_ERROR_OUT_OF_DEVICE_MEMORY; }
  std::memset(m->data, 0, ci->allocationSize);
  *out = from<VkDeviceMemory>(m);
  return VK_SUCCESS;
}
VKAPI void VKAPI_CALL jsnow_FreeMemory(VkDevice, VkDeviceMemory m, const VkAllocationCallbacks*) {
  if (!m) return;
  std::free(to<Memory>(m)->data);
  delete to<Memory>(m);
}
VKAPI VkResult VKAPI_CALL jsnow_MapMemory(VkDevice, VkDeviceMemory m, VkDeviceSize off, VkDeviceSize, VkMemoryMapFlags, void** p) {
  *p = to<Memory>(m)->data + off;
  return VK_SUCCESS;
}
VKAPI void VKAPI_CALL jsnow_UnmapMemory(VkDevice, VkDeviceMemory) {}
VKAPI VkResult VKAPI_CALL jsnow_FlushMappedMemoryRanges(VkDevice, uint32_t, const VkMappedMemoryRange*) { return VK_SUCCESS; }
VKAPI VkResult VKAPI_CALL jsnow_InvalidateMappedMemoryRanges(VkDevice, uint32_t, const VkMappedMemoryRange*) { return VK_SUCCESS; }
VKAPI VkResult VKAPI_CALL jsnow_CreateBuffer(VkDevice, const VkBufferCreateInfo* ci, const VkAllocationCallbacks*, VkBuffer* out) {
  auto* b = new Buffer();
  b->size = ci->size;
  *out = from<VkBuffer>(b);
  return VK_SUCCESS;
}
VKAPI void VKAPI_CALL jsnow_DestroyBuffer(VkDevice, VkBuffer b, const VkAllocationCallbacks*) { delete to<Buffer>(b); }
VKAPI void VKAPI_CALL jsnow_GetBufferMemoryRequirements(VkDevice, VkBuffer b, VkMemoryRequirements* r) {
  r->size = (to<Buffer>(b)->size + 15) & ~VkDeviceSize(15);
  r->alignment = 64;
  r->memoryTypeBits = 1;
}
VKAPI VkResult VKAPI_CALL jsnow_BindBufferMemory(VkDevice, VkBuffer b, VkDeviceMemory m, VkDeviceSize off) {
  to<Buffer>(b)->mem = to<Memory>(m);
  to<Buffer>(b)->offset = off;
  return VK_SUCCESS;
}
VKAPI VkResult VKAPI_CALL jsnow_CreateImage(VkDevice, const VkImageCreateInfo* ci, const VkAllocationCallbacks*, VkImage* out) {
  auto* im = new Image();
  im->format = ci->format;
  im->w = ci->extent.width; im->h = ci->extent.height;
  im->levels = ci->mipLevels; im->layers = ci->arrayLayers;
  if (ci->extent.depth > 1) missing("3D images");
  if (ci->samples != VK_SAMPLE_COUNT_1_BIT) missing("multisampled images");
  if (formatSize(ci->format) == 0) missing("image format " + std::to_string(int(ci->format)));
  im->init();
  *out = from<VkImage>(im);
  return VK_SUCCESS;
}
VKAPI void VKAPI_CALL jsnow_DestroyImage(VkDevice, VkImage i, const VkAllocationCallbacks*) { delete to<Image>(i); }
VKAPI void VKAPI_CALL jsnow_GetImageMemoryRequirements(VkDevice, VkImage i, VkMemoryRequirements* r) {
  r->size = std::max<VkDeviceSize>(to<Image>(i)->size, 16);
  r->alignment = 64;
  r->memoryTypeBits = 1;
}
VKAPI VkResult VKAPI_CALL jsnow_BindImageMemory(VkDevice, VkImage i, VkDeviceMemory m, VkDeviceSize off) {
  to<Image>(i)->mem = to<Memory>(m);
  to<Image>(i)->offset = off;
  return VK_SUCCESS;
}
VKAPI void VKAPI_CALL jsnow_GetImageSubresourceLayout(VkDevice, VkImage i, const VkImageSubresource* s, VkSubresourceLayout* l) {
  Image* im = to<Image>(i);
  l->offset = s->arrayLayer * im->layerSize + im->levelOffset[s->mipLevel];
  l->rowPitch = im->pitch(s->mipLevel);
  l->size = VkDeviceSize(l->rowPitch) * std::max(1u, im->h >> s->mipLevel);
  l->arrayPitch = im->layerSize;
  l->depthPitch = l->size;
}
VKAPI void VKAPI_CALL jsnow_GetImageSparseMemoryRequirements(VkDevice, VkImage, uint32_t* c, VkSparseImageMemoryRequirements*) { *c = 0; }
VKAPI VkResult VKAPI_CALL jsnow_CreateImageView(VkDevice, const VkImageViewCreateInfo* ci, const VkAllocationCallbacks*, VkImageView* out) {
  Image* im = to<Image>(ci->image);
  const uint32_t lv = ci->subresourceRange.levelCount == VK_REMAINING_MIP_LEVELS ? im->levels - ci->subresourceRange.baseMipLevel
                                                                                : ci->subresourceRange.levelCount;
  *out = from<VkImageView>(new ImageView{im, ci->format, ci->subresourceRange.baseMipLevel, lv,
                                          ci->subresourceRange.baseArrayLayer});
  return VK_SUCCESS;
}
VKAPI void VKAPI_CALL jsnow_DestroyImageView(VkDevice, VkImageView v, const VkAllocationCallbacks*) { delete to<ImageView>(v); }
VKAPI VkResult VKAPI_CALL jsnow_CreateSampler(VkDevice, const VkSamplerCreateInfo* ci, const VkAllocationCallbacks*, VkSampler* out) {
  *out = from<VkSampler>(new Sampler{*ci});
  return VK_SUCCESS;
}
VKAPI void VKAPI_CALL jsnow_DestroySampler(VkDevice, VkSampler s, const VkAllocationCallbacks*) { delete to<Sampler>(s); }

// --- shaders, descriptors, pipelines ---
VKAPI VkResult VKAPI_CALL jsnow_CreateShaderModule(VkDevice, const VkShaderModuleCreateInfo* ci, const VkAllocationCallbacks*, VkShaderModule* out) {
  std::string err;
  auto mod = spv::Module::parse(ci->pCode, ci->codeSize / 4, err);
  if (!mod) { missing("shader parse: " + err); return VK_ERROR_INVALID_SHADER_NV; }
  *out = from<VkShaderModule>(new ShaderModule{mod});
  return VK_SUCCESS;
}
VKAPI void VKAPI_CALL jsnow_DestroyShaderModule(VkDevice, VkShaderModule m, const VkAllocationCallbacks*) { delete to<ShaderModule>(m); }
VKAPI VkResult VKAPI_CALL jsnow_CreatePipelineCache(VkDevice, const VkPipelineCacheCreateInfo*, const VkAllocationCallbacks*, VkPipelineCache* out) {
  *out = from<VkPipelineCache>(new int(0));
  return VK_SUCCESS;
}
VKAPI void VKAPI_CALL jsnow_DestroyPipelineCache(VkDevice, VkPipelineCache c, const VkAllocationCallbacks*) { delete to<int>(c); }
VKAPI VkResult VKAPI_CALL jsnow_GetPipelineCacheData(VkDevice, VkPipelineCache, size_t* s, void*) { *s = 0; return VK_SUCCESS; }
VKAPI VkResult VKAPI_CALL jsnow_CreateDescriptorSetLayout(VkDevice, const VkDescriptorSetLayoutCreateInfo* ci, const VkAllocationCallbacks*, VkDescriptorSetLayout* out) {
  auto* l = new DescriptorSetLayout();
  l->bindings.assign(ci->pBindings, ci->pBindings + ci->bindingCount);
  *out = from<VkDescriptorSetLayout>(l);
  return VK_SUCCESS;
}
VKAPI void VKAPI_CALL jsnow_DestroyDescriptorSetLayout(VkDevice, VkDescriptorSetLayout l, const VkAllocationCallbacks*) { delete to<DescriptorSetLayout>(l); }
VKAPI VkResult VKAPI_CALL jsnow_CreatePipelineLayout(VkDevice, const VkPipelineLayoutCreateInfo* ci, const VkAllocationCallbacks*, VkPipelineLayout* out) {
  auto* l = new PipelineLayout();
  for (uint32_t i = 0; i < ci->setLayoutCount; ++i) l->sets.push_back(to<DescriptorSetLayout>(ci->pSetLayouts[i]));
  *out = from<VkPipelineLayout>(l);
  return VK_SUCCESS;
}
VKAPI void VKAPI_CALL jsnow_DestroyPipelineLayout(VkDevice, VkPipelineLayout l, const VkAllocationCallbacks*) { delete to<PipelineLayout>(l); }
VKAPI VkResult VKAPI_CALL jsnow_CreateDescriptorPool(VkDevice, const VkDescriptorPoolCreateInfo*, const VkAllocationCallbacks*, VkDescriptorPool* out) {
  *out = from<VkDescriptorPool>(new DescriptorPool());
  return VK_SUCCESS;
}
VKAPI void VKAPI_CALL jsnow_DestroyDescriptorPool(VkDevice, VkDescriptorPool p, const VkAllocationCallbacks*) {
  if (!p) return;
  for (auto* s : to<DescriptorPool>(p)->sets) delete s;
  delete to<DescriptorPool>(p);
}
VKAPI VkResult VKAPI_CALL jsnow_ResetDescriptorPool(VkDevice, VkDescriptorPool p, VkDescriptorPoolResetFlags) {
  for (auto* s : to<DescriptorPool>(p)->sets) delete s;
  to<DescriptorPool>(p)->sets.clear();
  return VK_SUCCESS;
}
VKAPI VkResult VKAPI_CALL jsnow_AllocateDescriptorSets(VkDevice, const VkDescriptorSetAllocateInfo* ai, VkDescriptorSet* out) {
  for (uint32_t i = 0; i < ai->descriptorSetCount; ++i) {
    auto* s = new DescriptorSet();
    uint32_t maxB = 0;
    for (auto& b : to<DescriptorSetLayout>(ai->pSetLayouts[i])->bindings) maxB = std::max(maxB, b.binding + 1);
    s->b.resize(maxB);
    for (auto& b : to<DescriptorSetLayout>(ai->pSetLayouts[i])->bindings) s->b[b.binding].type = b.descriptorType;
    to<DescriptorPool>(ai->descriptorPool)->sets.push_back(s);
    out[i] = from<VkDescriptorSet>(s);
  }
  return VK_SUCCESS;
}
VKAPI VkResult VKAPI_CALL jsnow_FreeDescriptorSets(VkDevice, VkDescriptorPool p, uint32_t n, const VkDescriptorSet* s) {
  auto& v = to<DescriptorPool>(p)->sets;
  for (uint32_t i = 0; i < n; ++i) {
    auto it = std::find(v.begin(), v.end(), to<DescriptorSet>(s[i]));
    if (it != v.end()) { delete *it; v.erase(it); }
  }
  return VK_SUCCESS;
}
VKAPI void VKAPI_CALL jsnow_UpdateDescriptorSets(VkDevice, uint32_t nw, const VkWriteDescriptorSet* w, uint32_t nc, const VkCopyDescriptorSet* c) {
  for (uint32_t i = 0; i < nw; ++i) {
    DescriptorSet* s = to<DescriptorSet>(w[i].dstSet);
    for (uint32_t k = 0; k < w[i].descriptorCount; ++k) {
      const uint32_t b = w[i].dstBinding + w[i].dstArrayElement + k;
      if (b >= s->b.size()) s->b.resize(b + 1);
      Descriptor& d = s->b[b];
      d.type = w[i].descriptorType;
      switch (d.type) {
        case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER: case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:
        case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC: case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC:
          d.buf = to<Buffer>(w[i].pBufferInfo[k].buffer);
          d.offset = w[i].pBufferInfo[k].offset;
          d.range = w[i].pBufferInfo[k].range;
          break;
        case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER: case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
        case VK_DESCRIPTOR_TYPE_SAMPLER:
          if (w[i].pImageInfo[k].imageView) d.view = to<ImageView>(w[i].pImageInfo[k].imageView);
          if (w[i].pImageInfo[k].sampler) d.sampler = to<Sampler>(w[i].pImageInfo[k].sampler);
          if (d.type != VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER) missing("separate images/samplers (bound per binding only)");
          prepareTexture(d);
          break;
        default: missing("descriptor type " + std::to_string(int(d.type))); break;
      }
    }
  }
  for (uint32_t i = 0; i < nc; ++i) {
    DescriptorSet* src = to<DescriptorSet>(c[i].srcSet);
    DescriptorSet* dst = to<DescriptorSet>(c[i].dstSet);
    for (uint32_t k = 0; k < c[i].descriptorCount; ++k) {
      const uint32_t db = c[i].dstBinding + k;
      if (db >= dst->b.size()) dst->b.resize(db + 1);
      dst->b[db] = src->b[c[i].srcBinding + k];
    }
  }
}
VKAPI VkResult VKAPI_CALL jsnow_CreateRenderPass(VkDevice, const VkRenderPassCreateInfo* ci, const VkAllocationCallbacks*, VkRenderPass* out) {
  auto* rp = new RenderPass();
  rp->att.assign(ci->pAttachments, ci->pAttachments + ci->attachmentCount);
  if (ci->subpassCount > 1) missing("multiple subpasses");
  const VkSubpassDescription& s = ci->pSubpasses[0];
  for (uint32_t i = 0; i < s.colorAttachmentCount; ++i) rp->color.push_back(s.pColorAttachments[i].attachment);
  if (s.colorAttachmentCount > 1) missing("multiple colour attachments (only #0 is written)");
  if (s.pDepthStencilAttachment && s.pDepthStencilAttachment->attachment != VK_ATTACHMENT_UNUSED)
    rp->depth = int(s.pDepthStencilAttachment->attachment);
  *out = from<VkRenderPass>(rp);
  return VK_SUCCESS;
}
VKAPI void VKAPI_CALL jsnow_DestroyRenderPass(VkDevice, VkRenderPass r, const VkAllocationCallbacks*) { delete to<RenderPass>(r); }
VKAPI VkResult VKAPI_CALL jsnow_CreateFramebuffer(VkDevice, const VkFramebufferCreateInfo* ci, const VkAllocationCallbacks*, VkFramebuffer* out) {
  auto* f = new Framebuffer();
  for (uint32_t i = 0; i < ci->attachmentCount; ++i) f->views.push_back(to<ImageView>(ci->pAttachments[i]));
  f->w = ci->width; f->h = ci->height;
  *out = from<VkFramebuffer>(f);
  return VK_SUCCESS;
}
VKAPI void VKAPI_CALL jsnow_DestroyFramebuffer(VkDevice, VkFramebuffer f, const VkAllocationCallbacks*) { delete to<Framebuffer>(f); }
VKAPI VkResult VKAPI_CALL jsnow_CreateGraphicsPipelines(VkDevice, VkPipelineCache, uint32_t n, const VkGraphicsPipelineCreateInfo* ci, const VkAllocationCallbacks*, VkPipeline* out) {
  for (uint32_t i = 0; i < n; ++i) {
    auto* p = new Pipeline();
    const VkGraphicsPipelineCreateInfo& c = ci[i];
    for (uint32_t s = 0; s < c.stageCount; ++s) {
      auto mod = to<ShaderModule>(c.pStages[s].module)->mod;
      if (c.pStages[s].stage == VK_SHADER_STAGE_VERTEX_BIT) p->vs = mod;
      else if (c.pStages[s].stage == VK_SHADER_STAGE_FRAGMENT_BIT) p->fs = mod;
      else missing("shader stage " + std::to_string(int(c.pStages[s].stage)));
      if (c.pStages[s].pSpecializationInfo) missing("specialization constants (defaults used)");
    }
    if (c.pVertexInputState) {
      const auto* v = c.pVertexInputState;
      p->bindings.assign(v->pVertexBindingDescriptions, v->pVertexBindingDescriptions + v->vertexBindingDescriptionCount);
      p->attrs.assign(v->pVertexAttributeDescriptions, v->pVertexAttributeDescriptions + v->vertexAttributeDescriptionCount);
    }
    if (c.pInputAssemblyState) p->topology = c.pInputAssemblyState->topology;
    if (c.pRasterizationState) {
      p->cull = c.pRasterizationState->cullMode;
      p->front = c.pRasterizationState->frontFace;
      if (c.pRasterizationState->polygonMode != VK_POLYGON_MODE_FILL) missing("non-fill polygon mode");
      if (c.pRasterizationState->depthBiasEnable) missing("depth bias");
    }
    if (c.pDepthStencilState) {
      p->depthTest = c.pDepthStencilState->depthTestEnable;
      p->depthWrite = c.pDepthStencilState->depthWriteEnable;
      p->depthOp = c.pDepthStencilState->depthCompareOp;
      if (c.pDepthStencilState->stencilTestEnable) missing("stencil test");
    }
    if (c.pColorBlendState && c.pColorBlendState->attachmentCount) {
      p->blend = c.pColorBlendState->pAttachments[0];
      p->hasBlend = true;
      if (p->blend.blendEnable && (p->blend.colorBlendOp != VK_BLEND_OP_ADD || p->blend.alphaBlendOp != VK_BLEND_OP_ADD))
        missing("blend ops other than ADD");
    }
    if (c.pViewportState) {
      if (c.pViewportState->pViewports) p->viewport = c.pViewportState->pViewports[0];
      if (c.pViewportState->pScissors) p->scissor = c.pViewportState->pScissors[0];
    }
    if (c.pDynamicState)
      for (uint32_t k = 0; k < c.pDynamicState->dynamicStateCount; ++k) {
        const VkDynamicState d = c.pDynamicState->pDynamicStates[k];
        if (d == VK_DYNAMIC_STATE_VIEWPORT) p->dynViewport = true;
        else if (d == VK_DYNAMIC_STATE_SCISSOR) p->dynScissor = true;
        else missing("dynamic state " + std::to_string(int(d)));
      }
    if (c.pMultisampleState && c.pMultisampleState->rasterizationSamples != VK_SAMPLE_COUNT_1_BIT) missing("MSAA");
    out[i] = from<VkPipeline>(p);
  }
  return VK_SUCCESS;
}
VKAPI VkResult VKAPI_CALL jsnow_CreateComputePipelines(VkDevice, VkPipelineCache, uint32_t n, const VkComputePipelineCreateInfo*, const VkAllocationCallbacks*, VkPipeline* out) {
  missing("compute pipelines");
  for (uint32_t i = 0; i < n; ++i) out[i] = VK_NULL_HANDLE;
  return VK_ERROR_FEATURE_NOT_PRESENT;
}
VKAPI void VKAPI_CALL jsnow_DestroyPipeline(VkDevice, VkPipeline p, const VkAllocationCallbacks*) { delete to<Pipeline>(p); }

// --- sync ---
VKAPI VkResult VKAPI_CALL jsnow_CreateFence(VkDevice, const VkFenceCreateInfo* ci, const VkAllocationCallbacks*, VkFence* out) {
  *out = from<VkFence>(new Fence{(ci->flags & VK_FENCE_CREATE_SIGNALED_BIT) != 0});
  return VK_SUCCESS;
}
VKAPI void VKAPI_CALL jsnow_DestroyFence(VkDevice, VkFence f, const VkAllocationCallbacks*) { delete to<Fence>(f); }
VKAPI VkResult VKAPI_CALL jsnow_ResetFences(VkDevice, uint32_t n, const VkFence* f) {
  for (uint32_t i = 0; i < n; ++i) to<Fence>(f[i])->signaled = false;
  return VK_SUCCESS;
}
VKAPI VkResult VKAPI_CALL jsnow_GetFenceStatus(VkDevice, VkFence f) { return to<Fence>(f)->signaled ? VK_SUCCESS : VK_NOT_READY; }
VKAPI VkResult VKAPI_CALL jsnow_WaitForFences(VkDevice, uint32_t, const VkFence*, VkBool32, uint64_t) { return VK_SUCCESS; }
VKAPI VkResult VKAPI_CALL jsnow_CreateSemaphore(VkDevice, const VkSemaphoreCreateInfo*, const VkAllocationCallbacks*, VkSemaphore* out) {
  *out = from<VkSemaphore>(new Semaphore{});
  return VK_SUCCESS;
}
VKAPI void VKAPI_CALL jsnow_DestroySemaphore(VkDevice, VkSemaphore s, const VkAllocationCallbacks*) { delete to<Semaphore>(s); }

// --- command buffers ---
VKAPI VkResult VKAPI_CALL jsnow_CreateCommandPool(VkDevice, const VkCommandPoolCreateInfo*, const VkAllocationCallbacks*, VkCommandPool* out) {
  *out = from<VkCommandPool>(new CommandPool{});
  return VK_SUCCESS;
}
VKAPI void VKAPI_CALL jsnow_DestroyCommandPool(VkDevice, VkCommandPool p, const VkAllocationCallbacks*) { delete to<CommandPool>(p); }
VKAPI VkResult VKAPI_CALL jsnow_ResetCommandPool(VkDevice, VkCommandPool, VkCommandPoolResetFlags) { return VK_SUCCESS; }
VKAPI VkResult VKAPI_CALL jsnow_AllocateCommandBuffers(VkDevice, const VkCommandBufferAllocateInfo* ai, VkCommandBuffer* out) {
  for (uint32_t i = 0; i < ai->commandBufferCount; ++i) {
    auto* cb = new CommandBuffer();
    set_loader_magic_value(cb);
    out[i] = from<VkCommandBuffer>(cb);
  }
  return VK_SUCCESS;
}
VKAPI void VKAPI_CALL jsnow_FreeCommandBuffers(VkDevice, VkCommandPool, uint32_t n, const VkCommandBuffer* c) {
  for (uint32_t i = 0; i < n; ++i) delete to<CommandBuffer>(c[i]);
}
VKAPI VkResult VKAPI_CALL jsnow_BeginCommandBuffer(VkCommandBuffer c, const VkCommandBufferBeginInfo*) {
  to<CommandBuffer>(c)->cmds.clear();
  return VK_SUCCESS;
}
VKAPI VkResult VKAPI_CALL jsnow_EndCommandBuffer(VkCommandBuffer) { return VK_SUCCESS; }
VKAPI VkResult VKAPI_CALL jsnow_ResetCommandBuffer(VkCommandBuffer c, VkCommandBufferResetFlags) {
  to<CommandBuffer>(c)->cmds.clear();
  return VK_SUCCESS;
}
#define REC(cb) to<CommandBuffer>(cb)->cmds.push_back
VKAPI void VKAPI_CALL jsnow_CmdBeginRenderPass(VkCommandBuffer c, const VkRenderPassBeginInfo* bi, VkSubpassContents) {
  RenderPass* rp = to<RenderPass>(bi->renderPass);
  Framebuffer* fb = to<Framebuffer>(bi->framebuffer);
  VkRect2D area = bi->renderArea;
  std::vector<VkClearValue> clears(bi->pClearValues, bi->pClearValues + bi->clearValueCount);
  REC(c)([=](Exec& ex) {
    ex.rp = rp; ex.fb = fb; ex.area = area;
    for (size_t i = 0; i < rp->att.size() && i < fb->views.size(); ++i) {
      const bool depth = isDepth(rp->att[i].format);
      if (rp->att[i].loadOp == VK_ATTACHMENT_LOAD_OP_CLEAR && i < clears.size()) clearAttachment(fb->views[i], clears[i], area);
      (void)depth;
    }
  });
}
VKAPI void VKAPI_CALL jsnow_CmdEndRenderPass(VkCommandBuffer c) { REC(c)([](Exec& ex) { ex.rp = nullptr; ex.fb = nullptr; }); }
VKAPI void VKAPI_CALL jsnow_CmdNextSubpass(VkCommandBuffer, VkSubpassContents) { missing("vkCmdNextSubpass"); }
VKAPI void VKAPI_CALL jsnow_CmdBindPipeline(VkCommandBuffer c, VkPipelineBindPoint bp, VkPipeline p) {
  Pipeline* pp = to<Pipeline>(p);
  if (bp != VK_PIPELINE_BIND_POINT_GRAPHICS) { missing("compute bind point"); return; }
  REC(c)([=](Exec& ex) { ex.pipe = pp; });
}
VKAPI void VKAPI_CALL jsnow_CmdBindDescriptorSets(VkCommandBuffer c, VkPipelineBindPoint, VkPipelineLayout, uint32_t first, uint32_t n, const VkDescriptorSet* s, uint32_t nd, const uint32_t* d) {
  std::vector<DescriptorSet*> sets;
  for (uint32_t i = 0; i < n; ++i) sets.push_back(to<DescriptorSet>(s[i]));
  std::vector<uint32_t> dyn(d, d + nd);
  REC(c)([=](Exec& ex) {
    size_t k = 0;
    for (uint32_t i = 0; i < n; ++i) {
      ex.sets[first + i] = sets[i];
      ex.dynOffsets[first + i].clear();
      for (auto& b : sets[i]->b)
        if ((b.type == VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC || b.type == VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC) && k < dyn.size())
          ex.dynOffsets[first + i].push_back(dyn[k++]);
    }
  });
}
VKAPI void VKAPI_CALL jsnow_CmdBindVertexBuffers(VkCommandBuffer c, uint32_t first, uint32_t n, const VkBuffer* b, const VkDeviceSize* o) {
  std::vector<std::pair<Buffer*, VkDeviceSize>> v;
  for (uint32_t i = 0; i < n; ++i) v.push_back({to<Buffer>(b[i]), o[i]});
  REC(c)([=](Exec& ex) { for (uint32_t i = 0; i < n; ++i) ex.vbs[first + i] = {v[i].first, v[i].second}; });
}
VKAPI void VKAPI_CALL jsnow_CmdBindIndexBuffer(VkCommandBuffer c, VkBuffer b, VkDeviceSize o, VkIndexType t) {
  Buffer* bb = to<Buffer>(b);
  REC(c)([=](Exec& ex) { ex.ib = bb; ex.ibOff = o; ex.ibType = t; });
}
VKAPI void VKAPI_CALL jsnow_CmdSetViewport(VkCommandBuffer c, uint32_t, uint32_t, const VkViewport* v) {
  VkViewport vp = v[0];
  REC(c)([=](Exec& ex) { ex.vp = vp; });
}
VKAPI void VKAPI_CALL jsnow_CmdSetScissor(VkCommandBuffer c, uint32_t, uint32_t, const VkRect2D* r) {
  VkRect2D s = r[0];
  REC(c)([=](Exec& ex) { ex.scissor = s; });
}
VKAPI void VKAPI_CALL jsnow_CmdPushConstants(VkCommandBuffer c, VkPipelineLayout, VkShaderStageFlags, uint32_t off, uint32_t size, const void* v) {
  std::vector<uint8_t> data(static_cast<const uint8_t*>(v), static_cast<const uint8_t*>(v) + size);
  REC(c)([=](Exec& ex) { std::memcpy(ex.push + off, data.data(), std::min<size_t>(size, 256 - off)); });
}
VKAPI void VKAPI_CALL jsnow_CmdDraw(VkCommandBuffer c, uint32_t n, uint32_t inst, uint32_t first, uint32_t firstInst) {
  REC(c)([=](Exec& ex) { cmdDraw(ex, n, inst, first, firstInst, false, 0); });
}
VKAPI void VKAPI_CALL jsnow_CmdDrawIndexed(VkCommandBuffer c, uint32_t n, uint32_t inst, uint32_t first, int32_t vo, uint32_t firstInst) {
  REC(c)([=](Exec& ex) { cmdDraw(ex, n, inst, first, firstInst, true, vo); });
}
VKAPI void VKAPI_CALL jsnow_CmdPipelineBarrier(VkCommandBuffer, VkPipelineStageFlags, VkPipelineStageFlags, VkDependencyFlags, uint32_t, const VkMemoryBarrier*, uint32_t, const VkBufferMemoryBarrier*, uint32_t, const VkImageMemoryBarrier*) {}
VKAPI void VKAPI_CALL jsnow_CmdCopyBuffer(VkCommandBuffer c, VkBuffer s, VkBuffer d, uint32_t n, const VkBufferCopy* r) {
  Buffer* sb = to<Buffer>(s); Buffer* db = to<Buffer>(d);
  std::vector<VkBufferCopy> rs(r, r + n);
  REC(c)([=](Exec&) { for (auto& x : rs) std::memmove(db->ptr() + x.dstOffset, sb->ptr() + x.srcOffset, x.size); });
}
VKAPI void VKAPI_CALL jsnow_CmdCopyBufferToImage(VkCommandBuffer c, VkBuffer s, VkImage d, VkImageLayout, uint32_t n, const VkBufferImageCopy* r) {
  Buffer* sb = to<Buffer>(s); Image* im = to<Image>(d);
  std::vector<VkBufferImageCopy> rs(r, r + n);
  REC(c)([=](Exec&) {
    for (auto& x : rs) {
      const uint32_t rowLen = x.bufferRowLength ? x.bufferRowLength : x.imageExtent.width;
      const uint32_t imgH = x.bufferImageHeight ? x.bufferImageHeight : x.imageExtent.height;
      for (uint32_t layer = 0; layer < x.imageSubresource.layerCount; ++layer)
        for (uint32_t y = 0; y < x.imageExtent.height; ++y)
          std::memcpy(im->at(x.imageSubresource.mipLevel, x.imageSubresource.baseArrayLayer + layer, x.imageOffset.x, x.imageOffset.y + y),
                      sb->ptr() + x.bufferOffset + (size_t(layer) * imgH + y) * rowLen * im->bpp,
                      size_t(x.imageExtent.width) * im->bpp);
    }
  });
}
VKAPI void VKAPI_CALL jsnow_CmdCopyImageToBuffer(VkCommandBuffer c, VkImage s, VkImageLayout, VkBuffer d, uint32_t n, const VkBufferImageCopy* r) {
  Image* im = to<Image>(s); Buffer* db = to<Buffer>(d);
  std::vector<VkBufferImageCopy> rs(r, r + n);
  REC(c)([=](Exec&) {
    for (auto& x : rs) {
      const uint32_t rowLen = x.bufferRowLength ? x.bufferRowLength : x.imageExtent.width;
      for (uint32_t y = 0; y < x.imageExtent.height; ++y)
        std::memcpy(db->ptr() + x.bufferOffset + size_t(y) * rowLen * im->bpp,
                    im->at(x.imageSubresource.mipLevel, x.imageSubresource.baseArrayLayer, x.imageOffset.x, x.imageOffset.y + y),
                    size_t(x.imageExtent.width) * im->bpp);
    }
  });
}
VKAPI void VKAPI_CALL jsnow_CmdCopyImage(VkCommandBuffer c, VkImage s, VkImageLayout, VkImage d, VkImageLayout, uint32_t n, const VkImageCopy* r) {
  Image* si = to<Image>(s); Image* di = to<Image>(d);
  std::vector<VkImageCopy> rs(r, r + n);
  REC(c)([=](Exec&) {
    for (auto& x : rs)
      for (uint32_t y = 0; y < x.extent.height; ++y)
        std::memcpy(di->at(x.dstSubresource.mipLevel, x.dstSubresource.baseArrayLayer, x.dstOffset.x, x.dstOffset.y + y),
                    si->at(x.srcSubresource.mipLevel, x.srcSubresource.baseArrayLayer, x.srcOffset.x, x.srcOffset.y + y),
                    size_t(x.extent.width) * si->bpp);
  });
}
VKAPI void VKAPI_CALL jsnow_CmdBlitImage(VkCommandBuffer c, VkImage s, VkImageLayout, VkImage d, VkImageLayout, uint32_t n, const VkImageBlit* r, VkFilter) {
  Image* si = to<Image>(s); Image* di = to<Image>(d);
  std::vector<VkImageBlit> rs(r, r + n);
  REC(c)([=](Exec&) {
    for (auto& x : rs) {
      const int dx0 = x.dstOffsets[0].x, dy0 = x.dstOffsets[0].y, dx1 = x.dstOffsets[1].x, dy1 = x.dstOffsets[1].y;
      const int sx0 = x.srcOffsets[0].x, sy0 = x.srcOffsets[0].y, sx1 = x.srcOffsets[1].x, sy1 = x.srcOffsets[1].y;
      for (int y = std::min(dy0, dy1); y < std::max(dy0, dy1); ++y)
        for (int X = std::min(dx0, dx1); X < std::max(dx0, dx1); ++X) {  // nearest
          const int sx = sx0 + int((X - dx0 + 0.5f) * float(sx1 - sx0) / float(dx1 - dx0));
          const int sy = sy0 + int((y - dy0 + 0.5f) * float(sy1 - sy0) / float(dy1 - dy0));
          float col[4];
          readColor(si->format, si->at(x.srcSubresource.mipLevel, x.srcSubresource.baseArrayLayer,
                                       std::clamp<uint32_t>(sx, 0, si->w - 1), std::clamp<uint32_t>(sy, 0, si->h - 1)), col);
          writeColor(di->format, di->at(x.dstSubresource.mipLevel, x.dstSubresource.baseArrayLayer, X, y), col);
        }
    }
  });
}
VKAPI void VKAPI_CALL jsnow_CmdClearColorImage(VkCommandBuffer c, VkImage i, VkImageLayout, const VkClearColorValue* v, uint32_t, const VkImageSubresourceRange* r) {
  Image* im = to<Image>(i);
  VkClearValue cv{};
  cv.color = *v;
  const uint32_t lvl = r->baseMipLevel;
  REC(c)([=](Exec&) {
    ImageView view{im, im->format, lvl, 1, 0};
    clearAttachment(&view, cv, VkRect2D{{0, 0}, {std::max(1u, im->w >> lvl), std::max(1u, im->h >> lvl)}});
  });
}
VKAPI void VKAPI_CALL jsnow_CmdClearDepthStencilImage(VkCommandBuffer c, VkImage i, VkImageLayout, const VkClearDepthStencilValue* v, uint32_t, const VkImageSubresourceRange*) {
  Image* im = to<Image>(i);
  VkClearValue cv{};
  cv.depthStencil = *v;
  REC(c)([=](Exec&) {
    ImageView view{im, im->format, 0, 1, 0};
    clearAttachment(&view, cv, VkRect2D{{0, 0}, {im->w, im->h}});
  });
}
VKAPI void VKAPI_CALL jsnow_CmdClearAttachments(VkCommandBuffer c, uint32_t na, const VkClearAttachment* a, uint32_t nr, const VkClearRect* r) {
  std::vector<VkClearAttachment> as(a, a + na);
  std::vector<VkClearRect> rs(r, r + nr);
  REC(c)([=](Exec& ex) {
    if (!ex.rp || !ex.fb) return;
    for (auto& at : as) {
      ImageView* v = nullptr;
      if (at.aspectMask & VK_IMAGE_ASPECT_COLOR_BIT) v = ex.fb->views[ex.rp->color[at.colorAttachment]];
      else if (ex.rp->depth >= 0) v = ex.fb->views[ex.rp->depth];
      if (v) for (auto& rr : rs) clearAttachment(v, at.clearValue, rr.rect);
    }
  });
}
VKAPI void VKAPI_CALL jsnow_CmdUpdateBuffer(VkCommandBuffer c, VkBuffer b, VkDeviceSize off, VkDeviceSize size, const void* d) {
  Buffer* bb = to<Buffer>(b);
  std::vector<uint8_t> data(static_cast<const uint8_t*>(d), static_cast<const uint8_t*>(d) + size);
  REC(c)([=](Exec&) { std::memcpy(bb->ptr() + off, data.data(), data.size()); });
}
VKAPI void VKAPI_CALL jsnow_CmdFillBuffer(VkCommandBuffer c, VkBuffer b, VkDeviceSize off, VkDeviceSize size, uint32_t v) {
  Buffer* bb = to<Buffer>(b);
  REC(c)([=](Exec&) {
    const VkDeviceSize n = size == VK_WHOLE_SIZE ? bb->size - off : size;
    for (VkDeviceSize i = 0; i + 4 <= n; i += 4) std::memcpy(bb->ptr() + off + i, &v, 4);
  });
}
VKAPI void VKAPI_CALL jsnow_CmdExecuteCommands(VkCommandBuffer c, uint32_t n, const VkCommandBuffer* s) {
  std::vector<CommandBuffer*> v;
  for (uint32_t i = 0; i < n; ++i) v.push_back(to<CommandBuffer>(s[i]));
  REC(c)([=](Exec& ex) { for (auto* cb : v) for (auto& f : cb->cmds) f(ex); });
}
VKAPI void VKAPI_CALL jsnow_CmdSetLineWidth(VkCommandBuffer, float) {}
VKAPI void VKAPI_CALL jsnow_CmdSetDepthBias(VkCommandBuffer, float, float, float) { missing("vkCmdSetDepthBias"); }
VKAPI void VKAPI_CALL jsnow_CmdSetBlendConstants(VkCommandBuffer, const float[4]) { missing("blend constants"); }
VKAPI void VKAPI_CALL jsnow_CmdDispatch(VkCommandBuffer, uint32_t, uint32_t, uint32_t) { missing("vkCmdDispatch (compute)"); }

VKAPI VkResult VKAPI_CALL jsnow_QueueSubmit(VkQueue q, uint32_t n, const VkSubmitInfo* s, VkFence f) {
  static double totalMs = 0;
  static uint64_t submits = 0;
  auto t0 = std::chrono::steady_clock::now();
  for (uint32_t i = 0; i < n; ++i)
    for (uint32_t k = 0; k < s[i].commandBufferCount; ++k) {
      Exec ex;
      ex.dev = to<Queue>(q)->dev;
      ex.pushConstants = ex.push;
      for (auto& cmd : to<CommandBuffer>(s[i].pCommandBuffers[k])->cmds) cmd(ex);
    }
  if (f) to<Fence>(f)->signaled = true;
  totalMs += std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
  ++submits;
  if (std::getenv("JSNOW_ICD_STATS") && submits % 100 == 0)
    std::fprintf(stderr, "[jsnow-icd] %llu submits, avg %.3f ms GPU work per submit\n", (unsigned long long)submits, totalMs / submits);
  return VK_SUCCESS;
}

// --- WSI (surfaces are created by the loader: interface version 2) ---
VKAPI void VKAPI_CALL jsnow_DestroySurfaceKHR(VkInstance, VkSurfaceKHR, const VkAllocationCallbacks*) {}
VKAPI VkResult VKAPI_CALL jsnow_GetPhysicalDeviceSurfaceSupportKHR(VkPhysicalDevice, uint32_t, VkSurfaceKHR, VkBool32* s) { *s = VK_TRUE; return VK_SUCCESS; }
VKAPI VkResult VKAPI_CALL jsnow_GetPhysicalDeviceSurfaceCapabilitiesKHR(VkPhysicalDevice, VkSurfaceKHR s, VkSurfaceCapabilitiesKHR* c) {
  auto* surf = reinterpret_cast<VkIcdSurfaceXcb*>(s);
  uint32_t w = 500, h = 500;
  if (surf->base.platform == VK_ICD_WSI_PLATFORM_XCB && surf->connection) {
    xcb_get_geometry_reply_t* g = xcb_get_geometry_reply(surf->connection, xcb_get_geometry(surf->connection, surf->window), nullptr);
    if (g) { w = g->width; h = g->height; free(g); }
  }
  std::memset(c, 0, sizeof *c);
  c->minImageCount = 2; c->maxImageCount = 8;
  c->currentExtent = {w, h}; c->minImageExtent = {1, 1}; c->maxImageExtent = {8192, 8192};
  c->maxImageArrayLayers = 1;
  c->supportedTransforms = c->currentTransform = VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR;
  c->supportedCompositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
  c->supportedUsageFlags = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
  return VK_SUCCESS;
}
VKAPI VkResult VKAPI_CALL jsnow_GetPhysicalDeviceSurfaceFormatsKHR(VkPhysicalDevice, VkSurfaceKHR, uint32_t* c, VkSurfaceFormatKHR* f) {
  static const VkSurfaceFormatKHR fm[] = {{VK_FORMAT_B8G8R8A8_UNORM, VK_COLOR_SPACE_SRGB_NONLINEAR_KHR},
                                          {VK_FORMAT_B8G8R8A8_SRGB, VK_COLOR_SPACE_SRGB_NONLINEAR_KHR}};
  return fillArray(c, f, fm, 2);
}
VKAPI VkResult VKAPI_CALL jsnow_GetPhysicalDeviceSurfacePresentModesKHR(VkPhysicalDevice, VkSurfaceKHR, uint32_t* c, VkPresentModeKHR* m) {
  static const VkPresentModeKHR pm[] = {VK_PRESENT_MODE_FIFO_KHR, VK_PRESENT_MODE_IMMEDIATE_KHR, VK_PRESENT_MODE_MAILBOX_KHR};
  return fillArray(c, m, pm, 3);
}
VKAPI VkBool32 VKAPI_CALL jsnow_GetPhysicalDeviceXcbPresentationSupportKHR(VkPhysicalDevice, uint32_t, xcb_connection_t*, xcb_visualid_t) { return VK_TRUE; }
VKAPI VkResult VKAPI_CALL jsnow_CreateSwapchainKHR(VkDevice, const VkSwapchainCreateInfoKHR* ci, const VkAllocationCallbacks*, VkSwapchainKHR* out) {
  auto* sc = new Swapchain();
  sc->surf = reinterpret_cast<VkIcdSurfaceXcb*>(ci->surface);
  for (uint32_t i = 0; i < std::max(2u, ci->minImageCount); ++i) {
    auto* im = new Image();
    im->format = ci->imageFormat;
    im->w = ci->imageExtent.width; im->h = ci->imageExtent.height;
    im->init();
    im->own.reset(new uint8_t[im->size]());
    sc->images.push_back(im);
  }
  *out = from<VkSwapchainKHR>(sc);
  return VK_SUCCESS;
}
VKAPI void VKAPI_CALL jsnow_DestroySwapchainKHR(VkDevice, VkSwapchainKHR s, const VkAllocationCallbacks*) {
  if (!s) return;
  for (auto* im : to<Swapchain>(s)->images) delete im;
  delete to<Swapchain>(s);
}
VKAPI VkResult VKAPI_CALL jsnow_GetSwapchainImagesKHR(VkDevice, VkSwapchainKHR s, uint32_t* c, VkImage* out) {
  auto& v = to<Swapchain>(s)->images;
  std::vector<VkImage> h;
  for (auto* im : v) h.push_back(from<VkImage>(im));
  return fillArray(c, out, h.data(), uint32_t(h.size()));
}
VKAPI VkResult VKAPI_CALL jsnow_AcquireNextImageKHR(VkDevice, VkSwapchainKHR s, uint64_t, VkSemaphore, VkFence f, uint32_t* idx) {
  Swapchain* sc = to<Swapchain>(s);
  *idx = sc->next;
  sc->next = (sc->next + 1) % uint32_t(sc->images.size());
  if (f) to<Fence>(f)->signaled = true;
  return VK_SUCCESS;
}
VKAPI VkResult VKAPI_CALL jsnow_QueuePresentKHR(VkQueue, const VkPresentInfoKHR* pi) {
  for (uint32_t i = 0; i < pi->swapchainCount; ++i) {
    Swapchain* sc = to<Swapchain>(pi->pSwapchains[i]);
    present(sc, sc->images[pi->pImageIndices[i]]);
    if (pi->pResults) pi->pResults[i] = VK_SUCCESS;
  }
  return VK_SUCCESS;
}

// --- Vulkan 1.1 core (and the matching KHR aliases) ---
VKAPI void VKAPI_CALL jsnow_GetPhysicalDeviceFeatures2(VkPhysicalDevice pd, VkPhysicalDeviceFeatures2* f) {
  jsnow_GetPhysicalDeviceFeatures(pd, &f->features);
  for (auto* n = static_cast<VkBaseOutStructure*>(f->pNext); n; n = n->pNext) {
    if (n->sType == VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES) {
      auto* v = reinterpret_cast<VkPhysicalDeviceVulkan11Features*>(n);
      void* next = v->pNext;
      std::memset(v, 0, sizeof *v);
      v->sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES;
      v->pNext = next;
    }
    // Other feature structs are left as zero-initialised by the app (= unsupported).
  }
}
VKAPI void VKAPI_CALL jsnow_GetPhysicalDeviceProperties2(VkPhysicalDevice pd, VkPhysicalDeviceProperties2* p) {
  jsnow_GetPhysicalDeviceProperties(pd, &p->properties);
  for (auto* n = static_cast<VkBaseOutStructure*>(p->pNext); n; n = n->pNext) {
    switch (n->sType) {
      case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SUBGROUP_PROPERTIES: {
        auto* s2 = reinterpret_cast<VkPhysicalDeviceSubgroupProperties*>(n);
        s2->subgroupSize = 1;
        s2->supportedStages = VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT;
        s2->supportedOperations = VK_SUBGROUP_FEATURE_BASIC_BIT;
        s2->quadOperationsInAllStages = VK_FALSE;
        break;
      }
      case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MAINTENANCE_3_PROPERTIES: {
        auto* m3 = reinterpret_cast<VkPhysicalDeviceMaintenance3Properties*>(n);
        m3->maxPerSetDescriptors = 1024;
        m3->maxMemoryAllocationSize = VkDeviceSize(1) << 31;
        break;
      }
      case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ID_PROPERTIES: {
        auto* id = reinterpret_cast<VkPhysicalDeviceIDProperties*>(n);
        std::memset(id->deviceUUID, 0x4A, VK_UUID_SIZE);
        std::memset(id->driverUUID, 0x53, VK_UUID_SIZE);
        id->deviceLUIDValid = VK_FALSE;
        break;
      }
      case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_POINT_CLIPPING_PROPERTIES:
        reinterpret_cast<VkPhysicalDevicePointClippingProperties*>(n)->pointClippingBehavior =
            VK_POINT_CLIPPING_BEHAVIOR_ALL_CLIP_PLANES;
        break;
      case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MULTIVIEW_PROPERTIES: {
        auto* mv = reinterpret_cast<VkPhysicalDeviceMultiviewProperties*>(n);
        mv->maxMultiviewViewCount = 1;
        mv->maxMultiviewInstanceIndex = 0;
        break;
      }
      default: break;
    }
  }
}
VKAPI void VKAPI_CALL jsnow_GetPhysicalDeviceFormatProperties2(VkPhysicalDevice pd, VkFormat f, VkFormatProperties2* p) {
  jsnow_GetPhysicalDeviceFormatProperties(pd, f, &p->formatProperties);
}
VKAPI VkResult VKAPI_CALL jsnow_GetPhysicalDeviceImageFormatProperties2(VkPhysicalDevice pd, const VkPhysicalDeviceImageFormatInfo2* i, VkImageFormatProperties2* p) {
  return jsnow_GetPhysicalDeviceImageFormatProperties(pd, i->format, i->type, i->tiling, i->usage, i->flags, &p->imageFormatProperties);
}
VKAPI void VKAPI_CALL jsnow_GetPhysicalDeviceQueueFamilyProperties2(VkPhysicalDevice pd, uint32_t* c, VkQueueFamilyProperties2* p) {
  if (!p) { *c = 1; return; }
  if (*c >= 1) { uint32_t one = 1; jsnow_GetPhysicalDeviceQueueFamilyProperties(pd, &one, &p[0].queueFamilyProperties); *c = 1; }
}
VKAPI void VKAPI_CALL jsnow_GetPhysicalDeviceMemoryProperties2(VkPhysicalDevice pd, VkPhysicalDeviceMemoryProperties2* p) {
  jsnow_GetPhysicalDeviceMemoryProperties(pd, &p->memoryProperties);
}
VKAPI void VKAPI_CALL jsnow_GetPhysicalDeviceSparseImageFormatProperties2(VkPhysicalDevice, const VkPhysicalDeviceSparseImageFormatInfo2*, uint32_t* c, VkSparseImageFormatProperties2*) { *c = 0; }
static void dedicated(void* pNext) {
  for (auto* n = static_cast<VkBaseOutStructure*>(pNext); n; n = n->pNext)
    if (n->sType == VK_STRUCTURE_TYPE_MEMORY_DEDICATED_REQUIREMENTS) {
      auto* d = reinterpret_cast<VkMemoryDedicatedRequirements*>(n);
      d->prefersDedicatedAllocation = d->requiresDedicatedAllocation = VK_FALSE;
    }
}
VKAPI void VKAPI_CALL jsnow_GetBufferMemoryRequirements2(VkDevice d, const VkBufferMemoryRequirementsInfo2* i, VkMemoryRequirements2* r) {
  jsnow_GetBufferMemoryRequirements(d, i->buffer, &r->memoryRequirements);
  dedicated(r->pNext);
}
VKAPI void VKAPI_CALL jsnow_GetImageMemoryRequirements2(VkDevice d, const VkImageMemoryRequirementsInfo2* i, VkMemoryRequirements2* r) {
  jsnow_GetImageMemoryRequirements(d, i->image, &r->memoryRequirements);
  dedicated(r->pNext);
}
VKAPI void VKAPI_CALL jsnow_GetImageSparseMemoryRequirements2(VkDevice, const VkImageSparseMemoryRequirementsInfo2*, uint32_t* c, VkSparseImageMemoryRequirements2*) { *c = 0; }
VKAPI VkResult VKAPI_CALL jsnow_BindBufferMemory2(VkDevice d, uint32_t n, const VkBindBufferMemoryInfo* b) {
  for (uint32_t i = 0; i < n; ++i) jsnow_BindBufferMemory(d, b[i].buffer, b[i].memory, b[i].memoryOffset);
  return VK_SUCCESS;
}
VKAPI VkResult VKAPI_CALL jsnow_BindImageMemory2(VkDevice d, uint32_t n, const VkBindImageMemoryInfo* b) {
  for (uint32_t i = 0; i < n; ++i) jsnow_BindImageMemory(d, b[i].image, b[i].memory, b[i].memoryOffset);
  return VK_SUCCESS;
}
VKAPI void VKAPI_CALL jsnow_GetDeviceQueue2(VkDevice d, const VkDeviceQueueInfo2*, VkQueue* q) { *q = from<VkQueue>(to<Device>(d)->queue); }
VKAPI void VKAPI_CALL jsnow_TrimCommandPool(VkDevice, VkCommandPool, VkCommandPoolTrimFlags) {}
VKAPI VkResult VKAPI_CALL jsnow_EnumeratePhysicalDeviceGroups(VkInstance i, uint32_t* c, VkPhysicalDeviceGroupProperties* p) {
  if (!p) { *c = 1; return VK_SUCCESS; }
  if (*c < 1) return VK_INCOMPLETE;
  p[0].physicalDeviceCount = 1;
  p[0].physicalDevices[0] = from<VkPhysicalDevice>(to<Instance>(i)->pd);
  p[0].subsetAllocation = VK_FALSE;
  *c = 1;
  return VK_SUCCESS;
}
VKAPI void VKAPI_CALL jsnow_GetDeviceGroupPeerMemoryFeatures(VkDevice, uint32_t, uint32_t, uint32_t, VkPeerMemoryFeatureFlags* f) {
  *f = VK_PEER_MEMORY_FEATURE_COPY_SRC_BIT | VK_PEER_MEMORY_FEATURE_COPY_DST_BIT;
}
VKAPI void VKAPI_CALL jsnow_CmdSetDeviceMask(VkCommandBuffer, uint32_t) {}
VKAPI void VKAPI_CALL jsnow_GetDescriptorSetLayoutSupport(VkDevice, const VkDescriptorSetLayoutCreateInfo*, VkDescriptorSetLayoutSupport* s) { s->supported = VK_TRUE; }
VKAPI void VKAPI_CALL jsnow_GetPhysicalDeviceExternalBufferProperties(VkPhysicalDevice, const VkPhysicalDeviceExternalBufferInfo*, VkExternalBufferProperties* p) {
  std::memset(&p->externalMemoryProperties, 0, sizeof p->externalMemoryProperties);
}
VKAPI void VKAPI_CALL jsnow_GetPhysicalDeviceExternalFenceProperties(VkPhysicalDevice, const VkPhysicalDeviceExternalFenceInfo*, VkExternalFenceProperties* p) {
  p->exportFromImportedHandleTypes = p->compatibleHandleTypes = 0; p->externalFenceFeatures = 0;
}
VKAPI void VKAPI_CALL jsnow_GetPhysicalDeviceExternalSemaphoreProperties(VkPhysicalDevice, const VkPhysicalDeviceExternalSemaphoreInfo*, VkExternalSemaphoreProperties* p) {
  p->exportFromImportedHandleTypes = p->compatibleHandleTypes = 0; p->externalSemaphoreFeatures = 0;
}
struct UpdateTemplate { std::vector<VkDescriptorUpdateTemplateEntry> entries; };
VKAPI VkResult VKAPI_CALL jsnow_CreateDescriptorUpdateTemplate(VkDevice, const VkDescriptorUpdateTemplateCreateInfo* ci, const VkAllocationCallbacks*, VkDescriptorUpdateTemplate* out) {
  auto* t = new UpdateTemplate();
  t->entries.assign(ci->pDescriptorUpdateEntries, ci->pDescriptorUpdateEntries + ci->descriptorUpdateEntryCount);
  *out = from<VkDescriptorUpdateTemplate>(t);
  return VK_SUCCESS;
}
VKAPI void VKAPI_CALL jsnow_DestroyDescriptorUpdateTemplate(VkDevice, VkDescriptorUpdateTemplate t, const VkAllocationCallbacks*) { delete to<UpdateTemplate>(t); }
VKAPI void VKAPI_CALL jsnow_UpdateDescriptorSetWithTemplate(VkDevice d, VkDescriptorSet set, VkDescriptorUpdateTemplate t, const void* data) {
  for (auto& e : to<UpdateTemplate>(t)->entries)
    for (uint32_t k = 0; k < e.descriptorCount; ++k) {
      const uint8_t* src = static_cast<const uint8_t*>(data) + e.offset + k * e.stride;
      VkWriteDescriptorSet w{VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET};
      w.dstSet = set; w.dstBinding = e.dstBinding; w.dstArrayElement = e.dstArrayElement + k;
      w.descriptorCount = 1; w.descriptorType = e.descriptorType;
      w.pBufferInfo = reinterpret_cast<const VkDescriptorBufferInfo*>(src);
      w.pImageInfo = reinterpret_cast<const VkDescriptorImageInfo*>(src);
      jsnow_UpdateDescriptorSets(d, 1, &w, 0, nullptr);
    }
}

// --- dispatch ---
static PFN_vkVoidFunction lookup(const char* name);
VKAPI PFN_vkVoidFunction VKAPI_CALL jsnow_GetInstanceProcAddr(VkInstance, const char* name) { return lookup(name); }
VKAPI PFN_vkVoidFunction VKAPI_CALL jsnow_GetDeviceProcAddr(VkDevice, const char* name) { return lookup(name); }
VKAPI VkResult VKAPI_CALL jsnow_EnumerateInstanceLayerProperties(uint32_t* c, VkLayerProperties*) { *c = 0; return VK_SUCCESS; }

static PFN_vkVoidFunction lookup(const char* name) {
#define E(fn) {"vk" #fn, reinterpret_cast<PFN_vkVoidFunction>(&jsnow_##fn)}
  static const std::unordered_map<std::string, PFN_vkVoidFunction> table = {
      E(GetInstanceProcAddr), E(GetDeviceProcAddr), E(EnumerateInstanceExtensionProperties),
      E(EnumerateInstanceLayerProperties), E(EnumerateInstanceVersion), E(CreateInstance), E(DestroyInstance),
      E(EnumeratePhysicalDevices), E(GetPhysicalDeviceProperties), E(GetPhysicalDeviceQueueFamilyProperties),
      E(GetPhysicalDeviceFeatures), E(GetPhysicalDeviceMemoryProperties), E(GetPhysicalDeviceFormatProperties),
      E(GetPhysicalDeviceImageFormatProperties), E(GetPhysicalDeviceSparseImageFormatProperties), E(EnumerateDeviceExtensionProperties),
      E(EnumerateDeviceLayerProperties), E(CreateDevice), E(DestroyDevice), E(GetDeviceQueue), E(DeviceWaitIdle),
      E(QueueWaitIdle), E(AllocateMemory), E(FreeMemory), E(MapMemory), E(UnmapMemory), E(FlushMappedMemoryRanges),
      E(InvalidateMappedMemoryRanges), E(CreateBuffer), E(DestroyBuffer), E(GetBufferMemoryRequirements),
      E(BindBufferMemory), E(CreateImage), E(DestroyImage), E(GetImageMemoryRequirements), E(BindImageMemory),
      E(GetImageSubresourceLayout), E(GetImageSparseMemoryRequirements), E(CreateImageView), E(DestroyImageView),
      E(CreateSampler), E(DestroySampler), E(CreateShaderModule), E(DestroyShaderModule), E(CreatePipelineCache),
      E(DestroyPipelineCache), E(GetPipelineCacheData), E(CreateDescriptorSetLayout), E(DestroyDescriptorSetLayout),
      E(CreatePipelineLayout), E(DestroyPipelineLayout), E(CreateDescriptorPool), E(DestroyDescriptorPool),
      E(ResetDescriptorPool), E(AllocateDescriptorSets), E(FreeDescriptorSets), E(UpdateDescriptorSets),
      E(CreateRenderPass), E(DestroyRenderPass), E(CreateFramebuffer), E(DestroyFramebuffer),
      E(CreateGraphicsPipelines), E(CreateComputePipelines), E(DestroyPipeline), E(CreateFence), E(DestroyFence),
      E(ResetFences), E(GetFenceStatus), E(WaitForFences), E(CreateSemaphore), E(DestroySemaphore),
      E(CreateCommandPool), E(DestroyCommandPool), E(ResetCommandPool), E(AllocateCommandBuffers),
      E(FreeCommandBuffers), E(BeginCommandBuffer), E(EndCommandBuffer), E(ResetCommandBuffer),
      E(CmdBeginRenderPass), E(CmdEndRenderPass), E(CmdNextSubpass), E(CmdBindPipeline), E(CmdBindDescriptorSets),
      E(CmdBindVertexBuffers), E(CmdBindIndexBuffer), E(CmdSetViewport), E(CmdSetScissor), E(CmdPushConstants),
      E(CmdDraw), E(CmdDrawIndexed), E(CmdPipelineBarrier), E(CmdCopyBuffer), E(CmdCopyBufferToImage),
      E(CmdCopyImageToBuffer), E(CmdCopyImage), E(CmdBlitImage), E(CmdClearColorImage), E(CmdClearDepthStencilImage),
      E(CmdClearAttachments), E(CmdUpdateBuffer), E(CmdFillBuffer), E(CmdExecuteCommands), E(CmdSetLineWidth),
      E(CmdSetDepthBias), E(CmdSetBlendConstants), E(CmdDispatch), E(QueueSubmit), E(DestroySurfaceKHR),
      E(GetPhysicalDeviceSurfaceSupportKHR), E(GetPhysicalDeviceSurfaceCapabilitiesKHR),
      E(GetPhysicalDeviceSurfaceFormatsKHR), E(GetPhysicalDeviceSurfacePresentModesKHR),
      E(GetPhysicalDeviceXcbPresentationSupportKHR), E(CreateSwapchainKHR), E(DestroySwapchainKHR),
      E(GetSwapchainImagesKHR), E(AcquireNextImageKHR), E(QueuePresentKHR),
      E(GetPhysicalDeviceFeatures2), E(GetPhysicalDeviceProperties2), E(GetPhysicalDeviceFormatProperties2),
      E(GetPhysicalDeviceImageFormatProperties2), E(GetPhysicalDeviceQueueFamilyProperties2),
      E(GetPhysicalDeviceMemoryProperties2), E(GetPhysicalDeviceSparseImageFormatProperties2),
      E(GetBufferMemoryRequirements2), E(GetImageMemoryRequirements2), E(GetImageSparseMemoryRequirements2),
      E(BindBufferMemory2), E(BindImageMemory2), E(GetDeviceQueue2), E(TrimCommandPool),
      E(EnumeratePhysicalDeviceGroups), E(GetDeviceGroupPeerMemoryFeatures), E(CmdSetDeviceMask),
      E(GetDescriptorSetLayoutSupport), E(GetPhysicalDeviceExternalBufferProperties),
      E(GetPhysicalDeviceExternalFenceProperties), E(GetPhysicalDeviceExternalSemaphoreProperties),
      E(CreateDescriptorUpdateTemplate), E(DestroyDescriptorUpdateTemplate), E(UpdateDescriptorSetWithTemplate)};
#undef E
  auto it = table.find(name);
  if (it != table.end()) return it->second;
  // KHR aliases of promoted 1.1 functions.
  std::string n(name);
  if (n.size() > 3 && n.compare(n.size() - 3, 3, "KHR") == 0) {
    it = table.find(n.substr(0, n.size() - 3));
    if (it != table.end()) return it->second;
  }
  if (std::getenv("JSNOW_ICD_VERBOSE")) std::fprintf(stderr, "[jsnow-icd] no entry point %s\n", name);
  return nullptr;
}

JSNOW_EXPORT VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL vk_icdGetInstanceProcAddr(VkInstance i, const char* name) {
  return lookup(name);
}
JSNOW_EXPORT VKAPI_ATTR VkResult VKAPI_CALL vk_icdNegotiateLoaderICDInterfaceVersion(uint32_t* v) {
  *v = std::min<uint32_t>(*v, 2);  // loader creates WSI surfaces
  return VK_SUCCESS;
}
