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
	_rpc_display_chat.rpc_id(peer_id, line)

## --- Chat / debug console ---
## Type a normal message to broadcast it to everyone, or "cmd ..." for a
## debug command:
##   "cmd add <resource> <amount>" grants yourself that resource, e.g. "cmd add wood 10".
##   "cmd spawn <unit|monster> [count]" spawns units you own at the mouse
##   cursor, e.g. "cmd spawn soldier 3"; "monster" picks a random one each.

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
	_rpc_submit_chat.rpc_id(1, trimmed, cursor_hit.get("position", Vector3.ZERO), not cursor_hit.is_empty())

@rpc("any_peer", "call_local", "reliable")
func _rpc_submit_chat(text: String, cursor_pos: Vector3, has_cursor: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = main.my_peer_id()

	if text.begins_with("cmd "):
		_execute_debug_command(sender_id, text.substr(4), cursor_pos, has_cursor)
	else:
		_rpc_display_chat.rpc("Player %d: %s" % [sender_id, text])

func _execute_debug_command(sender_id: int, args_string: String, cursor_pos: Vector3, has_cursor: bool) -> void:
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
				_rpc_display_chat.rpc_id(sender_id, "[debug] usage: cmd spawn <unit|monster> [count]")
				return
			var count: int = clampi(int(parts[2]) if parts.size() >= 3 else 1, 1, MAX_DEBUG_SPAWN)
			var wants_random_monster: bool = parts[1].to_lower() in ["monster", "monsters"]
			var scene_path: String = "" if wants_random_monster else _find_unit_scene_path(parts[1])
			if not wants_random_monster and scene_path.is_empty():
				_rpc_display_chat.rpc_id(sender_id, "[debug] unknown unit '%s' (known: monster, %s)" % [parts[1], ", ".join(_unit_scene_catalog().keys())])
				return
			var center: Vector3 = cursor_pos if has_cursor else _fallback_spawn_center(sender_id)
			var spawned_names: Array[String] = []
			for i in count:
				var path: String = _random_monster_scene_path() if wants_random_monster else scene_path
				if path.is_empty():
					break
				spawned_names.append(_spawn_debug_unit(sender_id, path, center + _spawn_offset(i)).display_name)
			_rpc_display_chat.rpc_id(sender_id, "[debug] spawned %s" % ", ".join(spawned_names))
		"help":
			_rpc_display_chat.rpc_id(sender_id, "[debug] commands: cmd add <resource> <amount>, cmd spawn <unit|monster> [count]")
		_:
			_rpc_display_chat.rpc_id(sender_id, "[debug] unknown command '%s'" % parts[0])

## --- "cmd spawn" ---

## Guards against a typo like "cmd spawn soldier 3000" stalling the host.
const MAX_DEBUG_SPAWN: int = 50
const UNIT_SCENE_DIR: String = "res://scenes/units/"
const MONSTER_SCENE_DIR: String = "res://scenes/units/monsters/"
## Spacing between debug-spawned units: comfortably wider than two avoidance
## radii, so a batch doesn't spawn overlapping (see the spawn jitter note in
## Main._on_building_item_completed for what overlapping spawns do).
const DEBUG_SPAWN_SPACING: float = 1.1

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

## Sunflower spiral: the first unit lands exactly on the cursor and each next
## one a little further out, packing a batch of any size into a tidy blob.
func _spawn_offset(index: int) -> Vector3:
	var radius: float = DEBUG_SPAWN_SPACING * sqrt(float(index))
	var angle: float = float(index) * 2.39996
	return Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)

## Same path as a starting unit (see Main._spawn_player_base): population is
## reserved by hand since the unit never went through a production queue, and
## Unit._die releases it again.
func _spawn_debug_unit(peer_id: int, scene_path: String, position: Vector3) -> Unit:
	var unit: Unit = main.unit_spawner.spawn({
		"scene_path": scene_path,
		"peer_id": peer_id,
		"tint": main.get_team_tint(peer_id),
		"position": position,
	})
	Population.reserve(peer_id, unit.population_cost)
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
