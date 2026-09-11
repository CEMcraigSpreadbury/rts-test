shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

// Clockwise pie-wipe fill, driven every physics tick by objective.gd from
// Objective.flag_control, tinted to whoever's flag it is (fill_color).
uniform float fill : hint_range(0.0, 1.0) = 0.0;
uniform vec4 fill_color : source_color = vec4(0.3, 0.85, 0.35, 0.85);

void fragment() {
	// Centred on the plane via UV, so it's clipped to the inscribed circle
	// whatever size the PlaneMesh is — the mesh itself is a square.
	vec2 p = UV - vec2(0.5);
	if (length(p) > 0.5) {
		discard;
	}
	// atan2 with the axes swapped so angle 0 is +Z (matches this disc lying
	// flat, seen from above) and increases clockwise as fill grows.
	float angle = atan(p.x, p.y);
	if (angle < 0.0) {
		angle += TAU;
	}
	if (angle > fill * TAU) {
		discard;
	}
	ALBEDO = fill_color.rgb;
	ALPHA = fill_color.a;
}
