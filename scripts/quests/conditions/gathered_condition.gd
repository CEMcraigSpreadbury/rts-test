class_name GatheredCondition
extends QuestCondition
## "Bring in 100 wood" — what the players' workers carry home since the step
## became active. Unlike HaveResourcesCondition, spending it doesn't undo it,
## and income from settlements doesn't count: it is about the gathering.

@export var resource_type: ResourceType
@export var amount: int = 100

var _gathered: int = 0

func setup(_runner) -> void:
	_gathered = 0

func on_event(runner, event: StringName, data: Dictionary) -> void:
	if event != &"resource_gathered" or data.get("resource_type") != resource_type:
		return
	if not runner.player_peers().has(data.get("peer_id", 0)):
		return
	_gathered += int(data.get("amount", 0))

func progress(_runner) -> Vector2i:
	return Vector2i(mini(_gathered, maxi(amount, 1)), maxi(amount, 1))
