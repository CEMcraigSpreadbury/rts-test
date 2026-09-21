class_name CampaignSelect
extends PanelContainer
## Which campaign to play — the tutorial set, the war itself, or whatever else
## is dropped into resources/campaigns/. Picking one opens its mission list
## (CampaignMenu).
##
## Built in code like the other menu panels; it needs no configuration beyond
## the campaign resources themselves.

## A campaign was chosen; the main menu opens its missions.
signal campaign_chosen(campaign: Campaign)
signal closed

const DONE_COLOR: Color = UiStyle.GOOD

var _list: ItemList
var _title: Label
var _description: Label
var _play_button: Button
var _campaigns: Array[Campaign] = []
var _selected: int = -1
var _shell: ModalShell

func _init() -> void:
	name = "CampaignSelect"
	## The shared setup-screen shell, so this reads as the same program as the
	## skirmish and lobby screens rather than its own layout.
	_shell = ModalShell.dress(self, "Single Player", "Campaigns", 960)
	var left := _shell.left
	var right := _shell.right
	var footer := _shell.footer

	left.add_child(ModalShell.column_head("Campaign"))
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 300)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_selected)
	_list.item_activated.connect(func(_i): _on_play_pressed())
	left.add_child(_list)

	_title = UiTextLine.make("", &"CaptionLabel", UiStyle.SIZE_LABEL, UiStyle.ACCENT).label
	right.add_child(_title.get_parent())
	_description = Label.new()
	_description.theme_type_variation = &"ProseLabel"
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	## Autowrap reports its height for the NARROWEST width, so a wrapping label
	## needs an explicit minimum width or the column springs to maximum.
	## Capped, not just given a minimum: a longer blurb would otherwise wrap to
	## more lines and grow the panel, and picking a campaign must not resize the
	## window it is being picked in.
	_description.custom_minimum_size = Vector2(420, 150)
	_description.max_lines_visible = 6
	right.add_child(_description)

	var back := UiButton.new()
	back.text = "Back"
	back.pressed.connect(func(): closed.emit())
	footer.add_child(back)
	_play_button = UiButton.new()
	_play_button.text = "Missions"
	_play_button.primary = true
	_play_button.pressed.connect(_on_play_pressed)
	footer.add_child(_play_button)

func open() -> void:
	visible = true
	refresh()

## Re-read every time it is shown: winning a mission changes the counts.
func refresh() -> void:
	_campaigns = Campaign.list_all()
	_list.clear()
	for campaign in _campaigns:
		var done: int = campaign.completed_count()
		var total: int = campaign.missions.size()
		_list.add_item("%s  (%d/%d)" % [campaign.campaign_name, done, total])
		if total > 0 and done == total:
			_list.set_item_custom_fg_color(_list.item_count - 1, DONE_COLOR)
	if _list.item_count > 0:
		var pick: int = clampi(_selected, 0, _list.item_count - 1)
		_list.select(pick)
		_on_selected(pick)
	_play_button.disabled = _list.item_count == 0

func _on_selected(index: int) -> void:
	_selected = index
	var campaign: Campaign = _campaigns[index]
	_title.text = campaign.campaign_name.to_upper()
	_description.text = campaign.description

func _on_play_pressed() -> void:
	if _selected >= 0 and _selected < _campaigns.size():
		campaign_chosen.emit(_campaigns[_selected])
