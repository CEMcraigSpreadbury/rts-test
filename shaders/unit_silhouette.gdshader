shader_type spatial;
// Pass 2 of the unit silhouette: a flat team-colored copy of the sprite that
// only draws where something is in front of it (depth_test_inverted), and not
// where the mask pass found another unit visible.
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_inverted, shadows_disabled, fog_disabled, blend_mix;
stencil_mode read, compare_not_equal, 1;

#include "res://shaders/unit_silhouette.gdshaderinc"

uniform vec4 silhouette_color : source_color = vec4(1.0, 1.0, 1.0, 0.55);

void fragment() {
	if (sprite_texel_is_empty(UV)) {
		discard;
	}
	ALBEDO = silhouette_color.rgb;
	ALPHA = silhouette_color.a;
}
