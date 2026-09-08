// Recolors only the team-colored parts of a building's texture, leaving its
// wood, thatch and stone exactly as painted.
//
// Shared by team_color.gdshader (a finished building) and
// team_color_construction.gdshader (the same recolor, alpha-blended while the
// building is still going up) — only render_mode and ALPHA differ between the
// two, so all of the actual work lives here.
//
// The building models are "shaded" GLB exports: their lighting is baked into
// an emissive texture with albedo left black, so the map that actually
// carries the art is the emission one, not the albedo one. Which map to read
// (and how it reaches the surface) is passed in by team_color_material.gd
// from the material the model shipped with rather than assumed here.

uniform sampler2D source_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 base_albedo : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 emission_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform bool texture_drives_emission = true;
uniform float emission_energy : hint_range(0.0, 16.0) = 1.0;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 1.0;

uniform vec4 team_color : source_color = vec4(0.25, 0.55, 1.0, 1.0);

// Every building texture paints its team-colored parts in one tight blue
// band. Measured across all of assets/art/Models that band is hue 213-220
// deg (median 216.3 = 0.601) at saturation 0.55-0.95, and nothing else in the
// art comes near it — wood and thatch sit at 15-45 deg, stone is grey. So the
// mask is just a window around that hue, and the wood/stone the player asked
// to keep unchanged is ~170 deg away from ever entering it.
uniform float source_hue : hint_range(0.0, 1.0) = 0.601;
// The measured saturation and value of that band, used below to carry each
// texel's own shading across to the new color as a ratio.
uniform float source_saturation : hint_range(0.01, 1.0) = 0.757;
uniform float source_value : hint_range(0.01, 1.0) = 0.475;
// Half-width of the fully-masked hue window, then how far past it the mask
// fades out. 0.05 = +-18 deg, still wider than the measured spread — it keeps
// 99.79% of the true blue, and the trim off the edges is deliberate: the
// texels out there are the desaturated ones where a recolor reads as coverage
// creeping into the stonework rather than as team color.
uniform float hue_width : hint_range(0.0, 0.5) = 0.050;
uniform float hue_feather : hint_range(0.0, 0.25) = 0.03;

// How saturated the recolored result gets, against the team color's own
// saturation. Slightly under 1.0 because a fully saturated repaint flattens
// the subtler shading in the banners and painted panels.
uniform float saturation_scale : hint_range(0.0, 1.0) = 0.88;
// How much the team color's *value* rescales the texture's shading, versus
// the texture keeping its own. This has to stay low: every palette color is
// full-value, so matching value outright multiplies the whole band by
// 1/source_value (~2.1x) and pushes it off the top — measured at 49.5% of the
// blue texels landing on one flat maximum, which is exactly the roof panels
// losing their folds and seams. At 0.25 the recolor still brightens toward
// the team color without crushing the range that carries the detail.
uniform float value_match : hint_range(0.0, 1.0) = 0.25;
// Stone in ambient shadow picks up a slight blue cast that lands inside the
// hue window, and near-black crevices have no meaningful hue at all — hue
// alone would recolor both. Gating on saturation sorts it out cleanly: that
// shadowed stone tops out around 0.20 saturation while the real team blue
// starts at 0.55, so this 0.30-0.50 ramp sits in an empty gap between them.
// Measured over every texture, it keeps 99.94% of the true blue while
// letting through 0.00% of the stone.
uniform float saturation_gate_low : hint_range(0.0, 1.0) = 0.34;
uniform float saturation_gate_high : hint_range(0.0, 1.0) = 0.52;
uniform float value_gate_low : hint_range(0.0, 1.0) = 0.05;
uniform float value_gate_high : hint_range(0.0, 1.0) = 0.10;
uniform float tint_strength : hint_range(0.0, 1.0) = 1.0;

vec3 rgb_to_hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1.0e-10)), d / (q.x + 1.0e-10), q.x);
}

vec3 hsv_to_rgb(vec3 c) {
	vec4 k = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
	return c.z * mix(k.xxx, clamp(p - k.xxx, 0.0, 1.0), c.y);
}

// A source_color sampler hands back linear values, but the art was painted —
// and the hue/saturation constants above were measured — in sRGB. Converting
// back before looking at hue keeps those numbers meaningful, and matters for
// more than tidiness: linear space crushes the dark end so hard that the blue
// band's own shading spans values 0.02-0.44 there, leaving no gap to separate
// genuine shadowed blue from black crevice noise. In sRGB it spans 0.15-0.69
// and the gates below have room to work.
vec3 linear_to_srgb(vec3 c) {
	c = clamp(c, vec3(0.0), vec3(1.0));
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

vec3 srgb_to_linear(vec3 c) {
	c = clamp(c, vec3(0.0), vec3(1.0));
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

vec3 apply_team_color(vec3 linear_rgb) {
	vec3 hsv = rgb_to_hsv(linear_to_srgb(linear_rgb));

	// Hue is a circle, so the distance to the window's center has to wrap.
	float hue_distance = abs(hsv.x - source_hue);
	hue_distance = min(hue_distance, 1.0 - hue_distance);

	float mask = 1.0 - smoothstep(hue_width, hue_width + hue_feather, hue_distance);
	mask *= smoothstep(saturation_gate_low, saturation_gate_high, hsv.y);
	mask *= smoothstep(value_gate_low, value_gate_high, hsv.z);
	mask *= tint_strength;
	if (mask <= 0.0) {
		return linear_rgb;
	}

	// Swap in the team's hue, then carry the texel's own saturation and value
	// across rather than copying the team color outright — that keeps every
	// painted highlight, fold and shadow in the flags and banners intact
	// instead of flattening them to one solid shape of color.
	//
	// Saturation scales as a ratio of the source blue's, so a texel at that
	// blue's saturation comes out at the team color's (times saturation_scale)
	// and the faded ones stay proportionally faded. Value deliberately does
	// *not* do the same — see value_match above for why matching it outright
	// clips half the band flat.
	vec3 team_hsv = rgb_to_hsv(linear_to_srgb(team_color.rgb));
	float value_factor = mix(1.0, team_hsv.z / source_value, value_match);
	vec3 tinted_hsv = vec3(
		team_hsv.x,
		clamp(team_hsv.y * saturation_scale * (hsv.y / source_saturation), 0.0, 1.0),
		clamp(hsv.z * value_factor, 0.0, 1.0)
	);
	return mix(linear_rgb, srgb_to_linear(hsv_to_rgb(tinted_hsv)), mask);
}

// Writes the recolored texture out the same way the model's own material did,
// so a team-colored building is lit identically to an untinted one.
void write_team_colored_surface(vec4 texel, out vec3 albedo, out vec3 emission) {
	vec3 recolored = apply_team_color(texel.rgb);
	if (texture_drives_emission) {
		albedo = base_albedo.rgb;
		emission = recolored * emission_color.rgb * emission_energy;
	} else {
		albedo = recolored * base_albedo.rgb;
		emission = vec3(0.0);
	}
}
