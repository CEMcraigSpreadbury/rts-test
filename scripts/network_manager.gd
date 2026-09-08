extends Node
## Autoload singleton wrapping Godot's high-level multiplayer API. Supports
## two independent transports that both just assign a MultiplayerPeer to
## `multiplayer.multiplayer_peer` — everything past that point (RPCs,
## MultiplayerSynchronizer, `players`, all the signals below) works
## identically regardless of which one connected the players:
## - Direct Connect: raw ENetMultiplayerPeer, typed IP (host_game/join_game).
## - Steam: SteamMultiplayerPeer over a Steam lobby, found either by Quick
##   Play matchmaking or by hosting/joining a Steam lobby directly (see
##   host_steam_lobby/quick_play/join_steam_lobby below). Requires the
##   Steamworks autoload to have initialized successfully.

signal player_connected(peer_id: int)
## player_data is that peer's now-removed `players` entry, passed along since
## by the time this fires the entry is already gone from `players` itself.
signal player_disconnected(peer_id: int, player_data: Dictionary)
## Fired when a player's own entry in `players` changes in place (faction_index
## or ready) — lets the lobby refresh one row instead of the whole list.
signal player_updated(peer_id: int)
signal connection_failed
signal connected_to_server
signal server_disconnected

## Fired once a Steam lobby is created and ready for others to join, whether
## from an explicit host_steam_lobby() call or a quick_play() that found no
## open lobby and fell back to hosting one itself.
signal steam_lobby_ready(lobby_id: int)
## Fired when creating/joining a Steam lobby fails for any reason.
signal steam_lobby_failed(reason: String)

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 4
## Steam lobby data key used to find lobbies for this game specifically —
## AppID 480 ("Spacewar", see Steamworks autoload) is shared by every game
## using it for development, so without this filter Quick Play could match
## players into some other project's test lobby.
const GAME_LOBBY_TAG: String = "rts-test"

## The team colors players choose between in the lobby. Also the fallback
## assignment, by join order, for anything that bypasses the lobby entirely —
## notably the established run-main.tscn-straight-from-the-editor workflow,
## which never populates `players` at all.
##
## Kept here rather than in main.gd because both ends need it: the lobby to
## offer the choice, main.gd to color what gets spawned. Buildings recolor
## only the blue parts of their texture to this (see team_color.gdshader), so
## these want to stay reasonably saturated — a near-grey or near-white choice
## reads as unpainted stone rather than as a team.
const TEAM_COLORS: Array[Color] = [
	Color(0.25, 0.55, 1.0), Color(1.0, 0.35, 0.3), Color(0.35, 1.0, 0.45), Color(1.0, 0.85, 0.3)
]
const TEAM_COLOR_NAMES: Array[String] = ["Blue", "Red", "Green", "Yellow"]

## peer_id -> { "name": String, "color": Color, "faction_index": int, "ready": bool }
var players: Dictionary = {}

## 0 when not hosting/in a Steam lobby.
var _steam_lobby_id: int = 0
var _quick_play_searching: bool = false

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	Steam.lobby_created.connect(_on_steam_lobby_created)
	Steam.lobby_match_list.connect(_on_steam_lobby_match_list)
	Steam.lobby_joined.connect(_on_steam_lobby_joined)
	Steam.join_requested.connect(_on_steam_join_requested)

## --- Direct Connect (typed IP), unchanged ---

