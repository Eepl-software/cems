#pragma once
#include <cstdint>
#include <string>
#include <vector>

#include "math.hpp"
#include "texture.hpp"
#include "threadpool.hpp"

namespace jsnow {

// Global vertex / index pool, structure-of-arrays.
struct Mesh {
  std::vector<float> px, py, pz;  // positions (world)
  std::vector<float> nx, ny, nz;  // unit normals
  std::vector<float> tu, tv;      // texture coordinates (repeats)
  std::vector<uint32_t> idx;      // 3 per triangle, CCW = front
  std::vector<uint16_t> triMat;   // material per triangle
  size_t vertexCount() const { return px.size(); }
  size_t triangleCount() const { return idx.size() / 3; }
};

struct LodRange {
  uint32_t firstIndex = 0, indexCount = 0, firstVertex = 0, vertexCount = 0;
};

struct Object {
  Vec3 center;
  float radius = 0;
  int lodCount = 1;
  LodRange lod[3];
  float lodEdge[3] = {0, 0, 0};  // typical triangle edge length (world units) per LOD
};

// Metallic-roughness PBR material. alpha < 1 = transparent (forward, blended).
struct Material {
  int texture = 0;
  float tint[3] = {1, 1, 1};
  float roughness = 0.6f;
  float metallic = 0.0f;
  float alpha = 1.0f;
};

struct PointLight {
  Vec3 pos;
  float radius = 10.0f;    // influence ends here (smooth window)
  float color[3] = {1, 1, 1};  // linear radiance scale
};

// Something to draw this pass: a contiguous index range with its vertices.
struct DrawItem {
  LodRange r;
};

enum class SceneKind { Small, Large };

struct Scene {
  Mesh mesh;
  std::vector<Object> objects;
  std::vector<Material> materials;
  std::vector<PointLight> lights;
  TextureArray textures;  // one layer per material texture
  size_t fullDetailTriangles = 0;  // sum of LOD0 triangle counts
  std::string description;
};

float terrainHeight(float x, float z);

// Small: session-1 scene (100,000 triangles, one LOD).
// Large: ~1,000,000 triangles at full detail, 3 LODs per object.
Scene buildScene(ThreadPool& pool, SceneKind kind, int textureSize = 2048, int pointLights = 128);

// Frustum test of every object, LOD selection by projected size, draw list out.
// Returns the number of triangles submitted.
struct CullStats {
  int objectsVisible = 0;
  size_t triangles = 0;
};
// LOD: the finest level whose projected edge is >= kLodTargetPx pixels at a
// 1080-line reference (pixelsPerUnitAt1m = 1080 / (2 tan(fovy/2))).
constexpr float kLodTargetPx = 5.0f;
CullStats buildDrawList(const Scene& s, const Mat4& viewProj, Vec3 lodEye, float pixelsPerUnitAt1m,
                        bool cullNear, int lodBias, std::vector<DrawItem>& out);

}  // namespace jsnow
