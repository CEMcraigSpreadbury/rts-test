class_name Gatherable
extends StaticBody3D
## A harvestable resource node (tree, rock, ore vein, ...). Duplicate this
## scene and swap the resource_type, model, and collision/obstacle sizes to
## create new resource types (Stone, Gold, ...).

signal depleted

## What this node is called in UI (info panel title, etc.) — distinct from
## resource_type.display_name, which names what it produces (e.g. a Berry
## Bush and a Farm both produce "Food" but shouldn't both be labeled "Food").
@export var display_name: String = "Resource"
## Only meaningful for a player-placed resource (Farm) — see BuildingType.get_costs().
## Natural resources (Tree, Berry Bush, Gold Deposit) just leave this empty.
@export var costs: Array[ResourceCost] = []
@export var resource_type: ResourceType
@export var amount_remaining: int = 500
## How close a gatherer needs to be before it starts harvesting.
@export var gather_range: float = 1.75
## 0 = neutral/natural resource (trees, berry bushes, gold deposits) that anyone
## can gather from. Player-built resources (Farm) are set to their owner's
## peer_id at spawn time so other players' villagers can't collect from them.
@export var owner_peer_id: int = 0
## When true, this node can't actually be harvested until a qualifying
## building has been constructed on top of it (see BuildingType.requires_deposit
## / main.gd's placement handling) — e.g. a Gold Deposit needs a Mine built on
## it first. Off by default so trees/berry bushes/farms are unaffected.
@export var requires_building_on_top: bool = false
## Set true once a qualifying building's construction finishes on this node,
## and back to false if that building is destroyed (see main.gd).
var has_required_building: bool = false
## True from the moment a building starts being placed here (even mid-
## construction) so a second building can't also claim the same node.
var is_claimed: bool = false
## -1 = unlimited (trees, berry bushes, gold deposits). Farm caps this so
## villagers don't all pile onto the same field.
@export var max_gatherers: int = -1
var gatherers: Array[Unit] = []
## When true, a gatherer whose node runs out moves on to the nearest other node
## of the same kind (see Unit._retarget_resource) instead of going idle. On for
## trees only — gold deposits need a Mine each, so there's no "next one" to find.
@export var seek_replacement_when_depleted: bool = false
## Whatever is gathered here goes straight into the stockpile instead of being
## carried to a drop-off, so the worker never leaves (a Library's readers).
@export var pays_at_once: bool = false
## Above zero, this is a forest tree: no collision shape, obstacle or model of
## its own. Forest draws it and answers clicks and placement checks for it,
## and the navmesh and the sim grid carve it as a trunk of this radius — see
## Forest for why.
@export var trunk_radius: float = 0.0

## One is picked at random and played through select_audio_player whenever
## this node becomes newly selected (see main.gd's selection code). Shared by
## every Gatherable (trees/berry bushes/gold deposits too), but only Farm
## currently has a SelectAudioPlayer node in its scene — safe no-op elsewhere.
## Farm is a player-built structure, so unlike natural resources its select
## sound is a plain (non-positional) AudioStreamPlayer, not a 3D one.
@export var on_select_sound_effects: Array[AudioStream] = []
@onready var select_audio_player: AudioStreamPlayer = get_node_or_null("SelectAudioPlayer")

## The visual model is a differently-named child in every gatherable scene
## (tree/bush/gold mound/farm mesh), so it's found by elimination rather than
## by a path each scene would have to keep in sync.
var _model: Node3D = null
var _model_base_scale: Vector3 = Vector3.ONE
var _model_base_quat: Quaternion = Quaternion.IDENTITY
var _squash_tween: Tween
## Several gatherers can strike the same node in quick succession, which
## would restart the pop before it ever plays out and read as a jitter.
const SQUASH_COOLDOWN_MSEC: int = 300
var _next_squash_msec: int = 0
## The harvest pop (see hit_pop): how long it runs, how fast it gives under
## the blow, how far it squashes, how far it leans away from the gatherer, and
## the springy settle after (wobbles a second and how quickly they die).
const POP_SECONDS: float = 0.6
const POP_GIVE: float = 0.05
const POP_SQUASH: Vector3 = Vector3(0.09, -0.13, 0.09)
const POP_TILT: float = 0.09
const POP_WOBBLES: float = 3.4
const POP_DAMPING: float = 6.5
## Which way the current pop leans (flat, away from the gatherer; zero for none).
var _pop_away: Vector3 = Vector3.ZERO
var _pop_strength: float = 1.0

## Bumped whenever any resource node enters or leaves the tree (or starts to
## deplete). Resource nodes never move, so this is all NavigationBlockers needs
## to notice one change, instead of re-fingerprinting every tree on the map.
static var tree_changes: int = 0

func _enter_tree() -> void:
	tree_changes += 1

func _exit_tree() -> void:
	tree_changes += 1

func _ready() -> void:
	if is_tree():
		_join_forest()
		return
	for child in get_children():
		if child is Node3D and not (child is CollisionShape3D or child is NavigationObstacle3D):
			_model = child
			_model_base_scale = _model.scale
			_model_base_quat = _model.quaternion
			BakedLightingMaterial.apply_to(_model)
			PlasticMaterial.apply_to(_model)
			TreeWind.apply_to_trees_in(_model)
			break

func is_tree() -> bool:
	return trunk_radius > 0.0

