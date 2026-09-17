@tool
class_name MapTerrainBuilder
extends RefCounted
## Turns a MapLayout into TerraBrush terrain data and a navigation mesh.
##
## The map is one TerraBrush zone with a heightmap pixel on every cell corner,
## straight from MapLayout's height field. The navigation mesh is baked from the
## same corner heights, so units walk on exactly what's drawn and Recast drops
## the steep cliff bands.

const TERRAIN_MATERIAL: ShaderMaterial = preload("res://resources/terrain/binbun/binbun_terrain_material.tres")
const TEXTURE_SETS: Resource = preload("res://resources/terrain/binbun/binbun_texture_sets.tres")
const GRASS_FOLIAGE: Resource = preload("res://resources/terrain/binbun/binbun_grass_foliage.tres")
const WATER_SHADER: Shader = preload("res://shaders/terrain/water_placeholder.gdshader")

## Splatmap channels, in TEXTURE_SETS order. Grass is also where the Binbun
## blades grow (binbun_grass_foliage.tres applies on texture 0).
const GRASS: int = 0
const DIRT: int = 1
const ROCK: int = 2
const SAND: int = 3
## Ground lower than this above the water, and within SAND_REACH pixels
## (metres) of it, is sand — so low-lying plains away from water stay grass.
const SAND_HEIGHT: float = 0.6
const SAND_REACH: int = 6
## A height step between neighbouring corners above this is a cliff face;
## hills and ramps (MapGenerator.ramp_slope) stay below it.
const ROCK_STEP: float = 0.6
const NAV_MAX_SLOPE_DEGREES: float = 40.0

## TerraBrush crashes without a data folder and writes any missing zone images
## into it, so the generator preview gets a throwaway one.
const PREVIEW_DATA_PATH: String = "user://map_generator_preview"

## Odd so corners land on whole metres: a zone of N pixels spans N - 1 metres
## centred on the origin, putting pixel p at world p - (N - 1) / 2.
static func zones_size(layout: MapLayout) -> int:
	return nearest_po2(layout.size + MapLayout.OUTER_PADDING * 2) + 1

static func build_zone(layout: MapLayout) -> ZoneResource:
	var n: int = zones_size(layout)
	var offset: int = (n - 1) / 2 - int(layout.half)
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	for py in n:
		for px in n:
			heights[py * n + px] = corner_height(layout, Vector2i(px - offset, py - offset))

	var heightmap := Image.create_empty(n, n, false, Image.FORMAT_RGF)
	var weights: Array[PackedFloat32Array] = []
	for channel in 4:
		var w := PackedFloat32Array()
		w.resize(n * n)
		weights.append(w)
	var corners: int = layout.size + 1
	var shore: PackedInt32Array = _distance_to_water(heights, n, layout.water_level)
	for py in n:
		for px in n:
			var i: int = py * n + px
			heightmap.set_pixel(px, py, Color(heights[i], 0.0, 0.0))
			var channel: int = GRASS
			if _max_step(heights, n, px, py) > ROCK_STEP:
				channel = ROCK
			elif heights[i] < layout.water_level + SAND_HEIGHT and shore[i] <= SAND_REACH:
				channel = SAND
			else:
				var cx: int = px - offset
				var cy: int = py - offset
				if cx >= 0 and cy >= 0 and cx < corners and cy < corners and layout.dirt[cy * corners + cx] == 1:
					channel = DIRT
			weights[channel][i] = 1.0

	var splatmap := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for py in n:
		for px in n:
			var blended := Color(0, 0, 0, 0)
			for channel in 4:
				blended[channel] = _box_blur(weights[channel], n, px, py)
			splatmap.set_pixel(px, py, blended)

	var zone := ZoneResource.new()
	zone.zonePosition = Vector2i.ZERO
	zone.heightMapImage = heightmap
	zone.splatmapsImage = [splatmap]
	zone.foliagesImage = [Image.create_empty(n, n, false, Image.FORMAT_RGBA8)]
	return zone

## A flat placeholder water surface at the water level, covering the whole
## terrain zone. Fog of war finds it by its shader, like the terrain.
static func make_water(layout: MapLayout) -> MeshInstance3D:
	var plane := PlaneMesh.new()
	## Well past the terrain, so the horizon is sea rather than the terrain's cut edge.
	var span: float = (zones_size(layout) - 1) * 4.0
	plane.size = Vector2(span, span)
	var material := ShaderMaterial.new()
	material.shader = WATER_SHADER
	var water := MeshInstance3D.new()
	water.mesh = plane
	water.material_override = material
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.position = Vector3(0.0, layout.water_level, 0.0)
	return water

