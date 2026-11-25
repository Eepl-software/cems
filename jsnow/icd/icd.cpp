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

#include "../src/simd.hpp"
#include "../src/threadpool.hpp"
#include "spirv.hpp"

static inline float halfToFloat(uint16_t h) {
  const uint32_t sgn = (h >> 15) & 1, e = (h >> 10) & 31, mnt = h & 1023;
  const float r = e == 0 ? std::ldexp(float(mnt), -24) : e == 31 ? (mnt ? NAN : INFINITY) : std::ldexp(float(mnt | 1024), int(e) - 25);
  return sgn ? -r : r;
}

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
    case VK_FORMAT_D16_UNORM: case VK_FORMAT_R8G8_UNORM: case VK_FORMAT_R16_SFLOAT: return 2;
    case VK_FORMAT_R16G16B16A16_SFLOAT: case VK_FORMAT_R32G32_UINT: case VK_FORMAT_R32G32_SINT: return 8;
    case VK_FORMAT_R16G16_SFLOAT: case VK_FORMAT_A2B10G10R10_UNORM_PACK32: case VK_FORMAT_B10G11R11_UFLOAT_PACK32: return 4;
    case VK_FORMAT_R8_UNORM: return 1;
    case VK_FORMAT_R32G32_SFLOAT: case VK_FORMAT_D32_SFLOAT_S8_UINT: return 8;
    case VK_FORMAT_R32G32B32A32_UINT: case VK_FORMAT_R32G32B32A32_SINT: return 16;
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
struct BufferView { Buffer* b; VkFormat f; VkDeviceSize offset, range; };
struct DescriptorPool { std::vector<DescriptorSet*> sets; };
struct PipelineLayout { std::vector<DescriptorSetLayout*> sets; };
struct Subpass {
  std::vector<uint32_t> color, input;  // attachment indices
  int depth = -1;
};
struct RenderPass {
  std::vector<VkAttachmentDescription> att;
  std::vector<Subpass> sub;
};
struct Framebuffer { std::vector<ImageView*> views; uint32_t w, h; };
struct Pipeline {
  std::shared_ptr<spv::Module> vs, fs, cs;
  uint32_t subpass = 0;
  std::vector<VkVertexInputBindingDescription> bindings;
  std::vector<VkVertexInputAttributeDescription> attrs;
  VkPrimitiveTopology topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
  VkCullModeFlags cull = VK_CULL_MODE_NONE;
  VkFrontFace front = VK_FRONT_FACE_COUNTER_CLOCKWISE;
  bool depthTest = false, depthWrite = false;
  VkCompareOp depthOp = VK_COMPARE_OP_LESS;
  std::vector<VkPipelineColorBlendAttachmentState> blends;
  VkViewport viewport{};
  VkRect2D scissor{};
  bool dynViewport = false, dynScissor = false;
  bool depthBias = false, dynDepthBias = false;
  float dbConst = 0, dbSlope = 0, dbClamp = 0;
  bool stencilTest = false, dynStencilCmp = false, dynStencilWrite = false, dynStencilRef = false;
  VkStencilOpState stencil[2]{};  // [0] front, [1] back
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
  float dbConst = 0, dbSlope = 0, dbClamp = 0;      // vkCmdSetDepthBias
  uint32_t stCmp[2] = {0xFF, 0xFF}, stWrite[2] = {0xFF, 0xFF}, stRef[2] = {0, 0};  // vkCmdSetStencil*
  Device* dev = nullptr;
  RenderPass* rp = nullptr;
  Framebuffer* fb = nullptr;
  VkRect2D area{};
  Pipeline* pipe = nullptr;
  DescriptorSet* sets[8] = {};  // graphics bind point
  std::vector<uint32_t> dynOffsets[8];
  DescriptorSet* csets[8] = {};  // compute bind point
  std::vector<uint32_t> cdynOffsets[8];
  Pipeline* cpipe = nullptr;
  bool computeMode = false;  // resource lookups use the compute bind point
  uint32_t subpass = 0;
  struct VB { Buffer* b = nullptr; VkDeviceSize off = 0; } vbs[16];
  Buffer* ib = nullptr;
  VkDeviceSize ibOff = 0;
  VkIndexType ibType = VK_INDEX_TYPE_UINT16;
  VkViewport vp{};
  VkRect2D scissor{};
  uint8_t push[256] = {};
  std::atomic<uint64_t>* query = nullptr;  // active occlusion query (samples passed)
  const uint8_t* buffer(int set, int binding) const override {
    DescriptorSet* const* sets = computeMode ? csets : this->sets;
    const std::vector<uint32_t>* dynOffsets = computeMode ? cdynOffsets : this->dynOffsets;
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
    DescriptorSet* const* sets = computeMode ? csets : this->sets;
    if (set < 0 || set >= 8 || !sets[set] || binding < 0 || size_t(binding) >= sets[set]->b.size()) return nullptr;
    const Descriptor& d = sets[set]->b[binding];
    return d.tex.data ? &d.tex : nullptr;
  }
};

int texFormatCode(VkFormat f);
void prepareTexelBuffer(Descriptor& d, BufferView* v) {
  spv::Texture& t = d.tex;
  Descriptor tmp;  // reuse the format table of prepareTexture
  t.isBuffer = true;
  t.data = v->b->ptr() + v->offset;
  t.levels = 1;
  t.levelOffset.assign(1, 0);
  t.levelPitch.assign(1, int(v->range));
  t.format = texFormatCode(v->f);
  const int bpp = std::max(1, formatSize(v->f));
  t.width = int(v->range / bpp);
  t.height = 1;
}
void prepareTexture(Descriptor& d) {
  if (!d.view) return;
  d.tex.isSubpass = d.type == VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT;
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
  switch (f) {
    case VK_FORMAT_B8G8R8A8_UNORM: case VK_FORMAT_B8G8R8A8_SRGB: t.format = 1; break;
    case VK_FORMAT_R32G32B32A32_SFLOAT: t.format = 2; break;
    case VK_FORMAT_D16_UNORM: t.format = 3; break;
    case VK_FORMAT_D32_SFLOAT: t.format = 4; break;
    case VK_FORMAT_D24_UNORM_S8_UINT: case VK_FORMAT_X8_D24_UNORM_PACK32: t.format = 5; break;
    case VK_FORMAT_R8_UNORM: t.format = 6; break;
    case VK_FORMAT_R16G16B16A16_SFLOAT: t.format = 7; break;
    case VK_FORMAT_R8G8_UNORM: t.format = 8; break;
    case VK_FORMAT_R8G8B8A8_UNORM: case VK_FORMAT_R8G8B8A8_SRGB: t.format = 0; break;
    case VK_FORMAT_R32_SFLOAT: t.format = 9; break;
    case VK_FORMAT_R32_UINT: t.format = 10; break;
    case VK_FORMAT_R32_SINT: t.format = 11; break;
    case VK_FORMAT_R32G32B32A32_UINT: case VK_FORMAT_R32G32B32A32_SINT: t.format = 12; break;
    case VK_FORMAT_R32G32_SFLOAT: t.format = 13; break;
    case VK_FORMAT_R16_SFLOAT: t.format = 14; break;
    case VK_FORMAT_R16G16_SFLOAT: t.format = 15; break;
    case VK_FORMAT_A2B10G10R10_UNORM_PACK32: t.format = 16; break;
    default: t.format = 0; missing("texture format " + std::to_string(int(f)));
  }
  if (d.sampler) {
    t.linear = d.sampler->ci.magFilter == VK_FILTER_LINEAR;
    auto am = [](VkSamplerAddressMode m) {
      return m == VK_SAMPLER_ADDRESS_MODE_MIRRORED_REPEAT ? 1
             : (m == VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE || m == VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER) ? 2 : 0;
    };
    t.addressU = am(d.sampler->ci.addressModeU);
    t.addressV = am(d.sampler->ci.addressModeV);
    t.compare = d.sampler->ci.compareEnable;
    t.compareOp = int(d.sampler->ci.compareOp);
    t.borderOne = (d.sampler->ci.borderColor == VK_BORDER_COLOR_FLOAT_OPAQUE_WHITE ||
                   d.sampler->ci.borderColor == VK_BORDER_COLOR_INT_OPAQUE_WHITE) ? 1.0f : 0.0f;
  }
}

