class_name UiCaps
extends Control
## Draws the brass corner caps over whatever it is a child of.
##
## UiPanel draws its own; this exists for panels that must size themselves to
## their contents and so have to be a PanelContainer rather than a fixed Control.
##
## A PanelContainer lays out EVERY child inside its content margins, including
## this one. Drawing at our own rect would put the caps at the corners of the
## content box, where they clip the first line of text. So the rect is grown back
## out by the parent's stylebox margins to reach the panel's real corners.

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _draw() -> void:
	UiStyle.draw_corner_caps(self, _panel_rect())

## The parent's rect expressed in our local space. Derived from the two nodes'
## positions rather than from stylebox margins, so it is exact whatever the
## parent is and whatever inset it applies.
func _panel_rect() -> Rect2:
	var parent := get_parent() as Control
	if parent == null:
		return Rect2(Vector2.ZERO, size)
	return Rect2(parent.global_position - global_position, parent.size)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
