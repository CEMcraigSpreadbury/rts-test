class_name FogOfWar
extends Node3D
## Local-only fog of war, split across two very different-cost layers:
##  - "Currently visible" is smooth, moves every frame, and is cheap to get
##    exactly right — so it's computed analytically per-pixel in the shader
##    (see fog_of_war.gdshader) from the local player's own unit/building
##    positions, never rasterized onto a grid at all.
##  - "Explored" is a slow-changing memory of where you've ever been, where a
##    coarse grid is fine (it's dim, static, and nobody scrutinizes its edges)
##    — that part stays a baked low-res texture, updated a few times a second.
## Every peer computes their OWN fog independently from their OWN units'/
## buildings' positions — "what have I seen" is inherently per-viewer, like
## sprite flip_h and the rally marker, so none of this is networked.

signal fog_updated

## World-space rectangle the explored-memory grid covers; should match the terrain.
@export var map_origin: Vector2 = Vector2(-30, -30)
@export var map_size: Vector2 = Vector2(60, 60)
## The terrain's own MeshInstance3D — its fragment shader material must chain
## a ShaderMaterial using fog_of_war.gdshader via `next_pass` (see
## StandardMaterial3D_b6ruc/ShaderMaterial_terrain_fog in main.tscn). Fog used
## to be a separate floating overlay plane instead, but a flat plane can only
## ever hide things shorter than itself (raised terrain, tall props poked
## through) and can't be raised much before it clears the camera's own
## downward-only view rays entirely (see rts_camera.gd; min eye height is
## zoom_distance * sin(pitch_degrees), just 4.0 at min_zoom). Running the
## identical shader as a second pass directly on the terrain's own geometry
## instead means it naturally follows the terrain's real height/contours
## exactly, since it's reading the terrain's own vertices, not a proxy's.
## Units/buildings/tagged props are still hidden by toggling their own
## .visible off in _update_node_visibility() below, same as always — this is
## only about terrain, which can't be toggled the same way.
@export var terrain_mesh_path: NodePath
## Only affects how blocky the dim "remembered but not currently seen" areas
## look — current vision is a smooth analytic circle regardless of this value.
## Cell size is map_size / grid_resolution: this was tuned for the original
## 60x60 map (0.625 world units/cell); after extending the map to 168x150
## without raising this, cells grew to ~1.75x1.56 units and the blend looked
## chunky. 256 restores roughly the original density (~0.66/0.59 units/cell)
## — cheap to push higher still, _rebuild_texture()'s full-grid pass runs only
## a few times a second and grid_resolution^2 simple ops is trivial even at
## much larger sizes.
@export var grid_resolution: int = 256
@export var explored_update_interval: float = 0.15

## Must match MAX_VISION_SOURCES in fog_of_war.gdshader.
const MAX_VISION_SOURCES: int = 32

## explored[] no longer stores a plain 0/1 flag — it stores 0..255 "how
## strongly explored" per cell, with a smoothstep falloff baked in at stamp
## time (see _stamp_explored) instead of a hard in/out circle test. Relying on
## GPU bilinear filtering alone wasn't enough of a blend across only ~1-2 grid
## cells to hide the grid at this resolution; baking the falloff into the
## data itself gives a properly anti-aliased edge instead of a hard step.
const RGB_UNEXPLORED := Vector3(0.0, 0.0, 0.0)
const RGB_EXPLORED := Vector3(5.0, 8.0, 5.0)
const ALPHA_UNEXPLORED: float = 255.0
const ALPHA_EXPLORED: float = 153.0

var explored: PackedByteArray = PackedByteArray()
var fog_texture: ImageTexture

var _image: Image
var _pixel_data: PackedByteArray = PackedByteArray()
var _explored_timer: float = 0.0

