shader_type spatial;
// Pass 1 of the unit silhouette: draws nothing visible, just stamps the
// stencil wherever a unit can actually be seen. The silhouette pass (render
// priority after this one) skips those pixels, so a unit standing behind
// another unit doesn't paint its outline over the one in front — only
// buildings, trees and terrain reveal it.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, blend_mix;
stencil_mode write, compare_always, 1;

#include "res://shaders/unit_silhouette.gdshaderinc"

void fragment() {
	if (sprite_texel_is_empty(UV)) {
		discard;
	}
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
}
