extends Node
## Autoload singleton wrapping Godot's high-level multiplayer API for
## direct-connect (IP-based) play, up to 4 players total.

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
## Fired when a player's own entry in `players` changes in place (currently
## just faction_index) — lets the lobby refresh one row instead of the whole list.
signal player_updated(peer_id: int)
signal connection_failed
signal connected_to_server
signal server_disconnected

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 4

## peer_id -> { "name": String, "color": Color, "faction_index": int }
var players: Dictionary = {}

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func host_game(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	players.clear()
	players[1] = {"name": "Host", "color": Color.WHITE, "faction_index": 0}
	return OK

func join_game(address: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	players.clear()
	return OK

func leave_game() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	players.clear()

func is_host() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.is_server()

func my_peer_id() -> int:
	return multiplayer.get_unique_id()

func _on_peer_connected(id: int) -> void:
	players[id] = {"name": "Player %d" % id, "color": Color.WHITE, "faction_index": 0}
	if is_host():
		_sync_player_list.rpc_id(id, players)
	player_connected.emit(id)

func _on_peer_disconnected(id: int) -> void:
	players.erase(id)
	player_disconnected.emit(id)

func _on_connected_ok() -> void:
	players[my_peer_id()] = {"name": "Me", "color": Color.WHITE, "faction_index": 0}
	connected_to_server.emit()

func _on_connected_fail() -> void:
	connection_failed.emit()

func _on_server_disconnected() -> void:
	players.clear()
	multiplayer.multiplayer_peer = null
	server_disconnected.emit()

## Lets a freshly-joined client learn about players who connected before it did.
@rpc("authority", "call_remote", "reliable")
func _sync_player_list(current_players: Dictionary) -> void:
	for id in current_players:
		players[id] = current_players[id]

## --- Faction selection (lobby only) ---

## Godot's high-level multiplayer here is star-topology (every RPC actually
## routes through the host — a client can't reach other clients directly,
## the same constraint main.gd's unit-animation relay works around). So a
## client proposes its choice to the host, which applies it and re-broadcasts;
## the host applies its own choice directly.
func set_my_faction(index: int) -> void:
	if is_host():
		_apply_faction_change(my_peer_id(), index)
	else:
		_rpc_request_faction.rpc_id(1, index)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_faction(index: int) -> void:
	if is_host():
		_apply_faction_change(multiplayer.get_remote_sender_id(), index)

func _apply_faction_change(peer_id: int, index: int) -> void:
	if not players.has(peer_id):
		return
	players[peer_id]["faction_index"] = index
	player_updated.emit(peer_id)
	if is_host():
		_rpc_faction_changed.rpc(peer_id, index)

@rpc("authority", "call_remote", "reliable")
func _rpc_faction_changed(peer_id: int, index: int) -> void:
	if players.has(peer_id):
		players[peer_id]["faction_index"] = index
	player_updated.emit(peer_id)
