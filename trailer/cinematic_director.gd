extends Node
## 45s cinematic trailer on Aldmere Vale (Realm): a Dark Elf village grows
## into a walled city, a Lord leads a column down the road, cavalry smash into
## a gnoll line (in slow motion as it lands), beasts and spells at night, then
## a full battle in the rain that the camera cranes up and away from under
## the title.
## Run: godot --path . --write-movie out.png --fixed-fps 30 res://trailer/cinematic_boot.tscn
## Movie Maker ignores --resolution; size it with an override.cfg setting
## display/window/size/window_width_override=1920 and window_height_override=1080.
## Prints TRAILER_START_FRAME / TRAILER_END_FRAME so the warm-up can be trimmed.
## The Music bus is muted: the score is laid under the game sound afterwards.

const TITLE: String = "Crowns of Aldmere"
const WARMUP_FRAMES: int = 150
const END: float = 45.0
const CUT_MARCH: float = 8.0
const CUT_CHARGE: float = 15.0
const CUT_NIGHT: float = 22.0
const CUT_RAIN: float = 30.0
const CRANE: float = 37.0
const TITLE_IN: float = 40.2
const FADE_OUT_START: float = 43.8
const DIP: float = 0.15
const NIGHT_AMOUNT: float = 0.7
## Armies spawn this long before their shot, off camera, so they are already
## dressed in their ranks when the cut lands on them.
const PRESPAWN: float = 1.6
## A shot's armies are freed this long after it ends, so finished fights
## don't cost frames for the rest of the film.
const CLEANUP_AFTER: float = 0.6

## Shot 1: the Dark Elf village nearest the hero's side of the map.
const VILLAGE_NAME: String = "Objective12"

## Shot 2: the road from the hero's base toward that village.
const ROAD_START: Vector3 = Vector3(-196, 0, 188)
const ROAD_DIR: Vector3 = Vector3(0.68, 0, -0.73)
const MARCH_DISTANCE: float = 70.0

## Shot 3: open grass. The gnolls stand facing west; the riders start
## CHARGE_RUN metres short of them.
const CHARGE_LINE: Vector3 = Vector3(-146, 0, -60)
const CHARGE_RUN: float = 28.0
## Slow motion from the first man thrown, in film seconds.
const SLOWMO_SCALE: float = 0.3
const SLOWMO_HOLD: float = 1.1
const SLOWMO_RAMP: float = 0.5

## Shots 4 and 5: two armies facing along x, meeting halfway.
const NIGHT_MEET: Vector3 = Vector3(-40, 0, -165)
const RAIN_MEET: Vector3 = Vector3(150, 0, 60)
const HALF_GAP: float = 4.5
## Blocks close at barely 1 m/s each once they sight each other (the whole
## group turns into one attack), so the fights are set going this long before
## their cut, off camera, to land in contact early in the shot.
const ADVANCE_LEAD: float = 3.2
## Their own spawn lead, long enough to dress into their blocks first: men
## still finding their places hold a block's march back.
const FIGHT_PRESPAWN: float = 4.4

const SPACING: float = 1.3

