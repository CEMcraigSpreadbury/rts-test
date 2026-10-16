extends QuickDirector
## Quick trailer for the itch.io demo page (0.9.0): the HQ at work by day,
## a grown Dark Elf city, the HQ's torches by night, men setting a tower
## alight, a dragon's fire breath, then the big battle. See QuickDirector for
## how to preview and film it; the title card goes on in the edit.

const NIGHT_AMOUNT: float = 0.85
const CITY_NAME: String = "Objective12"
## Aldmere buildings round the hero's Town Centre: [scene, angle, distance].
const BASE_LAYOUT: Array = [
	["barracks_building", 30.0, 15.0], ["library_building", 75.0, 13.0], ["mill_building", 110.0, 14.0],
	["blacksmith_building", 145.0, 14.0], ["archery_range_building", 190.0, 15.0], ["storehouse_building", 235.0, 13.0],
	["stables_building", 280.0, 15.0], ["watchtower_building", 325.0, 13.0], ["bestiary_building", 0.0, 21.0],
]
const WORKERS: int = 10

const FIGHT_MEET: Vector3 = Vector3(-146, 0, -60)
const HALF_GAP: float = 5.0
const FIGHT_PRESPAWN: float = 4.4
const FIGHT_LEAD: float = 3.0
const COLUMNS: int = 14
const HERO_ROSTER: Array = [["shieldman_unit", 14], ["soldier_unit", 14], ["halberdier_unit", 14], ["archer_unit", 14], ["cavalier_unit", 8]]
const ENEMY_ROSTER: Array = [["beastman_warrior_unit", 14], ["beastman_panda_warrior_unit", 14], ["beastman_raider_unit", 14], ["beastman_wolf_pathfinder_unit", 14], ["beastman_wolf_rider_unit", 8]]

## The torch raid: men walk up to a Beastman tower and set it alight.
const RAIDERS: Array = [["soldier_unit", 6], ["spearman_unit", 6]]
const RAID_FROM: float = 9.0
const RAID_LEAD: float = 2.5
## The dragon: it stands off a Beastman warband and breathes on it.
const DRAGON_STANDOFF: float = 7.5
## Set down this long before its shot (the warband charges it on sight), and
## breathes this far into it.
const DRAGON_PRESPAWN: float = 1.5
const DRAGON_BREATH_AT: float = 0.4
const WARBAND: Array = [["beastman_warrior_unit", 8], ["beastman_raider_unit", 8], ["beastman_panda_warrior_unit", 8]]

var city: Objective
var base_centre: Vector3
var hero_units: Array = []
var enemy_units: Array = []
var raid_spot: Vector3
var dragon_spot: Vector3
var tower: Node3D
var raiders: Array = []
var dragon: Unit
var warband: Array = []
var workers: Array = []
var _fight_spawned: bool = false
var _fight_started: bool = false
var _raid_started: bool = false
var _breathed: bool = false

func _init() -> void:
	shots = [
		{"len": 5.0, "subject": "base", "night": 0.0, "from": [20.0, 34.0, 34.0, Vector3(0, 0, 2)], "to": [58.0, 28.0, 25.0, Vector3.ZERO]},
		{"len": 4.5, "subject": "workers", "night": 0.0, "from": [0.0, 38.0, 14.0, Vector3.ZERO], "to": [15.0, 35.0, 12.0, Vector3.ZERO]},
		{"len": 4.5, "subject": "city", "night": 0.0, "from": [-40.0, 24.0, 24.0, Vector3(-2, 0, 2)], "to": [-8.0, 27.0, 18.0, Vector3.ZERO]},
		{"len": 4.5, "subject": "base", "night": NIGHT_AMOUNT, "from": [70.0, 20.0, 16.0, Vector3(1, 0, 1)], "to": [35.0, 23.0, 12.0, Vector3(-1, 0, 0)]},
		{"len": 5.0, "subject": "raid", "night": 0.0, "from": [0.0, 22.0, 9.5, Vector3(-1, 0, 0)], "to": [0.0, 20.0, 7.5, Vector3(0.5, 0, 0)]},
		{"len": 5.0, "subject": "dragon", "night": 0.0, "from": [0.0, 20.0, 15.0, Vector3.ZERO], "to": [0.0, 24.0, 13.0, Vector3(1, 0, 0)]},
		{"len": 6.0, "subject": "fight", "night": 0.0, "from": [-35.0, 21.0, 12.0, Vector3(-2, 0, 1)], "to": [-10.0, 24.0, 10.0, Vector3.ZERO]},
		{"len": 5.5, "subject": "fight", "night": 0.0, "from": [-10.0, 24.0, 10.0, Vector3.ZERO], "to": [14.0, 48.0, 46.0, Vector3(2, 0, -3)]},
	]

