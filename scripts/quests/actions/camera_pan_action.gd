class_name CameraPanAction
extends QuestAction
## Puts every player's camera over a named zone or marker — "look what just
## arrived".

@export var at: StringName = &""

func run(runner) -> void:
	runner.show_to_players({kind = "camera", position = runner.position_of(at)})