## Each battle: where the two sides draw up and what they bring. Roster
## entries are [scene name, count], front rank first; `columns` is the width
## of the block. Beasts stand in a line behind the last rank. casts are
## [seconds after the shot starts, side (0 hero / 1 enemy), index into beasts].
var battles: Array = [
	{
		"at": CUT_MARCH, "hero_front": ROAD_START, "hero_facing": ROAD_DIR, "columns": 7,
		"hero": {"roster": [["soldier_unit", 28], ["archer_unit", 21]], "beasts": []},
		"enemy": null, "casts": [],
	},
	{
		"at": CUT_CHARGE, "hero_front": CHARGE_LINE + Vector3.LEFT * CHARGE_RUN, "hero_facing": Vector3.RIGHT,
		"enemy_front": CHARGE_LINE, "columns": 10,
		"hero": {"roster": [["cavalier_unit", 12], ["horseman_unit", 8]], "beasts": []},
		"enemy": {"roster": [["gnoll_warrior_unit", 30], ["gnoll_archer_unit", 10]], "beasts": [], "columns": 14},
		"casts": [],
	},
	{
		"at": CUT_NIGHT, "lead": ADVANCE_LEAD, "prespawn": FIGHT_PRESPAWN, "hero_front": NIGHT_MEET + Vector3.LEFT * HALF_GAP, "hero_facing": Vector3.RIGHT,
		"enemy_front": NIGHT_MEET + Vector3.RIGHT * HALF_GAP, "columns": 14,
		"hero": {"roster": [["soldier_unit", 14], ["sw_knight_unit", 10], ["halberdier_unit", 8],
				["archer_unit", 14], ["wizard_unit", 6]],
				"beasts": ["griffin_unit", "lightning_dragon_unit", "dragon_unit", "manticore_unit"]},
		"enemy": {"roster": [["dark_elf_warrior_unit", 14], ["gnoll_berserk_unit", 12], ["dark_elf_guard_unit", 8],
				["dark_elf_archer_unit", 12], ["dark_elf_sorceress_unit", 6]],
				"beasts": ["kitsune_unit", "skeleton_dragon_unit", "sand_worm_unit", "wind_tiger_unit"]},
		"casts": [[2.0, 1, 1], [2.6, 0, 1], [3.3, 1, 0], [4.0, 0, 2], [4.8, 1, 2], [5.6, 1, 3], [6.3, 0, 1]],
	},
	{
		"at": CUT_RAIN, "lead": ADVANCE_LEAD, "prespawn": FIGHT_PRESPAWN, "hero_front": RAIN_MEET + Vector3.LEFT * HALF_GAP, "hero_facing": Vector3.RIGHT,
		"enemy_front": RAIN_MEET + Vector3.RIGHT * HALF_GAP, "columns": 18,
		"hero": {"roster": [["shieldman_unit", 18], ["soldier_unit", 18], ["sw_warrior_unit", 18],
				["archer_unit", 18], ["crossbowman_unit", 18], ["arch_mage_unit", 6], ["cavalier_unit", 12]],
				"beasts": ["phoenix_unit", "hydra_unit"]},
		"enemy": {"roster": [["gnoll_warrior_unit", 18], ["beastman_warrior_unit", 18], ["dark_elf_warrior_unit", 18],
				["gnoll_archer_unit", 18], ["dark_elf_archer_unit", 18], ["gnoll_shaman_unit", 6], ["dark_elf_rider_unit", 12]],
				"beasts": ["black_dragon_unit", "dark_lord_unit"]},
		"casts": [[2.4, 1, 0], [3.2, 0, 0], [4.1, 1, 1], [5.0, 0, 1], [7.6, 1, 0], [8.4, 0, 0], [9.6, 0, 1]],
	},
]

