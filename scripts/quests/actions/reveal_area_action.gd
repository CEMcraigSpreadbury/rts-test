class_name RevealAreaAction
extends QuestAction
## Opens a piece of the map up — the scouts' report, or showing the player what
## they are about to walk into.
##
## The revealed circle sees like a unit standing there: while it lasts, units
## inside it show live; once it expires the ground stays explored but goes
## quiet again.

@export var at: StringName = &""
## Defaults to the zone's own radius when it names a zone.
@export var radius: float = 0.0
## 0 keeps it revealed for the rest of the mission.
@export var seconds: float = 0.0

func run(runner) -> void:
	var size: float = radius
	if size <= 0.0:
		var area: ScenarioZone = runner.zone(at)
		size = area.radius if area != null else 12.0
	runner.show_to_players({
		kind = "reveal", position = runner.position_of(at), radius = size, seconds = seconds,
	})
