class_name StatBar
extends Control
## A track and a fill: health, build progress, a conquest score. The track is the
## same recessed well as a command slot so bars and slots read as one family.

var ratio: float = 1.0:
	set(value):
		ratio = clampf(value, 0.0, 1.0)
		queue_redraw()

var fill_color: Color = UiStyle.GOOD:
	set(value):
		fill_color = value
		queue_redraw()

var _track: StyleBoxFlat

func _init() -> void:
	_track = UiStyle.slot_box()
	custom_minimum_size = Vector2(0, 7)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_style_box(_track, rect)
	if ratio <= 0.0:
		return
	var inner := rect.grow(-float(UiStyle.BORDER))
	inner.size.x *= ratio
	draw_rect(inner, fill_color)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
