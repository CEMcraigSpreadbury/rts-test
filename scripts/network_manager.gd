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
## Fired when a player's own entry in `players` changes in place (ruler_index,
## color or ready) — lets the lobby refresh one row instead of the whole list.
signal player_updated(peer_id: int)
## Fired when the lobby's chosen map changes (host picked one, or a client
## learned the host's pick).
signal map_changed(index: int)
## Fired when the host changes the game mode or Favour target (or a client
## learns them).
signal match_settings_changed
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

## peer_id -> { "name": String, "color": Color, "ruler_index": int, "ready": bool }
## The colour doubles as the team — players sharing one are allies (see Teams).
## A scenario may add an explicit "team" int, which overrides that.
## ruler_index is a Ruler.list_all() index, or Ruler.RANDOM until the match starts.
## AI players are entries here too, with "ai": true and "difficulty" (see
## add_ai_player) — keyed by a made-up peer id that no real connection has.
var players: Dictionary = {}

enum AiDifficulty { EASY, NORMAL, HARD }
const AI_DIFFICULTY_NAMES: Array[String] = ["Easy", "Normal", "Hard"]
## AI peer ids are handed out from here upward. Real ENet/Steam peers get
## random ids in the millions-to-billions, so a collision is vanishingly rare
## — and _on_peer_connected moves an AI out of the way if one ever happens.
const FIRST_AI_PEER_ID: int = 2
## Index into the lobby's available_maps. Host-owned, like color assignment.
var map_index: int = 0

enum GameMode { CONQUEST, ANNIHILATION, REALM }
const GAME_MODE_NAMES: Array[String] = ["Conquest", "Annihilation", "Realm"]
## Host-owned, like map_index. Conquest: first to favour_target Favour wins
## (destroying every enemy base still wins too). Annihilation: bases only.
## Realm: Conquest's victory rules with the Realm economy (MatchRules.realm) —
## food, farms and upkeep instead of houses and a population cap.
var game_mode: GameMode = GameMode.CONQUEST
## 0 = the chosen map's default (see MapInfo.default_favour_target). Reset to
## 0 whenever the map changes, so a target picked for one map never silently
## carries over to another.
var favour_target: int = 0

## Campaign and tutorial missions only: 0 Easy, 1 Normal, 2 Hard. Shifts every
## enemy AI's level and scales enemy numbers and starting resources (see
## MatchRules.enemy_scale). Skirmish ignores it.
var campaign_difficulty: int = 1
## The ScenarioInfo id of the mission being played, so winning it can be
## written down (see CampaignProgress). Empty in a skirmish. In a lobby this is
## the host's choice, mirrored to everyone like the map is.
var current_scenario_id: StringName = &""
signal scenario_changed

## Host: pick a campaign mission for the lobby to play, or &"" for an ordinary
## skirmish on the chosen map.
func set_scenario(id: StringName) -> void:
	if multiplayer.multiplayer_peer != null and not is_host():
		return
	current_scenario_id = id
	scenario_changed.emit()
	if multiplayer.multiplayer_peer != null and is_host():
		_rpc_scenario_changed.rpc(id)
	trim_ai_to_capacity()

@rpc("authority", "call_remote", "reliable")
func _rpc_scenario_changed(id: StringName) -> void:
	current_scenario_id = id
	scenario_changed.emit()

## The mission the lobby is set to play, or null for a skirmish.
func current_scenario() -> ScenarioInfo:
	if String(current_scenario_id).is_empty():
		return null
	for info in ScenarioInfo.list_all():
		if info.id == current_scenario_id:
			return info
	return null

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
	players[1] = {"name": "Host", "color": TEAM_COLORS[0], "ruler_index": 0, "ready": false}
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
	players[my_peer_id()] = {"name": Steamworks.steam_username, "color": TEAM_COLORS[0], "ruler_index": 0, "ready": false}
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

## Single Player: an offline peer that is its own host with no one else
## connected. Called when the single player setup screen opens, so its AI
## rows can go straight into `players` through the same add_ai_player() etc.
## a lobby host uses; main.gd's _spawn_all_players() then spawns the local
## base plus one per AI.
func start_offline() -> void:
	leave_game()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players[1] = {"name": "You", "color": TEAM_COLORS[0], "ruler_index": 0, "ready": true}
	## Single player has no lobby to pick these in — always the defaults
	## rather than whatever a previous lobby left behind.
	game_mode = GameMode.CONQUEST
	favour_target = 0

