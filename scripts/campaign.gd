class_name Campaign
extends Resource
## The campaign: its missions in the order they are played. Winning one
## unlocks the next (see CampaignProgress).
##
## There is one, at PATH. Adding a mission is a ScenarioInfo added to its list.

const PATH: String = "res://resources/campaign.tres"

@export var campaign_name: String = "Campaign"
@export var missions: Array[ScenarioInfo] = []

static func current() -> Campaign:
	return load(PATH) as Campaign if ResourceLoader.exists(PATH) else null

## Every mission up to and including the first one not yet won is playable,
## so the campaign opens on mission 1 and unlocks forward.
func unlocked_count() -> int:
	for i in missions.size():
		if not CampaignProgress.is_completed(missions[i].id):
			return i + 1
	return missions.size()

## The mission after `mission_id`, or null after the last one.
func mission_after(mission_id: StringName) -> ScenarioInfo:
	for i in missions.size():
		if missions[i].id == mission_id and i + 1 < missions.size():
			return missions[i + 1]
	return null
