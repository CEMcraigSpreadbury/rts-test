class_name Forest
extends Node3D
## Every tree on the map, drawn and looked up as data rather than as thousands
## of heavy nodes.
##
## A tree used to be a StaticBody3D with a collision cylinder, a navigation
## obstacle, a sound player and a model holding a billboard sprite — about six
## nodes, a physics body and a sprite each. On a 1 km map that was 8,000 trees
## and 50,000 nodes, and every one of them was rescanned whenever anything on
## the map changed. Now a tree keeps only its Gatherable node (units, the AI
## and multiplayer still refer to it by path), and this node does the rest:
##   — drawing: one MultiMesh per CHUNK_SIZE square, so a whole patch of forest
##     is a single draw and one off-screen is culled whole;
##   — finding: a CELL_SIZE grid answers "trees near here", clicks (pick) and
##     building placement, instead of physics;
##   — blocking: ArmyBridge and NavigationBlockers read each trunk as a circle
##     (Gatherable.trunk_radius) and hear about felled ones through
##     tree_removed, instead of rescanning collision shapes;
##   — fog: trees stay hidden until their spot is explored, as before.
## The map's border trees (plain scenery models) are drawn here too, as
## decoration with no Gatherable behind them.

## A tree has left the forest (felled) from `position`. `id` is the instance id its blocker
## was stamped under.
signal tree_removed(id: int, position: Vector3)

## Metres per drawing chunk.
const CHUNK_SIZE: float = 64.0
## Metres per lookup cell.
const CELL_SIZE: float = 8.0
## What a click can hit: a little wider than the trunk and up into the canopy,
## so clicking the leaves picks the tree rather than the ground behind it.
const PICK_RADIUS: float = 0.7
const PICK_HEIGHT: float = 5.0
## Fog checks per frame once the first full pass is done.
const FOG_CHECKS_PER_UPDATE: int = 2000
## The harvest squash (see Gatherable.play_harvest_squash).
const SQUASH_SCALE: Vector3 = Vector3(1.07, 0.88, 1.07)
const SQUASH_SECONDS: float = 0.4
const BILLBOARD_SHADER: Shader = preload("res://shaders/forest_billboard.gdshader")
## Billboards blend their soft edges, so each chunk draws far to near: sorted
## along the camera's flat facing, which panning never changes — only turning
## the camera by more than this re-sorts, a few chunks a frame.
const SORT_ANGLE: float = deg_to_rad(4.0)
const SORTS_PER_FRAME: int = 6

## The forest of the map being played. Set by attach().
static var active: Forest = null

class Entry:
	## Null for decoration (border trees).
	var tree: Gatherable = null
	## Where the model stood (the tree's model child, or the scenery node).
	var xform: Transform3D
	var position: Vector3
	## Sheet region in UVs, w negative when flipped (see forest_billboard).
	var region: Color
	var model_path: String = ""
	var chunk: Vector2i
	var index: int = -1
	var alive: bool = true
	var revealed: bool = true
	var squash_time: float = -1.0

class Chunk:
	var entries: Array[Entry] = []
	var billboards: MultiMeshInstance3D = null
	## model scene path -> Array[MultiMeshInstance3D], one per mesh in it.
	var models: Dictionary = {}
	var dirty: bool = true

var _chunks: Dictionary = {}
var _cells: Dictionary = {}
var _by_tree: Dictionary = {}
var _fog_pending: Array[Entry] = []
var _fog_started: bool = false
var _fog_cursor: int = 0
var _squashing: Array[Entry] = []
var _billboards_on: bool = true
var _billboard_mesh: ArrayMesh = null
var _billboard_material: ShaderMaterial = null
## model scene path -> Array of [mesh with its materials set, local transform].
var _model_parts: Dictionary = {}
var _select_player: AudioStreamPlayer = null
## The flat camera facing chunks are sorted for, and the chunks still to do.
var _sort_facing: Vector2 = Vector2.ZERO
var _sort_queue: Array[Vector2i] = []

