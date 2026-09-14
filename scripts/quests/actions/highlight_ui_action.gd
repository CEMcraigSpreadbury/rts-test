class_name HighlightUiAction
extends QuestAction
## Draws attention to a part of the HUD — "the build button is here". A
## highlight stays until something takes it away, so the step that puts one up
## usually has a later step that clears it.

## Which piece of the HUD. Known names are the ones QuestUi can find; anything
## else is ignored.
@export_enum("minimap", "action_panel", "info_panel", "idle_button",
	"resources", "research_button", "quest_tracker")
var element: String = "action_panel"
## Take the highlight off instead of putting one on.
@export var clear: bool = false

func run(runner) -> void:
	runner.show_to_players({kind = "highlight", element = element, show = not clear})
