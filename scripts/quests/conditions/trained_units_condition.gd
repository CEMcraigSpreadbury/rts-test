class_name TrainedUnitsCondition
extends QuestCondition
## "Train 5 soldiers" — counted as the team trains them, so losing one later
## doesn't undo the objective. Only units trained after the step became active
## count.

## ProducibleItem.item_name, e.g. "Soldier". Empty counts every unit trained.
@export var unit_name: String = ""
@export var count: int = 1

var _trained: int = 0

func setup(_runner) -> void:
	_trained = 0

func on_event(runner, event: StringName, data: Dictionary) -> void:
	if event != &"unit_trained":
		return
	if Teams.team_of(data.get("peer_id", 0)) != runner.player_team():
		return
	if unit_name != "" and String(data.get("item_name", "")) != unit_name:
		return
	_trained += 1

func progress(_runner) -> Vector2i:
	return Vector2i(_trained, maxi(count, 1))
