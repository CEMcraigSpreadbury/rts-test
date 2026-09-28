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
	// Modulate over 1 is a hit flash (Unit.play_hit_flash): that part washes
	// the sprite toward white and glows, so it reads in shadow and at night.
	vec3 flash = clamp(v_modulate.rgb - vec3(1.0), vec3(0.0), vec3(1.0));
	ALBEDO = mix(texel.rgb * min(v_modulate.rgb, vec3(1.0)), vec3(1.0), flash);
	EMISSION = flash * 0.9;
	ALPHA = texel.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	NORMAL = vec3(0.0, 0.0, 1.0);
}
