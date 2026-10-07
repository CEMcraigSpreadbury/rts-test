shader_type spatial;
// Scattered pebbles: shaded like the rocks but too small to carry an outline.
render_mode cull_back;

#include "res://shaders/terrain/ground_scatter.gdshaderinc"
#include "res://shaders/util/plastic_light.gdshaderinc"

void vertex() {
	scatter_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	scatter_tint = INSTANCE_CUSTOM.rgb;
	if (!scatter_visible(MODEL_MATRIX[3].xyz, INSTANCE_CUSTOM.a)) {
		VERTEX = vec3(0.0);
	}
}

void fragment() {
	// The plastic finish every model shares (plastic_light.gdshaderinc); fog
	// takes the shine away with the specular.
	float specular = PLASTIC_SPECULAR;
	ALBEDO = scatter_albedo(COLOR.rgb, specular);
	SPECULAR = specular;
	ROUGHNESS = PLASTIC_ROUGHNESS;
	CLEARCOAT = PLASTIC_CLEARCOAT * specular / PLASTIC_SPECULAR;
	CLEARCOAT_ROUGHNESS = PLASTIC_CLEARCOAT_ROUGHNESS;
}
