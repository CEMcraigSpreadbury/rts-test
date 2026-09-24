shader_type spatial;
// Batched copy of unit_silhouette.gdshader (see unit_batch.gdshaderinc); the
// team colour comes per instance instead of per material.
// Pass 2 of the unit silhouette: a flat team-colored copy of the sprite that
// only draws where something is in front of it (depth_test_inverted), and not
// where the mask pass found another unit visible.
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_inverted, shadows_disabled, fog_disabled, blend_mix;
stencil_mode read, compare_not_equal, 1;

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

uniform float silhouette_alpha = 0.55;

void fragment() {
	if ((v_custom.w < 0.0 || batch_texel_is_empty(UV))) {
		discard;
	}
	ALBEDO = batch_team_colour(v_custom.w);
	ALPHA = silhouette_alpha;
}
