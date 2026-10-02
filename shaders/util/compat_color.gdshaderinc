// The Compatibility renderer (the web build) hands shaders source_color
// textures and uniforms still sRGB-encoded, and decodes ALBEDO and EMISSION
// itself afterwards. Forward+ works in linear throughout. Maths that isn't a
// plain product of colours — an energy multiplier, a hue shift, a mix — comes
// out very differently between the two (an emission energy of 2 lands at ~5x
// in Compatibility). compat_in() on what a shader reads and compat_out() on
// what it writes keep that maths in linear on both; elsewhere they're no-ops.
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
vec3 compat_in(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}
vec3 compat_out(vec3 c) {
	c = max(c, vec3(0.0));
	return mix(1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, c * 12.92, lessThan(c, vec3(0.0031308)));
}
#else
#define compat_in(c) (c)
#define compat_out(c) (c)
#endif
