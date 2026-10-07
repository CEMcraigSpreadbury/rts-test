shader_type spatial;
// Draws a "shaded" GLB export (tree, gold deposit, ...) the way its imported
// material did — baked texture as emission — but darkened under directional
// shadows. Applied by baked_lighting_material.gd; buildings get the same
// treatment through team_color.gdshader instead.
// cull_disabled matches the doubleSided flag those GLBs ship with.
render_mode cull_disabled;

#include "res://shaders/util/baked_sun_shadow.gdshaderinc"
#include "res://shaders/util/tree_wind.gdshaderinc"
#include "res://shaders/util/compat_color.gdshaderinc"
#include "res://shaders/util/plastic_light.gdshaderinc"
#include "res://shaders/util/cloud_shade.gdshaderinc"
#include "res://shaders/util/wetness.gdshaderinc"

uniform sampler2D source_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 emission_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float emission_energy : hint_range(0.0, 16.0) = 1.0;
uniform float sun_shadow_strength : hint_range(0.0, 1.0) = 0.5;
// Per-instance recolour, white = as exported. A farm field uses it to show
// its crop going from bare soil to green to ripe (see farm_field.gd).
instance uniform vec3 tint : source_color = vec3(1.0);

varying vec3 cloud_world;

void vertex() {
	VERTEX += tree_wind(VERTEX, MODEL_MATRIX, NODE_POSITION_WORLD, TIME);
	cloud_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 baked = compat_out(compat_in(texture(source_texture, UV).rgb) * compat_in(emission_color.rgb) * emission_energy * compat_in(tint));
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Darker and glossier in the rain (wetness.gdshaderinc).
	float wet = wet_amount((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz, world);
	baked *= wet_darken(wet);
	EMISSION = baked + wet_sheen(NORMAL, VIEW, wet);
	ALBEDO = baked;
	AO = 0.0;
	ROUGHNESS = wet_roughness(PLASTIC_ROUGHNESS, wet);
	SPECULAR = PLASTIC_SPECULAR;
	CLEARCOAT = wet_clearcoat(PLASTIC_CLEARCOAT, wet);
	CLEARCOAT_ROUGHNESS = wet_clearcoat_roughness(PLASTIC_CLEARCOAT_ROUGHNESS, wet);
}

void light() {
	// A passing cloud takes the sun as a shadow would (cloud_shade.gdshaderinc).
	float sun = min(ATTENUATION, cloud_light(cloud_world, LIGHT, INV_VIEW_MATRIX, LIGHT_IS_DIRECTIONAL));
	DIFFUSE_LIGHT -= baked_sun_shadow(NORMAL, LIGHT, sun, LIGHT_IS_DIRECTIONAL, sun_shadow_strength);
	SPECULAR_LIGHT += plastic_specular(NORMAL, LIGHT, VIEW, LIGHT_COLOR, sun, SPECULAR_AMOUNT);
	SPECULAR_LIGHT += wet_specular(NORMAL, LIGHT, VIEW, LIGHT_COLOR, sun, wet_facing(NORMAL, INV_VIEW_MATRIX));
}
