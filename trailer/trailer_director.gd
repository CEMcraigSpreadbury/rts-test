extends Node
## Drives a scripted camera through a skirmish for Movie Maker capture.
## Run: godot --path . --write-movie out.avi --fixed-fps 30 res://trailer/trailer_boot.tscn
## Prints TRAILER_START_FRAME so the warm-up can be trimmed off afterwards.

const TITLE: String = "Crowns of Aldmere"
const WARMUP_FRAMES: int = 150
const WARMUP_TIME_SCALE: float = 3.0

const HERO_CORNER: Vector3 = Vector3(-53, 0, 53)
const FADE_OUT_START: float = 26.4
const TITLE_IN: float = 26.9
const END: float = 29.4

const SHRINE: Vector3 = Vector3(-53.5, 0, 13.25)
## Seconds for a full squad to raise its flag on the filmed shrine (normally 15
## per unit), so the capture fits inside its shot.
const SHRINE_STAGE_DURATION: float = 2.4
const SHRINE_AT: float = 5.0

const CLASH: Vector3 = Vector3(-57, 0, 40)
const FROST: Vector3 = Vector3(-28, 0, -20)
const DRAGONS: Vector3 = Vector3(13, 0, -20)
const DARK: Vector3 = Vector3(26, 0, 17)

## Each shot: [start, end, from, to] where from/to are [pos, yaw, pitch, zoom].
## A cut dips to black briefly; battles spawn during that dip.
var shots: Array = [
	[0.0, 2.6, [Vector3(0, 0, -2), 20.0, 50.0, 110.0], [Vector3(-6, 0, 4), 30.0, 47.0, 96.0]],
	[2.6, 5.0, [Vector3(-52, 0, 55), -15.0, 35.0, 27.0], [Vector3(-53.5, 0, 52.5), -2.0, 33.5, 23.0]],
	[5.0, 9.3, [SHRINE + Vector3(0, 0, 6), -8.0, 38.0, 14.0], [SHRINE + Vector3(0, 0, 2.5), 6.0, 35.0, 11.5]],
	[9.3, 15.8, [CLASH + Vector3(0, 0, 1.5), 72.0, 32.0, 18.0], [CLASH, 108.0, 27.0, 12.5]],
	[15.8, 18.8, [FROST, -80.0, 34.0, 16.0], [FROST, -96.0, 31.0, 14.0]],
	[18.8, 21.8, [DRAGONS, -8.0, 36.0, 16.0], [DRAGONS, 6.0, 33.0, 14.0]],
	[21.8, 24.6, [DARK, 98.0, 38.0, 15.5], [DARK, 84.0, 36.0, 13.5]],
	[24.6, END, [DARK, 84.0, 36.0, 13.5], [DARK + Vector3(2, 0, -1), 65.0, 52.0, 36.0]],
]

