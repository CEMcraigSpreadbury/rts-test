class_name CapturePointsCondition
extends QuestCondition
## "Take the beacon" / "hold two points for three minutes". Ownership is
## team-wide, so an ally holding one counts.

## A point's letter ("A"), or empty for any of them.
@export var point_letter: String = ""
## How many points must be held at once (ignored when a letter is named).
@export var count: int = 1
## Seconds they have to stay held; 0 = taking them is enough.
@export var hold_seconds: float = 0.0

## Match time the team first held enough of them, or -1 while it doesn't.
var _held_since: float = -1.0

func setup(_runner) -> void:
	_held_since = -1.0

func progress(runner) -> Vector2i:
	var held := 0
	var wanted: int = maxi(count, 1)
	for node in runner.get_tree().get_nodes_in_group(&"objectives"):
		if point_letter != "" and node.letter != point_letter:
			continue
		if node.owner_peer_id > 0 and Teams.team_of(node.owner_peer_id) == runner.player_team():
			held += 1
	if point_letter != "":
		wanted = 1
	if held < wanted:
		_held_since = -1.0
		return Vector2i(held, wanted) if hold_seconds <= 0.0 else Vector2i(0, maxi(int(hold_seconds), 1))
	if hold_seconds <= 0.0:
		return Vector2i(held, wanted)
	if _held_since < 0.0:
		_held_since = runner.time
	return Vector2i(int(runner.time - _held_since), maxi(int(hold_seconds), 1))
