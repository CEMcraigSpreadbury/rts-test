// TerraBrush terrain shader with BinbunGrass's ground look (BinbunGrass/src/shader/ground.gdshader):
// wherever ground_texture_index is painted, the albedo is replaced by world-space
// noise sampled through the palette, so it matches binbun_foliage.gdshader's blades.
shader_type spatial;
render_mode cull_back, blend_mix, depth_draw_opaque;

#include "res://addons/terrabrush/Resources/Shaders/heightmap_clipmap_shader_include.gdshaderinc"

group_uniforms FogOfWar;
#include "res://shaders/terrain/binbun_fog.gdshaderinc"

group_uniforms Binbun;
uniform int ground_texture_index = 0;
uniform sampler2D noise_texture;
uniform sampler2D color_gradient : source_color;
uniform float brightness : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float noise_scale : hint_range(0.005, 0.2, 0.001) = 0.04;

varying vec3 _worldVertex;
varying vec3 _worldNormal;
varying vec3 _triplanarPos;
varying vec3 _triplanarPowerNormal;
varying vec3 world_pos;

float ground_weight(vec3 zone_vertex) {
	if (ground_texture_index < 0 || ground_texture_index >= NumberOfTextures) {
		return 0.0;
	}
	vec3 zone_uv = Resolution > 1.0 ? calculateZoneUVResolution(zone_vertex, false) : calculateZoneUV(zone_vertex);
	if (zone_uv.z < 0.0) {
		return 0.0;
	}
	float splatmap_layers = zone_uv.z * ceil(float(NumberOfTextures) / 4.0);
	vec4 splatmap = texture(Splatmaps, vec3(zone_uv.xy, float(ground_texture_index / 4) + splatmap_layers));
	return splatmap[ground_texture_index % 4];
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

	float weight = ground_weight(_worldVertex);
	float noise_value = texture(noise_texture, world_pos.xz * noise_scale).r;
	vec4 color = texture(color_gradient, vec2(noise_value, 0.0));
	ALBEDO = mix(ALBEDO, color.rgb * brightness, weight);
	ROUGHNESS = mix(ROUGHNESS, 1.0, weight);
	ALBEDO = apply_fog(ALBEDO, world_pos.xz, SPECULAR);
}

// Binbun's unclamped wrap lighting, scaled by the light's colour/energy like
// Godot's own lambert so it sits in maps lit for standard materials.
void light() {
	float ndotl = dot(LIGHT, NORMAL) * ATTENUATION;
	DIFFUSE_LIGHT += ndotl * LIGHT_COLOR / PI;
}
