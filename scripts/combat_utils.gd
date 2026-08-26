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
		if ally.status_command == Unit.Command.ATTACK:
			continue
		if ally.global_position.distance_to(from_position) <= ally.aggro_range:
			ally.command_attack(attacker)
