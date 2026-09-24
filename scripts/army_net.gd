class_name ArmyNet
extends Node
## Unit movement over the network, in bulk. The host sends one packed snapshot
## about SNAPSHOT_HZ times a second holding every unit whose position or
## heading changed (and each unit at least every FULL_REFRESH seconds, so a
## lost packet heals); clients ease each unit between snapshots. Replaces the
## per-unit MultiplayerSynchronizer sending position and rotation every
## network frame. The rest of what peers need to know about a unit — health,
## owner, tint, hold, regiment — goes the same way, in bulk and on change (see
## mark_state), replacing a MultiplayerSynchronizer on every unit.
##
## A unit is known on the wire by Unit.net_id, handed out by the host when the
## unit joins the sim. The first time the host sends a unit's state it names
## the unit by its node path too, which is how a client learns the id.

const SNAPSHOT_HZ: float = 15.0
const FULL_REFRESH: float = 2.0
## Units per RPC, keeping each packet near one MTU (11 bytes a unit).
const CHUNK: int = 110
## Position resolution on the wire: 2 cm, covering +-655 m.
const POSITION_SCALE: float = 50.0
## Smaller changes than these are not sent.
const MIN_MOVE: float = 0.02
const MIN_TURN: float = 0.03
const BYTES_PER_UNIT: int = 11

## Client side: net id -> Unit.
static var units_by_net_id: Dictionary = {}
## The match's ArmyNet, for units to report state changes to.
static var current: ArmyNet = null

var _timer: float = 0.0
var _next_net_id: int = 1
## Host side: net id -> [position, rotation.y, seconds since sent].
var _sent: Dictionary = {}
## Client side: units being eased toward their last snapshot.
var _easing: Dictionary = {}
## Host side: units whose state changed since the last send, and the ids whose
## path every client has been sent.
var _dirty: Dictionary = {}
var _named: Dictionary = {}
## Client side: states for a path not in the tree yet (the unit's spawn and
## its first state can cross), retried until PENDING_SECONDS.
var _pending: Array = []
const PENDING_SECONDS: float = 5.0

func _enter_tree() -> void:
	current = self
	multiplayer.peer_connected.connect(_on_peer_connected)

func _exit_tree() -> void:
	units_by_net_id.clear()
	if current == self:
		current = null
	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.disconnect(_on_peer_connected)

## Host: someone joined, so everyone's state goes out again, paths and all.
func _on_peer_connected(_id: int) -> void:
	if not multiplayer.is_server():
		return
	_named.clear()
	for node in get_tree().get_nodes_in_group(&"units"):
		var unit := node as Unit
		if unit != null and unit.net_id >= 0:
			_dirty[unit] = true

## Host: `unit`'s replicated state changed; it goes out with the next send.
func mark_state(unit: Unit) -> void:
	if multiplayer.is_server():
		_dirty[unit] = true

## Host: a new id for a unit joining the sim. Never reused, so a late packet
## can never land on a different unit.
func assign_net_id(unit: Unit) -> void:
	unit.net_id = _next_net_id
	_next_net_id += 1
	_dirty[unit] = true

## Client: a unit learned its id (Unit.net_id setter) or left.
static func register(unit: Unit) -> void:
	units_by_net_id[unit.net_id] = unit

static func unregister(unit: Unit) -> void:
	if units_by_net_id.get(unit.net_id) == unit:
		units_by_net_id.erase(unit.net_id)

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		_retry_pending(delta)
		return
	if multiplayer.get_peers().is_empty():
		_dirty.clear()
		return
	if not _dirty.is_empty():
		_send_states()
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 1.0 / SNAPSHOT_HZ
	_send_snapshot(1.0 / SNAPSHOT_HZ)

