class_name SettlementsCondition
extends QuestCondition
## "Take the village by the ford" / "hold three settlements" / "raise a Town"
## — Realm settlements the players hold right now, so losing one puts the step
## back. Pointed at another side it counts theirs instead.

## Settlements by node name as they stand in the map ("Objective6"); only
## these count. Empty counts any settlement.
@export var settlement_names: Array[String] = []
## How many must be held at once.
@export var count: int = 1
## Only settlements of this people ("Human", "Gnolls", "Dark Elves",
## "Star Wanderers", "Beastmen"). Empty accepts any.
@export var race_name: String = ""
## Only settlements grown to at least this tier.
@export_enum("Village", "Town", "City") var min_tier: int = 0
## -1 counts the player seats; otherwise the side playing that slot.
@export var slot_index: int = -1

func progress(runner) -> Vector2i:
	var peers: Array[int] = []
	if slot_index < 0:
		peers = runner.player_peers()
	else:
		var peer_id: int = runner.peer_for_slot(slot_index)
		if peer_id > 0:
			peers.append(peer_id)
	var held := 0
	for node in runner.get_tree().get_nodes_in_group(&"objectives"):
		var settlement := node as Objective
		if settlement == null or not settlement.is_settlement() or not peers.has(settlement.owner_peer_id):
			continue
		if not settlement_names.is_empty() and not settlement_names.has(String(settlement.name)):
			continue
		if race_name != "" and settlement.race_name != race_name:
			continue
		if settlement.tier < min_tier:
			continue
		held += 1
	return Vector2i(held, maxi(count, 1))
