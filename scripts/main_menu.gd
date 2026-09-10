extends Control

const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"
const LOBBY_SCENE_PATH: String = "res://scenes/lobby.tscn"

@onready var menu: VBoxContainer = $Menu
@onready var options_menu: OptionsMenu = $OptionsMenu

func _ready() -> void:
	$Menu/SinglePlayerButton.pressed.connect(_on_single_player_pressed)
	$Menu/MultiplayerButton.pressed.connect(SceneLoader.change_scene.bind(LOBBY_SCENE_PATH))
	$Menu/OptionsButton.pressed.connect(_on_options_pressed)
	$Menu/ExitButton.pressed.connect(get_tree().quit)
	options_menu.visible = false
	options_menu.closed.connect(_on_options_closed)
	UiDebugEditor.register_editable_root(self, "main_menu")

func _on_single_player_pressed() -> void:
	Network.start_offline()
	SceneLoader.change_scene(MAIN_SCENE_PATH)

func _on_options_pressed() -> void:
	menu.visible = false
	options_menu.open()

func _on_options_closed() -> void:
	menu.visible = true
