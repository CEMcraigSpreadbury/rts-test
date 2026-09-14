extends Control

const LOBBY_SCENE_PATH: String = "res://scenes/lobby.tscn"

var available_maps: Array[MapInfo] = MapInfo.list_all()

@onready var menu: VBoxContainer = $Menu
@onready var map_select: VBoxContainer = $MapSelect
@onready var map_option: OptionButton = $MapSelect/MapOption
@onready var options_menu: OptionsMenu = $OptionsMenu

## Same row as the lobby's, but local — handed to Network only on Start.
var _settings_row: MatchSettingsRow
## One row for the local player plus one per AI, rebuilt from Network.players
## whenever it changes. The single player screen runs on an offline peer from
## the moment it opens (see _on_single_player_pressed), so AI slots use the
## same Network.add_ai_player() etc. a lobby host does.
var _players_box: VBoxContainer
var _add_ai_button: Button
## The campaign list and the mission list inside one, built only when there is
## a campaign to show.
var _campaign_select: CampaignSelect = null
var _campaign_menu: CampaignMenu = null

func _ready() -> void:
	$Menu/SinglePlayerButton.pressed.connect(_on_single_player_pressed)
	$Menu/MultiplayerButton.pressed.connect(SceneLoader.change_scene.bind(LOBBY_SCENE_PATH))
	$Menu/OptionsButton.pressed.connect(_on_options_pressed)
	$Menu/ExitButton.pressed.connect(get_tree().quit)
	$MapSelect/StartButton.pressed.connect(_on_start_pressed)
	$MapSelect/BackButton.pressed.connect(_on_map_select_back_pressed)
	for map in available_maps:
		map_option.add_item(map.map_name)
	_settings_row = MatchSettingsRow.new()
	map_option.add_sibling(_settings_row)
	_players_box = VBoxContainer.new()
	_players_box.name = "Players"
	_settings_row.add_sibling(_players_box)
	_add_ai_button = Button.new()
	_add_ai_button.name = "AddAiButton"
	_add_ai_button.text = "Add AI"
	_add_ai_button.custom_minimum_size = Vector2(0, 36)
	_add_ai_button.pressed.connect(_on_add_ai_pressed)
	_players_box.add_sibling(_add_ai_button)
	## A new map always starts back on its own default target.
	map_option.item_selected.connect(func(_i):
		_show_map_default(_settings_row.get_mode())
		_trim_ai_to_map()
		_refresh_players())
	_show_map_default(Network.GameMode.CONQUEST)
	Network.player_updated.connect(_refresh_players.unbind(1))
	Network.player_disconnected.connect(_refresh_players.unbind(2))
	_build_campaign_buttons()
	map_select.visible = false
	options_menu.visible = false
	options_menu.closed.connect(_on_options_closed)
	UiDebugEditor.register_editable_root(self, "main_menu")

## --- Campaigns ---

## Three screens, one at a time: the main menu, the list of campaigns, and the
## missions inside the chosen one. Adding a campaign is a matter of dropping a
## .tres into resources/campaigns/ — no menu code to touch.
func _build_campaign_buttons() -> void:
	if Campaign.list_all().is_empty():
		return
	_campaign_select = CampaignSelect.new()
	_campaign_select.campaign_chosen.connect(_on_campaign_chosen)
	_campaign_select.closed.connect(_on_campaign_select_closed)
	_centre_panel(_campaign_select)

	_campaign_menu = CampaignMenu.new()
	_campaign_menu.closed.connect(_on_campaign_menu_closed)
	_centre_panel(_campaign_menu)

	var button := Button.new()
	button.name = "CampaignButton"
	button.text = "Campaign"
	button.custom_minimum_size = Vector2(0, 36)
	button.pressed.connect(_on_campaign_pressed)
	menu.add_child(button)
	menu.move_child(button, $Menu/SinglePlayerButton.get_index())

## Puts a panel in a screen-sized container that centres it at any window size.
## Centre anchors alone would pin only its top-left corner to the middle and
## let the rest run off the edges. The container must ignore the mouse and be
## hidden while unused, or it swallows every click meant for the screen behind.
func _centre_panel(panel: Control) -> void:
	var centre := CenterContainer.new()
	centre.name = "%sCentre" % panel.name
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.visible = false
	add_child(centre)
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.add_child(panel)

func _on_campaign_pressed() -> void:
	menu.visible = false
	_campaign_select.get_parent().visible = true
	_campaign_select.open()

## Chosen a campaign: swap the list for its missions.
func _on_campaign_chosen(campaign: Campaign) -> void:
	_campaign_select.get_parent().visible = false
	_campaign_menu.get_parent().visible = true
	_campaign_menu.open(campaign)

