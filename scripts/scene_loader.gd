extends Node
## Autoload that owns every scene change: fades to black, shows a loading
## screen while the next scene loads on a background thread, then fades the new
## scene in. Built entirely in code (like main.gd's small overlays) so there is
## no extra .tscn to keep in sync.
##
## Two entry points:
## - change_scene(): local only, e.g. leaving a match back to the lobby.
## - start_match(): host only. Every peer loads in the background and reports
##   in; the host waits for all of them before telling everyone to swap in.
##   Main._ready() on the host starts replicating spawns straight away, so a
##   client still mid-load would have no Main node to receive them — the old
##   instant change_scene_to_file() only got away with that because both ends
##   happened to load at roughly the same speed.

const FADE_DURATION: float = 0.35
## Keeps the loading screen from flashing up for a single frame when the scene
## is already cached (e.g. the second time back to the lobby).
const MIN_LOADING_TIME: float = 0.4
const GAME_FONT: Font = preload("res://assets/fonts/MedievalSharp-Book.ttf")
const BAR_FRAME_TEXTURE: Texture2D = preload("res://assets/ui/HUD/scaled/bar_frame.png")
const BAR_FILL_TEXTURE: Texture2D = preload("res://assets/ui/HUD/scaled/bar_fill_green.png")

var is_transitioning: bool = false
## Bumped by every new load, so an in-flight one can tell it's been superseded.
var _generation: int = 0

var _layer: CanvasLayer
var _fade: ColorRect
var _loading_root: Control
var _progress_bar: TextureProgressBar
var _status_label: Label

## --- Synced (multiplayer) load state ---
## Scene instantiated off-tree and waiting for the host's go-ahead.
var _pending_scene: Node = null
var _synced_path: String = ""
## Host only: peers that have finished loading _synced_path.
var _loaded_peers: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_overlay()
	Network.player_disconnected.connect(_on_player_disconnected)
	Network.server_disconnected.connect(_on_server_disconnected)

func change_scene(path: String) -> void:
	if is_transitioning:
		return
	is_transitioning = true
	_generation += 1
	await _fade_out()
	var scene: Node = await _load_and_instantiate(path, _generation)
	await _swap_and_fade_in(scene)

func start_match(path: String) -> void:
	if not Network.is_host() or is_transitioning:
		return
	_loaded_peers.clear()
	_rpc_begin_synced_load.rpc(path)

@rpc("authority", "call_local", "reliable")
func _rpc_begin_synced_load(path: String) -> void:
	if is_transitioning:
		return
	is_transitioning = true
	_generation += 1
	var generation: int = _generation
	_synced_path = path
	await _fade_out()
	var scene: Node = await _load_and_instantiate(path, generation)
	if generation != _generation:
		## Aborted mid-load (lost the host); _on_server_disconnected already
		## started the trip back to the lobby.
		scene.free()
		return
	_pending_scene = scene
	_status_label.text = "Waiting for players..."
	if Network.is_host():
		_mark_peer_loaded(1)
	else:
		_rpc_report_loaded.rpc_id(1, path)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_report_loaded(path: String) -> void:
	if Network.is_host() and path == _synced_path:
		_mark_peer_loaded(multiplayer.get_remote_sender_id())

func _mark_peer_loaded(peer_id: int) -> void:
	_loaded_peers[peer_id] = true
	_try_commit_synced_load()

func _try_commit_synced_load() -> void:
	if not Network.is_host() or _synced_path.is_empty():
		return
	if not _loaded_peers.has(1):
		return
	for peer_id in multiplayer.get_peers():
		if not _loaded_peers.has(peer_id):
			return
	_synced_path = ""
	_rpc_commit_synced_load.rpc()

## Swaps synchronously rather than through change_scene_to_node(), which defers
## to the end of the frame: the host's spawn packets can arrive in the same
## network poll as this RPC, and they need Main to already be in the tree.
@rpc("authority", "call_local", "reliable")
func _rpc_commit_synced_load() -> void:
	if _pending_scene == null:
		return
	var scene := _pending_scene
	_pending_scene = null
	_synced_path = ""
	_swap_and_fade_in(scene)

