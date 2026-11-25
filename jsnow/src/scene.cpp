#include "scene.hpp"

#include <algorithm>
#include <cmath>
#include <random>

namespace jsnow {

static constexpr float kSmallHalf = 80.0f;

float terrainHeight(float x, float z) {
  float h = 4.0f * std::sin(x * 0.07f) * std::cos(z * 0.06f);
  h += 2.0f * std::sin(x * 0.17f + 1.3f) * std::sin(z * 0.13f + 0.4f);
  h += 0.6f * std::sin(x * 0.53f + z * 0.41f);
  return h;
}

namespace {

constexpr float kTexRepeat = 0.25f;  // terrain: one texture repeat per 4 world units

Vec3 terrainNormal(float x, float z) {
  const float e = 0.05f;
  return normalize(Vec3{terrainHeight(x - e, z) - terrainHeight(x + e, z), 2 * e,
                        terrainHeight(x, z - e) - terrainHeight(x, z + e)});
}

uint32_t addVertex(Mesh& m, Vec3 p, Vec3 n, float u, float v) {
  n = normalize(n);
  m.px.push_back(p.x); m.py.push_back(p.y); m.pz.push_back(p.z);
  m.nx.push_back(n.x); m.ny.push_back(n.y); m.nz.push_back(n.z);
  m.tu.push_back(u); m.tv.push_back(v);
  return uint32_t(m.px.size() - 1);
}

Vec3 pos(const Mesh& m, uint32_t i) { return {m.px[i], m.py[i], m.pz[i]}; }
Vec3 nrm(const Mesh& m, uint32_t i) { return {m.nx[i], m.ny[i], m.nz[i]}; }

// Adds a triangle with the winding fixed so the geometric normal agrees with
// the vertex normals (front faces are CCW).
void addTri(Mesh& m, uint32_t a, uint32_t b, uint32_t c, uint16_t mat) {
  Vec3 fn = cross(pos(m, b) - pos(m, a), pos(m, c) - pos(m, a));
  Vec3 vn = nrm(m, a) + nrm(m, b) + nrm(m, c);
  if (dot(fn, vn) < 0) std::swap(b, c);
  m.idx.push_back(a); m.idx.push_back(b); m.idx.push_back(c);
  m.triMat.push_back(mat);
}

// Materials 0..2: grass, rock, snow.
uint16_t terrainMaterial(Vec3 p, Vec3 n) {
  if (p.y > 4.5f) return 2;
  return (1.0f - n.y) > 0.25f ? 1 : 0;
}

struct RangeBuilder {
  Mesh& m;
  LodRange r;
  explicit RangeBuilder(Mesh& mesh) : m(mesh) {
    r.firstIndex = uint32_t(m.idx.size());
    r.firstVertex = uint32_t(m.px.size());
  }
  LodRange done() {
    r.indexCount = uint32_t(m.idx.size()) - r.firstIndex;
    r.vertexCount = uint32_t(m.px.size()) - r.firstVertex;
    return r;
  }
};

// Terrain patch over [x0, x0+sx] x [z0, z0+sz] with nx x nz quads.
// Skirts hang 2 units below the border to hide cracks between LODs.
LodRange addTerrainPatch(Mesh& m, float x0, float z0, float sx, float sz, int nx, int nz, bool skirts) {
  RangeBuilder rb(m);
  const uint32_t base = uint32_t(m.px.size());
  for (int j = 0; j <= nz; ++j)
    for (int i = 0; i <= nx; ++i) {
      const float x = x0 + sx * i / nx, z = z0 + sz * j / nz;
      addVertex(m, {x, terrainHeight(x, z), z}, terrainNormal(x, z), x * kTexRepeat, z * kTexRepeat);
    }
  auto V = [&](int i, int j) { return base + uint32_t(j * (nx + 1) + i); };
  for (int j = 0; j < nz; ++j)
    for (int i = 0; i < nx; ++i) {
      const float cx = x0 + sx * (i + 0.5f) / nx, cz = z0 + sz * (j + 0.5f) / nz;
      const uint16_t mat = terrainMaterial({cx, terrainHeight(cx, cz), cz}, terrainNormal(cx, cz));
      addTri(m, V(i, j), V(i, j + 1), V(i + 1, j), mat);
      addTri(m, V(i + 1, j), V(i, j + 1), V(i + 1, j + 1), mat);
    }
  if (skirts) {
    auto edge = [&](int count, auto vertexAt, Vec3 outward) {
      std::vector<uint32_t> top, bottom;
      for (int k = 0; k <= count; ++k) {
        uint32_t t = vertexAt(k);
        top.push_back(t);
        Vec3 p = pos(m, t);
        p.y -= 2.0f;
        bottom.push_back(addVertex(m, p, nrm(m, t), m.tu[t], m.tv[t]));
      }
      for (int k = 0; k < count; ++k) {
        // Orient so the skirt faces outward (normals are the terrain's, so
        // addTri's winding fix would pick "up"; use outward explicitly).
        uint32_t a = top[k], b = top[k + 1], c = bottom[k];
        Vec3 fn = cross(pos(m, b) - pos(m, a), pos(m, c) - pos(m, a));
        if (dot(fn, outward) < 0) std::swap(b, c);
        m.idx.insert(m.idx.end(), {a, b, c});
        m.triMat.push_back(0);
        a = top[k + 1]; b = bottom[k + 1]; c = bottom[k];
        fn = cross(pos(m, b) - pos(m, a), pos(m, c) - pos(m, a));
        if (dot(fn, outward) < 0) std::swap(b, c);
        m.idx.insert(m.idx.end(), {a, b, c});
        m.triMat.push_back(0);
      }
    };
    edge(nx, [&](int k) { return V(k, 0); }, Vec3{0, 0, -1});
    edge(nx, [&](int k) { return V(k, nz); }, Vec3{0, 0, 1});
    edge(nz, [&](int k) { return V(0, k); }, Vec3{-1, 0, 0});
    edge(nz, [&](int k) { return V(nx, k); }, Vec3{1, 0, 0});
  }
  return rb.done();
}

// UV sphere with S stacks and L slices: 2 L (S - 1) triangles.
LodRange addSphere(Mesh& m, Vec3 center, float r, int S, int L, uint16_t mat) {
  RangeBuilder rb(m);
  const float kPi = 3.14159265358979f;
  const uint32_t first = uint32_t(m.px.size());
  for (int i = 0; i <= S; ++i) {
    const float th = kPi * i / S;
    for (int j = 0; j <= L; ++j) {
      const float ph = 2 * kPi * j / L;
      Vec3 n{std::sin(th) * std::cos(ph), std::cos(th), std::sin(th) * std::sin(ph)};
      addVertex(m, center + n * r, n, 3.0f * j / L, 1.5f * i / S);
    }
  }
  auto V = [&](int i, int j) { return first + uint32_t(i * (L + 1) + j); };
  for (int i = 0; i < S; ++i)
    for (int j = 0; j < L; ++j) {
      if (i != 0) addTri(m, V(i, j), V(i + 1, j), V(i, j + 1), mat);
      if (i != S - 1) addTri(m, V(i, j + 1), V(i + 1, j), V(i + 1, j + 1), mat);
    }
  return rb.done();
}

// Closed cylinder standing on `base`: segs x rings side quads + two caps.
LodRange addCylinder(Mesh& m, Vec3 base, float r, float height, int segs, int rings, uint16_t mat) {
  RangeBuilder rb(m);
  const float kTwoPi = 6.28318531f;
  const uint32_t first = uint32_t(m.px.size());
  for (int i = 0; i <= rings; ++i)
    for (int j = 0; j <= segs; ++j) {
      const float a = kTwoPi * j / segs;
      const Vec3 n{std::cos(a), 0, std::sin(a)};
      addVertex(m, base + Vec3{n.x * r, height * i / rings, n.z * r}, n, 4.0f * j / segs, height * i / rings * 0.25f);
    }
  auto V = [&](int i, int j) { return first + uint32_t(i * (segs + 1) + j); };
  for (int i = 0; i < rings; ++i)
    for (int j = 0; j < segs; ++j) {
      addTri(m, V(i, j), V(i + 1, j), V(i, j + 1), mat);
      addTri(m, V(i, j + 1), V(i + 1, j), V(i + 1, j + 1), mat);
    }
  for (int cap = 0; cap < 2; ++cap) {  // bottom (cap 0) and top (cap 1)
    const float y = cap ? height : 0.0f;
    const Vec3 n{0, cap ? 1.0f : -1.0f, 0};
    const uint32_t c = addVertex(m, base + Vec3{0, y, 0}, n, 0.5f, 0.5f);
    const uint32_t ring = uint32_t(m.px.size());
    for (int j = 0; j <= segs; ++j) {
      const float a = kTwoPi * j / segs;
      addVertex(m, base + Vec3{std::cos(a) * r, y, std::sin(a) * r}, n, 0.5f + 0.5f * std::cos(a), 0.5f + 0.5f * std::sin(a));
    }
    for (int j = 0; j < segs; ++j) addTri(m, c, ring + j, ring + j + 1, mat);
  }
  return rb.done();
}

// ---- procedural, tileable textures ----
inline uint32_t hash3(int x, int y, int seed) {
  uint32_t h = uint32_t(x) * 374761393u + uint32_t(y) * 668265263u + uint32_t(seed) * 2246822519u;
  h = (h ^ (h >> 13)) * 1274126177u;
  return h ^ (h >> 16);
}
inline float hashf(int x, int y, int seed) { return float(hash3(x, y, seed) & 0xFFFFFF) / 16777215.0f; }

// Value noise on a lattice that wraps every `period` cells.
float vnoise(float x, float y, int period, int seed) {
  const int xi = int(std::floor(x)), yi = int(std::floor(y));
  const float fx = x - xi, fy = y - yi;
  const float ux = fx * fx * (3 - 2 * fx), uy = fy * fy * (3 - 2 * fy);
  auto H = [&](int a, int b) {
    return hashf(((a % period) + period) % period, ((b % period) + period) % period, seed);
  };
  const float a = H(xi, yi), b = H(xi + 1, yi), c = H(xi, yi + 1), d = H(xi + 1, yi + 1);
  return (a + (b - a) * ux) + ((c + (d - c) * ux) - (a + (b - a) * ux)) * uy;
}

float fbm(float u, float v, int period, int seed, int octaves) {
  float sum = 0, amp = 0.5f, norm = 0;
  for (int o = 0; o < octaves; ++o) {
    sum += amp * vnoise(u * period, v * period, period, seed + o);
    norm += amp;
    amp *= 0.5f;
    period *= 2;
  }
  return sum / norm;
}

uint32_t rgba(float r, float g, float b) {
  auto c = [](float v) { return uint32_t(std::clamp(v, 0.0f, 1.0f) * 255.0f + 0.5f); };
  return c(r) | (c(g) << 8) | (c(b) << 16) | 0xFF000000u;
}

}  // namespace

Scene buildScene(ThreadPool& pool, SceneKind kind, int texSize, int pointLights) {
  Scene s;
  Mesh& m = s.mesh;
  const float N = float(texSize);

  // Textures: 0 grass, 1 rock, 2 snow, 3 painted tiles (tinted per sphere).
  std::vector<Texture> tex;
  tex.push_back(makeTexture(pool, texSize, [&](int x, int y) {
    const float u = x / N, v = y / N;
    const float f = fbm(u, v, 8, 11, 5);
    const float blades = hashf(x, y / 3, 5) * 0.25f;
    const float k = 0.65f + 0.55f * f + blades;
    return rgba(0.22f * k, 0.50f * k, 0.14f * k);
  }));
  tex.push_back(makeTexture(pool, texSize, [&](int x, int y) {
    const float u = x / N, v = y / N;
    const float f = fbm(u, v, 6, 21, 6);
    const float cracks = std::fabs(fbm(u, v, 4, 31, 4) - 0.5f) < 0.02f ? 0.55f : 1.0f;
    const float k = (0.6f + 0.7f * f) * cracks;
    return rgba(0.46f * k, 0.43f * k, 0.39f * k);
  }));
  tex.push_back(makeTexture(pool, texSize, [&](int x, int y) {
    const float f = fbm(x / N, y / N, 8, 41, 4);
    const float k = 0.88f + 0.14f * f;
    return rgba(0.93f * k, 0.95f * k, 1.0f * k);
  }));
  tex.push_back(makeTexture(pool, texSize, [&](int x, int y) {
    const float u = x / N, v = y / N;
    const int tx = int(u * 16), ty = int(v * 16);
    const float fu = u * 16 - tx, fv = v * 16 - ty;
    const bool mortar = fu < 0.06f || fv < 0.06f;
    const float f = fbm(u, v, 16, 51, 4);
    const float k = mortar ? 0.35f : (0.75f + 0.25f * hashf(tx, ty, 61)) * (0.85f + 0.3f * f);
    return rgba(k, k, k);
  }));
  s.textures = makeTextureArray(tex);
  s.materials.resize(3);
  s.materials[0].texture = 0; s.materials[0].roughness = 0.85f;
  s.materials[1].texture = 1; s.materials[1].roughness = 0.7f;
  s.materials[2].texture = 2; s.materials[2].roughness = 0.35f;

  const bool large = kind != SceneKind::Small;  // large and huge use chunks + 3 LODs
  const bool huge = kind == SceneKind::Huge;
  const float kTerrainHalf = huge ? 2 * kSmallHalf : kSmallHalf;
  // ---- terrain ----
  if (!large) {
    Object o;
    o.center = {0, 0, 0};
    o.radius = kTerrainHalf * 1.5f;
    o.lod[0] = addTerrainPatch(m, -kTerrainHalf, -kTerrainHalf, 2 * kTerrainHalf, 2 * kTerrainHalf, 250, 160, false);
    s.objects.push_back(o);
  } else {
    const int C = huge ? 32 : 16, Q = 40;  // CxC chunks of 40x40 quads, 10 m each
    const float cs = 2 * kTerrainHalf / C;
    for (int cz = 0; cz < C; ++cz)
      for (int cx = 0; cx < C; ++cx) {
        Object o;
        const float x0 = -kTerrainHalf + cx * cs, z0 = -kTerrainHalf + cz * cs;
        const float mx = x0 + cs / 2, mz = z0 + cs / 2;
        o.center = {mx, terrainHeight(mx, mz), mz};
        o.radius = cs * 0.75f + 8.0f;  // half diagonal + height variation
        o.lodCount = 3;
        for (int l = 0; l < 3; ++l) {
          o.lod[l] = addTerrainPatch(m, x0, z0, cs, cs, Q >> l, Q >> l, true);
          o.lodEdge[l] = cs / (Q >> l);
        }
        s.objects.push_back(o);
      }
  }

  // ---- huge scene: towers (good occluders) ----
  if (huge) {
    std::mt19937 towerRng(31337);
    std::uniform_real_distribution<float> T(0.0f, 1.0f);
    const uint16_t firstTowerMat = uint16_t(s.materials.size());
    for (int i = 0; i < 6; ++i) {
      Material tm;
      tm.texture = 1;
      const float k = 0.7f + 0.1f * i;
      tm.tint[0] = k; tm.tint[1] = k * (0.9f + 0.02f * i); tm.tint[2] = k * 0.85f;
      tm.roughness = 0.55f + 0.05f * i;
      s.materials.push_back(tm);
    }
    for (int i = 0; i < 480; ++i) {
      const float x = (T(towerRng) * 2 - 1) * 150.0f, z = (T(towerRng) * 2 - 1) * 150.0f;
      const float r = 1.5f + 2.5f * T(towerRng), height = 8.0f + 22.0f * T(towerRng);
      const uint16_t mat = uint16_t(firstTowerMat + i % 6);
      const Vec3 base{x, terrainHeight(x, z) - 2.0f, z};
      Object o;
      o.center = base + Vec3{0, height * 0.5f, 0};
      o.radius = std::sqrt(r * r + height * height * 0.25f);
      o.lodCount = 3;
      const int segs[3] = {48, 24, 12}, rings[3] = {29, 14, 6};
      for (int l = 0; l < 3; ++l) {
        o.lod[l] = addCylinder(m, base, r, height, segs[l], rings[l], mat);
        o.lodEdge[l] = std::min(6.283f * r / segs[l], height / rings[l]);
      }
      o.occluder = true;
      s.objects.push_back(o);
    }
  }

  // ---- spheres (same placement as session 1) ----
  std::mt19937 rng(1234), matRng(777);  // separate streams keep session-1 placement
  std::uniform_real_distribution<float> U(0.0f, 1.0f);
  for (int i = 0; i < 50; ++i) {
    const float r = 1.5f + 3.0f * U(rng);
    const float cx = (U(rng) * 2 - 1) * 55.0f, cz = (U(rng) * 2 - 1) * 55.0f;
    const Vec3 center{cx, terrainHeight(cx, cz) + r * 0.8f, cz};
    const float hue = U(rng);
    Material mat;
    mat.texture = 3;
    mat.tint[0] = 0.5f + 0.45f * std::cos(6.283f * hue);
    mat.tint[1] = 0.5f + 0.45f * std::cos(6.283f * (hue + 0.33f));
    mat.tint[2] = 0.5f + 0.45f * std::cos(6.283f * (hue + 0.67f));
    mat.roughness = 0.15f + 0.7f * U(matRng);
    mat.metallic = U(matRng) < 0.3f ? 1.0f : 0.0f;
    const uint16_t id = uint16_t(s.materials.size());
    s.materials.push_back(mat);
    Object o;
    o.center = center;
    o.radius = r;
    if (!large) {
      o.lod[0] = addSphere(m, center, r, 11, 20, id);
    } else {
      o.lodCount = 3;
      o.lod[0] = addSphere(m, center, r, 24, 48, id);
      o.lod[1] = addSphere(m, center, r, 12, 24, id);
      o.lod[2] = addSphere(m, center, r, 6, 12, id);
      for (int l = 0; l < 3; ++l) o.lodEdge[l] = 6.283f * r / (48 >> l);
    }
    s.objects.push_back(o);
  }
  // ---- transparency: water in the valleys + floating glass spheres ----
  {
    Material water;
    water.texture = 2;
    water.tint[0] = 0.10f; water.tint[1] = 0.32f; water.tint[2] = 0.42f;
    water.roughness = 0.08f;
    water.alpha = 0.55f;
    const uint16_t wid = uint16_t(s.materials.size());
    s.materials.push_back(water);
    const float level = -3.0f;
    const int C = 4, Q = 16;
    const float cs = 2 * kTerrainHalf / C;
    for (int cz = 0; cz < C; ++cz)
      for (int cx = 0; cx < C; ++cx) {
        RangeBuilder rb(m);
        const float x0 = -kTerrainHalf + cx * cs, z0 = -kTerrainHalf + cz * cs;
        const uint32_t base = uint32_t(m.px.size());
        for (int j = 0; j <= Q; ++j)
          for (int i = 0; i <= Q; ++i) {
            const float x = x0 + cs * i / Q, z = z0 + cs * j / Q;
            addVertex(m, {x, level, z}, {0, 1, 0}, x * 0.05f, z * 0.05f);
          }
        for (int j = 0; j < Q; ++j)
          for (int i = 0; i < Q; ++i) {
            const uint32_t v00 = base + j * (Q + 1) + i, v10 = v00 + 1, v01 = v00 + Q + 1, v11 = v01 + 1;
            addTri(m, v00, v01, v10, wid);
            addTri(m, v10, v01, v11, wid);
          }
        Object o;
        o.center = {x0 + cs / 2, level, z0 + cs / 2};
        o.radius = cs * 0.75f;
        o.lod[0] = rb.done();
        o.transparent = true;
        s.objects.push_back(o);
      }
    std::mt19937 glassRng(99);
    for (int i = 0; i < 8; ++i) {
      Material glass;
      glass.texture = 2;
      glass.tint[0] = 0.75f; glass.tint[1] = 0.85f; glass.tint[2] = 1.0f;
      glass.roughness = 0.05f;
      glass.alpha = 0.3f;
      const uint16_t gid = uint16_t(s.materials.size());
      s.materials.push_back(glass);
      const float x = (U(glassRng) * 2 - 1) * 45.0f, z = (U(glassRng) * 2 - 1) * 45.0f, r = 3.0f;
      const Vec3 c{x, terrainHeight(x, z) + 5.0f, z};
      Object o;
      o.center = c;
      o.radius = r;
      o.transparent = true;
      if (!large) {
        o.lod[0] = addSphere(m, c, r, 11, 20, gid);
      } else {
        o.lodCount = 3;
        o.lod[0] = addSphere(m, c, r, 24, 48, gid);
        o.lod[1] = addSphere(m, c, r, 12, 24, gid);
        o.lod[2] = addSphere(m, c, r, 6, 12, gid);
        for (int l = 0; l < 3; ++l) o.lodEdge[l] = 6.283f * r / (48 >> l);
      }
      s.objects.push_back(o);
    }
  }

  // Point lights: coloured lamps hovering 1.5-3 m above the terrain.
  std::mt19937 lightRng(4242);
  for (int i = 0; i < pointLights; ++i) {
    PointLight l;
    const float x = (U(lightRng) * 2 - 1) * 70.0f, z = (U(lightRng) * 2 - 1) * 70.0f;
    l.pos = {x, terrainHeight(x, z) + 1.5f + 1.5f * U(lightRng), z};
    l.radius = 9.0f;
    const float hue = U(lightRng);
    const float k = 22.0f;
    l.color[0] = k * (0.55f + 0.45f * std::cos(6.283f * hue));
    l.color[1] = k * (0.55f + 0.45f * std::cos(6.283f * (hue + 0.33f)));
    l.color[2] = k * (0.55f + 0.45f * std::cos(6.283f * (hue + 0.67f)));
    s.lights.push_back(l);
  }
  for (const Object& o : s.objects) s.fullDetailTriangles += o.lod[0].indexCount / 3;
  s.description = huge ? "huge (320 m terrain + 480 towers + spheres, 3 LODs)"
                 : large ? "large (chunked terrain + spheres, 3 LODs)" : "small (session-1 scene)";
  return s;
}

CullStats buildDrawList(const Scene& s, const Mat4& M, Vec3 eye, float pxPerUnit, bool cullNear, int lodBias,
                        std::vector<DrawItem>& out, std::vector<DrawItem>* transparentOut) {
  out.clear();
  if (transparentOut) transparentOut->clear();
  // Clip-space half-spaces as world planes (Gribb-Hartmann): row3 +- row0/1.
  float planes[5][4];
  int np = 0;
  for (int r = 0; r < 2; ++r)
    for (int sgn = -1; sgn <= 1; sgn += 2) {
      for (int c = 0; c < 4; ++c) planes[np][c] = M(3, c) + sgn * M(r, c);
      ++np;
    }
  if (cullNear) {  // w >= near (perspective): row3 - near
    for (int c = 0; c < 4; ++c) planes[np][c] = M(3, c);
    planes[np][3] -= 0.1f;
    ++np;
  }
  for (int p = 0; p < np; ++p) {
    const float l = std::sqrt(planes[p][0] * planes[p][0] + planes[p][1] * planes[p][1] + planes[p][2] * planes[p][2]);
    for (float& v : planes[p]) v /= l;
  }
  CullStats st;
  for (const Object& o : s.objects) {
    if (o.transparent && !transparentOut) continue;
    bool visible = true;
    for (int p = 0; p < np && visible; ++p)
      visible = planes[p][0] * o.center.x + planes[p][1] * o.center.y + planes[p][2] * o.center.z + planes[p][3] >= -o.radius;
    if (!visible) continue;
    const Vec3 dv = o.center - eye;
    const float dist = std::sqrt(dot(dv, dv));
    const float d = std::max(dist - o.radius, 1e-3f);  // nearest point of the bounds
    int lod = 0;
    while (lod + 1 < o.lodCount && o.lodEdge[lod] * pxPerUnit / d < kLodTargetPx) ++lod;
    lod = std::clamp(lod + lodBias, 0, o.lodCount - 1);
    (o.transparent ? *transparentOut : out).push_back({o.lod[lod]});
    ++st.objectsVisible;
    st.triangles += o.lod[lod].indexCount / 3;
  }
  return st;
}

}  // namespace jsnow
