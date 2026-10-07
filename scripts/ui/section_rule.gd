class_name SectionRule
extends Control
## The seam that separates a panel's title from its body: a groove moulded into
## the plastic, faint enough to read as a division rather than a border.

## Half strength on a panel, where the surface is already lighter than the
## ground. Exported because the same line is invisible on the main-menu
## ground and wants full strength there.
@export var strength: float = 0.5:
	set(value):
		strength = value
		queue_redraw()

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## The height comes from here rather than from custom_minimum_size, because a
## scene sets its properties in file order and the script's _init runs when the
## `script` line is reached -- assigning custom_minimum_size there overwrites a
## width the scene had already set, and the rule renders zero pixels wide.
func _get_minimum_size() -> Vector2:
	return Vector2(0, 2)

## A seam moulded into the plastic: a dark groove with light caught under it.
func _draw() -> void:
	var weight := strength * 2.0
	draw_rect(Rect2(0, 0, size.x, 1), Color(0, 0, 0, 0.3 * weight))
	draw_rect(Rect2(0, 1, size.x, 1), Color(1, 1, 1, 0.08 * weight))

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
