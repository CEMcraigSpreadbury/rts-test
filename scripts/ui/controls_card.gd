class_name UiControlsCard
extends Control
## Every click and key on one card: a drawn mouse or keycaps beside what each
## does. Opened from the pause menu's Controls button, and once by the
## tutorial. Escape or Close puts it away.
##
## Rebuilt on every open, so a key rebound in Options shows as its new key.

signal closed

## The key column's width, so the descriptions line up down each column.
const KEY_COL: int = 104
const ROW_HEIGHT: int = 31
const DESC_SIZE: int = 16
const CAPTION_SIZE: int = 13
const CARD_WIDTH: int = 880

const MOUSE_ROWS: Array = [
	["left", "", "Select a unit or building"],
	["left", "drag", "Select everything in the box"],
	["left", "×2", "Select all of that kind on screen"],
	["right", "", "Move, gather, build or attack"],
	["right", "drag", "Move in formation, facing the drag"],
	["middle", "drag", "Pan the view"],
	["wheel", "", "Zoom"],
]

var _shell: ModalShell

func _ready() -> void:
	name = "ControlsCard"
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.55)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var centre := CenterContainer.new()
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	centre.add_child(panel)
	_shell = ModalShell.dress(panel, "Reference", "Controls", CARD_WIDTH)
	## Near opaque: it is read over the busy HUD, which shows through the
	## usual modal panel.
	var box := panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	if box != null:
		box.bg_color.a = 0.97
		panel.add_theme_stylebox_override("panel", box)

	var close_button := UiButton.new()
	close_button.text = "Close"
	close_button.primary = true
	close_button.pressed.connect(close)
	_shell.footer.add_child(close_button)

func open() -> void:
	_rebuild()
	visible = true

func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()

## _input, like OptionsMenu: Escape here must not also reach main.gd's.
func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()

func _rebuild() -> void:
	for column in [_shell.left, _shell.right]:
		for child in column.get_children():
			column.remove_child(child)
			child.queue_free()

	var left := _shell.left
	left.add_child(ModalShell.column_head("Mouse"))
	for row in MOUSE_ROWS:
		_add_row(left, _mouse_cell(row[0], row[1]), row[2])
	left.add_child(_gap())
	left.add_child(ModalShell.column_head("Camera"))
	_add_row(left, _keys([Settings.get_key(&"camera_up"), Settings.get_key(&"camera_left"),
			Settings.get_key(&"camera_down"), Settings.get_key(&"camera_right")]), "Pan the view")
	_add_row(left, _keys([Settings.get_key(&"camera_rotate_left"),
			Settings.get_key(&"camera_rotate_right")]), "Turn the view")
	_add_row(left, _keys([Settings.get_key(&"center_selection")]), "Centre on the selection")

	var right := _shell.right
	right.add_child(ModalShell.column_head("Orders"))
	_add_row(right, _keys([Main.UNIT_ATTACK_KEY]), "Attack-move: fight on the way")
	_add_row(right, _keys([Main.UNIT_STOP_KEY]), "Stop")
	_add_row(right, _keys([Main.UNIT_HOLD_KEY]), "Hold ground, or Gather")
	_add_row(right, _keys([Main.UNIT_PATROL_KEY]), "Patrol")
	_add_row(right, _keys([Main.UNIT_BUILD_KEY]), "Build, or send builders to a site")
	_add_row(right, _keys([Main.UNIT_REGIMENT_KEY]), "Form or break up a regiment")
	_add_row(right, _keys([Main.UNIT_ARMY_KEY]), "Join or leave a Lord's army")
	right.add_child(_gap())
	right.add_child(ModalShell.column_head("Selection & Game"))
	_add_row(right, _keys([Settings.get_key(&"idle_villager")]), "Next idle villager")
	_add_row(right, _keys([Settings.get_key(&"select_military")]), "Every soldier")
	_add_row(right, _combo("Ctrl", "1-9"), "Make a group; 1-9 picks it again")
	_add_row(right, _keys([Main.RESEARCH_PANEL_KEY]), "Research")
	_add_row(right, _keys([Settings.get_key(&"slow_down"), Settings.get_key(&"speed_up")]),
			"Slower, faster (playing alone)")
	_add_row(right, _keys([KEY_ESCAPE]), "Menu")

func _add_row(column: VBoxContainer, cell: Control, text: String) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	row.add_theme_constant_override("separation", UiStyle.SPACE_M)
	cell.custom_minimum_size.x = KEY_COL
	row.add_child(cell)
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UiStyle.font_data())
	label.add_theme_font_size_override("font_size", DESC_SIZE)
	label.add_theme_color_override("font_color", UiStyle.INK)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	column.add_child(row)

