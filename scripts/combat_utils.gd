class_name CombatUtils
extends RefCounted
## Shared by Unit and ProductionBuilding (no common combat base class between
## a Node3D and a StaticBody3D), so this lives as a static helper.

const UnitGrid = preload("res://scripts/unit_grid.gd")
## Neighbour-query radius for alert_nearby_allies: must cover the largest
## Unit.aggro_range on any unit (20, the Ballista, as of writing), since each
## ally is still checked against its own.
const ALERT_QUERY_RADIUS: float = 20.0
## A unit being hit raises the alarm at most this often. Every hit used to
## re-scan the neighbourhood, and in a big melee that's hundreds a second for
## the same handful of allies, who are already fighting after the first one.
const ALERT_INTERVAL_MS: int = 500

## Damage multiplier per Unit.DamageType (row) against Unit.ArmorClass
## (column, in enum order: NONE, SOLDIER, SPEAR, ARCHER, CAVALRY, SIEGE, MONSTER).
## The loop: Spear > Cavalry > Archer > infantry, Soldier > Spear; siege is
## easy prey to anything that closes in and shrugs off arrows. The NONE row
## and column are x1 throughout (Villagers, monsters' own attacks).
const COUNTER_TABLE: Dictionary = {
	Unit.DamageType.NONE:    [1.0, 1.0,  1.0, 1.0,  1.0,  1.0, 1.0],
	Unit.DamageType.BLADE:   [1.0, 1.0,  1.5, 1.25, 1.0,  1.5, 1.0],
	Unit.DamageType.SPEAR:   [1.0, 0.75, 1.0, 1.0,  2.5,  1.0, 1.0],
	Unit.DamageType.CAVALRY: [1.0, 1.0,  0.5, 2.0,  1.0,  2.0, 1.0],
	Unit.DamageType.PIERCE:  [1.0, 1.5,  1.5, 1.0,  0.75, 0.5, 1.0],
	Unit.DamageType.MAGIC:   [1.0, 1.5,  1.0, 1.0,  1.5,  1.0, 1.5],
}

static func counter_multiplier(damage_type: Unit.DamageType, armor_class: Unit.ArmorClass) -> float:
	var row: Array = COUNTER_TABLE.get(damage_type, COUNTER_TABLE[Unit.DamageType.NONE])
	return row[armor_class]

## Calls in nearby allied units to help fight back against whoever just landed a hit.
static func alert_nearby_allies(tree: SceneTree, from_position: Vector3, defender_peer_id: int, attacker: Node3D) -> void:
	if attacker == null or not is_instance_valid(attacker):
		return
	for node in UnitGrid.units_near(tree, from_position, ALERT_QUERY_RADIUS):
		if not (node is Unit):
			continue
		var ally: Unit = node
		## Deliberately this player's own units only, not a teammate's: pulling
		## another human's idle soldiers into a fight would be commanding their
		## army for them. They still retaliate on their own when hit.
		if ally.owner_peer_id != defender_peer_id or not ally.can_fight:
			continue
		## attack_target is only ever non-null while actively engaged, regardless
		## of which command owns the fight — unlike status_command == ATTACK,
		## this also correctly covers a mid-fight Command.PATROL unit (which
		## deliberately stays PATROL through combat so it can resume its loop).
		if ally.attack_target != null:
			continue
		## A plain Command.MOVE is a deliberate player order (e.g. retreating);
		## pulling that unit into a neighbor's fight would silently override it.
		if ally.status_command == Unit.Command.MOVE or ally.status_command == Unit.Command.CAST:
			continue
		## Holding its ground, or its place in a fighting formation: it fights
		## whatever reaches it, not a neighbor's fight.
		if (ally.hold_position or ally.in_formation_fight) and ally.status_command == Unit.Command.NONE:
			continue
		## Already in its block's fight: its men fight whatever the sim puts in
		## their reach. Answering each hit on a neighbour sent the whole block
		## a fresh attack order per man alerted, onto whoever hit last.
		if ally.sim_follow and ally.in_formation_fight:
			continue
		## Part of an idle block: it answers as the block does, not by running
		## off on its own.
		if ally.in_idle_block():
			if ally.global_position.distance_to(from_position) <= ally.aggro_range:
				ally._block_contact(attacker)
			continue
		if ally.global_position.distance_to(from_position) <= ally.aggro_range:
			## An ally on a group attack-move brings its whole block round.
			if not ally._group_contact(attacker):
				ally.command_attack(attacker)

