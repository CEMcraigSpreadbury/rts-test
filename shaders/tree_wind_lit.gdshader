shader_type spatial;
// The lit pine GLBs' StandardMaterial3D, redrawn with tree_wind sway. Built by
// TreeWind (scripts/tree_wind.gd). cull_disabled matches the doubleSided flag
// those GLBs ship with.
render_mode cull_disabled;

#include "res://shaders/util/tree_wind.gdshaderinc"

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform bool use_vertex_color = false;
uniform float roughness : hint_range(0.0, 1.0) = 1.0;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;

void vertex() {
	VERTEX += tree_wind(VERTEX, MODEL_MATRIX, NODE_POSITION_WORLD, TIME);
}

void fragment() {
	vec3 albedo = texture(albedo_texture, UV).rgb * albedo_color.rgb;
	if (use_vertex_color) {
		albedo *= COLOR.rgb;
	}
	ALBEDO = albedo;
	ROUGHNESS = roughness;
	METALLIC = metallic;
}
