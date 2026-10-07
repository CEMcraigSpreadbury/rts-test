shader_type spatial;
// The figure copy of unit_batch_silhouette.gdshader. Pass 2 of a figure's
// see-through-buildings silhouette: a flat team-coloured copy of the figure
// that only draws where something is in front of it (depth_test_inverted),
// and not where the mask pass found a unit visible. It writes the stencil
// itself as it draws, so where a figure's own parts overlap behind a wall
// the colour goes down once, not stacked darker.
render_mode unshaded, depth_draw_never, depth_test_inverted, shadows_disabled, fog_disabled, blend_mix;
stencil_mode read, write, compare_not_equal, 1;

#include "res://shaders/unit_figure.gdshaderinc"

uniform float occlusion_bias = 0.9;
uniform float silhouette_alpha = 0.55;

varying flat vec4 v_custom;

void vertex() {
	POSITION = figure_biased_position(MODELVIEW_MATRIX, PROJECTION_MATRIX, VERTEX, occlusion_bias);
	v_custom = INSTANCE_CUSTOM;
}

void fragment() {
	if (v_custom.w < 0.0) {
		discard;
	}
	ALBEDO = figure_unpack_rgb(v_custom.x);
	ALPHA = silhouette_alpha;
}
