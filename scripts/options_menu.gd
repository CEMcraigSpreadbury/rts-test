class_name OptionsMenu
extends PanelContainer
## Tabbed settings screen shared by the main menu and the in-match pause menu.
## Every control writes straight through to the Settings autoload, so there is
## no apply/cancel step — the owner just hides this on `closed`.

signal closed

const WINDOW_MODE_NAMES: Array[String] = ["Windowed", "Borderless Fullscreen", "Fullscreen"]
const MAX_FPS_NAMES: Array[String] = ["Unlimited", "30", "60", "120", "144", "240"]
const MAX_FPS_VALUES: Array[int] = [0, 30, 60, 120, 144, 240]

## Order here is the order the Controls tab lists them in.
const KEY_ACTION_NAMES := {
	&"camera_up": "Pan Camera Up",
	&"camera_down": "Pan Camera Down",
	&"camera_left": "Pan Camera Left",
	&"camera_right": "Pan Camera Right",
	&"camera_rotate_left": "Rotate Camera Left",
	&"camera_rotate_right": "Rotate Camera Right",
	&"center_selection": "Center on Selection",
	&"idle_villager": "Next Idle Villager",
	&"select_military": "Select All Military",
	&"last_attack": "Jump to Last Attack",
}

const LABEL_WIDTH: float = 220.0
const CONTROL_WIDTH: float = 260.0

@onready var tab_buttons: HBoxContainer = $Margin/VBox/Tabs
@onready var pages: Array[Control] = [
	$Margin/VBox/Pages/Game,
	$Margin/VBox/Pages/Visuals,
	$Margin/VBox/Pages/SoundEffects,
	$Margin/VBox/Pages/Controls,
]
@onready var key_list: VBoxContainer = $Margin/VBox/Pages/Controls/Scroll/KeyList

var _key_buttons: Dictionary = {}
## The action waiting for its next key press, or &"" when not rebinding.
var _rebinding_action: StringName = &""

func _ready() -> void:
	var group := ButtonGroup.new()
	for i in tab_buttons.get_child_count():
		var tab: Button = tab_buttons.get_child(i)
		tab.toggle_mode = true
		tab.button_group = group
		tab.pressed.connect(_show_page.bind(i))
	$Margin/VBox/BackButton.pressed.connect(close)
	$Margin/VBox/Pages/Controls/ResetButton.pressed.connect(_on_reset_keys_pressed)

	_build_game_page(pages[0])
	_build_visuals_page(pages[1])
	_build_sound_page(pages[2])
	_build_controls_page()
	Settings.changed.connect(_on_settings_changed)
	visibility_changed.connect(_on_visibility_changed)
	_show_page(0)

func open() -> void:
	visible = true

func close() -> void:
	_cancel_rebind()
	visible = false
	closed.emit()

func _show_page(index: int) -> void:
	_cancel_rebind()
	for i in pages.size():
		pages[i].visible = i == index
	(tab_buttons.get_child(index) as Button).button_pressed = true

func _on_visibility_changed() -> void:
	if not visible:
		_cancel_rebind()

## _input rather than _unhandled_input: a key being rebound (or Escape backing
## out of the menu) must never also reach main.gd's hotkeys underneath.
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if _rebinding_action != &"":
		if event.keycode != KEY_ESCAPE:
			Settings.set_key(_rebinding_action, event.keycode)
		_cancel_rebind()
	elif event.keycode == KEY_ESCAPE:
		close()
	else:
		return
	get_viewport().set_input_as_handled()

## --- Pages ---

func _build_game_page(page: Control) -> void:
	_add_check(page, "Edge Scrolling", &"edge_pan")
	_add_slider(page, "Camera Pan Speed", Settings.get_value(&"pan_speed"), 8.0, 48.0, 1.0,
			func(v: float): Settings.set_value(&"pan_speed", v), func(v: float): return "%d" % v)
	_add_slider(page, "Camera Zoom Speed", Settings.get_value(&"zoom_speed"), 0.5, 5.0, 0.25,
			func(v: float): Settings.set_value(&"zoom_speed", v), func(v: float): return "%.2f" % v)
	_add_check(page, "Show Damage Numbers", &"damage_numbers")

func _build_visuals_page(page: Control) -> void:
	_add_choice(page, "Window Mode", WINDOW_MODE_NAMES,
			Settings.get_value(&"window_mode"), func(i: int): Settings.set_value(&"window_mode", i))
	_add_check(page, "VSync", &"vsync")
	_add_choice(page, "Frame Rate Limit", MAX_FPS_NAMES,
			maxi(MAX_FPS_VALUES.find(Settings.get_value(&"max_fps")), 0),
			func(i: int): Settings.set_value(&"max_fps", MAX_FPS_VALUES[i]))
	_add_slider(page, "Render Scale", Settings.get_value(&"render_scale") * 100.0, 50.0, 100.0, 5.0,
			func(v: float): Settings.set_value(&"render_scale", v / 100.0), func(v: float): return "%d%%" % v)
	_add_check(page, "Depth of Field", &"depth_of_field")

func _build_sound_page(page: Control) -> void:
	for bus_name in Settings.BUSES:
		_add_slider(page, bus_name,Settings.volumes[bus_name] * 100.0, 0.0, 100.0, 1.0,
				func(v: float): Settings.set_bus_volume(bus_name, v / 100.0), func(v: float): return "%d%%" % v)

func _build_controls_page() -> void:
	for action in KEY_ACTION_NAMES:
		var button := Button.new()
		button.pressed.connect(_start_rebind.bind(action))
		_key_buttons[action] = button
		_add_row(key_list, KEY_ACTION_NAMES[action], button)
	_refresh_key_buttons()

## --- Rows ---

func _add_row(page: Control, text: String, control: Control) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = LABEL_WIDTH
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	control.custom_minimum_size.x = CONTROL_WIDTH
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(control)
	page.add_child(row)

func _add_check(page: Control, text: String, key: StringName) -> void:
	var check := CheckBox.new()
	check.button_pressed = Settings.get_value(key)
	check.toggled.connect(func(on: bool): Settings.set_value(key, on))
	_add_row(page, text, check)

func _add_slider(page: Control, text: String, value: float, min_value: float, max_value: float,
		step: float, on_changed: Callable, format: Callable) -> void:
	var box := HBoxContainer.new()
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var readout := Label.new()
	readout.custom_minimum_size.x = 52.0
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	readout.text = format.call(value)
	slider.value_changed.connect(func(v: float):
		readout.text = format.call(v)
		on_changed.call(v))
	box.add_child(slider)
	box.add_child(readout)
	_add_row(page, text, box)

func _add_choice(page: Control, text: String, names: Array[String], selected: int, on_selected: Callable) -> void:
	var option := OptionButton.new()
	for item_name in names:
		option.add_item(item_name)
	option.select(selected)
	option.item_selected.connect(on_selected)
	_add_row(page, text, option)

## --- Key rebinding ---

func _start_rebind(action: StringName) -> void:
	_cancel_rebind()
	_rebinding_action = action
	(_key_buttons[action] as Button).text = "Press a key..."

func _cancel_rebind() -> void:
	if _rebinding_action == &"":
		return
	_rebinding_action = &""
	_refresh_key_buttons()

func _on_reset_keys_pressed() -> void:
	_cancel_rebind()
	Settings.reset_keys()

func _on_settings_changed(key: StringName) -> void:
	if _key_buttons.has(key):
		_refresh_key_buttons()

func _refresh_key_buttons() -> void:
	for action in _key_buttons:
		(_key_buttons[action] as Button).text = OS.get_keycode_string(Settings.get_key(action))