inline uint16_t toHalf(float f) {
  uint32_t x; std::memcpy(&x, &f, 4);
  const uint32_t sgn = (x >> 16) & 0x8000;
  int e = int((x >> 23) & 0xFF) - 127 + 15;
  uint32_t mnt = x & 0x7FFFFF;
  if (e >= 31) return uint16_t(sgn | 0x7C00 | (((x >> 23) & 0xFF) == 0xFF && mnt ? 0x200 : 0));
  if (e <= 0) { if (e < -10) return uint16_t(sgn); mnt |= 0x800000; return uint16_t(sgn | (mnt >> (14 - e))); }
  return uint16_t(sgn | (e << 10) | (mnt >> 13));
}
inline float fromHalf(uint16_t h) {
  const uint32_t sgn = (h >> 15) & 1, e = (h >> 10) & 31, mnt = h & 1023;
  const float r = e == 0 ? std::ldexp(float(mnt), -24) : e == 31 ? (mnt ? NAN : INFINITY) : std::ldexp(float(mnt | 1024), int(e) - 25);
  return sgn ? -r : r;
}
int texFormatCode(VkFormat f) {
  switch (f) {
    case VK_FORMAT_B8G8R8A8_UNORM: case VK_FORMAT_B8G8R8A8_SRGB: return 1;
    case VK_FORMAT_R32G32B32A32_SFLOAT: return 2;
    case VK_FORMAT_R8_UNORM: return 6;
    case VK_FORMAT_R16G16B16A16_SFLOAT: return 7;
    case VK_FORMAT_R8G8_UNORM: return 8;
    case VK_FORMAT_R32_SFLOAT: return 9;
    case VK_FORMAT_R32_UINT: return 10;
    case VK_FORMAT_R32_SINT: return 11;
    case VK_FORMAT_R32G32B32A32_UINT: case VK_FORMAT_R32G32B32A32_SINT: return 12;
    case VK_FORMAT_R32G32_SFLOAT: return 13;
    case VK_FORMAT_R16_SFLOAT: return 14;
    case VK_FORMAT_R16G16_SFLOAT: return 15;
    case VK_FORMAT_A2B10G10R10_UNORM_PACK32: return 16;
    default: return 0;
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
    case VK_FORMAT_R16G16B16A16_SFLOAT: for (int i = 0; i < 4; ++i) { const uint16_t h = toHalf(c[i]); std::memcpy(p + 2 * i, &h, 2); } break;
    case VK_FORMAT_R16_SFLOAT: { const uint16_t h = toHalf(c[0]); std::memcpy(p, &h, 2); break; }
    case VK_FORMAT_R8_UNORM: p[0] = q(c[0]); break;
    case VK_FORMAT_R8G8_UNORM: p[0] = q(c[0]); p[1] = q(c[1]); break;
    default: break;
  }
}
void readColor(VkFormat f, const uint8_t* p, float c[4]) {
  switch (f) {
    case VK_FORMAT_B8G8R8A8_UNORM: case VK_FORMAT_B8G8R8A8_SRGB:
      c[0] = p[2] / 255.0f; c[1] = p[1] / 255.0f; c[2] = p[0] / 255.0f; c[3] = p[3] / 255.0f; break;
    case VK_FORMAT_R32G32B32A32_SFLOAT: std::memcpy(c, p, 16); break;
    case VK_FORMAT_R16G16B16A16_SFLOAT: for (int i = 0; i < 4; ++i) { uint16_t h; std::memcpy(&h, p + 2 * i, 2); c[i] = fromHalf(h); } break;
    case VK_FORMAT_R8_UNORM: c[0] = p[0] / 255.0f; c[1] = c[2] = 0; c[3] = 1; break;
    case VK_FORMAT_R8G8_UNORM: c[0] = p[0] / 255.0f; c[1] = p[1] / 255.0f; c[2] = 0; c[3] = 1; break;
    case VK_FORMAT_R32_SFLOAT: std::memcpy(c, p, 4); c[1] = c[2] = 0; c[3] = 1; break;
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
    uint32_t v; std::memcpy(&v, p, 4); v = (v & 0xFF000000u) | std::min(0xFFFFFFu, uint32_t(double(d) * 16777215.0 + 0.5)); std::memcpy(p, &v, 4);  // (float would round 2^24-0.5 up to 2^24)
    return;
  }
  std::memcpy(p, &d, 4);
}
uint8_t* stencilPtr(VkFormat f, uint8_t* p) {
  if (f == VK_FORMAT_D24_UNORM_S8_UINT) return p + 3;
  if (f == VK_FORMAT_D32_SFLOAT_S8_UINT) return p + 4;
  if (f == VK_FORMAT_S8_UINT) return p;
  return nullptr;
}
uint8_t stencilOp(VkStencilOp op, uint8_t s, uint8_t ref) {
  switch (op) {
    case VK_STENCIL_OP_ZERO: return 0;
    case VK_STENCIL_OP_REPLACE: return ref;
    case VK_STENCIL_OP_INCREMENT_AND_CLAMP: return s == 255 ? 255 : uint8_t(s + 1);
    case VK_STENCIL_OP_DECREMENT_AND_CLAMP: return s == 0 ? 0 : uint8_t(s - 1);
    case VK_STENCIL_OP_INVERT: return uint8_t(~s);
    case VK_STENCIL_OP_INCREMENT_AND_WRAP: return uint8_t(s + 1);
    case VK_STENCIL_OP_DECREMENT_AND_WRAP: return uint8_t(s - 1);
    default: return s;  // KEEP
  }
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

void drawPrimitives(Exec& ex, const std::vector<uint32_t>& vertexIds, uint32_t firstInstance, uint32_t instances);

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
  if (!count || !instances) return;
  // Several instances per pass (bounded so the post-transform vertex buffer stays small).
  std::vector<uint32_t> u = ids;
  std::sort(u.begin(), u.end());
  const size_t uniqN = size_t(std::unique(u.begin(), u.end()) - u.begin());
  const uint32_t per = uint32_t(std::max<size_t>(1, std::min<size_t>(instances, (1u << 18) / std::max<size_t>(1, uniqN))));
  for (uint32_t inst = 0; inst < instances; inst += per)
    drawPrimitives(ex, ids, firstInstance + inst, std::min(per, instances - inst));
}

struct DrawStats {
  std::atomic<uint64_t> vsNs{0}, setupNs{0}, fsNs{0}, csNs{0}, verts{0}, tris{0}, draws{0}, frags{0};
  ~DrawStats() {
    if (std::getenv("JSNOW_ICD_STATS"))
      std::fprintf(stderr, "[jsnow-icd] %llu draws, %llu vertices, %llu triangles, %llu fragment blocks; time: VS %.0f ms, "
                   "clip/setup %.0f ms, raster+FS %.0f ms\n", (unsigned long long)draws, (unsigned long long)verts,
                   (unsigned long long)tris, (unsigned long long)frags, vsNs / 1e6, setupNs / 1e6, fsNs / 1e6);
  }
} gStats;
using sclk = std::chrono::steady_clock;
inline uint64_t nsSince(sclk::time_point t) { return uint64_t(std::chrono::duration_cast<std::chrono::nanoseconds>(sclk::now() - t).count()); }

