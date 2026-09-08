extends Objective
class_name MonsterDenObjective
## An Objective guarded by a single big monster, whose Monster Den can only
## ever train that same monster. Which one it is gets rolled once per match.
##
## The roll deliberately does NOT happen independently on each peer: the Den's
## build menu labels its button from producibles[0] (see main.gd's
## _show_build_menu), and enqueue orders travel as an index into that same
## array, so two peers rolling separately would leave a client's button
## naming a different monster than the one the host actually trains. The host
## rolls, and every client asks it for the answer once its own copy of the
## scene exists (see _rpc_request_monster) — a request rather than a broadcast
## because the host reaches main.tscn first (lobby.gd's _start_game is
## call_local, so clients change scene a round-trip later) and a broadcast
## sent from the host's _ready would arrive before clients had a node to
## deliver it to.

## Where the lone guard stands relative to the objective's origin — in front
## of the Den, which sits on the origin itself.
const GUARD_SPAWN_OFFSET: Vector3 = Vector3(0.0, 0.0, 3.2)

## Index into the Den's original producibles list, -1 until rolled/received.
var monster_index: int = -1

func _ready() -> void:
	## Has to run before super._ready(), which is what puts the guard on
	## patrol and leashes it — by then the guard needs to already exist.
	if multiplayer.is_server():
		_apply_monster(randi() % _den().producibles.size())
	super._ready()
	if not multiplayer.is_server() and multiplayer.multiplayer_peer != null:
		_rpc_request_monster.rpc_id(1)

## Reached via get_node rather than @onready: @onready assignments are injected
## into the _ready of the script that declares them, so anything this class
## touches before its super._ready() call can't rely on the base class's
## @onready vars (guards/buildings) having been filled in yet.
func _den() -> ProductionBuilding:
	return $Buildings/MonsterDen as ProductionBuilding

## Idempotent — a client that somehow both receives an answer and rolls one
## locally must not end up with two guards.
func _apply_monster(index: int) -> void:
	if monster_index != -1:
		return
	monster_index = index
	var den := _den()
	var item: ProducibleItem = den.producibles[index]
	var only_producible: Array[ProducibleItem] = [item]
	den.producibles = only_producible

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

@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_monster() -> void:
	if not multiplayer.is_server():
		return
	_rpc_set_monster.rpc_id(multiplayer.get_remote_sender_id(), monster_index)

@rpc("authority", "call_remote", "reliable")
func _rpc_set_monster(index: int) -> void:
	_apply_monster(index)