## The local player's own vision sources this frame — (x, z) position + radius,
## kept as flat, fixed-size arrays (matching the shader's declared array size
## exactly, with _vision_count marking how many entries are actually in use)
## so they can be pushed straight into the shader uniforms and also used for
## exact (non-grid) is_visible_at() queries.
var _vision_positions: PackedVector2Array = PackedVector2Array()
var _vision_radii: PackedFloat32Array = PackedFloat32Array()
var _vision_count: int = 0

## Deliberately created here at runtime rather than saved as a next_pass in
## the .tscn — a next_pass baked into the scene file renders in the EDITOR'S
## own 3D viewport too (with garbage default uniforms, since nothing drives
## them outside of Play), making the terrain unusable to look at while
## building maps. Chaining it here instead means the terrain's saved material
## never has a next_pass on disk at all; it only exists in memory while the
## game is actually running, so the editor view stays permanently clean with
## nothing to remember to toggle.
@onready var _material: ShaderMaterial = _setup_terrain_fog_material()

## Grass layers painted with the Grass Painter editor plugin (addons/grass_painter)
## get fog support wired straight onto their own material's uniforms (see
## grass_wind.gdshader's fog_enabled/fog_tex/fog_map_origin/.../fog_vision_*)
## rather than a chained next_pass — a next_pass was tried first but relies
## on every grass layer's node already being in the tree by the time this
## node's _ready() runs, which sibling order in the scene doesn't guarantee
## (this project already hit that same class of ordering bug once before,
## with Objective guard ownership).
##
## Found by matching the shader itself (any MultiMeshInstance3D anywhere in
## the tree whose material uses grass_wind.gdshader), not a "fog_grass" group
## tag — a tag would only ever get added to a layer the next time it's
## selected/created in the dock, silently leaving every layer painted before
## this fix (or a scene resave) unfogged forever. Matching by shader instead
## means every grass layer gets fog for free, with nothing to remember to redo.
const GRASS_SHADER: Shader = preload("res://shaders/grass_wind.gdshader")
var _grass_materials: Array[ShaderMaterial] = []

func _setup_terrain_fog_material() -> ShaderMaterial:
	var terrain_material: Material = get_node(terrain_mesh_path).get_active_material(0)
	var fog_material := ShaderMaterial.new()
	fog_material.shader = preload("res://shaders/fog_of_war.gdshader")
	terrain_material.next_pass = fog_material
	return fog_material

func _setup_grass_fog_materials() -> void:
	_grass_materials.clear()
	_find_grass_materials(get_tree().root)

func _find_grass_materials(node: Node) -> void:
	if node is MultiMeshInstance3D:
		var grass_material := (node as MultiMeshInstance3D).material_override as ShaderMaterial
		if grass_material and grass_material.shader == GRASS_SHADER:
			grass_material.set_shader_parameter("fog_enabled", true)
			grass_material.set_shader_parameter("fog_tex", fog_texture)
			grass_material.set_shader_parameter("fog_map_origin", map_origin)
			grass_material.set_shader_parameter("fog_map_size", map_size)
			_grass_materials.append(grass_material)
	for child in node.get_children():
		_find_grass_materials(child)

func _ready() -> void:
	var cell_count := grid_resolution * grid_resolution
	explored.resize(cell_count)
	_pixel_data.resize(cell_count * 4)

	_image = Image.create(grid_resolution, grid_resolution, false, Image.FORMAT_RGBA8)
	_image.fill(Color.BLACK)
	fog_texture = ImageTexture.create_from_image(_image)

	_material.set_shader_parameter("fog_tex", fog_texture)
	_material.set_shader_parameter("map_origin", map_origin)
	_material.set_shader_parameter("map_size", map_size)

	call_deferred("_setup_grass_fog_materials")

	_vision_positions.resize(MAX_VISION_SOURCES)
	_vision_radii.resize(MAX_VISION_SOURCES)

	_update_vision_sources()
	_push_vision_to_shader()
	_update_explored()

func _process(delta: float) -> void:
	## Vision sources move every frame, so this (and the shader push) runs
	## every frame too — it's just a handful of floats, not a texture rebuild.
	_update_vision_sources()
	_push_vision_to_shader()

	_explored_timer += delta
	if _explored_timer < explored_update_interval:
		return
	_explored_timer = 0.0
	_update_explored()

