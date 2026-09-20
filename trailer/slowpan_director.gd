extends Node
## 10s atmosphere piece on Aethermoor Creek: three slow, low pans over the map
## with the units standing still — a river bank, a building site where the
## villagers pop into their builder and lumberjack costumes, and a company
## drawn up on open grass. Nothing fights; every unit belongs to one player.
## Run: godot --path . --write-movie out.png --fixed-fps 30 res://trailer/slowpan_boot.tscn
## Movie Maker ignores --resolution; size it with an override.cfg setting
## display/window/size/window_width_override=1920 and window_height_override=1080.
## Prints TRAILER_START_FRAME / TRAILER_END_FRAME so the warm-up can be trimmed.

const WARMUP_FRAMES: int = 150
const END: float = 10.0
const CUT_SITE: float = 3.3
const CUT_FIELD: float = 6.9
const DIP: float = 0.15

const COLUMNS: int = 14
const SPACING: float = 1.3

## Shot 1: a line drawn up on the creek's west bank, looking east over the water.
const BANK_FRONT: Vector3 = Vector3(-37, 0, 22)
const FAR_BANK_FRONT: Vector3 = Vector3(-16, 0, 22)

## Shot 2: a barracks going up on the grass north of the pond. The villagers
## wait in a row in front of it and are put to work one after another, so the
## costume pops ripple across the shot instead of landing all at once.
const SITE_BUILDING: Vector3 = Vector3(-28, 0, 62)
const SITE_ROW_Z: float = 58.0
const SITE_ROW_X: float = -28.0
const BUILDERS: int = 5
const WOODCUTTERS: int = 2
const SITE_VILLAGERS: int = BUILDERS + WOODCUTTERS
const SITE_VILLAGER_GAP: float = 2.1
## Long enough that the site is still a frame of scaffolding at the end of
## the shot rather than a finished barracks.
const SITE_BUILD_TIME: float = 90.0
const SITE_START_PROGRESS: float = 0.4
const FIRST_POP_AT: float = 4.3
const POP_GAP: float = 0.18

## Shot 3: a company standing at ease on the open field in the south-east.
const FIELD_FRONT: Vector3 = Vector3(30, 0, -62)

## Each shot: [start, end, from, to] where from/to are [pivot, yaw, pitch, zoom].
## Low pitches and small zooms keep the lens near the grass; the pivot crawls
## a couple of metres a second, which is the whole point of the piece.
var shots: Array = [
	[0.0, CUT_SITE,
		[Vector3(-34, 0, 17.0), -97.0, 16.0, 14.0], [Vector3(-34, 0, 25.0), -85.0, 19.0, 16.0]],
	[CUT_SITE, CUT_FIELD,
		[Vector3(-32, 0, 58.0), 176.0, 19.0, 10.0], [Vector3(-24, 0, 58.5), 188.0, 23.0, 12.0]],
	[CUT_FIELD, END,
		[Vector3(26, 0, -64.0), -46.0, 16.0, 12.0], [Vector3(32, 0, -64.0), -33.0, 19.0, 14.0]],
]

## [scene name, count] per line, and how many ranks deep the block stands.
const BANK_ROSTER: Array = [["shieldman_unit", 14], ["sw_spearman_unit", 14], ["archer_unit", 14], ["wizard_unit", 7]]
const FAR_BANK_ROSTER: Array = [["gnoll_warrior_unit", 14], ["gnoll_archer_unit", 14]]
const FIELD_ROSTER: Array = [["shieldman_unit", 14], ["sw_knight_unit", 14], ["archer_unit", 14],
	["arch_mage_unit", 7]]

var main: Main
var hero: int = 1
var t: float = -0.3
var running: bool = false
var fade: ColorRect
var villagers: Array[Unit] = []
var site: ProductionBuilding
var popped: int = 0
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
	_clear_guards()
	_clear_wildlife()

	_spawn_block(BANK_FRONT, Vector3.RIGHT, BANK_ROSTER)
	_spawn_block(FAR_BANK_FRONT, Vector3.LEFT, FAR_BANK_ROSTER)
	_spawn_block(FIELD_FRONT, Vector3.LEFT, FIELD_ROSTER)
	_spawn_site()
	_update_camera()
	for i in WARMUP_FRAMES:
		await get_tree().process_frame
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
	t += delta
	_update_camera()
	_update_overlay()
	_label_timer -= delta
	if _label_timer <= 0.0:
		_label_timer = 0.5
		_hide_labels()
	while popped < villagers.size() and t >= FIRST_POP_AT + POP_GAP * popped:
		_put_to_work(popped)
		popped += 1
	if t >= END:
		print("TRAILER_END_FRAME=%d" % Engine.get_process_frames())
		get_tree().quit()

