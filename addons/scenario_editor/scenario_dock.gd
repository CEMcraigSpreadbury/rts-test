@tool
extends VBoxContainer
## The Scenario dock: makes a scenario out of a map, lays out its sides, zones
## and markers, and assembles quest steps with their conditions and actions.
##
## Structure is what this handles; the fields on whatever you select are edited
## in the normal inspector, so there is only one place to learn.

const CONDITIONS_DIR: String = "res://scripts/quests/conditions/"
const ACTIONS_DIR: String = "res://scripts/quests/actions/"
const SCENARIO_SCENE_DIR: String = "res://scenes/scenarios/"
const SCENARIO_INFO_DIR: String = "res://resources/scenarios/"

## Which list on a step an action is added to.
const ACTION_SLOTS: Array[String] = ["on_start", "on_complete", "on_fail"]

var plugin: EditorPlugin

var _map_option: OptionButton
var _name_edit: LineEdit
var _status: Label
var _structure_box: VBoxContainer
var _step_list: ItemList
var _condition_option: OptionButton
var _action_option: OptionButton
var _action_slot_option: OptionButton
var _report: RichTextLabel

var _maps: Array[MapInfo] = []
## Display name -> script path, for the two type pickers.
var _condition_types: Dictionary = {}
var _action_types: Dictionary = {}

func _ready() -> void:
	add_theme_constant_override("separation", 6)
	_build_new_scenario_section()
	_build_structure_section()
	_build_quest_section()
	_build_report_section()
	refresh()

## --- New scenario ---

func _build_new_scenario_section() -> void:
	add_child(_heading("New scenario"))
	_map_option = OptionButton.new()
	_maps = MapInfo.list_all()
	for map in _maps:
		_map_option.add_item(map.map_name)
	add_child(_map_option)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Scenario name"
	add_child(_name_edit)
	var create := Button.new()
	create.text = "Create from map"
	create.pressed.connect(_on_create_pressed)
	add_child(create)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)

func _on_create_pressed() -> void:
	var scenario_name: String = _name_edit.text.strip_edges()
	if scenario_name.is_empty() or _map_option.selected < 0:
		_status.text = "Pick a map and type a name."
		return
	var map: MapInfo = _maps[_map_option.selected]
	var problems: Array[String] = []
	var scene_path: String = ScenarioBuilder.create(map.scene_path, scenario_name, problems)
	if scene_path.is_empty():
		_status.text = "\n".join(problems)
		return
	EditorInterface.get_resource_filesystem().scan()
	EditorInterface.open_scene_from_path(scene_path)
	_status.text = "Created %s" % scene_path
	if not problems.is_empty():
		_status.text += "\n" + "\n".join(problems)

## --- Structure ---

func _build_structure_section() -> void:
	_structure_box = VBoxContainer.new()
	add_child(_structure_box)
	_structure_box.add_child(_heading("Scenario"))
	for entry in [["Add side", _add_slot], ["Add zone", _add_zone],
			["Add marker", _add_marker], ["Add quest step", _add_step]]:
		var button := Button.new()
		button.text = entry[0]
		button.pressed.connect(entry[1])
		_structure_box.add_child(button)

func _scenario() -> Scenario:
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return null
	if root is Scenario:
		return root
	return root.get_node_or_null(^"Scenario") as Scenario

## Makes sure the named container exists under the Scenario, and hands it back.
func _group(scenario: Scenario, group_name: String, three_d: bool) -> Node:
	var existing: Node = scenario.get_node_or_null(NodePath(group_name))
	if existing != null:
		return existing
	var group: Node = Node3D.new() if three_d else Node.new()
	group.name = group_name
	scenario.add_child(group)
	group.owner = EditorInterface.get_edited_scene_root()
	return group

func _add_node(parent: Node, node: Node, node_name: String) -> void:
	node.name = node_name
	parent.add_child(node)
	node.owner = EditorInterface.get_edited_scene_root()
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(node)
	EditorInterface.mark_scene_as_unsaved()
	refresh()

func _add_slot() -> void:
	var scenario := _scenario()
	if scenario == null:
		return
	var slots := _group(scenario, "Slots", true)
	_add_node(slots, ScenarioSlot.new(), "Side%d" % (slots.get_child_count() + 1))

func _add_zone() -> void:
	var scenario := _scenario()
	if scenario == null:
		return
	var zones := _group(scenario, "Zones", true)
	## Dropped where the viewport camera is looking, so it lands on screen
	## rather than at the map's origin.
	var zone := ScenarioZone.new()
	_add_node(zones, zone, "Zone%d" % (zones.get_child_count() + 1))