## Peer 0 is the neutral/AI-owner sentinel (Gatherable, Objective guards
## before capture) — never a real player, so it must never be treated as
## "mine" here even though multiplayer.get_unique_id() degrades to 0 (instead
## of the usual 1) in the direct-run-main.tscn-bypassing-the-lobby test
## workflow. Without this guard, that mode wrongly grants full vision from
## every un-captured Objective's guards, and _update_node_visibility() below
## wrongly renders them (and their buildings) through the fog entirely.
func _update_vision_sources() -> void:
	_vision_count = 0
	var my_peer := multiplayer.get_unique_id()
	if my_peer == 0:
		return

	for node in get_tree().get_nodes_in_group("units"):
		if _vision_count >= MAX_VISION_SOURCES:
			break
		var unit := node as Unit
		if unit and unit.owner_peer_id == my_peer and unit.status_activity != Unit.Activity.DEAD:
			_vision_positions[_vision_count] = Vector2(unit.global_position.x, unit.global_position.z)
			_vision_radii[_vision_count] = unit.vision_range
			_vision_count += 1

	for node in get_tree().get_nodes_in_group("buildings"):
		if _vision_count >= MAX_VISION_SOURCES:
			break
		var building := node as ProductionBuilding
		if building and building.owner_peer_id == my_peer and not building.is_destroyed:
			_vision_positions[_vision_count] = Vector2(building.global_position.x, building.global_position.z)
			_vision_radii[_vision_count] = building.vision_range
			_vision_count += 1

func _push_vision_to_shader() -> void:
	## _vision_positions/_vision_radii are always exactly MAX_VISION_SOURCES
	## long (fixed-size, matching the shader's array uniforms); only the
	## first _vision_count entries are meaningful, and the shader never reads
	## past vision_count either, so the unused tail is harmless.
	_material.set_shader_parameter("vision_count", _vision_count)
	_material.set_shader_parameter("vision_positions", _vision_positions)
	_material.set_shader_parameter("vision_radii", _vision_radii)
	## grass_wind.gdshader's fog uniforms are named with a fog_ prefix (see
	## that shader) since it also has its own unrelated uniforms — different
	## names than fog_of_war.gdshader's, same values.
	for grass_material in _grass_materials:
		grass_material.set_shader_parameter("fog_vision_count", _vision_count)
		grass_material.set_shader_parameter("fog_vision_positions", _vision_positions)
		grass_material.set_shader_parameter("fog_vision_radii", _vision_radii)

## Exact (not grid-quantized) check against this tick's own vision sources —
## smoother and cheaper than a lookup into a rasterized grid would be, since
## there are only ever a handful of these to check against.
func is_visible_at(world_pos: Vector3) -> bool:
	var p := Vector2(world_pos.x, world_pos.z)
	for i in _vision_count:
		if p.distance_to(_vision_positions[i]) <= _vision_radii[i]:
			return true
	return false

func _world_to_cell(world_pos: Vector3) -> Vector2i:
	var u := (world_pos.x - map_origin.x) / map_size.x
	var v := (world_pos.z - map_origin.y) / map_size.y
	return Vector2i(int(u * grid_resolution), int(v * grid_resolution))

func is_explored_at(world_pos: Vector3) -> bool:
	var c := _world_to_cell(world_pos)
	if c.x < 0 or c.x >= grid_resolution or c.y < 0 or c.y >= grid_resolution:
		return false
	return explored[c.y * grid_resolution + c.x] != 0

