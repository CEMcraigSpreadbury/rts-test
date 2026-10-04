class_name ShowControlsAction
extends QuestAction
## Puts up the controls card (every click and key, see UiControlsCard). It
## takes its turn in the dialogue queue, so it comes after the lines before it
## and the lines after it wait until it is closed. Holds a single player game
## while it is up.

func run(runner) -> void:
	runner.show_to_players({kind = "controls"})
