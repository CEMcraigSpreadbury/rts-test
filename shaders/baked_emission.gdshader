shader_type spatial;
// Draws a "shaded" GLB export (tree, gold deposit, ...) the way its imported
// material did — baked texture as emission — but darkened under directional
// shadows. Applied by baked_lighting_material.gd; buildings get the same
// treatment through team_color.gdshader instead.
// cull_disabled matches the doubleSided flag those GLBs ship with.
render_mode cull_disabled;

#include "res://shaders/util/baked_sun_shadow.gdshaderinc"
#include "res://shaders/util/tree_wind.gdshaderinc"
#include "res://shaders/util/cloud_shade.gdshaderinc"

uniform sampler2D source_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 emission_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float emission_energy : hint_range(0.0, 16.0) = 1.0;
uniform float sun_shadow_strength : hint_range(0.0, 1.0) = 0.5;
// Per-instance recolour, white = as exported. A farm field uses it to show
// its crop going from bare soil to green to ripe (see farm_field.gd).
instance uniform vec3 tint : source_color = vec3(1.0);

void vertex() {
	VERTEX += tree_wind(VERTEX, MODEL_MATRIX, NODE_POSITION_WORLD, TIME);
}

void fragment() {
	vec3 baked = texture(source_texture, UV).rgb * emission_color.rgb * emission_energy * tint;
	EMISSION = baked * cloud_shade((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	ALBEDO = baked;
	AO = 0.0;
}

void light() {
	DIFFUSE_LIGHT -= baked_sun_shadow(NORMAL, LIGHT, ATTENUATION, LIGHT_IS_DIRECTIONAL, sun_shadow_strength);
}
