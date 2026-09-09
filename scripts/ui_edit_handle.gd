extends Control
## One draggable/resizable overlay rectangle tracking a single HUD element
## for UiDebugEditor. Lives in the editor's own top-layer CanvasLayer, stays
## synced to its target's on-screen rect every frame. Single-click selects
## (or double-click, within the body, drills into its children); dragging
## the body moves it; any corner resizes (hold Shift to keep aspect ratio).
##
## If target's parent is a Container, the container recomputes its position
## AND size every frame regardless of what we set — so body-drag is
## disabled (nothing to move: the container decides that) and corner-resize
## writes to custom_minimum_size instead of the offset rect, since that's
## the one sizing hint a Container actually honors.

const GRIP_SIZE := 14.0
const COLOR_NORMAL := Color(1, 0.85, 0.2, 0.9)
const COLOR_SELECTED := Color(1, 0.2, 0.2, 0.95)
const COLOR_MANAGED := Color(0.4, 0.85, 1, 0.9)

## Which offsets move (by +delta.x / +delta.y) for each corner, and the sign
## that a "growing" drag has on each axis for that corner — needed to scale
## proportionally under Shift, since e.g. the top-right corner grows with
## +delta.x but -delta.y (opposite signs), while bottom-right grows with
## +delta.x and +delta.y (same sign).
const CORNERS := {
	"tl": {"free_x": "offset_left", "free_y": "offset_top", "sign_x": -1.0, "sign_y": -1.0},
	"tr": {"free_x": "offset_right", "free_y": "offset_top", "sign_x": 1.0, "sign_y": -1.0},
	"bl": {"free_x": "offset_left", "free_y": "offset_bottom", "sign_x": -1.0, "sign_y": 1.0},
	"br": {"free_x": "offset_right", "free_y": "offset_bottom", "sign_x": 1.0, "sign_y": 1.0},
}
const LABEL_FONT: Font = preload("res://assets/fonts/MedievalSharp-Book.ttf")

var target: Control
var save_key: String
var _editor: Node
var _selected: bool = false
var _dragging: bool = false
var _corner: String = ""
var _drag_start_mouse: Vector2
var _drag_start_offsets: Vector4 ## left, top, right, bottom — for a free Control
var _drag_start_size: Vector2 ## for a Container-managed child

func _init(p_target: Control, p_save_key: String, p_editor: Node) -> void:
	target = p_target
	save_key = p_save_key
	_editor = p_editor
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE

func _is_managed() -> bool:
	return is_instance_valid(target) and target.get_parent() is Container

func _process(_delta: float) -> void:
	if not is_instance_valid(target):
		queue_free()
		return
	var rect := target.get_global_rect()
	global_position = rect.position
	size = rect.size
	queue_redraw()

func _draw() -> void:
	var managed := _is_managed()
	var color := COLOR_SELECTED if _selected else (COLOR_MANAGED if managed else COLOR_NORMAL)
	draw_rect(Rect2(Vector2.ZERO, size), color, false, 2.0)
	for corner in CORNERS:
		draw_rect(_grip_rect(corner), color, true)
	var suffix := "  (auto — size only)" if managed else ""
	draw_string(LABEL_FONT, Vector2(4, -6), "%s  %dx%d%s" % [String(target.name), int(size.x), int(size.y), suffix], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)

func _grip_rect(corner: String) -> Rect2:
	var pos := Vector2.ZERO
	if corner.ends_with("r"):
		pos.x = size.x - GRIP_SIZE
	if corner.begins_with("b"):
		pos.y = size.y - GRIP_SIZE
	return Rect2(pos, Vector2(GRIP_SIZE, GRIP_SIZE))

func set_selected(value: bool) -> void:
	_selected = value
	queue_redraw()

func _corner_at(pos: Vector2) -> String:
	for corner in CORNERS:
		if _grip_rect(corner).has_point(pos):
			return corner
	return ""

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_editor.select(target)
			_drag_start_mouse = event.global_position
			_drag_start_offsets = Vector4(target.offset_left, target.offset_top, target.offset_right, target.offset_bottom)
			_drag_start_size = target.get_global_rect().size
			_corner = _corner_at(event.position)
			_dragging = true
			if _corner == "":
				_editor.register_click(target, save_key)
		else:
			if _dragging:
				_editor.snap_anchor(target)
			_dragging = false
			_corner = ""
	elif event is InputEventMouseMotion and _dragging:
		var delta: Vector2 = event.global_position - _drag_start_mouse
		if _corner == "":
			if not _is_managed():
				target.offset_left = _drag_start_offsets.x + delta.x
				target.offset_top = _drag_start_offsets.y + delta.y
				target.offset_right = _drag_start_offsets.z + delta.x
				target.offset_bottom = _drag_start_offsets.w + delta.y
		else:
			_apply_resize(delta, event.shift_pressed)

func _apply_resize(delta: Vector2, keep_aspect: bool) -> void:
	var info: Dictionary = CORNERS[_corner]
	var sign_x: float = info.sign_x
	var sign_y: float = info.sign_y
	var managed := _is_managed()
	var orig_w: float = maxf(_drag_start_size.x, 1.0)
	var orig_h: float = maxf(_drag_start_size.y, 1.0)
	if not managed:
		var d := _drag_start_offsets
		orig_w = maxf(d.z - d.x, 1.0)
		orig_h = maxf(d.w - d.y, 1.0)

	var dx := delta.x
	var dy := delta.y
	if keep_aspect:
		var rel_x: float = (delta.x * sign_x) / orig_w
		var rel_y: float = (delta.y * sign_y) / orig_h
		var rel: float = rel_x if absf(rel_x) > absf(rel_y) else rel_y
		dx = rel * orig_w * sign_x
		dy = rel * orig_h * sign_y

	## Clamp so the element can't be dragged through itself (min 24px either side).
	var new_w: float = maxf(orig_w + dx * sign_x, 24.0)
	var new_h: float = maxf(orig_h + dy * sign_y, 24.0)

	if managed:
		target.custom_minimum_size = Vector2(new_w, new_h)
		return

	dx = (new_w - orig_w) * sign_x
	dy = (new_h - orig_h) * sign_y
	var d := _drag_start_offsets
	if info.free_x == "offset_left":
		target.offset_left = d.x + dx
	else:
		target.offset_right = d.z + dx
	if info.free_y == "offset_top":
		target.offset_top = d.y + dy
	else:
		target.offset_bottom = d.w + dy
