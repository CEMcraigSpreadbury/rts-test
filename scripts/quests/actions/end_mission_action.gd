class_name EndMissionAction
extends QuestAction
## Wins or loses the mission. Nothing ends a scenario by itself except the
## ordinary "your whole team lost its bases" rule, so every other ending is
## one of these on a step.

@export var victory: bool = true

func run(runner) -> void:
	runner.end_mission(victory)
