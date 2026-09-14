class_name CombatUtils
extends RefCounted
## Shared by Unit and ProductionBuilding (no common combat base class between
## a CharacterBody3D and a StaticBody3D), so this lives as a static helper.

const UnitGrid = preload("res://scripts/unit_grid.gd")
## Neighbour-query radius for alert_nearby_allies: must cover the largest
## Unit.aggro_range on any unit (9 as of writing), since each ally is still
## checked against its own.
const ALERT_QUERY_RADIUS: float = 10.0
## A unit being hit raises the alarm at most this often. Every hit used to
## re-scan the neighbourhood, and in a big melee that's hundreds a second for
## the same handful of allies, who are already fighting after the first one.
const ALERT_INTERVAL_MS: int = 500
## Same for the aura lookup: must cover the largest Ability.aura_radius.
const AURA_QUERY_RADIUS: float = 10.0

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
		if ally.global_position.distance_to(from_position) <= ally.aggro_range:
			ally.command_attack(attacker)

## First matching nearby Monarch's PASSIVE_AURA attack-speed bonus for this
## unit, or 0.0 if none in range. Multiple Monarchs don't stack — a
## deliberate simplification, first match wins.
static func nearby_aura_attack_speed_bonus(tree: SceneTree, unit: Unit) -> float:
	var ability := _find_nearby_aura(tree, unit)
	return ability.aura_attack_speed_bonus if ability else 0.0

## Same as above, for flat armor (damage reduction).
static func nearby_aura_armor_bonus(tree: SceneTree, unit: Unit) -> int:
	var ability := _find_nearby_aura(tree, unit)
	return ability.aura_armor_bonus if ability else 0

## Nearest living enemy Unit within range of a position/owner — used by
## anything that can initiate an attack but isn't itself a Unit (e.g. a
## defensive building's own target-scan), which is why this doesn't reuse
## Unit._find_nearest_enemy_in_range (that one also factors in leash_radius,
## which only makes sense for a Unit that can move).
static func find_nearest_enemy_unit(tree: SceneTree, from_position: Vector3, owner_peer_id: int, search_range: float) -> Unit:
	var nearest: Unit = null
	var nearest_dist := search_range
	for node in UnitGrid.units_near(tree, from_position, search_range):
		if not (node is Unit):
			continue
		var other: Unit = node
		if not Teams.is_enemy(owner_peer_id, other.owner_peer_id) or other.status_activity == Unit.Activity.DEAD:
			continue
		if not is_worth_attacking(other):
			continue
		var dist := from_position.distance_to(other.global_position)
		if dist <= nearest_dist:
			nearest = other
			nearest_dist = dist
	return nearest

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
## (no common combat base class between a CharacterBody3D and a StaticBody3D),
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

static func _find_nearby_aura(tree: SceneTree, unit: Unit) -> Ability:
	if Unit.monarch_count <= 0:
		return null
	for node in UnitGrid.units_near(tree, unit.global_position, AURA_QUERY_RADIUS):
		if not (node is Unit) or node == unit:
			continue
		var monarch: Unit = node
		if not monarch.is_monarch or monarch.owner_peer_id != unit.owner_peer_id:
			continue
		for ability in monarch.monarch_abilities:
			if ability.kind == Ability.Kind.PASSIVE_AURA \
					and monarch.global_position.distance_to(unit.global_position) <= ability.aura_radius:
				return ability
	return null
