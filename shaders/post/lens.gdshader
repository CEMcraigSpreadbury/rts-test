shader_type canvas_item;
// The lens over the finished, tonemapped 3D frame, drawn just under the HUD by
// LensPass: a blur that creeps in from the edges and corners, the way a
// tilt-shift diorama photo softens there (the depth of field blurs the top and
// bottom by depth; this rounds the sharp band off at its ends), a vignette, a
// split tone that warms the light and cools the shade, and a soft warm-grey
// haze over the top of the frame, where the ground is furthest off. The HUD
// sits on a higher canvas layer, so none of this touches it.
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
// Blur radius in pixels (at 1080 lines tall) in the very corners. 0 turns the
// corner blur off (the Depth of Field option does).
uniform float corner_blur = 6.0;
// Where the corner blur and the vignette start, from 0 at the centre of the
// screen to 1 in the corners (the middle of each edge is at 0.71).
uniform float blur_start = 0.4;
uniform float vignette_start = 0.35;
// How much the vignette darkens the very corners.
uniform float vignette_strength = 0.5;
// The split tone: multipliers for the darkest and the brightest colours,
// blended across the middle tones. Multiplied, not added, so black stays
// black and unexplored ground never lifts.
uniform vec3 shade_tint = vec3(0.92, 0.98, 1.1);
uniform vec3 light_tint = vec3(1.05, 1.0, 0.94);
// The far ground: how far down the screen the haze reaches (share of its
// height), how strong it is at the top edge, and its tint. It greys what is
// there toward a soft warm grey; scaled from the colour itself, so black
// stays black.
uniform float haze_reach = 0.4;
uniform float haze_strength = 0.6;
uniform vec3 haze_tint = vec3(1.04, 0.96, 0.85);

// Golden-angle spiral: even coverage of the disc with few taps, each read
// from a mip level about as wide as the gap between taps so the disc is
// smooth rather than a ring of ghosts.
const int TAPS = 12;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 centred = (uv - 0.5) * 2.0;
	// Corners at 1 whatever the aspect, so the falloff hugs the frame.
	float r = length(centred) * 0.70710678;
	vec3 colour = textureLod(screen_tex, uv, 0.0).rgb;

	float blur = smoothstep(blur_start, 1.0, r) * corner_blur;
	if (blur > 0.25) {
		float scale = (1.0 / SCREEN_PIXEL_SIZE.y) / 1080.0;
		vec2 radius = blur * scale * SCREEN_PIXEL_SIZE;
		float lod = max(log2(blur * scale * 0.5), 0.0);
		vec3 sum = colour;
		float total = 1.0;
		for (int i = 0; i < TAPS; i++) {
			float t = (float(i) + 0.5) / float(TAPS);
			float angle = float(i) * 2.39996323;
			vec2 offset = vec2(cos(angle), sin(angle)) * sqrt(t);
			// Gaussian-ish weight across the disc.
			float weight = exp(-2.0 * t);
			sum += textureLod(screen_tex, uv + offset * radius, lod).rgb * weight;
			total += weight;
		}
		colour = sum / total;
	}

	float lum = dot(colour, vec3(0.2126, 0.7152, 0.0722));
	colour *= mix(shade_tint, light_tint, smoothstep(0.1, 0.75, lum));

	float haze = haze_strength * smoothstep(haze_reach, 0.0, uv.y);
	if (haze > 0.0) {
		vec3 hazed = mix(colour, vec3(lum), 0.5) * haze_tint;
		colour = mix(colour, hazed, haze);
	}

	float v = clamp((r - vignette_start) / (1.0 - vignette_start), 0.0, 1.0);
	colour *= 1.0 - vignette_strength * v * v * (3.0 - 2.0 * v);
	COLOR = vec4(colour, 1.0);
}