var main: Main
var terrain: Node
var village: Objective
var hero: int = 1
var enemy: int = 1
## Film time: unscaled, so slow motion doesn't stretch the edit.
var t: float = -0.3
var running: bool = false
var fade: ColorRect
var title: Label
var focus: Vector3 = Vector3.ZERO
var focus_shot: int = -1
var pending_casts: Array = []
## [time, Callable], fired once each and removed.
var events: Array = []
var _label_timer: float = 0.0
var _slowmo_from: float = -1.0
## --preview=<dir>: a small still every PREVIEW_EVERY film seconds, named by
## film time, for checking the choreography without a full movie capture.
var _preview_dir: String = ""
var _next_preview: float = 0.0
const PREVIEW_EVERY: float = 0.5

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	## After the game's own _process, so what is hidden here (banners, the
	## capture disc) isn't shown again in the same frame.
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
	title = Label.new()
	title.text = TITLE
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_override(&"font", load("res://assets/fonts/MarcellusSC-Regular.ttf"))
	title.add_theme_font_size_override(&"font_size", 124)
	title.add_theme_color_override(&"font_color", Color(0.96, 0.89, 0.7))
	title.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.75))
	title.add_theme_constant_override(&"shadow_offset_x", 0)
	title.add_theme_constant_override(&"shadow_offset_y", 4)
	title.add_theme_constant_override(&"shadow_outline_size", 18)
	title.modulate.a = 0.0
	layer.add_child(title)

	## Showcase look regardless of the local options, without saving them.
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
	## Past max_zoom the rig tilts toward its overview pitch; every shot here
	## sets its own.
	main.camera_rig.max_zoom = 1000.0
	for ai in main.ai_players.values():
		ai.process_mode = Node.PROCESS_MODE_DISABLED
	hero = main.my_peer_id()
	for id in Network.ai_peer_ids():
		enemy = id
	## Abilities are paid for out of the stockpile, and nobody is earning here.
	for peer in [hero, enemy]:
		for resource_type in Main.STARTING_RESOURCES:
			ResourceStockpile.add(peer, resource_type, 100000)
	## Clear and daylit until the film itself changes them.
	_set_night(0.0)
	_set_rain(false)
	_hide_labels()
	_take_village()
	_spawn_battle(battles[0])
	_update_camera(0.0)
	for i in WARMUP_FRAMES:
		await get_tree().process_frame
	_update_camera(0.0)
	print("TRAILER_START_FRAME=%d" % Engine.get_process_frames())
	running = true

func _force_setting(key: StringName, value: Variant) -> void:
	if Settings.values[key] == value:
		return
	Settings.values[key] = value
	Settings._apply(key, false)
	Settings.changed.emit(key)

func _process(delta: float) -> void:
	if not running:
		return
	var film_delta: float = delta / maxf(Engine.time_scale, 0.001)
	t += film_delta
	_update_slowmo()
	_update_camera(film_delta)
	_update_overlay()
	_label_timer -= film_delta
	if _label_timer <= 0.0:
		_label_timer = 0.25
		_hide_labels()
	_hide_health_bars()
	for banner in main.feedback._regiment_banners.values():
		banner.visible = false
	if village:
		village.progress_disc.visible = false
	for event in events.duplicate():
		if t >= event[0]:
			events.erase(event)
			event[1].call()
	for i in battles.size():
		var battle: Dictionary = battles[i]
		if not battle.get("spawned", false) and t >= battle.at - battle.get("prespawn", PRESPAWN):
			_spawn_battle(battle)
		if not battle.get("advanced", false) and t >= battle.at - battle.get("lead", 0.0):
			battle.advanced = true
			_advance(battle, i)
		var ends: float = _battle_end(i)
		if not battle.get("cleared", false) and t >= ends + CLEANUP_AFTER:
			battle.cleared = true
			for u in battle.get("hero_units", []) + battle.get("enemy_units", []):
				if is_instance_valid(u):
					u.queue_free()
	if _slowmo_from < 0.0 and t > CUT_CHARGE and t < CUT_NIGHT and _anyone_thrown(battles[1].get("enemy_units", [])):
		_slowmo_from = t
	if not battles[2].get("night", false) and t >= CUT_NIGHT:
		battles[2].night = true
		_set_night(NIGHT_AMOUNT)
	if not battles[3].get("rain", false) and t >= CUT_RAIN:
		battles[3].rain = true
		_set_night(0.0)
		_set_rain(true)
	for cast in pending_casts.duplicate():
		if t >= cast[0]:
			pending_casts.erase(cast)
			_cast_at_nearest(cast[1], cast[2])
	if _preview_dir != "" and t >= _next_preview:
		_next_preview += PREVIEW_EVERY
		var image := get_viewport().get_texture().get_image()
		image.resize(640, 360)
		image.save_jpg("%s/t%05.1f.jpg" % [_preview_dir, t])
	if t >= END:
		print("TRAILER_END_FRAME=%d" % Engine.get_process_frames())
		get_tree().quit()

func _battle_end(index: int) -> float:
	return battles[index + 1].at if index + 1 < battles.size() else END + 10.0

## --- Shot 1: the village ---