## The forest that trees under `node`'s map register with. One per map root,
## made on first use: trees ready before Main does, and attach() then puts it
## in the tree.
static func for_node(node: Node) -> Forest:
	var root: Node = node.owner if node.owner != null else node.get_parent()
	if root == null:
		root = node
	if root.has_meta(&"forest"):
		var existing = root.get_meta(&"forest")
		if is_instance_valid(existing):
			return existing
	var forest := Forest.new()
	forest.name = "Forest"
	root.set_meta(&"forest", forest)
	return forest

## Puts `root`'s forest (made already by its trees, or new) under it and makes
## it the active one.
static func attach(root: Node) -> Forest:
	var forest: Forest = null
	if root.has_meta(&"forest") and is_instance_valid(root.get_meta(&"forest")):
		forest = root.get_meta(&"forest")
	else:
		forest = Forest.new()
		forest.name = "Forest"
		root.set_meta(&"forest", forest)
	if forest.get_parent() == null:
		root.add_child(forest)
	active = forest
	return forest

func _init() -> void:
	_billboards_on = TreeBillboard.enabled
	_billboard_mesh = _make_quad()
	_billboard_material = ShaderMaterial.new()
	_billboard_material.shader = BILLBOARD_SHADER
	_billboard_material.set_shader_parameter(&"sheet", TreeBillboard.SHEET)
	_billboard_material.set_shader_parameter(&"pixel_size", TreeBillboard.PIXEL_SIZE)
	_billboard_material.set_shader_parameter(&"sink", TreeBillboard.SINK)

func _ready() -> void:
	_select_player = AudioStreamPlayer.new()
	_select_player.bus = &"SFX"
	add_child(_select_player)

func _exit_tree() -> void:
	if active == self:
		active = null

## --- Adding and removing ---

## A tree, taking over its model: the model node itself is freed.
func add_tree(tree: Gatherable, model: Node3D) -> void:
	var entry := Entry.new()
	entry.tree = tree
	entry.xform = model.global_transform if model != null else tree.global_transform
	entry.model_path = model.scene_file_path if model != null else ""
	_add(entry)
	_by_tree[tree.get_instance_id()] = entry
	var cell := _cell_of(entry.position)
	if not _cells.has(cell):
		_cells[cell] = []
	_cells[cell].append(entry)

## A scenery tree model: drawn and fogged like any tree, but not gatherable,
## solid or clickable. The node is left for the caller to free.
func add_decoration(model: Node3D) -> void:
	var entry := Entry.new()
	entry.xform = model.global_transform
	entry.model_path = model.scene_file_path
	_add(entry)

func _add(entry: Entry) -> void:
	entry.position = entry.xform.origin
	## Same seeded pick TreeBillboard made per sprite, so every tree keeps the
	## picture it had (and every peer agrees).
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(roundi(entry.position.x * 10.0), roundi(entry.position.z * 10.0)))
	var region: Rect2 = TreeBillboard.REGIONS[rng.randi() % TreeBillboard.REGIONS.size()]
	var flip: bool = rng.randi() % 2 == 0
	var sheet := Vector2(TreeBillboard.SHEET.get_size())
	entry.region = Color(region.position.x / sheet.x, region.position.y / sheet.y,
			(region.size.x / sheet.x) * (-1.0 if flip else 1.0), region.size.y / sheet.y)
	entry.chunk = Vector2i(floori(entry.position.x / CHUNK_SIZE), floori(entry.position.z / CHUNK_SIZE))
	if not _chunks.has(entry.chunk):
		_chunks[entry.chunk] = Chunk.new()
	var chunk: Chunk = _chunks[entry.chunk]
	entry.index = chunk.entries.size()
	chunk.entries.append(entry)
	chunk.dirty = true
	_fog_pending.append(entry)

## `tree` was felled: stops drawing, blocking and being found.
func remove_tree(tree: Gatherable) -> void:
	var id: int = tree.get_instance_id()
	var entry: Entry = _by_tree.get(id)
	if entry == null or not entry.alive:
		return
	entry.alive = false
	_by_tree.erase(id)
	var cell: Array = _cells.get(_cell_of(entry.position), [])
	cell.erase(entry)
	_refresh_instance(entry)
	tree_removed.emit(id, entry.position)

## --- Queries ---

