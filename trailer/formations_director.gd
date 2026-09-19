extends Node
## Formations showcase on Aethermoor Creek for Movie Maker capture: two mixed
## blocks meet in the creek. Two long shots, no quick cuts.
## Run: godot --path . --write-movie out.png --fixed-fps 30 res://trailer/formations_boot.tscn
## Movie Maker ignores --resolution; size it with an override.cfg setting
## display/window/size/window_width_override=1920 and window_height_override=1080.
## Prints TRAILER_START_FRAME / TRAILER_END_FRAME so the warm-up can be trimmed.

const WARMUP_FRAMES: int = 120
const END: float = 15.0
const CUT: float = 7.0
const FADE: float = 0.3

## The creek runs roughly north-south through x -30..-24 at this z.
const LANE_Z: float = 25.0
const BLUE_FRONT: Vector3 = Vector3(-37, 0, LANE_Z)
const RED_FRONT: Vector3 = Vector3(-5, 0, LANE_Z)
## Both blocks attack-move at the same patch of grass east of the creek: blue
## wades across to it, red sets off once blue is mid-crossing.
const MEET: Vector3 = Vector3(-16, 0, LANE_Z)
const RED_GO_AT: float = 2.5

const COLUMNS: int = 8
const SPACING: float = 1.3

## Each shot: [start, end, from, to, follow_all] where from/to are
## [offset, yaw, pitch, zoom]. The offset is from the smoothed centre of the
## blue block, or of every fighter when follow_all is set.
var shots: Array = [
	[0.0, CUT, [Vector3(1.5, 0, 0.5), -48.0, 30.0, 16.5], [Vector3(2.5, 0, 0.0), -32.0, 28.0, 14.0], false],
	[CUT, END, [Vector3(0, 0, -1.0), 128.0, 34.0, 17.0], [Vector3(0, 0, -0.5), 158.0, 29.0, 13.0], true],
]
var focus: Vector3 = BLUE_FRONT
var focus_shot: int = -1

var main: Main
var hero: int = 1
var enemy: int = 1
var t: float = -0.3
var running: bool = false
var red_sent: bool = false
var fade: ColorRect
var blue: Array[Unit] = []
var red: Array[Unit] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var layer := CanvasLayer.new()
	layer.layer = 200
	add_child(layer)
	fade = ColorRect.new()
	fade.color = Color.BLACK
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(fade)

	## Showcase look regardless of the local options, without saving them.
	for key in [&"clouds", &"wind", &"grass", &"water_reflections", &"depth_of_field"]:
		_force_setting(key, true)
	_force_setting(&"damage_numbers", false)

	while not (get_tree().current_scene is Main) or SceneLoader.is_transitioning:
		await get_tree().process_frame
	main = get_tree().current_scene
	main.ui_root.visible = false
	main.fog_of_war.reveal_all = true
	main.fog_of_war.wind_strength_range = Vector2(5.0, 6.5)
	main.fog_of_war._wind_strength = 5.5
	main.fog_of_war._wind_target_strength = 5.5
	main.camera_rig.set_process(false)
	main.camera_rig.set_process_unhandled_input(false)
	for label in main.find_children("*", "Label3D", true, false):
		label.visible = false
	for ai in main.ai_players.values():
		ai.process_mode = Node.PROCESS_MODE_DISABLED
	hero = main.my_peer_id()
	for id in Network.ai_peer_ids():
		enemy = id
	_clear_nearby_guards()

	blue = _spawn_block(hero, BLUE_FRONT, Vector3.RIGHT, [["soldier_unit", 16], ["archer_unit", 8]])
	red = _spawn_block(enemy, RED_FRONT, Vector3.LEFT, [["soldier_unit", 16], ["archer_unit", 8]])
	await get_tree().process_frame
	_order(hero, blue, NodePath(), BLUE_FRONT, false, Vector3.RIGHT)
	_order(enemy, red, NodePath(), RED_FRONT, false, Vector3.LEFT)

	_update_camera(0.0)
	for i in WARMUP_FRAMES:
		await get_tree().process_frame
	print("TRAILER_START_FRAME=%d" % Engine.get_process_frames())
	running = true
	_order(hero, blue, NodePath(), MEET, true, Vector3.RIGHT)

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
	_update_camera(delta)
	_update_overlay()
	if not red_sent and t >= RED_GO_AT:
		red_sent = true
		_order(enemy, red, NodePath(), MEET, true, Vector3.LEFT)
	if t >= END:
		print("TRAILER_END_FRAME=%d" % Engine.get_process_frames())
		get_tree().quit()

