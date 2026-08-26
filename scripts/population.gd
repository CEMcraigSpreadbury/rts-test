extends Node
## Autoload singleton tracking population usage/capacity per player (peer_id).
## Same host-authoritative + targeted-RPC pattern as ResourceStockpile: the
## host holds the only authoritative copy, each client is told only its own
## numbers.
##
## "Used" is reserved the moment a unit enters a production queue (not when it
## actually spawns) so a player can't queue past the cap, and is released only
## when that unit later dies — see ProductionBuilding.enqueue() and
## Unit._die().

signal changed(used: int, cap: int)

var _used: Dictionary = {}
var _cap: Dictionary = {}

func get_used(peer_id: int) -> int:
	return _used.get(peer_id, 0)

func get_cap(peer_id: int) -> int:
	return _cap.get(peer_id, 0)

func has_room(peer_id: int, amount: int) -> bool:
	return get_used(peer_id) + amount <= get_cap(peer_id)

func reserve(peer_id: int, amount: int) -> void:
	_used[peer_id] = get_used(peer_id) + amount
	_notify(peer_id)

func release(peer_id: int, amount: int) -> void:
	_used[peer_id] = maxi(get_used(peer_id) - amount, 0)
	_notify(peer_id)

func add_cap(peer_id: int, amount: int) -> void:
	_cap[peer_id] = get_cap(peer_id) + amount
	_notify(peer_id)

func _notify(peer_id: int) -> void:
	if peer_id == multiplayer.get_unique_id():
		changed.emit(get_used(peer_id), get_cap(peer_id))
	else:
		_rpc_notify.rpc_id(peer_id, get_used(peer_id), get_cap(peer_id))

@rpc("authority", "call_remote", "reliable")
func _rpc_notify(used: int, cap: int) -> void:
	changed.emit(used, cap)
