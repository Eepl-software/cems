#pragma once
#include <cmath>

namespace jsnow {

struct Vec3 {
  float x = 0, y = 0, z = 0;
};
inline Vec3 operator+(Vec3 a, Vec3 b) { return {a.x + b.x, a.y + b.y, a.z + b.z}; }
inline Vec3 operator-(Vec3 a, Vec3 b) { return {a.x - b.x, a.y - b.y, a.z - b.z}; }
inline Vec3 operator*(Vec3 a, float s) { return {a.x * s, a.y * s, a.z * s}; }
inline float dot(Vec3 a, Vec3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
inline Vec3 cross(Vec3 a, Vec3 b) {
  return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x};
}
inline Vec3 normalize(Vec3 a) {
  float l = std::sqrt(dot(a, a));
  return l > 0 ? a * (1.0f / l) : a;
}

// Row-major 4x4 matrix, column vectors: v' = M * v.
struct Mat4 {
  float m[16] = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1};
  float& operator()(int r, int c) { return m[r * 4 + c]; }
  float operator()(int r, int c) const { return m[r * 4 + c]; }
};

inline Mat4 operator*(const Mat4& a, const Mat4& b) {
  Mat4 r;
  for (int i = 0; i < 4; ++i)
    for (int j = 0; j < 4; ++j) {
      float s = 0;
      for (int k = 0; k < 4; ++k) s += a(i, k) * b(k, j);
      r(i, j) = s;
    }
  return r;
}

// Right-handed view matrix (camera looks down -Z).
inline Mat4 lookAt(Vec3 eye, Vec3 target, Vec3 up) {
  Vec3 f = normalize(target - eye);
  Vec3 s = normalize(cross(f, up));
  Vec3 u = cross(s, f);
  Mat4 v;
  v(0, 0) = s.x; v(0, 1) = s.y; v(0, 2) = s.z; v(0, 3) = -dot(s, eye);
  v(1, 0) = u.x; v(1, 1) = u.y; v(1, 2) = u.z; v(1, 3) = -dot(u, eye);
  v(2, 0) = -f.x; v(2, 1) = -f.y; v(2, 2) = -f.z; v(2, 3) = dot(f, eye);
  return v;
}

// Inverse of a rigid (rotation + translation) transform.
inline Mat4 rigidInverse(const Mat4& v) {
  Mat4 r;
  for (int i = 0; i < 3; ++i)
    for (int j = 0; j < 3; ++j) r(i, j) = v(j, i);
  for (int i = 0; i < 3; ++i)
    r(i, 3) = -(r(i, 0) * v(0, 3) + r(i, 1) * v(1, 3) + r(i, 2) * v(2, 3));
  return r;
}

// Perspective projection. Clip w = -z_view. Clip z is unused by the rasterizer:
// depth is stored as 1/w (reversed, larger = closer, infinite far plane).
inline Mat4 perspective(float fovyRad, float aspect, float zNear) {
  float f = 1.0f / std::tan(fovyRad * 0.5f);
  Mat4 p;
  for (float& x : p.m) x = 0;
  p(0, 0) = f / aspect;
  p(1, 1) = f;
  p(2, 3) = zNear;
  p(3, 2) = -1;
  return p;
}

}  // namespace jsnow
