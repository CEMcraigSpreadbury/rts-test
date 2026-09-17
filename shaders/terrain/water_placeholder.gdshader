// Placeholder water surface for generated maps, until a proper water shader
// replaces it: translucent, darker and more opaque the deeper the ground below.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

group_uniforms FogOfWar;
#include "res://shaders/terrain/binbun_fog.gdshaderinc"

group_uniforms Water;
uniform vec4 shallow_color : source_color = vec4(0.32, 0.62, 0.66, 0.45);
uniform vec4 deep_color : source_color = vec4(0.06, 0.22, 0.36, 0.9);
// Metres of water (along the view ray) to go from shallow to deep colour.
uniform float depth_fade = 3.0;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float scene_depth = texture(depth_tex, SCREEN_UV).r;
	vec4 scene_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene_depth, 1.0);
	float thickness = VERTEX.z - scene_view.z / scene_view.w;
	vec4 color = mix(shallow_color, deep_color, clamp(thickness / depth_fade, 0.0, 1.0));
	float specular = 0.5;
	ALBEDO = apply_fog(color.rgb, world_pos.xz, specular);
	SPECULAR = specular;
	ROUGHNESS = 0.15;
	ALPHA = color.a;
}
