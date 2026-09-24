// Plain 2D maths for the sim. The simulation is 2D on the ground plane: x is
// world X, y is world Z. Height is sampled, never simulated.

#pragma once

#include <cmath>
#include <cstdint>

namespace army {

inline constexpr uint32_t kInvalidId = 0xFFFFFFFFu;

struct Vec2 {
	float x = 0.0f, y = 0.0f;
	Vec2() = default;
	Vec2(float px, float py) : x(px), y(py) {}
	Vec2 operator+(Vec2 o) const { return { x + o.x, y + o.y }; }
	Vec2 operator-(Vec2 o) const { return { x - o.x, y - o.y }; }
	Vec2 operator*(float s) const { return { x * s, y * s }; }
	Vec2 &operator+=(Vec2 o) { x += o.x; y += o.y; return *this; }
};

inline float dot(Vec2 a, Vec2 b) { return a.x * b.x + a.y * b.y; }
inline float length_sq(Vec2 v) { return v.x * v.x + v.y * v.y; }
inline float length(Vec2 v) { return std::sqrt(length_sq(v)); }
inline float dist_sq(Vec2 a, Vec2 b) { return length_sq(a - b); }
inline float clampf(float v, float lo, float hi) { return v < lo ? lo : (v > hi ? hi : v); }
inline float lerpf(float a, float b, float t) { return a + (b - a) * t; }

} // namespace army
