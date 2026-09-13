// Ambient tree sway, shared by baked_emission.gdshader (the baked tree.glb)
// and tree_wind_lit.gdshader (the lit pines). TreeWind (scripts/tree_wind.gd)
// sets wind_strength/wind_height per tree mesh; wind_strength defaults to 0 so
// everything else on the baked shader (gold, bushes, fields) stays still.

uniform float wind_strength : hint_range(0.0, 0.2) = 0.0;
uniform float wind_height = 2.0;
uniform vec2 wind_direction = vec2(0.8, 0.6);
uniform float wind_speed = 1.0;

// Model-space offset for `vertex`. Bend grows with height squared so the
// trunk stays planted and the canopy does the moving; `origin` staggers the
// phase so a forest doesn't sway in lockstep.
vec3 tree_wind(vec3 vertex, mat4 model, vec3 origin, float time) {
	float bend = clamp(vertex.y / wind_height, 0.0, 1.0);
	bend *= bend;
	float phase = dot(origin.xz, vec2(0.37, 0.61));
	float t = time * wind_speed;

	float sway = 0.35 + sin(t * 1.1 + phase) * 0.6 + sin(t * 2.3 + phase * 1.7) * 0.25;
	float gust = 0.6 + 0.4 * sin(t * 0.35 + phase * 0.2);
	float flutter = sin(t * 4.0 + phase + dot(vertex, vec3(3.1, 2.3, 2.7))) * 0.15;

	// World wind direction into model space (row-vector multiply = inverse
	// rotation), so rotated/scaled instances all lean the same way.
	vec3 dir = normalize((vec4(wind_direction.x, 0.0, wind_direction.y, 0.0) * model).xyz);
	vec3 across = vec3(-dir.z, 0.3, dir.x);

	return (dir * sway * gust + across * flutter) * wind_strength * wind_height * bend;
}