func is_host() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.is_server()

## No other humans can ever be in this match — the only case where pausing
## the whole simulation is fair (see Main's pause menu).
func is_single_player() -> bool:
	return multiplayer.multiplayer_peer is OfflineMultiplayerPeer

## --- AI players ---
##
## Host-owned (or offline) entries in `players`. They never connect, load or
## receive RPCs — their brain runs on the host (see AiPlayer) and issues orders
## through the same *_as() entry points a human's RPCs end up in.

func is_ai(peer_id: int) -> bool:
	return players.get(peer_id, {}).get("ai", false)

## Whether `peer_id` is a real machine a targeted RPC can go to — not neutral
## (0), and not an AI, which has no connection at all. Every host-side
## "tell the owner" rpc_id() goes through this.
func can_rpc_to(peer_id: int) -> bool:
	return peer_id > 0 and not is_ai(peer_id)

## Every AI in `players`, oldest first.
func ai_peer_ids() -> Array[int]:
	var ids: Array[int] = []
	for id in players:
		if is_ai(id):
			ids.append(id)
	ids.sort()
	return ids

## How many players, humans and AIs together, the lobby's chosen map has spawn
## points for (MAX_PLAYERS for a map that doesn't say). The single player
## screen keeps its own map choice and works this out itself.
func player_capacity() -> int:
	## A mission seats exactly as many people as it has human slots; any it is
	## short of are filled by an allied AI when it starts.
	var scenario := current_scenario()
	if scenario != null:
		return clampi(scenario.human_slots, 1, MAX_PLAYERS)
	var maps: Array[MapInfo] = MapInfo.list_all()
	if maps.is_empty():
		return MAX_PLAYERS
	var map: MapInfo = maps[clampi(map_index, 0, maps.size() - 1)]
	return mini(map.max_players, MAX_PLAYERS) if map.max_players > 0 else MAX_PLAYERS

## Returns the new AI's peer id, or 0 if refused (not host, or no colour left).
func add_ai_player(difficulty: int = AiDifficulty.NORMAL) -> int:
	if multiplayer.multiplayer_peer != null and not is_host():
		return 0
	if players.size() >= MAX_PLAYERS:
		return 0
	var id := _free_ai_peer_id()
	players[id] = {"name": "", "color": _first_free_color(), "ruler_index": Ruler.RANDOM, "ready": true,
			"ai": true, "difficulty": clampi(difficulty, 0, AI_DIFFICULTY_NAMES.size() - 1)}
	_renumber_ai_players()
	_broadcast_ai_players()
	player_updated.emit(id)
	return id

func remove_ai_player(peer_id: int) -> void:
	if not is_ai(peer_id) or (multiplayer.multiplayer_peer != null and not is_host()):
		return
	var data: Dictionary = players[peer_id]
	players.erase(peer_id)
	_renumber_ai_players()
	_broadcast_ai_players()
	player_disconnected.emit(peer_id, data)

func set_ai_difficulty(peer_id: int, difficulty: int) -> void:
	if not is_ai(peer_id) or (multiplayer.multiplayer_peer != null and not is_host()):
		return
	players[peer_id]["difficulty"] = clampi(difficulty, 0, AI_DIFFICULTY_NAMES.size() - 1)
	_renumber_ai_players()
	_broadcast_ai_players()
	player_updated.emit(peer_id)

## Host: drops the newest AIs until everyone fits the map — after picking a
## smaller map, or when a human joins a lobby AIs had filled (humans come
## first).
func trim_ai_to_capacity() -> void:
	if multiplayer.multiplayer_peer != null and not is_host():
		return
	var ids := ai_peer_ids()
	while players.size() > player_capacity() and not ids.is_empty():
		remove_ai_player(ids.pop_back())

## Host -> clients: every AI slot, whole. One message for all of them rather
## than per-field updates, since adding or removing one renames the others
## ("AI 1", "AI 2", ...) — and a client can then never end up with a stale or
## half-built slot.
func _broadcast_ai_players() -> void:
	if multiplayer.multiplayer_peer == null or not is_host() or multiplayer.get_peers().is_empty():
		return
	var entries: Dictionary = {}
	for id in ai_peer_ids():
		entries[id] = players[id]
	_rpc_ai_players.rpc(entries)

