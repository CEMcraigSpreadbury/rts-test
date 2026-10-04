shader_type spatial;
// cull_disabled matches the doubleSided flag every building GLB ships with.
render_mode cull_disabled;
// Marks it for the ink outline (OutlinePass, shaders/post/outline.gdshader).
stencil_mode write, compare_always, 2;

#include "res://shaders/team_color.gdshaderinc"
#include "res://shaders/util/outline_mark.gdshaderinc"

varying flat float v_outline_roughness;

void vertex() {
	v_outline_roughness = outline_roughness_for(MODEL_MATRIX[3].xyz, float(INSTANCE_ID));
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
	ALBEDO *= foot;
	EMISSION = emission * foot * cloud_shade(world);
	AO = ao;
	METALLIC = metallic_value;
	ROUGHNESS = v_outline_roughness;
}
