extends QuickDirector
## Quick trailer, locked-off shots: villagers mining gold, chopping wood and
## raising buildings round the HQ, farms, then an army marching out of the
## base and, after the cut, that army walking into a Beastman host.
## See QuickDirector for how to preview and film it.

## Aldmere buildings already standing, as offsets from the Town Centre in
## (along the way out to the map's middle, to its right).
const BASE_LAYOUT: Array = [
	["barracks_building", Vector2(14, 12)], ["archery_range_building", Vector2(14, -12)],
	["house_building", Vector2(-2, 14)], ["house_building", Vector2(-10, 12)], ["house_building", Vector2(-2, -13)],
	["blacksmith_building", Vector2(-14, 2)], ["storehouse_building", Vector2(-12, -10)],
]
## The work spots are staged on open meadow found round the base, each laid
## out for one camera looking along VIEW_YAW. Offsets are (ahead of the
## camera, to its right) from the spot's centre.
const VIEW_YAW: float = 28.0
const SPOT_CLEAR: float = 16.0
const GROVE: Array = [Vector2(5, -5), Vector2(6.5, -1.5), Vector2(5, 2), Vector2(7, 5), Vector2(9, -3), Vector2(9.5, 1.5)]
const GROVE_STORE: Vector2 = Vector2(-3, 6)
const DEPOSIT: Vector2 = Vector2(3, -4)
const MINE_STORE: Vector2 = Vector2(-1, 6)
const MILL: Vector2 = Vector2(4, 5)
const FIELDS: Array = [Vector2(3, -2.5), Vector2(-3, -2.5), Vector2(-3, 3.5), Vector2(-2, -8.5)]
## Construction sites: [scene, offset, seconds to finish with its builders].
const SITES: Array = [
	["house_building", Vector2(3, -6), 9.0], ["stables_building", Vector2(-2, 3), 13.0], ["watchtower_building", Vector2(5, 6), 22.0],
]
const BUILDERS_PER_SITE: int = 3

const COLUMNS: int = 12
const HERO_ROSTER: Array = [["shieldman_unit", 12], ["soldier_unit", 12], ["spearman_unit", 12], ["archer_unit", 12], ["cavalier_unit", 8]]
const ENEMY_ROSTER: Array = [["beastman_warrior_unit", 12], ["beastman_panda_warrior_unit", 12], ["beastman_raider_unit", 12], ["beastman_wolf_pathfinder_unit", 12], ["beastman_wolf_rider_unit", 8]]

## The march out: the army forms up this far along the way out, then walks.
const MARCH_FROM: float = 6.0
const MARCH_CAMERA: float = 30.0
## The battle: the army walks in from WALK_IN west of the meeting point while
## the Beastmen hold ENEMY_GAP east of it, then both close.
const FIGHT_MEET: Vector3 = Vector3(-146, 0, -60)
const WALK_IN: float = 24.0
const ENEMY_GAP: float = 9.0
const CLOSE_AFTER: float = 5.0

var base_centre: Vector3
var out_dir: Vector3
var out_right: Vector3
## Centre of each staged work spot, by shot subject.
var spots: Dictionary = {}
var view_fwd: Vector3
var view_right: Vector3
var march_units: Array = []
var hero_units: Array = []
var enemy_units: Array = []
var _sites_started: bool = false
var _march_spawned: bool = false
var _march_started: bool = false
var _march_cleared: bool = false
var _fight_spawned: bool = false
var _fight_walking: bool = false
var _fight_closed: bool = false

func _init() -> void:
	shots = [
		{"len": 7.0, "subject": "wood", "night": 0.0, "locked": true, "from": [0.0, 29.0, 11.5, Vector3.ZERO], "to": [3.0, 28.0, 11.0, Vector3.ZERO]},
		{"len": 9.0, "subject": "build", "night": 0.0, "locked": true, "from": [0.0, 30.0, 16.0, Vector3.ZERO], "to": [3.0, 29.0, 15.0, Vector3.ZERO]},
		{"len": 7.0, "subject": "gold", "night": 0.0, "locked": true, "from": [0.0, 30.0, 14.0, Vector3.ZERO], "to": [3.0, 29.0, 13.5, Vector3.ZERO]},
		{"len": 6.0, "subject": "farms", "night": 0.0, "locked": true, "from": [0.0, 31.0, 14.0, Vector3.ZERO], "to": [3.0, 30.0, 13.5, Vector3.ZERO]},
		{"len": 10.0, "subject": "march", "night": 0.0, "locked": true, "from": [135.0, 21.0, 22.0, Vector3.ZERO], "to": [137.0, 22.0, 21.0, Vector3.ZERO]},
		{"len": 9.0, "subject": "advance", "night": 0.0, "locked": true, "from": [0.0, 22.0, 15.0, Vector3.ZERO], "to": [2.0, 22.0, 14.5, Vector3.ZERO]},
		{"len": 9.0, "subject": "clash", "night": 0.0, "locked": true, "from": [-20.0, 22.0, 13.0, Vector3.ZERO], "to": [-17.0, 22.0, 12.5, Vector3.ZERO]},
		{"len": 6.0, "subject": "clash", "night": 0.0, "locked": true, "from": [-17.0, 22.0, 12.5, Vector3.ZERO], "to": [0.0, 44.0, 40.0, Vector3(0, 0, -2)]},
	]

