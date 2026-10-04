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

// The ground (terrain, grass blades, scatter) is kept out of the decal and
// shades itself with this instead, so its fog of war covers the clouds too:
// a cool shade that keeps about half the light. Multiplies linear albedo; the
// texture's alpha peaks at CloudShadows.strength (0.8), which this is sized for.
const vec3 CLOUD_GROUND_MUL = vec3(0.12, 0.26, 0.7);

// `jitter` (0..1 noise at grass-tuft scale) breaks the shadow's edge into a
// crisp serrated line, as painted shade falls across grass, rather than a soft
// airbrushed gradient.
// How much cloud shade falls here, 0..0.8, with that serrated edge.
float cloud_ground_amount(vec3 world_pos, float jitter) {
	float shade = (1.0 - cloud_shade(world_pos)) / 0.8;
	return smoothstep(0.42, 0.58, shade + (jitter - 0.5) * 0.35) * 0.8;
}

// How much of the sun a cloud blocks on the ground, 0..1, for ground_light().
// A little light gets through even the thickest cloud.
float cloud_sun_block(vec3 world_pos, float jitter) {
	return cloud_ground_amount(world_pos, jitter) / 0.8 * 0.9;
}

vec3 cloud_ground(vec3 world_pos) {
	return mix(vec3(1.0), CLOUD_GROUND_MUL, 1.0 - cloud_shade(world_pos));
}
