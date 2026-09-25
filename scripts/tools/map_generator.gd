@tool
class_name MapGenerator
extends Node3D
## Editor tool: open scenes/tools/map_generator.tscn, tweak the settings, press
## Generate to preview, then Save As Map. A saved map inherits
## scenes/map_base.tscn and is listed in the menus through its MapInfo.

const MAP_BASE_SCENE: String = "res://scenes/map_base.tscn"
const MAP_SCENE_DIR: String = "res://scenes/maps/"
const MAP_INFO_DIR: String = "res://resources/maps/"
const PREVIEW_TERRAIN_NAME: String = "PreviewTerrain"
const PREVIEW_OBJECTS_NAME: String = "PreviewObjects"
const PREVIEW_WATER_NAME: String = "PreviewWater"
const MINIMAP_NODE_PATH: String = "UI/BottomBar/MinimapFrame"

enum CentreSite { NONE, OBJECTIVE, SHRINE }

@export_group("Map")
@export var map_name: String = "Generated Map"
@export var map_seed: int = 1
@export_range(2, 8) var player_count: int = 2
@export var symmetric: bool = true
@export_range(128, 480, 16) var map_size: int = 240
@export_range(0, 24) var border_width: int = 6
@export_range(0.3, 0.95, 0.01) var spawn_distance: float = 0.78
@export_range(0.0, 360.0, 1.0) var layout_rotation_degrees: float = 135.0

@export_group("Player Bases")
@export_range(5.0, 16.0, 0.5) var base_clear_radius: float = 7.0
@export_range(8.0, 40.0, 0.5) var base_flat_radius: float = 18.0
@export_range(0, 4) var base_gold_mines: int = 1
@export var base_gold_distance: Vector2 = Vector2(11.0, 14.0)
@export_range(0, 120) var base_trees: int = 30
@export_range(1, 4) var base_tree_clumps: int = 2
@export var base_tree_distance: Vector2 = Vector2(13.0, 20.0)

@export_group("Objectives")
@export var objective_scenes: Array[PackedScene] = [
	preload("res://scenes/objective.tscn"),
	preload("res://scenes/beastmen_objective.tscn"),
]
@export_range(0, 4) var objectives_per_player: int = 1
@export var shrine_scene: PackedScene = preload("res://scenes/shrine_objective.tscn")
@export_range(0, 4) var shrines_per_player: int = 0
@export var centre_site: CentreSite = CentreSite.SHRINE
@export_range(0.0, 10.0, 0.5) var centre_favour_per_second: float = 2.0
@export var objectives_on_plateaus: bool = true
@export_range(1, 3) var objective_plateau_tiers: int = 1
@export_range(4.0, 12.0, 0.5) var objective_clear_radius: float = 7.0
@export_range(10.0, 80.0, 1.0) var objective_min_base_distance: float = 30.0

@export_group("Settlements (Realm)")
## Above 0 this is a Realm map: each player gets this many settlements in place
## of Objectives Per Player, laid out on flat clearings (never plateaus) with
## room to grow, and joined to their base by roads.
@export_range(0, 8) var settlements_per_player: int = 0
## One per race. Every player draws them in the same shuffled order, so each
## has the same mix of races within reach.
@export var settlement_scenes: Array[PackedScene] = [
	preload("res://scenes/objective.tscn"),
	preload("res://scenes/beastmen_objective.tscn"),
	preload("res://scenes/settlements/gnoll_settlement.tscn"),
	preload("res://scenes/settlements/dark_elf_settlement.tscn"),
	preload("res://scenes/settlements/star_wanderer_settlement.tscn"),
]
@export_range(8.0, 24.0, 0.5) var settlement_clear_radius: float = 12.0
@export_range(15.0, 120.0, 1.0) var settlement_min_base_distance: float = 35.0
## Dirt roads from each base through its settlements to the centre.
@export var settlement_roads: bool = true
@export_range(2.0, 8.0, 0.5) var road_width: float = 3.5

func is_settlement_map() -> bool:
	return settlements_per_player > 0 and not settlement_scenes.is_empty()