## Humans against humans, each side bringing beastmen and monsters. The armies
## line up across the screen for the shot's yaw. casts are
## [seconds after the cut, side (0 hero / 1 enemy), index into that side's monsters].
var battles: Array = [
	{
		"at": 9.3, "centre": CLASH, "yaw": 90.0, "gap": 6.5,
		"sides": [
			{"roster": [["soldier_unit", 5], ["spearman_unit", 4], ["beastman_warrior_unit", 3], ["beastman_raider_unit", 3], ["archer_unit", 4], ["cavalry_unit", 2]],
				"monsters": ["phoenix_unit", "yeti_unit"]},
			{"roster": [["soldier_unit", 5], ["spearman_unit", 4], ["beastman_warrior_unit", 3], ["beastman_druid_unit", 3], ["archer_unit", 4], ["cavalry_unit", 2]],
				"monsters": ["orc_mutant_unit", "giant_bear_unit"]},
		],
		"casts": [[1.2, 1, 0], [1.9, 0, 0], [3.2, 1, 1], [4.0, 0, 1]],
	},
	{
		"at": 15.8, "centre": FROST, "yaw": -88.0, "gap": 5.0,
		"sides": [
			{"roster": [["soldier_unit", 4], ["beastman_raider_unit", 3], ["beastman_warrior_unit", 2], ["archer_unit", 3]],
				"monsters": ["skeleton_dragon_unit"]},
			{"roster": [["spearman_unit", 4], ["beastman_warrior_unit", 3], ["beastman_druid_unit", 2], ["archer_unit", 3]],
				"monsters": ["hydra_unit"]},
		],
		"casts": [[0.7, 1, 0], [1.4, 0, 0]],
	},
	{
		"at": 18.8, "centre": DRAGONS, "yaw": 0.0, "gap": 5.0,
		"sides": [
			{"roster": [["cavalry_unit", 3], ["soldier_unit", 3], ["beastman_warrior_unit", 3], ["beastman_druid_unit", 2], ["archer_unit", 3]],
				"monsters": ["black_dragon_unit"]},
			{"roster": [["soldier_unit", 4], ["beastman_raider_unit", 3], ["beastman_warrior_unit", 2], ["archer_unit", 3]],
				"monsters": ["dark_lord_unit"]},
		],
		"casts": [[0.6, 0, 0], [1.2, 1, 0]],
	},
	{
		"at": 21.8, "centre": DARK, "yaw": 91.0, "gap": 6.0,
		"sides": [
			{"roster": [["soldier_unit", 5], ["spearman_unit", 4], ["beastman_warrior_unit", 3], ["beastman_raider_unit", 2], ["archer_unit", 4], ["cavalry_unit", 2]],
				"monsters": ["giant_bear_unit", "phoenix_unit"]},
			{"roster": [["soldier_unit", 5], ["spearman_unit", 4], ["beastman_druid_unit", 3], ["beastman_raider_unit", 2], ["archer_unit", 4], ["cavalry_unit", 2]],
				"monsters": ["yeti_unit", "orc_mutant_unit"]},
		],
		"casts": [[0.6, 1, 0], [1.1, 0, 1], [1.7, 1, 1], [2.3, 0, 0]],
	},
]

var main: Main
var hero: int = 1
var t: float = -0.3
var running: bool = false
var shrine_squad_sent: bool = false
var fade: ColorRect
var title: Label
## [time, caster, target_units] pending casts.
var pending_casts: Array = []

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
	title = Label.new()
	title.text = TITLE
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override(&"font_size", 110)
	title.add_theme_color_override(&"font_color", Color(0.95, 0.88, 0.7))
	title.modulate.a = 0.0
	layer.add_child(title)

	while not (get_tree().current_scene is Main) or SceneLoader.is_transitioning:
		await get_tree().process_frame
	main = get_tree().current_scene
	main.ui_root.visible = false
	main.fog_of_war.reveal_all = true
	main.camera_rig.set_process(false)
	main.camera_rig.set_process_unhandled_input(false)
	for label in main.find_children("*", "Label3D", true, false):
		label.visible = false
	var best: float = INF
	for peer in main.town_centers:
		var d: float = main.town_centers[peer].global_position.distance_to(HERO_CORNER)
		if d < best:
			best = d
			hero = peer
	_dress_player_base()
	_send_villagers_to_work()
	_clear_filmed_shrine()
	Engine.time_scale = WARMUP_TIME_SCALE
	for i in WARMUP_FRAMES:
		await get_tree().process_frame
	Engine.time_scale = 1.0
	print("TRAILER_START_FRAME=%d" % Engine.get_process_frames())
	running = true

func _process(delta: float) -> void:
	if not running:
		return
	t += delta
	_update_camera()
	_update_overlay()
	if not shrine_squad_sent and t >= SHRINE_AT:
		shrine_squad_sent = true
		_send_shrine_squad()
	for battle in battles:
		if not battle.get("spawned", false) and t >= battle.at:
			battle.spawned = true
			_spawn_battle(battle)
	for cast in pending_casts.duplicate():
		if t >= cast[0]:
			pending_casts.erase(cast)
			_cast_at_nearest(cast[1], cast[2])
	if t >= END:
		print("TRAILER_END_FRAME=%d" % Engine.get_process_frames())
		get_tree().quit()

