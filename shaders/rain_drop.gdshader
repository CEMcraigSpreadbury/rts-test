shader_type spatial;
// Rain streaks (see weather.gd). The quad is kept along the drop's own fall
// direction — its Y axis, which the process material's Align Y points down the
// velocity — and spun about that axis to face the camera. Godot's built-in
// fixed-Y billboard can't do this: it forces world up, so slanted rain still
// drew perfectly upright.
render_mode unshaded, blend_mix, depth_draw_never, shadows_disabled, cull_disabled, fog_disabled;

uniform vec4 drop_color : source_color = vec4(0.78, 0.84, 0.92, 0.35);

void vertex() {
	vec3 axis = normalize(MODEL_MATRIX[1].xyz);
	vec3 to_camera = normalize(INV_VIEW_MATRIX[3].xyz - MODEL_MATRIX[3].xyz);
	vec3 right = cross(axis, to_camera);
	// Looking straight down a drop leaves no unique facing; any perpendicular
	// will do, and the streak is edge-on and invisible either way.
	right = length(right) > 0.0001 ? normalize(right) : normalize(cross(axis, INV_VIEW_MATRIX[0].xyz));
	vec3 forward = cross(right, axis);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			vec4(right * length(MODEL_MATRIX[0].xyz), 0.0),
			vec4(axis * length(MODEL_MATRIX[1].xyz), 0.0),
			vec4(forward, 0.0),
			MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	ALBEDO = drop_color.rgb;
	// Local +Y is the leading end, so the streak is brightest where the drop
	// is heading and fades out along its tail.
	ALPHA = drop_color.a * (1.0 - UV.y);
}
