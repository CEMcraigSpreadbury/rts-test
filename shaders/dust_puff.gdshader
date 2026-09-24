shader_type spatial;
// One puff of a unit's walking dust (DustPool): a ring buffer of instances in
// a single MultiMesh, each written once when it is spawned and animated here
// from its age alone — the look of the unit's old per-unit emitter (see the
// WalkDust particle material in unit.tscn): drifting up and out at 0.2-0.5 m/s
// within 50 degrees of straight up, a faint lift, sizes 0.4-0.9, half a
// second of life.
//   INSTANCE_CUSTOM.x  spawn time (on the pool's clock, `now`)
//   INSTANCE_CUSTOM.yzw  three random numbers for this puff
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

instance uniform float now = 0.0;
uniform float lifetime = 0.5;
uniform vec4 dust_color : source_color = vec4(0.75, 0.68, 0.55, 0.45);

varying float v_alive;

void vertex() {
	float age = now - INSTANCE_CUSTOM.x;
	v_alive = (age >= 0.0 && age < lifetime) ? 1.0 : 0.0;
	vec3 r = INSTANCE_CUSTOM.yzw;
	// Up, tipped out by up to 50 degrees in a random direction.
	float tilt = radians(50.0) * r.x;
	float turn = 6.2831853 * r.y;
	vec3 dir = vec3(sin(tilt) * cos(turn), cos(tilt), sin(tilt) * sin(turn));
	float speed = mix(0.2, 0.5, r.z);
	vec3 drift = dir * speed * age + vec3(0.0, 0.075, 0.0) * age * age;
	float size = mix(0.4, 0.9, fract(r.x * 7.13 + r.z * 3.7));
	vec3 origin = MODEL_MATRIX[3].xyz + drift;
	// Camera-facing, at its size; a dead puff collapses to nothing.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * size * v_alive, INV_VIEW_MATRIX[1] * size * v_alive, INV_VIEW_MATRIX[2], vec4(origin, 1.0));
}

void fragment() {
	if (v_alive < 0.5) {
		discard;
	}
	ALBEDO = dust_color.rgb;
	ALPHA = dust_color.a;
}