## Back out of the missions to the campaigns, refreshing the counts in case one
## was just won.
func _on_campaign_menu_closed() -> void:
	_campaign_menu.get_parent().visible = false
	_campaign_select.get_parent().visible = true
	_campaign_select.refresh()

func _on_campaign_select_closed() -> void:
	_campaign_select.get_parent().visible = false
	menu.visible = true

func _on_single_player_pressed() -> void:
	Network.start_offline()
	menu.visible = false
	map_select.visible = true
	_refresh_players()

func _on_map_select_back_pressed() -> void:
	Network.leave_game()
	map_select.visible = false
	menu.visible = true

func _on_start_pressed() -> void:
	if map_option.selected < 0 or not Network.can_start_match():
		return
	Network.set_match_settings(_settings_row.get_mode(), _settings_row.get_target())
	Network.resolve_random_rulers()
	SceneLoader.change_scene(available_maps[map_option.selected].scene_path)

func _show_map_default(mode: int) -> void:
	var map: MapInfo = available_maps[map_option.selected] if map_option.selected >= 0 else null
	_settings_row.show_values(mode, 0, map, true)

func _on_options_pressed() -> void:
	menu.visible = false
	options_menu.open()

func _on_options_closed() -> void:
	menu.visible = true

## --- Player slots ---

## Total players the chosen map has spawn points for (a map that doesn't say
## gets the transport cap).
func _map_capacity() -> int:
	var map: MapInfo = available_maps[map_option.selected] if map_option.selected >= 0 else null
	var cap: int = map.max_players if map != null and map.max_players > 0 else Network.MAX_PLAYERS
	return mini(cap, Network.MAX_PLAYERS)

## Switching to a smaller map drops the newest AIs that no longer fit.
func _trim_ai_to_map() -> void:
	var ids: Array[int] = Network.ai_peer_ids()
	while Network.players.size() > _map_capacity() and not ids.is_empty():
		Network.remove_ai_player(ids.pop_back())

func _on_add_ai_pressed() -> void:
	if Network.players.size() < _map_capacity():
		Network.add_ai_player()

func _refresh_players() -> void:
	if _players_box == null or not map_select.visible:
		return
	for child in _players_box.get_children():
		_players_box.remove_child(child)
		child.queue_free()
	if Network.players.has(1):
		_players_box.add_child(_make_player_row(1))
	for id in Network.ai_peer_ids():
		_players_box.add_child(_make_player_row(id))
	_add_ai_button.disabled = Network.players.size() >= _map_capacity()

func _make_player_row(peer_id: int) -> HBoxContainer:
	var data: Dictionary = Network.players[peer_id]
	var row := HBoxContainer.new()

	var swatch := ColorRect.new()
	swatch.color = data.get("color", Color.WHITE)
	swatch.custom_minimum_size = Vector2(24, 24)
	row.add_child(swatch)

	var name_label := Label.new()
	name_label.text = "AI %d" % (Network.ai_peer_ids().find(peer_id) + 1) if Network.is_ai(peer_id) else data.get("name", "You")
	name_label.custom_minimum_size = Vector2(60, 0)
	row.add_child(name_label)

	var color_option := OptionButton.new()
	var color_index: int = Network.color_index_of(peer_id)
	## Sharing a colour makes those players allies (see Teams), so nothing here
	## is disabled.
	for i in Network.TEAM_COLORS.size():
		color_option.add_item(Network.TEAM_COLOR_NAMES[i])
	if color_index >= 0:
		color_option.select(color_index)
	if Network.is_ai(peer_id):
		color_option.item_selected.connect(func(i): Network.set_ai_color(peer_id, i))
	else:
		color_option.item_selected.connect(Network.set_my_color)
	row.add_child(color_option)

	var ruler_option := RulerPicker.new(data.get("ruler_index", 0))
	if Network.is_ai(peer_id):
		ruler_option.ruler_picked.connect(func(i): Network.set_ai_ruler(peer_id, i))
	else:
		ruler_option.ruler_picked.connect(Network.set_my_ruler)
	row.add_child(ruler_option)

	if Network.is_ai(peer_id):
		var difficulty_option := OptionButton.new()
		for difficulty_name in Network.AI_DIFFICULTY_NAMES:
			difficulty_option.add_item(difficulty_name)
		difficulty_option.select(data.get("difficulty", Network.AiDifficulty.NORMAL))
		difficulty_option.item_selected.connect(func(i): Network.set_ai_difficulty(peer_id, i))
		row.add_child(difficulty_option)

		var remove_button := Button.new()
		remove_button.text = "Remove"
		remove_button.pressed.connect(Network.remove_ai_player.bind(peer_id))
		row.add_child(remove_button)
	return row
