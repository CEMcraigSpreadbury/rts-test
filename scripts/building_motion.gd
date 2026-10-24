class_name BuildingMotion
extends Node

## Turns a building model's moving parts: the nodes the Blender kit exported
## apart from the body (common.moving), named for what they do —
## anim_spin_<degrees a second>_<id> turns round and round, and
## anim_sway_<degrees either way>_<tenths of a second a swing>_<id> rocks to
## and fro. Each turns about its own Y. Purely cosmetic and local to each
## peer; still while a building is going up or coming down, and frees itself
## when the model has nothing to move.

var _root: Node3D
var _building: ProductionBuilding
var _parts: Array[Node3D] = []
var _bases: Array[Basis] = []
## Radians a second for a spinner, 0 for a swayer.
var _spins: Array[float] = []
var _amplitudes: Array[float] = []
var _rates: Array[float] = []
var _phase: float = 0.0

## `root` holds the model; `building`, when given, holds the parts still
## while it is under construction or destroyed.
func _init(root: Node3D, building: ProductionBuilding = null) -> void:
	_root = root
	_building = building
	name = "Motion"

func _ready() -> void:
	for node in _root.find_children("anim_*", "Node3D", true, false):
		var bits: PackedStringArray = node.name.split("_")
		if bits.size() < 4:
			continue
		var part := node as Node3D
		if bits[1] == "spin":
			_spins.append(deg_to_rad(bits[2].to_float()))
			_amplitudes.append(0.0)
			_rates.append(0.0)
		elif bits[1] == "sway" and bits.size() >= 5 and bits[3].to_float() > 0.0:
			_spins.append(0.0)
			_amplitudes.append(deg_to_rad(bits[2].to_float()))
			_rates.append(TAU / (bits[3].to_float() * 0.1))
		else:
			continue
		_parts.append(part)
		_bases.append(part.basis)
	if _parts.is_empty():
		queue_free()
		return
	_phase = float(hash(get_instance_id()) % 1000) * 0.01

func _process(_delta: float) -> void:
	if _building != null and (_building.is_under_construction or _building.is_destroyed):
		return
	var t: float = GameClock.msec() * 0.001 + _phase
	for i in _parts.size():
		var angle: float
		if _spins[i] != 0.0:
			angle = fmod(t * _spins[i], TAU)
		else:
			## A second, quicker wave on top so it flutters rather than ticks.
			var w: float = t * _rates[i] + i * 1.9
			angle = _amplitudes[i] * (0.8 * sin(w) + 0.2 * sin(w * 2.7 + 0.6))
		_parts[i].basis = _bases[i] * Basis(Vector3.UP, angle)
