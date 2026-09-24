class_name ChatConsole
extends Node
## Chat log, debug console ("cmd ...") and minimap pings, split out of
## main.gd. Everything is relayed through the host so every peer sees the
## same lines in the same order.
##
## Created by Main._enter_tree() under a fixed name, so its RPCs resolve to
## the same node path on every peer.

var main: Main

@onready var _chat_log: RichTextLabel = main.get_node(^"UI/BottomBar/ChatLog")
@onready var _chat_input: LineEdit = main.get_node(^"UI/BottomBar/ChatInput")

const MAX_CHAT_LINES: int = 8
var chat_lines: Array[String] = []
## Bumped on every show/hide request so a stale timer (from an older message)
## doesn't hide the log after a newer one already reset the countdown.
var _chat_hide_token: int = 0
const CHAT_LOG_VISIBLE_DURATION: float = 3.0
const CHAT_LOG_FADE_DURATION: float = 0.5
var _chat_log_tween: Tween

## Called from Main._ready(), once Main's own @onready nodes exist.
func setup() -> void:
	_chat_input.text_submitted.connect(_on_chat_submitted)
	main.minimap.ping_requested.connect(_on_minimap_ping_requested)
	_chat_log.visible = false

func is_input_open() -> bool:
	return _chat_input.visible

## Host-side: shows `line` in one peer's chat log only — used for replies that
## concern just that player (debug command results, their own completions).
func send_line(peer_id: int, line: String) -> void:
	if Network.can_rpc_to(peer_id):
		_rpc_display_chat.rpc_id(peer_id, line)

## --- Chat / debug console ---
## Type a normal message to broadcast it to everyone, or "cmd ..." for a
## debug command:
##   "cmd add <resource> <amount>" grants yourself that resource, e.g. "cmd add wood 10".
##   "cmd spawn <unit|monster> [count]" spawns units you own at the mouse
##   cursor, e.g. "cmd spawn soldier 3"; "monster" picks a random one each.
##   Append "e" ("cmd spawn soldier 3e", "cmd spawn monster e") to spawn them
##   as neutral enemies instead. More than one spawns as a block facing the
##   camera, front rank on the cursor; an enemy block holds its ground so it
##   stays a block to practise flanking and charging against.
##   "cmd speed <multiplier>" runs the whole match faster or slower (single
##   player only), e.g. "cmd speed 4"; "cmd speed 1" puts it back.
##   "cmd perf" toggles the movement profiling overlay (host only, see PerfStats).
##   "cmd navgrid" toggles the native sim's movement grid overlay (host only, see ArmyBridge).
##   "cmd formations" toggles the native sim's formation overlay (host only, see ArmyBridge).
##   "cmd control" lets you select and command any side's units, to set up fights (single player).
##   "cmd rain [on|off]" starts or stops rain for everyone; with no argument it
##   toggles. It still clears up / returns on its own afterwards (see Weather).
## Commands only run when the host is a debug build or was launched with
## "-- --cheats"; otherwise "cmd ..." is just sent as ordinary chat.

## Checked on the host only, since that's where commands execute — a client's
## own build/flags can't unlock them.
func _cheats_enabled() -> bool:
	return OS.is_debug_build() or OS.get_cmdline_user_args().has("--cheats")

## Physics steps don't get more frequent with Engine.time_scale, only longer,
## so past this movement and collisions start to go wrong.
const MIN_GAME_SPEED: float = 0.25
const MAX_GAME_SPEED: float = 8.0

func open_chat_input() -> void:
	_chat_input.visible = true
	_chat_input.text = ""
	_chat_input.grab_focus()
	## Bump the token so any pending auto-hide timer skips its hide while
	## the log needs to stay up for typing.
	_chat_hide_token += 1
	if _chat_log_tween:
		_chat_log_tween.kill()
	_chat_log.visible = true
	_chat_log.modulate.a = 1.0

func close_chat_input() -> void:
	_chat_input.visible = false
	_chat_input.text = ""
	_chat_input.release_focus()
	_show_chat_log()

func _on_chat_submitted(text: String) -> void:
	close_chat_input()
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return
	## Where the mouse is pointing on the ground, captured here because only
	## the typing player's machine knows it — "cmd spawn" drops units there.
	var cursor_hit: Dictionary = main.raycast(main.get_viewport().get_mouse_position())
	var camera := main.get_viewport().get_camera_3d()
	var camera_pos: Vector3 = camera.global_position if camera else Vector3.ZERO
	_rpc_submit_chat.rpc_id(1, trimmed, cursor_hit.get("position", Vector3.ZERO), not cursor_hit.is_empty(), camera_pos)

