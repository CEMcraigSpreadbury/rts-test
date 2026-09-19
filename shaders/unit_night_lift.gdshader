shader_type spatial;
// Pass 1 of the unit overlay chain (see unit_silhouette_material.gd): adds a
// little cool light back onto the unit's own pixels once night falls, so the
// sprites stay readable against dark ground without a real light per unit.
//
// Additive and shaped by the sheet's alpha, so it lifts the unit and nothing
// around it. Priced like a light that only touches one sprite: no per-unit
// CPU work at all (the strength is one global uniform DayNight writes once a
// frame), and the whole pass discards while it is day.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, blend_add;

#include "res://shaders/unit_silhouette.gdshaderinc"

// 0 while the sun is up, ramped to 1 across the fade by DayNight.
global uniform float unit_night_lift;
// Moonlight rather than white, to match what the sun turns into at night.
uniform vec4 lift_color : source_color = vec4(0.55, 0.68, 1.0, 1.0);
uniform float lift_strength = 0.4;

void fragment() {
	if (unit_night_lift <= 0.0 || sprite_texel_is_empty(UV)) {
		discard;
	}
	// Multiplied by the texel so a unit's own colours still show through the
	// lift, instead of every sprite flattening to the same blue.
	ALBEDO = texture(sprite_sheet, UV).rgb * lift_color.rgb * lift_strength * unit_night_lift;
	ALPHA = 1.0;
}
