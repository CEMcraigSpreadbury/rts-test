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

## Living units whose flat (XZ) distance to `pos` is within `radius`.
static func units_near(tree: SceneTree, pos: Vector3, radius: float) -> Array[Unit]:
	_ensure_built(tree)
	var result: Array[Unit] = []
	var min_cell := _cell_of(pos.x - radius, pos.z - radius)
	var max_cell := _cell_of(pos.x + radius, pos.z + radius)
	var radius_squared := radius * radius
	for x in range(min_cell.x, max_cell.x + 1):
		for y in range(min_cell.y, max_cell.y + 1):
			var bucket = _cells.get(Vector2i(x, y))
			if bucket == null:
				continue
			for unit in bucket:
				if not is_instance_valid(unit) or unit.status_activity == Unit.Activity.DEAD:
					continue
				var dx: float = unit.global_position.x - pos.x
				var dz: float = unit.global_position.z - pos.z
				if dx * dx + dz * dz <= radius_squared:
					result.append(unit)
	return result

static func _ensure_built(tree: SceneTree) -> void:
	var frame := Engine.get_physics_frames()
	if frame == _built_frame:
		return
	_built_frame = frame
	_cells.clear()
	for node in tree.get_nodes_in_group("units"):
		var unit := node as Unit
		if unit == null or unit.status_activity == Unit.Activity.DEAD:
			continue
		var key := _cell_of(unit.global_position.x, unit.global_position.z)
		if _cells.has(key):
			_cells[key].append(unit)
		else:
			_cells[key] = [unit]

static func _cell_of(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / CELL_SIZE), floori(z / CELL_SIZE))
