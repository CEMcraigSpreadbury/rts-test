class_name CampaignMenu
extends VBoxContainer
## Mission select for a campaign or the tutorial set: the list, what each
## mission is about, the difficulty and Ruler to play it with, and Start.
##
## Built in code rather than authored, like MatchSettingsRow — it is only ever
## used from the main menu and needs no configuration.

signal closed

const LOCKED_COLOR: Color = Color(0.55, 0.53, 0.48)
const COMPLETED_COLOR: Color = Color(0.55, 0.85, 0.55)

var _campaign: Campaign = null
var _list: ItemList
var _mission_title: Label
var _mission_text: Label
var _difficulty: OptionButton
var _ruler: RulerPicker
var _start_button: Button
## Index into the campaign's missions, or -1.
var _selected: int = -1

func _init() -> void:
	name = "CampaignMenu"
	add_theme_constant_override("separation", 8)

	var heading := Label.new()
	heading.name = "Heading"
	heading.add_theme_font_size_override("font_size", 24)
	add_child(heading)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	add_child(row)

	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(260, 220)
	_list.item_selected.connect(_on_mission_selected)
	row.add_child(_list)

	var details := VBoxContainer.new()
	details.custom_minimum_size = Vector2(340, 0)
	row.add_child(details)
	_mission_title = Label.new()
	_mission_title.add_theme_font_size_override("font_size", 18)
	details.add_child(_mission_title)
	_mission_text = Label.new()
	_mission_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mission_text.custom_minimum_size = Vector2(340, 120)
	details.add_child(_mission_text)

	var settings := HBoxContainer.new()
	add_child(settings)
	_difficulty = OptionButton.new()
	for difficulty_name in Network.AI_DIFFICULTY_NAMES:
		_difficulty.add_item(difficulty_name)
	_difficulty.select(Network.campaign_difficulty)
	settings.add_child(_difficulty)
	_ruler = RulerPicker.new(0)
	settings.add_child(_ruler)

	_start_button = Button.new()
	_start_button.text = "Start mission"
	_start_button.custom_minimum_size = Vector2(0, 36)
	_start_button.pressed.connect(_on_start_pressed)
	add_child(_start_button)

	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(func(): closed.emit())
	add_child(back)

func open(campaign: Campaign) -> void:
	_campaign = campaign
	visible = true
	get_node(^"Heading").text = campaign.campaign_name
	_refresh()

## Locked missions stay on the list, greyed — seeing what is still to come is
## part of the point.
func _refresh() -> void:
	_list.clear()
	if _campaign == null:
		return
	var unlocked: int = _campaign.unlocked_count()
	for i in _campaign.missions.size():
		var info: ScenarioInfo = _campaign.missions[i]
		var done: bool = CampaignProgress.is_completed(info.id)
		var label: String = "%d. %s" % [i + 1, info.scenario_name]
		if done:
			label += "  (completed)"
		_list.add_item(label)
		if i >= unlocked:
			_list.set_item_disabled(i, true)
			_list.set_item_custom_fg_color(i, LOCKED_COLOR)
		elif done:
			_list.set_item_custom_fg_color(i, COMPLETED_COLOR)
	var pick: int = mini(maxi(_selected, 0), maxi(unlocked - 1, 0))
	if _list.item_count > 0:
		_list.select(pick)
		_on_mission_selected(pick)

func _on_mission_selected(index: int) -> void:
	_selected = index
	var info: ScenarioInfo = _campaign.missions[index]
	_mission_title.text = info.briefing_title if info.briefing_title != "" else info.scenario_name
	_mission_text.text = info.briefing_text
	_start_button.disabled = index >= _campaign.unlocked_count()

func _on_start_pressed() -> void:
	if _campaign == null or _selected < 0 or _selected >= _campaign.missions.size():
		return
	var info: ScenarioInfo = _campaign.missions[_selected]
	if _selected >= _campaign.unlocked_count() or info.scene_path.is_empty():
		return
	## A mission is a single player match until the lobby learns about
	## campaigns (step 9), so it starts on the offline peer the same way the
	## single player map select does.
	Network.start_offline()
	Network.campaign_difficulty = _difficulty.selected
	Network.current_scenario_id = info.id
	Network.set_my_ruler(_ruler.selected_ruler())
	Network.resolve_random_rulers()
	SceneLoader.change_scene(info.scene_path)
