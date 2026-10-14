class_name QuickDirector
extends Node
## Shared by the quick trailers: a table of shots over one scene staged in the
## warm-up. Each shot is a subject, a time of day and a camera move from one
## framing to another; a subclass fills `shots`, stages the scene in _stage(),
## runs its own timed events in _tick() and names its subjects in _subject().
## Preview: godot --path . <boot>.tscn -- --preview=<dir>
##   saves a 640x360 jpg every 0.5 film-s for a contact sheet.
## Film:    godot --path . --fixed-fps 30 --write-movie out.avi <boot>.tscn
##   (MJPEG .avi straight out, no PNG dump; size it with override.cfg.)
## Prints TRAILER_START_FRAME so the warm-up can be trimmed.

const WARMUP_FRAMES: int = 150
const FADE_IN: float = 0.6
const FADE_OUT: float = 1.0
const SPACING: float = 1.3

## Each: {"len", "subject", "night", "from", "to"}; a framing is
## [yaw, pitch, zoom, offset from the subject].
var shots: Array = []
var main: Main
var terrain: Node
var hero: int = 1
var enemy: int = 1
var t: float = 0.0
var end_at: float = 0.0
var running: bool = false
var fade: ColorRect
var focus: Vector3
var focus_shot: int = -1
var _night_now: float = -1.0
var _label_timer: float = 0.0
var _preview_dir: String = ""
var _next_preview: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--preview="):
			_preview_dir = arg.trim_prefix("--preview=")
			DirAccess.make_dir_recursive_absolute(_preview_dir)
	var layer := CanvasLayer.new()
	layer.layer = 200
	add_child(layer)
	fade = ColorRect.new()
	fade.color = Color.BLACK
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(fade)
	for shot in shots:
		end_at += shot.len

	for key in [&"clouds", &"wind", &"grass", &"water_reflections", &"depth_of_field"]:
		_force_setting(key, true)
	_force_setting(&"damage_numbers", false)
	AudioServer.set_bus_mute(AudioServer.get_bus_index(&"Music"), true)

	while not (get_tree().current_scene is Main) or SceneLoader.is_transitioning:
		await get_tree().process_frame
	main = get_tree().current_scene
	terrain = main.get_node_or_null("NavigationRegion3D/Terrain")
	main.ui_root.visible = false
	main.fog_of_war.reveal_all = true
	main.camera_rig.set_process(false)
	main.camera_rig.set_process_unhandled_input(false)
	main.camera_rig.max_zoom = 1000.0
	for ai in main.ai_players.values():
		ai.process_mode = Node.PROCESS_MODE_DISABLED
	hero = main.my_peer_id()
	for id in Network.ai_peer_ids():
		enemy = id
	_freeze_weather()
	await _stage()
	_update_camera(0.0)
	for i in WARMUP_FRAMES:
		_hide_overlays()
		await get_tree().process_frame
	_update_camera(0.0)
	print("TRAILER_START_FRAME=%d" % Engine.get_process_frames())
	running = true

## --- For subclasses ---

func _stage() -> void:
	pass

func _tick() -> void:
	pass

func _subject(_which: String) -> Vector3:
	return Vector3.ZERO

## Points `subject`'s shots along `dir` (keeping each shot's drift).
func aim(subject: String, dir: Vector3) -> void:
	var yaw: float = yaw_facing(dir)
	for shot in shots:
		if shot.subject == subject:
			var drift: float = shot.to[0] - shot.from[0]
			shot.from[0] = yaw
			shot.to[0] = yaw + drift

## When the shot showing `subject` first starts.
func shot_start(subject: String) -> float:
	var start: float = 0.0
	for shot in shots:
		if shot.subject == subject:
			return start
		start += shot.len
	return INF

## --- Running ---

func _force_setting(key: StringName, value: Variant) -> void:
	if Settings.values[key] == value:
		return
	Settings.values[key] = value
	Settings._apply(key, false)
	Settings.changed.emit(key)

func _process(delta: float) -> void:
	if not running:
		return
	t += delta
	_tick()
	_update_camera(delta)
	fade.color.a = maxf(1.0 - clampf(t / FADE_IN, 0.0, 1.0), clampf((t - (end_at - FADE_OUT)) / FADE_OUT, 0.0, 1.0))
	_hide_overlays()
	if _preview_dir != "" and t >= _next_preview:
		_next_preview += 0.5
		var image := get_viewport().get_texture().get_image()
		image.resize(640, 360)
		image.save_jpg("%s/t%05.1f.jpg" % [_preview_dir, t])
	if t >= end_at:
		print("TRAILER_END_FRAME=%d" % Engine.get_process_frames())
		get_tree().quit()

## --- Armies ---

## Ranks `columns` wide stacked back from `front` in roster order; roster
## entries are [scene name, count].
func spawn_block(peer: int, front: Vector3, facing: Vector3, roster: Array, columns: int) -> Array:
	var right := Vector3(facing.z, 0, -facing.x)
	var units: Array = []
	var i: int = 0
	for entry in roster:
		for n in entry[1]:
			var row: int = floori(float(i) / columns)
			var col: int = i % columns
			var pos: Vector3 = front - facing * row * SPACING + right * (col - (columns - 1) * 0.5) * SPACING
			units.append(spawn_unit(entry[0], peer, pos))
			i += 1
	return units

