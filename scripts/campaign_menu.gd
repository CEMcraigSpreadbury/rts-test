class_name CampaignMenu
extends PanelContainer
## Mission select for a campaign or the tutorial set: the list, what each
## mission is about, the difficulty and Ruler to play it with, and Start.
##
## Built in code rather than authored, like MatchSettingsRow — it is only ever
## used from the main menu and needs no configuration.

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
	## Same shell as Campaigns, Skirmish and the lobby.
	_shell = ModalShell.dress(self, "Campaign", "Missions", 960)
	var left := _shell.left
	var right := _shell.right

	left.add_child(ModalShell.column_head("Mission"))
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 330)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_mission_selected)
	left.add_child(_list)

	_mission_title = UiTextLine.make("", &"CaptionLabel", UiStyle.SIZE_LABEL, UiStyle.ACCENT).label
	right.add_child(_mission_title.get_parent())
	_mission_text = Label.new()
	_mission_text.theme_type_variation = &"ProseLabel"
	_mission_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	## Autowrap measures its height at its narrowest width, so a wrapping label
	## needs an explicit minimum width or the column springs to maximum.
	## Capped, not just given a minimum: a longer blurb would otherwise wrap to
	## more lines and grow the panel, and picking a campaign must not resize the
	## window it is being picked in.
	_mission_text.custom_minimum_size = Vector2(420, 150)
	_mission_text.max_lines_visible = 6
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
	_shell.eyebrow_label.text = campaign.campaign_name.to_upper()
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