## The hero's from the start (its cottages already in their colour), rid of
## its neutral guards, with a few of its own people about. Then over the shot
## it grows twice, fills its slots and puts its walls up, each piece dropping in.
func _take_village() -> void:
	for node in get_tree().get_nodes_in_group(&"objectives"):
		if node.name == VILLAGE_NAME:
			village = node
	if village == null:
		push_error("cinematic_director: no %s" % VILLAGE_NAME)
		return
	focus = village.global_position
	village.guard_respawn_delay = 9999.0
	for guard in village._guards:
		if is_instance_valid(guard):
			guard.queue_free()
	village._guards.clear()
	village._set_owner(hero)
	village.resolve_choice(Objective.Choice.OCCUPY)
	## Its flag already up, so no capture disc fills over the shot.
	village.flag_peer_id = hero
	village.flag_control = 1.0
	for i in 5:
		village._raise_garrison_man()
	var items: Array[ProducibleItem] = village._slot_options()
	var by_name := {}
	for item in items:
		by_name[item.item_name] = item
	var military: ProducibleItem = items[0]
	events = [
		[0.9, func(): village.raise_tier(Objective.Tier.TOWN)],
		[1.7, func(): village.place_slot(military)],
		[2.3, func(): village.place_slot(by_name[Objective.MARKET])],
		[3.3, func(): village.raise_tier(Objective.Tier.CITY)],
		[4.1, func(): village.place_slot(by_name[Objective.WATCHTOWER])],
		## Last: the walls take the City's fourth slot.
		[4.8, func(): village.place_slot(by_name[Objective.WALLS])],
	]

## --- Camera ---

## Each shot: [start, end, subject, from, to], from/to being
## [offset from the subject, yaw, pitch, zoom]. The subject is followed with
## a little lag so the camera drifts rather than locks on.
func _shots() -> Array:
	var road_side: float = _yaw_facing(Vector3(-ROAD_DIR.z, 0, ROAD_DIR.x))
	var road_ahead: float = _yaw_facing(-ROAD_DIR)
	return [
		[0.0, CUT_MARCH, 0, [Vector3(0, 0, 1), 8.0, 34.0, 33.0], [Vector3.ZERO, 58.0, 29.0, 28.0]],
		[CUT_MARCH, CUT_CHARGE, 1, [ROAD_DIR * 3.0, road_side - 28.0, 25.0, 12.0], [ROAD_DIR * 2.0, road_ahead + 38.0, 29.0, 14.5]],
		[CUT_CHARGE, CUT_NIGHT, 2, [Vector3(-2, 0, 1), -118.0, 26.0, 16.0], [Vector3(1, 0, 0), -150.0, 29.0, 15.0]],
		[CUT_NIGHT, CUT_RAIN, 3, [Vector3(0, 0, 1), 28.0, 31.0, 20.0], [Vector3(0, 0, 0), 4.0, 27.0, 16.0]],
		[CUT_RAIN, CRANE, 4, [Vector3(-2, 0, 2), -32.0, 26.0, 19.0], [Vector3(0, 0, 0), -10.0, 29.0, 17.0]],
		[CRANE, END, 4, [Vector3(0, 0, 0), -10.0, 29.0, 17.0], [Vector3(2, 0, -4), 14.0, 50.0, 58.0]],
	]

## The yaw that has the camera looking along `dir`.
func _yaw_facing(dir: Vector3) -> float:
	return rad_to_deg(atan2(-dir.x, -dir.z))

func _subject(which: int) -> Vector3:
	match which:
		0:
			return village.global_position if village else Vector3.ZERO
		2:
			## Mostly the riders, so the camera runs with the charge.
			var riders := _centre(battles[1].get("hero_units", []))
			var line := _centre(battles[1].get("enemy_units", []))
			return riders.lerp(line, 0.5)
		_:
			var battle: Dictionary = battles[which - 1]
			return _centre(battle.get("hero_units", []) + battle.get("enemy_units", []))

