class_name UnitVoices
extends Node
## Every unit's voice, from a few shared players: selection and order barks are
## only ever one unit at a time (a group plays one member's line), so a player
## per unit — two nodes on every soldier of an army — was almost always silent.
## Interface lines (selecting, acknowledging an order) are flat; the attack bark
## is positional, played where the unit stands (see Unit._order_sound_player).

## The match's voices (every peer has them).
static var current: UnitVoices = null

const INTERFACE_PLAYERS: int = 4
const POSITIONAL_PLAYERS: int = 8

var _interface: Array[AudioStreamPlayer] = []
var _positional: Array[AudioStreamPlayer3D] = []

func _ready() -> void:
	for i in INTERFACE_PLAYERS:
		var player := AudioStreamPlayer.new()
		player.bus = &"SFX"
		add_child(player)
		_interface.append(player)
	for i in POSITIONAL_PLAYERS:
		## As each unit's own UnitAudioPlayer had it.
		var player := AudioStreamPlayer3D.new()
		player.bus = &"SFX"
		player.unit_size = 20.0
		player.max_distance = 40.0
		add_child(player)
		_positional.append(player)

func _enter_tree() -> void:
	current = self

func _exit_tree() -> void:
	if current == self:
		current = null

## A flat player to speak through: an idle one if any is, else the oldest.
func interface_player() -> AudioStreamPlayer:
	return _free(_interface)

## A positional player moved to `at`.
func positional_player(at: Vector3) -> AudioStreamPlayer3D:
	var player: AudioStreamPlayer3D = _free(_positional)
	player.global_position = at
	return player

func _free(players: Array) -> Node:
	for player in players:
		if not player.playing:
			return player
	## All busy: cut off the one that has been talking longest.
	var oldest: Node = players[0]
	for player in players:
		if player.get_playback_position() > oldest.get_playback_position():
			oldest = player
	return oldest