func _update_camera() -> void:
	for shot in shots:
		if t < shot[1] or shot == shots[-1]:
			var k: float = clampf(inverse_lerp(shot[0], shot[1], t), 0.0, 1.0)
			## Mostly linear with only a light ease, so the mid-shot speed stays low.
			k = lerpf(k, k * k * (3.0 - 2.0 * k), 0.4)
			var a: Array = shot[2]
			var b: Array = shot[3]
			_set_camera(a[0].lerp(b[0], k), lerpf(a[1], b[1], k), lerpf(a[2], b[2], k), lerpf(a[3], b[3], k))
			return

## Black at the start, a quick dip at each cut, a fade out to the title.
func _update_overlay() -> void:
	var alpha: float = 1.0 - clampf(t / 0.6, 0.0, 1.0)
	for shot in shots.slice(1, shots.size() - 1):
		alpha = maxf(alpha, 1.0 - clampf(absf(t - shot[0]) / 0.12, 0.0, 1.0))
	alpha = maxf(alpha, clampf((t - FADE_OUT_START) / 0.5, 0.0, 1.0))
	fade.color.a = alpha
	title.modulate.a = clampf((t - TITLE_IN) / 0.6, 0.0, 1.0)
	var s: float = 1.0 + 0.04 * clampf((t - TITLE_IN) / (END - TITLE_IN), 0.0, 1.0)
	title.pivot_offset = title.size * 0.5
	title.scale = Vector2(s, s)

func _set_camera(pos: Vector3, yaw_deg: float, pitch_deg: float, zoom: float) -> void:
	var rig := main.camera_rig
	rig.global_position = pos
	rig.yaw.rotation_degrees.y = yaw_deg
	rig.pitch_degrees = pitch_deg
	rig.pitch.rotation_degrees.x = -pitch_deg
	rig.zoom_distance = zoom
	rig._zoom_target = zoom
	rig._update_zoom()

func _enemy_peer() -> int:
	for id in Network.ai_peer_ids():
		if id != hero:
			return id
	return 1

func _dress_player_base() -> void:
	var hall: Node3D = main.town_centers.get(hero)
	if hall == null:
		return
	var base: Vector3 = hall.global_position
	var pieces: Array = [
		["res://scenes/buildings/house_building.tscn", Vector3(-8, 0, 3)],
		["res://scenes/buildings/house_building.tscn", Vector3(-8, 0, -3)],
		["res://scenes/buildings/barracks_building.tscn", Vector3(0, 0, 9)],
		["res://scenes/buildings/blacksmith_building.tscn", Vector3(-7, 0, 10)],
		["res://scenes/buildings/watchtower_building.tscn", Vector3(5, 0, -8)],
	]
	for p in pieces:
		main.building_spawner.spawn({
			"scene_path": p[0],
			"peer_id": hero,
			"position": base + p[1],
			"tint": main.get_team_tint(hero),
		})

func _send_villagers_to_work() -> void:
	var dropoff: Node3D = main._get_dropoff_for(hero)
	var trees: Array = []
	for node in get_tree().get_nodes_in_group("gatherables"):
		if node is Gatherable and node.can_be_gathered():
			trees.append(node)
	for child in main.units_root.get_children():
		var unit := child as Unit
		if unit == null or unit.owner_peer_id != hero or not unit.can_gather:
			continue
		trees.sort_custom(func(x, y): return x.global_position.distance_squared_to(unit.global_position) < y.global_position.distance_squared_to(unit.global_position))
		if not trees.is_empty():
			unit.command_gather(trees[randi() % mini(3, trees.size())], dropoff)

func _filmed_shrine() -> Objective:
	var best: Objective = null
	for node in get_tree().get_nodes_in_group(&"objectives"):
		var objective := node as Objective
		if objective and (best == null or objective.global_position.distance_to(SHRINE) < best.global_position.distance_to(SHRINE)):
			best = objective
	return best

## The shot is about the flag going up, not the guard fight, so the filmed
## shrine starts unguarded and captures quickly.
func _clear_filmed_shrine() -> void:
	var shrine := _filmed_shrine()
	if shrine == null:
		return
	shrine.stage_duration = SHRINE_STAGE_DURATION
	shrine.guard_respawn_delay = 9999.0
	for guard in shrine._guards:
		if is_instance_valid(guard):
			guard.queue_free()
	shrine._guards.clear()

