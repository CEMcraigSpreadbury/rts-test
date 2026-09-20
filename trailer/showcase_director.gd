extends Node
## 25s showcase on Aethermoor Creek: a daylight river crossing, a night battle,
## then the same war in daylight rain. Wide 3/4 shots held long enough to read
## the formations rather than quick cuts.
## Run: godot --path . --write-movie out.png --fixed-fps 30 res://trailer/showcase_boot.tscn
## Movie Maker ignores --resolution; size it with an override.cfg setting
## display/window/size/window_width_override=1920 and window_height_override=1080.
## Prints TRAILER_START_FRAME / TRAILER_END_FRAME so the warm-up can be trimmed.

const TITLE: String = "Crowns of Aldmere"
const WARMUP_FRAMES: int = 120
const END: float = 25.0
const CUT_NIGHT: float = 7.0
const CUT_RAIN: float = 14.0
const PULL_BACK: float = 20.5
const TITLE_IN: float = 21.9
const FADE_OUT_START: float = 24.1
const DIP: float = 0.15
## Short of full night: the moonlight lift washes the team colours out, and
## the armies still have to read as two sides.
const NIGHT_AMOUNT: float = 0.82

## Armies are built as ranks this wide, melee first, so archers and casters
## end up behind the shields and shoot over them.
const COLUMNS: int = 14
const SPACING: float = 1.3

## Shot 1. The creek runs north-south through x -32..-24 at this z, so an army
## starting west of it wades across on its way to the meeting ground.
const LANE_Z: float = 25.0
const CREEK_WEST: Vector3 = Vector3(-40, 0, LANE_Z)
const CREEK_EAST: Vector3 = Vector3(-8, 0, LANE_Z)
const CREEK_MEET: Vector3 = Vector3(-21, 0, LANE_Z)
## The east army sets off once the west one is already in the water.
const CREEK_EAST_GO_AT: float = 1.8

## Shots 2 and 3, both on open grass clear of the shrines and of either
## player's base, with the armies close enough to lock together inside the shot.
const PLAIN_WEST: Vector3 = Vector3(37, 0, -14)
const PLAIN_EAST: Vector3 = Vector3(57, 0, -14)
const PLAIN_MEET: Vector3 = Vector3(47, 0, -14)

const FIELD_WEST: Vector3 = Vector3(16, 0, -62)
const FIELD_EAST: Vector3 = Vector3(36, 0, -62)
const FIELD_MEET: Vector3 = Vector3(26, 0, -62)

## Each shot: [start, end, from, to, battle] where from/to are
## [offset, yaw, pitch, zoom]. The offset is from the smoothed centre of that
## battle's living units; battle -1 means the shot follows the first battle's
## west army alone, which keeps the river crossing centred.
var shots: Array = [
	[0.0, CUT_NIGHT, [Vector3(2.0, 0, 1.0), -52.0, 31.0, 26.0], [Vector3(3.0, 0, 0.0), -35.0, 27.0, 19.0], -1],
	[CUT_NIGHT, CUT_RAIN, [Vector3(0, 0, -1.0), 62.0, 33.0, 24.0], [Vector3(0, 0, 0.0), 44.0, 28.0, 19.0], 1],
	[CUT_RAIN, PULL_BACK, [Vector3(-1.5, 0, 1.0), -58.0, 34.0, 25.0], [Vector3(0, 0, 0.0), -39.0, 29.0, 19.0], 2],
	[PULL_BACK, END, [Vector3(0, 0, 0.0), -39.0, 29.0, 19.0], [Vector3(1.0, 0, -2.0), -21.0, 41.0, 34.0], 2],
]

## Armies spawn PRESPAWN seconds before their shot, off camera, so they are
## already dressed in their ranks when the cut lands on them.
const PRESPAWN: float = 1.5

