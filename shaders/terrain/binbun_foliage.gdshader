// TerraBrush foliage (MultiMesh strategy) shader with BinbunGrass's blade look
// (BinbunGrass/src/shader/grass.gdshader). TerraBrush's include still decides where
// each blade goes; its transform is recovered by running two probe points through
// it, then the quad is rebuilt around that point as a Binbun billboard.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

#include "res://shaders/terrain/binbun_foliage_clipmap.gdshaderinc"
#include "res://shaders/terrain/grass_clumps.gdshaderinc"
#include "res://shaders/util/cloud_shade.gdshaderinc"
#include "res://BinbunGrass/src/shader/util/dither.gdshaderinc"

uniform bool billboard = true;
// Per-blade size multiplier, picked evenly in this range — the demo's
// MultiMesh blades span 0..2x. TerraBrush's own scale noise is ignored.
uniform vec2 blade_scale_range = vec2(0.0, 2.0);
// Height relative to width: below 1 the blades are wide, low clumps, so a
// big blade still leaves unit sprites standing clear of the grass.
uniform float blade_height = 1.0;
// Blades in coarser LOD rings (wider spacing) grow by (spacing ratio)^this,
// so the grass doesn't visibly thin out with distance.
uniform float lod_size_compensation : hint_range(0.0, 1.0, 0.05) = 0.5;
// How far along the camera's view the dense grass is centred, at most.
uniform float max_focus_distance = 60.0;

uniform sampler2D shape_atlas;
uniform int atlas_size = 2;

group_uniforms Colors;
uniform sampler2D noise_texture;
uniform sampler2D color_gradient : source_color;
// Multiplies the palette; map lighting is far brighter than the demo scene.
uniform float brightness : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float noise_scale : hint_range(0.005, 0.2, 0.001) = 0.04;
uniform float random_variation : hint_range(0.0, 1.0, 0.001) = 0.002;

group_uniforms Wind;
uniform sampler2D wind_texture;
uniform vec2 wind_velocity;
// Accumulated noise scroll, driven by FogOfWar so velocity changes stay seamless.
uniform vec2 wind_offset;
// The wind noise only spans ~0.4-0.65, which reads as a steady lean rather than
// gusts, so it's stretched around its middle by this much.
uniform float gust_contrast = 4.0;
uniform float gust_strength = 0.18;
// Ripples rolling downwind on top of the gusts, as a fraction of the lean.
uniform float flutter : hint_range(0.0, 1.0, 0.05) = 0.3;
uniform float flutter_speed = 2.5;
// World units between ripple crests.
uniform float flutter_wavelength = 10.0;

group_uniforms Transparency;
uniform float alpha_cut_start : hint_range(0.0, 1.0, 0.05) = 0.4;
uniform float alpha_cut_end : hint_range(0.0, 1.0, 0.05) = 0.6;
uniform int alpha_mode : hint_enum("Dithered", "Cut") = 0;

group_uniforms FogOfWar;
#include "res://shaders/terrain/binbun_fog.gdshaderinc"
group_uniforms;
#include "res://shaders/terrain/ground_stamp.gdshaderinc"

group_uniforms Paths;
// The splatmap channels binbun_terrain.gdshader blends as grass and path dirt.
uniform int ground_texture_index = 0;
uniform int dirt_texture_index = 1;
// No blade where this share of the ground (path or stamp) is dirt, the same
// cut for both. A stamp's own 0.5 is its dirt edge, so blades stop just short.
uniform float dirt_cut : hint_range(0.0, 1.0, 0.01) = 0.4;
group_uniforms;

