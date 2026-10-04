// Shared by the ground scatter shaders (scripts/ground_scatter.gd): vertex
// colour lit like the terrain, a per-instance tint in INSTANCE_CUSTOM.rgb,
// hidden where dirt is stamped under a building or field, and fogged like
// the terrain (fog_of_war.gd finds these by shader).
#include "res://shaders/terrain/binbun_fog.gdshaderinc"
#include "res://shaders/terrain/ground_stamp.gdshaderinc"
#include "res://shaders/util/cloud_shade.gdshaderinc"

varying vec3 scatter_world;
varying vec3 scatter_tint;

// Each shader's vertex() sets the two varyings above (a function may not),
// then asks this whether the piece shows: `mode` (INSTANCE_CUSTOM.a) says how
// it treats dirt stamped under a building or field (GroundScatter.HIDE_ON_DIRT
// / ALWAYS / ONLY_ON_DIRT). Hidden pieces collapse to a point.
bool scatter_visible(vec3 origin, float mode) {
	bool stamped = ground_stamp(origin.xz) > 0.5;
	return !((mode < 0.25 && stamped) || (mode > 0.75 && !stamped));
}

vec3 scatter_albedo(vec3 colour, inout float specular) {
	return apply_fog(colour * scatter_tint * cloud_ground(scatter_world), scatter_world.xz, specular);
}
