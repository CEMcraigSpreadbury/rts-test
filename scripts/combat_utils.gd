class_name CombatUtils
extends RefCounted
## Shared by Unit and ProductionBuilding (no common combat base class between
## a CharacterBody3D and a StaticBody3D), so this lives as a static helper.

## Calls in nearby allied units to help fight back against whoever just landed a hit.
static func alert_nearby_allies(tree: SceneTree, from_position: Vector3, defender_peer_id: int, attacker: Node3D) -> void:
	if attacker == null or not is_instance_valid(attacker):
		return
	for node in tree.get_nodes_in_group("units"):
		if not (node is Unit):
			continue
		var ally: Unit = node
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
		if ally.status_command == Unit.Command.MOVE:
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

static func _find_nearby_aura(tree: SceneTree, unit: Unit) -> Ability:
	for node in tree.get_nodes_in_group("units"):
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
