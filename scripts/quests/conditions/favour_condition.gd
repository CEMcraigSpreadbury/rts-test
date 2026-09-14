class_name FavourCondition
extends QuestCondition
## "Reach 1500 Favour" — the team's Favour added together, for a mission that
## is a score race. Needs the scenario to have Favour switched on.

const FAVOUR: ResourceType = preload("res://resources/favour_resource_type.tres")

@export var amount: int = 1000

func progress(runner) -> Vector2i:
	var total := 0
	for peer_id in runner.player_peers():
		total += ResourceStockpile.get_amount(peer_id, FAVOUR)
	return Vector2i(total, maxi(amount, 1))
