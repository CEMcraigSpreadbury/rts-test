class_name UiButton
extends Button
## A Forged Brass button. `primary` fills it with the accent -- only one action
## on a screen gets that, everything else keeps the raised face.

## Exported so a scene can mark its one primary action without code.
@export var primary: bool = false:
	set(value):
		primary = value
		_restyle()

func _init() -> void:
	_restyle()

func _ready() -> void:
	## _init runs before the scene's exported values are applied, so the style is
	## settled again here or a scene-set `primary` would never take effect.
	_restyle()

func _restyle() -> void:
	add_theme_font_override("font", UiStyle.font_display())
	add_theme_font_size_override("font_size", UiStyle.SIZE_BUTTON)
	if primary:
		add_theme_stylebox_override("normal", UiStyle.button_box(UiStyle.ACCENT, UiStyle.ACCENT))
		add_theme_stylebox_override("hover", UiStyle.button_box(UiStyle.ACCENT, UiStyle.ACCENT.lightened(0.08)))
		add_theme_stylebox_override("pressed", UiStyle.button_box(UiStyle.ACCENT, UiStyle.ACCENT.darkened(0.12)))
		add_theme_color_override("font_color", UiStyle.ACCENT_INK)
		add_theme_color_override("font_hover_color", UiStyle.ACCENT_INK)
		add_theme_color_override("font_pressed_color", UiStyle.ACCENT_INK)
	else:
		add_theme_stylebox_override("normal", UiStyle.button_box())
		add_theme_stylebox_override("hover", UiStyle.button_box(UiStyle.LINE_STRONG))
		add_theme_stylebox_override("pressed", UiStyle.button_box(UiStyle.ACCENT))
		add_theme_color_override("font_color", UiStyle.INK)
		add_theme_color_override("font_hover_color", UiStyle.ACCENT)
		add_theme_color_override("font_pressed_color", UiStyle.ACCENT)