func _add_marker() -> void:
	var scenario := _scenario()
	if scenario == null:
		return
	var markers := _group(scenario, "Markers", true)
	_add_node(markers, Marker3D.new(), "Marker%d" % (markers.get_child_count() + 1))

func _add_step() -> void:
	var scenario := _scenario()
	if scenario == null:
		return
	var quests := _group(scenario, "Quests", false)
	var step := QuestStep.new()
	step.title = "New objective"
	_add_node(quests, step, "Step%d" % (quests.get_child_count() + 1))

## --- Quest steps ---

func _build_quest_section() -> void:
	add_child(_heading("Quest steps"))
	_step_list = ItemList.new()
	_step_list.custom_minimum_size = Vector2(0, 140)
	_step_list.item_selected.connect(_on_step_selected)
	add_child(_step_list)

	_condition_types = _scan_types(CONDITIONS_DIR)
	_action_types = _scan_types(ACTIONS_DIR)

	_condition_option = OptionButton.new()
	for type_name in _condition_types:
		_condition_option.add_item(type_name)
	add_child(_condition_option)
	var add_condition := Button.new()
	add_condition.text = "Add condition to selected step"
	add_condition.pressed.connect(_on_add_condition)
	add_child(add_condition)
	var add_fail := Button.new()
	add_fail.text = "Add as fail condition"
	add_fail.pressed.connect(_on_add_fail_condition)
	add_child(add_fail)

	_action_option = OptionButton.new()
	for type_name in _action_types:
		_action_option.add_item(type_name)
	add_child(_action_option)
	_action_slot_option = OptionButton.new()
	for slot_name in ACTION_SLOTS:
		_action_slot_option.add_item(slot_name)
	_action_slot_option.select(1)
	add_child(_action_slot_option)
	var add_action := Button.new()
	add_action.text = "Add action to selected step"
	add_action.pressed.connect(_on_add_action)
	add_child(add_action)

## Every condition/action script in a folder, so a new type shows up here the
## moment its script exists — no list to keep in step with.
func _scan_types(dir_path: String) -> Dictionary:
	var out: Dictionary = {}
	var names := PackedStringArray()
	for file in ResourceLoader.list_directory(dir_path):
		if file.ends_with(".gd"):
			names.append(file)
	names.sort()
	for file in names:
		var script: Script = load(dir_path + file)
		if script == null:
			continue
		var type_name: String = script.get_global_name()
		out[type_name if type_name != "" else file] = dir_path + file
	return out

func _selected_step() -> QuestStep:
	var scenario := _scenario()
	if scenario == null or _step_list.get_selected_items().is_empty():
		return null
	var quests: Node = scenario.get_node_or_null(^"Quests")
	if quests == null:
		return null
	var index: int = _step_list.get_selected_items()[0]
	if index < 0 or index >= quests.get_child_count():
		return null
	return quests.get_child(index) as QuestStep

func _on_step_selected(index: int) -> void:
	var step := _selected_step()
	if step != null:
		EditorInterface.get_selection().clear()
		EditorInterface.get_selection().add_node(step)

func _on_add_condition() -> void:
	_append_resource(_condition_types, _condition_option, "conditions")

func _on_add_fail_condition() -> void:
	_append_resource(_condition_types, _condition_option, "fail_conditions")

func _on_add_action() -> void:
	_append_resource(_action_types, _action_option, ACTION_SLOTS[maxi(_action_slot_option.selected, 0)])

## Appends a fresh instance of the chosen type to one of the step's lists. The
## step stays selected, so the new entry can be filled in in the inspector.
func _append_resource(types: Dictionary, option: OptionButton, property: String) -> void:
	var step := _selected_step()
	if step == null or option.selected < 0:
		_report.text = "Select a quest step first."
		return
	var type_name: String = option.get_item_text(option.selected)
	var script: Script = load(types[type_name])
	if script == null:
		return
	var list: Array = step.get(property).duplicate()
	list.append(script.new())
	step.set(property, list)
	EditorInterface.mark_scene_as_unsaved()
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(step)
	_report.text = "Added %s to %s.%s" % [type_name, step.name, property]

## --- Validation ---

func _build_report_section() -> void:
	var validate := Button.new()
	validate.text = "Validate scenario"
	validate.pressed.connect(_validate)
	add_child(validate)
	var play := Button.new()
	play.text = "Play scenario"
	play.pressed.connect(func(): EditorInterface.play_current_scene())
	add_child(play)
	_report = RichTextLabel.new()
	_report.custom_minimum_size = Vector2(0, 120)
	_report.bbcode_enabled = false
	add_child(_report)