// dirt / (grass + dirt) at a point in the terrain's space, as the terrain shader
// takes it. TerraBrush's own placement grows a blade anywhere the grass channel
// is over 0.2, which puts a scatter of blades out on the soft edge of a path.
float painted_dirt(vec3 terrain_pos) {
	if (dirt_texture_index < 0 || dirt_texture_index >= NumberOfTextures) {
		return 0.0;
	}
	vec3 zone_uv = calculateZoneUVResolution(vec3(terrain_pos.x, 0.0, terrain_pos.z), false);
	if (zone_uv.z < 0.0) {
		return 0.0;
	}
	float layers = zone_uv.z * ceil(float(NumberOfTextures) / 4.0);
	float grass = texture(Splatmaps, vec3(zone_uv.xy, float(ground_texture_index / 4) + layers))[ground_texture_index % 4];
	float dirt = texture(Splatmaps, vec3(zone_uv.xy, float(dirt_texture_index / 4) + layers))[dirt_texture_index % 4];
	return dirt / max(grass + dirt, 0.0001);
}

varying vec3 world_pos;
// Where the blade is rooted: it takes the painted ground colour from there, so
// a blade matches the ground it grows from and only shows as a ragged edge
// where that colour changes.
varying vec3 root_pos;
varying flat int blade_index;
varying flat float blade_random;

vec2 atlas_uv(vec2 uv, int index, int size) {
	int i = index % (size * size);
	vec2 tile_size = 1.0 / vec2(float(size));
	return uv * tile_size + vec2(float(i % size), float(i / size)) * tile_size;
}

// Always leans downwind (0..1 of the full lean), so neighbouring blades move together.
vec3 wind(vec2 uv) {
	float wind_noise = texture(wind_texture, (world_pos.xz * 0.03) - wind_offset).r;
	float gust = clamp(0.5 + (wind_noise - 0.5) * gust_contrast, 0.0, 1.0);
	float speed = length(wind_velocity);
	vec2 direction = speed > 0.0001 ? wind_velocity / speed : vec2(0.0);
	float ripple = 0.5 + 0.5 * sin(dot(world_pos.xz, direction) * TAU / flutter_wavelength - TIME * flutter_speed);
	gust = mix(gust, gust * ripple, flutter);
	float wind_affect = pow(1.0 - uv.y, 2.0);
	return vec3(wind_velocity.x, 0.0, wind_velocity.y) * gust * gust_strength * wind_affect;
}

// The ground point the main camera looks at (in the terrain's local space), snapped
// to the coarsest LOD cell so every ring's blades stay put while panning.
vec3 clip_centre(mat4 camera_transform, mat4 model_matrix) {
	vec3 camera = camera_transform[3].xyz;
	vec3 forward = -camera_transform[2].xyz;
	float distance_along = forward.y < -0.01 ? min(-camera.y / forward.y, max_focus_distance) : max_focus_distance;
	vec3 focus = camera + forward * distance_along - model_matrix[3].xyz;
	float snap = InitialCellWidth * pow(2.0, float(max(LODLevels - 1, 0)));
	return vec3(round(focus.x / snap) * snap, 0.0, round(focus.z / snap) * snap);
}