## Standing trees within `radius` of `centre` (flat distance).
func trees_in_circle(centre: Vector3, radius: float) -> Array[Gatherable]:
	var found: Array[Gatherable] = []
	var reach_sq: float = radius * radius
	for entry in _entries_near(centre, radius):
		var dx: float = entry.position.x - centre.x
		var dz: float = entry.position.z - centre.z
		if dx * dx + dz * dz <= reach_sq:
			found.append(entry.tree)
	return found

## Whether any standing trunk reaches into the circle.
func any_trunk_within(centre: Vector3, radius: float) -> bool:
	for entry in _entries_near(centre, radius + 1.0):
		var reach: float = radius + entry.tree.trunk_radius
		var dx: float = entry.position.x - centre.x
		var dz: float = entry.position.z - centre.z
		if dx * dx + dz * dz < reach * reach:
			return true
	return false

## Every standing tree.
func all_trees() -> Array[Gatherable]:
	var found: Array[Gatherable] = []
	for entry: Entry in _by_tree.values():
		found.append(entry.tree)
	return found

## The nearest tree a ray from the camera meets before `max_distance`, as a
## raycast-style result ({collider, position, distance}), or empty. Trees are
## upright cylinders PICK_RADIUS wide and PICK_HEIGHT tall; only unfogged ones
## count, as a hidden tree never had a collider you could click either (fog
## hid the model but the old physics body still answered — this is stricter).
func pick(from: Vector3, dir: Vector3, max_distance: float) -> Dictionary:
	var flat := Vector2(dir.x, dir.z)
	if flat.length_squared() < 0.000001:
		return {}
	var best: Entry = null
	var best_t: float = max_distance
	## Walk the ray's ground track cell by cell, one cell to either side.
	var steps: int = ceili(max_distance * flat.length() / CELL_SIZE) + 1
	var seen: Dictionary = {}
	for s in steps:
		var at: Vector3 = from + dir * (s * CELL_SIZE / flat.length())
		if s * CELL_SIZE / flat.length() > best_t + CELL_SIZE * 2.0:
			break
		var base := _cell_of(at)
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var key := Vector2i(base.x + dx, base.y + dz)
				if seen.has(key):
					continue
				seen[key] = true
				for entry: Entry in _cells.get(key, []):
					if not entry.revealed:
						continue
					var t: float = _ray_hits_trunk(from, dir, entry.position)
					if t >= 0.0 and t < best_t:
						best_t = t
						best = entry
	if best == null:
		return {}
	return {collider = best.tree, position = from + dir * best_t, distance = best_t}

static func _ray_hits_trunk(from: Vector3, dir: Vector3, base: Vector3) -> float:
	var ox: float = from.x - base.x
	var oz: float = from.z - base.z
	var a: float = dir.x * dir.x + dir.z * dir.z
	var b: float = 2.0 * (ox * dir.x + oz * dir.z)
	var c: float = ox * ox + oz * oz - PICK_RADIUS * PICK_RADIUS
	var disc: float = b * b - 4.0 * a * c
	if disc < 0.0:
		return -1.0
	var root: float = sqrt(disc)
	for t: float in [(-b - root) / (2.0 * a), (-b + root) / (2.0 * a)]:
		if t < 0.0:
			continue
		var y: float = from.y + dir.y * t
		if y >= base.y and y <= base.y + PICK_HEIGHT:
			return t
	return -1.0

func _entries_near(centre: Vector3, radius: float) -> Array[Entry]:
	var found: Array[Entry] = []
	var lo := _cell_of(centre - Vector3(radius, 0.0, radius))
	var hi := _cell_of(centre + Vector3(radius, 0.0, radius))
	for z in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			for entry: Entry in _cells.get(Vector2i(x, z), []):
				found.append(entry)
	return found

static func _cell_of(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / CELL_SIZE), floori(pos.z / CELL_SIZE))

## --- Feedback ---

func squash(tree: Gatherable) -> void:
	var entry: Entry = _by_tree.get(tree.get_instance_id())
	if entry == null:
		return
	if entry.squash_time < 0.0:
		_squashing.append(entry)
	entry.squash_time = 0.0

func play_select(sounds: Array[AudioStream]) -> void:
	AudioUtils.play_random(_select_player, sounds)

