extends Node
## Per-player audio volume, persisted to user://audio_settings.cfg. Not
## networked — this is local preference, unrelated to game state, so every
## peer just manages its own copy independently.

const SAVE_PATH := "user://audio_settings.cfg"
const BUSES := ["Master", "Music", "Ambience", "SFX"]

var volumes: Dictionary = {"Master": 1.0, "Music": 1.0, "Ambience": 1.0, "SFX": 1.0}

func _ready() -> void:
	_load()
	for bus_name in BUSES:
		_apply(bus_name)

func set_bus_volume(bus_name: String, linear_volume: float) -> void:
	volumes[bus_name] = clampf(linear_volume, 0.0, 1.0)
	_apply(bus_name)
	_save()

func _apply(bus_name: String) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx != -1:
		AudioServer.set_bus_volume_db(idx, linear_to_db(volumes[bus_name]))

func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		for bus_name in BUSES:
			volumes[bus_name] = config.get_value("audio", bus_name, 1.0)

func _save() -> void:
	var config := ConfigFile.new()
	for bus_name in BUSES:
		config.set_value("audio", bus_name, volumes[bus_name])
	config.save(SAVE_PATH)