## How far this node's solid footprint reaches: the trunk, or the
## NavigationObstacle3D a deposit or farm carries (1.2 if it has neither).
func footprint_radius() -> float:
	if is_tree():
		return trunk_radius
	var obstacle := get_node_or_null(^"NavigationObstacle3D") as NavigationObstacle3D
	return obstacle.radius if obstacle else 1.2

## Hands the model to the forest and leaves physics altogether: a body with no
## shape still counts against the physics engine's body limit.
func _join_forest() -> void:
	var model: Node3D = null
	for child in get_children():
		if child is Node3D:
			model = child
			break
	Forest.for_node(self).add_tree(self, model)
	if model != null:
		remove_child(model)
		model.free()
	PhysicsServer3D.body_set_space(get_rid(), RID())

func play_select_sound() -> void:
	if is_tree():
		if Forest.active != null:
			Forest.active.play_select(on_select_sound_effects)
		return
	AudioUtils.play_random(select_audio_player, on_select_sound_effects)

## A gatherer's blow landing: the node gives under it, leaning away from
## `from`, springs back past rest and wobbles still. Purely local per peer —
## each peer's gatherer calls it on its own swing (see Unit's gather impact).
func play_harvest_squash(from: Vector3 = Vector3.INF, strength: float = 1.0) -> void:
	var now: int = Time.get_ticks_msec()
	if now < _next_squash_msec:
		return
	var away := Vector3.ZERO
	if from.is_finite():
		away = global_position - from
		away.y = 0.0
		away = away.normalized() * _pop_tilt()
	if is_tree():
		_next_squash_msec = now + SQUASH_COOLDOWN_MSEC
		if Forest.active != null:
			Forest.active.squash(self, away)
		return
	if _model == null:
		return
	_next_squash_msec = now + SQUASH_COOLDOWN_MSEC
	if _squash_tween and _squash_tween.is_valid():
		_squash_tween.kill()
	_pop_away = away
	_pop_strength = strength
	_squash_tween = create_tween()
	_squash_tween.tween_method(_apply_pop, 0.0, POP_SECONDS, POP_SECONDS)

## How far this node leans under a blow.
func _pop_tilt() -> float:
	return POP_TILT

func _apply_pop(time: float) -> void:
	if _model == null:
		return
	var pop: float = hit_pop(time) * _pop_strength
	var basis := Basis(_model_base_quat).scaled_local(_model_base_scale * (Vector3.ONE + POP_SQUASH * pop))
	if _pop_away != Vector3.ZERO:
		basis = Basis(Vector3.UP.cross(_pop_away).normalized(), _pop_away.length() * pop) * basis
	_model.basis = basis

## How hard a harvest pop is pressing `time` seconds in: up to 1 as the blow
## lands, then a spring back that overshoots below 0 and dies away to 0.
static func hit_pop(time: float) -> float:
	if time >= POP_SECONDS:
		return 0.0
	if time < POP_GIVE:
		var k: float = time / POP_GIVE
		return k * (2.0 - k)
	var after: float = time - POP_GIVE
	var fade: float = 1.0 - smoothstep(POP_SECONDS * 0.7, POP_SECONDS, time)
	return exp(-POP_DAMPING * after) * cos(TAU * POP_WOBBLES * after) * fade

## The finished building standing on this node (a Mine on its deposit), on
## every peer: the one whose linked_deposit this is.
func building_on_top() -> ProductionBuilding:
	if not requires_building_on_top:
		return null
	if is_instance_valid(_building_on_top) and not _building_on_top.is_destroyed \
			and _building_on_top.linked_deposit == self:
		return _building_on_top
	_building_on_top = null
	for node in get_tree().get_nodes_in_group("buildings"):
		var building := node as ProductionBuilding
		if building and building.linked_deposit == self and not building.is_destroyed and not building.is_under_construction:
			_building_on_top = building
			break
	return _building_on_top

var _building_on_top: ProductionBuilding = null

func can_be_gathered() -> bool:
	return not requires_building_on_top or has_required_building

## Whether working this node gives anything right now. A farm field is worked
## through its whole cycle but only yields when ripe (see FarmField).
func is_yielding() -> bool:
	return true

## What the info panel shows as left in this node.
func display_remaining() -> int:
	return amount_remaining

func can_accept_gatherer() -> bool:
	return max_gatherers < 0 or gatherers.size() < max_gatherers

func add_gatherer(unit: Unit) -> void:
	if not gatherers.has(unit):
		gatherers.append(unit)

func remove_gatherer(unit: Unit) -> void:
	gatherers.erase(unit)

## Returns the amount actually taken (may be less than requested near depletion).
func gather(amount: int) -> int:
	var taken: int = mini(amount, amount_remaining)
	amount_remaining -= taken
	if amount_remaining <= 0:
		_deplete()
		## Gathering only runs on the host and Gatherables aren't networked
		## nodes, so every other peer has to be told to drop theirs too — or its
		## collision, model and navmesh carve stay behind on their screens.
		if multiplayer.is_server() and multiplayer.multiplayer_peer != null:
			_rpc_deplete.rpc()
	return taken

@rpc("authority", "call_remote", "reliable")
func _rpc_deplete() -> void:
	amount_remaining = 0
	_deplete()

func _deplete() -> void:
	if is_queued_for_deletion():
		return
	## Stops blocking the moment it's queued, not a frame later when it leaves.
	tree_changes += 1
	if is_tree():
		Forest.for_node(self).remove_tree(self)
	depleted.emit()
	queue_free()
