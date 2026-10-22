class_name RealmRoster
extends RefCounted
## Which units each people trains in a Realm settlement's military buildings,
## and what raising a slot building's level does.
## A settlement offers a Barracks, Range, Stables, Sanctum and Bestiary only where its
## people have units of that kind; the hall itself trains nobody. Each list is
## in level order: the first unit comes with the building, the next with each
## level. A line with no next unit gets its elite instead (tougher, harder
## hitting, drawn a size up), and a level past that trains faster.

enum Kind { BARRACKS, RANGE, STABLES, SANCTUM, BESTIARY }
const KIND_NAMES: Array[String] = ["Barracks", "Range", "Stables", "Sanctum", "Bestiary"]
## Each kind's UiGlyphs icon on a settlement hall's menu: one per kind of
## building, whatever race puts it up, like the capital's own.
const KIND_GLYPHS: Array[StringName] = [&"barracks", &"range", &"stables", &"sanctum", &"bestiary"]
## [wood, gold] to build one.
const KIND_COSTS: Array = [[120, 40], [120, 60], [150, 80], [140, 100], [180, 150]]
## Seconds to train one of each kind.
const KIND_TRAIN_SECONDS: Array[float] = [20.0, 22.0, 26.0, 30.0, 40.0]
## The building put up when a people has none of its own for that kind.
const GENERIC_SCENES: Array[String] = [
	"res://scenes/buildings/barracks_building.tscn",
	"res://scenes/buildings/archery_range_building.tscn",
	"res://scenes/buildings/stables_building.tscn",
	"res://scenes/buildings/arcane_sanctum_building.tscn",
	"res://scenes/buildings/bestiary_building.tscn",
]

## A slot building's levels (1-3, capped by its settlement's tier: Village
## 1, Town 2, City 3). A resource building pays this much of its base rate.
const LEVEL_INCOME: Array[float] = [1.0, 1.75, 2.5]
## [wood, gold] and seconds to reach levels 2 and 3 (index = level - 1).
const LEVEL_COSTS: Array = [[0, 0], [150, 100], [250, 200]]
const LEVEL_SECONDS: Array[float] = [0.0, 40.0, 60.0]
const MAX_LEVEL: int = 3
## Training speed at a level with no new unit left to give.
const SPARE_LEVEL_TRAIN_SPEED: float = 1.25
## Elite: health and damage multipliers, and how much bigger it is drawn.
const ELITE_HEALTH: float = 1.3
const ELITE_DAMAGE: float = 1.25
const ELITE_SCALE: float = 1.15

