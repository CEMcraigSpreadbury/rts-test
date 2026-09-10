shader_type spatial;
// This runs as a next_pass on the terrain's own material (see fog_of_war.gd),
// so it renders identical geometry at identical depth right after the base
// pass — a plain depth test would z-fight. It used to disable the depth test
// entirely, but then fogged terrain BEHIND a tree/building painted over it
// too, while any part poking past the terrain's silhouette (treetops against
// the sky at the map edge) stayed uncovered. Instead vertex() pulls each
// vertex a hair toward the camera along its own view ray: same screen
// position, marginally nearer depth, so it beats the terrain it sits on but
// still loses to anything genuinely in front of it.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

const float DEPTH_PULL = 0.998;

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
	vec4 view_pos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	view_pos.xyz *= DEPTH_PULL;
	POSITION = PROJECTION_MATRIX * view_pos;
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
