extends Node
## Runtime HUD layout editor for development builds only. Gated behind
## OS.is_debug_build() AND the "debug/ui_editor/enabled" project setting
## (Project Settings > Debug > Ui Editor > Enabled) so it can never end up
## active in a shipped export and stays off by default even in the editor.
##
## Any scene that wants its Control tree editable calls
## register_editable_root() once from its own _ready().
##
## Press Ctrl+Alt+U in-game to toggle the editor overlay (plain F-keys like
## F9 collide with Godot's own editor/debugger shortcuts and never reach the
## running game at all). The overlay starts by showing the registered root's
## DIRECT children — double-click any panel's body to drill into it and edit
## its own children, "Up" / "Top" in the toolbar to climb back out.
##
## A node whose parent is a Container (VBoxContainer, GridContainer, ...)
## has its position AND size recomputed by that container every frame, so
## dragging it would just snap back. For those nodes only the corner grips
## are active, and they resize custom_minimum_size (which the container
## does respect) instead of the offset rect; the body can still be clicked
## to select or double-clicked to drill in, just not dragged. A node whose
## parent is a plain Control (or a CanvasLayer, for a registered root) gets
## full move + resize via anchors/offsets, exactly like before.
##
## Every offset-based edit re-snaps the panel's anchor to whichever screen
## corner it now sits nearest, converting the drag into a small offset
## relative to THAT corner. Without this, a panel dragged far from its
## original edge (e.g. from top-right to bottom-left) would keep its old
## anchor with a huge offset — resolution-independent in theory, but in
## practice the anchor's own on-screen position moves with the window size,
## so the panel would drift wildly (or vanish off-screen) the moment the
## window was resized or its aspect ratio changed.
##
## "Save Layout" walks every registered root's ENTIRE Control subtree (not
## just what's currently on screen, so anything you drilled into and edited
## is captured too) and writes each node's anchors/offsets or
## custom_minimum_size to a ConfigFile, keyed by its path relative to the
## root. That file is re-applied on every future launch without touching
## the .tscn files.

const SAVE_PATH := "res://resources/ui_layout_overrides.cfg"
const TOGGLE_KEY := KEY_U
const NUDGE_STEP := 1.0
const NUDGE_STEP_FAST := 10.0
const DOUBLE_CLICK_TIME := 0.35

var _enabled: bool = false
var _active: bool = false
var _overlay: CanvasLayer
var _handles: Dictionary = {} ## Control target -> UiEditHandle
var _roots: Dictionary = {} ## save_key -> Node
var _view_root_key: String = "" ## which registered root the current drill view descends from
var _view_stack: Array[Node] = [] ## drill path below that root; last = current view parent
var _selected: Control = null
var _field_x: SpinBox
var _field_y: SpinBox
var _field_w: SpinBox
var _field_h: SpinBox
var _selected_label: Label
var _breadcrumb_label: Label
var _last_click_target: Control = null
var _last_click_time: float = -1.0

func _ready() -> void:
	_enabled = OS.is_debug_build() and bool(ProjectSettings.get_setting("debug/ui_editor/enabled", false))
	set_process_unhandled_input(_enabled)
	set_process(_enabled)
	if _enabled:
		print("UiDebugEditor: enabled — press Ctrl+Alt+U in-game to open the layout editor.")
	else:
		print("UiDebugEditor: disabled (Project Settings > Debug > Ui Editor > Enabled is off, or this is a release export).")

## Call once from a scene's _ready(). Immediately re-applies any previously
## saved layout for this root (at any depth); the live drag/resize overlay
## is only built the first time the editor is toggled on.
func register_editable_root(root: Node, save_key: String) -> void:
	if not _enabled:
		return
	_roots[save_key] = root
	_apply_saved_layout(root, save_key)

func _process(_delta: float) -> void:
	if not _active or not _selected or not is_instance_valid(_selected):
		return
	var rect := _selected.get_global_rect()
	_field_x.set_value_no_signal(rect.position.x)
	_field_y.set_value_no_signal(rect.position.y)
	_field_w.set_value_no_signal(rect.size.x)
	_field_h.set_value_no_signal(rect.size.y)

func _unhandled_input(event: InputEvent) -> void:
	if not _enabled:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == TOGGLE_KEY and event.ctrl_pressed and event.alt_pressed:
		_set_active(not _active)
		get_viewport().set_input_as_handled()
		return
	if _active and _selected and event is InputEventKey and event.pressed:
		_try_nudge(event)

func _try_nudge(event: InputEventKey) -> void:
	if _selected.get_parent() is Container:
		return ## Container overrides position every frame — nudging it is a no-op.
	var step: float = NUDGE_STEP_FAST if event.shift_pressed else NUDGE_STEP
	var delta := Vector2.ZERO
	match event.keycode:
		KEY_LEFT: delta.x = -step
		KEY_RIGHT: delta.x = step
		KEY_UP: delta.y = -step
		KEY_DOWN: delta.y = step
		_: return
	_selected.offset_left += delta.x
	_selected.offset_right += delta.x
	_selected.offset_top += delta.y
	_selected.offset_bottom += delta.y
	snap_anchor(_selected)
	get_viewport().set_input_as_handled()