## Race -> {scenes: a building per Kind ("" for the generic one), units: per
## Kind, unit scene paths in level order}.
const RACES: Dictionary = {
	"Human": {
		"scenes": ["", "", "", "", ""],
		"units": [
			["res://scenes/units/soldier_unit.tscn", "res://scenes/units/spearman_unit.tscn", "res://scenes/units/halberdier_unit.tscn"],
			["res://scenes/units/archer_unit.tscn", "res://scenes/units/crossbowman_unit.tscn"],
			["res://scenes/units/horseman_unit.tscn", "res://scenes/units/cavalier_unit.tscn"],
			["res://scenes/units/wizard_unit.tscn", "res://scenes/units/arch_mage_unit.tscn"],
			["res://scenes/units/beasts/griffin_unit.tscn", "res://scenes/units/beasts/manticore_unit.tscn"],
		],
	},
	"Dark Elves": {
		"scenes": ["res://scenes/buildings/dark_elf_spire_building.tscn", "", "", "res://scenes/buildings/dark_elf_coven_building.tscn", ""],
		"units": [
			["res://scenes/units/dark_elves/dark_elf_warrior_unit.tscn", "res://scenes/units/dark_elves/dark_elf_guard_unit.tscn", "res://scenes/units/dark_elves/dark_elf_assassin_unit.tscn"],
			["res://scenes/units/dark_elves/dark_elf_archer_unit.tscn"],
			["res://scenes/units/dark_elves/dark_elf_rider_unit.tscn"],
			["res://scenes/units/dark_elves/dark_elf_sorceress_unit.tscn", "res://scenes/units/dark_elves/dark_elf_spellstealer_unit.tscn"],
			["res://scenes/units/beasts/kitsune_unit.tscn", "res://scenes/units/beasts/wind_tiger_unit.tscn"],
		],
	},
	"Star Wanderers": {
		"scenes": ["res://scenes/buildings/star_gate_building.tscn", "", "", "res://scenes/buildings/star_sanctum_building.tscn", ""],
		"units": [
			["res://scenes/units/star_wanderers/sw_warrior_unit.tscn", "res://scenes/units/star_wanderers/sw_spearman_unit.tscn", "res://scenes/units/star_wanderers/sw_paladin_unit.tscn"],
			["res://scenes/units/star_wanderers/sw_hunter_unit.tscn"],
			["res://scenes/units/star_wanderers/sw_rider_unit.tscn", "res://scenes/units/star_wanderers/sw_knight_unit.tscn"],
			["res://scenes/units/star_wanderers/sw_priestess_unit.tscn"],
			["res://scenes/units/beasts/dragon_unit.tscn", "res://scenes/units/beasts/lightning_dragon_unit.tscn"],
		],
	},
	"Beastmen": {
		"scenes": ["res://scenes/buildings/beastmen_barracks_building.tscn", "", "", "", ""],
		"units": [
			["res://scenes/units/beastman_warrior_unit.tscn", "res://scenes/units/beastman_raider_unit.tscn", "res://scenes/units/beastman_panda_warrior_unit.tscn"],
			["res://scenes/units/beastman_wolf_pathfinder_unit.tscn"],
			["res://scenes/units/beastman_wolf_rider_unit.tscn"],
			["res://scenes/units/beastman_druid_unit.tscn"],
			["res://scenes/units/beasts/sand_worm_unit.tscn", "res://scenes/units/beasts/skeleton_dragon_unit.tscn"],
		],
	},
	## The playable peoples (Faction.PLAYABLE): no settlement is theirs, but
	## RaceTraits reads who their units are from here. `others`: what they
	## train that no settlement would (the worker, the Lord, siege).
	"Pirates": {
		"scenes": ["res://scenes/buildings/pirates/pirate_barracks_building.tscn",
				"res://scenes/buildings/pirates/pirate_range_building.tscn",
				"res://scenes/buildings/pirates/pirate_stables_building.tscn",
				"res://scenes/buildings/pirates/pirate_sanctum_building.tscn", ""],
		"units": [
			["res://scenes/units/pirates/pirate_swabbie_unit.tscn", "res://scenes/units/pirates/pirate_harpooner_unit.tscn",
					"res://scenes/units/pirates/pirate_brute_unit.tscn"],
			["res://scenes/units/pirates/pirate_musketeer_unit.tscn", "res://scenes/units/pirates/pirate_blunderbuss_unit.tscn"],
			["res://scenes/units/pirates/pirate_crab_rider_unit.tscn"],
			["res://scenes/units/pirates/pirate_voodoo_unit.tscn"],
			[],
		],
		"others": ["res://scenes/units/pirates/pirate_deckhand_unit.tscn", "res://scenes/units/pirates/pirate_captain_unit.tscn",
				"res://scenes/units/pirates/pirate_cannon_unit.tscn"],
	},
	"Robots": {
		"scenes": ["res://scenes/buildings/robots/robot_barracks_building.tscn",
				"res://scenes/buildings/robots/robot_range_building.tscn",
				"res://scenes/buildings/robots/robot_stables_building.tscn",
				"res://scenes/buildings/robots/robot_sanctum_building.tscn", ""],
		"units": [
			["res://scenes/units/robots/robot_trooper_unit.tscn", "res://scenes/units/robots/robot_driller_unit.tscn",
					"res://scenes/units/robots/robot_boiler_unit.tscn"],
			["res://scenes/units/robots/robot_ray_gunner_unit.tscn"],
			["res://scenes/units/robots/robot_hound_rider_unit.tscn"],
			["res://scenes/units/robots/robot_tesla_unit.tscn"],
			[],
		],
		"others": ["res://scenes/units/robots/robot_worker_unit.tscn", "res://scenes/units/robots/robot_mechanist_unit.tscn",
				"res://scenes/units/robots/robot_rocket_unit.tscn"],
	},
}

## The military buildings `race` can put up, in Kind order.
static func kinds_for(race: String) -> Array[int]:
	var kinds: Array[int] = []
	if not RACES.has(race):
		return kinds
	for kind in Kind.values():
		if not (RACES[race].units[kind] as Array).is_empty():
			kinds.append(kind)
	return kinds

## Kind for a slot item's name, or -1 for a building that trains nobody.
static func kind_named(item_name: String) -> int:
	return KIND_NAMES.find(item_name)

