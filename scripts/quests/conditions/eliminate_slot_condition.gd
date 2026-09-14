class_name EliminateSlotCondition
extends QuestCondition
## "Destroy the Beastmen camp" — a scenario side is wiped out: nothing of its
## left standing. Counts units and buildings, so a garrison with no base still
## has to be cleared.

## Index of the slot in the scenario's Slots list.
@export var slot_index: int = 1
## Ignore its units and go by buildings alone — for "raze their base" when
## stragglers shouldn't hold the mission open.
@export var buildings_only: bool = false

func progress(runner) -> Vector2i:
	var peer_id: int = runner.peer_for_slot(slot_index)
	if peer_id <= 0:
		return Vector2i(1, 1)
	var left := 0
	for node in runner.get_tree().get_nodes_in_group(&"buildings"):
		var building := node as ProductionBuilding
		if building != null and not building.is_destroyed and building.owner_peer_id == peer_id:
			left += 1
	if not buildings_only:
		for node in runner.get_tree().get_nodes_in_group(&"units"):
			var unit := node as Unit
			if unit != null and unit.status_activity != Unit.Activity.DEAD and unit.owner_peer_id == peer_id:
				left += 1
	return Vector2i(1 if left == 0 else 0, 1)