func _set_active(active: bool) -> void:
	_active = active
	_selected = null
	_view_stack.clear()
	_view_root_key = ""
	if active:
		_build_overlay()
	else:
		_teardown_overlay()

## Called by a handle when its body is double-clicked. Descends into that
## node's children (if it has any Control children — otherwise this is a
## no-op, there's nothing to drill into).
func drill_into(node: Control, save_key: String) -> void:
	var has_control_child := false
	for child in node.get_children():
		if child is Control:
			has_control_child = true
			break
	if not has_control_child:
		return
	if _view_stack.is_empty():
		_view_root_key = save_key
	_view_stack.append(node)
	_rebuild_handles()

func go_up() -> void:
	if _view_stack.is_empty():
		return
	_view_stack.pop_back()
	_rebuild_handles()

func go_top() -> void:
	_view_stack.clear()
	_rebuild_handles()

func _current_view_parent() -> Node:
	if not _view_stack.is_empty():
		return _view_stack.back()
	return null

func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 128
	get_tree().root.add_child(_overlay)
	_overlay.add_child(_make_toolbar())
	_rebuild_handles()

func _rebuild_handles() -> void:
	if not _overlay:
		return
	for target in _handles:
		_handles[target].queue_free()
	_handles.clear()
	_selected = null
	_selected_label.text = "Selected: (click a panel)"

	var view_parent := _current_view_parent()
	if view_parent:
		if not is_instance_valid(view_parent):
			go_top()
			return
		for child in view_parent.get_children():
			if child is Control:
				_add_handle(child, _view_root_key)
		_breadcrumb_label.text = "In: %s   (Up / Top to climb out)" % _breadcrumb_path()
	else:
		for save_key in _roots:
			var root: Node = _roots[save_key]
			for child in root.get_children():
				if child is Control:
					_add_handle(child, save_key)
		_breadcrumb_label.text = "Top level — double-click a panel to drill into it"

func _breadcrumb_path() -> String:
	var parts := PackedStringArray([_view_root_key])
	for n in _view_stack:
		parts.append(String(n.name) if is_instance_valid(n) else "?")
	return "/".join(parts)

func _add_handle(child: Control, save_key: String) -> void:
	var handle := UiEditHandle.new(child, save_key, self)
	_overlay.add_child(handle)
	_handles[child] = handle

func _teardown_overlay() -> void:
	if _overlay:
		_overlay.queue_free()
		_overlay = null
	_handles.clear()

func select(target: Control) -> void:
	_selected = target
	var managed := " (size only — positioned by its parent container)" if target.get_parent() is Container else ""
	_selected_label.text = "Selected: %s%s" % [target.name, managed]
	for t in _handles:
		_handles[t].set_selected(t == target)

## Double-click routing: the handle itself detects the click, this just
## tracks timing/target since a single shared threshold is simplest here.
func register_click(target: Control, save_key: String) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if _last_click_target == target and now - _last_click_time <= DOUBLE_CLICK_TIME:
		_last_click_target = null
		drill_into(target, save_key)
	else:
		_last_click_target = target
		_last_click_time = now

## Re-anchors target to whichever screen corner its center currently sits
## nearest, rewriting its offsets to keep it visually in the exact same
## place. See the class-level note on why every edit calls this. No-op for
## a Container-managed child, which ignores anchors/offsets entirely.
func snap_anchor(target: Control) -> void:
	if target.get_parent() is Container:
		return
	var rect := target.get_global_rect()
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var anchor_x: float = 0.0 if rect.position.x + rect.size.x * 0.5 < vp.x * 0.5 else 1.0
	var anchor_y: float = 0.0 if rect.position.y + rect.size.y * 0.5 < vp.y * 0.5 else 1.0
	target.anchor_left = anchor_x
	target.anchor_right = anchor_x
	target.anchor_top = anchor_y
	target.anchor_bottom = anchor_y
	target.offset_left = rect.position.x - anchor_x * vp.x
	target.offset_right = rect.position.x + rect.size.x - anchor_x * vp.x
	target.offset_top = rect.position.y - anchor_y * vp.y
	target.offset_bottom = rect.position.y + rect.size.y - anchor_y * vp.y