void vertex() {
	vec3 base = vec3(0.0);
	vec3 top = vec3(0.0, 1.0, 0.0);
	vec3 probe_normal = NORMAL;
	vec4 probe_color = COLOR;
	vec3 grid_position = vec3(0.0);
	float cell_width = InitialCellWidth;
	vec3 centre = clip_centre(MAIN_CAM_INV_VIEW_MATRIX, MODEL_MATRIX);
	calculateFoliageVertex(INSTANCE_ID, centre, base, probe_normal, probe_color, grid_position, cell_width);
	calculateFoliageVertex(INSTANCE_ID, centre, top, probe_normal, probe_color, grid_position, cell_width);
	bool blade_present = length(top - base) > 0.0001
			&& max(ground_stamp((MODEL_MATRIX * vec4(base, 1.0)).xz), painted_dirt(base)) < dirt_cut;

	// Seeded by the blade's whole-number cell index, never its float position:
	// the hash magnifies the last bit of a float, and the grid's positions shift
	// by that much every time the clipmap steps after the camera, which would
	// give every blade a new size, rotation and texture each step (jitter).
	vec2 cell_index = mod(round(grid_position.xz / cell_width), vec2(251.0));
	float lod_level = round(log2(cell_width / InitialCellWidth));
	vec3 seed = vec3(cell_index.x * 0.731, lod_level * 0.37, cell_index.y * 0.593);
	vec3 rnd = hash_noise_range(seed) * 0.5 + 0.5;
	blade_index = int(rnd.y * float(atlas_size * atlas_size));
	blade_random = rnd.z;

	float blade_scale = mix(blade_scale_range.x, blade_scale_range.y, hash_noise_range(seed + vec3(17.0)).x * 0.5 + 0.5);
	blade_scale *= pow(cell_width / InitialCellWidth, lod_size_compensation);

	vec3 offset = VERTEX * blade_scale * vec3(1.0, blade_height, 1.0);
	if (billboard) {
		offset = MAIN_CAM_INV_VIEW_MATRIX[0].xyz * offset.x + MAIN_CAM_INV_VIEW_MATRIX[1].xyz * offset.y;
	} else {
		offset = rotateY(rnd.x * TAU) * offset;
	}
	root_pos = (MODEL_MATRIX * vec4(base, 1.0)).xyz;
	world_pos = root_pos + offset;
	if (blade_present) {
		world_pos += wind(UV);
	}

	VERTEX = blade_present ? world_pos : vec3(0.0);
	MODELVIEW_MATRIX = VIEW_MATRIX;
	MODELVIEW_NORMAL_MATRIX = mat3(VIEW_MATRIX);
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	float shape_value = texture(shape_atlas, atlas_uv(UV, blade_index, atlas_size)).r;

	float noise_value = texture(noise_texture, root_pos.xz * noise_scale).r;
	if (blade_random < random_variation) noise_value += 0.4;
	SPECULAR = 0.0;
	// None: blades occlude one another, and any AO here lands on them as dark
	// patches across the meadow. The ground under them carries the contact
	// shading round walls and rocks.
	AO_LIGHT_AFFECT = 0.0;
	// Tells the outline pass this is a grass blade (see outline.gdshader).
	ROUGHNESS = 0.985;
	// Sunlit tips: the top of each blade a touch lighter and warmer (UV.y runs
	// 0 at the tip to 1 at the root); the base stays the ground's own colour.
	vec3 tip_light = mix(vec3(1.0), vec3(1.16, 1.12, 0.9), smoothstep(0.45, 0.95, 1.0 - UV.y));
	ALBEDO = apply_fog(grass_clumps(texture(color_gradient, vec2(noise_value, 0.0)).rgb * brightness, root_pos.xz, noise_texture) * tip_light, world_pos.xz, SPECULAR);

	float alpha = clamp((shape_value - alpha_cut_start) / (alpha_cut_end - alpha_cut_start), 0.0, 1.0);
	if (alpha_mode == 0) {
		alpha = step(bayer4(FRAGCOORD.xy) + 0.01, alpha);
	}
	if (alpha < 0.1) discard;

	// Wind can bend a blade's tip past its base on screen, flipping those triangles
	// to back faces; cull_disabled then flips NORMAL downward and the unclamped
	// light() turns them black. Keep every face lit as straight up.
	NORMAL = mat3(VIEW_MATRIX) * vec3(0.0, 1.0, 0.0);
}

// Binbun's unclamped wrap lighting, scaled by the light's colour/energy like
// Godot's own lambert so it sits in maps lit for standard materials.
#include "res://shaders/terrain/ground_light.gdshaderinc"

void light() {
	float cloud = cloud_sun_block(root_pos, texture(noise_texture, root_pos.xz * 0.7).r);
	ground_light(LIGHT, NORMAL, ATTENUATION, LIGHT_COLOR, LIGHT_IS_DIRECTIONAL, cloud, DIFFUSE_LIGHT);
}