## --- Fog ---

## Called by FogOfWar with the rest of its visibility pass. The first pass
## checks every tree (so nothing unexplored is ever drawn); later ones work
## through the still-hidden rest a slice at a time. Explored ground never
## becomes unexplored, so a tree is checked until it shows and never again.
func update_fog(fog: FogOfWar) -> void:
	if not _fog_started:
		_fog_started = true
		var i := _fog_pending.size() - 1
		while i >= 0:
			var entry: Entry = _fog_pending[i]
			if fog.is_explored_at(entry.position):
				_fog_pending[i] = _fog_pending[_fog_pending.size() - 1]
				_fog_pending.pop_back()
			else:
				entry.revealed = false
				_refresh_instance(entry)
			i -= 1
		return
	var checks: int = mini(FOG_CHECKS_PER_UPDATE, _fog_pending.size())
	for n in checks:
		if _fog_pending.is_empty():
			return
		_fog_cursor = _fog_cursor % _fog_pending.size()
		var entry: Entry = _fog_pending[_fog_cursor]
		if fog.is_explored_at(entry.position):
			entry.revealed = true
			_refresh_instance(entry)
			_fog_pending[_fog_cursor] = _fog_pending[_fog_pending.size() - 1]
			_fog_pending.pop_back()
		else:
			_fog_cursor += 1

## --- Drawing ---

## Billboards or 3D models (TreeBillboard's F10 test toggle).
func set_billboards(on: bool) -> void:
	_billboards_on = on
	for chunk: Chunk in _chunks.values():
		chunk.dirty = true

func _process(delta: float) -> void:
	_sort_for_camera()
	for key in _chunks:
		var chunk: Chunk = _chunks[key]
		if chunk.dirty:
			_build_chunk(key, chunk)
	var i := _squashing.size() - 1
	while i >= 0:
		var entry: Entry = _squashing[i]
		entry.squash_time += delta
		if entry.squash_time >= SQUASH_SECONDS or not entry.alive:
			entry.squash_time = -1.0
			_squashing.remove_at(i)
		_refresh_instance(entry)
		i -= 1

func _sort_for_camera() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var forward := Vector2(-camera.global_basis.z.x, -camera.global_basis.z.z)
	if forward.length_squared() < 0.0001:
		return
	forward = forward.normalized()
	if _sort_facing == Vector2.ZERO or absf(_sort_facing.angle_to(forward)) > SORT_ANGLE:
		_sort_facing = forward
		_sort_queue.assign(_chunks.keys())
	for n in mini(SORTS_PER_FRAME, _sort_queue.size()):
		var chunk: Chunk = _chunks.get(_sort_queue.pop_back())
		if chunk != null:
			_sort_chunk(chunk)

## Far first, so nearer trees blend over them.
func _sort_chunk(chunk: Chunk) -> void:
	var facing := _sort_facing
	chunk.entries.sort_custom(func(a: Entry, b: Entry) -> bool:
		return a.position.x * facing.x + a.position.z * facing.y > b.position.x * facing.x + b.position.z * facing.y)
	for i in chunk.entries.size():
		chunk.entries[i].index = i
	chunk.dirty = true

func _build_chunk(key: Vector2i, chunk: Chunk) -> void:
	chunk.dirty = false
	var aabb := _chunk_aabb(key, chunk)
	if _billboards_on:
		if chunk.billboards == null:
			chunk.billboards = _make_instance(_billboard_mesh, chunk.entries.size(), true, aabb)
			chunk.billboards.material_override = _billboard_material
		_fit(chunk.billboards, chunk.entries.size(), aabb)
		chunk.billboards.visible = true
	elif chunk.billboards != null:
		chunk.billboards.visible = false
	for path in chunk.models:
		for mmi: MultiMeshInstance3D in chunk.models[path]:
			_fit(mmi, chunk.entries.size(), aabb)
			mmi.visible = not _billboards_on
	if not _billboards_on:
		var paths: Dictionary = {}
		for entry in chunk.entries:
			if not entry.model_path.is_empty():
				paths[entry.model_path] = true
		for path in paths:
			if chunk.models.has(path):
				continue
			var list: Array = []
			for part in _parts_for(path):
				list.append(_make_instance(part[0], chunk.entries.size(), false, aabb))
			chunk.models[path] = list
	for entry in chunk.entries:
		_refresh_instance(entry)

