extends Control

@onready var address_edit: LineEdit = $VBox/ConnectRow/AddressEdit
@onready var host_button: Button = $VBox/ConnectRow/HostButton
@onready var join_button: Button = $VBox/ConnectRow/JoinButton
@onready var status_label: Label = $VBox/StatusLabel
@onready var player_list: VBoxContainer = $VBox/PlayerList
@onready var start_button: Button = $VBox/StartButton

const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"

func _ready() -> void:
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	start_button.pressed.connect(_on_start_pressed)
	start_button.visible = false

	Network.player_connected.connect(_refresh_player_list)
	Network.player_disconnected.connect(_refresh_player_list)
	Network.connected_to_server.connect(_on_connected)
	Network.connection_failed.connect(_on_connection_failed)

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
	_refresh_player_list()

func _on_connection_failed() -> void:
	status_label.text = "Connection failed."
	_set_connect_controls_enabled(true)

func _set_connect_controls_enabled(enabled: bool) -> void:
	address_edit.editable = enabled
	host_button.disabled = not enabled
	join_button.disabled = not enabled

func _refresh_player_list(_peer_id: int = -1) -> void:
	for child in player_list.get_children():
		child.queue_free()
	for id in Network.players:
		var label := Label.new()
		label.text = "Player %d%s" % [id, " (you)" if id == Network.my_peer_id() else ""]
		player_list.add_child(label)

func _on_start_pressed() -> void:
	if not Network.is_host():
		return
	_start_game.rpc()

@rpc("authority", "call_local", "reliable")
func _start_game() -> void:
	get_tree().change_scene_to_file(MAIN_SCENE_PATH)