func _update_camera(delta: float) -> void:
	for n in shots.size():
		var shot: Array = shots[n]
		if t < shot[1] or n == shots.size() - 1:
			var centre := _centre(blue + red if shot[4] else blue)
			if n != focus_shot:
				focus_shot = n
				focus = centre
			else:
				focus = focus.lerp(centre, 1.0 - exp(-1.5 * delta))
			var k: float = clampf(inverse_lerp(shot[0], shot[1], t), 0.0, 1.0)
			k = lerpf(k, k * k * (3.0 - 2.0 * k), 0.5)
			var a: Array = shot[2]
			var b: Array = shot[3]
			_set_camera(focus + a[0].lerp(b[0], k), lerpf(a[1], b[1], k), lerpf(a[2], b[2], k), lerpf(a[3], b[3], k))
			return

## Fade in, a soft dip through black at the one cut, fade out.
func _update_overlay() -> void:
	var alpha: float = 1.0 - clampf(t / 0.6, 0.0, 1.0)
	alpha = maxf(alpha, 1.0 - clampf(absf(t - CUT) / FADE, 0.0, 1.0))
	alpha = maxf(alpha, clampf((t - (END - 0.7)) / 0.6, 0.0, 1.0))
	fade.color.a = alpha

func _set_camera(pos: Vector3, yaw_deg: float, pitch_deg: float, zoom: float) -> void:
	var rig := main.camera_rig
	var terrain := GroundHeight.terrain(get_tree())
	if terrain:
		pos.y = maxf(terrain.getHeightAtPosition(pos.x, pos.z, true), -2.5)
	rig.global_position = pos
	rig.yaw.rotation_degrees.y = yaw_deg
	rig.pitch_degrees = pitch_deg
	rig.pitch.rotation_degrees.x = -pitch_deg
	rig.zoom_distance = zoom
	rig._zoom_target = zoom
	rig._update_zoom()

## Ranks of COLUMNS stacked back from `front`, in roster order (melee first).
func _spawn_block(peer: int, front: Vector3, facing: Vector3, roster: Array) -> Array[Unit]:
	var right := Vector3(facing.z, 0, -facing.x)
	var units: Array[Unit] = []
	var i: int = 0
	for entry in roster:
		for n in entry[1]:
			var row: int = floori(float(i) / COLUMNS)
			var col: int = i % COLUMNS
			var pos: Vector3 = front - facing * row * SPACING + right * (col - (COLUMNS - 1) * 0.5) * SPACING
			units.append(main.unit_spawner.spawn({
				"scene_path": "res://scenes/units/%s.tscn" % entry[0],
				"peer_id": peer,
				"tint": main.get_team_tint(peer),
				"position": pos,
			}))
			i += 1
	return units

func _order(peer: int, units: Array[Unit], target: NodePath, pos: Vector3, attack_move: bool, facing: Vector3) -> void:
	var paths: Array[NodePath] = []
	for u in units:
		if is_instance_valid(u):
			paths.append(u.get_path())
	main.issue_command_as(peer, paths, target, pos, attack_move, false, Formation.Type.BOX, (COLUMNS - 1) * SPACING, facing)

func _centre(units: Array) -> Vector3:
	var sum := Vector3.ZERO
	var count: int = 0
	for u in units:
		if is_instance_valid(u) and u.status_current_health > 0:
			sum += u.global_position
			count += 1
	return focus if count == 0 else sum / count

## Keeps neutral shrine guards out of the filmed fight.
func _clear_nearby_guards() -> void:
	for node in get_tree().get_nodes_in_group(&"objectives"):
		var objective := node as Objective
		if objective == null or objective.global_position.distance_to(Vector3(-25, 0, LANE_Z)) > 60.0:
			continue
		objective.guard_respawn_delay = 9999.0
		for guard in objective._guards:
			if is_instance_valid(guard):
				guard.queue_free()
		objective._guards.clear()
