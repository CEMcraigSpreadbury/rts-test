extends Control
## Studio logo splash: fades the logo in, holds, fades out, then swaps to the
## main menu. The menu loads on a background thread while the logo is up so the
## hand-off doesn't hitch. Any key or click skips straight to the fade-out.

const MAIN_MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"
const LEAD_IN: float = 0.4
const FADE_IN: float = 1.2
const HOLD: float = 1.6
const FADE_OUT: float = 1.0
const TAIL: float = 0.3

@onready var _logo: TextureRect = $Logo

var _tween: Tween
var _skipping: bool = false

func _ready() -> void:
	ResourceLoader.load_threaded_request(MAIN_MENU_SCENE_PATH)
	_logo.modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_interval(LEAD_IN)
	_tween.tween_property(_logo, "modulate:a", 1.0, FADE_IN)
	_tween.tween_interval(HOLD)
	_tween.tween_property(_logo, "modulate:a", 0.0, FADE_OUT)
	_tween.tween_interval(TAIL)
	_tween.finished.connect(_go_to_menu)

func _unhandled_input(event: InputEvent) -> void:
	if _skipping:
		return
	var pressed: bool = (event is InputEventKey or event is InputEventMouseButton \
			or event is InputEventJoypadButton) and event.is_pressed()
	if not pressed:
		return
	_skipping = true
	get_viewport().set_input_as_handled()
	_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_logo, "modulate:a", 0.0, FADE_OUT * 0.4 * _logo.modulate.a)
	_tween.finished.connect(_go_to_menu)

func _go_to_menu() -> void:
	var scene := ResourceLoader.load_threaded_get(MAIN_MENU_SCENE_PATH) as PackedScene
	SceneLoader.change_scene_from_black(scene)
