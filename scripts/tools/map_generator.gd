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

enum CentreSite { NONE, OBJECTIVE, SHRINE }

@export_group("Map")
@export var map_name: String = "Generated Map"
@export var map_seed: int = 1
@export_range(2, 8) var player_count: int = 2
@export_range(96, 320, 16) var map_size: int = 160
@export_range(0, 24) var border_width: int = 6
@export_range(0.3, 0.95, 0.01) var spawn_distance: float = 0.78
@export_range(0.0, 360.0, 1.0) var layout_rotation_degrees: float = 135.0

@export_group("Player Bases")
@export_range(5.0, 16.0, 0.5) var base_clear_radius: float = 7.0
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

@export_group("Terrain")
@export_range(1, 4) var plateau_height: int = 2
@export_range(0, 6) var plateaus_per_player: int = 1
@export_range(1, 3) var plateau_tiers: int = 1
@export var plateau_half_size: Vector2 = Vector2(6.0, 10.0)
@export_range(1, 4) var ramps_per_plateau: int = 2
@export_range(1, 7, 2) var ramp_width: int = 3
@export var paths_to_centre: bool = true
@export_range(1.0, 6.0, 0.5) var path_width: float = 3.0
@export_range(0, 12) var dirt_patches_per_player: int = 3
@export_range(0, 12) var grass_patches_per_player: int = 4

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
	preload("res://assets/art/Models/Tree/tree.glb"),
	preload("res://assets/art/AmiPolyGon_Forest_Free_Pack/AmiPolyGon_Forest_Free_Pack/GLB/tree_pine_1.glb"),
	preload("res://assets/art/AmiPolyGon_Forest_Free_Pack/AmiPolyGon_Forest_Free_Pack/GLB/tree_pine_2.glb"),
]

@export_group("Scenes")
@export var spawn_point_scene: PackedScene = preload("res://scenes/player_spawn_point.tscn")
@export var tree_scene: PackedScene = preload("res://scenes/resource_nodes/gatherable.tscn")
@export var gold_mine_scene: PackedScene = preload("res://scenes/resource_nodes/gold_deposit.tscn")

@export_group("Tiles")
@export var tileset: TileSet = preload("res://resources/terrain/terrain_tileset.tres")
@export var ground_tiles: Array[Vector2i] = [Vector2i(22, 7)]
@export var plateau_template: Vector2i = Vector2i(15, 10)
@export var cliff_tiles: Array[Vector2i] = [Vector2i(16, 15), Vector2i(17, 15), Vector2i(18, 15)]
@export var ramp_tiles: Array[Vector2i] = [Vector2i(12, 2), Vector2i(12, 3)]
@export var dirt_template: Vector2i = Vector2i(10, 5)
@export var grass_template: Vector2i = Vector2i(0, 5)

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
	var terrain := TileMapLayer3D.new()
	terrain.name = PREVIEW_TERRAIN_NAME
	terrain.settings = make_tile_settings()
	terrain.tile_map_data = MapTerrainBuilder.build_tile_data(layout, self, terrain)
	add_child(terrain)
	var objects := Node3D.new()
	objects.name = PREVIEW_OBJECTS_NAME
	add_child(objects)
	for entry in layout.objects:
		objects.add_child(_instantiate_object(entry, PackedScene.GEN_EDIT_STATE_DISABLED))
	for i in layout.spawn_positions.size():
		var spawn: Node3D = spawn_point_scene.instantiate()
		spawn.position = layout.spawn_positions[i]
		objects.add_child(spawn)
	print("MapGenerator: '%s' seed %d — %d tiles, %d objects." % [map_name, map_seed, terrain.get_tile_count(), layout.objects.size()])
	return true

func clear_preview() -> void:
	for child_name in [PREVIEW_TERRAIN_NAME, PREVIEW_OBJECTS_NAME]:
		var child := get_node_or_null(NodePath(child_name))
		if child != null:
			remove_child(child)
			child.queue_free()