func _send_snapshot(elapsed: float) -> void:
	var start := Time.get_ticks_usec() if PerfStats.enabled else 0
	var changed: Array[Unit] = []
	var seen: Dictionary = {}
	for node in get_tree().get_nodes_in_group(&"units"):
		var unit := node as Unit
		if unit == null or unit.net_id < 0:
			continue
		seen[unit.net_id] = true
		var pos := unit.global_position
		var rot := unit.rotation.y
		var last: Array = _sent.get(unit.net_id, [])
		if not last.is_empty():
			last[2] = float(last[2]) + elapsed
			if (last[0] as Vector3).distance_squared_to(pos) < MIN_MOVE * MIN_MOVE \
					and absf(angle_difference(float(last[1]), rot)) < MIN_TURN and float(last[2]) < FULL_REFRESH:
				continue
		_sent[unit.net_id] = [pos, rot, 0.0]
		changed.append(unit)
	## Units that have gone.
	if _sent.size() > seen.size():
		for id in _sent.keys():
			if not seen.has(id):
				_sent.erase(id)
	for from in range(0, changed.size(), CHUNK):
		var count: int = mini(CHUNK, changed.size() - from)
		var bytes := PackedByteArray()
		bytes.resize(count * BYTES_PER_UNIT)
		for i in count:
			var unit: Unit = changed[from + i]
			var at := i * BYTES_PER_UNIT
			var pos := unit.global_position * POSITION_SCALE
			bytes.encode_u32(at, unit.net_id)
			bytes.encode_s16(at + 4, clampi(roundi(pos.x), -32768, 32767))
			bytes.encode_s16(at + 6, clampi(roundi(pos.y), -32768, 32767))
			bytes.encode_s16(at + 8, clampi(roundi(pos.z), -32768, 32767))
			bytes.encode_u8(at + 10, posmod(roundi(unit.rotation.y / TAU * 256.0), 256))
		_rpc_snapshot.rpc(bytes)
	if PerfStats.enabled:
		PerfStats.add_section(&"net snapshot", Time.get_ticks_usec() - start)

@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_snapshot(bytes: PackedByteArray) -> void:
	for at in range(0, bytes.size() - BYTES_PER_UNIT + 1, BYTES_PER_UNIT):
		var unit: Unit = units_by_net_id.get(bytes.decode_u32(at))
		if unit == null or not is_instance_valid(unit):
			continue
		var pos := Vector3(bytes.decode_s16(at + 4), bytes.decode_s16(at + 6), bytes.decode_s16(at + 8)) / POSITION_SCALE
		var rot := float(bytes.decode_u8(at + 10)) / 256.0 * TAU
		## Eased over one snapshot interval, from wherever it is now.
		_easing[unit] = [unit.global_position, pos, unit.rotation.y, rot, 0.0]

## Host: every marked unit's state, one reliable call for the lot. Each entry
## is [net_id, health, owner, tint, hold, regiment], with the unit's path added
## the first time.
func _send_states() -> void:
	var states: Array = []
	for unit in _dirty:
		if not is_instance_valid(unit) or not unit.is_inside_tree() or unit.net_id < 0:
			continue
		var state: Array = [unit.net_id, unit.status_current_health, unit.owner_peer_id, unit.team_tint, unit.hold_position, unit.regiment_id]
		if not _named.has(unit.net_id):
			_named[unit.net_id] = true
			state.append(unit.get_path())
		states.append(state)
	_dirty.clear()
	if not states.is_empty():
		_rpc_states.rpc(states)

@rpc("authority", "call_remote", "reliable")
func _rpc_states(states: Array) -> void:
	for state in states:
		if not _apply_state(state):
			_pending.append([state, 0.0])

## False while the unit it names is not here yet.
func _apply_state(state: Array) -> bool:
	var unit: Unit = units_by_net_id.get(int(state[0]))
	if (unit == null or not is_instance_valid(unit)) and state.size() > 6:
		unit = get_node_or_null(state[6] as NodePath) as Unit
		if unit == null:
			return false
		unit.net_id = int(state[0])
		ArmyNet.register(unit)
	if unit == null or not is_instance_valid(unit):
		## An update for a unit already gone (or never named): nothing to do.
		return true
	unit.status_current_health = int(state[1])
	unit.owner_peer_id = int(state[2])
	unit.team_tint = state[3]
	unit.hold_position = bool(state[4])
	unit.regiment_id = int(state[5])
	return true

func _retry_pending(delta: float) -> void:
	if _pending.is_empty():
		return
	var still: Array = []
	for entry in _pending:
		entry[1] = float(entry[1]) + delta
		if not _apply_state(entry[0]) and float(entry[1]) < PENDING_SECONDS:
			still.append(entry)
	_pending = still

func _process(delta: float) -> void:
	if _easing.is_empty():
		return
	var step := delta * SNAPSHOT_HZ
	for unit in _easing.keys():
		if not is_instance_valid(unit):
			_easing.erase(unit)
			continue
		var e: Array = _easing[unit]
		var t: float = minf(float(e[4]) + step, 1.0)
		e[4] = t
		(unit as Unit).global_position = (e[0] as Vector3).lerp(e[1], t)
		(unit as Unit).rotation.y = lerp_angle(float(e[2]), float(e[3]), t)
		if t >= 1.0:
			_easing.erase(unit)