## roster entries are [scene name, count], melee first. casts are
## [seconds after the shot starts, side (0 west / 1 east), index into monsters].
var battles: Array = [
	{
		"at": 0.0, "west": CREEK_WEST, "east": CREEK_EAST, "meet": CREEK_MEET,
		"sides": [
			{"roster": [["shieldman_unit", 10], ["soldier_unit", 8], ["sw_knight_unit", 8], ["sw_spearman_unit", 6],
				["archer_unit", 12], ["wizard_unit", 4]], "monsters": []},
			{"roster": [["gnoll_warrior_unit", 10], ["dark_elf_guard_unit", 8], ["gnoll_berserk_unit", 8],
				["dark_elf_warrior_unit", 6], ["gnoll_archer_unit", 10], ["dark_elf_archer_unit", 6]], "monsters": []},
		],
		"casts": [],
	},
	{
		"at": CUT_NIGHT, "west": PLAIN_WEST, "east": PLAIN_EAST, "meet": PLAIN_MEET,
		"sides": [
			{"roster": [["soldier_unit", 10], ["halberdier_unit", 8], ["sw_warrior_unit", 8], ["sw_paladin_unit", 4],
				["archer_unit", 10], ["arch_mage_unit", 4]], "monsters": ["phoenix_unit", "giant_bear_unit"]},
			{"roster": [["gnoll_warrior_unit", 10], ["beastman_warrior_unit", 8], ["dark_elf_warrior_unit", 8],
				["dark_elf_assassin_unit", 4], ["gnoll_archer_unit", 10], ["dark_elf_sorceress_unit", 4]],
				"monsters": ["black_dragon_unit", "yeti_unit"]},
		],
		"casts": [[2.2, 1, 0], [3.0, 0, 0], [3.9, 1, 1], [4.7, 0, 1]],
	},
	{
		"at": CUT_RAIN, "west": FIELD_WEST, "east": FIELD_EAST, "meet": FIELD_MEET,
		"sides": [
			{"roster": [["shieldman_unit", 10], ["soldier_unit", 8], ["sw_paladin_unit", 6], ["cavalier_unit", 6],
				["archer_unit", 12], ["arch_mage_unit", 5]], "monsters": ["phoenix_unit", "hydra_unit"]},
			{"roster": [["gnoll_warrior_unit", 10], ["gnoll_berserk_unit", 8], ["dark_elf_guard_unit", 6],
				["beastman_raider_unit", 6], ["gnoll_archer_unit", 10], ["gnoll_shaman_unit", 5]],
				"monsters": ["black_dragon_unit", "dark_lord_unit"]},
		],
		"casts": [[2.3, 1, 0], [3.1, 0, 0], [4.0, 1, 1], [4.9, 0, 1], [7.4, 1, 0], [8.2, 0, 1]],
	},
]

var main: Main
var hero: int = 1
var enemy: int = 1
var t: float = -0.3
var running: bool = false
var creek_east_sent: bool = false
var fade: ColorRect
var title: Label
var focus: Vector3 = CREEK_WEST
var focus_shot: int = -1
## Pending [time, caster, target_units].
var pending_casts: Array = []
var _label_timer: float = 0.0

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

	## Showcase look regardless of the local options, without saving them.
	for key in [&"clouds", &"wind", &"grass", &"water_reflections", &"depth_of_field"]:
		_force_setting(key, true)
	_force_setting(&"damage_numbers", false)

	while not (get_tree().current_scene is Main) or SceneLoader.is_transitioning:
		await get_tree().process_frame
	main = get_tree().current_scene
	main.ui_root.visible = false
	main.fog_of_war.reveal_all = true
	main.camera_rig.set_process(false)
	main.camera_rig.set_process_unhandled_input(false)
	_hide_labels()
	for ai in main.ai_players.values():
		ai.process_mode = Node.PROCESS_MODE_DISABLED
	hero = main.my_peer_id()
	for id in Network.ai_peer_ids():
		enemy = id
	## Abilities are paid for out of the stockpile, and nobody is earning here.
	for peer in [hero, enemy]:
		for resource_type in Main.STARTING_RESOURCES:
			ResourceStockpile.add(peer, resource_type, 100000)
	_clear_guards()

	await _spawn_battle(battles[0])
	_update_camera(0.0)
	for i in WARMUP_FRAMES:
		await get_tree().process_frame
	print("TRAILER_START_FRAME=%d" % Engine.get_process_frames())
	running = true
	_advance(battles[0], 0)

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
	## Objectives put their banner letters up again as their state changes, so
	## one sweep at startup isn't enough to keep them out of shot.
	_label_timer -= delta
	if _label_timer <= 0.0:
		_label_timer = 0.5
		_hide_labels()
	if not creek_east_sent and t >= CREEK_EAST_GO_AT:
		creek_east_sent = true
		_order(enemy, battles[0].east_units, CREEK_MEET, Vector3.LEFT, true)
	for i in range(1, battles.size()):
		var battle: Dictionary = battles[i]
		if not battle.get("spawned", false) and t >= battle.at - PRESPAWN:
			battle.spawned = true
			_spawn_battle(battle)
		elif battle.get("spawned", false) and not battle.get("advanced", false) and t >= battle.at:
			battle.advanced = true
			_advance(battle, i)
	if not battles[1].get("night", false) and t >= CUT_NIGHT:
		battles[1].night = true
		_set_night(NIGHT_AMOUNT)
	if not battles[2].get("rain", false) and t >= CUT_RAIN:
		battles[2].rain = true
		_set_night(0.0)
		_set_rain(true)
	for cast in pending_casts.duplicate():
		if t >= cast[0]:
			pending_casts.erase(cast)
			_cast_at_nearest(cast[1], cast[2])
	if t >= END:
		print("TRAILER_END_FRAME=%d" % Engine.get_process_frames())
		get_tree().quit()

