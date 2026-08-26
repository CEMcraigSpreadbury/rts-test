extends Node
## Autoload singleton tracking totals per player (peer_id) per ResourceType.
## The host holds the only authoritative copy; each client is told only its
## own totals via a targeted RPC, so one player's economy stays private from
## another's.

signal changed(resource_name: String, amount: int)

## peer_id -> { ResourceType -> int }. Only meaningful on the host.
var _totals: Dictionary = {}

func add(peer_id: int, resource_type: ResourceType, amount: int) -> void:
	if amount <= 0 or resource_type == null:
		return
	_set_amount(peer_id, resource_type, get_amount(peer_id, resource_type) + amount)

func can_afford(peer_id: int, costs: Array[ResourceCost]) -> bool:
	for cost in costs:
		if get_amount(peer_id, cost.resource_type) < cost.amount:
			return false
	return true

## Caller must have already checked can_afford(); this does not clamp or refuse.
func spend(peer_id: int, costs: Array[ResourceCost]) -> void:
	for cost in costs:
		_set_amount(peer_id, cost.resource_type, get_amount(peer_id, cost.resource_type) - cost.amount)

func get_amount(peer_id: int, resource_type: ResourceType) -> int:
	var per_player: Dictionary = _totals.get(peer_id, {})
	return per_player.get(resource_type, 0)

func _set_amount(peer_id: int, resource_type: ResourceType, new_amount: int) -> void:
	var per_player: Dictionary = _totals.get(peer_id, {})
	per_player[resource_type] = new_amount
	_totals[peer_id] = per_player
	_notify_owner(peer_id, resource_type.display_name, new_amount)

func _notify_owner(peer_id: int, resource_name: String, amount: int) -> void:
	if peer_id == multiplayer.get_unique_id():
		changed.emit(resource_name, amount)
	else:
		_rpc_notify.rpc_id(peer_id, resource_name, amount)

@rpc("authority", "call_remote", "reliable")
func _rpc_notify(resource_name: String, amount: int) -> void:
	changed.emit(resource_name, amount)
