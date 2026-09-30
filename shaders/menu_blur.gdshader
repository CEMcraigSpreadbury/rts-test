shader_type canvas_item;
// A wide gaussian over the menu backdrop's small render (see MenuBackdrop).
// Run at that render's own low resolution, so a big kernel stays cheap; the
// result is then stretched to the screen, which smooths it further.

uniform sampler2D scene : filter_linear, repeat_disable;
// In texels of the small render.
uniform float sigma = 1.6;
// Multiplies the colour, so the menu reads over it: `shade_left` at the
// screen's left edge, where the menu sits, rising to `brightness` by `shade_reach`.
uniform float brightness = 0.72;
uniform float shade_left = 0.38;
uniform float shade_reach = 0.55;

const int RADIUS = 8;

void fragment() {
	vec2 texel = 1.0 / vec2(textureSize(scene, 0));
	vec3 sum = vec3(0.0);
	float weight_sum = 0.0;
	// Step two texels at a time, sampling between pairs, so the bilinear
	// filter does half the taps' work.
	for (int y = -RADIUS; y <= RADIUS; y += 2) {
		for (int x = -RADIUS; x <= RADIUS; x += 2) {
			vec2 offset = vec2(float(x) + 0.5, float(y) + 0.5);
			float w = exp(-dot(offset, offset) / (2.0 * sigma * sigma));
			sum += texture(scene, UV + offset * texel).rgb * w;
			weight_sum += w;
		}
	}
	float shade = mix(shade_left, brightness, smoothstep(0.0, shade_reach, UV.x));
	COLOR = vec4(sum / weight_sum * shade, 1.0);
}
