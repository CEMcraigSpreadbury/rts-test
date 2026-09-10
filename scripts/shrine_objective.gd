extends Objective
class_name ShrineObjective
## An Objective guarded by a single big monster, whose Shrine can only
## ever train that same monster. Which one it is gets rolled once per match.
##
## The roll deliberately does NOT happen independently on each peer: the
## Shrine's build menu labels its button from producibles[0] (see main.gd's
## _show_build_menu), and enqueue orders travel as an index into that same
## array, so two peers rolling separately would leave a client's button
## naming a different monster than the one the host actually trains. The host
## rolls, and every client asks it for the answer (see _rpc_request_monster) —
## a request rather than a broadcast because the host reaches main.tscn first
## (lobby.gd's _start_game is call_local, so clients change scene a round-trip
## later) and a broadcast sent from the host's _ready would arrive before
## clients had a node to deliver it to.

## Where the lone guard stands relative to the objective's origin — in front
## of the Shrine, which sits on the origin itself.
const GUARD_SPAWN_OFFSET: Vector3 = Vector3(0.0, 0.0, 3.2)

## A client repeats its request on this interval until an answer lands. The
## first request is sent from _ready, which relies on the host having already
## reached main.tscn — true in practice (see the class comment) but a scene-
## load timing assumption rather than a guarantee, and an RPC that arrives
## before the host's own copy of this node exists is simply dropped by Godot
## with no delivery failure reported back to the sender. Without a retry that
## single dropped packet would strand the client permanently: no guard, and a
## Shrine still offering all the monsters it was never trimmed down from.
const MONSTER_REQUEST_RETRY_SEC: float = 0.5
## Gives up (loudly) rather than retrying forever, since a host that hasn't
## answered by now isn't going to. Generous: the host loads main.tscn ahead of
## every client, so this whole window only ever needs to cover the gap between
## the two, not a cold scene load.
const MONSTER_REQUEST_MAX_ATTEMPTS: int = 20

## Shrines sharing a non-empty group train the same monster in a match — the
## map generator gives each player's copy of a shrine the same group, so no
## one ends up with a stronger monster on their doorstep.
@export var roll_group: StringName = &""

## Index into the Shrine's original producibles list, -1 until rolled/received.
var monster_index: int = -1

var _request_timer: Timer = null
var _request_attempts: int = 0

func _ready() -> void:
	## Has to run before super._ready(), which is what puts the guard on
	## patrol and leashes it — by then the guard needs to already exist.
	if multiplayer.is_server():
		_apply_monster(_roll_monster())
	super._ready()
	if not multiplayer.is_server() and multiplayer.multiplayer_peer != null:
		_start_monster_requests()

## Host only. Shared rolls live on the match scene, so they reset every match.
func _roll_monster() -> int:
	var count: int = _shrine().producibles.size()
	if roll_group == &"":
		return randi() % count
	var main := get_tree().current_scene
	var rolls: Dictionary = main.get_meta(&"shrine_rolls", {})
	if not rolls.has(roll_group):
		rolls[roll_group] = randi() % count
		main.set_meta(&"shrine_rolls", rolls)
	return rolls[roll_group]

## Reached via get_node rather than @onready: @onready assignments are injected
## into the _ready of the script that declares them, so anything this class
## touches before its super._ready() call can't rely on the base class's
## @onready vars (guards/buildings) having been filled in yet.
func _shrine() -> ProductionBuilding:
	return $Buildings/Shrine as ProductionBuilding

## Idempotent — a late answer arriving after an earlier one already landed
## must not leave this objective with two guards.
func _apply_monster(index: int) -> void:
	if monster_index != -1:
		return
	monster_index = index
	_stop_monster_requests()
	var shrine := _shrine()
	var item: ProducibleItem = shrine.producibles[index]
	var only_producible: Array[ProducibleItem] = [item]
	shrine.producibles = only_producible

	var guard: Unit = item.unit_scene.instantiate()
	guard.name = "Guard"
	guard.position = GUARD_SPAWN_OFFSET
	## Set before add_child for the same reason the hand-placed guards in the
	## other objective scenes bake these into their .tscn — see the ownership
	## note on Objective._ready. A guard that spends even one frame in the
	## tree with the scene default owner_peer_id of 1 can be caught by
	## FogOfWar's one-time initial "explored" stamp and permanently reveal
	## this objective to the host.
	guard.owner_peer_id = 0
	guard.team_tint = Color(0.5, 0.5, 0.5)
	$Guards.add_child(guard)
	## No-op on the host, where this runs before Objective._ready's own pass —
	## see register_guard. Needed on a client, where the answer that creates
	## this guard arrives long after _ready has been and gone.
	register_guard(guard)

## --- Client-side request/retry (see MONSTER_REQUEST_RETRY_SEC) ---

func _start_monster_requests() -> void:
	_request_timer = Timer.new()
	_request_timer.wait_time = MONSTER_REQUEST_RETRY_SEC
	_request_timer.timeout.connect(_request_monster_once)
	add_child(_request_timer)
	_request_timer.start()
	_request_monster_once()

func _request_monster_once() -> void:
	## The peer can go away mid-retry (host quit, connection dropped), which
	## would make rpc_id error rather than simply go unanswered.
	if multiplayer.multiplayer_peer == null:
		_stop_monster_requests()
		return
	if _request_attempts >= MONSTER_REQUEST_MAX_ATTEMPTS:
		push_error("ShrineObjective at %s got no monster from the host after %d requests; its Shrine will keep offering every monster and it has no guard." % [get_path(), _request_attempts])
		_stop_monster_requests()
		return
	_request_attempts += 1
	_rpc_request_monster.rpc_id(1)

func _stop_monster_requests() -> void:
	if _request_timer == null:
		return
	_request_timer.stop()
	_request_timer.queue_free()
	_request_timer = null

## --- Host/client handshake ---

@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_monster() -> void:
	## A request can legitimately land before the host has rolled (both peers
	## race through their own _ready): answering -1 would be applied verbatim
	## by the client. Staying silent instead lets its retry cover the gap.
	if not multiplayer.is_server() or monster_index == -1:
		return
	_rpc_set_monster.rpc_id(multiplayer.get_remote_sender_id(), monster_index)

@rpc("authority", "call_remote", "reliable")
func _rpc_set_monster(index: int) -> void:
	_apply_monster(index)
