// Shared by unit_silhouette_mask.gdshader and unit_silhouette.gdshader — the
// two passes of the see-through-buildings silhouette UnitSilhouetteMaterial
// hangs on each unit's AnimatedSprite3D as its material_overlay. An overlay
// draws the sprite's own mesh (so its UVs already point at the current frame
// on the sheet), but none of the sprite's internal material, billboarding
// included — hence it being redone here.

uniform sampler2D sprite_sheet : source_color, filter_nearest;
// How far (world units along the view ray) something must be in front of the
// unit before it counts as hiding it. Grass writes depth (depth_prepass_alpha)
// and a billboard's feet dip into the terrain on a slope; both sit well inside
// this, so neither lights a unit up just for standing in a field.
uniform float occlusion_bias = 0.9;

void vertex() {
	// Same billboard (keep scale) SpriteBase3D's own material uses.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
			vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
	vec4 view_pos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	// Slid toward the camera along its own view ray, so it lands on exactly
	// the same pixels but tests depth as if it stood occlusion_bias closer.
	view_pos.xyz -= normalize(view_pos.xyz) * occlusion_bias;
	POSITION = PROJECTION_MATRIX * view_pos;
}

// Same cutoff as the sprite's own alpha_cut (discard at 0.5).
bool sprite_texel_is_empty(vec2 uv) {
	return texture(sprite_sheet, uv).a < 0.5;
}
