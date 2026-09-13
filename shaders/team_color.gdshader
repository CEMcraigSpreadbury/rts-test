shader_type spatial;
// cull_disabled matches the doubleSided flag every building GLB ships with.
render_mode cull_disabled;

#include "res://shaders/team_color.gdshaderinc"

void fragment() {
	vec4 texel = texture(source_texture, UV);
	vec3 albedo;
	vec3 emission;
	float ao;
	write_team_colored_surface(texel, albedo, emission, ao);
	ALBEDO = albedo;
	EMISSION = emission;
	AO = ao;
	METALLIC = metallic_value;
	ROUGHNESS = roughness_value;
}
