// Dirt stamped around finished buildings at runtime (scripts/ground_stamps.gd).
global uniform sampler2D ground_stamp_tex;
global uniform vec4 ground_stamp_rect;

float ground_stamp(vec2 world_xz) {
	if (ground_stamp_rect.z <= 0.0) {
		return 0.0;
	}
	vec2 uv = (world_xz - ground_stamp_rect.xy) / ground_stamp_rect.zw;
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) {
		return 0.0;
	}
	return texture(ground_stamp_tex, uv).r;
}
