// Cloud shadows for emission-baked models. The CloudShadows decal darkens
// everything lit through ALBEDO, but emission ignores albedo, so these shaders
// sample the decal's texture through globals and darken their emission by the
// same amount. The texture's alpha already carries the strength;
// cloud_shadow_strength is only the on/off and restart fade. See cloud_shadows.gd.
global uniform sampler2D cloud_shadow_tex;
global uniform vec4 cloud_shadow_rect;
global uniform float cloud_shadow_strength;

float cloud_shade(vec3 world_pos) {
	if (cloud_shadow_strength <= 0.0) {
		return 1.0;
	}
	vec2 uv = (world_pos.xz - cloud_shadow_rect.xy) / cloud_shadow_rect.zw;
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) {
		return 1.0;
	}
	return 1.0 - texture(cloud_shadow_tex, uv).a * cloud_shadow_strength;
}
