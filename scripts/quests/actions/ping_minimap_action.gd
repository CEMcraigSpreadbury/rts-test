class_name PingMinimapAction
extends QuestAction
## Flashes a spot on everyone's minimap, the same ping a captured point makes.

@export var at: StringName = &""
## Draws the attention-grabbing version instead (used for threats).
@export var hostile: bool = false

func run(runner) -> void:
	runner.show_to_players({kind = "ping", position = runner.position_of(at), hostile = hostile})
