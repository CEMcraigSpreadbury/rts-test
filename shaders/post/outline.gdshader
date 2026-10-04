shader_type spatial;
// Ink outlines on the 3D world (buildings, trees, deposits, rocks), drawn as
// one full-screen pass by OutlinePass. Only pixels whose material wrote 2 to
// the stencil buffer are touched, so grass, terrain and the sprite units never
// get lines. Each outlined object writes its own id into roughness
// (outline_mark.gdshaderinc); a pixel is on the line where a neighbour belongs
// to something else and is not in front of it. That traces each object's
// silhouette as the camera sees it, and nothing inside it -- no roof tiles,
// no creases. The line sits on the inside edge of the nearer object.
//
// Against the ground (terrain and grass blades, roughness above 0.95) the line
// is drawn only where the object stands clear of it: where the object's pixel
// is higher in the world than the ground beside it. A roof edge against the
// field behind is lined; the foot of a wall, a trunk or a rock, where it meets
// the ground at the same height, is not.
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled, blend_mix, shadows_disabled;
stencil_mode read, compare_equal, 2;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest;
uniform vec4 line_color : source_color = vec4(0.17, 0.10, 0.06, 1.0);
// Line width in pixels at 1080 lines tall; scaled with the viewport.
uniform float thickness = 1.6;
// Two touching objects can draw the same id (1 in OUTLINE_ID_SLOTS); a big
// jump in depth still lines them.
uniform float depth_threshold = 0.08;
uniform float depth_full = 0.15;
// How far (metres) an object's pixel must rise above the ground beside it
// before the line against that ground starts, and reaches full strength.
uniform float ground_rise_start = 0.1;
uniform float ground_rise_full = 0.3;
uniform float strength = 0.95;
// Distance (view depth) the line starts thinning from, and how faint it gets
// far away.
uniform float fade_start = 30.0;
uniform float far_strength = 0.35;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

vec3 view_position(vec2 uv, mat4 inv_projection) {
	float raw = texture(depth_tex, uv).r;
	vec4 view = inv_projection * vec4(uv * 2.0 - 1.0, raw, 1.0);
	return view.xyz / view.w;
}

void fragment() {
	vec3 centre_view = view_position(SCREEN_UV, INV_PROJECTION_MATRIX);
	float centre = -centre_view.z;
	float centre_height = (INV_VIEW_MATRIX * vec4(centre_view, 1.0)).y;
	// Pulled back, objects shrink but a fixed-width line would not: the line
	// thins (to a pixel) and fades with distance, so far buildings and trees
	// aren't swamped by their own outline.
	float near_share = clamp(fade_start / max(centre, 0.001), 0.0, 1.0);
	float px = max(thickness * VIEWPORT_SIZE.y / 1080.0 * near_share, 1.0);
	vec2 step_px = vec2(px) / VIEWPORT_SIZE;
	float centre_id = texture(normal_tex, SCREEN_UV).a;
	// Something without an id drawn over an outlined object (a grass blade in
	// front of a rock) still carries the object's stencil: leave it alone.
	if (centre_id > 0.95) {
		discard;
	}
	float line = 0.0;
	vec2 offsets[8] = vec2[](vec2(1.0, 0.0), vec2(-1.0, 0.0), vec2(0.0, 1.0), vec2(0.0, -1.0),
			vec2(0.7, 0.7), vec2(-0.7, 0.7), vec2(0.7, -0.7), vec2(-0.7, -0.7));
	for (int i = 0; i < 8; i++) {
		vec2 uv = SCREEN_UV + offsets[i] * step_px;
		vec3 view = view_position(uv, INV_PROJECTION_MATRIX);
		float d = -view.z;
		if (d <= centre - 0.05) {
			// In front of this pixel: its own outline, not ours.
			continue;
		}
		float id = texture(normal_tex, uv).a;
		if (id > 0.95) {
			// The ground (or a grass blade on it).
			float rise = centre_height - (INV_VIEW_MATRIX * vec4(view, 1.0)).y;
			line = max(line, smoothstep(ground_rise_start, ground_rise_full, rise));
			continue;
		}
		if (abs(id - centre_id) > 0.5 / 255.0) {
			line = 1.0;
		}
		line = max(line, smoothstep(depth_threshold, depth_full, (d - centre) / centre));
	}
	ALBEDO = line_color.rgb;
	ALPHA = line * strength * mix(far_strength, 1.0, near_share);
}