@export_group("Terrain")
@export_range(0.0, 6.0, 0.1) var hill_height: float = 1.5
@export_range(0.005, 0.08, 0.001) var hill_frequency: float = 0.02
@export_range(0, 6) var plateaus_per_player: int = 1
@export_range(1, 3) var plateau_tiers: int = 1
@export var plateau_half_size: Vector2 = Vector2(6.0, 10.0)
@export var plateau_height_range: Vector2 = Vector2(1.5, 3.5)
@export_range(0.0, 1.0, 0.05) var valley_chance: float = 0.35
@export var valley_depth_range: Vector2 = Vector2(1.5, 3.0)
@export_range(0.0, 6.0, 0.1) var plateau_outline_noise: float = 2.0
@export_range(0.6, 3.0, 0.1) var cliff_width: float = 1.2
@export_range(0, 8) var building_pockets_per_player: int = 2
@export var building_pocket_radius: Vector2 = Vector2(5.0, 8.0)
@export_range(1, 4) var ramps_per_plateau: int = 2
@export_range(2.0, 8.0, 0.5) var ramp_width: float = 3.0
@export_range(0.15, 0.6, 0.01) var ramp_slope: float = 0.45
@export var paths_to_centre: bool = true
@export_range(1.0, 6.0, 0.5) var path_width: float = 3.0
@export_range(0, 12) var dirt_patches_per_player: int = 3
@export_range(0, 12) var grass_patches_per_player: int = 4

@export_group("Water")
@export_range(-10.0, 5.0, 0.1) var water_level: float = -2.5
@export_range(0.0, 1.0, 0.05) var coast_fraction: float = 0.5
@export_range(0.0, 20.0, 0.5) var coast_wobble: float = 8.0
@export_range(0.05, 0.6, 0.01) var beach_slope: float = 0.2
@export_range(1.0, 12.0, 0.5) var sea_depth: float = 4.0
@export_range(2.0, 20.0, 0.5) var shore_drop: float = 6.0
@export_range(0, 6) var lakes_per_player: int = 1
@export var lake_radius: Vector2 = Vector2(5.0, 11.0)
@export_range(0.5, 6.0, 0.1) var lake_depth: float = 2.5
@export_range(0.05, 1.0, 0.01) var lake_shore_slope: float = 0.35
@export_range(0, 3) var rivers_per_player: int = 1
@export var river_width: Vector2 = Vector2(4.0, 7.0)
@export_range(0.5, 5.0, 0.1) var river_depth: float = 1.8
@export_range(0.2, 0.9, 0.05) var river_length: float = 0.55
@export_range(0.0, 20.0, 0.5) var river_meander: float = 6.0
@export_range(0, 4) var fords_per_river: int = 1
@export_range(3.0, 12.0, 0.5) var ford_width: float = 6.0

@export_group("Heightmap Import")
@export_global_file("*.sd7", "*.smf", "*.png", "*.exr", "*.r16", "*.raw") var import_heightmap: String = ""
@export_range(2.0, 80.0, 0.5) var import_height_range: float = 16.0
@export_range(0.0, 1.0, 0.01) var import_image_water_height: float = 0.2
@export_range(0, 6) var import_smoothing: int = 1
@export var import_metal_as_gold: bool = true

@export_group("Colours")
@export var grass_light: Color = Color(0.658824, 0.792157, 0.345098):
	set(value):
		grass_light = value
		_apply_colours_to_preview()
@export var grass_mid: Color = Color(0.458824, 0.654902, 0.262745):
	set(value):
		grass_mid = value
		_apply_colours_to_preview()
@export var grass_dark: Color = Color(0.27451, 0.509804, 0.196078):
	set(value):
		grass_dark = value
		_apply_colours_to_preview()
@export_range(0.1, 2.0, 0.05) var grass_height: float = 0.8:
	set(value):
		grass_height = value
		_apply_colours_to_preview()
@export_range(10.0, 40.0, 1.0) var grass_detail_distance: float = 24.0
@export_range(0.1, 1.5, 0.05) var grass_brightness: float = 0.5:
	set(value):
		grass_brightness = value
		_apply_colours_to_preview()
