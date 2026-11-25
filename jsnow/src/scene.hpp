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
  uint32_t firstCluster = 0, clusterCount = 0;  // meshlets of this range (Scene::clusters)
};

// Meshlet: up to kClusterTris consecutive triangles with bounds and a normal
// cone (all face normals within acos(coneCos) of coneAxis) for back-face culling.
constexpr uint32_t kClusterTris = 128;
struct Cluster {
  uint32_t firstIndex = 0, indexCount = 0;
  Vec3 center;
  float radius = 0;
  Vec3 coneAxis;
  float coneCos = -1;  // <= 0: never back-face culled
};

struct Object {
  Vec3 center;
  float radius = 0;
  int lodCount = 1;
  LodRange lod[3];
  float lodEdge[3] = {0, 0, 0};  // typical triangle edge length (world units) per LOD
  bool transparent = false;      // alpha-blended material (no shadow casting)
  bool occluder = false;         // used by the occlusion pre-pass (D3)
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

enum class SceneKind { Small, Large, Huge };

struct Scene {
  Mesh mesh;
  std::vector<Object> objects;
  std::vector<Material> materials;
  std::vector<PointLight> lights;
  std::vector<Cluster> clusters;
  TextureArray textures;  // one layer per material texture
  size_t fullDetailTriangles = 0;  // sum of LOD0 triangle counts
  std::string description;
};

float terrainHeight(float x, float z);

// Small: session-1 scene (100,000 triangles, one LOD).
// Large: ~1,000,000 triangles at full detail, 3 LODs per object.
// Huge: ~5,000,000 triangles at full detail (Phase D), 3 LODs per object.
Scene buildScene(ThreadPool& pool, SceneKind kind, int textureSize = 2048, int pointLights = 128);

// Frustum test of every object, LOD selection by projected size, then per
// meshlet frustum + normal-cone back-face culling (orthoDir = view direction of
// an orthographic pass, e.g. the shadow camera). Returns submitted triangles.
struct CullStats {
  int objectsVisible = 0, objectsOccluded = 0;
  size_t triangles = 0;
  size_t clustersTested = 0, clustersBackface = 0, clustersOccluded = 0;
};
// LOD: the finest level whose projected edge is >= kLodTargetPx pixels at a
// 1080-line reference (pixelsPerUnitAt1m = 1080 / (2 tan(fovy/2))).
constexpr float kLodTargetPx = 5.0f;
// Transparent objects go to *transparentOut, or are skipped when it is null
// (shadow passes: transparent objects do not cast shadows).
CullStats buildDrawList(const Scene& s, const Mat4& viewProj, Vec3 lodEye, float pixelsPerUnitAt1m,
                        bool cullNear, int lodBias, std::vector<DrawItem>& out,
                        std::vector<DrawItem>* transparentOut = nullptr, const Vec3* orthoDir = nullptr,
                        bool clusterCull = true, const class OcclusionCuller* occlusion = nullptr,
                        bool occludersOnly = false);

}  // namespace jsnow
