shader_type spatial;
// A plain-coloured imported model (rocks, gold deposits, the farm field,
// scenery props) in the moulded-plastic finish every model shares; the
// constants are the buildings' (plastic_light.gdshaderinc). Built by
// PlasticMaterial (scripts/plastic_material.gd) from the model's own
// StandardMaterial3D. cull_disabled matches the doubleSided flag the GLBs ship
// with.
render_mode cull_disabled;

#include "res://shaders/util/plastic_light.gdshaderinc"

uniform sampler2D albedo_texture : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform bool use_vertex_color = false;
// Foliage (bushes) takes the pines' softer finish (tree_wind_lit.gdshader);
// everything else the buildings' gloss.
uniform bool foliage = false;
// Per-instance recolour, white = as exported. A farm field uses it to show
// its crop going from bare soil to green to ripe (see farm_field.gd).
instance uniform vec3 tint : source_color = vec3(1.0);

void fragment() {
	vec3 albedo = texture(albedo_texture, UV).rgb * albedo_color.rgb * tint;
	if (use_vertex_color) {
		albedo *= COLOR.rgb;
	}
	ALBEDO = albedo;
	ROUGHNESS = foliage ? 0.5 : PLASTIC_ROUGHNESS;
	SPECULAR = PLASTIC_SPECULAR;
	CLEARCOAT = foliage ? 0.25 : PLASTIC_CLEARCOAT;
	CLEARCOAT_ROUGHNESS = foliage ? 0.35 : PLASTIC_CLEARCOAT_ROUGHNESS;
}
