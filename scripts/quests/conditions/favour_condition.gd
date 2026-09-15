class_name FavourCondition
extends QuestCondition
## "Reach 1500 Favour" — the team's Favour added together, for a mission that
## is a score race. Needs the scenario to have Favour switched on.
##
## Pointed at an enemy slot it reads the other way, as a fail condition: "the
## warlord reaches 1000 Favour before you do".

const FAVOUR: ResourceType = preload("res://resources/favour_resource_type.tres")

@export var amount: int = 1000
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
	var total := 0
	for peer_id in peers:
		total += ResourceStockpile.get_amount(peer_id, FAVOUR)
	return Vector2i(total, maxi(amount, 1))
