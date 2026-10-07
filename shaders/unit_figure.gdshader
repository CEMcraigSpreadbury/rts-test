shader_type spatial;
// A unit drawn as a painted diorama figure (assets/art/Models/Units, built by
// the Blender kit there), one instance of FigureBatcher's MultiMesh per unit
// (native/src/figure_batcher.*). The mesh has no texture of its own: every
// face's UVs sit on one row of the shared palette image, and its vertex
// colours carry what the kit baked (see kit/figure.py):
//   UV        palette row (V) and shadow..highlight tone along it (U)
//   COLOR.r   ambient occlusion and the top-to-toe falloff
//   COLOR.g   shine, 0 matte cloth .. 1 polished steel
// Rows from team_v down are grey shades the team colour is multiplied into
// (the helmet's paint, the shield's face, the hem). No ink outline: the
// figure reads by its shading and colour, as the reference's do.
//
// What varies per unit arrives in INSTANCE_CUSTOM (see figure_batcher.cpp):
//   .x team colour packed 0xRRGGBB   .y status tint packed the same way
//   .z hit flash 0..1                .w shown 0..1, negative when dying

#include "res://shaders/unit_figure.gdshaderinc"

uniform sampler2D palette : source_color, filter_linear, repeat_disable;
// palette.py TEAM_V: where the team rows start, from the image's top.
uniform float team_v = 0.875;
// A team swatch of this grey (linear) shows the team colour as it is; lighter
// and darker greys shade it. Kept in step with kit/palette.py.
uniform float team_grey_ref = 0.42;
// The team colours are fully saturated; painted onto a figure they are taken
// down a little, as the building roofs' are.
uniform float team_saturation = 0.88;

// Night: a little cool light back onto the figure, as unit_night_lift.gdshader
// gives the sprites (DayNight writes the global once a frame).
global uniform float unit_night_lift;
uniform vec4 lift_color : source_color = vec4(0.55, 0.68, 1.0, 1.0);
uniform float lift_strength = 0.35;
uniform float flash_strength = 0.7;

varying flat vec4 v_custom;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
}

void fragment() {
	// A corpse fades out by a fixed dither, so it stays in the opaque pipeline
	// (and keeps casting and taking shadows) all the way.
	if (figure_dithered_out(abs(v_custom.w), FRAGCOORD.xy)) {
		discard;
	}
	vec3 colour = compat_in(texture(palette, UV).rgb);
	if (UV.y >= team_v) {
		vec3 team = figure_to_linear(figure_unpack_rgb(v_custom.x));
		team = mix(vec3(dot(team, vec3(0.2126, 0.7152, 0.0722))), team, team_saturation);
		colour = min(team * (colour.r / team_grey_ref), vec3(1.0));
	}
	float ao = COLOR.r;
	float shine = COLOR.g;
	// The status tint multiplies as the sprites' modulate does.
	vec3 albedo = colour * ao * figure_unpack_rgb(v_custom.y);
	vec3 emission = albedo * lift_color.rgb * lift_strength * unit_night_lift;
	// The hit flash washes it toward white, short of a white blob: a solid
	// figure has far more pixels than a sprite to flash.
	float flash = clamp(v_custom.z, 0.0, 1.0) * flash_strength;
	albedo = mix(albedo, vec3(1.0), flash);
	emission += vec3(flash * 0.6);
	ALBEDO = compat_out(albedo);
	EMISSION = compat_out(emission);
	// Painted plastic in the satin finish every model shares, so the sun leaves
	// a soft glint on helmets, heads and shoulders; steel tighter still.
	ROUGHNESS = mix(0.5, 0.25, shine);
	SPECULAR = mix(0.5, 0.8, shine);
	// The thin clear coat every model shares (plastic_light.gdshaderinc).
	CLEARCOAT = 0.25;
	CLEARCOAT_ROUGHNESS = 0.35;
}