static func scene_for(race: String, kind: int) -> String:
	var own: String = RACES[race].scenes[kind] if RACES.has(race) else ""
	return own if not own.is_empty() else GENERIC_SCENES[kind]

## What a `kind` building of `race` trains at `level`: [scene path, bodies,
## seconds, elite] per unit, as plain data every peer works out the same.
static func roster(race: String, kind: int, level: int = 1) -> Array:
	var out: Array = []
	if not RACES.has(race):
		return out
	var units: Array = RACES[race].units[kind]
	for i in mini(level, units.size()):
		out.append([units[i], KIND_TRAIN_SECONDS[kind], false])
	if level > units.size() and not units.is_empty():
		out.append([units[units.size() - 1], KIND_TRAIN_SECONDS[kind], true])
	return out

## A level beyond the elite has no unit to give, so it trains faster.
static func train_speed(race: String, kind: int, level: int) -> float:
	if not RACES.has(race) or kind < 0:
		return 1.0
	return SPARE_LEVEL_TRAIN_SPEED if level > (RACES[race].units[kind] as Array).size() + 1 else 1.0

## "Upgrade to Level 2" and "Level 3", offered on every slot building (the
## HUD and ProductionBuilding.can_raise_level decide which is open).
## `military`: it trains units rather than paying resources.
static func level_items(military: bool = false) -> Array[ProducibleItem]:
	var out: Array[ProducibleItem] = []
	for level in range(2, MAX_LEVEL + 1):
		var item := ProducibleItem.new()
		item.item_name = "Upgrade to Level %d" % level
		if military:
			item.description = "Unlocks a stronger unit here, or faster training once the line is complete."
		else:
			item.description = "Raises this building's income to %d%% of its base rate." % roundi(LEVEL_INCOME[level - 1] * 100.0)
		item.kind = ProducibleItem.Kind.LEVEL
		item.icon = UiStyle.icon_art("settlement", "level_%d" % level)
		item.glyph = StringName("level_%d" % level)
		item.level_to = level
		item.build_time = LEVEL_SECONDS[level - 1]
		var costs: Array[ResourceCost] = []
		for pair in [[Objective.WOOD_COST, LEVEL_COSTS[level - 1][0]], [Objective.GOLD_COST, LEVEL_COSTS[level - 1][1]]]:
			var cost := ResourceCost.new()
			cost.resource_type = pair[0]
			cost.amount = pair[1]
			costs.append(cost)
		item.costs = costs
		out.append(item)
	return out

## A slot building's one-line description: who it trains, level by level.
static func describe_kind(race: String, kind: int) -> String:
	var names: Array[String] = []
	for entry in RACES[race].units[kind] if RACES.has(race) else []:
		names.append(_display_name(entry))
	if names.is_empty():
		return ""
	if names.size() == 1:
		return "Trains %s, and its elite at higher levels." % names[0]
	var listed := ", ".join(names.slice(0, names.size() - 1)) + " and " + names[names.size() - 1]
	return "Trains %s, one more with each level." % listed

static var _names: Dictionary = {}

static func _display_name(scene_path: String) -> String:
	if not _names.has(scene_path):
		var scene := load(scene_path) as PackedScene
		var probe := scene.instantiate() if scene != null else null
		_names[scene_path] = probe.get(&"display_name") if probe != null and probe.get(&"display_name") != null \
				else scene_path.get_file().get_basename()
		if probe != null:
			probe.free()
	return _names[scene_path]

## The building menu for a roster().
## `tint`: the owner's colour for the units' portraits (the local player's
## when not given).
static func items(entries: Array, tint: Color = Color(0, 0, 0, 0)) -> Array[ProducibleItem]:
	var out: Array[ProducibleItem] = []
	for entry in entries:
		var scene := load(entry[0]) as PackedScene
		if scene == null:
			continue
		var item := ProducibleItem.new()
		item.kind = ProducibleItem.Kind.UNIT
		item.unit_scene = scene
		item.build_time = float(entry[1])
		item.elite = entry.size() > 2 and bool(entry[2])
		item.icon = UnitPortrait.of_scene(entry[0], tint)
		var probe := scene.instantiate()
		item.item_name = probe.get(&"display_name") if probe.get(&"display_name") != null else entry[0].get_file().get_basename()
		probe.free()
		if item.elite:
			item.item_name = "Elite " + item.item_name
		out.append(item)
	return out
