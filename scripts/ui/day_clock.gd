class_name UiDayClock
extends HBoxContainer
## The time of day, top right beside the speed buttons: a dial whose bead goes
## once round per day and night (gold arc the day, blue the night), and the day
## count. It runs on game time, so at 3x it visibly turns three times as fast.
## Shown in every match; it moves left to make room when the speed buttons show.

const DIAL_SIZE := Vector2(40, 40)
const DIAL_RADIUS: float = 12.0
const ARC_WIDTH: float = 2.0
const BEAD_RADIUS: float = 3.5
const NIGHT_ARC := Color(0.45, 0.58, 0.9, 0.85)
const MOON_BEAD := Color(0.78, 0.85, 1.0)
## Kept between the clock and the speed buttons.
const GAP: float = 12.0

var main: Main
var _speed_controls: Control
var _dial: Control
var _day: Label
var _shown_day: int = -1

func setup(p_main: Main, speed_controls: Control) -> void:
	main = p_main
	_speed_controls = speed_controls
	name = "DayClock"
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	offset_top = UiSpeedControls.MARGIN
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", UiStyle.SPACE_S)
	_dial = Control.new()
	_dial.custom_minimum_size = DIAL_SIZE
	_dial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dial.draw.connect(_draw_dial)
	add_child(_dial)
	_day = Label.new()
	_day.custom_minimum_size.y = DIAL_SIZE.y
	_day.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	## The number face: Marcellus SC draws a 1 that reads as an I.
	_day.add_theme_font_override("font", UiStyle.font_data_bold())
	_day.add_theme_font_size_override("font_size", UiStyle.SIZE_VALUE)
	_day.add_theme_color_override("font_color", UiStyle.INK)
	add_child(_day)

func _process(_delta: float) -> void:
	if main == null or main.day_night == null:
		return
	var right: float = -UiSpeedControls.MARGIN
	if _speed_controls != null and _speed_controls.visible:
		right -= _speed_controls.size.x + GAP
	if offset_right != right:
		offset_right = right
		offset_left = right - get_combined_minimum_size().x
	if main.day_night.day_number != _shown_day:
		_shown_day = main.day_night.day_number
		_day.text = "Day %d" % _shown_day
	_dial.queue_redraw()

func _draw_dial() -> void:
	var rect := Rect2(Vector2.ZERO, _dial.size)
	_dial.draw_style_box(UiStyle.slot_box(UiStyle.LINE), rect)
	var centre: Vector2 = rect.get_center()
	## The day arc is centred on the top, the night arc fills the bottom.
	var share: float = DayNight.day_share()
	var sunrise: float = -PI * 0.5 - PI * share
	var sunset: float = sunrise + TAU * share
	_dial.draw_arc(centre, DIAL_RADIUS, sunrise, sunset, 32, UiStyle.ACCENT, ARC_WIDTH, true)
	_dial.draw_arc(centre, DIAL_RADIUS, sunset, sunrise + TAU, 16, NIGHT_ARC, ARC_WIDTH, true)
	var tip: Vector2 = centre + Vector2.from_angle(sunrise + TAU * main.day_night.cycle_fraction()) * DIAL_RADIUS
	_dial.draw_line(centre, tip, UiStyle.INK, ARC_WIDTH, true)
	_dial.draw_circle(tip, BEAD_RADIUS, UiStyle.ACCENT.lerp(MOON_BEAD, main.day_night.night_amount), true, -1.0, true)