func _send_shrine_squad() -> void:
	var shrine := _filmed_shrine()
	var target: Vector3 = shrine.global_position if shrine else SHRINE
	target.y = 0.0
	var squad: Array = ["soldier_unit", "spearman_unit", "beastman_warrior_unit", "archer_unit", "soldier_unit"]
	var offsets: Array = [Vector3(-0.6, 0, 0), Vector3(0.6, 0, 0), Vector3(-0.6, 0, 1.3), Vector3(0.6, 0, 1.3), Vector3(0, 0, 2.6)]
	var units: Array[Unit] = []
	for i in squad.size():
		units.append(_spawn_unit(squad[i], hero, target + Vector3(0, 0, 10.5) + offsets[i]))
	await get_tree().process_frame
	for i in units.size():
		units[i].command_move(target + Vector3(offsets[i].x * 2.5, 0, offsets[i].z * 0.6 + 1.5))

## Hero on the left of the shot, enemy on the right; each army's rows stack
## away from the centre, monsters in a line behind them.
func _spawn_battle(battle: Dictionary) -> void:
	var centre: Vector3 = battle.centre
	var yaw: float = deg_to_rad(battle.yaw)
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var forward := Vector3(-sin(yaw), 0, -cos(yaw))
	var peers: Array[int] = [hero, _enemy_peer()]
	var armies: Array = [[], []]
	var monsters: Array = [[], []]
	for s in 2:
		var side: Dictionary = battle.sides[s]
		var away: Vector3 = right * (-1.0 if s == 0 else 1.0)
		var origin: Vector3 = centre + away * battle.gap
		var rows: int = 0
		var i: int = 0
		for entry in side.roster:
			for n in entry[1]:
				var row: int = floori(i / 5.0)
				var col: int = i % 5
				rows = row + 1
				var pos: Vector3 = origin + away * row * 1.4 + forward * (col - 2) * 1.5
				armies[s].append(_spawn_unit(entry[0], peers[s], pos))
				i += 1
		var names: Array = side.monsters
		for m in names.size():
			var pos: Vector3 = origin + away * (rows * 1.4 + 1.2) + forward * (m - (names.size() - 1) * 0.5) * 3.5
			monsters[s].append(_spawn_unit(names[m], peers[s], pos))
	await get_tree().process_frame
	for s in 2:
		var toward: Vector3 = right * (1.0 if s == 0 else -1.0)
		for u in armies[s] + monsters[s]:
			u.command_attack_move(centre + toward * 14.0)
	for cast in battle.casts:
		var s: int = cast[1]
		pending_casts.append([battle.at + cast[0], monsters[s][cast[2]], armies[1 - s] + monsters[1 - s]])

## Aims at the thickest part of the enemy line: the living target nearest the
## caster, nudged toward the targets' average so the blast catches several.
func _cast_at_nearest(caster: Unit, targets: Array) -> void:
	if not is_instance_valid(caster):
		return
	var living: Array = targets.filter(func(u): return is_instance_valid(u) and u.status_current_health > 0)
	if living.is_empty():
		return
	var avg := Vector3.ZERO
	var nearest: Unit = living[0]
	for u in living:
		avg += u.global_position
		if u.global_position.distance_squared_to(caster.global_position) < nearest.global_position.distance_squared_to(caster.global_position):
			nearest = u
	avg /= living.size()
	var aim: Vector3 = nearest.global_position.lerp(avg, 0.4)
	main.request_ability_as(caster.owner_peer_id, caster.get_path(), 0, aim)

func _spawn_unit(scene_name: String, peer: int, pos: Vector3) -> Unit:
	var folder: String = "units/monsters" if ResourceLoader.exists("res://scenes/units/monsters/%s.tscn" % scene_name) else "units"
	return main.unit_spawner.spawn({
		"scene_path": "res://scenes/%s/%s.tscn" % [folder, scene_name],
		"peer_id": peer,
		"tint": main.get_team_tint(peer),
		"position": pos,
	})