## The mistakes that are easy to make and hard to spot: a step nothing can
## satisfy, a requirement naming a step that isn't there, a loop, a zone or
## marker a quest refers to that doesn't exist, and a mission with no way to
## win.
func _validate() -> void:
	var scenario := _scenario()
	if scenario == null:
		_report.text = "No Scenario node in this scene."
		return
	var problems: Array[String] = []
	var slots := scenario.slots()
	if slots.is_empty():
		problems.append("No sides: add at least one HUMAN slot.")
	var has_human := false
	for slot in slots:
		if slot.kind == ScenarioSlot.Kind.HUMAN:
			has_human = true
		if slot.spawn_point_index < 0 and slot.placed_entities().is_empty() and slot.kind != ScenarioSlot.Kind.DEFENDERS:
			problems.append("%s has no spawn point and nothing placed under it." % slot.name)
	if not has_human:
		problems.append("No HUMAN side: nobody would be playing this.")

	var quests: Node = scenario.get_node_or_null(^"Quests")
	var steps: Array[QuestStep] = []
	if quests != null:
		for child in quests.get_children():
			if child is QuestStep:
				steps.append(child)
	if steps.is_empty():
		problems.append("No quest steps.")
	var names: Array[String] = []
	for step in steps:
		names.append(String(step.name))
	## Everything the scenario places by hand, which is what a quest can name.
	var placed: Array[String] = []
	for slot in slots:
		for entity in slot.placed_entities():
			placed.append(String(entity.name))
	var wins := false
	for step in steps:
		for path in step.requires:
			var target: String = String(path).get_file()
			if not names.has(target):
				problems.append("%s requires '%s', which is not a step here." % [step.name, target])
			elif target == String(step.name):
				problems.append("%s requires itself." % step.name)
		if step.conditions.is_empty() and step.on_complete.is_empty() and step.on_start.is_empty():
			problems.append("%s does nothing: no conditions and no actions." % step.name)
		for action in step.on_complete + step.on_start + step.on_fail:
			if action is EndMissionAction and action.victory:
				wins = true
			if action != null and "at" in action and String(action.at) != "" \
					and not _place_exists(scenario, String(action.at)):
				problems.append("%s refers to '%s', which is not a zone or marker." % [step.name, action.at])
			problems.append_array(_missing_targets(step, action, placed))
		## A condition naming something that was never placed would sit at zero
		## forever — or, for a destroy condition, be satisfied from the start.
		for condition in step.conditions + step.fail_conditions:
			problems.append_array(_missing_targets(step, condition, placed))
	if not wins:
		problems.append("Nothing wins this mission: no EndMissionAction with victory set.")

	if problems.is_empty():
		_report.text = "No problems found. %d side(s), %d step(s)." % [slots.size(), steps.size()]
	else:
		_report.text = "\n".join(problems)

## Names of placed units/buildings a condition or action refers to that the
## scenario does not actually have.
func _missing_targets(step: QuestStep, resource: Resource, placed: Array[String]) -> Array[String]:
	var problems: Array[String] = []
	if resource == null:
		return problems
	for property in ["target_names", "entity_name"]:
		if not (property in resource):
			continue
		var value = resource.get(property)
		var wanted: Array = value if value is Array else ([value] if String(value) != "" else [])
		for entry in wanted:
			if not placed.has(String(entry)):
				problems.append("%s names '%s', which nothing in this scenario places." % [step.name, entry])
	return problems

func _place_exists(scenario: Scenario, place_name: String) -> bool:
	for group_name in ["Zones", "Markers"]:
		var group: Node = scenario.get_node_or_null(NodePath(group_name))
		if group != null and group.get_node_or_null(NodePath(place_name)) != null:
			return true
	return false

## --- Refresh ---

func refresh() -> void:
	var scenario := _scenario()
	_structure_box.visible = scenario != null
	_step_list.clear()
	if scenario == null:
		_status.text = "Open a scenario scene, or make one above."
		return
	_status.text = "Editing %s" % scenario.scenario_name
	var quests: Node = scenario.get_node_or_null(^"Quests")
	if quests == null:
		return
	for child in quests.get_children():
		if child is QuestStep:
			_step_list.add_item("%s — %s" % [child.name, child.title])

func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.85, 0.72, 0.42))
	return label