@export var ground_light: Color = Color(0.658824, 0.792157, 0.345098):
	set(value):
		ground_light = value
		_apply_colours_to_preview()
@export var ground_mid: Color = Color(0.458824, 0.654902, 0.262745):
	set(value):
		ground_mid = value
		_apply_colours_to_preview()
@export var ground_dark: Color = Color(0.27451, 0.509804, 0.196078):
	set(value):
		ground_dark = value
		_apply_colours_to_preview()

@export_group("Forests")
@export_range(0, 30) var forest_clusters_per_player: int = 3
@export var forest_cluster_radius: Vector2 = Vector2(4.0, 9.0)
@export_range(0.0, 14.0, 0.5) var edge_forest_depth: float = 8.0
@export_range(1.2, 4.0, 0.1) var tree_spacing: float = 1.4
@export_range(1.5, 8.0, 0.1) var forest_corridor: float = 3.5

@export_group("Neutral Resources")
@export_range(0, 4) var neutral_gold_per_player: int = 1

@export_group("Decoration")
@export_range(0, 300) var props_per_player: int = 40
@export var prop_scenes: Array[PackedScene] = [
	preload("res://assets/art/AmiPolyGon_Forest_Free_Pack/AmiPolyGon_Forest_Free_Pack/GLB/bush_1.glb"),
	preload("res://assets/art/AmiPolyGon_Forest_Free_Pack/AmiPolyGon_Forest_Free_Pack/GLB/bush_2.glb"),
	preload("res://assets/art/AmiPolyGon_Forest_Free_Pack/AmiPolyGon_Forest_Free_Pack/GLB/bush_3.glb"),
	preload("res://assets/art/AmiPolyGon_Forest_Free_Pack/AmiPolyGon_Forest_Free_Pack/GLB/bush_4.glb"),
	preload("res://assets/art/AmiPolyGon_Forest_Free_Pack/AmiPolyGon_Forest_Free_Pack/GLB/log_2.glb"),
	preload("res://assets/art/AmiPolyGon_Forest_Free_Pack/AmiPolyGon_Forest_Free_Pack/GLB/log_4.glb"),
	preload("res://assets/art/AmiPolyGon_Forest_Free_Pack/AmiPolyGon_Forest_Free_Pack/GLB/trunk_2.glb"),
	preload("res://assets/art/AmiPolyGon_Forest_Free_Pack/AmiPolyGon_Forest_Free_Pack/GLB/trunk_3.glb"),
	preload("res://assets/art/AmiPolyGon_Forest_Free_Pack/AmiPolyGon_Forest_Free_Pack/GLB/stick_1.glb"),
	preload("res://assets/art/AmiPolyGon_Forest_Free_Pack/AmiPolyGon_Forest_Free_Pack/GLB/stick_2.glb"),
]
@export_range(1.5, 8.0, 0.1) var border_tree_spacing: float = 2.4
@export var border_tree_scenes: Array[PackedScene] = [
	preload("res://assets/art/AmiPolyGon_Forest_Free_Pack/AmiPolyGon_Forest_Free_Pack/GLB/tree_pine_1.glb"),
	preload("res://assets/art/AmiPolyGon_Forest_Free_Pack/AmiPolyGon_Forest_Free_Pack/GLB/tree_pine_2.glb"),
]

@export_group("Scenes")
@export var spawn_point_scene: PackedScene = preload("res://scenes/player_spawn_point.tscn")
@export var tree_scene: PackedScene = preload("res://scenes/resource_nodes/gatherable.tscn")
@export var gold_mine_scene: PackedScene = preload("res://scenes/resource_nodes/gold_deposit.tscn")

@export_group("Output")
@export var overwrite_existing: bool = false

@export_tool_button("Randomize Seed", "RandomNumberGenerator") var randomize_button: Callable = randomize_and_generate
@export_tool_button("Generate", "Reload") var generate_button: Callable = generate
@export_tool_button("Save As Map", "Save") var save_button: Callable = save_map
@export_tool_button("Clear Preview", "Clear") var clear_button: Callable = clear_preview