func _update_camera() -> void:
	for shot in shots:
		if t < shot[1] or shot == shots[-1]:
			var k: float = clampf(inverse_lerp(shot[0], shot[1], t), 0.0, 1.0)
			## Eased at both ends only enough to take the edge off the start
			## and stop; the middle stays a steady crawl.
			k = lerpf(k, k * k * (3.0 - 2.0 * k), 0.35)
			var a: Array = shot[2]
			var b: Array = shot[3]
			_set_camera(a[0].lerp(b[0], k), lerpf(a[1], b[1], k), lerpf(a[2], b[2], k), lerpf(a[3], b[3], k))
			return

## Fade in, a dip through black at each cut, fade out.
func _update_overlay() -> void:
	var alpha: float = 1.0 - clampf(t / 0.5, 0.0, 1.0)
	for cut in [CUT_SITE, CUT_FIELD]:
		alpha = maxf(alpha, 1.0 - clampf(absf(t - cut) / DIP, 0.0, 1.0))
	alpha = maxf(alpha, clampf((t - (END - 0.55)) / 0.5, 0.0, 1.0))
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

## Ranks of COLUMNS stacked back from `front`, then ordered onto that same
## ground so they settle into their exact slots and stand there facing one way.
func _spawn_block(front: Vector3, facing: Vector3, roster: Array) -> void:
	var right := Vector3(facing.z, 0, -facing.x)
	var units: Array[Unit] = []
	var i: int = 0
	for entry in roster:
		for n in entry[1]:
			var row: int = floori(float(i) / COLUMNS)
			var col: int = i % COLUMNS
			units.append(_spawn_unit(entry[0], front - facing * row * SPACING
					+ right * (col - (COLUMNS - 1) * 0.5) * SPACING))
			i += 1
	var paths: Array[NodePath] = []
	for u in units:
		paths.append(u.get_path())
	main.issue_command_as(hero, paths, NodePath(), front, false, false,
			Formation.Type.BOX, (COLUMNS - 1) * SPACING, facing)

## The barracks is put straight back into its under-construction state, so the
## villagers have something real to be sent to.
func _spawn_site() -> void:
	site = main.building_spawner.spawn({
		"scene_path": "res://scenes/buildings/barracks_building.tscn",
		"peer_id": hero,
		"position": SITE_BUILDING,
		"tint": main.get_team_tint(hero),
	})
	site.begin_construction(SITE_BUILD_TIME)
	## Started part-raised: at zero progress the site is a flat outline on the
	## grass, and the shot wants a half-built barracks to send them to.
	site.construction_progress = SITE_START_PROGRESS
	for i in SITE_VILLAGERS:
		var offset: float = (i - (SITE_VILLAGERS - 1) * 0.5) * SITE_VILLAGER_GAP
		villagers.append(_spawn_unit("unit", Vector3(SITE_ROW_X + offset, 0, SITE_ROW_Z)))

## Most of the row walks onto the scaffolding; the last couple go for the
## trees instead, so the lumberjack costume gets its moment too.
func _put_to_work(index: int) -> void:
	var villager: Unit = villagers[index]
	if not is_instance_valid(villager):
		return
	if index < BUILDERS:
		villager.command_build(site)
		return
	var tree: Gatherable = _nearest_tree(villager.global_position)
	if tree:
		villager.command_gather(tree, main._get_dropoff_for(hero))

func _nearest_tree(from: Vector3) -> Gatherable:
	var best: Gatherable = null
	for node in get_tree().get_nodes_in_group("gatherables"):
		var tree := node as Gatherable
		if tree == null or not tree.can_be_gathered() or not tree.can_accept_gatherer():
			continue
		if best == null or tree.global_position.distance_to(from) < best.global_position.distance_to(from):
			best = tree
	return best

func _spawn_unit(scene_name: String, pos: Vector3) -> Unit:
	return main.unit_spawner.spawn({
		"scene_path": _scene_path(scene_name),
		"peer_id": hero,
		"tint": main.get_team_tint(hero),
		"position": pos,
	})

func _scene_path(scene_name: String) -> String:
	for folder in ["units", "units/monsters", "units/gnolls", "units/dark_elves", "units/star_wanderers"]:
		var path: String = "res://scenes/%s/%s.tscn" % [folder, scene_name]
		if ResourceLoader.exists(path):
			return path
	push_error("slowpan_director: no scene for %s" % scene_name)
	return "res://scenes/units/soldier_unit.tscn"

func _hide_labels() -> void:
	for label in main.find_children("*", "Label3D", true, false):
		label.visible = false

## Wandering boars and deer crowd the low, close shots — cleared out of the
## three filmed spots only, so the rest of the map keeps its wildlife.
func _clear_wildlife() -> void:
	for child in main.units_root.get_children():
		var animal := child as Unit
		if animal == null or animal.owner_peer_id > 0:
			continue
		for spot in [BANK_FRONT, SITE_BUILDING, FIELD_FRONT]:
			if animal.global_position.distance_to(spot) < 22.0:
				animal.queue_free()
				break

## Keeps neutral shrine guards from wandering into a shot nothing fights in.
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