@rpc("authority", "call_remote", "reliable")
func _rpc_ai_players(entries: Dictionary) -> void:
	for id in ai_peer_ids():
		if not entries.has(id):
			var data: Dictionary = players[id]
			players.erase(id)
			player_disconnected.emit(id, data)
	for id in entries:
		players[id] = entries[id]
		player_updated.emit(id)

## Host-side colour change for an AI (a human picks their own through
## set_my_color). Same no-duplicates rule.
func set_ai_color(peer_id: int, index: int) -> void:
	if not is_ai(peer_id) or index < 0 or index >= TEAM_COLORS.size():
		return
	if multiplayer.multiplayer_peer != null and not is_host():
		return
	_apply_color_change(peer_id, TEAM_COLORS[index])

func _free_ai_peer_id() -> int:
	var taken: Array = players.keys()
	if multiplayer.multiplayer_peer != null:
		taken.append_array(multiplayer.get_peers())
	var id := FIRST_AI_PEER_ID
	while taken.has(id):
		id += 1
	return id

## "AI 1 (Hard)", "AI 2 (Easy)", ... numbered by age, so removing one never
## leaves a gap.
func _renumber_ai_players() -> void:
	var ids := ai_peer_ids()
	for i in ids.size():
		var entry: Dictionary = players[ids[i]]
		entry["name"] = "AI %d (%s)" % [i + 1, AI_DIFFICULTY_NAMES[entry.get("difficulty", AiDifficulty.NORMAL)]]

func my_peer_id() -> int:
	return multiplayer.get_unique_id()

func _on_peer_connected(id: int) -> void:
	## A real peer landed on an id an AI already holds — move the AI aside.
	if is_ai(id):
		var ai_data: Dictionary = players[id]
		players.erase(id)
		players[_free_ai_peer_id()] = ai_data
	players[id] = {"name": "Player %d" % id, "color": Color.WHITE, "ruler_index": 0, "ready": false}
	if is_host():
		## Humans come first: a lobby AIs had filled drops its newest AI to
		## make room — before the colour pick below, so the one it frees is up
		## for grabs.
		trim_ai_to_capacity()
		## Only the host sees every player's pick, so it owns color assignment
		## outright — clients each guessing a default locally is exactly how two
		## players end up the same color. Assigned before the sync below so the
		## joiner receives its own color in that same snapshot, then broadcast
		## so the peers who were already here learn it too (they only ever get
		## this callback, never _sync_player_list).
		players[id]["color"] = _first_free_color()
		_sync_player_list.rpc_id(id, players)
		_rpc_color_changed.rpc(id, players[id]["color"])
		_rpc_map_changed.rpc_id(id, map_index)
		_rpc_match_settings_changed.rpc_id(id, game_mode, favour_target)
	player_connected.emit(id)

func _on_peer_disconnected(id: int) -> void:
	var data: Dictionary = players.get(id, {})
	players.erase(id)
	player_disconnected.emit(id, data)

func _on_connected_ok() -> void:
	var display_name: String = Steamworks.steam_username if (Steamworks.is_available and _steam_lobby_id != 0) else "Me"
	players[my_peer_id()] = {"name": display_name, "color": Color.WHITE, "ruler_index": 0, "ready": false}
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
## host-relay pattern as Ruler selection below.
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

## --- Ruler selection (lobby / single player setup) ---

## Godot's high-level multiplayer here is star-topology (every RPC actually
## routes through the host — a client can't reach other clients directly,
## the same constraint main.gd's unit-animation relay works around). So a
## client proposes its choice to the host, which applies it and re-broadcasts;
## the host applies its own choice directly. `index` is a Ruler.list_all()
## index or Ruler.RANDOM.
func set_my_ruler(index: int) -> void:
	if is_host():
		_apply_ruler_change(my_peer_id(), index)
	else:
		_rpc_request_ruler.rpc_id(1, index)

## Host-side Ruler change for an AI (a human picks their own above).
func set_ai_ruler(peer_id: int, index: int) -> void:
	if not is_ai(peer_id) or (multiplayer.multiplayer_peer != null and not is_host()):
		return
	_apply_ruler_change(peer_id, index)

## Host, just before the match loads: every "Random" pick becomes a real
## Ruler, broadcast like any other change so every peer loads the same trees.
func resolve_random_rulers() -> void:
	if multiplayer.multiplayer_peer != null and not is_host():
		return
	var count := Ruler.list_all().size()
	if count == 0:
		return
	for id in players:
		if players[id].get("ruler_index", 0) == Ruler.RANDOM:
			_apply_ruler_change(id, randi() % count)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_ruler(index: int) -> void:
	if is_host():
		_apply_ruler_change(multiplayer.get_remote_sender_id(), index)

