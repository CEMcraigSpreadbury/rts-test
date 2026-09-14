@tool
class_name ScenarioBuilder
extends RefCounted
## Writes a new scenario scene: a map scene with a Scenario skeleton added on
## top, plus the ScenarioInfo the menus list it by.
##
## Kept out of the dock so it can be run and tested without the editor UI.
##
## The inheritance is done by rewriting the packed scene's text, exactly as
## MapGenerator does: PackedScene.pack() cannot produce an inherited scene from
## script (the editor sets that state internally), so the content is serialised
## normally and its root header swapped for an instance of the map.

const SCENE_DIR: String = "res://scenes/scenarios/"
const INFO_DIR: String = "res://resources/scenarios/"
const TEMP_PATH: String = "user://scenario_builder_tmp.tscn"

## Returns the new scene's path, or "" with the reason in `error`.
static func create(map_scene_path: String, scenario_name: String, error: Array[String] = []) -> String:
	var id: String = scenario_name.strip_edges().to_snake_case().validate_filename().replace(" ", "_")
	if id.is_empty():
		error.append("Give the scenario a name.")
		return ""
	if not ResourceLoader.exists(map_scene_path):
		error.append("No such map scene: %s" % map_scene_path)
		return ""
	var scene_path: String = SCENE_DIR + id + ".tscn"
	if ResourceLoader.exists(scene_path):
		error.append("%s already exists." % scene_path)
		return ""

	var root := Node3D.new()
	root.name = "Main"
	var scenario := Scenario.new()
	scenario.name = "Scenario"
	scenario.scenario_name = scenario_name
	scenario.briefing_title = scenario_name
	_own(root, scenario, root)
	for child_name in ["Slots", "Zones", "Markers"]:
		var group := Node3D.new()
		group.name = child_name
		_own(scenario, group, root)
	var quests := Node.new()
	quests.name = "Quests"
	_own(scenario, quests, root)

	var packed := PackedScene.new()
	var pack_error: int = packed.pack(root)
	root.free()
	if pack_error != OK:
		error.append("Could not pack the scenario (error %d)." % pack_error)
		return ""
	if not _save_inherited(packed, map_scene_path, scene_path, error):
		return ""

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(INFO_DIR))
	var info := ScenarioInfo.new()
	info.id = StringName(id)
	info.scenario_name = scenario_name
	info.scene_path = scene_path
	info.briefing_title = scenario_name
	if ResourceSaver.save(info, INFO_DIR + id + ".tres") != OK:
		error.append("Scene written, but the ScenarioInfo could not be saved.")
	return scene_path

static func _own(parent: Node, child: Node, owner_root: Node) -> void:
	parent.add_child(child)
	child.owner = owner_root

## Serialises `packed`, then rewrites the root header so the scene inherits the
## map instead of being a plain Node3D that merely contains a Scenario node.
static func _save_inherited(packed: PackedScene, map_scene_path: String, scene_path: String, error: Array[String]) -> bool:
	if ResourceSaver.save(packed, TEMP_PATH) != OK:
		error.append("Could not serialise the scenario.")
		return false
	var text: String = FileAccess.get_file_as_string(TEMP_PATH)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PATH))

	var header := RegEx.create_from_string("(?m)^\\[node name=\"Main\" type=\"Node3D\"[^\\]]*\\]$")
	if header.search(text) == null:
		error.append("Unexpected scene layout while writing %s." % scene_path)
		return false
	text = header.sub(text, "[node name=\"Main\" instance=ExtResource(\"map_base\")]")
	var first_marker: int = text.find("[ext_resource")
	if first_marker < 0:
		first_marker = text.find("[node")
	text = text.insert(first_marker,
			"[ext_resource type=\"PackedScene\" path=\"%s\" id=\"map_base\"]\n" % map_scene_path)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCENE_DIR))
	var file := FileAccess.open(scene_path, FileAccess.WRITE)
	if file == null:
		error.append("Cannot write %s." % scene_path)
		return false
	file.store_string(text)
	file.close()
	return true
