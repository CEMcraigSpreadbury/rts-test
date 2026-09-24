shader_type spatial;
// Batched copy of unit_silhouette_mask.gdshader (see unit_batch.gdshaderinc).
// Pass 1 of the unit silhouette: draws nothing visible, just stamps the
// stencil wherever a unit can actually be seen. The silhouette pass (render
// priority after this one) skips those pixels, so a unit standing behind
// another unit doesn't paint its outline over the one in front — only
// buildings, trees and terrain reveal it.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, blend_mix;
stencil_mode write, compare_always, 1;

#include "res://shaders/unit_batch.gdshaderinc"

// Slid toward the camera along its own view ray, so it lands on the same
// pixels but tests depth as if it stood occlusion_bias closer (see
// unit_silhouette.gdshaderinc).
uniform float occlusion_bias = 0.9;

void vertex() {
	batch_billboard(MODELVIEW_MATRIX, MODEL_MATRIX, VIEW_MATRIX, MAIN_CAM_INV_VIEW_MATRIX);
	vec4 view_pos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	view_pos.xyz -= normalize(view_pos.xyz) * occlusion_bias;
	POSITION = PROJECTION_MATRIX * view_pos;
	v_custom = INSTANCE_CUSTOM;
	UV = batch_uv(UV, INSTANCE_CUSTOM);
}

void fragment() {
	if ((v_custom.w < 0.0 || batch_texel_is_empty(UV))) {
		discard;
	}
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
}