void drawPrimitives(Exec& ex, const std::vector<uint32_t>& ids, uint32_t firstInstance, uint32_t instances) {
  Pipeline& P = *ex.pipe;
  auto tStart = sclk::now();
  ++gStats.draws;
  if (!P.vs || !P.fs) return;
  const spv::Module& vs = *P.vs;
  const spv::Module& fs = *P.fs;
  // ---- vertex shading (unique vertex ids, 8 per batch) ----
  std::vector<uint32_t> uniq = ids;
  std::sort(uniq.begin(), uniq.end());
  uniq.erase(std::unique(uniq.begin(), uniq.end()), uniq.end());
  uint32_t posVar = 0;
  const int posComp = vs.findBuiltinOutputComp(0, posVar);  // BuiltIn Position
  const auto vsOut = vs.locationVars(3);
  const auto vsIn = vs.locationVars(1);
  const int vidVar = vs.findBuiltinInput(42), iidVar = vs.findBuiltinInput(43);
  std::vector<uint32_t> outComps;
  uint32_t K = 0;  // varying floats per vertex
  for (auto& o : vsOut) { outComps.push_back(vs.types[vs.vars[o.second].type].comps); K += outComps.back(); }
  const uint32_t stride = 4 + K;
  const size_t U = uniq.size();
  std::vector<float> vout(U * instances * stride, 0.0f);
  {
    // Vertex input plan (resolved once per draw).
    struct AttrPlan { uint32_t var, nc, stride, floats; const uint8_t* base; bool perInstance; VkFormat fmt; };
    std::vector<AttrPlan> plan;
    for (auto& in : vsIn) {
      AttrPlan ap{in.second, vs.types[vs.vars[in.second].type].comps, 0, 0, nullptr, false, VK_FORMAT_UNDEFINED};
      const VkVertexInputAttributeDescription* attr = nullptr;
      for (auto& a : P.attrs) if (int(a.location) == in.first) attr = &a;
      const VkVertexInputBindingDescription* bd = nullptr;
      if (attr) for (auto& bb : P.bindings) if (bb.binding == attr->binding) bd = &bb;
      if (attr && bd && ex.vbs[attr->binding].b) {
        ap.base = ex.vbs[attr->binding].b->ptr() + ex.vbs[attr->binding].off + attr->offset;
        ap.stride = bd->stride;
        ap.perInstance = bd->inputRate == VK_VERTEX_INPUT_RATE_INSTANCE;
        ap.fmt = attr->format;
        uint32_t fc = 0;
        switch (attr->format) {
          case VK_FORMAT_R32_SFLOAT: case VK_FORMAT_R32_SINT: case VK_FORMAT_R32_UINT: fc = 1; break;
          case VK_FORMAT_R32G32_SFLOAT: case VK_FORMAT_R32G32_SINT: case VK_FORMAT_R32G32_UINT: fc = 2; break;
          case VK_FORMAT_R32G32B32_SFLOAT: case VK_FORMAT_R32G32B32_SINT: case VK_FORMAT_R32G32B32_UINT: fc = 3; break;
          case VK_FORMAT_R32G32B32A32_SFLOAT: case VK_FORMAT_R32G32B32A32_SINT: case VK_FORMAT_R32G32B32A32_UINT: fc = 4; break;
          default: break;
        }
        ap.floats = std::min(fc, ap.nc);
      }
      plan.push_back(ap);
    }
    // Vertex shading in parallel: batches of 8 vertices of one instance, 8 batches per task.
    std::atomic<bool> failed{false};
    const size_t nb = (U + 7) / 8;  // batches per instance
    const size_t batchesTotal = nb * instances;
    const int vblocks = int((batchesTotal + 7) / 8);
    ex.dev->pool->run(vblocks, [&](int vb, int) {
    spv::Invocation& inv = spv::threadInvocation(vs);
    for (size_t bi = size_t(vb) * 8; bi < std::min(batchesTotal, size_t(vb) * 8 + 8); ++bi) {
      const uint32_t instance = firstInstance + uint32_t(bi / nb);
      const size_t b = (bi % nb) * 8;
      const size_t voutBase = size_t(bi / nb) * U;
      const int n = int(std::min<size_t>(8, U - b));
      if (vidVar >= 0) {
        int32_t* v = reinterpret_cast<int32_t*>(inv.input(uint32_t(vidVar)));
        for (int l = 0; l < 8; ++l) v[l] = int32_t(uniq[b + std::min(l, n - 1)]);
      }
      if (iidVar >= 0) {
        int32_t* v = reinterpret_cast<int32_t*>(inv.input(uint32_t(iidVar)));
        for (int l = 0; l < 8; ++l) v[l] = int32_t(instance);
      }
      for (const AttrPlan& ap : plan) {
        float* dst = inv.input(ap.var);
        for (uint32_t c = 0; c < ap.nc; ++c)
          for (int l = 0; l < 8; ++l) dst[c * 8 + l] = c == 3 ? 1.0f : 0.0f;
        if (!ap.base) continue;
        for (int l = 0; l < 8; ++l) {
          const uint32_t idx = ap.perInstance ? instance : uniq[b + std::min(l, n - 1)];
          const uint8_t* p = ap.base + size_t(idx) * ap.stride;
          if (ap.floats) {  // fast path: 32-bit float/int components
            for (uint32_t c = 0; c < ap.floats; ++c) std::memcpy(&dst[c * 8 + l], p + 4 * c, 4);
            continue;
          }
          float c4[4] = {0, 0, 0, 1};
          switch (ap.fmt) {
            case VK_FORMAT_R32_SFLOAT: std::memcpy(c4, p, 4); break;
            case VK_FORMAT_R32G32_SFLOAT: std::memcpy(c4, p, 8); break;
            case VK_FORMAT_R32G32B32_SFLOAT: std::memcpy(c4, p, 12); break;
            case VK_FORMAT_R32G32B32A32_SFLOAT: std::memcpy(c4, p, 16); break;
            case VK_FORMAT_R8G8B8A8_UNORM: for (int c = 0; c < 4; ++c) c4[c] = p[c] / 255.0f; break;
            case VK_FORMAT_B8G8R8A8_UNORM: for (int c = 0; c < 4; ++c) c4[c] = p[c == 3 ? 3 : 2 - c] / 255.0f; break;
            case VK_FORMAT_R8G8B8A8_SNORM:
              for (int c = 0; c < 4; ++c) c4[c] = std::max(-1.0f, int8_t(p[c]) / 127.0f);
              break;
            case VK_FORMAT_R8G8B8A8_UINT: for (int c = 0; c < 4; ++c) { const uint32_t u = p[c]; std::memcpy(&c4[c], &u, 4); } break;
            case VK_FORMAT_R8G8_UNORM: c4[0] = p[0] / 255.0f; c4[1] = p[1] / 255.0f; break;
            case VK_FORMAT_R16G16_SFLOAT: case VK_FORMAT_R16G16B16A16_SFLOAT: {
              const int nn = ap.fmt == VK_FORMAT_R16G16_SFLOAT ? 2 : 4;
              for (int c = 0; c < nn; ++c) { uint16_t h; std::memcpy(&h, p + 2 * c, 2); c4[c] = halfToFloat(h); }
              break;
            }
            case VK_FORMAT_R32_SINT: case VK_FORMAT_R32_UINT: std::memcpy(c4, p, 4); break;  // raw bits
            case VK_FORMAT_R32G32_SINT: case VK_FORMAT_R32G32_UINT: std::memcpy(c4, p, 8); break;
            case VK_FORMAT_R32G32B32A32_SINT: case VK_FORMAT_R32G32B32A32_UINT: std::memcpy(c4, p, 16); break;
            default: missing("vertex format " + std::to_string(int(ap.fmt))); break;
          }
          for (uint32_t c = 0; c < std::min(ap.nc, 4u); ++c) dst[c * 8 + l] = c4[c];
        }
      }
      inv.run(ex, 0xFF);
      if (!inv.error.empty()) { missing("vertex shader: " + inv.error); failed = true; return; }
      {
        const float* pos = posComp >= 0 ? inv.output(posVar) + posComp * 8 : nullptr;
        float* o0 = vout.data() + (voutBase + b) * stride;
        if (pos)
          for (int l = 0; l < n; ++l)
            for (int c = 0; c < 4; ++c) o0[size_t(l) * stride + c] = pos[c * 8 + l];
        uint32_t k = 4;
        for (size_t i = 0; i < vsOut.size(); ++i) {
          const float* src = inv.output(vsOut[i].second);
          for (uint32_t c = 0; c < outComps[i]; ++c, ++k)
            for (int l = 0; l < n; ++l) o0[size_t(l) * stride + k] = src[c * 8 + l];
        }
      }
    }
    });
    if (failed) return;
  }
  gStats.vsNs += nsSince(tStart);
  gStats.verts += U * instances;
  auto tSetup = sclk::now();
  // ---- primitive assembly + clipping (z >= 0, z <= w, guard band) ----
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
  // Set-up triangles: screen vertices + varyings/w in one flat pool (no per-triangle allocations).
  struct STri { SVert v[3]; uint32_t var; bool front; };
  const float G = 64.0f;
  auto dist = [&](const float* v, int plane) {
    switch (plane) {
      case 0: return v[2];         // z >= 0
      case 1: return v[3] - v[2];  // z <= w
      case 2: return G * v[3] - v[0];
      case 3: return G * v[3] + v[0];
      case 4: return G * v[3] - v[1];
      default: return G * v[3] + v[1];
    }
  };
  // Vertex index -> slot in the post-transform buffer (per instance block of U).
  std::vector<uint32_t> vslot(ids.size());
  for (size_t i = 0; i < ids.size(); ++i) vslot[i] = uint32_t(std::lower_bound(uniq.begin(), uniq.end(), ids[i]) - uniq.begin());
  auto setupRange = [&](size_t w0, size_t w1, std::vector<STri>& stris, std::vector<float>& varPool) {
  auto emit = [&](const float* const* pv) {  // pv: 3 clip-space vertices (stride floats)
    STri t;
    for (int j = 0; j < 3; ++j) {
      const float q = 1.0f / pv[j][3];
      t.v[j] = {vp.x + (pv[j][0] * q + 1) * vp.width * 0.5f, vp.y + (pv[j][1] * q + 1) * vp.height * 0.5f,
                vp.minDepth + pv[j][2] * q * (vp.maxDepth - vp.minDepth), q};
    }
    // Vulkan area with y down: a = -1/2 sum(x_i y_{i+1} - x_{i+1} y_i); CCW front if a > 0.
    float a = 0;
    for (int j = 0; j < 3; ++j) a += t.v[j].x * t.v[(j + 1) % 3].y - t.v[(j + 1) % 3].x * t.v[j].y;
    a *= -0.5f;
    if (a == 0 || std::isnan(a)) return;
    t.front = P.front == VK_FRONT_FACE_COUNTER_CLOCKWISE ? a > 0 : a < 0;
    if ((P.cull & VK_CULL_MODE_FRONT_BIT) && t.front) return;
    if ((P.cull & VK_CULL_MODE_BACK_BIT) && !t.front) return;
    {  // no pixel centre inside the bounding box (tiny or off-scissor triangle): nothing to draw
      const float mnx = std::min({t.v[0].x, t.v[1].x, t.v[2].x}), mxx = std::max({t.v[0].x, t.v[1].x, t.v[2].x});
      const float mny = std::min({t.v[0].y, t.v[1].y, t.v[2].y}), mxy = std::max({t.v[0].y, t.v[1].y, t.v[2].y});
      const float cx0 = std::max(std::ceil(mnx - 0.5f), float(sc.offset.x));
      const float cx1 = std::min(std::floor(mxx - 0.5f), float(sc.offset.x + int(sc.extent.width) - 1));
      const float cy0 = std::max(std::ceil(mny - 0.5f), float(sc.offset.y));
      const float cy1 = std::min(std::floor(mxy - 0.5f), float(sc.offset.y + int(sc.extent.height) - 1));
      if (cx0 > cx1 || cy0 > cy1) return;
    }
    t.var = uint32_t(varPool.size());
    for (int j = 0; j < 3; ++j)
      for (uint32_t k = 0; k < K; ++k) varPool.push_back(pv[j][4 + k] * t.v[j].q);  // perspective: var/w
    stris.push_back(t);
  };
  stris.reserve(w1 - w0);
  varPool.reserve((w1 - w0) * 3 * K);
  for (size_t w = w0; w < w1; ++w) {
    const auto& pr = prims[w % prims.size()];
    const size_t vbase = (w / prims.size()) * U;
    const float* pv[3];
    for (int j = 0; j < 3; ++j) pv[j] = vout.data() + (vbase + vslot[pr[j]]) * stride;
    int outside = 0;
    for (int plane = 0; plane < 6; ++plane) {
      int n = 0;
      for (int j = 0; j < 3; ++j) n += dist(pv[j], plane) < 0;
      if (n == 3) { outside = -1; break; }
      if (n) outside = 1;
    }
    if (outside < 0) continue;
    if (outside == 0) { emit(pv); continue; }  // fast path: no clipping
    // Sutherland-Hodgman against the 6 planes.
    std::vector<std::vector<float>> poly = {std::vector<float>(pv[0], pv[0] + stride), std::vector<float>(pv[1], pv[1] + stride),
                                            std::vector<float>(pv[2], pv[2] + stride)};
    for (int plane = 0; plane < 6 && poly.size() >= 3; ++plane) {
      std::vector<std::vector<float>> out;
      for (size_t k = 0; k < poly.size(); ++k) {
        const auto& va = poly[k];
        const auto& vb = poly[(k + 1) % poly.size()];
        const float da = dist(va.data(), plane), db = dist(vb.data(), plane);
        if (da >= 0) out.push_back(va);
        if ((da >= 0) != (db >= 0)) {
          const float t = da / (da - db);
          std::vector<float> c(stride);
          for (uint32_t j = 0; j < stride; ++j) c[j] = va[j] + (vb[j] - va[j]) * t;
          out.push_back(c);
        }
      }
      poly.swap(out);
    }
    for (size_t k = 1; k + 1 < poly.size(); ++k) {
      const float* tri[3] = {poly[0].data(), poly[k].data(), poly[k + 1].data()};
      emit(tri);
    }
  }
  };
  // Ordered chunks (blending needs primitive order), set up in parallel and concatenated.
  const size_t work = prims.size() * instances;
  const int chunks = work < 4096 ? 1 : std::min<int>(ex.dev->pool->size() * 2, int(work / 2048));
  std::vector<std::vector<STri>> cst(chunks);
  std::vector<std::vector<float>> cvar(chunks);
  if (chunks == 1) setupRange(0, work, cst[0], cvar[0]);
  else ex.dev->pool->run(chunks, [&](int c, int) { setupRange(work * c / chunks, work * (c + 1) / chunks, cst[c], cvar[c]); });
  std::vector<STri> stris;
  std::vector<float> varPool;
  if (chunks == 1) { stris.swap(cst[0]); varPool.swap(cvar[0]); }
  else {
    size_t nt = 0, nv = 0;
    for (int c = 0; c < chunks; ++c) { nt += cst[c].size(); nv += cvar[c].size(); }
    stris.reserve(nt); varPool.reserve(nv);
    for (int c = 0; c < chunks; ++c) {
      const uint32_t off = uint32_t(varPool.size());
      for (STri& t : cst[c]) { t.var += off; stris.push_back(t); }
      varPool.insert(varPool.end(), cvar[c].begin(), cvar[c].end());
    }
  }
  gStats.setupNs += nsSince(tSetup);
  gStats.tris += stris.size();
  if (stris.empty()) return;
  auto tRaster = sclk::now();
  struct RasterTimer { sclk::time_point t; ~RasterTimer() { gStats.fsNs += nsSince(t); } } rasterTimer{tRaster};
  // ---- rasterization: horizontal bands per thread, 4x2 pixel blocks ----
  RenderPass& rp = *ex.rp;
  const Subpass& sp = rp.sub[std::min<size_t>(ex.subpass, rp.sub.size() - 1)];
  ImageView* depthView = sp.depth >= 0 ? ex.fb->views[sp.depth] : nullptr;
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
  uint8_t outFast[4] = {0, 0, 0, 0};  // 1 RGBA8, 2 BGRA8: no blending, full write mask
  uint32_t fsOutComps[4] = {4, 4, 4, 4};
  for (size_t oi = 0; oi < fsOut.size() && oi < 4; ++oi) {
    const auto& fo = fsOut[oi];
    fsOutComps[oi] = std::min(4u, fs.types[fs.vars[fo.second].type].comps);
    if (fo.first < 0 || size_t(fo.first) >= sp.color.size() || sp.color[fo.first] == VK_ATTACHMENT_UNUSED) continue;
    const VkPipelineColorBlendAttachmentState* bs = size_t(fo.first) < P.blends.size() ? &P.blends[fo.first] : nullptr;
    if (bs && (bs->blendEnable || bs->colorWriteMask != 0xF)) continue;
    static const bool noFast = std::getenv("JSNOW_ICD_NO_FASTOUT") != nullptr;
    if (noFast) continue;
    const VkFormat f = ex.fb->views[sp.color[fo.first]]->format;
    if (f == VK_FORMAT_R8G8B8A8_UNORM || f == VK_FORMAT_R8G8B8A8_SRGB || f == VK_FORMAT_A8B8G8R8_UNORM_PACK32) outFast[oi] = 1;
    else if (f == VK_FORMAT_B8G8R8A8_UNORM || f == VK_FORMAT_B8G8R8A8_SRGB) outFast[oi] = 2;
  }
  const bool biasOn = P.depthBias && depthView;
  const float dbConst = P.dynDepthBias ? ex.dbConst : P.dbConst, dbSlope = P.dynDepthBias ? ex.dbSlope : P.dbSlope;
  const float dbClamp = P.dynDepthBias ? ex.dbClamp : P.dbClamp;
  static const bool dbgDraw = std::getenv("JSNOW_ICD_DEBUG_DRAWS") != nullptr;
  std::atomic<uint64_t> dbgCover{0}, dbgPass{0};
  struct DbgPrint { const bool& on; std::atomic<uint64_t>& c; std::atomic<uint64_t>& p; const Pipeline& P;
    ~DbgPrint() { if (on) std::fprintf(stderr, "[jsnow-draw] pipe %p stencil %d depthTest %d op %d: covered %llu passed %llu\n",
        (const void*)&P, P.stencilTest, P.depthTest, int(P.depthOp), (unsigned long long)c, (unsigned long long)p); } }
    dbgPrint{dbgDraw, dbgCover, dbgPass, P};
  const bool stencilOn = P.stencilTest && depthView && stencilPtr(depthView->format, depthView->img->at(0, 0, 0, 0));
  // Per-draw addressing (Image::at() per lane was ~7% of a vkQuake frame).
  uint8_t* const dBase = depthView ? depthView->img->at(0, depthView->baseLayer, 0, 0) : nullptr;
  const size_t dPitch = depthView ? size_t(depthView->img->at(0, depthView->baseLayer, 0, 1) - dBase) : 0;
  const size_t dBpp = depthView ? depthView->img->bpp : 0;
  auto dAt = [&](int X, int Y) { return dBase + size_t(Y) * dPitch + size_t(X) * dBpp; };
  uint8_t* cBase[8] = {}; size_t cPitch[8] = {}, cBpp[8] = {};
  for (size_t oi = 0; oi < fsOut.size() && oi < 8; ++oi) {
    const auto& fo = fsOut[oi];
    if (fo.first < 0 || size_t(fo.first) >= sp.color.size() || sp.color[fo.first] == VK_ATTACHMENT_UNUSED) continue;
    ImageView* cv = ex.fb->views[sp.color[fo.first]];
    cBase[oi] = cv->img->at(cv->baseLevel, cv->baseLayer, 0, 0);
    cPitch[oi] = size_t(cv->img->at(cv->baseLevel, cv->baseLayer, 0, 1) - cBase[oi]);
    cBpp[oi] = cv->img->bpp;
  }
  const int bands = std::max(1, std::min(ex.dev->pool->size() * 4, (y1 - y0 + 7) / 8));
  // Bin triangles into bands (order preserved within a band).
  std::vector<uint32_t> binStart(size_t(bands) + 1, 0), binIdx;
  {
    const int H = y1 - y0;
    std::vector<std::pair<int, int>> range(stris.size());
    for (size_t i = 0; i < stris.size(); ++i) {
      const STri& t = stris[i];
      const float mny = std::min({t.v[0].y, t.v[1].y, t.v[2].y}), mxy = std::max({t.v[0].y, t.v[1].y, t.v[2].y});
      const int lo = std::clamp(int((int64_t(std::floor(mny)) - y0) * bands / H) - 1, 0, bands - 1);
      const int hi = std::clamp(int((int64_t(std::ceil(mxy)) - y0) * bands / H) + 1, 0, bands - 1);
      range[i] = {lo, hi};
      for (int b = lo; b <= hi; ++b) ++binStart[size_t(b) + 1];
    }
    for (int b = 0; b < bands; ++b) binStart[size_t(b) + 1] += binStart[size_t(b)];
    binIdx.resize(binStart[size_t(bands)]);
    std::vector<uint32_t> fillPos(binStart.begin(), binStart.end() - 1);
    for (size_t i = 0; i < stris.size(); ++i)
      for (int b = range[i].first; b <= range[i].second; ++b) binIdx[fillPos[size_t(b)]++] = uint32_t(i);
  }
  ex.dev->pool->run(bands, [&](int band, int) {
    const int by0 = y0 + (y1 - y0) * band / bands, by1 = y0 + (y1 - y0) * (band + 1) / bands;
    if (by0 >= by1) return;
    spv::Invocation& inv = spv::threadInvocation(fs);
    for (uint32_t bi = binStart[size_t(band)]; bi < binStart[size_t(band) + 1]; ++bi) {
      const STri& t = stris[binIdx[bi]];
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
      // Edge functions (sign-normalised so inside >= 0), evaluated exactly at each block's
      // first pixel centre and stepped across the 4x2 lanes with SIMD.
      auto edge = [&](const SVert& p, const SVert& q, float x, float y) { return ((q.x - p.x) * (y - p.y) - (q.y - p.y) * (x - p.x)) * inv2; };
      using namespace jsnow::simd;
      alignas(32) static const float kOX[8] = {0, 1, 2, 3, 0, 1, 2, 3}, kOY[8] = {0, 0, 0, 0, 1, 1, 1, 1};
      const vf OX = load(kOX), OY = load(kOY);
      const vf d0 = fma(set1(-(C.y - B.y) * inv2), OX, set1((C.x - B.x) * inv2) * OY);
      const vf d1 = fma(set1(-(A.y - C.y) * inv2), OX, set1((A.x - C.x) * inv2) * OY);
      const vf d2 = fma(set1(-(B.y - A.y) * inv2), OX, set1((B.x - A.x) * inv2) * OY);
      const vf Az = set1(A.z), Bz = set1(B.z), Cz = set1(C.z), Aq = set1(A.q), Bq = set1(B.q), Cq = set1(C.q);
      const float* tvA = varPool.data() + t.var;
      float zBias = 0;
      if (biasOn) {
        // Vulkan depth bias: m * slope + r * constant, r = minimum resolvable difference of the format.
        const float dzdx = -(C.y - B.y) * inv2 * A.z - (A.y - C.y) * inv2 * B.z - (B.y - A.y) * inv2 * C.z;
        const float dzdy = (C.x - B.x) * inv2 * A.z + (A.x - C.x) * inv2 * B.z + (B.x - A.x) * inv2 * C.z;
        const float m = std::max(std::fabs(dzdx), std::fabs(dzdy));
        float r = 1.0f / 16777216.0f;
        if (depthView->format == VK_FORMAT_D16_UNORM) r = 1.0f / 65536.0f;
        else if (depthView->format == VK_FORMAT_D32_SFLOAT || depthView->format == VK_FORMAT_D32_SFLOAT_S8_UINT) {
          int e;
          std::frexp(std::max({std::fabs(A.z), std::fabs(B.z), std::fabs(C.z)}), &e);
          r = std::ldexp(1.0f, e - 24);
        }
        zBias = m * dbSlope + r * dbConst;
        if (dbClamp > 0) zBias = std::min(zBias, dbClamp);
        else if (dbClamp < 0) zBias = std::max(zBias, dbClamp);
      }
      const VkStencilOpState& sf = P.stencil[t.front ? 0 : 1];
      const uint32_t fi = t.front ? 0 : 1;
      const uint32_t stCmp = P.dynStencilCmp ? ex.stCmp[fi] : sf.compareMask;
      const uint32_t stWm = P.dynStencilWrite ? ex.stWrite[fi] : sf.writeMask;
      const uint32_t stRef = P.dynStencilRef ? ex.stRef[fi] : sf.reference;
      for (int y = yy0; y <= yy1; y += 2)
        for (int x = bx0; x <= bx1; x += 4) {
          const float cx = x + 0.5f, cy = y + 0.5f;
          const vf L0 = set1(edge(B, C, cx, cy)) + d0, L1 = set1(edge(C, A, cx, cy)) + d1, L2 = set1(edge(A, B, cx, cy)) + d2;
          uint8_t cover = uint8_t(bits((L0 >= zerof()) & (L1 >= zerof()) & (L2 >= zerof())));
          if (cover && (x < x0 || x + 3 >= x1 || y < by0 || y + 1 >= by1))
            for (int l = 0; l < 8; ++l) {
              const int X = x + (l & 3), Y = y + (l >> 2);
              if (X < x0 || X >= x1 || Y < by0 || Y >= by1) cover &= uint8_t(~(1 << l));
            }
          if (!cover) continue;
          alignas(32) float l0[8], l1[8], l2[8], z[8], qn[8];
          const vf Z = fma(L0, Az, fma(L1, Bz, L2 * Cz)) + set1(zBias), Q = fma(L0, Aq, fma(L1, Bq, L2 * Cq));
          store(l0, L0); store(l1, L1); store(l2, L2); store(z, Z); store(qn, Q);
          // Early stencil + depth test.
          uint8_t pass = cover;
          if (stencilOn)
            for (int l = 0; l < 8; ++l)
              if (pass & (1 << l)) {
                uint8_t* spp = stencilPtr(depthView->format, dAt(x + (l & 3), y + (l >> 2)));
                if (!depthPass(sf.compareOp, float(stRef & stCmp), float(*spp & stCmp))) {
                  *spp = uint8_t((*spp & ~stWm) | (stencilOp(sf.failOp, *spp, uint8_t(stRef)) & stWm));
                  pass &= uint8_t(~(1 << l));
                }
              }
          if (depthView && P.depthTest)
            for (int l = 0; l < 8; ++l)
              if (pass & (1 << l)) {
                uint8_t* dp = dAt(x + (l & 3), y + (l >> 2));
                if (!depthPass(P.depthOp, z[l], readDepth(depthView->format, dp))) {
                  if (dbgDraw) { static std::atomic<int> once{0}; if (once++ < 3) std::fprintf(stderr, "[jsnow-draw] depth fail z %g d %g fmt %d\n", z[l], readDepth(depthView->format, dp), int(depthView->format)); }
                  pass &= uint8_t(~(1 << l));
                  if (stencilOn) {
                    uint8_t* spp = stencilPtr(depthView->format, dp);
                    *spp = uint8_t((*spp & ~stWm) | (stencilOp(sf.depthFailOp, *spp, uint8_t(stRef)) & stWm));
                  }
                }
              }
          if (dbgDraw) { dbgCover += __builtin_popcount(cover); dbgPass += __builtin_popcount(pass); }
          if (!pass) continue;
          {
            const vf Wv = set1(1.0f) / Q;
            const float* tvB = tvA + K;
            const float* tvC = tvA + 2 * K;
            for (auto& im : inMap) {
              float* dst = inv.input(im.first);
              const uint32_t nc = fs.types[fs.vars[im.first].type].comps;
              for (uint32_t c = 0; c < nc; ++c) {
                const uint32_t o = im.second + c;
                storeu(dst + c * 8, fma(L0, set1(tvA[o]), fma(L1, set1(tvB[o]), L2 * set1(tvC[o]))) * Wv);
              }
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
          ++gStats.frags;
          for (int l = 0; l < 8; ++l) { inv.fragX[l] = x + (l & 3); inv.fragY[l] = y + (l >> 2); }
          inv.run(ex, 0xFF);  // helper lanes run too (derivatives)
          if (!inv.error.empty()) { missing("fragment shader: " + inv.error); return; }
          pass &= uint8_t(~inv.killed());
          if (ex.query && fsOut.empty())
            for (int l = 0; l < 8; ++l) if (pass & (1 << l)) ex.query->fetch_add(1, std::memory_order_relaxed);
          // 8-bit colour targets without blending: pack all 8 lanes with SIMD.
          alignas(32) uint32_t packed[4][8];
          for (size_t oi = 0; oi < fsOut.size() && oi < 4; ++oi) {
            if (!outFast[oi]) continue;
            const float* src = inv.output(fsOut[oi].second);
            vf ch[4];
            for (int k = 0; k < 4; ++k)
              ch[k] = k < int(fsOutComps[oi]) ? min(max(loadu(src + k * 8), zerof()), set1(1.0f)) : set1(k == 3 ? 1.0f : 0.0f);
            if (outFast[oi] == 2) std::swap(ch[0], ch[2]);
            vi px = set1i(0);
            for (int k = 0; k < 4; ++k) px = px | shlv(trunc_i(fma(ch[k], set1(255.0f), set1(0.5f))), set1i(8 * k));
            storei(packed[oi], px);
          }
          for (int l = 0; l < 8; ++l) {
            if (!(pass & (1 << l))) continue;
            const int X = x + (l & 3), Y = y + (l >> 2);
            if (depthView && P.depthWrite)
              writeDepth(depthView->format, dAt(X, Y), z[l]);
            if (stencilOn) {
              uint8_t* spp = stencilPtr(depthView->format, dAt(X, Y));
              *spp = uint8_t((*spp & ~stWm) | (stencilOp(sf.passOp, *spp, uint8_t(stRef)) & stWm));
            }
            for (size_t oi = 0; oi < fsOut.size(); ++oi) {  // one output per colour attachment (by location)
              const auto& fo = fsOut[oi];
              if (fo.first < 0 || size_t(fo.first) >= sp.color.size() || sp.color[fo.first] == VK_ATTACHMENT_UNUSED) continue;
              ImageView* cv = ex.fb->views[sp.color[fo.first]];
              if (oi < 4 && outFast[oi]) {
                std::memcpy(cBase[oi] + size_t(Y) * cPitch[oi] + size_t(X) * 4, &packed[oi][l], 4);
                continue;
              }
              const uint32_t nc = fs.types[fs.vars[fo.second].type].comps;
              float c[4] = {0, 0, 0, 1};
              for (uint32_t ch = 0; ch < std::min(nc, 4u); ++ch) c[ch] = inv.output(fo.second)[ch * 8 + l];
              uint8_t* cp = oi < 8 ? cBase[oi] + size_t(Y) * cPitch[oi] + size_t(X) * cBpp[oi] : cv->img->at(cv->baseLevel, cv->baseLayer, X, Y);
              const VkPipelineColorBlendAttachmentState* bs =
                  size_t(fo.first) < P.blends.size() ? &P.blends[fo.first] : nullptr;
              float d[4];
              if ((bs && bs->blendEnable) || (bs && bs->colorWriteMask != 0xF)) readColor(cv->format, cp, d);
              if (bs && bs->blendEnable) {
                float o[4];
                for (int ch = 0; ch < 4; ++ch) {
                  const bool alpha = ch == 3;
                  const float sf = blendFactor(alpha ? bs->srcAlphaBlendFactor : bs->srcColorBlendFactor, c, d, ch);
                  const float df = blendFactor(alpha ? bs->dstAlphaBlendFactor : bs->dstColorBlendFactor, c, d, ch);
                  o[ch] = c[ch] * sf + d[ch] * df;  // VK_BLEND_OP_ADD
                }
                std::memcpy(c, o, sizeof o);
              }
              if (bs && bs->colorWriteMask != 0xF)
                for (int ch = 0; ch < 4; ++ch) if (!(bs->colorWriteMask & (1 << ch))) c[ch] = d[ch];
              writeColor(cv->format, cp, c);
            }
            if (ex.query) ex.query->fetch_add(1, std::memory_order_relaxed);
          }
        }
    }
  });
}

void clearAttachment(ImageView* v, const VkClearValue& cv, const VkRect2D& r, int aspects = 3) {
  Image* im = v->img;
  const bool whole = !isDepth(v->format) || aspects == 3 || !stencilPtr(v->format, im->at(0, 0, 0, 0));
  if (whole && r.extent.height > 1 && r.offset.y < int32_t(im->h)) {
    // Fill the first row, then copy it (the per-pixel path below is only for partial depth/stencil).
    VkRect2D row = r;
    row.extent.height = 1;
    clearAttachment(v, cv, row, aspects);
    const uint32_t x0 = uint32_t(std::max(0, r.offset.x)), x1 = std::min(im->w, uint32_t(r.offset.x) + r.extent.width);
    if (x1 <= x0) return;
    const uint8_t* src = im->at(v->baseLevel, v->baseLayer, x0, uint32_t(r.offset.y));
    const size_t n = size_t(x1 - x0) * im->bpp;
    for (uint32_t y = uint32_t(r.offset.y) + 1; y < uint32_t(r.offset.y) + r.extent.height && y < im->h; ++y)
      std::memcpy(im->at(v->baseLevel, v->baseLayer, x0, y), src, n);
    return;
  }
  for (uint32_t y = r.offset.y; y < r.offset.y + r.extent.height && y < im->h; ++y)
    for (uint32_t x = r.offset.x; x < r.offset.x + r.extent.width && x < im->w; ++x) {
      uint8_t* p = im->at(v->baseLevel, v->baseLayer, x, y);
      if (isDepth(v->format)) {
        if (aspects & 1) writeDepth(v->format, p, cv.depthStencil.depth);
        if (aspects & 2) if (uint8_t* sp = stencilPtr(v->format, p)) *sp = uint8_t(cv.depthStencil.stencil);
      }
      else writeColor(v->format, p, cv.color.float32);
    }
}

// ----------------------------------------------------------- present (xcb)
void present(Swapchain* sc, Image* im) {
  static const bool skip = std::getenv("JSNOW_ICD_NO_PRESENT") != nullptr;
  ++sc->presented;
  if (std::getenv("JSNOW_ICD_STATS")) {
    static auto last = std::chrono::steady_clock::now();
    if (sc->presented % 50 == 0) {
      const auto now = std::chrono::steady_clock::now();
      std::fprintf(stderr, "[jsnow-icd] presented %llu frames, last 50 at %.2f FPS\n", (unsigned long long)sc->presented,
                   50.0 / std::chrono::duration<double>(now - last).count());
      last = now;
    }
  }
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
                                                      {VK_KHR_XCB_SURFACE_EXTENSION_NAME, 6},
                                                      {VK_KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME, 2}};
static const VkExtensionProperties kDeviceExts[] = {{VK_KHR_SWAPCHAIN_EXTENSION_NAME, 70},
                                                    {VK_KHR_MAINTENANCE_1_EXTENSION_NAME, 2}};

template <class T>
static VkResult fillArray(uint32_t* count, T* out, const T* src, uint32_t n) {
  if (!out) { *count = n; return VK_SUCCESS; }
  const uint32_t k = std::min(*count, n);
  for (uint32_t i = 0; i < k; ++i) out[i] = src[i];
  *count = k;
  return k < n ? VK_INCOMPLETE : VK_SUCCESS;
}

VKAPI VkResult VKAPI_CALL jsnow_EnumerateInstanceExtensionProperties(const char*, uint32_t* c, VkExtensionProperties* p) {
  return fillArray(c, p, kInstanceExts, 3);
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
    case VK_FORMAT_R32G32B32A32_SFLOAT: case VK_FORMAT_R16G16B16A16_SFLOAT: case VK_FORMAT_R8_UNORM:
    case VK_FORMAT_R8G8_UNORM:
      p->linearTilingFeatures = p->optimalTilingFeatures = color;
      p->bufferFeatures = VK_FORMAT_FEATURE_VERTEX_BUFFER_BIT;
      break;
    case VK_FORMAT_R32_SINT: case VK_FORMAT_R32_UINT: case VK_FORMAT_R32G32_SINT: case VK_FORMAT_R32G32B32A32_SINT:
    case VK_FORMAT_R32G32B32A32_UINT:
      p->bufferFeatures = VK_FORMAT_FEATURE_VERTEX_BUFFER_BIT;
      break;
    case VK_FORMAT_R32_SFLOAT: case VK_FORMAT_R32G32_SFLOAT: case VK_FORMAT_R32G32B32_SFLOAT:
      p->bufferFeatures = VK_FORMAT_FEATURE_VERTEX_BUFFER_BIT;
      break;
    case VK_FORMAT_D16_UNORM: case VK_FORMAT_D32_SFLOAT: case VK_FORMAT_D24_UNORM_S8_UINT:
      p->optimalTilingFeatures = VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT | VK_FORMAT_FEATURE_TRANSFER_SRC_BIT |
                                 VK_FORMAT_FEATURE_TRANSFER_DST_BIT | VK_FORMAT_FEATURE_SAMPLED_IMAGE_BIT |
                                 VK_FORMAT_FEATURE_SAMPLED_IMAGE_FILTER_LINEAR_BIT | VK_FORMAT_FEATURE_BLIT_SRC_BIT;
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
  return fillArray(c, p, kDeviceExts, 2);
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
        case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE: case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT:
          d.view = to<ImageView>(w[i].pImageInfo[k].imageView);
          prepareTexture(d);
          break;
        case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER: case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:
          if (w[i].pTexelBufferView && w[i].pTexelBufferView[k]) prepareTexelBuffer(d, to<BufferView>(w[i].pTexelBufferView[k]));
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
  for (uint32_t si = 0; si < ci->subpassCount; ++si) {
    const VkSubpassDescription& s = ci->pSubpasses[si];
    Subpass sp;
    for (uint32_t i = 0; i < s.colorAttachmentCount; ++i) sp.color.push_back(s.pColorAttachments[i].attachment);
    for (uint32_t i = 0; i < s.inputAttachmentCount; ++i) sp.input.push_back(s.pInputAttachments[i].attachment);
    if (s.pDepthStencilAttachment && s.pDepthStencilAttachment->attachment != VK_ATTACHMENT_UNUSED)
      sp.depth = int(s.pDepthStencilAttachment->attachment);
    if (s.pResolveAttachments) missing("resolve attachments (single-sampled: ignored)");
    rp->sub.push_back(sp);
  }
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
      if (const VkSpecializationInfo* si = c.pStages[s].pSpecializationInfo) {
        auto copy = std::make_shared<spv::Module>(*mod);
        std::vector<std::array<uint32_t, 3>> entries;
        for (uint32_t k = 0; k < si->mapEntryCount; ++k)
          entries.push_back({si->pMapEntries[k].constantID, si->pMapEntries[k].offset, uint32_t(si->pMapEntries[k].size)});
        copy->specialize(entries, static_cast<const uint8_t*>(si->pData));
        mod = copy;
      }
      if (c.pStages[s].stage == VK_SHADER_STAGE_VERTEX_BIT) p->vs = mod;
      else if (c.pStages[s].stage == VK_SHADER_STAGE_FRAGMENT_BIT) p->fs = mod;
      else missing("shader stage " + std::to_string(int(c.pStages[s].stage)));
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
      p->depthBias = c.pRasterizationState->depthBiasEnable;
      p->dbConst = c.pRasterizationState->depthBiasConstantFactor;
      p->dbSlope = c.pRasterizationState->depthBiasSlopeFactor;
      p->dbClamp = c.pRasterizationState->depthBiasClamp;
    }
    if (c.pDepthStencilState) {
      p->depthTest = c.pDepthStencilState->depthTestEnable;
      p->depthWrite = c.pDepthStencilState->depthWriteEnable;
      p->depthOp = c.pDepthStencilState->depthCompareOp;
      p->stencilTest = c.pDepthStencilState->stencilTestEnable;
      p->stencil[0] = c.pDepthStencilState->front;
      p->stencil[1] = c.pDepthStencilState->back;
    }
    if (c.pColorBlendState && c.pColorBlendState->attachmentCount) {
      p->blends.assign(c.pColorBlendState->pAttachments, c.pColorBlendState->pAttachments + c.pColorBlendState->attachmentCount);
      for (auto& b : p->blends)
        if (b.blendEnable && (b.colorBlendOp != VK_BLEND_OP_ADD || b.alphaBlendOp != VK_BLEND_OP_ADD))
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
        else if (d == VK_DYNAMIC_STATE_DEPTH_BIAS) p->dynDepthBias = true;
        else if (d == VK_DYNAMIC_STATE_STENCIL_COMPARE_MASK) p->dynStencilCmp = true;
        else if (d == VK_DYNAMIC_STATE_STENCIL_WRITE_MASK) p->dynStencilWrite = true;
        else if (d == VK_DYNAMIC_STATE_STENCIL_REFERENCE) p->dynStencilRef = true;
        else if (d == VK_DYNAMIC_STATE_BLEND_CONSTANTS || d == VK_DYNAMIC_STATE_LINE_WIDTH) {}
        else missing("dynamic state " + std::to_string(int(d)));
      }
    if (c.pMultisampleState && c.pMultisampleState->rasterizationSamples != VK_SAMPLE_COUNT_1_BIT) missing("MSAA");
    out[i] = from<VkPipeline>(p);
  }
  return VK_SUCCESS;
}
VKAPI VkResult VKAPI_CALL jsnow_CreateComputePipelines(VkDevice, VkPipelineCache, uint32_t n, const VkComputePipelineCreateInfo* ci, const VkAllocationCallbacks*, VkPipeline* out) {
  for (uint32_t i = 0; i < n; ++i) {
    auto* p = new Pipeline();
    auto mod = to<ShaderModule>(ci[i].stage.module)->mod;
    if (const VkSpecializationInfo* si = ci[i].stage.pSpecializationInfo) {
      auto copy = std::make_shared<spv::Module>(*mod);
      std::vector<std::array<uint32_t, 3>> entries;
      for (uint32_t k = 0; k < si->mapEntryCount; ++k)
        entries.push_back({si->pMapEntries[k].constantID, si->pMapEntries[k].offset, uint32_t(si->pMapEntries[k].size)});
      copy->specialize(entries, static_cast<const uint8_t*>(si->pData));
      mod = copy;
    }
    p->cs = mod;
    out[i] = from<VkPipeline>(p);
  }
  return VK_SUCCESS;
}

