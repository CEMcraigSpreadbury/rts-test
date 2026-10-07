class_name UiButton
extends Button
## A moulded-plastic button. `primary` makes it the player's colour (KEY) --
## only one action on a screen gets that -- and `danger` the red of a
## destructive one; everything else is the panels' own plastic, solid.

## Exported so a scene can mark its one primary action without code.
@export var primary: bool = false:
	set(value):
		primary = value
		_restyle()

@export var danger: bool = false:
	set(value):
		danger = value
		_restyle()

func _init() -> void:
	## The face and size go on once, here, and only where nothing set them: a
	## scene applies its properties in file order, so its own size override (a
	## modal's tall buttons) can already be in place when the script attaches.
	if not has_theme_font_override("font"):
		add_theme_font_override("font", UiStyle.font_display())
	if not has_theme_font_size_override("font_size"):
		add_theme_font_size_override("font_size", UiStyle.SIZE_BUTTON)
	_restyle()

func _ready() -> void:
	## _init runs before the scene's exported values are applied, so the style is
	## settled again here or a scene-set `primary` would never take effect.
	_restyle()

func _restyle() -> void:
	var base := UiStyle.RAISED
	if primary:
		base = UiStyle.KEY
	elif danger:
		base = UiStyle.DANGER
	add_theme_stylebox_override("normal", UiStyle.button_box(base))
	add_theme_stylebox_override("hover", UiStyle.button_box(base, UiStyle.KeyState.HOVER))
	add_theme_stylebox_override("pressed", UiStyle.button_box(base, UiStyle.KeyState.PRESSED))
	add_theme_stylebox_override("disabled", UiStyle.button_box(base, UiStyle.KeyState.DISABLED))
	for colour in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		add_theme_color_override(colour, UiStyle.INK)