## Writes a smoothstep falloff (255 deep inside the circle, fading to 0 over
## the outer ~15% of the radius) rather than a hard 1/0 cutoff, so the grid
## itself holds an anti-aliased edge instead of depending on texture
## filtering to hide a single hard step. Cells already explored by an earlier,
## stronger stamp are never dimmed back down (max, not overwrite).
func _stamp_explored(world_pos: Vector3, world_radius: float) -> void:
	var center := _world_to_cell(world_pos)
	var cell_size_x: float = map_size.x / float(grid_resolution)
	var cell_size_y: float = map_size.y / float(grid_resolution)
	var cell_radius_x: int = int(ceil(world_radius / cell_size_x))
	var cell_radius_y: int = int(ceil(world_radius / cell_size_y))
	for dy in range(-cell_radius_y, cell_radius_y + 1):
		var y := center.y + dy
		if y < 0 or y >= grid_resolution:
			continue
		for dx in range(-cell_radius_x, cell_radius_x + 1):
			var x := center.x + dx
			if x < 0 or x >= grid_resolution:
				continue
			var world_dx := dx * cell_size_x
			var world_dy := dy * cell_size_y
			var dist := sqrt(world_dx * world_dx + world_dy * world_dy)
			if dist > world_radius:
				continue
			var falloff := 1.0 - smoothstep(world_radius * 0.85, world_radius, dist)
			var value := int(round(falloff * 255.0))
			var idx := y * grid_resolution + x
			explored[idx] = maxi(explored[idx], value)

func _update_explored() -> void:
	for i in _vision_count:
		var pos := _vision_positions[i]
		_stamp_explored(Vector3(pos.x, 0.0, pos.y), _vision_radii[i])

	_rebuild_texture()
	_update_node_visibility()
	fog_updated.emit()

func _rebuild_texture() -> void:
	var cell_count := grid_resolution * grid_resolution
	for i in range(cell_count):
		var t: float = float(explored[i]) / 255.0
		var offset := i * 4
		_pixel_data[offset] = int(lerp(RGB_UNEXPLORED.x, RGB_EXPLORED.x, t))
		_pixel_data[offset + 1] = int(lerp(RGB_UNEXPLORED.y, RGB_EXPLORED.y, t))
		_pixel_data[offset + 2] = int(lerp(RGB_UNEXPLORED.z, RGB_EXPLORED.z, t))
		_pixel_data[offset + 3] = int(lerp(ALPHA_UNEXPLORED, ALPHA_EXPLORED, t))
	_image.set_data(grid_resolution, grid_resolution, false, Image.FORMAT_RGBA8, _pixel_data)
	fog_texture.update(_image)

## Enemy units only render while actually in vision (they move, so a stale
## position would be misleading). Enemy buildings and neutral resource nodes
## don't move, so once explored they stay visible at their known position —
## same "remembered map" idea classic RTS fog uses for static structures.
func _update_node_visibility() -> void:
	## 0 is never really "mine" — see the guard/comment in _update_vision_sources().
	var my_peer := multiplayer.get_unique_id()
	var i_am_valid_peer := my_peer != 0

	for node in get_tree().get_nodes_in_group("units"):
		var unit := node as Unit
		if unit:
			unit.visible = (i_am_valid_peer and unit.owner_peer_id == my_peer) or is_visible_at(unit.global_position)

	for node in get_tree().get_nodes_in_group("buildings"):
		var building := node as ProductionBuilding
		if building:
			building.visible = (i_am_valid_peer and building.owner_peer_id == my_peer) or is_explored_at(building.global_position)

	for node in get_tree().get_nodes_in_group("gatherables"):
		var res := node as Gatherable
		if res:
			res.visible = is_explored_at(res.global_position)

	## Purely decorative scenery (imported models with no Unit/ProductionBuilding
	## script attached, e.g. an Objective's terrain dressing) — add "fog_static_props"
	## to a node's Groups in the Inspector to have fog hide it too. Same "remembered
	## map" rule as buildings/gatherables above: once explored it stays visible,
	## since it's static and being wrong about its remembered appearance never
	## matters the way a stale unit position would.
	for node in get_tree().get_nodes_in_group("fog_static_props"):
		var prop := node as Node3D
		if prop:
			prop.visible = is_explored_at(prop.global_position)
