class_name VerticalRule
extends Control
## The vertical twin of SectionRule: a moulded seam between two columns,
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
	return Vector2(2, 0)

## The vertical twin of SectionRule's moulded seam.
func _draw() -> void:
	var weight := strength * 2.0
	draw_rect(Rect2(0, 0, 1, size.y), Color(0, 0, 0, 0.3 * weight))
	draw_rect(Rect2(1, 0, 1, size.y), Color(1, 1, 1, 0.08 * weight))

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
