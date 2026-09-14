extends Control

## The screen is two panels, one at a time: Connect (how to get into a game)
## and Room (what to play and who is playing it). You only choose a map, a
## mission or an opponent once you are actually in a lobby.
@onready var connect_panel: VBoxContainer = $VBox/Connect
@onready var room_panel: VBoxContainer = $VBox/Room

@onready var quick_play_button: Button = $VBox/Connect/SteamRow/QuickPlayButton
@onready var host_steam_button: Button = $VBox/Connect/SteamRow/HostSteamButton
@onready var searching_label: Label = $VBox/Connect/SearchingRow/SearchingLabel
@onready var cancel_search_button: Button = $VBox/Connect/SearchingRow/CancelSearchButton
@onready var address_edit: LineEdit = $VBox/Connect/ConnectRow/AddressEdit
@onready var host_button: Button = $VBox/Connect/ConnectRow/HostButton
@onready var join_button: Button = $VBox/Connect/ConnectRow/JoinButton
@onready var status_label: Label = $VBox/StatusLabel
@onready var invite_button: Button = $VBox/Room/InviteButton
@onready var map_option: OptionButton = $VBox/Room/MapOption
@onready var player_list: VBoxContainer = $VBox/Room/PlayerList
@onready var start_button: Button = $VBox/Room/StartButton
@onready var disconnect_button: Button = $VBox/Room/DisconnectButton

const MAIN_MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"

## Network.map_index is an index into this (see MapInfo.list_all).
var available_maps: Array[MapInfo] = MapInfo.list_all()

## Under the map picker. Host-editable, read-only for everyone else — same
## rule as the map picker.
var _settings_row: MatchSettingsRow
## Under the player list, host only: fills an empty slot with an AI (see
## Network.add_ai_player). Disabled once the map's spawn points are all taken.
var _add_ai_button: Button
## Campaign mission picker: "Skirmish" plus every mission the host has
## unlocked. Host-editable, mirrored to everyone else like the map is.
var _scenario_option: OptionButton
## Parallel to the picker's items; index 0 is &"" for an ordinary skirmish.
var _scenario_ids: Array[StringName] = []

func _ready() -> void:
	for map in available_maps:
		map_option.add_item(map.map_name)
	map_option.item_selected.connect(Network.set_map)
	Network.map_changed.connect(_on_map_changed)
	## A mission played from the campaign menu earlier in the session leaves its
	## id behind; without clearing it the lobby would quietly carry a single
	## player mission into a multiplayer match.
	Network.set_scenario(&"")
	_scenario_option = OptionButton.new()
	_scenario_option.name = "ScenarioOption"
	_populate_scenarios()
	_scenario_option.item_selected.connect(_on_scenario_picked)
	map_option.add_sibling(_scenario_option)
	map_option.get_parent().move_child(_scenario_option, map_option.get_index())
	Network.scenario_changed.connect(_on_scenario_changed)
	_settings_row = MatchSettingsRow.new()
	_settings_row.edited.connect(func(): Network.set_match_settings(_settings_row.get_mode(), _settings_row.get_target()))
	map_option.add_sibling(_settings_row)
	Network.match_settings_changed.connect(_refresh_match_settings)
	_add_ai_button = Button.new()
	_add_ai_button.name = "AddAiButton"
	_add_ai_button.text = "Add AI"
	_add_ai_button.pressed.connect(func(): Network.add_ai_player())
	player_list.add_sibling(_add_ai_button)
	_refresh_map_option()
	quick_play_button.pressed.connect(_on_quick_play_pressed)
	host_steam_button.pressed.connect(_on_host_steam_pressed)
	invite_button.pressed.connect(Network.invite_friend)
	cancel_search_button.pressed.connect(_on_cancel_search_pressed)
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	start_button.pressed.connect(_on_start_pressed)
	disconnect_button.pressed.connect(_on_disconnect_pressed)
	$VBox/Connect/BackButton.pressed.connect(_on_back_pressed)
	invite_button.visible = false
	_add_ai_button.visible = false
	searching_label.get_parent().visible = false
	_show_connect("Not connected.")

	if not Steamworks.is_available:
		quick_play_button.disabled = true
		quick_play_button.tooltip_text = "Steam must be running to use Quick Play."
		host_steam_button.disabled = true
		host_steam_button.tooltip_text = "Steam must be running to host a Steam lobby."

	Network.player_connected.connect(_refresh_player_list)
	## player_disconnected also hands over the departed player's data, which
	## the refresh has no use for.
	Network.player_disconnected.connect(_refresh_player_list.unbind(1))
	Network.player_updated.connect(_refresh_player_list)
	Network.connected_to_server.connect(_on_connected)
	Network.connection_failed.connect(_on_connection_failed)
	Network.steam_lobby_ready.connect(_on_steam_lobby_ready)
	Network.steam_lobby_failed.connect(_on_steam_lobby_failed)
	UiDebugEditor.register_editable_root(self, "lobby")
	## Otherwise nothing sets the buttons' state until a network signal fires,
	## and Start sits there looking usable in an empty lobby.
	_refresh_player_list()

