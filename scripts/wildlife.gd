class_name Wildlife
extends Node
## Forest animals, scattered over the map at the start of every match and
## restocked slowly as they are hunted. Created by Main as `main.wildlife`.
##
## Animals are ordinary neutral units (peer 0, like an Objective's guards)
## rather than resource nodes, so hunting them is just combat: a hunter kills
## one, Pacts.award_death pays the Meat (and a Soul to anyone watching). That
## also means they show up in fog of war, get in the way, and — for the wolves
## and bears — bite back.
##
## Host-only: units are spawned through Main.unit_spawner, which replicates
## them to every peer.

## Placed out from the map's trees rather than anywhere at all: herds belong
## by the woods, in the clearings and along the treeline, not standing in the
## middle of a battlefield — and not buried in the canopy either, which is
## where a 2-6m offset put them on a densely forested map.
const SPAWN_NEAR_TREE_MIN: float = 7.0
const SPAWN_NEAR_TREE_MAX: float = 18.0
## No animal is placed closer than this to any tree, so a herd stands in open
## ground with the wood behind it instead of inside it.
const TREE_CLEARANCE: float = 5.0
## Kept clear of player spawns so nobody opens the match with a bear in their
## town centre.
const MIN_DISTANCE_FROM_BASE: float = 30.0
## One HERD per this many trees on the map, so a dense forest map stocks more
## game than a bare one.
const TREES_PER_HERD: int = 7
const MAX_HERDS: int = 26
## Animals arrive as a herd of one kind grazing together, not as lone bodies
## dotted about — so a hunting party gets a worthwhile trip out of finding one.
## These are prey numbers; predators pack smaller (PREDATOR_HERD_MAX).
const HERD_MIN: int = 3
const HERD_MAX: int = 5
## Wolves and bears pack smaller than the herds they hunt, and the map holds
## only a handful of them at a time however the weights roll — they are a
## hazard you stumble into, not a Meat supply. A Gnoll player's living comes
## from the deer and boar instead.
const PREDATOR_HERD_MAX: int = 2
const MAX_PREDATORS: int = 6
## How far a herd spreads around the spot it was placed.
const HERD_SPREAD: float = 3.0
## Each herd grazes around a marker left at the spot it was placed, drifting
## between random points inside this radius rather than standing where it
## spawned for the whole match.
const WANDER_RADIUS: float = 9.0
## A predator that gives chase turns back once this far from its herd's patch.
## Set through the leash an Objective's guards already use (Unit.leash_origin
## /leash_radius), which breaks off a chase and ignores targets beyond it.
const LEASH_RADIUS: float = 18.0
## A hunted-out map refills, or Meat would run dry by mid-game. One herd per
## tick, so a cleared wood comes back over a couple of minutes rather than
## popping back the moment it is emptied.
const RESTOCK_INTERVAL: float = 15.0

## Weighted by how common each should be: deer and boar are the staple a Gnoll
## player lives on, foxes are thin pickings at 7 Meat apiece, and wolves and
## bears are the risk that comes with hunting rather than a supply.
const ANIMAL_SCENES: Array[String] = [
	"res://scenes/units/animals/deer_animal.tscn",
	"res://scenes/units/animals/deer_animal.tscn",
	"res://scenes/units/animals/deer_animal.tscn",
	"res://scenes/units/animals/boar_animal.tscn",
	"res://scenes/units/animals/boar_animal.tscn",
	"res://scenes/units/animals/boar_animal.tscn",
	"res://scenes/units/animals/fox_animal.tscn",
	"res://scenes/units/animals/wolf_animal.tscn",
	"res://scenes/units/animals/bear_animal.tscn",
]

var main: Main

var _restock_timer: float = RESTOCK_INTERVAL
var _target_count: int = 0
var _tree_positions: Array[Vector3] = []

func setup() -> void:
	if not multiplayer.is_server():
		return
	_collect_tree_positions()
	var herds: int = clampi(_tree_positions.size() / TREES_PER_HERD, 4, MAX_HERDS)
	## Judged in animals rather than herds so hunting a herd down to its last
	## deer still counts as a gap worth refilling.
	_target_count = herds * HERD_MIN
	for i in herds:
		_spawn_one()

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or _target_count <= 0:
		return
	_restock_timer -= delta
	if _restock_timer > 0.0:
		return
	_restock_timer = RESTOCK_INTERVAL
	if _living_count() < _target_count:
		_spawn_one()

## Trees are Gatherables that pay wood; gold deposits and farms are not what
## we want to hide deer behind.
func _collect_tree_positions() -> void:
	for node in get_tree().get_nodes_in_group("gatherables"):
		var gatherable := node as Gatherable
		if gatherable == null or gatherable.resource_type == null:
			continue
		if gatherable.resource_type.display_name != "Wood":
			continue
		_tree_positions.append(gatherable.global_position)
	## A map with no trees at all still gets some game, spread around the
	## player spawn markers instead.
	if _tree_positions.is_empty() and main.player_spawn_points != null:
		for node in main.player_spawn_points.get_children():
			if node is Node3D:
				_tree_positions.append(node.global_position)

func _living_count() -> int:
	var count: int = 0
	for node in get_tree().get_nodes_in_group("units"):
		var unit := node as Unit
		if unit != null and is_instance_valid(unit) and unit.hunt_meat > 0 \
				and unit.status_activity != Unit.Activity.DEAD:
			count += 1
	return count

