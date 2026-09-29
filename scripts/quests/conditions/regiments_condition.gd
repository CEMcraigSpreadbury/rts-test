class_name RegimentsCondition
extends QuestCondition
## "Form a regiment" / "bring two regiments into a Lord's army" — regiments the
## players field right now, so one cut down below `min_size` stops counting.

@export var count: int = 1
## Men still standing in it.
@export var min_size: int = Regiment.MIN_SIZE
## Unit.display_name of its men ("Soldier"), or empty for any.
@export var unit_name: String = ""
## Only regiments in a Lord's army.
@export var in_lords_army: bool = false

func progress(runner) -> Vector2i:
	var peers: Array[int] = runner.player_peers()
	var have := 0
	for regiment in runner.main.regiments.values():
		if not peers.has(regiment.owner_peer_id):
			continue
		regiment.prune()
		if regiment.members.is_empty() or regiment.strength() < min_size:
			continue
		if unit_name != "" and regiment.members[0].display_name != unit_name:
			continue
		if in_lords_army and regiment.lord(runner.get_tree()) == null:
			continue
		have += 1
	return Vector2i(have, maxi(count, 1))
