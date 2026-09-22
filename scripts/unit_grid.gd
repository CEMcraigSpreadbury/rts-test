extends RefCounted
## Host-side spatial hash over every living Unit, rebuilt lazily at most once
## per physics frame (on the first query of that frame). Lets a neighbour query
## look at a handful of nearby cells instead of every unit on the map — used by
## Unit's separation push and melee crowding checks, which run for every unit.
## Positions are as of the rebuild, so a unit that moved earlier in the same
## frame is off by at most one frame's travel, which none of the callers mind.

const CELL_SIZE: float = 2.0

static var _built_frame: int = -1
static var _cells: Dictionary = {}
## The same, split by owner: owner_peer_id -> {cell -> [units]}.
static var _owner_cells: Dictionary = {}

## Living units whose flat (XZ) distance to `pos` is within `radius`.
static func units_near(tree: SceneTree, pos: Vector3, radius: float) -> Array[Unit]:
	_ensure_built(tree)
	var result: Array[Unit] = []
	_collect(_cells, pos, radius, result)
	return result

## Like units_near, but only units hostile to `owner_peer_id` — without
## walking past every friendly unit in range to find them. An army standing
## guard scans for enemies every quarter second, and its own ranks were
## nearly all of what those scans looked at.
static func enemies_near(tree: SceneTree, pos: Vector3, radius: float, owner_peer_id: int) -> Array[Unit]:
	_ensure_built(tree)
	var result: Array[Unit] = []
	for owner in _owner_cells:
		if Teams.is_enemy(owner_peer_id, owner):
			_collect(_owner_cells[owner], pos, radius, result)
	return result

static func _collect(cells: Dictionary, pos: Vector3, radius: float, result: Array[Unit]) -> void:
	var min_cell := _cell_of(pos.x - radius, pos.z - radius)
	var max_cell := _cell_of(pos.x + radius, pos.z + radius)
	var radius_squared := radius * radius
	for x in range(min_cell.x, max_cell.x + 1):
		for y in range(min_cell.y, max_cell.y + 1):
			var bucket = cells.get(Vector2i(x, y))
			if bucket == null:
				continue
			for unit in bucket:
				if not is_instance_valid(unit) or unit.status_activity == Unit.Activity.DEAD:
					continue
				var dx: float = unit.global_position.x - pos.x
				var dz: float = unit.global_position.z - pos.z
				if dx * dx + dz * dz <= radius_squared:
					result.append(unit)

static func _ensure_built(tree: SceneTree) -> void:
	var frame := Engine.get_physics_frames()
	if frame == _built_frame:
		return
	_built_frame = frame
	if not PerfStats.enabled:
		_rebuild(tree)
		return
	var start := Time.get_ticks_usec()
	_rebuild(tree)
	PerfStats.add_unit_section(&"grid rebuild", Time.get_ticks_usec() - start)

static func _rebuild(tree: SceneTree) -> void:
	_cells.clear()
	_owner_cells.clear()
	for node in tree.get_nodes_in_group("units"):
		var unit := node as Unit
		if unit == null or unit.status_activity == Unit.Activity.DEAD:
			continue
		var key := _cell_of(unit.global_position.x, unit.global_position.z)
		if _cells.has(key):
			_cells[key].append(unit)
		else:
			_cells[key] = [unit]
		var owned: Dictionary = _owner_cells.get(unit.owner_peer_id, {})
		if owned.is_empty():
			_owner_cells[unit.owner_peer_id] = owned
		if owned.has(key):
			owned[key].append(unit)
		else:
			owned[key] = [unit]

static func _cell_of(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / CELL_SIZE), floori(z / CELL_SIZE))
