extends Control

@onready var quick_play_button: Button = $VBox/SteamRow/QuickPlayButton
@onready var host_steam_button: Button = $VBox/SteamRow/HostSteamButton
@onready var invite_button: Button = $VBox/SteamRow/InviteButton
@onready var searching_label: Label = $VBox/SearchingRow/SearchingLabel
@onready var cancel_search_button: Button = $VBox/SearchingRow/CancelSearchButton
@onready var address_edit: LineEdit = $VBox/ConnectRow/AddressEdit
@onready var host_button: Button = $VBox/ConnectRow/HostButton
@onready var join_button: Button = $VBox/ConnectRow/JoinButton
@onready var status_label: Label = $VBox/StatusLabel
@onready var player_list: VBoxContainer = $VBox/PlayerList
@onready var start_button: Button = $VBox/StartButton
@onready var disconnect_button: Button = $VBox/DisconnectButton

const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"

## Same list (and order) as main.tscn's Main.available_factions — that shared
## order is what a "faction_index" in Network.players actually refers to.
@export var available_factions: Array[Faction] = []

func _ready() -> void:
	quick_play_button.pressed.connect(_on_quick_play_pressed)
	host_steam_button.pressed.connect(_on_host_steam_pressed)
	invite_button.pressed.connect(Network.invite_friend)
	cancel_search_button.pressed.connect(_on_cancel_search_pressed)
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	start_button.pressed.connect(_on_start_pressed)
	disconnect_button.pressed.connect(_on_disconnect_pressed)
	start_button.visible = false
	invite_button.visible = false
	disconnect_button.visible = false
	searching_label.get_parent().visible = false

	if not Steamworks.is_available:
		quick_play_button.disabled = true
		quick_play_button.tooltip_text = "Steam must be running to use Quick Play."
		host_steam_button.disabled = true
		host_steam_button.tooltip_text = "Steam must be running to host a Steam lobby."

	Network.player_connected.connect(_refresh_player_list)
	Network.player_disconnected.connect(_refresh_player_list)
	Network.player_updated.connect(_refresh_player_list)
	Network.connected_to_server.connect(_on_connected)
	Network.connection_failed.connect(_on_connection_failed)
	Network.steam_lobby_ready.connect(_on_steam_lobby_ready)
	Network.steam_lobby_failed.connect(_on_steam_lobby_failed)
	UiDebugEditor.register_editable_root(self, "lobby")

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

func _reset_to_idle(message: String) -> void:
	searching_label.get_parent().visible = false
	invite_button.visible = false
	start_button.visible = false
	status_label.text = message
	_set_connect_controls_enabled(true)
	_refresh_player_list()

func _on_steam_lobby_ready(_lobby_id: int) -> void:
	searching_label.text = "Waiting for opponent..."
	searching_label.get_parent().visible = true
	invite_button.visible = true
	start_button.visible = true
	_refresh_player_list()

func _on_steam_lobby_failed(reason: String) -> void:
	searching_label.get_parent().visible = false
	status_label.text = reason
	_set_connect_controls_enabled(true)

func _on_host_pressed() -> void:
	var err := Network.host_game()
	if err != OK:
		status_label.text = "Failed to host (error %d)" % err
		return
	status_label.text = "Hosting on port %d" % Network.DEFAULT_PORT
	start_button.visible = true
	_set_connect_controls_enabled(false)
	_refresh_player_list()

func _on_join_pressed() -> void:
	var err := Network.join_game(address_edit.text)
	if err != OK:
		status_label.text = "Failed to join (error %d)" % err
		return
	status_label.text = "Connecting to %s..." % address_edit.text
	_set_connect_controls_enabled(false)

func _on_connected() -> void:
	status_label.text = "Connected."
	searching_label.get_parent().visible = false
	_refresh_player_list()

func _on_connection_failed() -> void:
	status_label.text = "Connection failed."
	_set_connect_controls_enabled(true)

func _set_connect_controls_enabled(enabled: bool) -> void:
	address_edit.editable = enabled
	host_button.disabled = not enabled
	join_button.disabled = not enabled
	quick_play_button.disabled = not enabled or not Steamworks.is_available
	host_steam_button.disabled = not enabled or not Steamworks.is_available
	disconnect_button.visible = not enabled

func _refresh_player_list(_peer_id: int = -1) -> void:
	for child in player_list.get_children():
		child.queue_free()
	for id in Network.players:
		var row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = "%s%s" % [Network.players[id].get("name", "Player %d" % id), " (you)" if id == Network.my_peer_id() else ""]
		row.add_child(name_label)

		var faction_index: int = Network.players[id].get("faction_index", 0)
		if id == Network.my_peer_id():
			var option := OptionButton.new()
			for faction in available_factions:
				option.add_item(faction.faction_name)
			option.selected = faction_index
			option.item_selected.connect(Network.set_my_faction)
			row.add_child(option)
		else:
			var faction_label := Label.new()
			faction_label.text = available_factions[faction_index].faction_name \
					if faction_index < available_factions.size() else "?"
			row.add_child(faction_label)

		var swatch := ColorRect.new()
		swatch.color = Network.players[id].get("color", Color.WHITE)
		swatch.custom_minimum_size = Vector2(24, 24)
		row.add_child(swatch)

		if id == Network.my_peer_id():
			var color_option := OptionButton.new()
			var available: Array[int] = Network.available_color_indices(id)
			var color_index: int = Network.color_index_of(id)
			for i in Network.TEAM_COLORS.size():
				color_option.add_item(Network.TEAM_COLOR_NAMES[i])
				## A color someone else already holds stays listed but
				## unpickable, rather than being dropped — otherwise the
				## entries would shuffle position under the player's cursor
				## every time another player changed theirs.
				color_option.set_item_disabled(i, not available.has(i) and i != color_index)
			if color_index >= 0:
				color_option.select(color_index)
			color_option.item_selected.connect(Network.set_my_color)
			row.add_child(color_option)

		var ready_check := CheckButton.new()
		ready_check.text = "Ready"
		ready_check.button_pressed = Network.players[id].get("ready", false)
		if id == Network.my_peer_id():
			ready_check.toggled.connect(Network.set_my_ready)
		else:
			ready_check.disabled = true
		row.add_child(ready_check)

		player_list.add_child(row)

	if Network.is_host():
		start_button.disabled = not Network.all_players_ready()

func _on_start_pressed() -> void:
	if not Network.is_host():
		return
	if not Network.all_players_ready():
		return
	Network.mark_steam_lobby_in_progress()
	start_button.disabled = true
	SceneLoader.start_match(MAIN_SCENE_PATH)
