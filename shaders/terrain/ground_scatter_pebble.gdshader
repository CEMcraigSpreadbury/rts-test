shader_type spatial;
// Scattered pebbles: shaded like the rocks but too small to carry an outline.
render_mode cull_back;

#include "res://shaders/terrain/ground_scatter.gdshaderinc"

void vertex() {
	scatter_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	scatter_tint = INSTANCE_CUSTOM.rgb;
	if (!scatter_visible(MODEL_MATRIX[3].xyz, INSTANCE_CUSTOM.a)) {
		VERTEX = vec3(0.0);
	}
}

void fragment() {
	ALBEDO = scatter_albedo(COLOR.rgb, SPECULAR);
	ROUGHNESS = 1.0;
}
