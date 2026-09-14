class_name QuestCondition
extends Resource
## One thing a quest step is waiting for. Subclasses live in
## scripts/quests/conditions/ — adding a new kind of condition means adding one
## script there and nothing else (the editor dock finds them by scanning the
## folder).
##
## Conditions are asked about four times a second, and told about things that
## happen (see QuestRunner.notify) as they happen. Counting is team-wide: a
## co-op team's soldiers, kills and resources all add up together, because the
## team plays one quest.
##
## The runner duplicates every condition as a mission starts, so a condition
## that counts events can keep its own tally without two steps sharing one
## authored resource ever crossing wires.

## Shown in the tracker. Left empty, the step's own title carries it.
@export var label: String = ""

## Called once when the step holding this condition becomes active.
func setup(_runner) -> void:
	pass

## Current progress and what it is aiming at, e.g. (2, 5) for "2 of 5
## soldiers". A condition with nothing to count returns (0, 1) / (1, 1).
func progress(_runner) -> Vector2i:
	return Vector2i(0, 1)

func is_met(runner) -> bool:
	var p: Vector2i = progress(runner)
	return p.x >= p.y

## Something happened (see QuestRunner.notify): a unit was trained, a building
## finished, something died, a point changed hands. Only conditions that count
## events need this.
func on_event(_runner, _event: StringName, _data: Dictionary) -> void:
	pass
