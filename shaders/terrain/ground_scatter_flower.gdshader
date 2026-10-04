shader_type spatial;
// Scattered daisies: drawn flat-on to the camera, so a white five-petalled
// flower with a yellow eye always reads as one rather than as a sliver seen
// edge-on. The mesh is built upright, facing +z (GroundScatter._flower_mesh).
render_mode cull_disabled;

#include "res://shaders/terrain/ground_scatter.gdshaderinc"

void vertex() {
	scatter_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	scatter_tint = INSTANCE_CUSTOM.rgb;
	if (!scatter_visible(MODEL_MATRIX[3].xyz, INSTANCE_CUSTOM.a)) {
		VERTEX = vec3(0.0);
	} else {
		float scale = length(MODEL_MATRIX[0].xyz);
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * scale, INV_VIEW_MATRIX[1] * scale,
				INV_VIEW_MATRIX[2] * scale, MODEL_MATRIX[3]);
	}
}

void fragment() {
	ALBEDO = scatter_albedo(COLOR.rgb, SPECULAR);
	ROUGHNESS = 1.0;
	NORMAL = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
}