func _gap() -> Control:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, UiStyle.SPACE_XS)
	return gap

func _mouse_cell(part: String, caption: String) -> Control:
	var cell := HBoxContainer.new()
	cell.add_theme_constant_override("separation", UiStyle.SPACE_XS)
	var mouse := MousePicture.new()
	mouse.part = part
	cell.add_child(mouse)
	if caption != "":
		cell.add_child(_caption(caption))
	return cell

func _keys(keycodes: Array) -> Control:
	var cell := HBoxContainer.new()
	cell.add_theme_constant_override("separation", 3)
	for keycode in keycodes:
		cell.add_child(_keycap(_key_text(keycode)))
	return cell

## A held key plus a second one: "Ctrl + 1-9".
func _combo(held: String, then: String) -> Control:
	var cell := HBoxContainer.new()
	cell.add_theme_constant_override("separation", 3)
	cell.add_child(_keycap(held))
	cell.add_child(_caption("+"))
	cell.add_child(_keycap(then))
	return cell

func _keycap(text: String) -> Control:
	var cap := PanelContainer.new()
	var box := UiStyle.flat(UiStyle.RAISED, UiStyle.LINE_STRONG, 3)
	## A deeper bottom edge, so it reads as a key rather than a tag.
	box.border_width_bottom = 3
	box.content_margin_left = 6
	box.content_margin_right = 6
	box.content_margin_top = 0
	box.content_margin_bottom = 0
	cap.add_theme_stylebox_override("panel", box)
	cap.custom_minimum_size = Vector2(22, 22)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", UiStyle.font_data_bold())
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", UiStyle.INK)
	cap.add_child(label)
	return cap

func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", UiStyle.font_data())
	label.add_theme_font_size_override("font_size", CAPTION_SIZE)
	label.add_theme_color_override("font_color", UiStyle.DIM)
	return label

## OS.get_keycode_string spells punctuation out ("Period"); a keycap wants the mark.
static func _key_text(keycode: Key) -> String:
	match keycode:
		KEY_PERIOD: return "."
		KEY_COMMA: return ","
		KEY_MINUS: return "-"
		KEY_EQUAL: return "="
		KEY_ESCAPE: return "Esc"
		KEY_BACKSPACE: return "Bksp"
	return OS.get_keycode_string(keycode)

## A mouse seen from above with the button in question lit.
class MousePicture extends Control:
	## "left", "right", "middle" (the wheel pressed) or "wheel" (rolled).
	var part: String = ""

	func _init() -> void:
		custom_minimum_size = Vector2(24, 31)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var body := Rect2(1, 0, 22, 31)
		var split_y: float = 14.0
		var mid_x: float = body.position.x + body.size.x * 0.5
		## Radius half the width, so the top of the body is a half circle.
		var radius: float = body.size.x * 0.5
		draw_style_box(UiStyle.flat(UiStyle.SLOT, UiStyle.LINE_STRONG, int(radius), 2), body)
		if part == "left" or part == "right":
			draw_colored_polygon(_button_shape(part == "left", Vector2(mid_x, radius), radius - 2.0, split_y),
					UiStyle.ACCENT)
		draw_line(Vector2(body.position.x + 1, split_y), Vector2(body.end.x - 1, split_y), UiStyle.LINE_STRONG, 1.0)
		draw_line(Vector2(mid_x, body.position.y + 1), Vector2(mid_x, split_y), UiStyle.LINE_STRONG, 1.0)
		var wheel_lit: bool = part == "middle" or part == "wheel"
		var wheel := Rect2(mid_x - 1.5, 4, 3, 7)
		draw_rect(wheel, UiStyle.SLOT)
		draw_rect(wheel, UiStyle.ACCENT if wheel_lit else UiStyle.DIM, wheel_lit)

	## One button: the quarter of the top half circle on its side, down to the split.
	func _button_shape(left: bool, centre: Vector2, radius: float, split_y: float) -> PackedVector2Array:
		var side: float = -1.0 if left else 1.0
		var points := PackedVector2Array([Vector2(centre.x, split_y), Vector2(centre.x + side * radius, split_y)])
		const STEPS: int = 8
		for i in STEPS + 1:
			## From the side (PI or 0) round to the top (1.5 PI and -0.5 PI are both straight up).
			var angle: float = lerpf(PI if left else 0.0, PI * 1.5 if left else -PI * 0.5, float(i) / STEPS)
			points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
		return points