func _apply_ruler_change(peer_id: int, index: int) -> void:
	if not players.has(peer_id):
		return
	index = clampi(index, Ruler.RANDOM, Ruler.list_all().size() - 1)
	players[peer_id]["ruler_index"] = index
	player_updated.emit(peer_id)
	if is_host():
		_rpc_ruler_changed.rpc(peer_id, index)

@rpc("authority", "call_remote", "reliable")
func _rpc_ruler_changed(peer_id: int, index: int) -> void:
	if players.has(peer_id):
		players[peer_id]["ruler_index"] = index
	player_updated.emit(peer_id)

## --- Team color selection (lobby only) ---
##
## Same host-relay shape as Ruler selection above. Sharing a colour is allowed
## and is how team games are set up: the colour IS the team (see Teams), so two
## players on Blue play as allies and everyone on a different colour is the old
## free-for-all. Only the host sees everyone's current pick, so the host alone
## decides — a client can propose, never apply.

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

## Every colour is offered to everyone — picking one somebody already has is
## how you join their team. Kept as a function (rather than dropped) because
## both pickers ask it, and a scenario may yet want to narrow the choice.
func available_color_indices(_peer_id: int) -> Array[int]:
	var out: Array[int] = []
	for i in TEAM_COLORS.size():
		out.append(i)
	return out

## Whether at least two teams are represented — false when everyone has picked
## the same colour, which would be a match with nobody to fight.
func has_opposing_teams() -> bool:
	return Teams.teams_of(players.keys()).size() > 1

## What both Start buttons check. A lone player is still allowed to start (the
## established "walk around a map on my own" case); two or more have to be on
## at least two teams.
func can_start_match() -> bool:
	return players.size() <= 1 or has_opposing_teams()

## The peer already using `color`, ignoring `except_peer_id`, or 0 for nobody.
## No longer a veto (see the section note) — only _first_free_color() still
## uses it, to keep each added AI on its own team by default.
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
	players[peer_id]["color"] = color
	player_updated.emit(peer_id)
	if is_host():
		_rpc_color_changed.rpc(peer_id, color)

@rpc("authority", "call_remote", "reliable")
func _rpc_color_changed(peer_id: int, color: Color) -> void:
	if players.has(peer_id):
		players[peer_id]["color"] = color
	player_updated.emit(peer_id)

## --- Map selection (lobby only) ---
##
## Only the host picks; clients just mirror it. Also callable before hosting
## or joining at all, so the lobby's picker is usable from the start.

func set_map(index: int) -> void:
	if multiplayer.multiplayer_peer != null and not is_host():
		return
	map_index = index
	map_changed.emit(index)
	if is_host():
		_rpc_map_changed.rpc(index)
	set_match_settings(game_mode, 0)

@rpc("authority", "call_remote", "reliable")
func _rpc_map_changed(index: int) -> void:
	map_index = index
	map_changed.emit(index)

## --- Game mode + Favour target (lobby only) ---
##
## Same host-owned, clients-mirror shape as map selection above.

## Whether `mode` (a GameMode value) is won by racing to a Favour target.
static func scores_favour(mode: int) -> bool:
	return mode == GameMode.CONQUEST or mode == GameMode.REALM

## `mode` is a GameMode value — typed int so other scripts can pass one (an
## autoload's enum isn't usable as a type outside it).
func set_match_settings(mode: int, target: int) -> void:
	if multiplayer.multiplayer_peer != null and not is_host():
		return
	game_mode = mode as GameMode
	favour_target = maxi(target, 0)
	match_settings_changed.emit()
	if is_host():
		_rpc_match_settings_changed.rpc(game_mode, favour_target)

@rpc("authority", "call_remote", "reliable")
func _rpc_match_settings_changed(mode: int, target: int) -> void:
	game_mode = mode as GameMode
	favour_target = target
	match_settings_changed.emit()

## --- Ready-up (lobby only) ---
##
## Quick Play can match a player with a stranger who isn't at their keyboard
## yet, so the host's Start button now waits for every connected player to
## mark themselves ready instead of being available immediately — same
## request/relay pattern as Ruler selection above.

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
