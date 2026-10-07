// Rain soaking the models: Weather (scripts/weather.gd) ramps the rain_wetness
// global up through a shower and lets it dry off slowly afterwards. A wet
// surface goes darker and glossier -- a tight, bright glint over the plastic's
// satin shine, and a cool sheen of sky along the edges turned from the view.
//
// In fragment():
//   float wet = wet_amount(world_normal, world_pos);
//   colour *= wet_darken(wet);   (albedo, and the emission of baked models)
//   ROUGHNESS = wet_roughness(ROUGHNESS, wet);  CLEARCOAT/_ROUGHNESS likewise
//   EMISSION += wet_sheen(NORMAL, VIEW, wet);
// Shaders with their own light() add the glint themselves:
//   SPECULAR_LIGHT += wet_specular(NORMAL, LIGHT, VIEW, LIGHT_COLOR, ATTENUATION, wet_facing(NORMAL, INV_VIEW_MATRIX));
global uniform float rain_wetness;
// 0 by day, 1 at night (DayNight); the sky the sheen reflects goes dark.
global uniform float unit_night_lift;

const float WET_DARKEN = 0.72;
const float WET_ROUGHNESS = 0.1;
const vec3 WET_SKY = vec3(0.5, 0.58, 0.68);

float wet_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float wet_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(wet_hash(i), wet_hash(i + vec2(1.0, 0.0)), u.x),
			mix(wet_hash(i + vec2(0.0, 1.0)), wet_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// How much of the rain lands on a face, by which way it points: tops (roofs,
// helmets, shoulders) soak, walls get less, undersides (eaves) stay dry.
float wet_facing_world(vec3 world_normal) {
	float up = world_normal.y;
	return rain_wetness * mix(0.55, 1.0, smoothstep(0.0, 0.7, up)) * smoothstep(-0.75, -0.2, up);
}

float wet_facing(vec3 view_normal, mat4 inv_view) {
	return wet_facing_world(normalize((inv_view * vec4(view_normal, 0.0)).xyz));
}

// wet_facing, with streaks of water running down the walls and patches that
// stay a little drier on the tops.
float wet_amount(vec3 world_normal, vec3 world_pos) {
	if (rain_wetness <= 0.0) {
		return 0.0;
	}
	float wall = 1.0 - smoothstep(0.4, 0.8, abs(world_normal.y));
	float streaks = wet_noise(vec2((world_pos.x + world_pos.z) * 7.0, world_pos.y * 0.6));
	float patches = wet_noise(world_pos.xz * 1.3);
	float vary = mix(mix(0.8, 1.0, patches), mix(0.45, 1.0, streaks), wall);
	return wet_facing_world(world_normal) * vary;
}

float wet_darken(float wet) {
	return mix(1.0, WET_DARKEN, wet);
}

float wet_roughness(float roughness, float wet) {
	return mix(roughness, WET_ROUGHNESS, wet);
}

// A film of water over the clear coat: it goes thick and mirror-smooth.
float wet_clearcoat(float clearcoat, float wet) {
	return mix(clearcoat, 1.0, wet);
}

float wet_clearcoat_roughness(float roughness, float wet) {
	return mix(roughness, 0.02, wet);
}

// The sky caught in the water film, mostly along the edges turned from the
// view. Emission rather than a reflection, so it shows the same on every
// model, whatever its lighting path.
vec3 wet_sheen(vec3 view_normal, vec3 view, float wet) {
	float fresnel = pow(1.0 - clamp(dot(view_normal, view), 0.0, 1.0), 4.0);
	return WET_SKY * (0.03 + 0.35 * fresnel) * wet * mix(1.0, 0.15, unit_night_lift);
}

// The sun's glint off the water film: a tight GGX lobe at WET_ROUGHNESS.
vec3 wet_specular(vec3 normal, vec3 light, vec3 view, vec3 light_color, float attenuation, float wet) {
	float n_dot_l = dot(normal, light);
	if (wet <= 0.0 || n_dot_l <= 0.0) {
		return vec3(0.0);
	}
	vec3 h = normalize(light + view);
	float n_dot_h = max(dot(normal, h), 0.0);
	float l_dot_h = max(dot(light, h), 1e-4);
	float alpha = WET_ROUGHNESS * WET_ROUGHNESS;
	float a2 = alpha * alpha;
	float d = n_dot_h * n_dot_h * (a2 - 1.0) + 1.0;
	float ggx = a2 / (PI * d * d);
	float fresnel = 0.04 + 0.96 * pow(1.0 - l_dot_h, 5.0);
	// Clear-coat style visibility (as plastic_specular's coat).
	float spec = ggx * (0.25 / (l_dot_h * l_dot_h)) * fresnel;
	return light_color / PI * attenuation * spec * n_dot_l * wet;
}