func _update_camera(delta: float) -> void:
	var shots := _shots()
	for n in shots.size():
		var shot: Array = shots[n]
		if t >= shot[1] and n != shots.size() - 1:
			continue
		var centre := _subject(shot[2])
		if n != focus_shot:
			## The crane carries on from the shot before it without a jump.
			if focus_shot < 0 or shots[focus_shot][2] != shot[2]:
				focus = centre
			focus_shot = n
		else:
			focus = focus.lerp(centre, 1.0 - exp(-1.6 * delta))
		var k: float = clampf(inverse_lerp(shot[0], shot[1], t), 0.0, 1.0)
		k = k * k * (3.0 - 2.0 * k)
		var a: Array = shot[3]
		var b: Array = shot[4]
		## The short way round, whatever the yaws were written as.
		var yaw_b: float = a[1] + wrapf(b[1] - a[1], -180.0, 180.0)
		_set_camera(focus + a[0].lerp(b[0], k), lerpf(a[1], yaw_b, k), lerpf(a[2], b[2], k), lerpf(a[3], b[3], k))
		return

func _set_camera(pos: Vector3, yaw_deg: float, pitch_deg: float, zoom: float) -> void:
	var rig := main.camera_rig
	if terrain:
		pos.y = maxf(float(terrain.call("getHeightAtPosition", pos.x, pos.z, true)), -2.5)
	rig.global_position = pos
	rig.yaw.rotation_degrees.y = yaw_deg
	rig.pitch_degrees = pitch_deg
	rig.pitch.rotation_degrees.x = -pitch_deg
	rig.zoom_distance = zoom
	rig._zoom_target = zoom
	rig._update_zoom()

## Fade in, a dip through black at each cut, fade out under the title.
func _update_overlay() -> void:
	var alpha: float = 1.0 - clampf(t / 0.8, 0.0, 1.0)
	for cut in [CUT_MARCH, CUT_CHARGE, CUT_NIGHT, CUT_RAIN]:
		alpha = maxf(alpha, 1.0 - clampf(absf(t - cut) / DIP, 0.0, 1.0))
	alpha = maxf(alpha, clampf((t - FADE_OUT_START) / 0.9, 0.0, 1.0))
	fade.color.a = alpha
	title.modulate.a = clampf((t - TITLE_IN) / 0.9, 0.0, 1.0)
	var s: float = 1.0 + 0.05 * clampf((t - TITLE_IN) / (END - TITLE_IN), 0.0, 1.0)
	title.pivot_offset = title.size * 0.5
	title.scale = Vector2(s, s)

## --- Slow motion ---

func _anyone_thrown(units: Array) -> bool:
	for u in units:
		if is_instance_valid(u) and u._knockback_remaining > 0.0:
			return true
	return false

## Down to SLOWMO_SCALE the moment the charge lands, held, then eased back.
func _update_slowmo() -> void:
	if _slowmo_from < 0.0:
		return
	var since: float = t - _slowmo_from
	var scale: float = SLOWMO_SCALE
	if since > SLOWMO_HOLD:
		var k: float = clampf((since - SLOWMO_HOLD) / SLOWMO_RAMP, 0.0, 1.0)
		scale = lerpf(SLOWMO_SCALE, 1.0, k * k)
	Engine.time_scale = scale
	if since > SLOWMO_HOLD + SLOWMO_RAMP:
		Engine.time_scale = 1.0
		_slowmo_from = INF

## --- Weather ---

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
	weather._set_intensity(1.0 if raining else 0.0)

## --- Armies ---

func _spawn_battle(battle: Dictionary) -> void:
	battle.spawned = true
	var facing: Vector3 = battle.hero_facing
	battle.hero_units = _spawn_block(battle, hero, battle.hero_front, facing, battle.hero, battle.columns, true)
	if battle.enemy != null:
		var columns: int = battle.enemy.get("columns", battle.columns)
		battle.enemy_units = _spawn_block(battle, enemy, battle.enemy_front, -facing, battle.enemy, columns, false)
	await get_tree().process_frame
	_order(hero, battle.hero_units, battle.hero_front, facing, battle.columns)
	if battle.enemy != null:
		_order(enemy, battle.enemy_units, battle.enemy_front, -facing, battle.enemy.get("columns", battle.columns))

