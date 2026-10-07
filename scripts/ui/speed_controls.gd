class_name UiSpeedControls
extends HBoxContainer
## Single player's pause and game speed (see Main.GAME_SPEEDS), in the
## top-right tray (UiMatchState): a pause key, then slower, the speed now and
## faster sunk in a socket. The same as the Pause and -/= keys.

const PAUSE_SIZE := Vector2(44, 44)
const STEP_SIZE := Vector2(34, 34)

var main: Main
var _pause: Button
var _speed: Label
var _shown_paused: bool = false

func setup(p_main: Main) -> void:
	main = p_main
	name = "SpeedControls"
	add_theme_constant_override("separation", 10)
	_pause = _button(self, "||", main.toggle_game_pause, PAUSE_SIZE)
	var socket := PanelContainer.new()
	var well := UiStyle.slot_box()
	well.radius = 22
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		well.set_content_margin(side, 5)
	socket.add_theme_stylebox_override(&"panel", well)
	add_child(socket)
	var steps := HBoxContainer.new()
	steps.add_theme_constant_override("separation", 2)
	socket.add_child(steps)
	_button(steps, "-", main.step_game_speed.bind(-1), STEP_SIZE)
	_speed = Label.new()
	_speed.custom_minimum_size = Vector2(40, STEP_SIZE.y)
	_speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speed.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_speed.add_theme_font_override("font", UiStyle.font_data_bold())
	_speed.add_theme_font_size_override("font_size", 22)
	_speed.add_theme_color_override("font_color", UiStyle.INK)
	steps.add_child(_speed)
	_button(steps, "+", main.step_game_speed.bind(1), STEP_SIZE)
	visible = main.can_change_speed()

## A small plain key with a glyph on it: the data face, no word padding.
func _button(parent: Control, text: String, callback: Callable, size: Vector2) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = size
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	button.add_theme_font_override("font", UiStyle.font_data_bold())
	button.add_theme_font_size_override("font_size", 18)
	_style(button, UiStyle.RAISED)
	parent.add_child(button)
	return button

func _style(button: Button, base: Color) -> void:
	button.add_theme_stylebox_override("normal", UiStyle.key_box(base))
	button.add_theme_stylebox_override("hover", UiStyle.key_box(base, UiStyle.KeyState.HOVER))
	button.add_theme_stylebox_override("pressed", UiStyle.key_box(base, UiStyle.KeyState.PRESSED))
	for colour in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(colour, UiStyle.INK)

func _process(_delta: float) -> void:
	if main == null:
		return
	visible = main.can_change_speed()
	if not visible:
		return
	## Paused, the pause key turns the player's colour.
	if main.game_paused != _shown_paused:
		_shown_paused = main.game_paused
		_style(_pause, UiStyle.KEY if _shown_paused else UiStyle.RAISED)
	var speed: float = main.GAME_SPEEDS[main.game_speed_index]
	_speed.text = "||" if main.game_paused else ("%s×" % (str(speed) if speed != int(speed) else str(int(speed))))
