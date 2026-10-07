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

// The texture's alpha peaks at CloudShadows.strength; kept in step with it.
const float CLOUD_STRENGTH = 0.35;

// The ground (terrain, grass blades, scatter) is kept out of the decal and
// shades itself with this instead, so its fog of war covers the clouds too:
// a cool shade, mixed in by the texture's alpha. Multiplies linear albedo.
const vec3 CLOUD_GROUND_MUL = vec3(0.12, 0.26, 0.7);

// `jitter` (0..1 noise at grass-tuft scale) breaks the shadow's edge into a
// crisp serrated line, as painted shade falls across grass, rather than a soft
// airbrushed gradient.
// How much of the cloud's cover falls here, 0..1, with that serrated edge.
float cloud_ground_amount(vec3 world_pos, float jitter) {
	float cover = (1.0 - cloud_shade(world_pos)) / CLOUD_STRENGTH;
	return smoothstep(0.42, 0.58, cover + (jitter - 0.5) * 0.35);
}

// How much of the sun a cloud blocks on the ground, 0..1, for ground_light().
// Thin cloud: half the sun gets through even the thickest of it, which darkens
// the ground about as much as the decal darkens what stands on it.
const float CLOUD_SUN_BLOCK = 0.5;
float cloud_sun_block(vec3 world_pos, float jitter) {
	return cloud_ground_amount(world_pos, jitter) * CLOUD_SUN_BLOCK;
}

vec3 cloud_ground(vec3 world_pos) {
	return mix(vec3(1.0), CLOUD_GROUND_MUL, 1.0 - cloud_shade(world_pos));
}

// What stands on the ground loses the sun under a cloud too, the same shape
// with a plain soft edge. More of it than the ground, which keeps a cool fill
// in its shade (ground_light.gdshaderinc) that models don't get.
const float CLOUD_MODEL_BLOCK = 0.9;
float cloud_model_block(vec3 world_pos) {
	return cloud_ground_amount(world_pos, 0.5) * CLOUD_MODEL_BLOCK;
}

// Toward the sun, in world space (CloudShadows writes it from the sun).
global uniform vec3 cloud_sun_dir;

// For a light() of its own: what's left of this light's ATTENUATION-style
// strength under a cloud. Only the sun is clouded; the fill light (also
// directional, shadowless) passes untouched.
float cloud_light(vec3 world_pos, vec3 view_light, mat4 inv_view, bool directional) {
	if (!directional || dot((inv_view * vec4(view_light, 0.0)).xyz, cloud_sun_dir) < 0.99) {
		return 1.0;
	}
	return 1.0 - cloud_model_block(world_pos);
}

// For shaders that leave lighting to Godot (trees, figures): albedo darkened
// by the sun's share of a sunlit face, on faces turned to the sun.
const float CLOUD_SUN_SHARE = 0.6;
float cloud_albedo_shade(vec3 world_pos, vec3 world_normal) {
	if (cloud_shadow_strength <= 0.0) {
		return 1.0;
	}
	float facing = smoothstep(0.0, 0.35, dot(world_normal, cloud_sun_dir));
	return 1.0 - cloud_model_block(world_pos) * CLOUD_SUN_SHARE * facing;
}
