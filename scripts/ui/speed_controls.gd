class_name UiSpeedControls
extends HBoxContainer
## Single player's pause and game speed (see Main.GAME_SPEEDS), top right:
## pause, slower, the speed now, faster. The same as the Pause and -/= keys.

const MARGIN: float = 24.0
const BUTTON_SIZE := Vector2(44, 40)

var main: Main
var _pause: UiButton
var _speed: Label

func setup(p_main: Main) -> void:
	main = p_main
	name = "SpeedControls"
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	offset_right = -MARGIN
	offset_top = MARGIN
	add_theme_constant_override("separation", 4)
	_pause = _button("||", main.toggle_game_pause)
	_button("-", main.step_game_speed.bind(-1))
	_speed = Label.new()
	_speed.custom_minimum_size = Vector2(52, BUTTON_SIZE.y)
	_speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speed.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_speed.add_theme_font_override("font", UiStyle.font_display())
	_speed.add_theme_font_size_override("font_size", UiStyle.SIZE_BUTTON)
	_speed.add_theme_color_override("font_color", UiStyle.INK)
	add_child(_speed)
	_button("+", main.step_game_speed.bind(1))
	visible = main.can_change_speed()

func _button(text: String, callback: Callable) -> UiButton:
	var button := UiButton.new()
	button.text = text
	button.custom_minimum_size = BUTTON_SIZE
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	add_child(button)
	return button

func _process(_delta: float) -> void:
	if main == null:
		return
	visible = main.can_change_speed()
	if not visible:
		return
	_pause.primary = main.game_paused
	var speed: float = main.GAME_SPEEDS[main.game_speed_index]
	_speed.text = "||" if main.game_paused else ("%sx" % (str(speed) if speed != int(speed) else str(int(speed))))
