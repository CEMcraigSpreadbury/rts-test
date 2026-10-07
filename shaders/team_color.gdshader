shader_type spatial;
// cull_disabled matches the doubleSided flag every building GLB ships with.
render_mode cull_disabled;

#include "res://shaders/team_color.gdshaderinc"

void vertex() {
	cloud_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

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
	// Darker and glossier in the rain (wetness.gdshaderinc).
	float wet = wet_amount((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz, world);
	float shade = foot * wet_darken(wet);
	ALBEDO *= shade;
	EMISSION = emission * shade + wet_sheen(NORMAL, VIEW, wet);
	AO = ao;
	METALLIC = metallic_value;
	ROUGHNESS = wet_roughness(PLASTIC_ROUGHNESS, wet);
	SPECULAR = PLASTIC_SPECULAR;
	CLEARCOAT = wet_clearcoat(PLASTIC_CLEARCOAT, wet);
	CLEARCOAT_ROUGHNESS = wet_clearcoat_roughness(PLASTIC_CLEARCOAT_ROUGHNESS, wet);
}