func _make_toolbar() -> Control:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(8, 8)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	var label := Label.new()
	label.text = "UI Editor — drag/corner-resize a panel, double-click to drill in (Ctrl+Alt+U to close)"
	vbox.add_child(label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vbox.add_child(row)

	var save_button := Button.new()
	save_button.text = "Save Layout"
	save_button.pressed.connect(_save_layout)
	row.add_child(save_button)

	var reset_button := Button.new()
	reset_button.text = "Clear Saved Layout"
	reset_button.pressed.connect(_clear_layout)
	row.add_child(reset_button)

	var up_button := Button.new()
	up_button.text = "Up"
	up_button.pressed.connect(go_up)
	row.add_child(up_button)

	var top_button := Button.new()
	top_button.text = "Top"
	top_button.pressed.connect(go_top)
	row.add_child(top_button)

	_breadcrumb_label = Label.new()
	vbox.add_child(_breadcrumb_label)

	_selected_label = Label.new()
	_selected_label.text = "Selected: (click a panel)"
	vbox.add_child(_selected_label)

	var field_row := HBoxContainer.new()
	field_row.add_theme_constant_override("separation", 6)
	vbox.add_child(field_row)
	_field_x = _add_field(field_row, "X", _on_field_x)
	_field_y = _add_field(field_row, "Y", _on_field_y)
	_field_w = _add_field(field_row, "W", _on_field_w)
	_field_h = _add_field(field_row, "H", _on_field_h)

	return panel

func _add_field(parent: HBoxContainer, caption: String, callback: Callable) -> SpinBox:
	var label := Label.new()
	label.text = caption
	parent.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = -4000
	spin.max_value = 4000
	spin.step = 1
	spin.custom_minimum_size = Vector2(72, 0)
	spin.value_changed.connect(callback)
	parent.add_child(spin)
	return spin

func _on_field_x(v: float) -> void:
	if not _selected or _selected.get_parent() is Container: return
	var rect := _selected.get_global_rect()
	var delta := v - rect.position.x
	_selected.offset_left += delta
	_selected.offset_right += delta
	snap_anchor(_selected)

func _on_field_y(v: float) -> void:
	if not _selected or _selected.get_parent() is Container: return
	var rect := _selected.get_global_rect()
	var delta := v - rect.position.y
	_selected.offset_top += delta
	_selected.offset_bottom += delta
	snap_anchor(_selected)

func _on_field_w(v: float) -> void:
	if not _selected: return
	if _selected.get_parent() is Container:
		_selected.custom_minimum_size.x = maxf(v, 4.0)
		return
	var rect := _selected.get_global_rect()
	_selected.offset_right += v - rect.size.x
	snap_anchor(_selected)

func _on_field_h(v: float) -> void:
	if not _selected: return
	if _selected.get_parent() is Container:
		_selected.custom_minimum_size.y = maxf(v, 4.0)
		return
	var rect := _selected.get_global_rect()
	_selected.offset_bottom += v - rect.size.y
	snap_anchor(_selected)

func _save_layout() -> void:
	var config := ConfigFile.new()
	config.load(SAVE_PATH) ## Best-effort: keep any sections we're not touching right now.
	for save_key in _roots:
		var root: Node = _roots[save_key]
		_walk_and_save(config, root, root, save_key)
	var err := config.save(SAVE_PATH)
	if err == OK:
		print("UiDebugEditor: saved layout to ", SAVE_PATH)
	else:
		push_warning("UiDebugEditor: failed to save layout (error %d) — read-only export?" % err)

func _walk_and_save(config: ConfigFile, root: Node, node: Node, save_key: String) -> void:
	for child in node.get_children():
		if not (child is Control):
			continue
		var key := String(root.get_path_to(child))
		if child.get_parent() is Container:
			config.set_value(save_key, key, {"custom_min_x": child.custom_minimum_size.x, "custom_min_y": child.custom_minimum_size.y})
		else:
			config.set_value(save_key, key, {
				"anchor_left": child.anchor_left, "anchor_top": child.anchor_top,
				"anchor_right": child.anchor_right, "anchor_bottom": child.anchor_bottom,
				"offset_left": child.offset_left, "offset_top": child.offset_top,
				"offset_right": child.offset_right, "offset_bottom": child.offset_bottom,
			})
		_walk_and_save(config, root, child, save_key)

func _clear_layout() -> void:
	var config := ConfigFile.new()
	var err := config.save(SAVE_PATH)
	if err == OK:
		print("UiDebugEditor: cleared saved layout — relaunch to see the scene defaults.")
	else:
		push_warning("UiDebugEditor: failed to clear saved layout (error %d)" % err)

func _apply_saved_layout(root: Node, save_key: String) -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK or not config.has_section(save_key):
		return
	_walk_and_apply(config, root, root, save_key)

func _walk_and_apply(config: ConfigFile, root: Node, node: Node, save_key: String) -> void:
	for child in node.get_children():
		if not (child is Control):
			continue
		var key := String(root.get_path_to(child))
		if config.has_section_key(save_key, key):
			var d: Dictionary = config.get_value(save_key, key, {})
			if child.get_parent() is Container:
				child.custom_minimum_size = Vector2(d.get("custom_min_x", 0.0), d.get("custom_min_y", 0.0))
			else:
				child.anchor_left = d.get("anchor_left", child.anchor_left)
				child.anchor_top = d.get("anchor_top", child.anchor_top)
				child.anchor_right = d.get("anchor_right", child.anchor_right)
				child.anchor_bottom = d.get("anchor_bottom", child.anchor_bottom)
				child.offset_left = d.get("offset_left", child.offset_left)
				child.offset_top = d.get("offset_top", child.offset_top)
				child.offset_right = d.get("offset_right", child.offset_right)
				child.offset_bottom = d.get("offset_bottom", child.offset_bottom)
		_walk_and_apply(config, root, child, save_key)

const UiEditHandle = preload("res://scripts/ui_edit_handle.gd")
