class_name UiPanel
extends Control
## A Forged Brass panel body: translucent surface, one hairline border, and the
## brass L cap in the top-left and bottom-right corners that every panel in the
## game carries.
##
## Put content in `panel.content`, NOT in the panel itself. The panel is a plain
## Control rather than a MarginContainer on purpose: a MarginContainer lays out
## its internal children too, so a background layer added with INTERNAL_MODE
## still gets squashed into the content rect. Keeping the panel a Control and
## drawing the material in _draw() avoids that entirely.

## The inset between the panel edge and its content on each side.
var inset: int = UiStyle.SPACE_L:
	set(value):
		inset = value
		_insets = {"left": value, "top": value, "right": value, "bottom": value}
		_apply_insets()

## Set false for a panel that should not carry the corner caps. Nothing in the
## game does yet -- the tooltip is a popup, not a UiPanel.
var show_caps: bool = true:
	set(value):
		show_caps = value
		queue_redraw()

## Created on first access, so the same script can dress a scene node whose
## children are already laid out at explicit offsets (the HUD modules) as well
## as a panel built in code that wants a content container.
var content: MarginContainer:
	get:
		if _content == null:
			_content = MarginContainer.new()
			_content.name = "Content"
			_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			_content.mouse_filter = Control.MOUSE_FILTER_PASS
			add_child(_content)
			_apply_insets()
		return _content

var _content: MarginContainer
var _insets := {"left": UiStyle.SPACE_L, "top": UiStyle.SPACE_L,
		"right": UiStyle.SPACE_L, "bottom": UiStyle.SPACE_L}
var _box: StyleBoxFlat

func _init() -> void:
	_box = UiStyle.panel_box()

func _apply_insets() -> void:
	if _content == null:
		return
	for side: String in _insets:
		_content.add_theme_constant_override("margin_" + side, int(_insets[side]))

## Different insets per side, for a panel whose grid needs more room beneath it
## than beside it -- the selection panel wants 14 around and 22 below.
func set_insets(left: int, top: int, right: int, bottom: int) -> void:
	_insets = {"left": left, "top": top, "right": right, "bottom": bottom}
	_apply_insets()

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_style_box(_box, rect)
	if show_caps:
		UiStyle.draw_corner_caps(self, rect)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
