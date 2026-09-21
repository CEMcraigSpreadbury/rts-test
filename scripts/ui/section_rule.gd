class_name SectionRule
extends Control
## The 1px brass rule that separates a panel's title from its body. Half-strength
## brass, so it reads as a division rather than as another border.

## Half strength on a panel, where the surface is already lighter than the
## ground. Exported because the same 42% line is invisible on the near-black
## main-menu ground and wants full brass there.
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
	return Vector2(0, UiStyle.BORDER)

func _draw() -> void:
	var colour := UiStyle.LINE_STRONG
	colour.a *= strength
	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, UiStyle.BORDER)), colour)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
