class_name VerticalRule
extends Control
## The vertical twin of SectionRule: a 1px brass divider between two columns,
## used to separate the options screen's category rail from its fields.

@export var strength: float = 0.5:
	set(value):
		strength = value
		queue_redraw()

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## Width comes from here, not custom_minimum_size, so a scene can set a height
## without _init clobbering it (see SectionRule for why that matters).
func _get_minimum_size() -> Vector2:
	return Vector2(UiStyle.BORDER, 0)

func _draw() -> void:
	var colour := UiStyle.LINE_STRONG
	colour.a *= strength
	draw_rect(Rect2(Vector2.ZERO, Vector2(UiStyle.BORDER, size.y)), colour)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