func _stage() -> void:
	for res in [RealmEconomy.FOOD, AiPlayer.GOLD, AiPlayer.WOOD, Research.RESOURCE]:
		ResourceStockpile.add(hero, res, 99999)
	_build_base()
	_grow_city()
	await get_tree().process_frame
	_put_workers_on_trees()
	var forest: Forest = Forest.active
	raid_spot = _open_spot(forest, FIGHT_MEET, [])
	dragon_spot = _open_spot(forest, FIGHT_MEET, [raid_spot])
	## Side-on to each set piece.
	aim("raid", Vector3.FORWARD)
	aim("dragon", Vector3.FORWARD)
	_stage_raid()
	## Side-on to the line from the hall out to the woodcutters.
	var out: Vector3 = (centre_of(workers, base_centre) - base_centre).normalized()
	aim("workers", Vector3(out.z, 0, -out.x))

func _tick() -> void:
	if not _raid_started and t >= shot_start("raid") - RAID_LEAD:
		_raid_started = true
		_attack(hero, raiders, tower)
	if dragon == null and t >= shot_start("dragon") - DRAGON_PRESPAWN:
		_stage_dragon()
	if not _breathed and t >= shot_start("dragon") + DRAGON_BREATH_AT and is_instance_valid(dragon):
		_breathed = main.request_ability_as(hero, dragon.get_path(), 0, centre_of(warband, dragon_spot))
	var fight_at: float = shot_start("fight")
	if not _fight_spawned and t >= fight_at - FIGHT_PRESPAWN:
		_fight_spawned = true
		_spawn_fight()
	if not _fight_started and t >= fight_at - FIGHT_LEAD:
		_fight_started = true
		order(hero, hero_units, FIGHT_MEET, Vector3.RIGHT, COLUMNS, true)
		order(enemy, enemy_units, FIGHT_MEET, Vector3.LEFT, COLUMNS, true)
	if city:
		city.progress_disc.visible = false

func _subject(which: String) -> Vector3:
	match which:
		"base":
			return base_centre
		"workers":
			return centre_of(workers, base_centre)
		"city":
			return city.global_position if city else Vector3.ZERO
		"raid":
			return raid_spot + Vector3.LEFT * 3.0
		"dragon":
			return dragon_spot + Vector3.LEFT * DRAGON_STANDOFF * 0.4
		_:
			return centre_of(hero_units + enemy_units, FIGHT_MEET)

## --- Staging ---

func _toward() -> Vector3:
	var angle: float = atan2(-base_centre.x, -base_centre.z)
	return Vector3(sin(angle), 0, cos(angle))

func _build_base() -> void:
	var tc: Node3D = main.town_centers.get(hero)
	base_centre = tc.global_position if tc else Vector3(-278, 0, 278)
	var toward: float = atan2(-base_centre.x, -base_centre.z)
	for entry in BASE_LAYOUT:
		var angle: float = toward + deg_to_rad(entry[1])
		var pos: Vector3 = base_centre + Vector3(sin(angle), 0, cos(angle)) * entry[2]
		pos.y = height(pos)
		main.building_spawner.spawn({
			"scene_path": "res://scenes/buildings/%s.tscn" % entry[0],
			"peer_id": hero,
			"position": pos,
			"tint": main.get_team_tint(hero),
		})

## Villagers out on the trees behind the hall, each on his own trunk.
func _put_workers_on_trees() -> void:
	var forest: Forest = Forest.active
	if forest == null:
		return
	var trees: Array = forest.trees_in_circle(base_centre, 40.0)
	trees.sort_custom(func(a, b): return a.global_position.distance_to(base_centre) < b.global_position.distance_to(base_centre))
	for i in mini(WORKERS, trees.size()):
		var tree: Node3D = trees[i]
		var villager := spawn_unit("unit", hero, tree.global_position.lerp(base_centre, 0.15))
		workers.append(villager)
		var paths: Array[NodePath] = [villager.get_path()]
		main.issue_command_as(hero, paths, tree.get_path(), tree.global_position, false, false)