@rpc("any_peer", "call_local", "reliable")
func _rpc_submit_chat(text: String, cursor_pos: Vector3, has_cursor: bool, camera_pos: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = main.my_peer_id()

	if text.begins_with("cmd ") and _cheats_enabled():
		_execute_debug_command(sender_id, text.substr(4), cursor_pos, has_cursor, camera_pos)
	else:
		_rpc_display_chat.rpc("Player %d: %s" % [sender_id, text])

func _execute_debug_command(sender_id: int, args_string: String, cursor_pos: Vector3, has_cursor: bool, camera_pos: Vector3) -> void:
	var parts: PackedStringArray = args_string.strip_edges().split(" ", false)
	if parts.is_empty():
		return

	match parts[0].to_lower():
		"add":
			if parts.size() < 3:
				_rpc_display_chat.rpc_id(sender_id, "[debug] usage: cmd add <resource> <amount>")
				return
			var resource_type: ResourceType = _find_resource_type_by_name(parts[1])
			if resource_type == null:
				_rpc_display_chat.rpc_id(sender_id, "[debug] unknown resource '%s'" % parts[1])
				return
			var amount: int = int(parts[2])
			ResourceStockpile.add(sender_id, resource_type, amount)
			_rpc_display_chat.rpc_id(sender_id, "[debug] +%d %s" % [amount, resource_type.display_name])
		"spawn":
			if parts.size() < 2:
				_rpc_display_chat.rpc_id(sender_id, "[debug] usage: cmd spawn <unit|monster> [count][e]")
				return
			## A trailing "e" ("3e", or a lone "e") spawns them as neutral enemies.
			var count_arg: String = " ".join(parts.slice(2)).to_lower().replace(" ", "")
			var as_enemy: bool = count_arg.ends_with("e")
			count_arg = count_arg.trim_suffix("e")
			var count: int = clampi(int(count_arg) if not count_arg.is_empty() else 1, 1, MAX_DEBUG_SPAWN)
			var wants_random_monster: bool = parts[1].to_lower() in ["monster", "monsters"]
			var scene_path: String = "" if wants_random_monster else _find_unit_scene_path(parts[1])
			if not wants_random_monster and scene_path.is_empty():
				_rpc_display_chat.rpc_id(sender_id, "[debug] unknown unit '%s' (known: monster, %s)" % [parts[1], ", ".join(_unit_scene_catalog().keys())])
				return
			var center: Vector3 = cursor_pos if has_cursor else _fallback_spawn_center(sender_id)
			var facing := _spawn_facing(center, camera_pos)
			var positions := _spawn_block_slots(center, facing, count)
			var spawned_names: Array[String] = []
			var block: Array[Unit] = []
			for i in count:
				var path: String = _random_monster_scene_path() if wants_random_monster else scene_path
				if path.is_empty():
					break
				var unit := _spawn_debug_unit(0 if as_enemy else sender_id, path, positions[i])
				if count > 1:
					unit.formation_facing = facing
					unit.rotation.y = atan2(facing.x, facing.z)
					unit.hold_position = as_enemy
					block.append(unit)
				spawned_names.append(unit.display_name)
			## Standing together as a block, as if they'd walked there as one
			## (see Unit.arrived_group) — so they answer an attack as a block.
			for unit in block:
				unit.arrived_group = block
			_rpc_display_chat.rpc_id(sender_id, "[debug] spawned %s%s" % [", ".join(spawned_names), " (enemy)" if as_enemy else ""])
		"speed":
			## Single player only: the host is the only machine simulating, so
			## in multiplayer this would just leave everyone else behind.
			if not Network.is_single_player():
				_rpc_display_chat.rpc_id(sender_id, "[debug] speed only works in single player")
				return
			var factor: float = clampf(float(parts[1]) if parts.size() > 1 else 1.0, MIN_GAME_SPEED, MAX_GAME_SPEED)
			Engine.time_scale = factor
			_rpc_display_chat.rpc_id(sender_id, "[debug] game speed x%s" % factor)
		"perf":
			## The counters are host-side (only the host simulates), so the
			## overlay can only ever show on the host's own screen.
			if sender_id != main.my_peer_id():
				_rpc_display_chat.rpc_id(sender_id, "[debug] perf only works on the host")
				return
			var existing := main.get_node_or_null(^"PerfStats")
			if existing:
				existing.queue_free()
			else:
				var overlay := PerfStats.new()
				overlay.name = "PerfStats"
				main.add_child(overlay)
			_rpc_display_chat.rpc_id(sender_id, "[debug] perf overlay %s" % ("off" if existing else "on"))
		"navgrid":
			## The grid lives on the host with the rest of the sim.
			if sender_id != main.my_peer_id() or main.army_bridge == null or ArmyBridge.current == null:
				_rpc_display_chat.rpc_id(sender_id, "[debug] navgrid only works on the host")
				return
			var shown: bool = main.army_bridge.toggle_overlay()
			_rpc_display_chat.rpc_id(sender_id, "[debug] navgrid overlay %s" % ("on" if shown else "off"))
		"control":
			## Single player only, like "cmd speed": commanding the other side
			## has no place in a real match.
			if not Network.is_single_player():
				_rpc_display_chat.rpc_id(sender_id, "[debug] control only works in single player")
				return
			main.debug_control_all = not main.debug_control_all
			_rpc_display_chat.rpc_id(sender_id, "[debug] control of every unit %s" % ("on" if main.debug_control_all else "off"))
		"formations":
			if sender_id != main.my_peer_id() or main.army_bridge == null or ArmyBridge.current == null:
				_rpc_display_chat.rpc_id(sender_id, "[debug] formations only works on the host")
				return
			var drawn: bool = main.army_bridge.toggle_formation_overlay()
			_rpc_display_chat.rpc_id(sender_id, "[debug] formation overlay %s" % ("on" if drawn else "off"))
		"rain":
			var arg: String = parts[1].to_lower() if parts.size() > 1 else ""
			if arg not in ["", "on", "off"]:
				_rpc_display_chat.rpc_id(sender_id, "[debug] usage: cmd rain [on|off]")
				return
			var raining: bool = not main.weather.is_raining if arg.is_empty() else arg == "on"
			main.weather.set_raining(raining)
			_rpc_display_chat.rpc_id(sender_id, "[debug] rain %s" % ("on" if raining else "off"))
		"day":
			var day_arg: String = parts[1].to_lower() if parts.size() > 1 else ""
			if day_arg not in ["", "on", "off"]:
				_rpc_display_chat.rpc_id(sender_id, "[debug] usage: cmd day [on|off]")
				return
			## "on" is daytime, so it turns night off.
			var night: bool = not main.day_night.is_night if day_arg.is_empty() else day_arg == "off"
			main.day_night.set_night(night)
			_rpc_display_chat.rpc_id(sender_id, "[debug] day %s" % ("off" if night else "on"))
		"help":
			_rpc_display_chat.rpc_id(sender_id, "[debug] commands: cmd add <resource> <amount>, cmd spawn <unit|monster> [count][e], cmd speed <multiplier>, cmd perf, cmd navgrid, cmd formations, cmd control, cmd rain [on|off], cmd day [on|off]")
		_:
			_rpc_display_chat.rpc_id(sender_id, "[debug] unknown command '%s'" % parts[0])

## --- "cmd spawn" ---

## Guards against a typo like "cmd spawn soldier 30000" stalling the host.
## High enough to stress-test mass movement (see "cmd perf").
const MAX_DEBUG_SPAWN: int = 500
const UNIT_SCENE_DIR: String = "res://scenes/units/"
const MONSTER_SCENE_DIR: String = "res://scenes/units/monsters/"

## Spawn name ("soldier", "black_dragon", ...) -> scene path, read off the unit
## scene files themselves so a newly added unit is spawnable with no changes
## here. The shared base scene unit.tscn is the Villager.
var _unit_scenes: Dictionary = {}
var _monster_scene_paths: Array[String] = []

func _unit_scene_catalog() -> Dictionary:
	if _unit_scenes.is_empty():
		for dir in [UNIT_SCENE_DIR, MONSTER_SCENE_DIR]:
			for path in _scene_paths_in(dir):
				var key: String = path.get_file().get_basename().trim_suffix("_unit")
				_unit_scenes["villager" if key == "unit" else key] = path
				if dir == MONSTER_SCENE_DIR:
					_monster_scene_paths.append(path)
	return _unit_scenes

## Exported builds list "x.tscn.remap" rather than "x.tscn"; load() takes the
## original name either way.
func _scene_paths_in(dir: String) -> Array[String]:
	var paths: Array[String] = []
	for file in DirAccess.get_files_at(dir):
		file = file.trim_suffix(".remap")
		if file.get_extension() == "tscn":
			paths.append(dir + file)
	return paths

## Case, spaces and underscores are ignored, so "blackdragon", "Black_Dragon"
## and "black_dragon" all match.
func _find_unit_scene_path(unit_name: String) -> String:
	var wanted: String = unit_name.to_lower().replace("_", "").replace(" ", "")
	var catalog := _unit_scene_catalog()
	for key in catalog:
		if key.replace("_", "") == wanted:
			return catalog[key]
	return ""

func _random_monster_scene_path() -> String:
	_unit_scene_catalog()
	return _monster_scene_paths.pick_random() if not _monster_scene_paths.is_empty() else ""

## The cursor wasn't over the ground (e.g. over the HUD), so fall back to a spot
## just in front of the sender's Town Center.
func _fallback_spawn_center(peer_id: int) -> Vector3:
	var town_center: Node3D = main.town_centers.get(peer_id)
	return town_center.global_position + Vector3(0.0, 0.0, 5.0) if town_center else Vector3.ZERO

## A spawned block faces the camera that typed the command, so its front is
## the side the player is looking at and its flanks and rear are easy to find.
func _spawn_facing(center: Vector3, camera_pos: Vector3) -> Vector3:
	var to_camera := camera_pos - center
	to_camera.y = 0.0
	return to_camera.normalized() if to_camera.length_squared() > 0.0001 else Vector3.BACK

## The same box a formation order would stand in, front rank on the cursor —
## laid out from the count alone, before any unit exists to fill it.
func _spawn_block_slots(center: Vector3, facing: Vector3, count: int) -> Array[Vector3]:
	var placeholders: Array[Unit] = []
	placeholders.resize(count)
	var right := Vector3(facing.z, 0.0, -facing.x)
	return Formation.new(placeholders).get_slot_positions(center, facing, right)

## Same path as a starting unit (see Main._spawn_player_base): population is
## reserved by hand since the unit never went through a production queue, and
## Unit._die releases it again. Peer 0 is neutral, owned the same way as
## objective guards (see Objective._setup_guard).
func _spawn_debug_unit(peer_id: int, scene_path: String, position: Vector3) -> Unit:
	## A big batch's spiral reaches into tree lines and buildings; units start
	## on the nearest walkable ground instead of walled in among the trunks.
	var nav_map: RID = main.get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(nav_map) > 0:
		position = NavigationServer3D.map_get_closest_point(nav_map, position)
	var unit: Unit = main.unit_spawner.spawn({
		"scene_path": scene_path,
		"peer_id": peer_id,
		"tint": main.get_team_tint(peer_id) if peer_id > 0 else Objective.NEUTRAL_TINT,
		"position": position,
	})
	if peer_id > 0:
		Population.reserve(peer_id, unit.population_cost, unit.population_pool)
	return unit

func _find_resource_type_by_name(resource_name: String) -> ResourceType:
	for resource_type in Main.DEBUG_RESOURCE_TYPES:
		if resource_type.display_name.to_lower() == resource_name.to_lower():
			return resource_type
	return null

@rpc("authority", "call_local", "reliable")
func _rpc_display_chat(line: String) -> void:
	chat_lines.append(line)
	if chat_lines.size() > MAX_CHAT_LINES:
		chat_lines.pop_front()
	_chat_log.text = "\n".join(chat_lines)
	_show_chat_log()

## Shows the chat log and (re)starts its auto-hide countdown; a stale timer
## from an earlier call is ignored via the token check.
func _show_chat_log() -> void:
	if _chat_log_tween:
		_chat_log_tween.kill()
	_chat_log.visible = true
	_chat_log.modulate.a = 1.0
	_chat_hide_token += 1
	var token := _chat_hide_token
	var timer := get_tree().create_timer(CHAT_LOG_VISIBLE_DURATION)
	timer.timeout.connect(func() -> void:
		if token == _chat_hide_token and not _chat_input.visible:
			_chat_log_tween = create_tween()
			_chat_log_tween.tween_property(_chat_log, "modulate:a", 0.0, CHAT_LOG_FADE_DURATION)
	)

## Right-click on the minimap; relayed through the host (same call-to-1-then-
## broadcast shape as chat) so every player sees the same ping at once,
## including the one who placed it.
func _on_minimap_ping_requested(world_pos: Vector3) -> void:
	_rpc_request_ping.rpc_id(1, world_pos)

@rpc("any_peer", "call_local", "reliable")
func _rpc_request_ping(world_pos: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = main.my_peer_id()
	_rpc_show_ping.rpc(world_pos, sender_id)

@rpc("authority", "call_local", "reliable")
func _rpc_show_ping(world_pos: Vector3, sender_id: int) -> void:
	main.minimap.show_ping(world_pos)
	main.feedback.play_ping_effect(world_pos)
	chat_lines.append("Player %d pinged the map" % sender_id)
	if chat_lines.size() > MAX_CHAT_LINES:
		chat_lines.pop_front()
	_chat_log.text = "\n".join(chat_lines)
	_show_chat_log()