// Compute dispatch: invocations of a workgroup are independent (barriers and
// shared memory are not supported), so they run in 8-lane batches, workgroups in parallel.
void cmdDispatch(Exec& ex, uint32_t gx, uint32_t gy, uint32_t gz, uint32_t bx, uint32_t by, uint32_t bz) {
  if (!ex.cpipe || !ex.cpipe->cs) return;
  const spv::Module& cs = *ex.cpipe->cs;
  const uint32_t lx = cs.localSize[0], ly = cs.localSize[1], lz = cs.localSize[2];
  const uint32_t local = lx * ly * lz;
  const int gid = cs.findBuiltinInput(28), lid = cs.findBuiltinInput(27), wid = cs.findBuiltinInput(26);
  const int nwg = cs.findBuiltinInput(24), lix = cs.findBuiltinInput(29);
  const uint64_t groups = uint64_t(gx) * gy * gz;
  if (!groups) return;
  ex.computeMode = true;
  const auto tCs = sclk::now();
  struct CsTimer { sclk::time_point t; ~CsTimer() { gStats.csNs += nsSince(t); } } csTimer{tCs};
  const uint32_t batches = (local + 7) / 8;
  const bool group = cs.usesWorkgroupMemory();  // shared memory / barriers: run batches together
  const int tasks = int(std::min<uint64_t>(groups, 4096));
  std::atomic<bool> failed{false};
  ex.dev->pool->run(tasks, [&](int task, int) {
    if (failed) return;
    spv::Invocation* batch[64];
    uint8_t masks[64];
    const uint64_t g0 = groups * task / tasks, g1 = groups * (task + 1) / tasks;
    for (uint64_t g = g0; g < g1; ++g) {
      const uint32_t wx = uint32_t(g % gx) + bx, wy = uint32_t((g / gx) % gy) + by, wz = uint32_t(g / (uint64_t(gx) * gy)) + bz;
      auto fill = [&](spv::Invocation& inv, uint32_t base) {
        uint8_t mask = 0;
        auto set3 = [&](int var, auto fn) {
          if (var < 0) return;
          uint32_t* v = reinterpret_cast<uint32_t*>(inv.input(uint32_t(var)));
          for (int l = 0; l < 8; ++l) {
            const uint32_t li = std::min(base + l, local - 1);
            uint32_t xyz[3];
            fn(li, xyz);
            v[l] = xyz[0]; v[8 + l] = xyz[1]; v[16 + l] = xyz[2];
          }
        };
        for (int l = 0; l < 8; ++l) if (base + l < local) mask |= uint8_t(1 << l);
        set3(lid, [&](uint32_t li, uint32_t* o) { o[0] = li % lx; o[1] = (li / lx) % ly; o[2] = li / (lx * ly); });
        set3(gid, [&](uint32_t li, uint32_t* o) {
          o[0] = wx * lx + li % lx; o[1] = wy * ly + (li / lx) % ly; o[2] = wz * lz + li / (lx * ly);
        });
        set3(wid, [&](uint32_t, uint32_t* o) { o[0] = wx; o[1] = wy; o[2] = wz; });
        set3(nwg, [&](uint32_t, uint32_t* o) { o[0] = gx; o[1] = gy; o[2] = gz; });
        if (lix >= 0) {
          uint32_t* v = reinterpret_cast<uint32_t*>(inv.input(uint32_t(lix)));
          for (int l = 0; l < 8; ++l) v[l] = std::min(base + l, local - 1);
        }
        return mask;
      };
      if (group && batches <= 64) {
        for (uint32_t b = 0; b < batches; ++b) { batch[b] = &spv::threadInvocation(cs, int(b)); masks[b] = fill(*batch[b], b * 8); }
        if (spv::runWorkgroup(batch, masks, int(batches), ex)) continue;
      }
      for (uint32_t base = 0; base < local; base += 8) {
        spv::Invocation& inv = spv::threadInvocation(cs);
        const uint8_t mask = fill(inv, base);
        inv.run(ex, mask);
        if (!inv.error.empty()) { missing("compute shader: " + inv.error); failed = true; return; }
      }
    }
  });
  ex.computeMode = false;
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
    ex.rp = rp; ex.fb = fb; ex.area = area; ex.subpass = 0;
    for (size_t i = 0; i < rp->att.size() && i < fb->views.size(); ++i) {
      const bool depth = isDepth(rp->att[i].format);
      if (i >= clears.size()) continue;
      const int aspects = (rp->att[i].loadOp == VK_ATTACHMENT_LOAD_OP_CLEAR ? 1 : 0) |
                          (depth && rp->att[i].stencilLoadOp == VK_ATTACHMENT_LOAD_OP_CLEAR ? 2 : 0);
      if (aspects) clearAttachment(fb->views[i], clears[i], area, depth ? aspects : 1);
    }
  });
}
VKAPI void VKAPI_CALL jsnow_CmdEndRenderPass(VkCommandBuffer c) { REC(c)([](Exec& ex) { ex.rp = nullptr; ex.fb = nullptr; }); }
VKAPI void VKAPI_CALL jsnow_CmdNextSubpass(VkCommandBuffer c, VkSubpassContents) { REC(c)([](Exec& ex) { ++ex.subpass; }); }
VKAPI void VKAPI_CALL jsnow_CmdBindPipeline(VkCommandBuffer c, VkPipelineBindPoint bp, VkPipeline p) {
  Pipeline* pp = to<Pipeline>(p);
  if (bp == VK_PIPELINE_BIND_POINT_COMPUTE) REC(c)([=](Exec& ex) { ex.cpipe = pp; });
  else REC(c)([=](Exec& ex) { ex.pipe = pp; });
}
VKAPI void VKAPI_CALL jsnow_CmdBindDescriptorSets(VkCommandBuffer c, VkPipelineBindPoint bp, VkPipelineLayout, uint32_t first, uint32_t n, const VkDescriptorSet* s, uint32_t nd, const uint32_t* d) {
  std::vector<DescriptorSet*> sets;
  for (uint32_t i = 0; i < n; ++i) sets.push_back(to<DescriptorSet>(s[i]));
  std::vector<uint32_t> dyn(d, d + nd);
  const bool compute = bp == VK_PIPELINE_BIND_POINT_COMPUTE;
  REC(c)([=](Exec& ex) {
    DescriptorSet** dst = compute ? ex.csets : ex.sets;
    std::vector<uint32_t>* dofs = compute ? ex.cdynOffsets : ex.dynOffsets;
    size_t k = 0;
    for (uint32_t i = 0; i < n; ++i) {
      dst[first + i] = sets[i];
      dofs[first + i].clear();
      if (!sets[i]) continue;
      for (auto& b : sets[i]->b)
        if ((b.type == VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC || b.type == VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC) && k < dyn.size())
          dofs[first + i].push_back(dyn[k++]);
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
      const Subpass& sp = ex.rp->sub[std::min<size_t>(ex.subpass, ex.rp->sub.size() - 1)];
      if (at.aspectMask & VK_IMAGE_ASPECT_COLOR_BIT) v = ex.fb->views[sp.color[at.colorAttachment]];
      else if (sp.depth >= 0) v = ex.fb->views[sp.depth];
      const int aspects = (at.aspectMask & (VK_IMAGE_ASPECT_COLOR_BIT | VK_IMAGE_ASPECT_DEPTH_BIT) ? 1 : 0) |
                          (at.aspectMask & VK_IMAGE_ASPECT_STENCIL_BIT ? 2 : 0);
      if (v) for (auto& rr : rs) clearAttachment(v, at.clearValue, rr.rect, aspects);
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
VKAPI void VKAPI_CALL jsnow_CmdSetDepthBias(VkCommandBuffer c, float k, float clamp, float slope) {
  REC(c)([=](Exec& ex) { ex.dbConst = k; ex.dbClamp = clamp; ex.dbSlope = slope; });
}
VKAPI void VKAPI_CALL jsnow_CmdSetBlendConstants(VkCommandBuffer, const float[4]) { missing("blend constants"); }
VKAPI void VKAPI_CALL jsnow_CmdDispatch(VkCommandBuffer c, uint32_t x, uint32_t y, uint32_t z) {
  REC(c)([=](Exec& ex) { cmdDispatch(ex, x, y, z, 0, 0, 0); });
}

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
  if (std::getenv("JSNOW_ICD_STATS") && submits % 100 == 0) {
    static double lastMs = 0;
    static uint64_t lv = 0, ls = 0, lf = 0, lc = 0, ld = 0, lt = 0, lb = 0;
    const uint64_t v = gStats.vsNs, su = gStats.setupNs, fsn = gStats.fsNs, c = gStats.csNs, d = gStats.draws,
                   t = gStats.tris, b = gStats.frags;
    std::fprintf(stderr, "[jsnow-icd] %llu submits, avg %.3f ms GPU work per submit; last 100: %.2f ms/submit = VS %.2f + "
                 "setup %.2f + raster/FS %.2f + compute %.2f (+ other); %.0f draws, %.0f tris, %.0f blocks per submit\n",
                 (unsigned long long)submits, totalMs / submits, (totalMs - lastMs) / 100, (v - lv) / 1e8, (su - ls) / 1e8,
                 (fsn - lf) / 1e8, (c - lc) / 1e8, (d - ld) / 100.0, (t - lt) / 100.0, (b - lb) / 100.0);
    lastMs = totalMs; lv = v; ls = su; lf = fsn; lc = c; ld = d; lt = t; lb = b;
  }
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

// --- remaining Vulkan 1.0 core: queries, indirect draws, events, buffer views, misc ---
struct QueryPool { std::vector<std::atomic<uint64_t>> v; VkQueryType type; explicit QueryPool(uint32_t n) : v(n) {} };
VKAPI VkResult VKAPI_CALL jsnow_CreateQueryPool(VkDevice, const VkQueryPoolCreateInfo* ci, const VkAllocationCallbacks*, VkQueryPool* out) {
  auto* q = new QueryPool(ci->queryCount);
  q->type = ci->queryType;
  if (ci->queryType == VK_QUERY_TYPE_PIPELINE_STATISTICS) missing("pipeline statistics queries (report 0)");
  *out = from<VkQueryPool>(q);
  return VK_SUCCESS;
}
VKAPI void VKAPI_CALL jsnow_DestroyQueryPool(VkDevice, VkQueryPool q, const VkAllocationCallbacks*) { delete to<QueryPool>(q); }
VKAPI VkResult VKAPI_CALL jsnow_GetQueryPoolResults(VkDevice, VkQueryPool qp, uint32_t first, uint32_t n, size_t, void* data, VkDeviceSize stride, VkQueryResultFlags flags) {
  QueryPool* q = to<QueryPool>(qp);
  for (uint32_t i = 0; i < n; ++i) {
    const uint64_t v = q->v[first + i].load();
    uint8_t* p = static_cast<uint8_t*>(data) + i * stride;
    if (flags & VK_QUERY_RESULT_64_BIT) {
      std::memcpy(p, &v, 8);
      if (flags & VK_QUERY_RESULT_WITH_AVAILABILITY_BIT) { const uint64_t one = 1; std::memcpy(p + 8, &one, 8); }
    } else {
      const uint32_t v32 = uint32_t(v);
      std::memcpy(p, &v32, 4);
      if (flags & VK_QUERY_RESULT_WITH_AVAILABILITY_BIT) { const uint32_t one = 1; std::memcpy(p + 4, &one, 4); }
    }
  }
  return VK_SUCCESS;
}
VKAPI void VKAPI_CALL jsnow_ResetQueryPool(VkDevice, VkQueryPool qp, uint32_t first, uint32_t n) {
  for (uint32_t i = 0; i < n; ++i) to<QueryPool>(qp)->v[first + i] = 0;
}
VKAPI void VKAPI_CALL jsnow_CmdResetQueryPool(VkCommandBuffer c, VkQueryPool qp, uint32_t first, uint32_t n) {
  QueryPool* q = to<QueryPool>(qp);
  REC(c)([=](Exec&) { for (uint32_t i = 0; i < n; ++i) q->v[first + i] = 0; });
}
VKAPI void VKAPI_CALL jsnow_CmdBeginQuery(VkCommandBuffer c, VkQueryPool qp, uint32_t i, VkQueryControlFlags) {
  QueryPool* q = to<QueryPool>(qp);
  REC(c)([=](Exec& ex) { if (q->type == VK_QUERY_TYPE_OCCLUSION) { q->v[i] = 0; ex.query = &q->v[i]; } });
}
VKAPI void VKAPI_CALL jsnow_CmdEndQuery(VkCommandBuffer c, VkQueryPool, uint32_t) { REC(c)([](Exec& ex) { ex.query = nullptr; }); }
VKAPI void VKAPI_CALL jsnow_CmdWriteTimestamp(VkCommandBuffer c, VkPipelineStageFlagBits, VkQueryPool qp, uint32_t i) {
  QueryPool* q = to<QueryPool>(qp);
  REC(c)([=](Exec&) {
    q->v[i] = uint64_t(std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now().time_since_epoch()).count());
  });
}
VKAPI void VKAPI_CALL jsnow_CmdCopyQueryPoolResults(VkCommandBuffer c, VkQueryPool qp, uint32_t first, uint32_t n, VkBuffer b, VkDeviceSize off, VkDeviceSize stride, VkQueryResultFlags flags) {
  REC(c)([=](Exec&) { jsnow_GetQueryPoolResults(nullptr, qp, first, n, 0, to<Buffer>(b)->ptr() + off, stride, flags); });
}
VKAPI void VKAPI_CALL jsnow_CmdDrawIndirect(VkCommandBuffer c, VkBuffer b, VkDeviceSize off, uint32_t n, uint32_t stride) {
  Buffer* bb = to<Buffer>(b);
  REC(c)([=](Exec& ex) {
    for (uint32_t i = 0; i < n; ++i) {
      VkDrawIndirectCommand d;
      std::memcpy(&d, bb->ptr() + off + i * stride, sizeof d);
      cmdDraw(ex, d.vertexCount, d.instanceCount, d.firstVertex, d.firstInstance, false, 0);
    }
  });
}
VKAPI void VKAPI_CALL jsnow_CmdDrawIndexedIndirect(VkCommandBuffer c, VkBuffer b, VkDeviceSize off, uint32_t n, uint32_t stride) {
  Buffer* bb = to<Buffer>(b);
  REC(c)([=](Exec& ex) {
    for (uint32_t i = 0; i < n; ++i) {
      VkDrawIndexedIndirectCommand d;
      std::memcpy(&d, bb->ptr() + off + i * stride, sizeof d);
      cmdDraw(ex, d.indexCount, d.instanceCount, d.firstIndex, d.firstInstance, true, d.vertexOffset);
    }
  });
}
VKAPI void VKAPI_CALL jsnow_CmdDispatchIndirect(VkCommandBuffer c, VkBuffer b, VkDeviceSize off) {
  Buffer* bb = to<Buffer>(b);
  REC(c)([=](Exec& ex) {
    VkDispatchIndirectCommand d;
    std::memcpy(&d, bb->ptr() + off, sizeof d);
    cmdDispatch(ex, d.x, d.y, d.z, 0, 0, 0);
  });
}
VKAPI void VKAPI_CALL jsnow_CmdDispatchBase(VkCommandBuffer c, uint32_t bx, uint32_t by, uint32_t bz, uint32_t x, uint32_t y, uint32_t z) {
  REC(c)([=](Exec& ex) { cmdDispatch(ex, x, y, z, bx, by, bz); });
}
struct Event { std::atomic<bool> set{false}; };
VKAPI VkResult VKAPI_CALL jsnow_CreateEvent(VkDevice, const VkEventCreateInfo*, const VkAllocationCallbacks*, VkEvent* out) { *out = from<VkEvent>(new Event()); return VK_SUCCESS; }
VKAPI void VKAPI_CALL jsnow_DestroyEvent(VkDevice, VkEvent e, const VkAllocationCallbacks*) { delete to<Event>(e); }
VKAPI VkResult VKAPI_CALL jsnow_GetEventStatus(VkDevice, VkEvent e) { return to<Event>(e)->set ? VK_EVENT_SET : VK_EVENT_RESET; }
VKAPI VkResult VKAPI_CALL jsnow_SetEvent(VkDevice, VkEvent e) { to<Event>(e)->set = true; return VK_SUCCESS; }
VKAPI VkResult VKAPI_CALL jsnow_ResetEvent(VkDevice, VkEvent e) { to<Event>(e)->set = false; return VK_SUCCESS; }
VKAPI void VKAPI_CALL jsnow_CmdSetEvent(VkCommandBuffer c, VkEvent e, VkPipelineStageFlags) { Event* ev = to<Event>(e); REC(c)([=](Exec&) { ev->set = true; }); }
VKAPI void VKAPI_CALL jsnow_CmdResetEvent(VkCommandBuffer c, VkEvent e, VkPipelineStageFlags) { Event* ev = to<Event>(e); REC(c)([=](Exec&) { ev->set = false; }); }
VKAPI void VKAPI_CALL jsnow_CmdWaitEvents(VkCommandBuffer, uint32_t, const VkEvent*, VkPipelineStageFlags, VkPipelineStageFlags, uint32_t, const VkMemoryBarrier*, uint32_t, const VkBufferMemoryBarrier*, uint32_t, const VkImageMemoryBarrier*) {}
VKAPI VkResult VKAPI_CALL jsnow_CreateBufferView(VkDevice, const VkBufferViewCreateInfo* ci, const VkAllocationCallbacks*, VkBufferView* out) {
  Buffer* b = to<Buffer>(ci->buffer);
  const VkDeviceSize range = ci->range == VK_WHOLE_SIZE ? b->size - ci->offset : ci->range;
  *out = from<VkBufferView>(new BufferView{b, ci->format, ci->offset, range});
  return VK_SUCCESS;
}
VKAPI void VKAPI_CALL jsnow_DestroyBufferView(VkDevice, VkBufferView v, const VkAllocationCallbacks*) { delete to<BufferView>(v); }
VKAPI void VKAPI_CALL jsnow_CmdResolveImage(VkCommandBuffer c, VkImage s, VkImageLayout l1, VkImage d, VkImageLayout l2, uint32_t n, const VkImageResolve* r) {
  std::vector<VkImageCopy> cp;  // single-sample "resolve" = copy
  for (uint32_t i = 0; i < n; ++i) cp.push_back({r[i].srcSubresource, r[i].srcOffset, r[i].dstSubresource, r[i].dstOffset, r[i].extent});
  jsnow_CmdCopyImage(c, s, l1, d, l2, n, cp.data());
}
VKAPI void VKAPI_CALL jsnow_CmdSetStencilCompareMask(VkCommandBuffer c, VkStencilFaceFlags f, uint32_t v) {
  REC(c)([=](Exec& ex) { if (f & 1) ex.stCmp[0] = v; if (f & 2) ex.stCmp[1] = v; });
}
VKAPI void VKAPI_CALL jsnow_CmdSetStencilWriteMask(VkCommandBuffer c, VkStencilFaceFlags f, uint32_t v) {
  REC(c)([=](Exec& ex) { if (f & 1) ex.stWrite[0] = v; if (f & 2) ex.stWrite[1] = v; });
}
VKAPI void VKAPI_CALL jsnow_CmdSetStencilReference(VkCommandBuffer c, VkStencilFaceFlags f, uint32_t v) {
  REC(c)([=](Exec& ex) { if (f & 1) ex.stRef[0] = v; if (f & 2) ex.stRef[1] = v; });
}
VKAPI void VKAPI_CALL jsnow_CmdSetDepthBounds(VkCommandBuffer, float, float) { missing("depth bounds test"); }
VKAPI void VKAPI_CALL jsnow_GetRenderAreaGranularity(VkDevice, VkRenderPass, VkExtent2D* g) { *g = {1, 1}; }
VKAPI VkResult VKAPI_CALL jsnow_MergePipelineCaches(VkDevice, VkPipelineCache, uint32_t, const VkPipelineCache*) { return VK_SUCCESS; }
VKAPI void VKAPI_CALL jsnow_GetDeviceMemoryCommitment(VkDevice, VkDeviceMemory m, VkDeviceSize* c) { *c = to<Memory>(m)->size; }
VKAPI VkResult VKAPI_CALL jsnow_QueueBindSparse(VkQueue, uint32_t, const VkBindSparseInfo*, VkFence) { missing("sparse binding"); return VK_ERROR_FEATURE_NOT_PRESENT; }

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
      E(CreateDescriptorUpdateTemplate), E(DestroyDescriptorUpdateTemplate), E(UpdateDescriptorSetWithTemplate),
      E(CreateQueryPool), E(DestroyQueryPool), E(GetQueryPoolResults), E(ResetQueryPool), E(CmdResetQueryPool),
      E(CmdBeginQuery), E(CmdEndQuery), E(CmdWriteTimestamp), E(CmdCopyQueryPoolResults), E(CmdDrawIndirect),
      E(CmdDrawIndexedIndirect), E(CmdDispatchIndirect), E(CmdDispatchBase), E(CreateEvent), E(DestroyEvent),
      E(GetEventStatus), E(SetEvent), E(ResetEvent), E(CmdSetEvent), E(CmdResetEvent), E(CmdWaitEvents),
      E(CreateBufferView), E(DestroyBufferView), E(CmdResolveImage), E(CmdSetStencilCompareMask),
      E(CmdSetStencilWriteMask), E(CmdSetStencilReference), E(CmdSetDepthBounds), E(GetRenderAreaGranularity),
      E(MergePipelineCaches), E(GetDeviceMemoryCommitment), E(QueueBindSparse)};
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