func _subject(which: String) -> Vector3:
	match which:
		"march":
			return base_centre + out_dir * MARCH_CAMERA * 0.6
		"advance":
			return FIGHT_MEET + Vector3.LEFT * 6.0
		"clash":
			return FIGHT_MEET
		"wood":
			return spots.wood + view_fwd * 3.5
		_:
			return spots.get(which, base_centre)

func _at(offset: Vector2) -> Vector3:
	var pos: Vector3 = base_centre + out_dir * offset.x + out_right * offset.y
	pos.y = height(pos)
	return pos

## A point laid out for the shot cameras, from a spot's centre.
func _in_view(centre: Vector3, offset: Vector2) -> Vector3:
	var pos: Vector3 = centre + view_fwd * offset.x + view_right * offset.y
	pos.y = height(pos)
	return pos

## --- Staging ---

func _stage() -> void:
	var tc: Node3D = main.town_centers.get(hero)
	base_centre = tc.global_position if tc else Vector3(-278, 0, 278)
	out_dir = Vector3(-base_centre.x, 0, -base_centre.z).normalized()
	out_right = Vector3(out_dir.z, 0, -out_dir.x)
	var yaw: float = deg_to_rad(VIEW_YAW)
	view_fwd = Vector3(-sin(yaw), 0, -cos(yaw))
	view_right = Vector3(cos(yaw), 0, -sin(yaw))
	for shot in shots:
		if shot.subject in ["wood", "build", "gold", "farms"]:
			aim(shot.subject, view_fwd)
	for entry in BASE_LAYOUT:
		_place(entry[0], _at(entry[1]))
	## Every one of the base's own villagers is replaced by the staged ones.
	for u in get_tree().get_nodes_in_group(&"units"):
		if u is Unit and u.owner_peer_id == hero:
			u.queue_free()
	await get_tree().process_frame
	var forest: Forest = main.find_children("*", "Forest", true, false)[0]
	for subject in ["wood", "gold", "farms", "build"]:
		spots[subject] = _find_spot(forest)
		print("TRAILER_SPOT %s %s" % [subject, spots[subject]])

	var wood: Vector3 = spots.wood
	## A spawned tree joins the forest its parent names, which the spawner's
	## node doesn't; without this it would draw into a forest nobody shows.
	main.building_spawner.get_node(main.building_spawner.spawn_path).set_meta(&"forest", forest)
	var trees: Array = []
	for offset in GROVE:
		var jitter := Vector2(randf_range(-0.6, 0.6), randf_range(-0.6, 0.6))
		trees.append(main.building_spawner.spawn({
			"scene_path": "res://scenes/resource_nodes/gatherable.tscn",
			"peer_id": 0,
			"position": _in_view(wood, offset + jitter),
		}))
	_place("storehouse_building", _in_view(wood, GROVE_STORE))

	var gold: Vector3 = spots.gold
	var deposit: Gatherable = main.building_spawner.spawn({
		"scene_path": "res://scenes/resource_nodes/gold_deposit.tscn",
		"peer_id": 0,
		"position": _in_view(gold, DEPOSIT),
	})
	deposit.is_claimed = true
	## Normally set when the Mine finishes building; this one never was.
	deposit.has_required_building = true
	var mine: Node = main.building_spawner.spawn({
		"scene_path": "res://scenes/buildings/mine_building.tscn",
		"peer_id": hero,
		"position": deposit.global_position,
		"tint": main.get_team_tint(hero),
		"deposit_path": deposit.get_path(),
	})
	_place("storehouse_building", _in_view(gold, MINE_STORE))

	var farms: Vector3 = spots.farms
	_place("mill_building", _in_view(farms, MILL))
	var fields: Array = []
	for offset in FIELDS:
		fields.append(_place("farm_building", _in_view(farms, offset)))

	await get_tree().process_frame
	await get_tree().process_frame
	## Miners hop into the Mine and carry their loads to the Storehouse.
	_villagers_on(mine, 6)
	for tree in trees.slice(0, 3):
		_villagers_on(tree, 2)
	for field in fields:
		_villagers_on(field, 1)

