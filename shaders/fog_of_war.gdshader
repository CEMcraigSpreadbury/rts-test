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

// Tiles stack (e.g. dirt tiles with ragged cut-out edges lifted slightly over
// grass), and every layer gets this pass — so each fog fragment must only draw
// if its own surface is the one actually visible there, or cut-out parts of
// the upper tile get double-fogged over the lower one. That used to be done
// by re-sampling the terrain's albedo alpha here, but this pass's UVs never
// round exactly like the base pass's, so single texels along every cut-out
// edge were drawn by the base pass yet discarded here, sparkling unfogged.
// Comparing against the real depth buffer instead is exact: it holds whichever
// layer the base pass kept, and the layers are far enough apart (DIRT_LIFT)
// to tell them apart well within LAYER_EPSILON.
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
const float LAYER_EPSILON = 0.02;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec4 view_pos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	view_pos.xyz *= DEPTH_PULL;
	POSITION = PROJECTION_MATRIX * view_pos;
}

void fragment() {
	// VERTEX here is the un-pulled view-space surface position.
	float scene_depth = texture(depth_tex, SCREEN_UV).r;
	vec4 scene_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene_depth, 1.0);
	float scene_z = scene_view.z / scene_view.w;
	if (abs(VERTEX.z - scene_z) > LAYER_EPSILON) {
		discard;
	}

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