## One herd: several animals of the SAME kind, grazing within HERD_SPREAD of
## each other.
func _spawn_one() -> void:
	if _tree_positions.is_empty():
		return
	var position := _pick_position()
	if position == Vector3.INF:
		return
	var scene_path: String = ANIMAL_SCENES[randi() % ANIMAL_SCENES.size()]
	var count: int = randi_range(HERD_MIN, HERD_MAX)
	if _is_predator(scene_path):
		## Rolled a predator with the map already at its quota: the wood gets
		## a herd of prey instead rather than losing the spawn altogether.
		if _living_predators() + PREDATOR_HERD_MAX > MAX_PREDATORS:
			scene_path = _prey_scene()
		else:
			count = mini(count, PREDATOR_HERD_MAX)
	var nav_map: RID = main.get_world_3d().navigation_map
	var navigation_ready: bool = NavigationServer3D.map_get_iteration_id(nav_map) > 0
	## The patch this herd calls home. A marker rather than the spawn position
	## itself because Unit.command_wander follows a Node3D, and it is parented
	## here so it outlives the animals that graze around it — a restocked herd
	## can be given the same ground.
	var home := Marker3D.new()
	add_child(home)
	home.global_position = position
	for i in count:
		var spot := position
		if i > 0:
			## A few tries at a spot beside the others that is still out of the
			## trees; failing that the animal simply stands with the herd.
			for attempt in 6:
				var candidate := position + Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized() * randf_range(1.0, HERD_SPREAD)
				if navigation_ready:
					candidate = NavigationServer3D.map_get_closest_point(nav_map, candidate)
				if _clear_of_trees(candidate, TREE_CLEARANCE * 0.6):
					spot = candidate
					break
		var animal: Unit = main.unit_spawner.spawn({
			"scene_path": scene_path,
			"peer_id": 0,
			"tint": Objective.NEUTRAL_TINT,
			"position": spot,
		})
		if animal == null:
			continue
		## Deferred rather than hung off `ready`: a spawned unit may already be
		## ready by the time this returns, and a ready that has fired never
		## fires again — the herds then stood still for the whole match.
		_start_grazing.call_deferred(animal, home)

## Animals that can't fight (deer, foxes) have no wander of their own —
## command_wander refuses a unit that can't fight — so they are drifted about
## by hand instead, on the same radius.
func _start_grazing(animal: Unit, home: Node3D) -> void:
	if not is_instance_valid(animal) or not is_instance_valid(home):
		return
	animal.leash_origin = home
	animal.leash_radius = LEASH_RADIUS
	if animal.can_fight:
		animal.command_wander(home, WANDER_RADIUS)
	else:
		animal.command_graze(home, WANDER_RADIUS)

## Tries a handful of trees before giving up, rather than looping until it
## finds a spot — on a map whose every tree is near a base this would
## otherwise never return.
func _pick_position() -> Vector3:
	## More attempts than the spread needs: on a heavily wooded map most rolls
	## land back under the canopy, and giving up too early is what leaves the
	## herds standing in the trees.
	for attempt in 24:
		var origin: Vector3 = _tree_positions[randi() % _tree_positions.size()]
		var offset := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized() \
				* randf_range(SPAWN_NEAR_TREE_MIN, SPAWN_NEAR_TREE_MAX)
		var candidate := origin + offset
		if _too_close_to_a_base(candidate):
			continue
		var nav_map: RID = main.get_world_3d().navigation_map
		if NavigationServer3D.map_get_iteration_id(nav_map) > 0:
			candidate = NavigationServer3D.map_get_closest_point(nav_map, candidate)
		## Checked after the navmesh snap, not before: the snap is what can
		## drag a perfectly good clearing spot back against a trunk.
		if not _clear_of_trees(candidate, TREE_CLEARANCE):
			continue
		return candidate
	return Vector3.INF

## True when nothing in _tree_positions is within `clearance` of the spot.
func _clear_of_trees(position: Vector3, clearance: float) -> bool:
	var clearance_squared: float = clearance * clearance
	for tree_position in _tree_positions:
		if position.distance_squared_to(tree_position) < clearance_squared:
			return false
	return true

static func _is_predator(scene_path: String) -> bool:
	return scene_path.contains("wolf") or scene_path.contains("bear")

func _living_predators() -> int:
	var count: int = 0
	for node in get_tree().get_nodes_in_group("units"):
		var unit := node as Unit
		if unit == null or not is_instance_valid(unit) or unit.hunt_meat <= 0:
			continue
		if unit.status_activity == Unit.Activity.DEAD:
			continue
		if _is_predator(unit.scene_file_path):
			count += 1
	return count

## Any non-predator entry, so a blocked predator roll still stocks the wood.
func _prey_scene() -> String:
	for attempt in 8:
		var candidate: String = ANIMAL_SCENES[randi() % ANIMAL_SCENES.size()]
		if not _is_predator(candidate):
			return candidate
	return "res://scenes/units/animals/deer_animal.tscn"

func _too_close_to_a_base(position: Vector3) -> bool:
	for node in get_tree().get_nodes_in_group("buildings"):
		var building := node as ProductionBuilding
		if building == null or not building.is_main_base:
			continue
		if position.distance_to(building.global_position) < MIN_DISTANCE_FROM_BASE:
			return true
	return false
