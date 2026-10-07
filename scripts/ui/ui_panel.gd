class_name UiPanel
extends Control
## A moulded-plastic panel: smoked translucent plastic frosting the battle
## behind it, drawn by a UiPlasticBody child.
##
## Put content in `panel.content`, NOT in the panel itself. The panel is a plain
## Control rather than a MarginContainer on purpose: a MarginContainer lays out
## its internal children too, so a background layer added with INTERNAL_MODE
## still gets squashed into the content rect. Keeping the panel a Control and
## letting UiPlasticBody draw the material behind it avoids that entirely.

## The inset between the panel edge and its content on each side.
var inset: int = UiStyle.SPACE_L:
	set(value):
		inset = value
		_insets = {"left": value, "top": value, "right": value, "bottom": value}
		_apply_insets()

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
var _body: UiPlasticBody

func _init() -> void:
	_body = UiPlasticBody.new()
	_body.name = "PlasticBody"
	add_child(_body, false, Node.INTERNAL_MODE_FRONT)

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
