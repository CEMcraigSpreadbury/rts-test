class_name CampaignMenu
extends PanelContainer
## The campaign screen: its missions, the chosen one's briefing, the
## difficulty and Ruler to play it with, and Begin.
##
## Built in code like the other menu panels; everything it shows comes from
## the Campaign resource and its ScenarioInfos.

signal closed

const LOCKED_COLOR: Color = UiStyle.DIM
const COMPLETED_COLOR: Color = UiStyle.GOOD

var _campaign: Campaign = null
var _list: ItemList
var _mission_title: Label
var _mission_text: Label
var _difficulty: OptionButton
var _ruler: RulerPicker
var _start_button: Button
## Index into the campaign's missions, or -1.
var _selected: int = -1
var _shell: ModalShell

func _init() -> void:
	name = "CampaignMenu"
	_shell = ModalShell.dress(self, "Campaign", "Campaign", 960)
	var left := _shell.left
	var right := _shell.right

	left.add_child(ModalShell.column_head("Mission"))
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 330)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_mission_selected)
	_list.item_activated.connect(func(_i): _on_start_pressed())
	left.add_child(_list)

	_mission_title = UiTextLine.make("", &"CaptionLabel", UiStyle.SIZE_LABEL, UiStyle.ACCENT).label
	right.add_child(_mission_title.get_parent())
	_mission_text = Label.new()
	_mission_text.theme_type_variation = &"ProseLabel"
	_mission_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	## A wrapping label measures its height at its narrowest width, so it needs
	## a minimum width; capped in lines so picking a mission with a longer
	## briefing never resizes the panel.
	_mission_text.custom_minimum_size = Vector2(420, 190)
	_mission_text.max_lines_visible = 8
	right.add_child(_mission_text)

	right.add_child(SectionRule.new())
	var settings := HBoxContainer.new()
	settings.add_theme_constant_override("separation", UiStyle.SPACE_M)
	right.add_child(settings)
	_difficulty = OptionButton.new()
	for difficulty_name in Network.AI_DIFFICULTY_NAMES:
		_difficulty.add_item(difficulty_name)
	_difficulty.select(Network.campaign_difficulty)
	settings.add_child(_difficulty)
	_ruler = RulerPicker.new(0)
	settings.add_child(_ruler)

	var back := UiButton.new()
	back.text = "Back"
	back.pressed.connect(func(): closed.emit())
	_shell.footer.add_child(back)
	_start_button = UiButton.new()
	_start_button.text = "Begin Mission"
	_start_button.primary = true
	_start_button.pressed.connect(_on_start_pressed)
	_shell.footer.add_child(_start_button)

func open(campaign: Campaign) -> void:
	_campaign = campaign
	visible = true
	_shell.title_label.text = campaign.campaign_name
	_refresh()

## Locked missions stay on the list, greyed, so the player sees what is ahead.
func _refresh() -> void:
	_list.clear()
	if _campaign == null:
		return
	var unlocked: int = _campaign.unlocked_count()
	for i in _campaign.missions.size():
		var info: ScenarioInfo = _campaign.missions[i]
		_list.add_item("%d. %s" % [i + 1, info.scenario_name])
		if i >= unlocked:
			_list.set_item_disabled(i, true)
			_list.set_item_custom_fg_color(i, LOCKED_COLOR)
		elif CampaignProgress.is_completed(info.id):
			_list.set_item_custom_fg_color(i, COMPLETED_COLOR)
	## Opens on the furthest mission the player can play.
	var pick: int = clampi(_selected if _selected >= 0 else unlocked - 1, 0, maxi(unlocked - 1, 0))
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
	launch(info, _difficulty.selected, _ruler.selected_ruler())

## Starts a mission. Also used by the main menu's first-launch tutorial offer,
## which skips this screen.
static func launch(info: ScenarioInfo, difficulty: int, ruler_index: int) -> void:
	Network.start_offline()
	Network.campaign_difficulty = difficulty
	Network.current_scenario_id = info.id
	Network.set_my_ruler(ruler_index)
	Network.resolve_random_rulers()
	SceneLoader.change_scene(info.scene_path)
