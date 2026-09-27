class_name RealmRoster
extends RefCounted
## Which units each people trains in a Realm settlement's military buildings,
## and what raising a slot building's level does.
## A settlement offers a Barracks, Range, Stables and Sanctum only where its
## people have units of that kind; the hall itself trains nobody. Each list is
## in level order: the first unit comes with the building, the next with each
## level. A line with no next unit gets its elite instead (tougher, harder
## hitting, drawn a size up), and a level past that trains faster.

enum Kind { BARRACKS, RANGE, STABLES, SANCTUM }
const KIND_NAMES: Array[String] = ["Barracks", "Range", "Stables", "Sanctum"]
## [wood, gold] to build one.
const KIND_COSTS: Array = [[120, 40], [120, 60], [150, 80], [140, 100]]
## Seconds to train one of each kind (a litter counts as one).
const KIND_TRAIN_SECONDS: Array[float] = [20.0, 22.0, 26.0, 30.0]
## The building put up when a people has none of its own for that kind.
const GENERIC_SCENES: Array[String] = [
	"res://scenes/buildings/barracks_building.tscn",
	"res://scenes/buildings/archery_range_building.tscn",
	"res://scenes/buildings/stables_building.tscn",
	"res://scenes/buildings/arcane_sanctum_building.tscn",
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
## Kind, [scene path, bodies per training] in level order}.
const RACES: Dictionary = {
	"Human": {
		"scenes": ["", "", "", ""],
		"units": [
			[["res://scenes/units/soldier_unit.tscn", 1], ["res://scenes/units/spearman_unit.tscn", 1], ["res://scenes/units/halberdier_unit.tscn", 1]],
			[["res://scenes/units/archer_unit.tscn", 1], ["res://scenes/units/crossbowman_unit.tscn", 1]],
			[["res://scenes/units/horseman_unit.tscn", 1], ["res://scenes/units/cavalier_unit.tscn", 1]],
			[["res://scenes/units/wizard_unit.tscn", 1], ["res://scenes/units/arch_mage_unit.tscn", 1]],
		],
	},
	"Gnolls": {
		"scenes": ["res://scenes/buildings/gnoll_den_building.tscn", "", "", "res://scenes/buildings/gnoll_totem_building.tscn"],
		"units": [
			[["res://scenes/units/gnolls/gnoll_warrior_unit.tscn", 3], ["res://scenes/units/gnolls/gnoll_berserk_unit.tscn", 2], ["res://scenes/units/gnolls/gnoll_leader_unit.tscn", 1]],
			[["res://scenes/units/gnolls/gnoll_archer_unit.tscn", 2]],
			[["res://scenes/units/gnolls/hyena_unit.tscn", 2]],
			[["res://scenes/units/gnolls/gnoll_shaman_unit.tscn", 1]],
		],
	},
	"Dark Elves": {
		"scenes": ["res://scenes/buildings/dark_elf_spire_building.tscn", "", "", "res://scenes/buildings/dark_elf_coven_building.tscn"],
		"units": [
			[["res://scenes/units/dark_elves/dark_elf_warrior_unit.tscn", 1], ["res://scenes/units/dark_elves/dark_elf_guard_unit.tscn", 1], ["res://scenes/units/dark_elves/dark_elf_assassin_unit.tscn", 1]],
			[["res://scenes/units/dark_elves/dark_elf_archer_unit.tscn", 1]],
			[["res://scenes/units/dark_elves/dark_elf_rider_unit.tscn", 1]],
			[["res://scenes/units/dark_elves/dark_elf_sorceress_unit.tscn", 1], ["res://scenes/units/dark_elves/dark_elf_spellstealer_unit.tscn", 1]],
		],
	},
	"Star Wanderers": {
		"scenes": ["res://scenes/buildings/star_gate_building.tscn", "", "", "res://scenes/buildings/star_sanctum_building.tscn"],
		"units": [
			[["res://scenes/units/star_wanderers/sw_warrior_unit.tscn", 1], ["res://scenes/units/star_wanderers/sw_spearman_unit.tscn", 1], ["res://scenes/units/star_wanderers/sw_paladin_unit.tscn", 1]],
			[["res://scenes/units/star_wanderers/sw_hunter_unit.tscn", 1]],
			[["res://scenes/units/star_wanderers/sw_rider_unit.tscn", 1], ["res://scenes/units/star_wanderers/sw_knight_unit.tscn", 1]],
			[["res://scenes/units/star_wanderers/sw_priestess_unit.tscn", 1]],
		],
	},
	"Beastmen": {
		"scenes": ["res://scenes/buildings/beastmen_barracks_building.tscn", "", "", ""],
		"units": [
			[["res://scenes/units/beastman_warrior_unit.tscn", 1], ["res://scenes/units/beastman_panda_warrior_unit.tscn", 1]],
			[["res://scenes/units/beastman_wolf_pathfinder_unit.tscn", 1]],
			[["res://scenes/units/beastman_raider_unit.tscn", 1]],
			[["res://scenes/units/beastman_druid_unit.tscn", 1]],
		],
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
		out.append([units[i][0], units[i][1], KIND_TRAIN_SECONDS[kind], false])
	if level > units.size() and not units.is_empty():
		var top: Array = units[units.size() - 1]
		out.append([top[0], top[1], KIND_TRAIN_SECONDS[kind], true])
	return out

## A level beyond the elite has no unit to give, so it trains faster.
static func train_speed(race: String, kind: int, level: int) -> float:
	if not RACES.has(race) or kind < 0:
		return 1.0
	return SPARE_LEVEL_TRAIN_SPEED if level > (RACES[race].units[kind] as Array).size() + 1 else 1.0

## "Upgrade to Level 2" and "Level 3", offered on every slot building (the
## HUD and ProductionBuilding.can_raise_level decide which is open).
static func level_items() -> Array[ProducibleItem]:
	var out: Array[ProducibleItem] = []
	for level in range(2, MAX_LEVEL + 1):
		var item := ProducibleItem.new()
		item.item_name = "Upgrade to Level %d" % level
		item.kind = ProducibleItem.Kind.LEVEL
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

## The building menu for a roster().
static func items(entries: Array) -> Array[ProducibleItem]:
	var out: Array[ProducibleItem] = []
	for entry in entries:
		var scene := load(entry[0]) as PackedScene
		if scene == null:
			continue
		var item := ProducibleItem.new()
		item.kind = ProducibleItem.Kind.UNIT
		item.unit_scene = scene
		item.spawn_count = int(entry[1])
		item.build_time = float(entry[2])
		item.elite = entry.size() > 3 and bool(entry[3])
		item.icon = UnitPortrait.of_scene(entry[0])
		var probe := scene.instantiate()
		item.item_name = probe.get(&"display_name") if probe.get(&"display_name") != null else entry[0].get_file().get_basename()
		probe.free()
		if item.elite:
			item.item_name = "Elite " + item.item_name
		out.append(item)
	return out
