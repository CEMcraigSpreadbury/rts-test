class_name UiTextLine
extends Control
## A text line whose box is exactly as tall as it is in the mockup.
##
## The mockup sets `line-height: 1` on its labels, so a 22px name occupies 22px.
## A Godot Label reports ascent + descent instead, so the same name occupies
## about 27px, and a column of them silently overflows a fixed-height panel --
## which is exactly how the previous attempt at this UI ended up misaligned.
## Wrapping the Label in a Control with an explicit height pins the box back to
## the mockup's number and lets the glyphs overhang harmlessly.

var label: Label

static func make(text: String, variation: StringName, line_height: int,
		colour: Color = UiStyle.INK, font_size: int = -1) -> UiTextLine:
	var line := UiTextLine.new()
	line.custom_minimum_size = Vector2(0, line_height)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE

	line.label = Label.new()
	line.label.text = text
	line.label.theme_type_variation = variation
	line.label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.label.add_theme_color_override("font_color", colour)
	if font_size > 0:
		line.label.add_theme_font_size_override("font_size", font_size)
	## Vertical overflow has to be allowed to spill, or centring it inside a box
	## shorter than the font's line height clips the descenders.
	line.label.clip_text = false
	line.add_child(line.label)
	return line

## The height is pinned by custom_minimum_size, but the WIDTH still has to come
## from the text, or a row of these collapses to zero width and the cells draw
## on top of one another.
func _get_minimum_size() -> Vector2:
	if label == null:
		return Vector2.ZERO
	return Vector2(label.get_combined_minimum_size().x, 0.0)

func set_text(value: String) -> void:
	if label == null:
		return
	label.text = value
	update_minimum_size()
