class_name ProducibleItem
extends Resource
## One entry offered in a Building's build menu: a Villager on a TownCenter,
## a Soldier on a Barracks, an "Upgrade Gathering" on some future building, etc.
## Create new ones by duplicating a .tres of this (or embedding one in a
## building's scene) and editing the fields in the inspector.

enum Kind { UNIT, UPGRADE, PACT, SACRIFICE }

@export var item_name: String = "Villager"
## Shown on its command-card button; left null until real icon art exists,
## in which case the button falls back to showing just its hotkey letter.
@export var icon: Texture2D
@export var kind: Kind = Kind.UNIT
@export var build_time: float = 5.0
## Only used for UPGRADE items — a UNIT's real cost lives on unit_scene's own
## Unit.costs/population_cost instead (see get_costs()/get_population_cost()),
## so it's editable directly on the unit for balancing rather than buried here.
@export var costs: Array[ResourceCost] = []
@export var population_cost: int = 1
## Used when kind == UNIT; the scene instanced into the world on completion.
@export var unit_scene: PackedScene

## Used when kind == PACT (a Pact Hall's alliance with one race): the race
## allied with on completion. Completing any Pact takes the other races off
## that hall's menu for good, and a race already allied with can't be taken
## again at a second hall — both enforced in ProductionBuilding.enqueue().
@export var pact_race: PactRace

## How many units one completed item spawns. Gnolls are trained in litters:
## one cost, one build time, three or four bodies. 1 for everything else.
@export var spawn_count: int = 1

## Used when kind == SACRIFICE (the Dark Elf Altar): one of the owner's own
## units within SACRIFICE_RADIUS is killed and this much of the building's
## Pact currency paid instead. The victim is chosen cheapest-first, so an
## Altar eats villagers before it eats Sorceresses.
@export var sacrifice_payout: int = 0

## Used when kind == UPGRADE, for a Blacksmith-style weapon/armor upgrade
## (see UnitUpgrades autoload). upgrade_bonus == 0 means this item doesn't
## grant one. A future upgrade effect is another optional field here plus a
## matching check in main.gd's completion handler.
@export var upgrade_category: Unit.UnitCategory = Unit.UnitCategory.NONE
@export var upgrade_stat: UnitUpgrades.Stat = UnitUpgrades.Stat.WEAPON
@export var upgrade_bonus: int = 0
## Tier prerequisite — null means this is the first tier in its line.
## Enforced in ProductionBuilding.enqueue(), same place the existing
## one-time-purchase guard lives.
@export var requires_upgrade: ProducibleItem = null

## Peeks at unit_scene's exported defaults without adding it to the tree (so
## _ready() — sprite sheet building, etc. — never runs) for UNIT items;
## falls back to this resource's own costs for UPGRADE items, which have no unit.
func get_costs() -> Array[ResourceCost]:
	if kind == Kind.UNIT and unit_scene != null:
		var temp: Unit = unit_scene.instantiate()
		var result: Array[ResourceCost] = temp.costs
		temp.free()
		return result
	return costs

## Which population pool this item spends. Read off the unit itself, like its
## cost, so a Gnoll scene is the one place its pool is set.
func get_population_pool() -> PopulationPool.Kind:
	if kind == Kind.UNIT and unit_scene != null:
		var temp: Unit = unit_scene.instantiate()
		var result: PopulationPool.Kind = temp.population_pool
		temp.free()
		return result
	return PopulationPool.Kind.MAIN

func get_population_cost() -> int:
	if kind == Kind.UNIT and unit_scene != null:
		var temp: Unit = unit_scene.instantiate()
		var result := temp.population_cost
		temp.free()
		return result
	return population_cost
