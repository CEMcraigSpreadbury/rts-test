class_name CampaignSelect
extends VBoxContainer
## Which campaign to play — the tutorial set, the war itself, or whatever else
## is dropped into resources/campaigns/. Picking one opens its mission list
## (CampaignMenu).
##
## Built in code like the other menu panels; it needs no configuration beyond
## the campaign resources themselves.

## A campaign was chosen; the main menu opens its missions.
signal campaign_chosen(campaign: Campaign)
signal closed

const DONE_COLOR: Color = Color(0.55, 0.85, 0.55)

var _list: ItemList
var _title: Label
var _description: Label
var _play_button: Button
var _campaigns: Array[Campaign] = []
var _selected: int = -1

func _init() -> void:
	name = "CampaignSelect"
	add_theme_constant_override("separation", 8)

	var heading := Label.new()
	heading.text = "Campaigns"
	heading.add_theme_font_size_override("font_size", 24)
	add_child(heading)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	add_child(row)

	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(260, 180)
	_list.item_selected.connect(_on_selected)
	_list.item_activated.connect(func(_i): _on_play_pressed())
	row.add_child(_list)

	var details := VBoxContainer.new()
	details.custom_minimum_size = Vector2(340, 0)
	row.add_child(details)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 18)
	details.add_child(_title)
	_description = Label.new()
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.custom_minimum_size = Vector2(340, 100)
	details.add_child(_description)

	_play_button = Button.new()
	_play_button.text = "Missions"
	_play_button.custom_minimum_size = Vector2(0, 36)
	_play_button.pressed.connect(_on_play_pressed)
	add_child(_play_button)

	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(func(): closed.emit())
	add_child(back)

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
	_title.text = campaign.campaign_name
	_description.text = campaign.description

func _on_play_pressed() -> void:
	if _selected >= 0 and _selected < _campaigns.size():
		campaign_chosen.emit(_campaigns[_selected])