func _grow_city() -> void:
	for node in get_tree().get_nodes_in_group(&"objectives"):
		if node.name == CITY_NAME:
			city = node
	if city == null:
		push_error("itch_director: no %s" % CITY_NAME)
		return
	city.guard_respawn_delay = 9999.0
	for guard in city._guards:
		if is_instance_valid(guard):
			guard.queue_free()
	city._guards.clear()
	city._set_owner(hero)
	city.resolve_choice(Objective.Choice.OCCUPY)
	city.flag_peer_id = hero
	city.flag_control = 1.0
	city.raise_tier(Objective.Tier.TOWN)
	city.raise_tier(Objective.Tier.CITY)
	var by_name := {}
	var items: Array[ProducibleItem] = city._slot_options()
	for item in items:
		by_name[item.item_name] = item
	city.place_slot(items[0])
	city.place_slot(by_name[Objective.MARKET])
	city.place_slot(by_name[Objective.WATCHTOWER])
	city.place_slot(by_name[Objective.WALLS])

func _stage_raid() -> void:
	tower = main.building_spawner.spawn({
		"scene_path": "res://scenes/buildings/beastmen_barracks_building.tscn",
		"peer_id": enemy,
		"position": Vector3(raid_spot.x, height(raid_spot), raid_spot.z),
		"tint": main.get_team_tint(enemy),
	})
	## Stands up to the raid for the length of the shot.
	tower.max_health = 5000
	tower.current_health = 5000
	raiders = spawn_block(hero, raid_spot + Vector3.LEFT * RAID_FROM, Vector3.RIGHT, RAIDERS, 4)

func _stage_dragon() -> void:
	dragon = spawn_unit("black_dragon_unit", hero, dragon_spot + Vector3.LEFT * DRAGON_STANDOFF)
	dragon.rotation.y = PI * 0.5
	warband = spawn_block(enemy, dragon_spot, Vector3.LEFT, WARBAND, 8)
	## They only stand and burn: a mobbed dragon flashes white with every hit
	## it takes, and the shot is about the fire.
	for u in warband:
		u.can_fight = false

func _attack(peer: int, units: Array, target: Node3D) -> void:
	var paths: Array[NodePath] = []
	for u in units:
		if is_instance_valid(u):
			paths.append(u.get_path())
	main.issue_command_as(peer, paths, target.get_path(), target.global_position, false, false)

## Flat grass clear of trees and everything else, searched outward from `near`
## and far enough from the battle that its wide shots never show it.
func _open_spot(forest: Forest, near: Vector3, taken: Array) -> Vector3:
	var blockers: Array = taken.duplicate()
	blockers.append(FIGHT_MEET)
	for group in [&"buildings", &"objectives"]:
		for node in get_tree().get_nodes_in_group(group):
			if node is Node3D:
				blockers.append(node.global_position)
	for radius in range(70, 180, 6):
		for step in 24:
			var angle: float = TAU * step / 24.0
			var p: Vector3 = near + Vector3(sin(angle), 0, cos(angle)) * radius
			if forest != null and forest.any_trunk_within(p, 16.0):
				continue
			if blockers.any(func(b): return Vector2(b.x - p.x, b.z - p.z).length() < 30.0):
				continue
			var h: float = height(p)
			var flat: bool = h > -0.3
			for k in 8:
				var q: Vector3 = p + Vector3(sin(k * TAU / 8), 0, cos(k * TAU / 8)) * 12.0
				if absf(height(q) - h) > 0.8:
					flat = false
			if flat:
				p.y = h
				return p
	push_error("itch_director: no open spot")
	return near

func _spawn_fight() -> void:
	hero_units = spawn_block(hero, FIGHT_MEET + Vector3.LEFT * HALF_GAP, Vector3.RIGHT, HERO_ROSTER, COLUMNS)
	enemy_units = spawn_block(enemy, FIGHT_MEET + Vector3.RIGHT * HALF_GAP, Vector3.LEFT, ENEMY_ROSTER, COLUMNS)
	await get_tree().process_frame
	order(hero, hero_units, FIGHT_MEET + Vector3.LEFT * HALF_GAP, Vector3.RIGHT, COLUMNS, false)
	order(enemy, enemy_units, FIGHT_MEET + Vector3.RIGHT * HALF_GAP, Vector3.LEFT, COLUMNS, false)