func _on_quick_play_pressed() -> void:
	var err := Network.quick_play()
	if err != OK:
		status_label.text = "Failed to start Quick Play (error %d)" % err
		return
	status_label.text = ""
	searching_label.text = "Searching for opponent..."
	searching_label.get_parent().visible = true
	_set_connect_controls_enabled(false)

func _on_host_steam_pressed() -> void:
	var err := Network.host_steam_lobby()
	if err != OK:
		status_label.text = "Failed to host Steam lobby (error %d)" % err
		return
	searching_label.text = "Waiting for opponent..."
	searching_label.get_parent().visible = true
	_set_connect_controls_enabled(false)

func _on_cancel_search_pressed() -> void:
	Network.cancel_quick_play()
	_reset_to_idle("Not connected.")

## Covers a stalled lobby (host never presses Start) as well as simply
## changing your mind after connecting — works the same regardless of which
## transport got you connected, since Network.leave_game() already handles
## tearing down either one.
func _on_disconnect_pressed() -> void:
	Network.leave_game()
	_reset_to_idle("Not connected.")

func _on_back_pressed() -> void:
	Network.cancel_quick_play()
	Network.leave_game()
	SceneLoader.change_scene(MAIN_MENU_SCENE_PATH)

## --- Which panel is showing ---

## Back to "how do you want to get into a game", with nothing connected.
func _show_connect(message: String) -> void:
	connect_panel.visible = true
	room_panel.visible = false
	searching_label.get_parent().visible = false
	invite_button.visible = false
	status_label.text = message
	_set_connect_controls_enabled(true)
	_refresh_player_list()

## In a lobby: what to play, who is playing, and Start.
func _show_room(message: String) -> void:
	connect_panel.visible = false
	room_panel.visible = true
	status_label.text = message
	_refresh_map_option()
	_refresh_player_list()

func _reset_to_idle(message: String) -> void:
	_show_connect(message)

func _on_steam_lobby_ready(_lobby_id: int) -> void:
	_show_room("Steam lobby open — waiting for players.")
	invite_button.visible = true

func _on_steam_lobby_failed(reason: String) -> void:
	searching_label.get_parent().visible = false
	status_label.text = reason
	_set_connect_controls_enabled(true)

func _on_host_pressed() -> void:
	var err := Network.host_game()
	if err != OK:
		status_label.text = "Failed to host (error %d)" % err
		return
	_show_room("Hosting on port %d" % Network.DEFAULT_PORT)

func _on_join_pressed() -> void:
	var err := Network.join_game(address_edit.text)
	if err != OK:
		status_label.text = "Failed to join (error %d)" % err
		return
	status_label.text = "Connecting to %s..." % address_edit.text
	_set_connect_controls_enabled(false)
	_refresh_map_option()

func _on_connected() -> void:
	_show_room("Connected.")

func _on_connection_failed() -> void:
	_show_connect("Connection failed.")

## Locks the connect panel's controls while a connection attempt is in flight
## (the panel itself stays up until it either succeeds or is cancelled).
func _set_connect_controls_enabled(enabled: bool) -> void:
	address_edit.editable = enabled
	host_button.disabled = not enabled
	join_button.disabled = not enabled
	quick_play_button.disabled = not enabled or not Steamworks.is_available
	host_steam_button.disabled = not enabled or not Steamworks.is_available

## --- Campaign missions ---

## Only what the host has unlocked is offered: their progress decides what the
## group can play (see CampaignProgress). Missions built for one player are
## left out entirely — there would be nowhere for anyone else to sit.
func _populate_scenarios() -> void:
	_scenario_option.clear()
	_scenario_ids.clear()
	_scenario_option.add_item("Skirmish")
	_scenario_ids.append(&"")
	for campaign in Campaign.list_all():
		var unlocked: int = campaign.unlocked_count()
		for i in mini(unlocked, campaign.missions.size()):
			var info: ScenarioInfo = campaign.missions[i]
			if info.human_slots < 2:
				continue
			_scenario_option.add_item("%s: %s" % [campaign.campaign_name, info.scenario_name])
			_scenario_ids.append(info.id)

func _on_scenario_picked(index: int) -> void:
	if index >= 0 and index < _scenario_ids.size():
		Network.set_scenario(_scenario_ids[index])

## A mission brings its own map, sides and rules, so the map picker and the
## game-mode row have nothing to say while one is chosen.
func _on_scenario_changed() -> void:
	var index: int = maxi(_scenario_ids.find(Network.current_scenario_id), 0)
	_scenario_option.select(index)
	var playing_mission: bool = not String(Network.current_scenario_id).is_empty()
	map_option.visible = not playing_mission
	_settings_row.visible = not playing_mission
	_refresh_player_list()

## A smaller map can't seat everyone the last one did — the host drops the
## newest AIs to fit (see Network.trim_ai_to_capacity).
func _on_map_changed(_index: int) -> void:
	if Network.is_host():
		Network.trim_ai_to_capacity()
	_refresh_map_option()
	_refresh_player_list()

