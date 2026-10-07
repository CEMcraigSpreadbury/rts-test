shader_type spatial;
// The figure copy of unit_batch_mask.gdshader. Pass 1 of a figure's
// see-through-buildings silhouette: draws nothing visible, just stamps the
// stencil wherever a unit can actually be seen. The silhouette pass (render
// priority after this one) skips those pixels, so a unit behind another unit
// doesn't paint its outline over the one in front: only buildings, trees and
// terrain reveal it.
render_mode unshaded, depth_draw_never, shadows_disabled, fog_disabled, blend_mix;
stencil_mode write, compare_always, 1;

#include "res://shaders/unit_figure.gdshaderinc"

uniform float occlusion_bias = 0.9;

varying flat vec4 v_custom;

void vertex() {
	POSITION = figure_biased_position(MODELVIEW_MATRIX, PROJECTION_MATRIX, VERTEX, occlusion_bias);
	v_custom = INSTANCE_CUSTOM;
}

void fragment() {
	if (v_custom.w < 0.0) {
		discard;
	}
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
}