func _advance(battle: Dictionary, index: int) -> void:
	var facing: Vector3 = battle.hero_facing
	if battle.enemy == null:
		_order(hero, battle.hero_units, battle.hero_front + facing * MARCH_DISTANCE, facing, battle.columns)
		return
	var meet: Vector3 = (battle.hero_front + battle.enemy_front) * 0.5
	if index == 1:
		## The gnolls hold; the riders run through where they stand.
		meet = battle.enemy_front + facing * 4.0
		_order(hero, battle.hero_units, meet, facing, battle.columns, true)
	else:
		_order(hero, battle.hero_units, meet, facing, battle.columns, true)
		_order(enemy, battle.enemy_units, meet, -facing, battle.enemy.get("columns", battle.columns), true)
	for cast in battle.casts:
		var side: int = cast[1]
		var casters: Array = battle.hero_beasts if side == 0 else battle.enemy_beasts
		if cast[2] >= casters.size():
			continue
		var targets: Array = battle.enemy_units if side == 0 else battle.hero_units
		pending_casts.append([battle.at + cast[0], casters[cast[2]], targets])

## Ranks `columns` wide stacked back from `front` in roster order, with the
## side's beasts in a line behind the last rank.
func _spawn_block(battle: Dictionary, peer: int, front: Vector3, facing: Vector3, side: Dictionary, columns: int, is_hero: bool) -> Array[Unit]:
	var right := Vector3(facing.z, 0, -facing.x)
	var units: Array[Unit] = []
	var i: int = 0
	for entry in side.roster:
		## A Lord rides out in front of his men, not in their ranks.
		if entry[0] == "lord_unit":
			units.append(_spawn_unit(entry[0], peer, front + facing * 3.0))
			continue
		for n in entry[1]:
			var row: int = floori(float(i) / columns)
			var col: int = i % columns
			units.append(_spawn_unit(entry[0], peer,
					front - facing * row * SPACING + right * (col - (columns - 1) * 0.5) * SPACING))
			i += 1
	var rows: int = ceili(float(i) / columns)
	var names: Array = side.beasts
	var beasts: Array[Unit] = []
	for m in names.size():
		beasts.append(_spawn_unit(names[m], peer,
				front - facing * (rows * SPACING + 3.0) + right * (m - (names.size() - 1) * 0.5) * 5.0))
	if is_hero:
		battle.hero_beasts = beasts
	else:
		battle.enemy_beasts = beasts
	units.append_array(beasts)
	return units

func _spawn_unit(scene_name: String, peer: int, pos: Vector3) -> Unit:
	return main.unit_spawner.spawn({
		"scene_path": _scene_path(scene_name),
		"peer_id": peer,
		"tint": main.get_team_tint(peer),
		"position": pos,
	})

func _scene_path(scene_name: String) -> String:
	for folder in ["units", "units/beasts", "units/monsters", "units/gnolls", "units/dark_elves", "units/star_wanderers"]:
		var path: String = "res://scenes/%s/%s.tscn" % [folder, scene_name]
		if ResourceLoader.exists(path):
			return path
	push_error("cinematic_director: no scene for %s" % scene_name)
	return "res://scenes/units/soldier_unit.tscn"

func _order(peer: int, units: Array, pos: Vector3, facing: Vector3, columns: int, attack_move: bool = false) -> void:
	var paths: Array[NodePath] = []
	for u in units:
		if is_instance_valid(u):
			paths.append(u.get_path())
	main.issue_command_as(peer, paths, NodePath(), pos, attack_move, false,
			Formation.Type.BOX, (columns - 1) * SPACING, facing)

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

func _hide_health_bars() -> void:
	for battle in battles:
		for u in battle.get("hero_units", []) + battle.get("enemy_units", []):
			if is_instance_valid(u) and u.health_bar:
				u.health_bar.visible = false
	if village:
		for u in village._garrison:
			if is_instance_valid(u) and u.health_bar:
				u.health_bar.visible = false
