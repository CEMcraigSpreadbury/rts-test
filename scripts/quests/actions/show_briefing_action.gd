class_name ShowBriefingAction
extends QuestAction
## Opens the briefing screen part-way through a mission, for the turns in the
## story that deserve more than a line of dialogue.
##
## In single player it holds the game until the player closes it; in
## multiplayer each player gets their own overlay and the match carries on.

@export var title: String = ""
@export_multiline var text: String = ""

func run(runner) -> void:
	runner.show_to_players({kind = "briefing", title = title, text = text})
