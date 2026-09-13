shader_type spatial;
// Ambient dust motes (ForestDust in map_base.tscn). Fog of war is a next_pass
// on the terrain only, so it never covered these floating motes — they showed
// against the dark fog but vanished on the bright visible ground. Instead
// fog_of_war.gd wires its live vision sources in here (same fog_ uniforms as
// grass_wind.gdshader) and motes only appear inside the local player's
// current vision. fog_enabled stays off in the editor so they still preview.
render_mode unshaded, blend_mix, depth_draw_never, shadows_disabled;

uniform vec4 dust_color : source_color = vec4(1.0, 0.97, 0.86, 0.9);
uniform float twinkle_speed = 1.6;

const int FOG_MAX_VISION_SOURCES = 64;
uniform bool fog_enabled = false;
uniform vec2 fog_vision_positions[FOG_MAX_VISION_SOURCES];
uniform float fog_vision_radii[FOG_MAX_VISION_SOURCES];
uniform int fog_vision_count;

varying vec3 mote_pos;
varying float twinkle;

void vertex() {
	mote_pos = MODEL_MATRIX[3].xyz;
	float phase = fract(sin(float(INSTANCE_ID) * 12.9898) * 43758.5453) * 6.2831;
	twinkle = 0.6 + 0.4 * sin(TIME * twinkle_speed + phase);
}

void fragment() {
	float vis = 1.0;
	if (fog_enabled) {
		vis = 0.0;
		for (int i = 0; i < fog_vision_count; i++) {
			float d = distance(mote_pos.xz, fog_vision_positions[i]);
			float r = fog_vision_radii[i];
			vis = max(vis, 1.0 - smoothstep(r * 0.85, r, d));
		}
	}
	// Soft rim so each mote reads as a glowing dot rather than a hard ball.
	float edge = smoothstep(0.0, 0.6, clamp(dot(NORMAL, VIEW), 0.0, 1.0));
	ALBEDO = dust_color.rgb;
	ALPHA = dust_color.a * twinkle * edge * vis;
}
