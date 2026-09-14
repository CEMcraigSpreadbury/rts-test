class_name HaveUnitsCondition
extends QuestCondition
## "Have 10 soldiers" — what the team has alive right now, so losing them puts
## the step back. Use TrainedUnitsCondition for "train 10 soldiers", which
## counts them as they are made and never goes down.

## Unit.display_name, e.g. "Soldier". Empty counts every unit.
@export var unit_name: String = ""
@export var count: int = 1
## Villagers and other workers don't count toward an army.
@export var fighters_only: bool = false

func progress(runner) -> Vector2i:
	var have := 0
	for unit in runner.team_units():
		if unit_name != "" and unit.display_name != unit_name:
			continue
		if fighters_only and unit.can_gather:
			continue
		have += 1
	return Vector2i(have, maxi(count, 1))