var layout: MapLayout = null
var _busy: bool = false

func randomize_and_generate() -> void:
	map_seed = randi() % 1000000
	notify_property_list_changed()
	generate()

func generate() -> bool:
	if _busy:
		return false
	clear_preview()
	layout = MapLayout.new(self)
	if not layout.generate():
		push_error("MapGenerator: layout generation failed (see warnings above) — try another seed or smaller counts.")
		layout = null
		return false
	var terrain: TerraBrush = MapTerrainBuilder.make_terrain(MapTerrainBuilder.build_zone(layout), MapTerrainBuilder.zones_size(layout), MapTerrainBuilder.PREVIEW_DATA_PATH, grass_palette(), ground_palette(), grass_height, grass_brightness, grass_detail_distance)
	terrain.name = PREVIEW_TERRAIN_NAME
	add_child(terrain)
	var water: MeshInstance3D = MapTerrainBuilder.make_water(layout)
	water.name = PREVIEW_WATER_NAME
	add_child(water)
	var objects := Node3D.new()
	objects.name = PREVIEW_OBJECTS_NAME
	add_child(objects)
	for entry in layout.objects:
		objects.add_child(_instantiate_object(entry, PackedScene.GEN_EDIT_STATE_DISABLED))
	for i in layout.spawn_positions.size():
		var spawn: Node3D = spawn_point_scene.instantiate()
		spawn.position = layout.spawn_positions[i]
		objects.add_child(spawn)
	print("MapGenerator: '%s' seed %d — %d objects." % [map_name, map_seed, layout.objects.size()])
	return true

func grass_palette() -> PackedColorArray:
	return PackedColorArray([grass_light, grass_mid, grass_dark])

func ground_palette() -> PackedColorArray:
	return PackedColorArray([ground_light, ground_mid, ground_dark])

func _apply_colours_to_preview() -> void:
	if is_inside_tree() and get_preview_terrain() != null:
		MapTerrainBuilder.set_palettes(get_preview_terrain(), grass_palette(), ground_palette(), grass_height, grass_brightness)

func clear_preview() -> void:
	for child_name in [PREVIEW_TERRAIN_NAME, PREVIEW_OBJECTS_NAME, PREVIEW_WATER_NAME]:
		var child := get_node_or_null(NodePath(child_name))
		if child != null:
			remove_child(child)
			child.queue_free()

func get_preview_terrain() -> TerraBrush:
	return get_node_or_null(NodePath(PREVIEW_TERRAIN_NAME)) as TerraBrush

func map_id() -> String:
	var id: String = map_name.strip_edges().to_snake_case().validate_filename().replace(" ", "_")
	return id if not id.is_empty() else "generated_map"

func save_map() -> void:
	if _busy:
		return
	if layout == null or get_preview_terrain() == null:
		if not generate():
			return
	var id: String = map_id()
	var scene_path: String = MAP_SCENE_DIR + id + ".tscn"
	var data_dir: String = MAP_SCENE_DIR + id + "_data/"
	var info_path: String = MAP_INFO_DIR + id + ".tres"
	if not overwrite_existing and (ResourceLoader.exists(scene_path) or ResourceLoader.exists(info_path)):
		push_error("MapGenerator: '%s' already exists — rename the map or tick Overwrite Existing." % id)
		return
	_busy = true
	var ok: bool = await _save_map(scene_path, data_dir, info_path)
	_busy = false
	if ok:
		print("MapGenerator: saved %s (%d players)." % [scene_path, player_count])
		if Engine.is_editor_hint():
			Engine.get_singleton(&"EditorInterface").get_resource_filesystem().scan()

