class_name ScenarioInfo
extends Resource
## One playable scenario, the way MapInfo describes one map: what the menus
## list and what a Campaign is made of. The scene it points at is a map scene
## with a Scenario node added (see Scenario).

const SCENARIOS_DIR: String = "res://resources/scenarios/"

## Stable across renames — campaign progress is saved against this.
@export var id: StringName = &""
@export var scenario_name: String = "Scenario"
@export_file("*.tscn") var scene_path: String = ""
## Shown on the briefing screen before the mission starts.
@export var briefing_title: String = ""
@export_multiline var briefing_text: String = ""
## How many people can play it together; 1 for a solo mission.
@export var human_slots: int = 1

static func list_all() -> Array[ScenarioInfo]:
	var out: Array[ScenarioInfo] = []
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(SCENARIOS_DIR)):
		return out
	var files: PackedStringArray = ResourceLoader.list_directory(SCENARIOS_DIR)
	files.sort()
	for file in files:
		if not (file.ends_with(".tres") or file.ends_with(".res")):
			continue
		var info := load(SCENARIOS_DIR + file) as ScenarioInfo
		if info != null:
			out.append(info)
	return out
