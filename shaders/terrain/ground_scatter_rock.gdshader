shader_type spatial;
// Scattered rocks: outlined like the buildings and trees.
render_mode cull_back;
// Marks it for the ink outline (OutlinePass, shaders/post/outline.gdshader).
stencil_mode write, compare_always, 2;

#include "res://shaders/terrain/ground_scatter.gdshaderinc"
#include "res://shaders/util/outline_mark.gdshaderinc"

varying flat float v_outline_roughness;

void vertex() {
	v_outline_roughness = outline_roughness_for(MODEL_MATRIX[3].xyz, float(INSTANCE_ID));
	scatter_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	scatter_tint = INSTANCE_CUSTOM.rgb;
	if (!scatter_visible(MODEL_MATRIX[3].xyz, INSTANCE_CUSTOM.a)) {
		VERTEX = vec3(0.0);
	}
}

void fragment() {
	ALBEDO = scatter_albedo(COLOR.rgb, SPECULAR);
	ROUGHNESS = v_outline_roughness;
}