func _save_map(scene_path: String, data_dir: String, info_path: String) -> bool:
	var zone: ZoneResource = get_preview_terrain().terrainZones.zones[0]
	var nav_mesh: NavigationMesh = MapTerrainBuilder.bake_navigation_mesh(layout)
	if nav_mesh.get_polygon_count() == 0:
		push_error("MapGenerator: navigation mesh bake produced no polygons.")
		return false

	_clear_data_dir(data_dir)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(data_dir))
	var heightmap: Image = zone.heightMapImage.duplicate()
	var splatmap: Image = zone.splatmapsImage[0].duplicate()
	var foliage: Image = zone.foliagesImage[0].duplicate()
	if not _save_resource(heightmap, data_dir + "Heightmap_0_0.res"):
		return false
	if not _save_resource(splatmap, data_dir + "Splatmap_0_0_0.res"):
		return false
	if not _save_resource(foliage, data_dir + "Foliage_0_0_0.res"):
		return false
	if not _save_resource(nav_mesh, data_dir + "navigation_mesh.res"):
		return false
	var minimap_path: String = data_dir + "minimap_terrain.res"
	if not _save_resource(ImageTexture.create_from_image(MapTerrainBuilder.build_minimap_image(layout)), minimap_path):
		return false
	var saved_zone := ZoneResource.new()
	saved_zone.zonePosition = Vector2i.ZERO
	saved_zone.heightMapImage = heightmap
	saved_zone.splatmapsImage = [splatmap]
	saved_zone.foliagesImage = [foliage]

	var root := Node3D.new()
	root.name = "Main"
	_assemble_map(root, MapTerrainBuilder.make_terrain(saved_zone, MapTerrainBuilder.zones_size(layout), data_dir.trim_suffix("/"), grass_palette(), ground_palette(), grass_height, grass_brightness, grass_detail_distance), nav_mesh)
	var packed := PackedScene.new()
	var err: int = packed.pack(root)
	root.free()
	if err != OK:
		push_error("MapGenerator: failed to pack map scene (error %d)." % err)
		return false
	if not _save_inherited_scene(packed, scene_path, minimap_path):
		return false

	var info := MapInfo.new()
	info.map_name = map_name.strip_edges()
	info.scene_path = scene_path
	info.max_players = player_count
	info.capture_points = layout.objects.filter(func(e): return e.kind == &"objective").size()
	return _save_resource(info, info_path)

## Builds only what the map adds on top of map_base.tscn. The three shared
## containers are created here as stand-ins and turned into overrides of the
## base's own nodes by _save_inherited_scene().
func _assemble_map(root: Node3D, terrain: TerraBrush, nav_mesh: NavigationMesh) -> void:
	var nav_region := NavigationRegion3D.new()
	nav_region.name = "NavigationRegion3D"
	nav_region.navigation_mesh = nav_mesh
	_add_owned(root, nav_region, root)

	terrain.name = "Terrain"
	_add_owned(nav_region, terrain, root)

	var water: MeshInstance3D = MapTerrainBuilder.make_water(layout)
	water.name = "Water"
	_add_owned(root, water, root)

	var spawns := Node3D.new()
	spawns.name = "PlayerSpawnPoints"
	_add_owned(root, spawns, root)
	for i in layout.spawn_positions.size():
		var spawn: Node3D = spawn_point_scene.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		spawn.name = "PlayerSpawnPoint%d" % (i + 1)
		spawn.position = layout.spawn_positions[i]
		_add_owned(spawns, spawn, root)

	var resources := Node3D.new()
	resources.name = "ResourceNodes"
	_add_owned(root, resources, root)
	var objectives := Node3D.new()
	objectives.name = "Objectives"
	_add_owned(root, objectives, root)
	var scenery := Node3D.new()
	scenery.name = "Scenery"
	_add_owned(root, scenery, root)
	var counts: Dictionary = {}
	for entry in layout.objects:
		var node: Node3D = _instantiate_object(entry, PackedScene.GEN_EDIT_STATE_INSTANCE)
		var kind: StringName = entry.kind
		counts[kind] = int(counts.get(kind, 0)) + 1
		node.name = "%s%d" % [String(kind).to_pascal_case(), counts[kind]]
		match kind:
			&"objective":
				_add_owned(objectives, node, root)
			&"border_tree", &"prop":
				node.add_to_group(&"fog_static_props", true)
				_add_owned(scenery, node, root)
			_:
				_add_owned(resources, node, root)

