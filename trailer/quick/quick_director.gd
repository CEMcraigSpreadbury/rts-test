extends QuickDirector
## Quick trailer: a built-up HQ by day and night, a grown Dark Elf city, one
## battle. See QuickDirector for how to preview and film it.

const NIGHT_AMOUNT: float = 0.85

const CITY_NAME: String = "Objective12"
## Aldmere buildings set round the hero's Town Centre: [scene, angle, distance].
const BASE_LAYOUT: Array = [
	["barracks_building", 30.0, 15.0], ["house_building", 75.0, 12.0], ["house_building", 100.0, 13.0],
	["blacksmith_building", 140.0, 14.0], ["archery_range_building", 190.0, 15.0], ["house_building", 235.0, 12.0],
	["stables_building", 280.0, 15.0], ["watchtower_building", 325.0, 13.0], ["mill_building", 0.0, 21.0],
	["farm_building", 345.0, 28.0], ["farm_building", 15.0, 28.0], ["storehouse_building", 210.0, 24.0],
]

## Open grass; the two blocks start HALF_GAP either side and attack-move in.
const FIGHT_MEET: Vector3 = Vector3(-146, 0, -60)
const HALF_GAP: float = 5.0
const FIGHT_PRESPAWN: float = 4.4
const FIGHT_LEAD: float = 3.0
const COLUMNS: int = 14
const HERO_ROSTER: Array = [["shieldman_unit", 14], ["soldier_unit", 14], ["halberdier_unit", 14], ["archer_unit", 14], ["cavalier_unit", 8]]
const ENEMY_ROSTER: Array = [["beastman_warrior_unit", 14], ["beastman_panda_warrior_unit", 14], ["beastman_raider_unit", 14], ["beastman_wolf_pathfinder_unit", 14], ["beastman_wolf_rider_unit", 8]]

var city: Objective
var base_centre: Vector3
var hero_units: Array = []
var enemy_units: Array = []
var _fight_spawned: bool = false
var _fight_started: bool = false

func _init() -> void:
	shots = [
		{"len": 4.5, "subject": "base", "night": 0.0, "from": [20.0, 32.0, 30.0, Vector3(0, 0, 2)], "to": [62.0, 27.0, 23.0, Vector3.ZERO]},
		{"len": 4.5, "subject": "city", "night": 0.0, "from": [-40.0, 24.0, 24.0, Vector3(-2, 0, 2)], "to": [-8.0, 27.0, 18.0, Vector3.ZERO]},
		{"len": 4.5, "subject": "base", "night": NIGHT_AMOUNT, "from": [70.0, 20.0, 16.0, Vector3(1, 0, 1)], "to": [35.0, 23.0, 12.0, Vector3(-1, 0, 0)]},
		{"len": 3.5, "subject": "city", "night": NIGHT_AMOUNT, "from": [150.0, 30.0, 22.0, Vector3.ZERO], "to": [170.0, 36.0, 28.0, Vector3.ZERO]},
		{"len": 6.0, "subject": "fight", "night": 0.0, "from": [-35.0, 21.0, 12.0, Vector3(-2, 0, 1)], "to": [-10.0, 24.0, 10.0, Vector3.ZERO]},
		{"len": 4.0, "subject": "fight", "night": 0.0, "from": [-10.0, 24.0, 10.0, Vector3.ZERO], "to": [14.0, 48.0, 46.0, Vector3(2, 0, -3)]},
	]

func _stage() -> void:
	_build_base()
	_grow_city()

func _tick() -> void:
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
		"city":
			return city.global_position if city else Vector3.ZERO
		_:
			return centre_of(hero_units + enemy_units, FIGHT_MEET)

## --- Staging ---

func _build_base() -> void:
	var tc: Node3D = main.town_centers.get(hero)
	base_centre = tc.global_position if tc else Vector3(-278, 0, 278)
	## Built toward the map's middle, where there is room.
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

func _grow_city() -> void:
	for node in get_tree().get_nodes_in_group(&"objectives"):
		if node.name == CITY_NAME:
			city = node
	if city == null:
		push_error("quick_director: no %s" % CITY_NAME)
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

func _spawn_fight() -> void:
	hero_units = spawn_block(hero, FIGHT_MEET + Vector3.LEFT * HALF_GAP, Vector3.RIGHT, HERO_ROSTER, COLUMNS)
	enemy_units = spawn_block(enemy, FIGHT_MEET + Vector3.RIGHT * HALF_GAP, Vector3.LEFT, ENEMY_ROSTER, COLUMNS)
	await get_tree().process_frame
	order(hero, hero_units, FIGHT_MEET + Vector3.LEFT * HALF_GAP, Vector3.RIGHT, COLUMNS, false)
	order(enemy, enemy_units, FIGHT_MEET + Vector3.RIGHT * HALF_GAP, Vector3.LEFT, COLUMNS, false)