## Both the clock and the shower normally cross over across tens of seconds;
## here each is snapped over behind the cut that hides the change.
func _set_night(amount: float) -> void:
	var day_night: DayNight = main.day_night
	if day_night == null:
		return
	if day_night._fade_tween:
		day_night._fade_tween.kill()
	day_night.is_night = amount > 0.5
	day_night._time_to_change = 9999.0
	day_night._set_night_amount(amount)

func _set_rain(raining: bool) -> void:
	var weather: Weather = main.weather
	if weather == null:
		return
	if weather._fade_tween:
		weather._fade_tween.kill()
	weather.is_raining = raining
	weather._time_to_change = 9999.0
	var wind := Vector3(0.22, -1.0, 0.1).normalized()
	(weather._particles.process_material as ParticleProcessMaterial).direction = wind
	weather._particles.visible = raining
	weather._particles.emitting = raining
	if raining and not weather._sound.playing:
		weather._sound.play()
	elif not raining:
		weather._sound.stop()
	weather._set_intensity(1.0 if raining else 0.0)

func _update_camera(delta: float) -> void:
	for n in shots.size():
		var shot: Array = shots[n]
		if t < shot[1] or n == shots.size() - 1:
			var centre := _shot_centre(shot[4])
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

func _shot_centre(which: int) -> Vector3:
	if which < 0:
		return _centre(battles[0].get("west_units", []))
	var battle: Dictionary = battles[which]
	return _centre(battle.get("west_units", []) + battle.get("east_units", []))

## Fade in, a dip through black at each cut, fade out under the title.
func _update_overlay() -> void:
	var alpha: float = 1.0 - clampf(t / 0.6, 0.0, 1.0)
	for cut in [CUT_NIGHT, CUT_RAIN]:
		alpha = maxf(alpha, 1.0 - clampf(absf(t - cut) / DIP, 0.0, 1.0))
	alpha = maxf(alpha, clampf((t - FADE_OUT_START) / 0.5, 0.0, 1.0))
	fade.color.a = alpha
	title.modulate.a = clampf((t - TITLE_IN) / 0.6, 0.0, 1.0)
	var s: float = 1.0 + 0.04 * clampf((t - TITLE_IN) / (END - TITLE_IN), 0.0, 1.0)
	title.pivot_offset = title.size * 0.5
	title.scale = Vector2(s, s)

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

## West army faces east, east army faces west; both hold their ranks until the
## shot they belong to starts.
func _spawn_battle(battle: Dictionary) -> void:
	battle.west_units = _spawn_block(battle, hero, battle.west, Vector3.RIGHT, battle.sides[0], true)
	battle.east_units = _spawn_block(battle, enemy, battle.east, Vector3.LEFT, battle.sides[1], false)
	await get_tree().process_frame
	_order(hero, battle.west_units, battle.west, Vector3.RIGHT)
	_order(enemy, battle.east_units, battle.east, Vector3.LEFT)