## Open, flat meadow near the base: no trees, buildings, resources or
## settlements within SPOT_CLEAR, off the army's road out, and clear of the
## spots already taken.
func _find_spot(forest: Forest) -> Vector3:
	var blockers: Array = []
	for group in [&"buildings", &"gatherables", &"objectives"]:
		for node in get_tree().get_nodes_in_group(group):
			if node is Node3D:
				blockers.append(node.global_position)
	blockers.append_array(spots.values())
	for radius in range(34, 110, 6):
		for step in 24:
			var angle: float = TAU * step / 24.0
			var p: Vector3 = base_centre + Vector3(sin(angle), 0, cos(angle)) * radius
			var rel: Vector3 = p - base_centre
			if rel.dot(out_dir) > 0.0 and absf(rel.dot(out_right)) < 22.0:
				continue
			if forest.any_trunk_within(p, SPOT_CLEAR):
				continue
			if blockers.any(func(b): return Vector2(b.x - p.x, b.z - p.z).length() < SPOT_CLEAR + 4.0):
				continue
			var h: float = height(p)
			var flat: bool = h > -0.3
			for k in 8:
				var q: Vector3 = p + Vector3(sin(k * TAU / 8), 0, cos(k * TAU / 8)) * 10.0
				if absf(height(q) - h) > 0.8:
					flat = false
			if flat:
				p.y = h
				return p
	push_error("economy_director: no open spot")
	return base_centre

func _place(scene: String, pos: Vector3) -> Node:
	return main.building_spawner.spawn({
		"scene_path": "res://scenes/buildings/%s.tscn" % scene,
		"peer_id": hero,
		"position": pos,
		"tint": main.get_team_tint(hero),
	})

## `count` villagers stood round `target`, sent to work it.
func _villagers_on(target: Node3D, count: int) -> Array:
	var villagers: Array = []
	if target == null:
		return villagers
	var paths: Array[NodePath] = []
	for i in count:
		var angle: float = TAU * float(i) / count + randf() * 0.5
		var u := spawn_unit("unit", hero, target.global_position + Vector3(cos(angle), 0, sin(angle)) * 4.0)
		villagers.append(u)
		paths.append(u.get_path())
	main.issue_command_as.call_deferred(hero, paths, target.get_path(), target.global_position, false, false)
	return villagers

func _start_sites() -> void:
	for entry in SITES:
		var site: ProductionBuilding = _place(entry[0], _in_view(spots.build, entry[1]))
		site.begin_construction(entry[2] * BUILDERS_PER_SITE)
		_villagers_on(site, BUILDERS_PER_SITE)

## --- Timeline ---

func _tick() -> void:
	if not _sites_started and t >= shot_start("build") - 2.5:
		_sites_started = true
		_start_sites()
	var march_at: float = shot_start("march")
	if not _march_spawned and t >= march_at - 4.0:
		_march_spawned = true
		march_units = spawn_block(hero, base_centre + out_dir * MARCH_FROM, out_dir, HERO_ROSTER, COLUMNS)
	if not _march_started and t >= march_at - 0.5:
		_march_started = true
		order(hero, march_units, base_centre + out_dir * 120.0, out_dir, COLUMNS, false)
	var advance_at: float = shot_start("advance")
	if not _march_cleared and t >= advance_at + 0.5:
		_march_cleared = true
		for u in march_units:
			if is_instance_valid(u):
				u.queue_free()
	if not _fight_spawned and t >= advance_at - 4.0:
		_fight_spawned = true
		hero_units = spawn_block(hero, FIGHT_MEET + Vector3.LEFT * WALK_IN, Vector3.RIGHT, HERO_ROSTER, COLUMNS)
		enemy_units = spawn_block(enemy, FIGHT_MEET + Vector3.RIGHT * ENEMY_GAP, Vector3.LEFT, ENEMY_ROSTER, COLUMNS)
	if not _fight_walking and t >= advance_at - 0.5:
		_fight_walking = true
		order(hero, hero_units, FIGHT_MEET + Vector3.LEFT * 3.0, Vector3.RIGHT, COLUMNS, false)
	if not _fight_closed and t >= advance_at + CLOSE_AFTER:
		_fight_closed = true
		order(hero, hero_units, FIGHT_MEET, Vector3.RIGHT, COLUMNS, true)
		order(enemy, enemy_units, FIGHT_MEET, Vector3.LEFT, COLUMNS, true)
