shader_type spatial;
// The team_color.gdshader look for a building that is still going up (see
// ProductionBuilding._update_construction_layers): solid plastic below
// build_y, a faint see-through blueprint above it, and a bright rim along
// the newest layer's top edge as it snaps on. Kept as a separate shader so a
// finished building still renders in the opaque pass, where it sorts against
// the world correctly and costs nothing extra. depth_prepass_alpha lets the
// solid part write depth like any opaque model; the ghost above does not.
render_mode cull_disabled, blend_mix, depth_prepass_alpha;

#include "res://shaders/team_color.gdshaderinc"

// World height of the top of the built part.
uniform float build_y = -1000.0;
// 1 the moment a layer snaps on, fading to 0: lights its fresh top edge.
uniform float band_glow : hint_range(0.0, 1.0) = 0.0;
uniform float ghost_alpha : hint_range(0.0, 1.0) = 0.18;
const float BAND_WIDTH = 0.09;

void vertex() {
	cloud_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 texel = texture(source_texture, UV);
	vec3 albedo;
	vec3 emission;
	float ao;
	write_team_colored_surface(texel, albedo, emission, ao);
	ALBEDO = albedo;
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// A little grime toward the foot of the walls.
	float foot = mix(0.82, 1.0, smoothstep(0.0, 0.9, world.y - MODEL_MATRIX[3].y));
	// Darker and glossier in the rain (wetness.gdshaderinc).
	float wet = wet_amount((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz, world);
	float shade = foot * wet_darken(wet);
	ALBEDO *= shade;
	EMISSION = emission * shade + wet_sheen(NORMAL, VIEW, wet);
	AO = ao;
	METALLIC = metallic_value;
	ROUGHNESS = wet_roughness(PLASTIC_ROUGHNESS, wet);
	SPECULAR = PLASTIC_SPECULAR;
	CLEARCOAT = wet_clearcoat(PLASTIC_CLEARCOAT, wet);
	CLEARCOAT_ROUGHNESS = wet_clearcoat_roughness(PLASTIC_CLEARCOAT_ROUGHNESS, wet);
	if (world.y > build_y) {
		// Not built yet: a pale blueprint of what is coming.
		ALBEDO = mix(ALBEDO, vec3(dot(ALBEDO, vec3(0.333))), 0.5) + 0.08;
		ALPHA = texel.a * ghost_alpha;
	} else {
		float band = 1.0 - smoothstep(0.0, BAND_WIDTH, build_y - world.y);
		EMISSION += ALBEDO * band * band_glow * 1.6 + vec3(band * band_glow * 0.25);
		ALPHA = texel.a;
	}
}
