class_name HaveResourcesCondition
extends QuestCondition
## "Gather 500 wood" — what the team is holding, added across its players.
## Spending it again puts the step back, which is what "have 500 wood in hand"
## should mean.

@export var resource_type: ResourceType
@export var amount: int = 100

func progress(runner) -> Vector2i:
	if resource_type == null:
		return Vector2i(0, 1)
	var held := 0
	for peer_id in runner.player_peers():
		held += ResourceStockpile.get_amount(peer_id, resource_type)
	return Vector2i(held, maxi(amount, 1))
