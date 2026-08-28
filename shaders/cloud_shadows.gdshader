// A large, slow-drifting noise layer meant to sit high above the map and
// cast shadows through the scene's DirectionalLight3D — the shadow shape is
// the actual point of this material, not how it looks directly. Combined
// with Environment.volumetric_fog_enabled (already set up on WorldEnvironment
// in main.tscn), gaps between clouds should read as visible light shafts
// through the fog, the same way real god-rays form under a broken cloud deck.
//
// Godot's shadow maps are a binary depth test, not a soft blend — a plain
// alpha-blended cloud texture would still cast one solid rectangular shadow
// for the whole mesh regardless of its ALPHA. ALPHA_SCISSOR_THRESHOLD below
// is what actually punches cloud-shaped holes in the shadow (same mechanism
// as StandardMaterial3D's "Alpha Scissor" transparency mode): Godot discards
// any fragment whose ALPHA falls under it, for both the color and shadow
// passes, so only the discarded (see-through) fragments let light/shafts
// through underneath.

shader_type spatial;
render_mode unshaded, cull_disabled;

// World-space tiling: smaller = larger cloud shapes.
uniform float noise_scale = 0.015;
uniform float detail_scale = 0.05;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.35;
// World units/second the noise field drifts by, along world X/Z.
uniform vec2 scroll_speed = vec2(0.4, 0.15);
// Compared directly against the noise value (not a blend amount): higher
// means more of the sky reads as cloud, so more shadow/less light gets
// through to the ground.
uniform float coverage : hint_range(0.0, 1.0) = 0.55;
uniform vec3 cloud_color : source_color = vec3(0.9, 0.92, 0.95);
// How visible the clouds are if the camera looks up at them directly —
// independent of coverage, which only controls the shadow-casting cutoff.
uniform float visible_opacity : hint_range(0.0, 1.0) = 0.6;

float random(vec2 uv) {
	return fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453123);
}

float value_noise(vec2 uv) {
	vec2 i = floor(uv);
	vec2 f = fract(uv);
	float a = random(i);
	float b = random(i + vec2(1.0, 0.0));
	float c = random(i + vec2(0.0, 1.0));
	float d = random(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Sampled by world-space XZ (like fog_of_war.gdshader) rather than mesh
	// UVs, so cloud shapes drift smoothly across world space regardless of
	// how the plane mesh's own UVs are laid out.
	vec2 base_uv = world_pos.xz * noise_scale + TIME * scroll_speed;
	vec2 detail_uv = world_pos.xz * detail_scale + TIME * scroll_speed * 1.7;
	float density = mix(value_noise(base_uv), value_noise(detail_uv), detail_strength);

	// ALPHA_SCISSOR_THRESHOLD (not a manual `discard`) is what actually gets
	// this material proper per-pixel shadow casting from Godot — a plain
	// blended-transparency material (which a bare `discard` still counts as)
	// is excluded from the shadow pass entirely, casting no shadow at all
	// rather than a cloud-shaped one.
	//
	// The comparison Godot performs is `ALPHA < ALPHA_SCISSOR_THRESHOLD`,
	// which is invariant to scaling both sides by the same factor — so
	// multiplying both by visible_opacity keeps the actual cutoff at
	// `density < coverage` (shadow shape stays independent of how visible
	// the clouds look directly) while still letting ALPHA reflect
	// visible_opacity for the color pass. Only breaks down at
	// visible_opacity == 0 exactly (0 < 0 is false, so nothing would be
	// discarded) — nudged away from that with max().
	float safe_opacity = max(visible_opacity, 0.001);
	ALBEDO = cloud_color;
	ALPHA = density * safe_opacity;
	ALPHA_SCISSOR_THRESHOLD = coverage * safe_opacity;
}
