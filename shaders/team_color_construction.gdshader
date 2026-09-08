shader_type spatial;
// The team_color.gdshader look, but alpha-blended for a building that is
// still under construction (see ProductionBuilding._apply_construction_transparency).
// Kept as a separate shader rather than an alpha uniform on that one so a
// finished building still renders in the opaque pass, where it sorts against
// the world correctly and costs nothing extra.
render_mode cull_disabled, blend_mix, depth_draw_opaque;

#include "res://shaders/team_color.gdshaderinc"

uniform float construction_alpha : hint_range(0.0, 1.0) = 0.45;

void fragment() {
	vec4 texel = texture(source_texture, UV);
	vec3 albedo;
	vec3 emission;
	write_team_colored_surface(texel, albedo, emission);
	ALBEDO = albedo;
	EMISSION = emission;
	METALLIC = metallic_value;
	ROUGHNESS = roughness_value;
	ALPHA = texel.a * construction_alpha;
}
