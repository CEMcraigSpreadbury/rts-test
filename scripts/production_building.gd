class_name ProductionBuilding
extends StaticBody3D
## Generic producing building. One reusable scene/script pair: what a specific
## building "is" (Town Center, Barracks, ...) is entirely defined by the
## `building_name` and `producibles` configured on the instance in the inspector.
## The build menu UI reads `producibles` to know what buttons to show.
##
## Only the host ever actually runs the queue/construction simulation (see the
## is_multiplayer_authority() guard in _process); everyone else just displays
## the handful of fields below that are kept in sync for the UI.

signal queue_changed
signal item_completed(item: ProducibleItem)
signal construction_finished

@export var building_name: String = "Production Building"
@export var producibles: Array[ProducibleItem] = []
## Which player owns this building; only they may queue production on it.
@export var owner_peer_id: int = 1
## Where completed units appear in the world.
@export var spawn_point_path: NodePath = ^"SpawnPoint"
## How far the model sinks below its resting position at the start of construction.
@export var construction_sink_depth: float = 3.0

## Mirrored to non-authoritative peers purely so their build panel UI reads correctly.
@export var is_under_construction: bool = false
@export var construction_progress: float = 1.0
@export var synced_queue_size: int = 0
@export var synced_time_remaining: float = 0.0
@export var synced_current_item_name: String = ""

var queue: Array[ProducibleItem] = []
var build_timer: float = 0.0

var construction_time: float = 0.0
var _construction_timer: float = 0.0
var _rest_position_y: float = 0.0

## Called by whatever places this building (e.g. the placement system) once
## it's positioned in the world. Buildings placed directly in a scene file
## (like a level's starting Town Center) simply never call this, so they
## start fully built with no rising animation.
func begin_construction(duration: float) -> void:
	if duration <= 0.0:
		return
	construction_time = duration
	is_under_construction = true
	construction_progress = 0.0
	_construction_timer = 0.0
	_rest_position_y = position.y
	position.y = _rest_position_y - construction_sink_depth

func enqueue(item: ProducibleItem) -> bool:
	if is_under_construction or item == null or not ResourceStockpile.can_afford(owner_peer_id, item.costs):
		return false
	ResourceStockpile.spend(owner_peer_id, item.costs)
	queue.append(item)
	queue_changed.emit()
	return true

func time_remaining() -> float:
	if queue.is_empty():
		return 0.0
	return maxf(queue[0].build_time - build_timer, 0.0)

func _process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	if is_under_construction:
		_construction_timer += delta
		construction_progress = clampf(_construction_timer / construction_time, 0.0, 1.0)
		position.y = lerpf(_rest_position_y - construction_sink_depth, _rest_position_y, construction_progress)
		if construction_progress >= 1.0:
			is_under_construction = false
			position.y = _rest_position_y
			construction_finished.emit()
		return

	if queue.is_empty():
		build_timer = 0.0
	else:
		build_timer += delta
		if build_timer >= queue[0].build_time:
			var item: ProducibleItem = queue.pop_front()
			build_timer = 0.0
			item_completed.emit(item)
			queue_changed.emit()

	synced_queue_size = queue.size()
	synced_time_remaining = time_remaining()
	synced_current_item_name = queue[0].item_name if not queue.is_empty() else ""
