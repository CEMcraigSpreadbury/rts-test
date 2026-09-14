class_name PopulationCondition
extends QuestCondition
## "Reach 20 population" — the team's used population added together.

@export var amount: int = 10

func progress(runner) -> Vector2i:
	var used := 0
	for peer_id in runner.player_peers():
		used += Population.get_used(peer_id)
	return Vector2i(used, maxi(amount, 1))
