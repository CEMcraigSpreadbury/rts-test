// Shared light() for the terrain and the Binbun grass blades: Binbun's
// unclamped wrap lighting, plus a cool blue-green fill where the sun is
// blocked, so shade on the grass reads as soft teal pools rather than
// near-black olive. Only the ground gets it: buildings and trees keep their
// own shading.
//
// `cloud` (0..1) is how much of the sun a passing cloud blocks here. It is
// folded into the sun's own shadow -- the ground under a cloud is lit exactly
// like ground in a tree's shadow -- so where the two overlap nothing changes,
// instead of a cast shadow showing darker inside the cloud's shade.
const vec3 GROUND_SHADOW_FILL = vec3(0.1, 0.15, 0.6);

void ground_light(vec3 light_dir, vec3 normal, float attenuation, vec3 light_color, bool directional,
		float cloud, inout vec3 diffuse) {
	float ndotl = dot(light_dir, normal);
	float sun = directional ? min(attenuation, 1.0 - cloud) : attenuation;
	diffuse += ndotl * sun * light_color / PI;
	if (directional) {
		diffuse += max(ndotl, 0.0) * (1.0 - sun) * GROUND_SHADOW_FILL * light_color / PI;
	}
}