func spawn_unit(scene_name: String, peer: int, pos: Vector3) -> Unit:
	pos.y = height(pos)
	return main.unit_spawner.spawn({
		"scene_path": _scene_path(scene_name),
		"peer_id": peer,
		"tint": main.get_team_tint(peer),
		"position": pos,
	})

func _scene_path(scene_name: String) -> String:
	for folder in ["units", "units/beasts", "units/monsters", "units/dark_elves", "units/star_wanderers"]:
		var path: String = "res://scenes/%s/%s.tscn" % [folder, scene_name]
		if ResourceLoader.exists(path):
			return path
	push_error("quick director: no scene for %s" % scene_name)
	return "res://scenes/units/soldier_unit.tscn"

func order(peer: int, units: Array, pos: Vector3, facing: Vector3, columns: int, attack_move: bool) -> void:
	var paths: Array[NodePath] = []
	for u in units:
		if is_instance_valid(u):
			paths.append(u.get_path())
	main.issue_command_as(peer, paths, NodePath(), pos, attack_move, false,
			Formation.Type.BOX, (columns - 1) * SPACING, facing)

func centre_of(units: Array, fallback: Vector3) -> Vector3:
	var sum := Vector3.ZERO
	var count: int = 0
	for u in units:
		if is_instance_valid(u) and u.status_current_health > 0:
			sum += u.global_position
			count += 1
	return fallback if count == 0 else sum / count

## --- Camera ---

func _update_camera(delta: float) -> void:
	var start: float = 0.0
	for n in shots.size():
		var shot: Dictionary = shots[n]
		if t >= start + shot.len and n != shots.size() - 1:
			start += shot.len
			continue
		var centre := _subject(shot.subject)
		if n != focus_shot:
			if focus_shot < 0 or shots[focus_shot].subject != shot.subject:
				focus = centre
			focus_shot = n
		elif not shot.get("locked", false):
			focus = focus.lerp(centre, 1.0 - exp(-1.6 * delta))
		if shot.night != _night_now:
			_night_now = shot.night
			_set_night(shot.night)
		var k: float = clampf((t - start) / shot.len, 0.0, 1.0)
		k = k * k * (3.0 - 2.0 * k)
		var a: Array = shot.from
		var b: Array = shot.to
		var yaw_b: float = a[0] + wrapf(b[0] - a[0], -180.0, 180.0)
		_set_camera(focus + a[3].lerp(b[3], k), lerpf(a[0], yaw_b, k), lerpf(a[1], b[1], k), lerpf(a[2], b[2], k))
		return

func _set_camera(pos: Vector3, yaw_deg: float, pitch_deg: float, zoom: float) -> void:
	var rig := main.camera_rig
	pos.y = maxf(height(pos), -2.5)
	rig.global_position = pos
	rig.yaw.rotation_degrees.y = yaw_deg
	rig.pitch_degrees = pitch_deg
	rig.pitch.rotation_degrees.x = -pitch_deg
	rig.zoom_distance = zoom
	rig._zoom_target = zoom
	rig._update_zoom()

## The yaw that has the camera looking along `dir`.
static func yaw_facing(dir: Vector3) -> float:
	return rad_to_deg(atan2(-dir.x, -dir.z))

func height(pos: Vector3) -> float:
	if terrain == null:
		return 0.0
	return float(terrain.call("getHeightAtPosition", pos.x, pos.z, true))

## --- Weather and overlays ---

func _freeze_weather() -> void:
	var weather: Weather = main.weather
	if weather:
		if weather._fade_tween:
			weather._fade_tween.kill()
		weather.is_raining = false
		weather._time_to_change = 9999.0
		weather._particles.visible = false
		weather._particles.emitting = false
		weather._set_intensity(0.0)

func _set_night(amount: float) -> void:
	var day_night: DayNight = main.day_night
	if day_night == null:
		return
	if day_night._fade_tween:
		day_night._fade_tween.kill()
	day_night.is_night = amount > 0.5
	day_night._time_to_change = 9999.0
	day_night._set_night_amount(amount)

func _hide_overlays() -> void:
	_label_timer -= get_process_delta_time()
	if _label_timer <= 0.0:
		_label_timer = 0.25
		for label in main.find_children("*", "Label3D", true, false):
			label.visible = false
	for u in get_tree().get_nodes_in_group(&"units"):
		if u is Unit and u.health_bar:
			u.health_bar.visible = false
	for b in get_tree().get_nodes_in_group(&"buildings"):
		if b is ProductionBuilding and b.get(&"health_bar") is Node3D:
			b.health_bar.visible = false
	for banner in main.feedback._regiment_banners.values():
		banner.visible = false
	## The ring under the (idle) mouse cursor.
	if main.feedback.hover_ring:
		main.feedback.hover_ring.visible = false
