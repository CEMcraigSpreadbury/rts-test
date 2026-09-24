shader_type spatial;
// The unit sprite itself, batched (see unit_batch.gdshaderinc): lit, cut out
// at the sheet's alpha with an alpha scissor, as AnimatedSprite3D's alpha_cut
// is — which keeps it in the opaque pipeline, so it casts and takes shadows
// (writing a plain ALPHA would make it transparent, and a crowd would stop
// shading itself).
render_mode cull_disabled;

#include "res://shaders/unit_batch.gdshaderinc"

varying vec4 v_modulate;

void vertex() {
	batch_billboard(MODELVIEW_MATRIX, MODEL_MATRIX, VIEW_MATRIX, MAIN_CAM_INV_VIEW_MATRIX);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	v_custom = INSTANCE_CUSTOM;
	v_modulate = COLOR;
	UV = batch_uv(UV, INSTANCE_CUSTOM);
}

void fragment() {
	vec4 texel = texture(sprite_sheet, UV);
	ALBEDO = texel.rgb * v_modulate.rgb;
	ALPHA = texel.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	NORMAL = vec3(0.0, 0.0, 1.0);
}
