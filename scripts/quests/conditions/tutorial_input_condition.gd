class_name TutorialInputCondition
extends QuestCondition
## Waits for the player to actually do something with the game — the backbone
## of the tutorial missions. "Select a villager", "move the camera", "press B
## to build", "open the research panel".
##
## Everything else a quest watches is about the world; this is the only
## condition about the person playing.

## What to wait for. These are the kinds Main and the HUD report (see
## QuestRunner.report_input).
@export_enum(
	"select_units", "move_order", "attack_order", "patrol_order",
	"camera_move", "camera_rotate", "camera_zoom",
	"hotkey", "formation", "control_group",
	"build_placed", "research_panel", "research_bought", "power_cast")
var kind: String = "select_units"
## Narrows it further where the kind carries one: the key for "hotkey" ("B"),
## the node name for "research_bought", the group number for "control_group".
## Empty accepts any.
@export var detail: String = ""
## How many times it has to happen.
@export var count: int = 1

var _seen: int = 0

func setup(_runner) -> void:
	_seen = 0

func on_event(runner, event: StringName, data: Dictionary) -> void:
	if event != &"player_input" or String(data.get("kind", "")) != kind:
		return
	if Teams.team_of(data.get("peer_id", 0)) != runner.player_team():
		return
	if detail != "" and String(data.get("detail", "")) != detail:
		return
	_seen += 1

func progress(_runner) -> Vector2i:
	return Vector2i(_seen, maxi(count, 1))