## One pixel per cell for the minimap: water shaded by depth, sand, rock on
## cliffs, and grass lighter the higher it stands.
static func build_minimap_image(layout: MapLayout) -> Image:
	var image := Image.create_empty(layout.size, layout.size, false, Image.FORMAT_RGB8)
	var low: float = layout.water_level
	var high: float = layout.water_level + 1.0
	for h in layout.heights:
		high = maxf(high, h)
	var shore: PackedInt32Array = _distance_to_water(layout.heights, layout.size + 1, low)
	for z in layout.size:
		for x in layout.size:
			var c := Vector2i(x, z)
			var h: float = layout.surface_height(layout.cell_centre(c))
			var color: Color
			if h < low:
				color = Color(0.16, 0.34, 0.42).lerp(Color(0.06, 0.16, 0.26), clampf((low - h) / 3.0, 0.0, 1.0))
			elif layout.cliff[layout.index(c)] == 1:
				color = Color(0.3, 0.29, 0.27)
			elif h < low + SAND_HEIGHT and shore[z * (layout.size + 1) + x] <= SAND_REACH:
				color = Color(0.55, 0.5, 0.36)
			else:
				color = Color(0.17, 0.26, 0.14).lerp(Color(0.3, 0.4, 0.22), clampf((h - low) / (high - low), 0.0, 1.0))
			image.set_pixel(x, z, color)
	return image

## Offsets of BinbunGrass/src/palette/palette_01.tres, which the palettes replace.
const PALETTE_OFFSETS: PackedFloat32Array = [0.166667, 0.5, 0.833333]

## The terrain material and grass foliage definition are duplicated per map so
## each map keeps its own palettes (saved inline in the map scene).
static func make_terrain(zone: ZoneResource, zone_size: int, data_path: String, grass_palette: PackedColorArray, ground_palette: PackedColorArray, grass_height: float, grass_brightness: float, grass_detail_distance: float) -> TerraBrush:
	var zones := ZonesResource.new()
	zones.zones = [zone]
	var definition: FoliageDefinitionResource = GRASS_FOLIAGE.duplicate()
	definition.customShader = definition.customShader.duplicate()
	## Width of the full-density ring of blades (the clipmap's first LOD level);
	## the blade count grows with its square. Rows must be odd.
	definition.lodRowsPerLevel = int(ceil(grass_detail_distance / definition.lodInitialCellWidth)) | 1
	var foliage := FoliageResource.new()
	foliage.definition = definition
	var terrain := TerraBrush.new()
	terrain.dataPath = data_path
	terrain.zonesSize = zone_size
	terrain.customShader = TERRAIN_MATERIAL.duplicate()
	terrain.textureSets = TEXTURE_SETS
	terrain.foliages = [foliage]
	terrain.createCollisionInThread = false
	terrain.terrainZones = zones
	set_palettes(terrain, grass_palette, ground_palette, grass_height, grass_brightness)
	return terrain

## TerraBrush renders with copies of these materials on its internal mesh
## nodes, so those copies are updated too for a live preview.
static func set_palettes(terrain: TerraBrush, grass_palette: PackedColorArray, ground_palette: PackedColorArray, grass_height: float, grass_brightness: float) -> void:
	var ground_texture := _palette_texture(ground_palette)
	var grass_texture := _palette_texture(grass_palette)
	var terrain_material: ShaderMaterial = terrain.customShader
	var grass_material: ShaderMaterial = terrain.foliages[0].definition.customShader
	terrain_material.set_shader_parameter("color_gradient", ground_texture)
	terrain_material.set_shader_parameter("brightness", grass_brightness)
	grass_material.set_shader_parameter("brightness", grass_brightness)
	grass_material.set_shader_parameter("color_gradient", grass_texture)
	grass_material.set_shader_parameter("blade_scale_range", Vector2(grass_height * 0.5, grass_height))
	_set_rendered_palettes(terrain, terrain_material.shader, ground_texture, grass_material.shader, grass_texture, grass_height, grass_brightness)

