class_name ScenarioZone
extends Node3D
## A named circle on the map: "get your army here", "hold this", "spawn the
## raiders there". Quest conditions and actions refer to one by node name.
##
## Flat (XZ) on purpose — like everything else that asks "is this inside the
## area the designer drew", height on a slope shouldn't decide it.

@export var radius: float = 8.0

func _ready() -> void:
	add_to_group(&"scenario_zones")

func contains(pos: Vector3) -> bool:
	return Vector2(pos.x - global_position.x, pos.z - global_position.z).length() <= radius

## Every living unit of `peer_id` inside the circle (0 = anyone's).
func units_inside(peer_id: int = 0) -> Array[Unit]:
	var out: Array[Unit] = []
	for node in get_tree().get_nodes_in_group(&"units"):
		var unit := node as Unit
		if unit == null or unit.status_activity == Unit.Activity.DEAD:
			continue
		if peer_id != 0 and unit.owner_peer_id != peer_id:
			continue
		if contains(unit.global_position):
			out.append(unit)
	return out
