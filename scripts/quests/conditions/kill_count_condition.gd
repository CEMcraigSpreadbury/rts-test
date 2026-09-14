class_name KillCountCondition
extends QuestCondition
## "Kill 15 beastmen" — enemies the team has killed since the step became
## active. Neutral guards count; allies never do.

@export var count: int = 10
## Unit.display_name of the victim, or empty for anything hostile.
@export var unit_name: String = ""

var _killed: int = 0

func setup(_runner) -> void:
	_killed = 0

func on_event(runner, event: StringName, data: Dictionary) -> void:
	if event != &"unit_killed":
		return
	if Teams.team_of(data.get("killer_peer", 0)) != runner.player_team():
		return
	if not Teams.is_enemy(data.get("killer_peer", 0), data.get("victim_peer", 0)):
		return
	if unit_name != "" and String(data.get("victim_name", "")) != unit_name:
		return
	_killed += 1

func progress(_runner) -> Vector2i:
	return Vector2i(_killed, maxi(count, 1))
