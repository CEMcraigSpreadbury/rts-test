class_name ProductionBuilding
extends StaticBody3D
## Generic producing building. One reusable scene/script pair: what a specific
## building "is" (Town Center, Barracks, ...) is entirely defined by the
## `building_name` and `producibles` configured on the instance in the inspector.
## The build menu UI reads `producibles` to know what buttons to show.
##
## Only the host ever actually runs the queue/construction/combat simulation
## (see the is_multiplayer_authority() guard in _process); everyone else just
## displays the handful of fields below that are kept in sync for the UI.

signal queue_changed
signal item_completed(item: ProducibleItem)
signal construction_finished
signal destroyed

const DESTROY_SINK_DURATION: float = 1.5

@export var building_name: String = "Production Building"
@export var producibles: Array[ProducibleItem] = []
## Which player owns this building; only they may queue production on it.
@export var owner_peer_id: int = 1
## Where completed units appear in the world.
@export var spawn_point_path: NodePath = ^"SpawnPoint"
## Whether this building type supports a rally point at all (Town Center,
## Barracks, etc). When off, right-clicking it while selected does nothing.
@export var can_rally: bool = true
## How far this building reveals fog of war around itself.
@export var vision_range: float = 10.0
## Added to the owner's population cap once construction finishes (or
## immediately for buildings placed pre-built, e.g. the starting Town
## Center), and removed again if this building is destroyed. 0 for buildings
## that don't grant population room (Barracks, Farm).
@export var population_capacity: int = 0
## Set alongside owner_peer_id at spawn time; used only for the minimap dot
## color (buildings have no sprite to modulate the way units do).
@export var team_tint: Color = Color.WHITE
## How far the model sinks below its resting position at the start of construction.
@export var construction_sink_depth: float = 3.0

@export_group("Combat")
@export var max_health: int = 100
## True only for Town Center-type buildings: a player loses when all of theirs are destroyed.
@export var is_main_base: bool = false

## Mirrored to non-authoritative peers purely so their UI/health bar reads correctly.
@export var is_under_construction: bool = false
@export var construction_progress: float = 1.0
@export var synced_queue_size: int = 0
@export var synced_time_remaining: float = 0.0
@export var synced_current_item_name: String = ""
@export var health_fraction: float = 1.0

var queue: Array[ProducibleItem] = []
var build_timer: float = 0.0

var construction_time: float = 0.0
var _construction_timer: float = 0.0
var _rest_position_y: float = 0.0

## Not networked: only the host's copy is ever read (when spawning units), and
## the one peer allowed to set it (the owner) writes their own local copy
## directly at the same time as sending the RPC that updates the host's copy.
var rally_point: Vector3 = Vector3.ZERO
var has_rally_point: bool = false

var current_health: int = 1
var is_destroyed: bool = false
var _destroy_timer: float = 0.0
var _destroy_start_y: float = 0.0

@onready var health_bar: Node3D = $HealthBar
@onready var health_bar_fill: Sprite3D = $HealthBar/Fill

## Captured from the scene's authored (full-health) scale so the fill's
## aspect-ratio/sizing lives in the scene file, not duplicated in script.
var _fill_base_scale_x: float = 1.0

func _ready() -> void:
	current_health = max_health
	if health_bar_fill:
		_fill_base_scale_x = health_bar_fill.scale.x

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
	if is_destroyed or is_under_construction or item == null or not ResourceStockpile.can_afford(owner_peer_id, item.costs):
		return false
	## Population is reserved as soon as an item enters the queue (not when it
	## actually spawns) so a player can't queue past the cap; Unit.release()s
	## the same amount when the resulting unit later dies.
	if item.kind == ProducibleItem.Kind.UNIT and not Population.has_room(owner_peer_id, item.population_cost):
		return false
	ResourceStockpile.spend(owner_peer_id, item.costs)
	if item.kind == ProducibleItem.Kind.UNIT:
		Population.reserve(owner_peer_id, item.population_cost)
	queue.append(item)
	queue_changed.emit()
	return true

func time_remaining() -> float:
	if queue.is_empty():
		return 0.0
	return maxf(queue[0].build_time - build_timer, 0.0)

## Buildings can't fight back themselves, but they can call nearby units in to defend.
func take_damage(amount: int, attacker: Node3D = null) -> void:
	if not is_multiplayer_authority() or is_destroyed:
		return
	current_health = maxi(current_health - amount, 0)
	health_fraction = float(current_health) / float(maxi(max_health, 1))
	if current_health <= 0:
		_begin_destruction()
		return
	CombatUtils.alert_nearby_allies(get_tree(), global_position, owner_peer_id, attacker)

## How far NavigationObstacle3D avoidance keeps agents pushed back from this
## building's center; units attacking a building need to account for this so
## they don't try to stand somewhere avoidance will never let them reach.
func get_footprint_radius() -> float:
	var obstacle: NavigationObstacle3D = get_node_or_null("NavigationObstacle3D")
	return obstacle.radius if obstacle else 0.0

func _begin_destruction() -> void:
	is_destroyed = true
	is_under_construction = false
	_destroy_timer = 0.0
	_destroy_start_y = position.y
	destroyed.emit()

func _process(delta: float) -> void:
	_update_health_bar_visual()

	if not is_multiplayer_authority():
		return

	if is_destroyed:
		_destroy_timer += delta
		var t: float = clampf(_destroy_timer / DESTROY_SINK_DURATION, 0.0, 1.0)
		position.y = lerpf(_destroy_start_y, _destroy_start_y - construction_sink_depth, t)
		if t >= 1.0:
			queue_free()
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

func _update_health_bar_visual() -> void:
	if not health_bar:
		return
	var fraction: float = clampf(health_fraction, 0.0, 1.0)
	health_bar.visible = fraction < 0.999 and not is_destroyed
	## Scale from center only (no position offset) so Fill can't visually drift
	## away from Background as the camera orbits.
	health_bar_fill.scale.x = _fill_base_scale_x * maxf(fraction, 0.001)
