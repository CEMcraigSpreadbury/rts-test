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
##
## There are two independent pools. MAIN is the ordinary Human population fed
## by Houses; PACT is the separate, much smaller cap that units from an allied
## race spend instead (see Pacts), so allying always adds army on top of your
## Humans rather than competing with them. A unit declares which pool it
## belongs to with Unit.population_pool, a building which pool its
## population_capacity feeds with ProductionBuilding.population_pool. The
## enum itself is PopulationPool.Kind — an autoload's name can't be used as a
## type, which an export needs.

signal changed(used: int, cap: int, pool: int)

## Ceiling on the PACT pool however many pact buildings are standing.
const MAX_PACT_CAP: int = 40

var _used: Dictionary = {}
var _cap: Dictionary = {}

## Emptied at the start of every match, for the same reason as
## ResourceStockpile.reset — this is an autoload and outlives a match.
func reset() -> void:
	_used.clear()
	_cap.clear()

## Realm has no Pacts: allied races come from their settlements and share the
## one army, so every pool is the main one.
static func _pool(pool: PopulationPool.Kind) -> PopulationPool.Kind:
	return PopulationPool.Kind.MAIN if MatchRules.realm() else pool

func get_used(peer_id: int, pool: PopulationPool.Kind = PopulationPool.Kind.MAIN) -> int:
	pool = _pool(pool)
	return _used.get(_key(peer_id, pool), 0)

## A scenario can pin a player's cap regardless of what they have built (see
## ScenarioModifiers.population_cap); 0 there means the ordinary rules. That
## only ever governs the MAIN pool — a scenario pinning Human population
## shouldn't silently hand out pact room as well.
func get_cap(peer_id: int, pool: PopulationPool.Kind = PopulationPool.Kind.MAIN) -> int:
	pool = _pool(pool)
	if pool == PopulationPool.Kind.MAIN:
		var fixed: int = MatchRules.active().population_cap(peer_id)
		if fixed > 0:
			return fixed
		return _cap.get(_key(peer_id, pool), 0)
	## An allied race is meant to be a wing of your army, never the whole of
	## it, so pact room stops climbing however many of their halls you raise.
	return mini(_cap.get(_key(peer_id, pool), 0), MAX_PACT_CAP)

func has_room(peer_id: int, amount: int, pool: PopulationPool.Kind = PopulationPool.Kind.MAIN) -> bool:
	return get_used(peer_id, pool) + amount <= get_cap(peer_id, pool)

func reserve(peer_id: int, amount: int, pool: PopulationPool.Kind = PopulationPool.Kind.MAIN) -> void:
	pool = _pool(pool)
	_used[_key(peer_id, pool)] = get_used(peer_id, pool) + amount
	_notify(peer_id, pool)

func release(peer_id: int, amount: int, pool: PopulationPool.Kind = PopulationPool.Kind.MAIN) -> void:
	pool = _pool(pool)
	_used[_key(peer_id, pool)] = maxi(get_used(peer_id, pool) - amount, 0)
	_notify(peer_id, pool)

func add_cap(peer_id: int, amount: int, pool: PopulationPool.Kind = PopulationPool.Kind.MAIN) -> void:
	pool = _pool(pool)
	_cap[_key(peer_id, pool)] = get_cap(peer_id, pool) + amount
	_notify(peer_id, pool)

func _key(peer_id: int, pool: PopulationPool.Kind) -> String:
	return "%d:%d" % [peer_id, int(pool)]

func _notify(peer_id: int, pool: PopulationPool.Kind) -> void:
	if peer_id == multiplayer.get_unique_id():
		changed.emit(get_used(peer_id, pool), get_cap(peer_id, pool), int(pool))
	elif Network.can_rpc_to(peer_id):
		_rpc_notify.rpc_id(peer_id, get_used(peer_id, pool), get_cap(peer_id, pool), int(pool))

@rpc("authority", "call_remote", "reliable")
func _rpc_notify(used: int, cap: int, pool: int) -> void:
	changed.emit(used, cap, pool)
