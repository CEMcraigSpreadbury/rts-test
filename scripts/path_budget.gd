class_name PathBudget
extends RefCounted
## Caps how many units may run a navmesh path query per physics frame. A path
## query is an A* search over the whole navmesh (tens of thousands of polygons
## on a hilly map), and whole armies ask for one on the same frame — a march
## releasing onto its slots, every unit re-pathing after a navmesh rebake, a
## big fight's chase repaths lining up. Units queue here first-come-first-served
## and steer straight at their target until their turn (see Unit._path_ready),
## so the burst is spread over a few frames instead of landing on one.

const PATHS_PER_FRAME: int = 6

static var _queue: Array[Unit] = []
static var _frame: int = -1
static var _iteration_frame: int = -1
static var _iteration: int = 0

## The navigation map's iteration id, read once per physics frame. It changes
## when the navmesh does (a rebake around a new building or a felled tree), and
## every agent then re-runs its path query on its next call — so a unit whose
## path predates it waits for its turn here like any other (Unit._path_ready).
static func map_iteration(map: RID) -> int:
	var frame := Engine.get_physics_frames()
	if frame != _iteration_frame:
		_iteration_frame = frame
		_iteration = NavigationServer3D.map_get_iteration_id(map)
	return _iteration

## Queues `unit` for a path query. Callers make sure a unit is only queued once.
static func enqueue(unit: Unit) -> void:
	_queue.append(unit)

## Hands out this frame's queries to the front of the queue, once per physics
## frame (on whichever unit asks first). A unit granted after it already ticked
## this frame simply uses the grant on its next tick; one that doesn't use it by
## then has stopped needing it, and has to queue again (see Unit._path_ready).
static func serve() -> void:
	var frame := Engine.get_physics_frames()
	if frame == _frame:
		return
	_frame = frame
	var granted := 0
	while granted < PATHS_PER_FRAME and not _queue.is_empty():
		## Untyped: a unit freed while queued can't be assigned to a Unit var.
		var entry = _queue.pop_front()
		if not is_instance_valid(entry) or not entry._path_queued:
			continue
		entry._path_granted_frame = frame
		granted += 1
