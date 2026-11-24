#include "scene.hpp"

#include <cmath>
#include <random>

namespace jsnow {

static constexpr float kTerrainHalf = 80.0f;

float terrainHeight(float x, float z) {
  float h = 4.0f * std::sin(x * 0.07f) * std::cos(z * 0.06f);
  h += 2.0f * std::sin(x * 0.17f + 1.3f) * std::sin(z * 0.13f + 0.4f);
  h += 0.6f * std::sin(x * 0.53f + z * 0.41f);
  return h;
}

namespace {

uint32_t addVertex(Mesh& m, Vec3 p, Vec3 n) {
  n = normalize(n);
  m.px.push_back(p.x); m.py.push_back(p.y); m.pz.push_back(p.z);
  m.nx.push_back(n.x); m.ny.push_back(n.y); m.nz.push_back(n.z);
  return uint32_t(m.px.size() - 1);
}

Vec3 pos(const Mesh& m, uint32_t i) { return {m.px[i], m.py[i], m.pz[i]}; }
Vec3 nrm(const Mesh& m, uint32_t i) { return {m.nx[i], m.ny[i], m.nz[i]}; }

// Adds a triangle, fixing the winding so the geometric normal agrees with the
// vertex normals (front faces are CCW).
void addTri(Mesh& m, uint32_t a, uint32_t b, uint32_t c, Vec3 albedo) {
  Vec3 fn = cross(pos(m, b) - pos(m, a), pos(m, c) - pos(m, a));
  Vec3 vn = nrm(m, a) + nrm(m, b) + nrm(m, c);
  if (dot(fn, vn) < 0) std::swap(b, c);
  m.idx.push_back(a); m.idx.push_back(b); m.idx.push_back(c);
  m.ar.push_back(albedo.x); m.ag.push_back(albedo.y); m.ab.push_back(albedo.z);
}

Vec3 terrainAlbedo(Vec3 p, Vec3 n) {
  Vec3 grass{0.25f, 0.55f, 0.18f}, rock{0.45f, 0.40f, 0.36f}, snow{0.92f, 0.93f, 0.96f};
  float slope = 1.0f - n.y;
  Vec3 c = slope > 0.25f ? rock : grass;
  if (p.y > 4.5f) c = snow;
  // Cheap checker variation so motion is visible.
  int cx = int(std::floor(p.x * 0.25f)), cz = int(std::floor(p.z * 0.25f));
  float k = ((cx + cz) & 1) ? 1.0f : 0.85f;
  return c * k;
}

}  // namespace

Mesh buildScene() {
  Mesh m;
  // Terrain: 250 x 160 quads = 80,000 triangles.
  const int GX = 250, GZ = 160;
  const float sx = 2 * kTerrainHalf / GX, sz = 2 * kTerrainHalf / GZ;
  const uint32_t base = 0;
  for (int j = 0; j <= GZ; ++j)
    for (int i = 0; i <= GX; ++i) {
      float x = -kTerrainHalf + i * sx, z = -kTerrainHalf + j * sz;
      const float e = 0.05f;
      Vec3 n{terrainHeight(x - e, z) - terrainHeight(x + e, z), 2 * e,
             terrainHeight(x, z - e) - terrainHeight(x, z + e)};
      addVertex(m, {x, terrainHeight(x, z), z}, n);
    }
  for (int j = 0; j < GZ; ++j)
    for (int i = 0; i < GX; ++i) {
      uint32_t v00 = base + j * (GX + 1) + i, v10 = v00 + 1;
      uint32_t v01 = v00 + (GX + 1), v11 = v01 + 1;
      Vec3 c = terrainAlbedo(pos(m, v00), nrm(m, v00));
      addTri(m, v00, v01, v10, c);
      addTri(m, v10, v01, v11, c);
    }

  // 50 UV spheres, 11 stacks x 20 slices = 400 triangles each.
  std::mt19937 rng(1234);
  std::uniform_real_distribution<float> U(0.0f, 1.0f);
  const int S = 11, L = 20;
  const float kPi = 3.14159265358979f;
  for (int s = 0; s < 50; ++s) {
    float r = 1.5f + 3.0f * U(rng);
    float cx = (U(rng) * 2 - 1) * 55.0f, cz = (U(rng) * 2 - 1) * 55.0f;
    Vec3 center{cx, terrainHeight(cx, cz) + r * 0.8f, cz};
    float hue = U(rng);
    Vec3 alb{0.5f + 0.45f * std::cos(6.283f * hue), 0.5f + 0.45f * std::cos(6.283f * (hue + 0.33f)),
             0.5f + 0.45f * std::cos(6.283f * (hue + 0.67f))};
    uint32_t first = uint32_t(m.px.size());
    for (int i = 0; i <= S; ++i) {
      float th = kPi * i / S;
      for (int j = 0; j <= L; ++j) {
        float ph = 2 * kPi * j / L;
        Vec3 n{std::sin(th) * std::cos(ph), std::cos(th), std::sin(th) * std::sin(ph)};
        addVertex(m, center + n * r, n);
      }
    }
    auto V = [&](int i, int j) { return first + uint32_t(i * (L + 1) + j); };
    for (int i = 0; i < S; ++i)
      for (int j = 0; j < L; ++j) {
        if (i != 0) addTri(m, V(i, j), V(i + 1, j), V(i, j + 1), alb);
        if (i != S - 1) addTri(m, V(i, j + 1), V(i + 1, j), V(i + 1, j + 1), alb);
      }
  }
  return m;
}

}  // namespace jsnow