func _make_instance(mesh: Mesh, count: int, custom: bool, aabb: AABB) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = custom
	multimesh.mesh = mesh
	multimesh.instance_count = count
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = multimesh
	mmi.custom_aabb = aabb
	add_child(mmi)
	return mmi

## A chunk that gained trees since it was built needs room for them.
static func _fit(mmi: MultiMeshInstance3D, count: int, aabb: AABB) -> void:
	if mmi.multimesh.instance_count != count:
		mmi.multimesh.instance_count = count
		mmi.custom_aabb = aabb

## Writes `entry`'s instance in every multimesh of its chunk: its place (or a
## zero basis when felled or fogged), squashed if mid-squash, and its region.
func _refresh_instance(entry: Entry) -> void:
	var chunk: Chunk = _chunks[entry.chunk]
	var xform: Transform3D = entry.xform
	if not entry.alive or not entry.revealed:
		xform.basis = Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	elif entry.squash_time >= 0.0:
		var scale: Vector3 = Tween.interpolate_value(SQUASH_SCALE, Vector3.ONE - SQUASH_SCALE,
				entry.squash_time, SQUASH_SECONDS, Tween.TRANS_ELASTIC, Tween.EASE_OUT)
		xform.basis = xform.basis * Basis.from_scale(scale)
	if chunk.dirty:
		return
	if chunk.billboards != null:
		chunk.billboards.multimesh.set_instance_transform(entry.index, xform)
		chunk.billboards.multimesh.set_instance_custom_data(entry.index, entry.region)
	for path in chunk.models:
		var parts: Array = _parts_for(path)
		var list: Array = chunk.models[path]
		for p in list.size():
			var part_xform: Transform3D = xform * parts[p][1] if path == entry.model_path else Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), xform.origin)
			(list[p] as MultiMeshInstance3D).multimesh.set_instance_transform(entry.index, part_xform)

## Bounds that hold every billboard in the chunk whichever way the camera
## looks: MultiMesh would size them off the unit quad otherwise.
func _chunk_aabb(key: Vector2i, chunk: Chunk) -> AABB:
	var low: float = INF
	var high: float = -INF
	for entry in chunk.entries:
		low = minf(low, entry.position.y)
		high = maxf(high, entry.position.y)
	var margin: float = 8.0
	return AABB(Vector3(key.x * CHUNK_SIZE - margin, low - 1.0, key.y * CHUNK_SIZE - margin),
			Vector3(CHUNK_SIZE + margin * 2.0, high - low + 12.0, CHUNK_SIZE + margin * 2.0))

## A 3D tree model's meshes, each with its (baked, windy) materials set on a
## copy of the mesh, and where it sits in the model.
func _parts_for(path: String) -> Array:
	if _model_parts.has(path):
		return _model_parts[path]
	var parts: Array = []
	var scene := load(path) as PackedScene
	if scene != null:
		var model: Node3D = scene.instantiate()
		BakedLightingMaterial.apply_to(model)
		TreeWind.apply_to_trees_in(model)
		_collect_parts(model, Transform3D.IDENTITY, parts, true)
		model.free()
	_model_parts[path] = parts
	return parts

func _collect_parts(node: Node, to_root: Transform3D, parts: Array, is_root: bool) -> void:
	var here: Transform3D = to_root
	if not is_root and node is Node3D:
		here = to_root * (node as Node3D).transform
	if node is MeshInstance3D and node.mesh != null:
		var mesh_instance: MeshInstance3D = node
		var mesh: Mesh = mesh_instance.mesh.duplicate()
		for i in mesh.get_surface_count():
			mesh.surface_set_material(i, mesh_instance.get_active_material(i))
		parts.append([mesh, here])
	for child in node.get_children():
		_collect_parts(child, here, parts, false)

static func _make_quad() -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-0.5, 0.0, 0.0), Vector3(0.5, 0.0, 0.0), Vector3(0.5, 1.0, 0.0), Vector3(-0.5, 1.0, 0.0)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1, 0, 3, 2])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
