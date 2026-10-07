class_name UiPlasticBody
extends Control
## Draws a panel's whole moulded-plastic body BEHIND it: drop shadow, the darker
## lip under the bottom edge, the battlefield frosted through the translucent
## plastic, and the highlight along the top edge (shaders/ui/ui_plastic_panel).
##
## Add one as a child of any Panel, PanelContainer or UiPanel. It takes over
## the parent's own "panel" stylebox (keeping its content margins), because a
## stylebox can't sample the screen to frost it, and a stylebox's shadow is
## painted under the box where it would darken the plastic from behind.
##
## A PanelContainer lays out EVERY child inside its content margins, including
## this one, so the body is drawn at the parent's real rect, recovered from the
## two nodes' global positions rather than from our own.

const SHADER := preload("res://shaders/ui/ui_plastic_panel.gdshader")
## Room around the panel for the drop shadow to fade out in.
const SHADOW_ROOM: float = 40.0

## Corner radius, for a panel that wants other than UiStyle.RADIUS.
var radius: int = UiStyle.RADIUS:
	set(value):
		radius = value
		queue_redraw()

## How opaque the plastic is over the frosted battle (UiStyle.PANEL_OPACITY
## unless a panel that must stay readable over the busy HUD wants more).
var opacity: float = UiStyle.PANEL_OPACITY:
	set(value):
		opacity = value
		_material.set_shader_parameter(&"opacity", value)

## Godot copies the screen for frosting once, at the first panel that reads
## it each frame -- before the rest of the HUD is drawn. A panel that opens
## OVER the HUD (a modal, the research tree) sets this to take its own fresh
## copy, so the HUD shows frosted through it instead of bare battlefield.
## Off by default: each copy is a full-screen blit.
@export var fresh_backdrop: bool = false:
	set(value):
		fresh_backdrop = value
		if value and _copy == null:
			_copy = BackBufferCopy.new()
			_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
			_copy.show_behind_parent = true
			add_child(_copy, false, Node.INTERNAL_MODE_FRONT)
		elif not value and _copy != null:
			_copy.queue_free()
			_copy = null

var _material: ShaderMaterial
var _watched: Control
var _copy: BackBufferCopy

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	show_behind_parent = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter(&"base_color", UiStyle.TRAY)
	_material.set_shader_parameter(&"opacity", opacity)
	material = _material

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_PARENTED:
			_take_over_parent()
		NOTIFICATION_UNPARENTED:
			_watch(null)
		NOTIFICATION_READY:
			## A caller may set its own panel style after adding us.
			_take_over_parent()
		NOTIFICATION_RESIZED:
			queue_redraw()

func _take_over_parent() -> void:
	var parent := get_parent() as Control
	_watch(parent)
	if parent is Panel or parent is PanelContainer:
		var current := parent.get_theme_stylebox(&"panel")
		if current is StyleBoxEmpty:
			return
		var empty := StyleBoxEmpty.new()
		if current != null:
			for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
				empty.set_content_margin(side, current.get_content_margin(side))
		parent.add_theme_stylebox_override(&"panel", empty)

func _watch(parent: Control) -> void:
	if _watched == parent:
		return
	if _watched != null and _watched.resized.is_connected(queue_redraw):
		_watched.resized.disconnect(queue_redraw)
	_watched = parent
	if _watched != null:
		_watched.resized.connect(queue_redraw)

func _draw() -> void:
	var rect := _panel_rect()
	_material.set_shader_parameter(&"panel_pos", rect.position)
	_material.set_shader_parameter(&"panel_size", rect.size)
	_material.set_shader_parameter(&"radius", float(radius))
	draw_rect(rect.grow(SHADOW_ROOM), Color.WHITE)

## The parent's rect expressed in our local space.
func _panel_rect() -> Rect2:
	var parent := get_parent() as Control
	if parent == null:
		return Rect2(Vector2.ZERO, size)
	return Rect2(parent.global_position - global_position, parent.size)