static func _set_rendered_palettes(node: Node, terrain_shader: Shader, ground_texture: Texture2D, grass_shader: Shader, grass_texture: Texture2D, grass_height: float, grass_brightness: float) -> void:
	if node is GeometryInstance3D:
		var material := (node as GeometryInstance3D).material_override as ShaderMaterial
		if material != null and material.shader == terrain_shader:
			material.set_shader_parameter("color_gradient", ground_texture)
			material.set_shader_parameter("brightness", grass_brightness)
		elif material != null and material.shader == grass_shader:
			material.set_shader_parameter("color_gradient", grass_texture)
			material.set_shader_parameter("blade_scale_range", Vector2(grass_height * 0.5, grass_height))
			material.set_shader_parameter("brightness", grass_brightness)
	for child in node.get_children(true):
		_set_rendered_palettes(child, terrain_shader, ground_texture, grass_shader, grass_texture, grass_height, grass_brightness)

static func _palette_texture(colors: PackedColorArray) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PALETTE_OFFSETS
	gradient.colors = colors
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	return texture

static func corner_height(layout: MapLayout, corner: Vector2i) -> float:
	return layout.corner_height(corner)

## Steps (4-connected, capped just past SAND_REACH) from each pixel to the
## nearest one under water.
static func _distance_to_water(heights: PackedFloat32Array, n: int, water_level: float) -> PackedInt32Array:
	var distance := PackedInt32Array()
	distance.resize(n * n)
	distance.fill(SAND_REACH + 1)
	var frontier: Array[int] = []
	for i in n * n:
		if heights[i] < water_level:
			distance[i] = 0
			frontier.append(i)
	var head: int = 0
	while head < frontier.size():
		var i: int = frontier[head]
		head += 1
		var next: int = distance[i] + 1
		if next > SAND_REACH:
			continue
		var x: int = i % n
		var y: int = i / n
		for neighbour in [i - 1 if x > 0 else -1, i + 1 if x < n - 1 else -1, i - n if y > 0 else -1, i + n if y < n - 1 else -1]:
			if neighbour >= 0 and distance[neighbour] > next:
				distance[neighbour] = next
				frontier.append(neighbour)
	return distance

static func _max_step(heights: PackedFloat32Array, n: int, px: int, py: int) -> float:
	var h: float = heights[py * n + px]
	var step: float = 0.0
	for d in MapLayout.DIRS:
		var x: int = px + d.x
		var y: int = py + d.y
		if x >= 0 and y >= 0 and x < n and y < n:
			step = maxf(step, absf(heights[y * n + x] - h))
	return step

static func _box_blur(values: PackedFloat32Array, n: int, px: int, py: int) -> float:
	var total: float = 0.0
	var count: int = 0
	for y in range(maxi(0, py - 1), mini(n, py + 2)):
		for x in range(maxi(0, px - 1), mini(n, px + 2)):
			total += values[y * n + x]
			count += 1
	return total / count

## Navigation is baked from the layout rather than the rendered terrain, so
## only playable surfaces are included: nothing in the decorative border.
static func bake_navigation_mesh(layout: MapLayout) -> NavigationMesh:
	var faces := PackedVector3Array()
	for z in layout.size:
		for x in layout.size:
			var c := Vector2i(x, z)
			if not layout.is_playable_cell(c) or layout.is_deep_water(c):
				continue
			var corners: Array[Vector3] = []
			for offset in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var corner: Vector2i = c + offset
				corners.append(Vector3(corner.x - layout.half, corner_height(layout, corner), corner.y - layout.half))
			_append_down_facing(faces, corners[0], corners[1], corners[2])
			_append_down_facing(faces, corners[0], corners[2], corners[3])
	var geometry := NavigationMeshSourceGeometryData3D.new()
	geometry.add_faces(faces, Transform3D.IDENTITY)
	var nav_mesh := NavigationMesh.new()
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.01
	nav_mesh.agent_radius = NavigationBlockers.UNIT_BODY_RADIUS
	nav_mesh.agent_max_slope = NAV_MAX_SLOPE_DEGREES
	## Default detail on purpose: NavigationBlockers rebakes this mesh at match
	## start from its own triangles, which already hugs hills to ~0.3m, while
	## finer detail here multiplied the rebaked polygon count (~3.7x) and made
	## every rebake and unit repath visibly hitch.
	NavigationServer3D.bake_from_source_geometry_data(nav_mesh, geometry)
	return nav_mesh

## add_faces() flips winding, and Recast drops downward faces — so hand it
## triangles facing down (same trick as NavigationBlockers).
static func _append_down_facing(faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3) -> void:
	if (b - a).cross(c - a).y <= 0.0:
		faces.append_array(PackedVector3Array([a, b, c]))
	else:
		faces.append_array(PackedVector3Array([a, c, b]))
