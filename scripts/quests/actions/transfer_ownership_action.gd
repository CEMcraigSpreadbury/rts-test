class_name TransferOwnershipAction
extends QuestAction
## Hands scenario-placed units or buildings to another side — the rescued
## village joining you, or a garrison changing hands.
##
## Names are the ones authored under the slot (see Main.scenario_entities).

@export var target_names: Array[String] = []
## Which side they join; -1 makes them neutral.
@export var slot_index: int = 0

func run(runner) -> void:
	var peer_id: int = runner.peer_for_slot(slot_index) if slot_index >= 0 else 0
	for target_name in target_names:
		runner.set_entity_owner(target_name, peer_id)
