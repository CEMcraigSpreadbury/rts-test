class_name GiveResourcesAction
extends QuestAction
## A reward, a stipend, or a levy taken back off a side.

@export var amounts: Array[ResourceCost] = []
## Which side gets it; -1 gives it to every player on the quest's own team.
@export var slot_index: int = -1
## Take it away instead of handing it over.
@export var take: bool = false

func run(runner) -> void:
	var peers: Array[int] = []
	if slot_index < 0:
		peers = runner.player_peers()
	else:
		var peer_id: int = runner.peer_for_slot(slot_index)
		if peer_id > 0:
			peers.append(peer_id)
	for peer_id in peers:
		for cost in amounts:
			if cost == null or cost.resource_type == null:
				continue
			if take:
				var held: int = ResourceStockpile.get_amount(peer_id, cost.resource_type)
				var taken := ResourceCost.new()
				taken.resource_type = cost.resource_type
				taken.amount = mini(cost.amount, held)
				ResourceStockpile.spend(peer_id, [taken] as Array[ResourceCost])
			else:
				ResourceStockpile.add(peer_id, cost.resource_type, cost.amount)
