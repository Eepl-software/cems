#pragma once
#include <cstdint>
#include <vector>

#include "math.hpp"

namespace jsnow {

// Static indexed triangle mesh, structure-of-arrays.
struct Mesh {
  std::vector<float> px, py, pz;  // vertex positions (world)
  std::vector<float> nx, ny, nz;  // vertex normals (world, unit length)
  std::vector<uint32_t> idx;      // 3 indices per triangle, CCW = front
  std::vector<float> ar, ag, ab;  // per-triangle albedo
  size_t vertexCount() const { return px.size(); }
  size_t triangleCount() const { return idx.size() / 3; }
};

float terrainHeight(float x, float z);

// Terrain (80,000 tris) + 50 spheres (400 tris each) = 100,000 triangles.
Mesh buildScene();

}  // namespace jsnow