func host_game(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	players.clear()
	players[1] = {"name": "Host", "color": TEAM_COLORS[0], "faction_index": 0, "ready": false}
	return OK

func join_game(address: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	players.clear()
	return OK

## --- Steam (Quick Play matchmaking + hosting a Steam lobby) ---

func host_steam_lobby() -> Error:
	if not Steamworks.is_available:
		return ERR_UNAVAILABLE
	if _steam_lobby_id != 0:
		return ERR_ALREADY_IN_USE
	Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, MAX_PLAYERS)
	return OK

## Steam's lobby-list response usually arrives within a second or two, but
## isn't guaranteed to arrive at all (a dropped response leaves nothing to
## ever call _on_steam_lobby_match_list) — without a timeout, a lost response
## means quick_play() gets permanently stuck "searching" with no fallback to
## hosting, unlike the normal empty-list case which falls back immediately.
const QUICK_PLAY_TIMEOUT_SEC: float = 8.0
var _quick_play_timeout_timer: Timer = null

## Joins the first open lobby tagged for this game, or hosts one itself (so
## the next Quick Play searcher finds it) if none are currently open.
func quick_play() -> Error:
	if not Steamworks.is_available:
		return ERR_UNAVAILABLE
	if _steam_lobby_id != 0:
		return ERR_ALREADY_IN_USE
	_quick_play_searching = true
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	Steam.addRequestLobbyListStringFilter("game", GAME_LOBBY_TAG, Steam.LOBBY_COMPARISON_EQUAL)
	Steam.addRequestLobbyListStringFilter("status", "open", Steam.LOBBY_COMPARISON_EQUAL)
	Steam.requestLobbyList()
	_start_quick_play_timeout()
	return OK

func _start_quick_play_timeout() -> void:
	if _quick_play_timeout_timer == null:
		_quick_play_timeout_timer = Timer.new()
		_quick_play_timeout_timer.one_shot = true
		_quick_play_timeout_timer.timeout.connect(_on_quick_play_timeout)
		add_child(_quick_play_timeout_timer)
	_quick_play_timeout_timer.start(QUICK_PLAY_TIMEOUT_SEC)

func _stop_quick_play_timeout() -> void:
	if _quick_play_timeout_timer != null:
		_quick_play_timeout_timer.stop()

func _on_quick_play_timeout() -> void:
	if not _quick_play_searching:
		return
	_on_steam_lobby_match_list([])

func cancel_quick_play() -> void:
	_quick_play_searching = false
	_stop_quick_play_timeout()
	if _steam_lobby_id != 0:
		leave_game()

func join_steam_lobby(lobby_id: int) -> Error:
	if not Steamworks.is_available:
		return ERR_UNAVAILABLE
	Steam.joinLobby(lobby_id)
	return OK

## Opens Steam's native "invite a friend" overlay for the lobby currently
## being hosted; a no-op if not hosting one.
func invite_friend() -> void:
	if _steam_lobby_id != 0:
		Steam.activateGameOverlayInviteDialog(_steam_lobby_id)

## Host-only: hides the lobby from future Quick Play searches once the match
## actually starts (only the lobby owner is guaranteed permission to write
## lobby data, so this can't happen the moment a second player joins).
func mark_steam_lobby_in_progress() -> void:
	if is_host() and _steam_lobby_id != 0:
		Steam.setLobbyData(_steam_lobby_id, "status", "in_progress")

func _on_steam_lobby_created(connection: int, lobby_id: int) -> void:
	if connection != 1:
		_quick_play_searching = false
		_stop_quick_play_timeout()
		steam_lobby_failed.emit("Failed to create Steam lobby.")
		return
	_steam_lobby_id = lobby_id
	Steam.setLobbyJoinable(lobby_id, true)
	Steam.setLobbyData(lobby_id, "game", GAME_LOBBY_TAG)
	Steam.setLobbyData(lobby_id, "status", "open")

	var peer := SteamMultiplayerPeer.new()
	peer.create_host(0)
	multiplayer.multiplayer_peer = peer
	players.clear()
	players[my_peer_id()] = {"name": Steamworks.steam_username, "color": TEAM_COLORS[0], "faction_index": 0, "ready": false}
	_quick_play_searching = false
	steam_lobby_ready.emit(lobby_id)

func _on_steam_lobby_match_list(lobbies: Array) -> void:
	if not _quick_play_searching:
		return
	_stop_quick_play_timeout()
	if lobbies.is_empty():
		## Nobody else is waiting — become the host so the next searcher finds us.
		host_steam_lobby()
		return
	_quick_play_searching = false
	join_steam_lobby(lobbies[0])

func _on_steam_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		_quick_play_searching = false
		_stop_quick_play_timeout()
		steam_lobby_failed.emit("Could not join lobby (code %d)." % response)
		return
	_steam_lobby_id = lobby_id
	## If we're the owner, _on_steam_lobby_created already set up our peer.
	if Steam.getLobbyOwner(lobby_id) == Steamworks.steam_id:
		return
	var peer := SteamMultiplayerPeer.new()
	peer.create_client(Steam.getLobbyOwner(lobby_id), 0)
	multiplayer.multiplayer_peer = peer
	players.clear()

## Fired when this player accepts a Steam friend invite (via the overlay or
## friends list) to a lobby that's already open — join it the same way
## Quick Play would.
func _on_steam_join_requested(lobby_id: int, _friend_id: int) -> void:
	join_steam_lobby(lobby_id)

## --- Shared by both transports ---

func leave_game() -> void:
	if _steam_lobby_id != 0:
		Steam.leaveLobby(_steam_lobby_id)
		_steam_lobby_id = 0
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	players.clear()

func is_host() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.is_server()

func my_peer_id() -> int:
	return multiplayer.get_unique_id()

func _on_peer_connected(id: int) -> void:
	players[id] = {"name": "Player %d" % id, "color": Color.WHITE, "faction_index": 0, "ready": false}
	if is_host():
		## Only the host sees every player's pick, so it owns color assignment
		## outright — clients each guessing a default locally is exactly how two
		## players end up the same color. Assigned before the sync below so the
		## joiner receives its own color in that same snapshot, then broadcast
		## so the peers who were already here learn it too (they only ever get
		## this callback, never _sync_player_list).
		players[id]["color"] = _first_free_color()
		_sync_player_list.rpc_id(id, players)
		_rpc_color_changed.rpc(id, players[id]["color"])
	player_connected.emit(id)

func _on_peer_disconnected(id: int) -> void:
	var data: Dictionary = players.get(id, {})
	players.erase(id)
	player_disconnected.emit(id, data)

func _on_connected_ok() -> void:
	var display_name: String = Steamworks.steam_username if (Steamworks.is_available and _steam_lobby_id != 0) else "Me"
	players[my_peer_id()] = {"name": display_name, "color": Color.WHITE, "faction_index": 0, "ready": false}
	connected_to_server.emit()
	if display_name != "Me":
		_rpc_report_identity.rpc_id(1, display_name)

func _on_connected_fail() -> void:
	_quick_play_searching = false
	connection_failed.emit()

func _on_server_disconnected() -> void:
	players.clear()
	multiplayer.multiplayer_peer = null
	_steam_lobby_id = 0
	server_disconnected.emit()

## Lets the host learn a joining Steam player's real display name (their own
## peer id isn't known to the joiner ahead of time, so this can't be filled
## in any earlier than this) and re-broadcast it to everyone else — same
## host-relay pattern as faction selection below.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_report_identity(display_name: String) -> void:
	if not is_host():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not players.has(sender_id):
		return
	players[sender_id]["name"] = display_name
	player_updated.emit(sender_id)
	_rpc_identity_changed.rpc(sender_id, display_name)

@rpc("authority", "call_remote", "reliable")
func _rpc_identity_changed(peer_id: int, display_name: String) -> void:
	if players.has(peer_id):
		players[peer_id]["name"] = display_name
	player_updated.emit(peer_id)

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

## --- Team color selection (lobby only) ---
##
## Same host-relay shape as faction selection above, with one extra rule: two
## players must never share a color, or telling their buildings apart on the
## field stops working. Only the host sees everyone's current pick, so the
## host alone decides — a client can propose, never apply.

func set_my_color(index: int) -> void:
	if index < 0 or index >= TEAM_COLORS.size():
		return
	if is_host():
		_apply_color_change(my_peer_id(), TEAM_COLORS[index])
	else:
		_rpc_request_color.rpc_id(1, index)

## The palette index a peer is currently on, or -1 for a color that isn't one
## of the presets (nothing sets that today, but a saved custom color would).
func color_index_of(peer_id: int) -> int:
	return TEAM_COLORS.find(players.get(peer_id, {}).get("color", Color.WHITE))

## Colors no other player has claimed — what the lobby offers this peer.
func available_color_indices(peer_id: int) -> Array[int]:
	var out: Array[int] = []
	for i in TEAM_COLORS.size():
		if _color_holder(TEAM_COLORS[i], peer_id) == 0:
			out.append(i)
	return out

## The peer already using `color`, ignoring `except_peer_id`, or 0 for nobody.
func _color_holder(color: Color, except_peer_id: int) -> int:
	for id in players:
		if id != except_peer_id and players[id].get("color", Color.WHITE) == color:
			return id
	return 0

func _first_free_color() -> Color:
	for color in TEAM_COLORS:
		if _color_holder(color, 0) == 0:
			return color
	## Only reachable past MAX_PLAYERS, which the transports already cap.
	return TEAM_COLORS[0]

@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_color(index: int) -> void:
	if not is_host() or index < 0 or index >= TEAM_COLORS.size():
		return
	_apply_color_change(multiplayer.get_remote_sender_id(), TEAM_COLORS[index])

func _apply_color_change(peer_id: int, color: Color) -> void:
	if not players.has(peer_id):
		return
	if _color_holder(color, peer_id) != 0:
		## Taken. Re-broadcast the color they still have rather than staying
		## silent, so the asking player's own picker snaps back to reality
		## instead of sitting on a choice that never took.
		var unchanged: Color = players[peer_id].get("color", Color.WHITE)
		player_updated.emit(peer_id)
		_rpc_color_changed.rpc(peer_id, unchanged)
		return
	players[peer_id]["color"] = color
	player_updated.emit(peer_id)
	if is_host():
		_rpc_color_changed.rpc(peer_id, color)

@rpc("authority", "call_remote", "reliable")
func _rpc_color_changed(peer_id: int, color: Color) -> void:
	if players.has(peer_id):
		players[peer_id]["color"] = color
	player_updated.emit(peer_id)

## --- Ready-up (lobby only) ---
##
## Quick Play can match a player with a stranger who isn't at their keyboard
## yet, so the host's Start button now waits for every connected player to
## mark themselves ready instead of being available immediately — same
## request/relay pattern as faction selection above.

func set_my_ready(ready: bool) -> void:
	if is_host():
		_apply_ready_change(my_peer_id(), ready)
	else:
		_rpc_request_ready.rpc_id(1, ready)

func all_players_ready() -> bool:
	for id in players:
		if not players[id].get("ready", false):
			return false
	return not players.is_empty()

@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_ready(ready: bool) -> void:
	if is_host():
		_apply_ready_change(multiplayer.get_remote_sender_id(), ready)

func _apply_ready_change(peer_id: int, ready: bool) -> void:
	if not players.has(peer_id):
		return
	players[peer_id]["ready"] = ready
	player_updated.emit(peer_id)
	if is_host():
		_rpc_ready_changed.rpc(peer_id, ready)

@rpc("authority", "call_remote", "reliable")
func _rpc_ready_changed(peer_id: int, ready: bool) -> void:
	if players.has(peer_id):
		players[peer_id]["ready"] = ready
	player_updated.emit(peer_id)
