shader_type spatial;
// Flat ground markers (selection/hover/command/path/ping/quest rings). Grass
// writes depth (depth_prepass_alpha), so a plain depth-tested ring sitting on
// the ground gets buried under the blades. Pulling the ring toward the camera
// by grass_bias lifts it clear of the grass while buildings, trees and hills
// (much taller than that) still stand in front of it. The stencil read skips
// pixels the unit silhouette mask stamped as a visible unit, so the bias
// never paints the ring over a unit's own sprite.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, blend_mix, skip_vertex_transform;
stencil_mode read, compare_not_equal, 1;

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float grass_bias = 0.3;

void vertex() {
	VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// View space looks down -Z, so +Z is toward the camera (perspective or
	// orthographic alike).
	VERTEX.z += grass_bias;
	NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	ALBEDO = albedo_color.rgb;
	ALPHA = albedo_color.a;
}
