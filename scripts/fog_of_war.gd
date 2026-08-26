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

## World-space rectangle the explored-memory grid covers; should match the ground plane.
@export var map_origin: Vector2 = Vector2(-30, -30)
@export var map_size: Vector2 = Vector2(60, 60)
## Only affects how blocky the dim "remembered but not currently seen" areas
## look — current vision is a smooth analytic circle regardless of this value,
## so there's no reason to push it high anymore.
@export var grid_resolution: int = 96
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

@onready var _mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var _material: ShaderMaterial = _mesh_instance.get_surface_override_material(0)

func _ready() -> void:
	var cell_count := grid_resolution * grid_resolution
	explored.resize(cell_count)
	_pixel_data.resize(cell_count * 4)

	_image = Image.create(grid_resolution, grid_resolution, false, Image.FORMAT_RGBA8)
	_image.fill(Color.BLACK)
	fog_texture = ImageTexture.create_from_image(_image)

	var mesh: PlaneMesh = _mesh_instance.mesh
	mesh.size = map_size
	_mesh_instance.position = Vector3(
		map_origin.x + map_size.x * 0.5, 0.05, map_origin.y + map_size.y * 0.5
	)

	_material.set_shader_parameter("fog_tex", fog_texture)
	_material.set_shader_parameter("map_origin", map_origin)
	_material.set_shader_parameter("map_size", map_size)

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

func _update_vision_sources() -> void:
	_vision_count = 0
	var my_peer := multiplayer.get_unique_id()

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
	var my_peer := multiplayer.get_unique_id()

	for node in get_tree().get_nodes_in_group("units"):
		var unit := node as Unit
		if unit:
			unit.visible = unit.owner_peer_id == my_peer or is_visible_at(unit.global_position)

	for node in get_tree().get_nodes_in_group("buildings"):
		var building := node as ProductionBuilding
		if building:
			building.visible = building.owner_peer_id == my_peer or is_explored_at(building.global_position)

	for node in get_tree().get_nodes_in_group("gatherables"):
		var res := node as Gatherable
		if res:
			res.visible = is_explored_at(res.global_position)