func _on_player_disconnected(peer_id: int, _data: Dictionary) -> void:
	_loaded_peers.erase(peer_id)
	_try_commit_synced_load()

func _on_server_disconnected() -> void:
	if _synced_path.is_empty() and _pending_scene == null:
		return
	if _pending_scene != null:
		_pending_scene.free()
		_pending_scene = null
	var lobby_path: String = ProjectSettings.get_setting("application/run/main_scene")
	_synced_path = ""
	_loaded_peers.clear()
	is_transitioning = false
	change_scene(lobby_path)

## --- Shared steps ---

## `generation` lets a superseded load (see _on_server_disconnected) finish
## quietly without fighting the newer one over the progress bar.
func _load_and_instantiate(path: String, generation: int) -> Node:
	_progress_bar.value = 0.0
	_status_label.text = "Loading..."
	_loading_root.visible = true
	var started_ms: int = Time.get_ticks_msec()
	ResourceLoader.load_threaded_request(path)
	var progress: Array = []
	while true:
		var status := ResourceLoader.load_threaded_get_status(path, progress)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			break
		if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			push_error("SceneLoader: failed to load %s" % path)
			break
		if generation == _generation and not progress.is_empty():
			_progress_bar.value = progress[0]
		await get_tree().process_frame
	if generation != _generation:
		ResourceLoader.load_threaded_get(path)
		return Node.new()
	_progress_bar.value = 1.0
	var remaining: float = MIN_LOADING_TIME - (Time.get_ticks_msec() - started_ms) / 1000.0
	if remaining > 0.0:
		await get_tree().create_timer(remaining, true, false, true).timeout
	var packed := ResourceLoader.load_threaded_get(path) as PackedScene
	return packed.instantiate() if packed else Node.new()

func _swap_and_fade_in(scene: Node) -> void:
	var tree := get_tree()
	var old_scene := tree.current_scene
	if old_scene:
		tree.root.remove_child(old_scene)
		old_scene.queue_free()
	## current_scene has to be in place before any child's _ready() runs
	## (objective.gd reaches Main through it), and tree_entered fires before
	## those — setting it after add_child() would be too late.
	scene.tree_entered.connect(func(): tree.current_scene = scene, CONNECT_ONE_SHOT)
	tree.root.add_child(scene)
	tree.paused = false
	_loading_root.visible = false
	await _fade_in()
	is_transitioning = false

func _fade_out() -> void:
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, FADE_DURATION)
	await tween.finished

func _fade_in() -> void:
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 0.0, FADE_DURATION)
	await tween.finished
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE

## --- Overlay ---

func _build_overlay() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 128
	add_child(_layer)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_fade)

	_loading_root = VBoxContainer.new()
	_loading_root.visible = false
	_loading_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_root.set_anchors_preset(Control.PRESET_CENTER)
	_loading_root.custom_minimum_size = Vector2(360, 0)
	_loading_root.position = Vector2(-180, -30)
	_loading_root.add_theme_constant_override("separation", 12)
	_layer.add_child(_loading_root)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_override("font", GAME_FONT)
	_status_label.add_theme_font_size_override("font_size", 28)
	_loading_root.add_child(_status_label)

	_progress_bar = TextureProgressBar.new()
	_progress_bar.custom_minimum_size = Vector2(0, 20)
	_progress_bar.max_value = 1.0
	_progress_bar.step = 0.0
	_progress_bar.texture_under = BAR_FRAME_TEXTURE
	_progress_bar.texture_progress = BAR_FILL_TEXTURE
	_progress_bar.fill_mode = TextureProgressBar.FILL_LEFT_TO_RIGHT
	_progress_bar.nine_patch_stretch = true
	_progress_bar.stretch_margin_left = 10
	_progress_bar.stretch_margin_right = 10
	_progress_bar.stretch_margin_top = 6
	_progress_bar.stretch_margin_bottom = 6
	_loading_root.add_child(_progress_bar)
