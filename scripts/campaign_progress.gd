class_name CampaignProgress
extends RefCounted
## Which missions the player has won, kept in user:// so it survives the game
## closing: a mission id and the hardest difficulty it was won on.
##
## Static, and read off disk the first time it is asked, because the menu and
## the end of a mission both need it and neither owns the other.

const PATH: String = "user://campaign.cfg"
const SECTION: String = "won"

static var _config: ConfigFile = null

static func _load() -> ConfigFile:
	if _config == null:
		_config = ConfigFile.new()
		## A missing file is a player who hasn't won anything yet.
		_config.load(PATH)
	return _config

static func is_completed(scenario_id: StringName) -> bool:
	return _load().has_section_key(SECTION, String(scenario_id))

## The hardest difficulty it has been won on, or -1 if it hasn't.
static func best_difficulty(scenario_id: StringName) -> int:
	return int(_load().get_value(SECTION, String(scenario_id), -1))

static func mark_completed(scenario_id: StringName, difficulty: int) -> void:
	if String(scenario_id).is_empty():
		return
	var config := _load()
	config.set_value(SECTION, String(scenario_id), maxi(difficulty, best_difficulty(scenario_id)))
	config.save(PATH)

static func clear() -> void:
	_config = ConfigFile.new()
	_config.save(PATH)
