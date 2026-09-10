extends Node
## Per-player preferences (game, visuals, audio, key bindings), persisted to
## user://settings.cfg. Not networked — this is local preference, unrelated to
## game state, so every peer just manages its own copy independently.
##
## Anything that reads a setting at runtime (the camera, main.gd) listens to
## `changed` rather than polling, so the options menu takes effect live.

signal changed(key: StringName)

const SAVE_PATH := "user://settings.cfg"
## Where volumes lived before there was an options menu — read only when
## SAVE_PATH doesn't exist yet, so existing levels carry over.
const LEGACY_AUDIO_PATH := "user://audio_settings.cfg"
const BUSES := ["Master", "Music", "Ambience", "SFX"]

enum WindowMode { WINDOWED, BORDERLESS_FULLSCREEN, EXCLUSIVE_FULLSCREEN }

const DEFAULTS := {
	&"edge_pan": false,
	&"pan_speed": 24.0,
	&"zoom_speed": 2.0,
	&"damage_numbers": true,
	&"window_mode": WindowMode.WINDOWED,
	&"vsync": true,
	&"max_fps": 0,
	&"render_scale": 1.0,
	&"depth_of_field": true,
}

## Only the fixed, per-player hotkeys. Ability/production/building hotkeys are
## laid out by button slot in main.gd and aren't rebindable.
const DEFAULT_KEYS := {
	&"camera_up": KEY_W,
	&"camera_down": KEY_S,
	&"camera_left": KEY_A,
	&"camera_right": KEY_D,
	&"camera_rotate_left": KEY_Q,
	&"camera_rotate_right": KEY_E,
	&"center_selection": KEY_SPACE,
	&"idle_villager": KEY_PERIOD,
	&"select_military": KEY_COMMA,
	&"last_attack": KEY_BACKSPACE,
}

var volumes: Dictionary = {"Master": 1.0, "Music": 1.0, "Ambience": 1.0, "SFX": 1.0}
var values: Dictionary = DEFAULTS.duplicate()
var keys: Dictionary = DEFAULT_KEYS.duplicate()

func _ready() -> void:
	_load()
	for bus_name in BUSES:
		_apply_volume(bus_name)
	for key in values:
		_apply(key, true)

func get_value(key: StringName) -> Variant:
	return values[key]

func set_value(key: StringName, value: Variant) -> void:
	if values[key] == value:
		return
	values[key] = value
	_apply(key, false)
	_save()
	changed.emit(key)

func set_bus_volume(bus_name: String, linear_volume: float) -> void:
	volumes[bus_name] = clampf(linear_volume, 0.0, 1.0)
	_apply_volume(bus_name)
	_save()

## --- Key bindings ---

func get_key(action: StringName) -> Key:
	return keys[action]

## Binding a key another action already holds swaps the two, so no action is
## ever left sharing a key or unbound.
func set_key(action: StringName, keycode: Key) -> void:
	for other in keys:
		if other != action and keys[other] == keycode:
			keys[other] = keys[action]
			changed.emit(other)
	keys[action] = keycode
	_save()
	changed.emit(action)

func reset_keys() -> void:
	keys = DEFAULT_KEYS.duplicate()
	_save()
	for action in keys:
		changed.emit(action)

func is_action_key_pressed(action: StringName) -> bool:
	return Input.is_key_pressed(keys[action])

func is_action_key_event(event: InputEvent, action: StringName) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.keycode == keys[action]

## --- Applying ---

func _apply_volume(bus_name: String) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx != -1:
		AudioServer.set_bus_volume_db(idx, linear_to_db(volumes[bus_name]))

## Only the settings the engine owns directly are applied here; the rest
## (camera, damage numbers, depth of field) are read by whatever uses them.
func _apply(key: StringName, at_startup: bool) -> void:
	match key:
		&"window_mode":
			_apply_window_mode(at_startup)
		&"vsync":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if values[&"vsync"] else DisplayServer.VSYNC_DISABLED)
		&"max_fps":
			Engine.max_fps = values[&"max_fps"]
		&"render_scale":
			get_tree().root.scaling_3d_scale = values[&"render_scale"]

## At startup, "windowed" leaves the window alone — forcing it would undo a
## maximized window or whatever the editor's embedded game view asked for.
func _apply_window_mode(at_startup: bool) -> void:
	match values[&"window_mode"]:
		WindowMode.BORDERLESS_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		WindowMode.EXCLUSIVE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		_:
			var current := DisplayServer.window_get_mode()
			if not at_startup or current == DisplayServer.WINDOW_MODE_FULLSCREEN \
					or current == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

## --- Persistence ---

func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		if config.load(LEGACY_AUDIO_PATH) != OK:
			return
	for bus_name in BUSES:
		volumes[bus_name] = config.get_value("audio", bus_name, 1.0)
	for key in DEFAULTS:
		var loaded: Variant = config.get_value("settings", key, DEFAULTS[key])
		if typeof(loaded) == typeof(DEFAULTS[key]):
			values[key] = loaded
	for action in DEFAULT_KEYS:
		keys[action] = int(config.get_value("keys", action, DEFAULT_KEYS[action]))

func _save() -> void:
	var config := ConfigFile.new()
	for bus_name in BUSES:
		config.set_value("audio", bus_name, volumes[bus_name])
	for key in values:
		config.set_value("settings", key, values[key])
	for action in keys:
		config.set_value("keys", action, keys[action])
	config.save(SAVE_PATH)