## Nearest living enemy Unit within range of a position/owner — used by
## anything that can initiate an attack but isn't itself a Unit (e.g. a
## defensive building's own target-scan), which is why this doesn't reuse
## Unit._find_nearest_enemy_in_range (that one also factors in leash_radius,
## which only makes sense for a Unit that can move).
static func find_nearest_enemy_unit(tree: SceneTree, from_position: Vector3, owner_peer_id: int, search_range: float) -> Unit:
	var nearest: Unit = null
	var nearest_dist := search_range
	var candidates := UnitGrid.enemies_near(tree, from_position, search_range, owner_peer_id)
	var sorted := UnitGrid.last_sorted
	for node in candidates:
		var other: Unit = node
		if sorted and nearest != null and from_position.distance_to(other.global_position) > nearest_dist + UnitGrid.SORT_SLACK:
			break
		if not is_worth_attacking(other):
			continue
		## A tower whose attack_range reaches past what its side can see
		## doesn't get to shoot at what's standing in the fog.
		if not is_visible_to(tree, owner_peer_id, other.global_position):
			continue
		var dist := from_position.distance_to(other.global_position)
		if dist <= nearest_dist:
			nearest = other
			nearest_dist = dist
	return nearest

## --- Sight ---
##
## Host-side "can that side actually see this spot?" — the combat counterpart
## to FogOfWar, which is local-only and only exists on the viewing peer. Target
## selection runs on the host for every player at once, so it can't ask a fog
## overlay; it asks this instead, and the answer has the same shape: a position
## is seen if any living friendly unit, or any finished friendly building, has
## it inside its own vision_range. Without it an archer (attack_range 18,
## vision_range 14) happily shot whatever stood in its owner's fog.

## Neighbour-query radius for the unit half of the check: must cover the
## largest Unit.vision_range in the game (20, the Ballista, as of writing),
## since each candidate is still measured against its own.
const VISION_QUERY_RADIUS: float = 24.0

## Buildings don't move and there are few of them, so their eyes are gathered
## as a flat list and reused for this long rather than re-walking the group on
## every target scan. A tower finished mid-interval is blind for at most this,
## which nothing in combat can tell apart from the scan cadence anyway.
const BUILDING_EYE_CACHE_SECONDS: float = 0.5

## [[position_x, position_z, vision_range, owner_peer_id], ...]
static var _building_eyes: Array = []
static var _building_eyes_time: float = -1.0

## `viewer_peer_id` is the side asking (a unit's/building's owner_peer_id), not
## necessarily the local player — this is asked on behalf of every player the
## host simulates, AI included.
static func is_visible_to(tree: SceneTree, viewer_peer_id: int, world_pos: Vector3) -> bool:
	## The sim answers for the units, natively, for any side but the neutral
	## one (whose peers are all one sim team there, yet not friends here).
	if ArmyBridge.current != null and Teams.team_of(viewer_peer_id) != Teams.NEUTRAL:
		if ArmyBridge.current.team_sees(viewer_peer_id, world_pos):
			return true
	else:
		for node in UnitGrid.units_near(tree, world_pos, VISION_QUERY_RADIUS):
			var unit: Unit = node
			if not Teams.is_friendly(viewer_peer_id, unit.owner_peer_id):
				continue
			if unit.global_position.distance_to(world_pos) <= unit.vision_range:
				return true
	for eye in _building_vision_sources(tree):
		if not Teams.is_friendly(viewer_peer_id, int(eye[3])):
			continue
		var dx: float = float(eye[0]) - world_pos.x
		var dz: float = float(eye[1]) - world_pos.z
		if dx * dx + dz * dz <= float(eye[2]) * float(eye[2]):
			return true
	return false

static func _building_vision_sources(tree: SceneTree) -> Array:
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _building_eyes_time < BUILDING_EYE_CACHE_SECONDS:
		return _building_eyes
	_building_eyes_time = now
	_building_eyes = []
	for node in tree.get_nodes_in_group("buildings"):
		var building := node as ProductionBuilding
		## Matches FogOfWar._update_vision_sources: a foundation sees nothing, so
		## scattering unbuilt sites can't scout the map for free.
		if building == null or building.is_destroyed or building.is_under_construction:
			continue
		_building_eyes.append([
			building.global_position.x,
			building.global_position.z,
			building.vision_range,
			building.owner_peer_id,
		])
	return _building_eyes

## --- Overkill prevention ---
##
## Damage from a shot is reserved against its target the moment it's fired
## (Unit/ProductionBuilding._fire_projectile) and released when that shot
## resolves, however it resolves. Target selection then treats a target as
## already dead once the reserved damage covers its remaining health, so a
## volley from twenty archers spreads across the enemy line instead of
## stacking onto whoever the first three arrows had already killed.
##
## `target` is untyped throughout: it may be a Unit or a ProductionBuilding
## (no common combat base class between a Node3D and a StaticBody3D),
## and a statically-typed parameter would make GDScript type-check the
## argument before the body runs, throwing on an object freed between a shot
## being fired and it landing instead of letting is_instance_valid() catch it.
static func reserve_damage(target, amount: int) -> void:
	if not is_instance_valid(target):
		return
	if target is Unit or target is ProductionBuilding:
		target.incoming_damage += amount

## Health `target` will have left once every shot currently in flight at it has
## landed. Zero or less means it's already dead on arrival.
static func effective_health(target) -> int:
	if not is_instance_valid(target):
		return 0
	if target is Unit:
		return target.status_current_health - target.incoming_damage
	if target is ProductionBuilding:
		return target.current_health - target.incoming_damage
	return 0

static func is_worth_attacking(target) -> bool:
	return effective_health(target) > 0
