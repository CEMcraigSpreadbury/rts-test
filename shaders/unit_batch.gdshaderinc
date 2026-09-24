// Shared by the unit batch shaders (unit_batch_*.gdshader): every unit sprite
// of one sheet drawn as a single MultiMesh (SpriteBatcher, native/src). What
// varies per unit arrives per instance:
//   transform        world position of the sprite, its quad size as the scale
//   COLOR            the sprite's modulate (team tint, hit flash, fades)
//   INSTANCE_CUSTOM  .x atlas column, .y atlas row, .z 1 when flipped,
//                    .w team colour packed as 0xRRGGBB, or -1 for no
//                    silhouette/lift (a corpse)

uniform sampler2D sprite_sheet : source_color, filter_nearest;
// One cell of the sheet, as a fraction of the whole sheet.
uniform vec2 cell_uv = vec2(0.125, 0.125);

varying flat vec4 v_custom;

// Full billboard keeping the instance's scale, as SpriteBase3D's own material.
// `main_cam_inv_view` must be MAIN_CAM_INV_VIEW_MATRIX, not INV_VIEW_MATRIX:
// in a shadow pass the view is the light's, and a quad turned to face the
// light casts a differently-angled shadow back onto its own camera-facing
// self — dark stripes across every sprite, plain once zoomed in.
void batch_billboard(inout mat4 modelview, mat4 model, mat4 view, mat4 main_cam_inv_view) {
	modelview = view * mat4(main_cam_inv_view[0], main_cam_inv_view[1], main_cam_inv_view[2], model[3]);
	modelview = modelview * mat4(
			vec4(length(model[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(model[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, 1.0, 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
}

// The quad's UV moved onto this instance's cell, mirrored when flipped.
vec2 batch_uv(vec2 uv, vec4 custom) {
	if (custom.z > 0.5) {
		uv.x = 1.0 - uv.x;
	}
	// A hair inside the cell, so nearest filtering never bleeds a neighbour.
	uv = clamp(uv, vec2(0.001), vec2(0.999));
	return (custom.xy + uv) * cell_uv;
}

vec3 batch_team_colour(float packed) {
	float p = max(packed, 0.0);
	return vec3(floor(p / 65536.0), mod(floor(p / 256.0), 256.0), mod(p, 256.0)) / 255.0;
}

bool batch_texel_is_empty(vec2 uv) {
	return texture(sprite_sheet, uv).a < 0.5;
}
