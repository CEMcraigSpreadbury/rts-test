shader_type spatial;
// Every tree in a Forest chunk, drawn from one MultiMesh: the same upright
// billboard, sheet region, size and sink that TreeBillboard gave each tree as
// its own Sprite3D. The mesh is a unit quad (x -0.5..0.5, y 0..1); each
// instance's INSTANCE_CUSTOM is its sheet region in UVs (x, y, w, h), with a
// negative w meaning flipped. The instance transform only places and scales
// it, so a zero basis hides it (fog, felled) and a squashed one squashes it.
render_mode cull_disabled, depth_prepass_alpha;

uniform sampler2D sheet : source_color, filter_linear_mipmap;
// World metres per sheet pixel (TreeBillboard.PIXEL_SIZE).
uniform float pixel_size = 0.016;
// How far the trunk's bottom edge sits into the ground (TreeBillboard.SINK).
uniform float sink = 0.15;

varying vec2 region_uv;

void vertex() {
	vec4 region = INSTANCE_CUSTOM;
	vec2 sheet_size = vec2(textureSize(sheet, 0));
	vec2 size = abs(region.zw) * sheet_size * pixel_size;
	VERTEX.x *= size.x;
	VERTEX.y = VERTEX.y * size.y - sink;
	vec2 uv = UV;
	if (region.z < 0.0) {
		uv.x = 1.0 - uv.x;
	}
	region_uv = region.xy + uv * abs(region.zw);
	// Upright billboard, as BaseMaterial3D's BILLBOARD_FIXED_Y builds it, and
	// against the main camera so shadows face the same way the trees do.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			vec4(normalize(cross(vec3(0.0, 1.0, 0.0), MAIN_CAM_INV_VIEW_MATRIX[2].xyz)), 0.0),
			vec4(0.0, 1.0, 0.0, 0.0),
			vec4(normalize(cross(MAIN_CAM_INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0),
			MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
			vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec4 texel = texture(sheet, region_uv);
	ALBEDO = texel.rgb;
	ALPHA = texel.a;
}
