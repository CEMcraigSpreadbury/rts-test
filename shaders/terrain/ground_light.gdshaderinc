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
// The fill takes the sun's strength but not its colour, so a warm sun leaves
// the shade cool rather than warming it to olive.
//
// The ground also takes the sun a little stronger than what stands on it: the
// sun sits low, so a flat field catches less of it than the sides of trees and
// units turned toward it, and this keeps the field bright without them glaring.
const vec3 GROUND_SHADOW_FILL = vec3(0.03, 0.11, 0.56);
const float GROUND_SUN_GAIN = 1.35;

void ground_light(vec3 light_dir, vec3 normal, float attenuation, vec3 light_color, bool directional,
		float cloud, inout vec3 diffuse) {
	float ndotl = dot(light_dir, normal);
	float sun = directional ? min(attenuation, 1.0 - cloud) : attenuation;
	vec3 light = directional ? light_color * GROUND_SUN_GAIN : light_color;
	diffuse += ndotl * sun * light / PI;
	if (directional) {
		float strength = dot(light, vec3(0.2126, 0.7152, 0.0722));
		diffuse += max(ndotl, 0.0) * (1.0 - sun) * GROUND_SHADOW_FILL * strength / PI;
	}
}
