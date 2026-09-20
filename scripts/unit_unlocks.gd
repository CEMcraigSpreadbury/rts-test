extends Node
## Autoload singleton: which units each player has unlocked by finishing an
## upgrade somewhere in their base (see ProducibleItem.grants_unlock /
## requires_unlock). Researching Lances at a Blacksmith is what puts the
## Cavalier on every Stables that player owns, so an unlock can't live on the
## building that granted it the way ProductionBuilding._purchased_upgrades does.
##
## Host-authoritative like Pacts, and broadcast rather than sent privately —
## what someone can train isn't secret, and every peer's HUD needs it to
## decide which producible buttons to draw.

## The local player's own unlocks changed.
signal unlocks_changed

## peer_id -> Array[StringName] of tags granted.
var _granted: Dictionary = {}

## An autoload, so it outlives a match — without this a rematch or the next
## mission would open with the last one's unlocks already bought.
func reset() -> void:
	_granted.clear()

func has(peer_id: int, tag: StringName) -> bool:
	if tag == &"":
		return true
	return _granted.get(peer_id, []).has(tag)

## Host only. Returns false if this player already had it (a second Blacksmith
## can't sell the same unlock twice).
func grant(peer_id: int, tag: StringName) -> bool:
	if not multiplayer.is_server() or tag == &"":
		return false
	if has(peer_id, tag):
		return false
	var tags: Array = _granted.get(peer_id, [])
	tags.append(tag)
	_granted[peer_id] = tags
	var typed: Array[StringName] = []
	typed.assign(tags)
	_rpc_granted.rpc(peer_id, typed)
	return true

@rpc("authority", "call_local", "reliable")
func _rpc_granted(peer_id: int, tags: Array[StringName]) -> void:
	_granted[peer_id] = tags
	if peer_id == multiplayer.get_unique_id():
		unlocks_changed.emit()