## PackedScene.pack() can't produce an inherited scene from script (the editor
## sets that state internally), so the packed content is serialised normally
## and its text rewritten: the root becomes an instance of map_base.tscn and
## the base's own nodes become overrides.
func _save_inherited_scene(packed: PackedScene, scene_path: String, minimap_path: String) -> bool:
	var temp_path: String = "user://map_generator_tmp.tscn"
	var err: int = ResourceSaver.save(packed, temp_path)
	if err != OK:
		push_error("MapGenerator: failed to serialise map scene (error %d)." % err)
		return false
	var text: String = FileAccess.get_file_as_string(temp_path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))

	var root_header := RegEx.create_from_string("(?m)^\\[node name=\"Main\" type=\"Node3D\"[^\\]]*\\]$")
	var overrides := RegEx.create_from_string("(?m)^\\[node name=\"(NavigationRegion3D|PlayerSpawnPoints|ResourceNodes)\" type=\"[^\"]+\" parent=\"\\.\"[^\\]]*\\]$")
	if root_header.search(text) == null:
		push_error("MapGenerator: unexpected scene layout while writing %s." % scene_path)
		return false
	text = root_header.sub(text, "[node name=\"Main\" instance=ExtResource(\"map_base\")]")
	text = overrides.sub(text, "[node name=\"$1\" parent=\".\"]", true)

	var first_ext: int = text.find("[ext_resource")
	var first_sub: int = text.find("[sub_resource")
	var head_end: int = first_ext if first_ext >= 0 else first_sub
	if head_end < 0:
		head_end = text.find("[node")
	text = text.insert(head_end, "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"map_base\"]\n[ext_resource type=\"Texture2D\" path=\"%s\" id=\"minimap_terrain\"]\n" % [MAP_BASE_SCENE, minimap_path])
	var cloud_size: int = layout.size + 80
	text = text.insert(text.find("[node"), "[sub_resource type=\"PlaneMesh\" id=\"PlaneMesh_map_clouds\"]\nsize = Vector2(%d, %d)\n\n" % [cloud_size, cloud_size])
	text += "\n[node name=\"FogOfWar\" parent=\".\"]\nmap_origin = Vector2(%s, %s)\nmap_size = Vector2(%d, %d)\nterrain_mesh_path = NodePath(\"\")\n" % [-layout.half, -layout.half, layout.size, layout.size]
	text += "\n[node name=\"CloudShadowLayer\" parent=\".\"]\nmesh = SubResource(\"PlaneMesh_map_clouds\")\n"
	text += "\n[node name=\"Minimap\" parent=\"%s\"]\nterrain_texture = ExtResource(\"minimap_terrain\")\n" % MINIMAP_NODE_PATH

	var file := FileAccess.open(scene_path, FileAccess.WRITE)
	if file == null:
		push_error("MapGenerator: cannot write %s." % scene_path)
		return false
	file.store_string(text)
	file.close()
	return true

func _instantiate_object(entry: Dictionary, edit_state: int) -> Node3D:
	var scene: PackedScene = entry.scene
	var node: Node3D = scene.instantiate(edit_state)
	node.position = entry.position
	node.rotation.y = entry.yaw
	var props: Dictionary = entry.get("props", {})
	for key in props:
		if key in node:
			node.set(key, props[key])
	if entry.scale != 1.0:
		node.scale = Vector3.ONE * entry.scale
	return node

func _add_owned(parent: Node, child: Node, root: Node) -> void:
	parent.add_child(child)
	child.owner = root

func _save_resource(resource: Resource, path: String) -> bool:
	var err: int = ResourceSaver.save(resource, path)
	if err != OK:
		push_error("MapGenerator: failed to save %s (error %d)." % [path, err])
		return false
	resource.take_over_path(path)
	return true

func _clear_data_dir(data_dir: String) -> void:
	var dir := DirAccess.open(data_dir)
	if dir == null:
		return
	for file in dir.get_files():
		if file.ends_with(".res") or file.ends_with(".import"):
			dir.remove(file)
