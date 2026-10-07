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
	float ao;
	write_team_colored_surface(texel, albedo, emission, ao);
	ALBEDO = albedo;
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// A little grime toward the foot of the walls.
	float foot = mix(0.82, 1.0, smoothstep(0.0, 0.9, world.y - MODEL_MATRIX[3].y));
	ALBEDO *= foot;
	EMISSION = emission * foot * cloud_shade(world);
	AO = ao;
	METALLIC = metallic_value;
	ROUGHNESS = 0.8;
	ALPHA = texel.a * construction_alpha;
}
