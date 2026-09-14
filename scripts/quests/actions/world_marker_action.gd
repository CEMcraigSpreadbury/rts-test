class_name WorldMarkerAction
extends QuestAction
## A ring on the ground saying "here" — where to move, what to attack, what to
## defend. Markers stay until something clears them, so a step that puts one
## down usually has a later step that takes it away.

@export var at: StringName = &""
## Lets a later action clear this exact marker; markers sharing an id replace
## each other.
@export var marker_id: StringName = &"default"
@export var radius: float = 3.0
## Take the marker away instead of putting one down.
@export var clear: bool = false

func run(runner) -> void:
	runner.show_to_players({
		kind = "marker",
		id = String(marker_id),
		position = runner.position_of(at),
		radius = radius,
		show = not clear,
	})
