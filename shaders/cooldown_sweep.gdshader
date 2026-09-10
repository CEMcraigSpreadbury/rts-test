shader_type canvas_item;

// Clock-style cooldown overlay for a command-card button. The shaded part is
// what's still cooling down; the clear wedge grows clockwise from 12 o'clock
// until it fills the button and the ability is ready.

uniform float remaining : hint_range(0.0, 1.0) = 0.0;
uniform vec4 shade_color : source_color = vec4(0.0, 0.0, 0.0, 0.65);
uniform vec4 edge_color : source_color = vec4(1.0, 0.85, 0.4, 0.9);
// Width of the bright leading edge, as a fraction of a full turn.
uniform float edge_width = 0.012;

void fragment() {
	vec2 d = UV - vec2(0.5);
	// 0 at 12 o'clock, increasing clockwise on screen (UV y points down).
	float turn = fract(atan(d.x, -d.y) / TAU + 1.0);
	float cleared = 1.0 - remaining;
	if (turn < cleared) {
		COLOR = vec4(0.0);
	} else if (turn < cleared + edge_width) {
		COLOR = edge_color;
	} else {
		COLOR = shade_color;
	}
}
