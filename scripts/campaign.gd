class_name Campaign
extends Resource
## An ordered run of scenarios — the tutorial set, or the campaign proper.
## Winning one unlocks the next (see CampaignProgress).

const CAMPAIGNS_DIR: String = "res://resources/campaigns/"

## Stable across renames: progress is saved against this.
@export var id: StringName = &""
@export var campaign_name: String = "Campaign"
## What the menu says under the title.
@export_multiline var description: String = ""
## In the order they are played.
@export var missions: Array[ScenarioInfo] = []
## Sorts the menu list; lower comes first.
@export var order: int = 0

static func list_all() -> Array[Campaign]:
	var out: Array[Campaign] = []
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(CAMPAIGNS_DIR)):
		return out
	var files: PackedStringArray = ResourceLoader.list_directory(CAMPAIGNS_DIR)
	files.sort()
	for file in files:
		if not (file.ends_with(".tres") or file.ends_with(".res")):
			continue
		var campaign := load(CAMPAIGNS_DIR + file) as Campaign
		if campaign != null:
			out.append(campaign)
	out.sort_custom(func(a, b): return a.order < b.order)
	return out

## The mission after this one in this campaign, or null at the end of it.
func mission_after(mission_id: StringName) -> ScenarioInfo:
	for i in missions.size():
		if missions[i].id == mission_id and i + 1 < missions.size():
			return missions[i + 1]
	return null

## The mission that follows this one, in whichever campaign holds it — what the
## victory screen offers so a player can carry straight on.
static func next_mission_after(mission_id: StringName) -> ScenarioInfo:
	for campaign in list_all():
		var next := campaign.mission_after(mission_id)
		if next != null:
			return next
	return null

## How far the player has got: every mission up to and including the first one
## they haven't won is playable, so a campaign opens on mission 1 and unlocks
## forward. Returns the number of playable missions.
func unlocked_count() -> int:
	for i in missions.size():
		if not CampaignProgress.is_completed(missions[i].id):
			return i + 1
	return missions.size()
