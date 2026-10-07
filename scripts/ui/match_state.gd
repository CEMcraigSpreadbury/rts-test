class_name UiMatchState
extends PanelContainer
## The top-right tray: the day clock, then (single player only) pause and the
## game speed. Docked to the corner and sized to whatever it holds, so it
## shrinks to the clock alone when the speed controls hide.

const MARGIN_X: int = 12
const MARGIN_Y: int = 10
const TOP: float = 22.0
## Its 44px keys plus the insets.
const HEIGHT: float = 64.0

var _row: HBoxContainer

func setup(main: Main) -> void:
	name = "MatchState"
	anchor_left = 1.0
	anchor_right = 1.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	offset_right = -UiStyle.SCREEN_MARGIN
	offset_top = TOP
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inset := UiStyle.empty_box()
	inset.content_margin_left = MARGIN_X
	inset.content_margin_right = MARGIN_X
	inset.content_margin_top = MARGIN_Y
	inset.content_margin_bottom = MARGIN_Y
	add_theme_stylebox_override(&"panel", inset)
	add_child(UiPlasticBody.new())
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 10)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)
	var clock := UiDayClock.new()
	clock.setup(main)
	_row.add_child(clock)
	var speed := UiSpeedControls.new()
	speed.setup(main)
	_row.add_child(speed)

func _process(_delta: float) -> void:
	var wanted: float = get_combined_minimum_size().x
	if not is_equal_approx(offset_right - offset_left, wanted):
		offset_left = offset_right - wanted
		offset_bottom = offset_top + get_combined_minimum_size().y