## Only the host (or someone not yet connected, who'll become one by hosting)
## gets to pick — a joined client just sees the host's choice.
func _refresh_map_option() -> void:
	var host_picks: bool = multiplayer.multiplayer_peer == null or Network.is_host()
	if _scenario_option != null:
		_scenario_option.disabled = not host_picks
	if available_maps.is_empty():
		return
	map_option.select(clampi(Network.map_index, 0, available_maps.size() - 1))
	map_option.disabled = not host_picks
	_refresh_match_settings()

func _refresh_match_settings() -> void:
	if _settings_row == null or available_maps.is_empty():
		return
	var map: MapInfo = available_maps[clampi(Network.map_index, 0, available_maps.size() - 1)]
	var editable := multiplayer.multiplayer_peer == null or Network.is_host()
	_settings_row.show_values(Network.game_mode, Network.favour_target, map, editable)

func _refresh_player_list(_peer_id: int = -1) -> void:
	_refresh_map_option()
	for child in player_list.get_children():
		player_list.remove_child(child)
		child.queue_free()
	var is_host := Network.is_host()
	for id in Network.players:
		var row := HBoxContainer.new()
		var is_ai := Network.is_ai(id)
		var name_label := Label.new()
		name_label.text = "%s%s" % [Network.players[id].get("name", "Player %d" % id), " (you)" if id == Network.my_peer_id() else ""]
		row.add_child(name_label)

		## Your own Ruler, or — for the host — an AI's.
		var ruler_index: int = Network.players[id].get("ruler_index", 0)
		if id == Network.my_peer_id() or (is_ai and is_host):
			var ruler_option := RulerPicker.new(ruler_index)
			if is_ai:
				ruler_option.ruler_picked.connect(func(i): Network.set_ai_ruler(id, i))
			else:
				ruler_option.ruler_picked.connect(Network.set_my_ruler)
			row.add_child(ruler_option)
		else:
			var ruler_label := Label.new()
			ruler_label.text = Ruler.display_name_for(ruler_index)
			row.add_child(ruler_label)

		var swatch := ColorRect.new()
		swatch.color = Network.players[id].get("color", Color.WHITE)
		swatch.custom_minimum_size = Vector2(24, 24)
		row.add_child(swatch)

		## Your own colour, or — for the host — an AI's.
		if id == Network.my_peer_id() or (is_ai and is_host):
			var color_option := OptionButton.new()
			var color_index: int = Network.color_index_of(id)
			## Every colour stays pickable even when someone else holds it —
			## sharing one is how you play as a team (see Teams).
			for i in Network.TEAM_COLORS.size():
				color_option.add_item(Network.TEAM_COLOR_NAMES[i])
			if color_index >= 0:
				color_option.select(color_index)
			if is_ai:
				color_option.item_selected.connect(func(i): Network.set_ai_color(id, i))
			else:
				color_option.item_selected.connect(Network.set_my_color)
			row.add_child(color_option)

		## Everyone else reads an AI's difficulty off its name ("AI 1 (Hard)").
		if is_ai and is_host:
			var difficulty_option := OptionButton.new()
			for difficulty_name in Network.AI_DIFFICULTY_NAMES:
				difficulty_option.add_item(difficulty_name)
			difficulty_option.select(Network.players[id].get("difficulty", Network.AiDifficulty.NORMAL))
			difficulty_option.item_selected.connect(func(i): Network.set_ai_difficulty(id, i))
			row.add_child(difficulty_option)

		var ready_check := CheckButton.new()
		ready_check.text = "Ready"
		ready_check.button_pressed = Network.players[id].get("ready", false)
		if id == Network.my_peer_id():
			ready_check.toggled.connect(Network.set_my_ready)
		else:
			ready_check.disabled = true
		row.add_child(ready_check)

		if is_ai and is_host:
			var remove_button := Button.new()
			remove_button.text = "Remove"
			remove_button.pressed.connect(Network.remove_ai_player.bind(id))
			row.add_child(remove_button)

		player_list.add_child(row)

	_add_ai_button.visible = is_host
	_add_ai_button.disabled = Network.players.size() >= Network.player_capacity()
	## Always on screen, greyed until it would actually do something: hiding it
	## until you host made a lobby where you had picked a mission and added an
	## AI look like it had no way to begin.
	start_button.disabled = not (is_host and Network.all_players_ready() and Network.can_start_match())

func _on_start_pressed() -> void:
	if not Network.is_host():
		return
	if not Network.all_players_ready() or not Network.can_start_match():
		return
	if available_maps.is_empty():
		return
	Network.mark_steam_lobby_in_progress()
	## Before the buttons lock below: each resolved pick refreshes the player
	## list, which would otherwise re-enable Start.
	Network.resolve_random_rulers()
	start_button.disabled = true
	map_option.disabled = true
	_scenario_option.disabled = true
	_add_ai_button.disabled = true
	_settings_row.set_editable(false)
	## A mission brings its own map; everything else plays the chosen one.
	var scenario: ScenarioInfo = Network.current_scenario()
	if scenario != null:
		SceneLoader.start_match(scenario.scene_path)
		return
	SceneLoader.start_match(available_maps[clampi(Network.map_index, 0, available_maps.size() - 1)].scene_path)
