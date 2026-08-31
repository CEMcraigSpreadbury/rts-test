shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

// Clockwise pie-wipe fill, driven every physics tick by objective.gd from
// Objective.capture_progress / Objective.capture_duration.
uniform float fill : hint_range(0.0, 1.0) = 0.0;
uniform vec4 fill_color : source_color = vec4(0.3, 0.85, 0.35, 0.85);

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX.xz;
}

void fragment() {
	// atan2 with the axes swapped so angle 0 is +Z (matches this disc lying
	// flat, seen from above) and increases clockwise as fill grows.
	float angle = atan(local_pos.x, local_pos.y);
	if (angle < 0.0) {
		angle += TAU;
	}
	if (angle > fill * TAU) {
		discard;
	}
	ALBEDO = fill_color.rgb;
	ALPHA = fill_color.a;
}
