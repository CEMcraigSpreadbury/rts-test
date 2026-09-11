class_name MatchSettingsRow
extends HBoxContainer
## Game mode + Conquest Favour target picker, shared by the lobby (host-
## editable, mirrored to clients through Network) and the single player map
## select (local until Start).

## Fired when the user changes either control — never by show_values().
signal edited

var _mode_option: OptionButton
var _target_spin: SpinBox
var _map: MapInfo = null
## Whether the spin box holds a real number — false for a map with no known
## capture-point count until one is set.
var _has_target: bool = false
## Set while show_values() writes the controls, so doing that doesn't echo
## back out as an edit.
var _applying: bool = false

func _init() -> void:
	name = "MatchSettingsRow"
	_mode_option = OptionButton.new()
	for mode_name in Network.GAME_MODE_NAMES:
		_mode_option.add_item(mode_name)
	_mode_option.item_selected.connect(_on_changed.unbind(1))
	add_child(_mode_option)
	_target_spin = SpinBox.new()
	_target_spin.min_value = 100
	_target_spin.max_value = 100000
	_target_spin.step = 100
	_target_spin.suffix = "Favour"
	_target_spin.value_changed.connect(_on_changed.unbind(1))
	add_child(_target_spin)

## `target` 0 = the map's default (MapInfo.default_favour_target).
func show_values(mode: int, target: int, map: MapInfo, editable: bool) -> void:
	_map = map
	_applying = true
	_mode_option.select(mode)
	_mode_option.disabled = not editable
	var shown := target if target > 0 else (map.default_favour_target() if map != null else 0)
	## A map with no known point count leaves the match to work it out on
	## load (see Main._ready), so there's no number to show here.
	_has_target = shown > 0
	if _has_target:
		_target_spin.value = shown
	_target_spin.editable = editable
	_applying = false
	_refresh_visibility()

func set_editable(editable: bool) -> void:
	_mode_option.disabled = not editable
	_target_spin.editable = editable

func get_mode() -> int:
	return _mode_option.selected

## 0 while left at the map's default, so it keeps following the map.
func get_target() -> int:
	if not _has_target:
		return 0
	var target := int(_target_spin.value)
	if _map != null and target == _map.default_favour_target():
		return 0
	return target

func _refresh_visibility() -> void:
	_target_spin.visible = get_mode() == Network.GameMode.CONQUEST and _has_target

func _on_changed() -> void:
	if _applying:
		return
	_refresh_visibility()
	edited.emit()
