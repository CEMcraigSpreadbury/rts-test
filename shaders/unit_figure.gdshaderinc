// Shared by the figure shaders (unit_figure*.gdshader): FigureBatcher's
// per-instance data (see unit_figure.gdshader for the layout).

#include "res://shaders/util/compat_color.gdshaderinc"

vec3 figure_unpack_rgb(float packed) {
	float p = max(packed, 0.0);
	return vec3(floor(p / 65536.0), mod(floor(p / 256.0), 256.0), mod(p, 256.0)) / 255.0;
}

// A packed colour is the game's sRGB Color as is; lit maths wants it linear
// (on both renderers: nothing has decoded it, unlike a source_color uniform).
vec3 figure_to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

// True where a figure only `shown` (0..1) visible leaves this pixel out: a
// 4x4 ordered dither, steady on screen as the corpse sinks.
bool figure_dithered_out(float shown, vec2 frag) {
	if (shown >= 1.0) {
		return false;
	}
	int x = int(mod(frag.x, 4.0));
	int y = int(mod(frag.y, 4.0));
	int index = x + y * 4;
	float bayer[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return shown <= (bayer[index] + 0.5) / 16.0;
}

// Slid toward the camera along its own view ray, so it lands on the same
// pixels but tests depth as if it stood `bias` closer (see
// unit_silhouette.gdshaderinc: grass, and a foot dipping into a slope, never
// count as hiding a unit).
vec4 figure_biased_position(mat4 modelview, mat4 projection, vec3 vertex, float bias) {
	vec4 view_pos = modelview * vec4(vertex, 1.0);
	view_pos.xyz -= normalize(view_pos.xyz) * bias;
	return projection * view_pos;
}
