// TerraBrush terrain shader with BinbunGrass's ground look (BinbunGrass/src/shader/ground.gdshader):
// wherever ground_texture_index is painted, the albedo is replaced by world-space
// noise sampled through the palette, so it matches binbun_foliage.gdshader's blades.
shader_type spatial;
render_mode cull_back, blend_mix, depth_draw_opaque;

#include "res://addons/terrabrush/Resources/Shaders/heightmap_clipmap_shader_include.gdshaderinc"

group_uniforms FogOfWar;
#include "res://shaders/terrain/binbun_fog.gdshaderinc"
#include "res://shaders/terrain/ground_stamp.gdshaderinc"

group_uniforms Binbun;
uniform int ground_texture_index = 0;
uniform sampler2D noise_texture;
uniform sampler2D color_gradient : source_color;
uniform float brightness : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float noise_scale : hint_range(0.005, 0.2, 0.001) = 0.04;

group_uniforms Paths;
uniform int dirt_texture_index = 1;
uniform vec3 dirt_dark : source_color = vec3(0.42, 0.30, 0.20);
uniform vec3 dirt_light : source_color = vec3(0.54, 0.41, 0.28);
uniform vec3 dirt_edge : source_color = vec3(0.30, 0.22, 0.13);
uniform vec3 pebble_color : source_color = vec3(0.70, 0.62, 0.50);
// Sharpens the soft 1 px/m splat blend into a crisp edge, wobbled by noise.
uniform float edge_sharpness : hint_range(1.0, 40.0, 0.5) = 7.0;
uniform float edge_wobble : hint_range(0.0, 1.0, 0.01) = 0.35;
uniform float edge_band : hint_range(0.0, 0.5, 0.01) = 0.12;
uniform float pebble_density : hint_range(0.0, 1.0, 0.01) = 0.05;

varying vec3 _worldVertex;
varying vec3 _worldNormal;
varying vec3 _triplanarPos;
varying vec3 _triplanarPowerNormal;
varying vec3 world_pos;

float splat_weight(vec3 zone_vertex, int index) {
	if (index < 0 || index >= NumberOfTextures) {
		return 0.0;
	}
	vec3 zone_uv = Resolution > 1.0 ? calculateZoneUVResolution(zone_vertex, false) : calculateZoneUV(zone_vertex);
	if (zone_uv.z < 0.0) {
		return 0.0;
	}
	float splatmap_layers = zone_uv.z * ceil(float(NumberOfTextures) / 4.0);
	vec4 splatmap = texture(Splatmaps, vec3(zone_uv.xy, float(index / 4) + splatmap_layers));
	return splatmap[index % 4];
}

vec3 dirt_albedo(vec2 xz, float edge) {
	float broad = texture(noise_texture, xz * 0.06).r;
	float fine = texture(noise_texture, xz * 0.45 + vec2(0.37, 0.71)).r;
	float tone = clamp(broad * 0.8 + fine * 0.25 - 0.05, 0.0, 1.0);
	vec3 color = mix(dirt_dark, dirt_light, smoothstep(0.2, 0.9, tone));
	float speck = texture(noise_texture, xz * 2.3 + vec2(0.13, 0.52)).r;
	color = mix(color, pebble_color, step(1.0 - pebble_density * 0.35, speck) * 0.8);
	return mix(color, dirt_edge, edge);
}

void vertex() {
	_worldVertex = vec3(0);
	_worldNormal = vec3(0);
	_triplanarPos = vec3(0);
	_triplanarPowerNormal = vec3(0);
	calculateHeightmapVertex(
		MODEL_MATRIX,
		COLOR,
		VERTEX,
		NORMAL,
		_worldVertex,
		_worldNormal,
		_triplanarPos,
		_triplanarPowerNormal
	);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	calculateHeightmapFragment(
		_worldVertex,
		_worldNormal,
		_triplanarPos,
		_triplanarPowerNormal,
		ALBEDO,
		NORMAL_MAP,
		METALLIC,
		SPECULAR,
		ROUGHNESS
	);

	float grass_w = splat_weight(_worldVertex, ground_texture_index);
	float dirt_w = splat_weight(_worldVertex, dirt_texture_index);
	float stamped = max(dirt_w, ground_stamp(world_pos.xz) * (grass_w + dirt_w));
	grass_w = max(grass_w + dirt_w - stamped, 0.0);
	dirt_w = stamped;
	float noise_value = texture(noise_texture, world_pos.xz * noise_scale).r;
	vec3 grass = texture(color_gradient, vec2(noise_value, 0.0)).rgb * brightness;

	// Grass/dirt share of this pixel; rock and sand keep TerraBrush's blend.
	float ground_w = clamp(grass_w + dirt_w, 0.0, 1.0);
	float dirt_share = dirt_w / max(grass_w + dirt_w, 0.0001);
	float wobble = (texture(noise_texture, world_pos.xz * 0.35).r - 0.5) * edge_wobble;
	float d = dirt_share - 0.5 + wobble;
	float dirt_mask = clamp(d * edge_sharpness + 0.5, 0.0, 1.0);
	float edge = 1.0 - smoothstep(0.0, edge_band, d);
	vec3 path = mix(grass, dirt_albedo(world_pos.xz, edge * 0.7), dirt_mask);
	ALBEDO = mix(ALBEDO, path, ground_w);
	ROUGHNESS = mix(ROUGHNESS, 1.0, ground_w);
	ALBEDO = apply_fog(ALBEDO, world_pos.xz, SPECULAR);
}

// Binbun's unclamped wrap lighting, scaled by the light's colour/energy like
// Godot's own lambert so it sits in maps lit for standard materials.
void light() {
	float ndotl = dot(LIGHT, NORMAL) * ATTENUATION;
	DIFFUSE_LIGHT += ndotl * LIGHT_COLOR / PI;
}
