// Fog of war for the Binbun TerraBrush shaders. TerraBrush displaces its terrain
// in the vertex shader, so fog_of_war.gdshader's next_pass (which reads the raw
// mesh vertices) can't follow it; the fog is mixed in here instead. Same uniform
// names and math as grass_wind.gdshader, so fog_of_war.gd wires both alike.
// fog_enabled stays off in the editor, where nothing drives these uniforms.
uniform bool fog_enabled = false;
uniform sampler2D fog_tex : filter_linear;
uniform vec2 fog_map_origin;
uniform vec2 fog_map_size;
const int FOG_MAX_VISION_SOURCES = 64;
uniform vec2 fog_vision_positions[FOG_MAX_VISION_SOURCES];
uniform float fog_vision_radii[FOG_MAX_VISION_SOURCES];
uniform int fog_vision_count;

// Fog colour in linear space: (5, 8, 5) sRGB bytes, see fog_of_war.gdshader.
const vec3 FOG_COLOR = vec3(5.0, 8.0, 5.0) / 255.0 / 12.92;

// How strongly fog covers this point: 1 = never explored, 0.6 = explored, 0 = in vision.
float fog_amount(vec2 world_xz, out float explored) {
	explored = 0.0;
	if (!fog_enabled) {
		return 0.0;
	}
	explored = texture(fog_tex, (world_xz - fog_map_origin) / fog_map_size).r;
	float vis = 0.0;
	for (int i = 0; i < fog_vision_count; i++) {
		float r = fog_vision_radii[i];
		vis = max(vis, 1.0 - smoothstep(r * 0.85, r, distance(world_xz, fog_vision_positions[i])));
	}
	return mix(1.0, 0.6, explored) * (1.0 - vis);
}

// The overlay blends FOG_COLOR * explored over the unshaded surface; lighting is
// linear in albedo, so blending the albedo gives the same result on a lit surface.
// specular is scaled down too, or sky reflections show fogged terrain's relief.
vec3 apply_fog(vec3 albedo, vec2 world_xz, inout float specular) {
	float explored;
	float amount = fog_amount(world_xz, explored);
	specular *= 1.0 - amount;
	return mix(albedo, FOG_COLOR * explored, amount);
}
