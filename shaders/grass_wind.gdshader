// Billboard Grass with Wind — https://godotshaders.com/shader/billboard-grass-with-wind/
// Kept byte-for-byte identical to the original (only the #include path below
// was ever adjusted, to this project's shaders/util/ location) so it's easy
// to tell at a glance this isn't diverging from the reference.
shader_type spatial;
render_mode blend_mix, depth_prepass_alpha;

uniform bool billboard = false;

uniform sampler2D shape_texture;
uniform sampler2D shape_atlas;
uniform bool use_atlas = false;

group_uniforms Colors;
uniform sampler2D noise_texture;
uniform sampler2D color_gradient;
uniform float random_variation : hint_range(0.0, 1.0, 0.001) = 0.002;

group_uniforms Wind;
uniform sampler2D wind_texture;
uniform vec2 wind_velocity;

group_uniforms Transparency;
uniform float alpha_cut_start : hint_range(0.0, 1.0, 0.05) = 0.1;
uniform float alpha_cut_end : hint_range(0.0, 1.0, 0.05) = 0.9;
uniform int alpha_mode : hint_enum("Smooth", "Dithered", "Cut") = 0;

group_uniforms FogOfWar;
// Wired up by fog_of_war.gd directly onto each grass layer's own material
// (see FogOfWar._setup_grass_fog_materials) — not part of the original
// referenced shader, kept in its own uniform group and named with a fog_
// prefix so it's obviously separate from everything above.
//
// fog_enabled defaults off and must be explicitly turned on by fog_of_war.gd
// — the material also renders in the editor (while painting, with no
// FogOfWar node running anywhere), where every uniform below is unset
// garbage; without this gate, an unbound fog_tex + fog_vision_count == 0
// made every blade discard itself, which is exactly what made grass
// disappear entirely both in the editor and anywhere fog isn't wired up.
uniform bool fog_enabled = false;
uniform sampler2D fog_tex : source_color, filter_linear;
uniform vec2 fog_map_origin;
uniform vec2 fog_map_size;
const int FOG_MAX_VISION_SOURCES = 32;
uniform vec2 fog_vision_positions[FOG_MAX_VISION_SOURCES];
uniform float fog_vision_radii[FOG_MAX_VISION_SOURCES];
uniform int fog_vision_count;

varying flat int id;
varying vec3 world_pos;

#include "util/dither.gdshaderinc"

vec2 atlas_uv(vec2 uv, int index, int size){
	int tile_count = size * size;
	int i = index % tile_count;
	float x = float(i % size);
	float y = float(i / size);
	vec2 tile_size = 1.0 / vec2(float(size));
	return uv* tile_size + (vec2(x, y) * tile_size);
}

float randomf(int index, int seed){
	float value = sin(float(index + seed)) * 0.5 + 0.5;
	return value;
}

float wind_noise(){
	float value = texture(wind_texture, (world_pos.xz*0.03) - (vec2(TIME * 0.01) * wind_velocity)).r;
	return value;
}

vec3 wind(vec2 uv){
	float wind_noise = wind_noise();
	float wind_affect = pow(1.0 - uv.y, 2.0);
	vec3 value = vec3(
		wind_noise * (wind_velocity.x),
		0.0,
		wind_noise * (wind_velocity.y)) * 0.25;
	value *= wind_affect;
	return value;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	id = INSTANCE_ID;

	if(billboard){
		mat4 billboard_matrix = mat4(
				MAIN_CAM_INV_VIEW_MATRIX[0],
				MAIN_CAM_INV_VIEW_MATRIX[1],
				MAIN_CAM_INV_VIEW_MATRIX[2],
				MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = VIEW_MATRIX * billboard_matrix;

		VERTEX += (VIEW_MATRIX * vec4(wind(UV), 0.0)).xyz;
	} else {
		VERTEX += wind(UV);
	}
	NORMAL = vec3(0.0,1.0,0.0);
}

void fragment() {
	float shape_value = texture(shape_texture, UV).r;
	if(use_atlas){
		vec2 atlas_uv = atlas_uv(UV, id, 2);
		shape_value = texture(shape_atlas, atlas_uv).r;
	}

	float noise_value = texture(noise_texture, world_pos.xz * 0.1).r;
	if(randomf(id,1) < random_variation) noise_value += 0.4;
	vec4 color = texture(color_gradient, vec2(noise_value, 0.0));

	ALBEDO = color.rgb;

	float alpha = shape_value;
	if(alpha_mode == 0){
		ALPHA = alpha;
	} else {
		alpha = clamp((shape_value - alpha_cut_start) / (alpha_cut_end - alpha_cut_start), 0.0, 1.0);
		if(alpha_mode == 1){
			alpha = step(bayer4(FRAGCOORD.xy) + 0.01, alpha);
		}
		if(alpha < 0.1) discard;
	}

	// Fog of war: identical math to fog_of_war.gdshader's terrain overlay
	// (fog_tex's alpha channel encodes 1.0 = never explored down to ~0.6 =
	// explored, with vision carving a smooth currently-visible hole out of
	// that), applied here as a multiply-and-discard on this blade's own
	// alpha instead of a separate overlay pass — a next_pass tried first but
	// depends on FogOfWar._ready() finding this layer's node already in the
	// tree, which isn't guaranteed by sibling order; doing it inline here
	// has no such ordering dependency. Gated on fog_enabled — see that
	// uniform's declaration for why this can't just run unconditionally.
	if (fog_enabled) {
		vec2 fog_uv = (world_pos.xz - fog_map_origin) / fog_map_size;
		vec4 fog = texture(fog_tex, fog_uv);
		float fog_vis = 0.0;
		for (int i = 0; i < fog_vision_count; i++) {
			float d = distance(world_pos.xz, fog_vision_positions[i]);
			float r = fog_vision_radii[i];
			fog_vis = max(fog_vis, 1.0 - smoothstep(r * 0.85, r, d));
		}
		ALPHA *= 1.0 - fog.a * (1.0 - fog_vis);
		if (ALPHA < 0.01) {
			discard;
		}
	}
}

void light(){
	float ndotl = dot(LIGHT, NORMAL) * ATTENUATION;
	DIFFUSE_LIGHT += ndotl;
}
