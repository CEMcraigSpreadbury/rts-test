// Shared by the shaders that draw "shaded" GLB exports — lighting baked into
// an emission texture with albedo left black. Emission ignores lights
// entirely, so on its own a cloud or building shadow passes straight over
// them. Call from light() as
//   DIFFUSE_LIGHT -= baked_sun_shadow(NORMAL, LIGHT, ATTENUATION, LIGHT_IS_DIRECTIONAL, strength);
// with ALBEDO set to the baked color and AO = 0.0 in fragment(): the
// subtraction then takes that fraction of the baked color away under a
// shadow, ambient light adds nothing on top, and out of shadow the result is
// exactly the baked emission.
//
// Only faces turned toward the sun lose light — faces turned away already
// carry their baked shading. The fill light casts no shadows (ATTENUATION
// stays 1.0) and non-directional lights are skipped, so neither adds anything.
vec3 baked_sun_shadow(vec3 normal, vec3 light, float attenuation, bool is_directional, float strength) {
	if (!is_directional) {
		return vec3(0.0);
	}
	float facing = smoothstep(0.0, 0.25, dot(normal, light));
	return vec3((1.0 - attenuation) * strength * facing);
}