func _advance(battle: Dictionary, index: int) -> void:
	_order(hero, battle.west_units, battle.meet, Vector3.RIGHT, true)
	## The creek's east army waits, so the crossing is in shot on its own.
	if index != 0:
		_order(enemy, battle.east_units, battle.meet, Vector3.LEFT, true)
	for cast in battle.casts:
		var side: int = cast[1]
		var casters: Array = battle.west_monsters if side == 0 else battle.east_monsters
		if cast[2] >= casters.size():
			continue
		var targets: Array = battle.east_units if side == 0 else battle.west_units
		pending_casts.append([battle.at + cast[0], casters[cast[2]], targets])

## Ranks of COLUMNS stacked back from `front` in roster order, with the side's
## monsters in a line behind the last rank.
func _spawn_block(battle: Dictionary, peer: int, front: Vector3, facing: Vector3, side: Dictionary, west: bool) -> Array[Unit]:
	var right := Vector3(facing.z, 0, -facing.x)
	var units: Array[Unit] = []
	var i: int = 0
	for entry in side.roster:
		for n in entry[1]:
			var row: int = floori(float(i) / COLUMNS)
			var col: int = i % COLUMNS
			units.append(_spawn_unit(entry[0], peer,
					front - facing * row * SPACING + right * (col - (COLUMNS - 1) * 0.5) * SPACING))
			i += 1
	var rows: int = ceili(float(i) / COLUMNS)
	var names: Array = side.monsters
	var monsters: Array[Unit] = []
	for m in names.size():
		monsters.append(_spawn_unit(names[m], peer,
				front - facing * (rows * SPACING + 2.5) + right * (m - (names.size() - 1) * 0.5) * 5.0))
	if west:
		battle.west_monsters = monsters
	else:
		battle.east_monsters = monsters
	units.append_array(monsters)
	return units

func _spawn_unit(scene_name: String, peer: int, pos: Vector3) -> Unit:
	return main.unit_spawner.spawn({
		"scene_path": _scene_path(scene_name),
		"peer_id": peer,
		"tint": main.get_team_tint(peer),
		"position": pos,
	})

func _scene_path(scene_name: String) -> String:
	for folder in ["units", "units/monsters", "units/gnolls", "units/dark_elves", "units/star_wanderers"]:
		var path: String = "res://scenes/%s/%s.tscn" % [folder, scene_name]
		if ResourceLoader.exists(path):
			return path
	push_error("showcase_director: no scene for %s" % scene_name)
	return "res://scenes/units/soldier_unit.tscn"

func _order(peer: int, units: Array, pos: Vector3, facing: Vector3, attack_move: bool = false) -> void:
	var paths: Array[NodePath] = []
	for u in units:
		if is_instance_valid(u):
			paths.append(u.get_path())
	main.issue_command_as(peer, paths, NodePath(), pos, attack_move, false,
			Formation.Type.BOX, (COLUMNS - 1) * SPACING, facing)

func _centre(units: Array) -> Vector3:
	var sum := Vector3.ZERO
	var count: int = 0
	for u in units:
		if is_instance_valid(u) and u.status_current_health > 0:
			sum += u.global_position
			count += 1
	return focus if count == 0 else sum / count

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
	main.request_ability_as(caster.owner_peer_id, caster.get_path(), 0,
			nearest.global_position.lerp(avg, 0.4))

func _hide_labels() -> void:
	for label in main.find_children("*", "Label3D", true, false):
		label.visible = false

## Keeps neutral shrine guards out of every filmed fight.
func _clear_guards() -> void:
	for node in get_tree().get_nodes_in_group(&"objectives"):
		var objective := node as Objective
		if objective == null:
			continue
		objective.guard_respawn_delay = 9999.0
		for guard in objective._guards:
			if is_instance_valid(guard):
				guard.queue_free()
		objective._guards.clear()