func get_preview_terrain() -> TileMapLayer3D:
	return get_node_or_null(NodePath(PREVIEW_TERRAIN_NAME)) as TileMapLayer3D

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
	var terrain: TileMapLayer3D = get_preview_terrain()
	var options := RegionBakeOptions.new()
	var baked_instance: MeshInstance3D = await RegionBaker.bake_mesh(terrain, null, options)
	if baked_instance == null:
		push_error("MapGenerator: terrain mesh bake failed.")
		return false
	var terrain_mesh: Mesh = baked_instance.mesh
	baked_instance.free()

	terrain.clear_collision_shapes(Vector3i.MAX)
	var collision: Array = []
	for region in TileMeshMerger.get_collision_regions(terrain, true):
		var shape: ConcavePolygonShape3D = await RegionBaker.bake_collision(terrain, region, options)
		if shape != null:
			collision.append([region.region_key, shape])
	if collision.is_empty():
		push_error("MapGenerator: collision bake produced no shapes.")
		return false

	var nav_mesh: NavigationMesh = MapTerrainBuilder.bake_navigation_mesh(layout)
	if nav_mesh.get_polygon_count() == 0:
		push_error("MapGenerator: navigation mesh bake produced no polygons.")
		return false

	_clear_data_dir(data_dir)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(data_dir))
	var tile_data: TileMapLayerData = terrain.tile_map_data.duplicate()
	if not _save_resource(tile_data, data_dir + "terrain_tiles.res"):
		return false
	if not _save_resource(terrain_mesh, data_dir + "terrain_mesh.res"):
		return false
	if not _save_resource(nav_mesh, data_dir + "navigation_mesh.res"):
		return false
	for entry in collision:
		var key: Vector3i = entry[0]
		if not _save_resource(entry[1], data_dir + "collision_%d_%d_%d.res" % [key.x, key.y, key.z]):
			return false

	var root := Node3D.new()
	root.name = "Main"
	_assemble_map(root, tile_data, terrain_mesh, nav_mesh, collision)
	var packed := PackedScene.new()
	var err: int = packed.pack(root)
	root.free()
	if err != OK:
		push_error("MapGenerator: failed to pack map scene (error %d)." % err)
		return false
	if not _save_inherited_scene(packed, scene_path):
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
func _assemble_map(root: Node3D, tile_data: TileMapLayerData, terrain_mesh: Mesh, nav_mesh: NavigationMesh, collision: Array) -> void:
	var nav_region := NavigationRegion3D.new()
	nav_region.name = "NavigationRegion3D"
	nav_region.navigation_mesh = nav_mesh
	_add_owned(root, nav_region, root)

	var terrain := TileMapLayer3D.new()
	terrain.name = "TileMapLayer3D"
	terrain.settings = make_tile_settings()
	terrain.tile_map_data = tile_data
	_add_owned(nav_region, terrain, root)
	var body := StaticCollisionBody3D.new()
	body.name = "TileMapLayer3D_Collision"
	_add_owned(terrain, body, root)
	for entry in collision:
		var key: Vector3i = entry[0]
		var shape_node := RegionCollisionShape.new()
		shape_node.name = "Region_%d_%d_%d" % [key.x, key.y, key.z]
		shape_node.region_key = key
		shape_node.shape = entry[1]
		_add_owned(body, shape_node, root)

	var baked := MeshInstance3D.new()
	baked.name = "TileMapLayer3D_Baked"
	baked.mesh = terrain_mesh
	_add_owned(nav_region, baked, root)

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
func _save_inherited_scene(packed: PackedScene, scene_path: String) -> bool:
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
	text = text.insert(head_end, "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"map_base\"]\n" % MAP_BASE_SCENE)
	var cloud_size: int = layout.size + 80
	text = text.insert(text.find("[node"), "[sub_resource type=\"PlaneMesh\" id=\"PlaneMesh_map_clouds\"]\nsize = Vector2(%d, %d)\n\n" % [cloud_size, cloud_size])
	text += "\n[node name=\"FogOfWar\" parent=\".\"]\nmap_origin = Vector2(%s, %s)\nmap_size = Vector2(%d, %d)\nterrain_mesh_path = NodePath(\"../NavigationRegion3D/TileMapLayer3D_Baked\")\n" % [-layout.half, -layout.half, layout.size, layout.size]
	text += "\n[node name=\"CloudShadowLayer\" parent=\".\"]\nmesh = SubResource(\"PlaneMesh_map_clouds\")\n"

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

func make_tile_settings() -> TileMapLayerSettings:
	var settings := TileMapLayerSettings.new()
	settings._settings_format_version = 1
	settings.tileset_texture = MapTerrainBuilder.atlas_texture(tileset)
	settings.tile_size = tileset.tile_size
	settings.autotile_tileset = tileset
	settings.mesh_mode = GlobalConstants.MeshMode.FLAT_SQUARE
	return settings

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
