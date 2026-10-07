// The moulded-plastic finish every model shares, for the shaders whose own
// light() replaces Godot's (buildings, baked props), so they shine the way the
// trees and figures do under Godot's lighting: a GGX highlight at
// PLASTIC_ROUGHNESS plus a thin clear coat, both as Godot computes them.
// Call from light() as
//   SPECULAR_LIGHT += plastic_specular(NORMAL, LIGHT, VIEW, LIGHT_COLOR, ATTENUATION, SPECULAR_AMOUNT);
// and in fragment() set ROUGHNESS, SPECULAR, CLEARCOAT and CLEARCOAT_ROUGHNESS
// to the constants below, so the sky's reflections match too.
// Tighter and glossier than the trees' (tree_wind_lit.gdshader) on purpose:
// pale plaster and stone need a sharper glint to read as plastic beside dark
// green scallops, and their blocks' rounded edges are smaller than a scallop.
const float PLASTIC_ROUGHNESS = 0.35;
const float PLASTIC_SPECULAR = 0.5;
const float PLASTIC_CLEARCOAT = 0.45;
const float PLASTIC_CLEARCOAT_ROUGHNESS = 0.3;

float plastic_ggx(float n_dot_h, float alpha) {
	float a2 = alpha * alpha;
	float d = n_dot_h * n_dot_h * (a2 - 1.0) + 1.0;
	return a2 / (PI * d * d);
}

vec3 plastic_specular(vec3 normal, vec3 light, vec3 view, vec3 light_color, float attenuation, float specular_amount) {
	float n_dot_l = dot(normal, light);
	if (n_dot_l <= 0.0) {
		return vec3(0.0);
	}
	vec3 h = normalize(light + view);
	float n_dot_h = max(dot(normal, h), 0.0);
	float n_dot_v = max(dot(normal, view), 1e-4);
	float l_dot_h = max(dot(light, h), 1e-4);
	float fresnel = pow(1.0 - l_dot_h, 5.0);
	// Base layer: GGX with a Smith visibility term, F0 from SPECULAR as Godot has it.
	float alpha = PLASTIC_ROUGHNESS * PLASTIC_ROUGHNESS;
	float k = alpha * 0.5;
	float vis = 0.25 / ((n_dot_l * (1.0 - k) + k) * (n_dot_v * (1.0 - k) + k));
	float f0 = 0.16 * PLASTIC_SPECULAR * PLASTIC_SPECULAR;
	float spec = plastic_ggx(n_dot_h, alpha) * vis * (f0 + (1.0 - f0) * fresnel);
	// Clear coat, as Godot's: a tighter lobe with its own fixed 0.04 F0.
	float coat_alpha = mix(0.001, 0.1, PLASTIC_CLEARCOAT_ROUGHNESS);
	spec += PLASTIC_CLEARCOAT * plastic_ggx(n_dot_h, coat_alpha) * (0.25 / (l_dot_h * l_dot_h))
			* (0.04 + 0.96 * fresnel);
	// LIGHT_COLOR carries a factor of PI for physically based models.
	return light_color / PI * attenuation * specular_amount * spec * n_dot_l;
}
