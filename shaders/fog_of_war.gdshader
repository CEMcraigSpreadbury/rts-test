shader_type spatial;
// depth_test_disabled matters now that this also runs as a next_pass on the
// terrain's own material (see fog_of_war.gd/main.tscn): rendering identical
// geometry at identical depth right after the base pass makes a normal depth
// test flicker (z-fighting) since neither fragment reliably wins. This pass
// is meant to always draw on top of whatever's beneath it regardless, so
// skipping the depth test entirely avoids the comparison instead of trying
// to win it.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, depth_test_disabled;

// Sampled by world-space XZ position rather than mesh UVs, so the overlay
// always lines up with FogOfWar's grid regardless of how the plane mesh's
// own UVs are laid out.
uniform sampler2D fog_tex : source_color, filter_linear;
uniform vec2 map_origin;
uniform vec2 map_size;

// Currently-visible vision is NOT baked into fog_tex — a rasterized grid can
// never look smooth as it moves without pushing resolution absurdly high.
// Instead each of the local player's own units/buildings is passed in here
// and the reveal circle is computed analytically per-pixel, which is exact
// (no steps at any distance) and cheap regardless of grid resolution.
const int MAX_VISION_SOURCES = 32;
uniform vec2 vision_positions[MAX_VISION_SOURCES];
uniform float vision_radii[MAX_VISION_SOURCES];
uniform int vision_count;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = (world_pos.xz - map_origin) / map_size;
	vec4 fog = texture(fog_tex, uv);

	float vis = 0.0;
	for (int i = 0; i < vision_count; i++) {
		float d = distance(world_pos.xz, vision_positions[i]);
		float r = vision_radii[i];
		// Soft-feathered edge over the outer ~15% of the radius instead of a hard rim.
		vis = max(vis, 1.0 - smoothstep(r * 0.85, r, d));
	}

	ALBEDO = fog.rgb;
	ALPHA = fog.a * (1.0 - vis);
}
