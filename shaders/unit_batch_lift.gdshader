shader_type spatial;
// Batched copy of unit_night_lift.gdshader (see unit_batch.gdshaderinc).
// Pass 1 of the unit overlay chain (see unit_silhouette_material.gd): adds a
// little cool light back onto the unit's own pixels once night falls, so the
// sprites stay readable against dark ground without a real light per unit.
//
// Additive and shaped by the sheet's alpha, so it lifts the unit and nothing
// around it. Priced like a light that only touches one sprite: no per-unit
// CPU work at all (the strength is one global uniform DayNight writes once a
// frame), and the whole pass discards while it is day.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, blend_add;

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

// 0 while the sun is up, ramped to 1 across the fade by DayNight.
global uniform float unit_night_lift;
// Moonlight rather than white, to match what the sun turns into at night.
uniform vec4 lift_color : source_color = vec4(0.55, 0.68, 1.0, 1.0);
uniform float lift_strength = 0.4;

void fragment() {
	if (unit_night_lift <= 0.0 || (v_custom.w < 0.0 || batch_texel_is_empty(UV))) {
		discard;
	}
	// Multiplied by the texel so a unit's own colours still show through the
	// lift, instead of every sprite flattening to the same blue.
	ALBEDO = texture(sprite_sheet, UV).rgb * lift_color.rgb * lift_strength * unit_night_lift;
	ALPHA = 1.0;
}
