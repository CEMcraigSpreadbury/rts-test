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
## debug command (currently: "cmd add <resource> <amount>" grants yourself
## that resource without playing, e.g. "cmd add wood 10").

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
	_rpc_submit_chat.rpc_id(1, trimmed)

@rpc("any_peer", "call_local", "reliable")
func _rpc_submit_chat(text: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = main.my_peer_id()

	if text.begins_with("cmd "):
		_execute_debug_command(sender_id, text.substr(4))
	else:
		_rpc_display_chat.rpc("Player %d: %s" % [sender_id, text])

func _execute_debug_command(sender_id: int, args_string: String) -> void:
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
		"help":
			_rpc_display_chat.rpc_id(sender_id, "[debug] commands: cmd add <resource> <amount>")
		_:
			_rpc_display_chat.rpc_id(sender_id, "[debug] unknown command '%s'" % parts[0])

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
