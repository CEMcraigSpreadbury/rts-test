extends Control

const LOBBY_SCENE_PATH: String = "res://scenes/lobby.tscn"

## Same list (and order) as lobby.tscn's available_maps.
@export var available_maps: Array[MapInfo] = []

@onready var menu: VBoxContainer = $Menu
@onready var map_select: VBoxContainer = $MapSelect
@onready var map_option: OptionButton = $MapSelect/MapOption
@onready var options_menu: OptionsMenu = $OptionsMenu

func _ready() -> void:
	$Menu/SinglePlayerButton.pressed.connect(_on_single_player_pressed)
	$Menu/MultiplayerButton.pressed.connect(SceneLoader.change_scene.bind(LOBBY_SCENE_PATH))
	$Menu/OptionsButton.pressed.connect(_on_options_pressed)
	$Menu/ExitButton.pressed.connect(get_tree().quit)
	$MapSelect/StartButton.pressed.connect(_on_start_pressed)
	$MapSelect/BackButton.pressed.connect(_on_map_select_back_pressed)
	for map in available_maps:
		map_option.add_item(map.map_name)
	map_select.visible = false
	options_menu.visible = false
	options_menu.closed.connect(_on_options_closed)
	UiDebugEditor.register_editable_root(self, "main_menu")

func _on_single_player_pressed() -> void:
	menu.visible = false
	map_select.visible = true

func _on_map_select_back_pressed() -> void:
	map_select.visible = false
	menu.visible = true

func _on_start_pressed() -> void:
	if map_option.selected < 0:
		return
	Network.start_offline()
	SceneLoader.change_scene(available_maps[map_option.selected].scene_path)

func _on_options_pressed() -> void:
	menu.visible = false
	options_menu.open()

func _on_options_closed() -> void:
	menu.visible = true
