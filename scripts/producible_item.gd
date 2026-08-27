class_name ProducibleItem
extends Resource
## One entry offered in a Building's build menu: a Villager on a TownCenter,
## a Soldier on a Barracks, an "Upgrade Gathering" on some future building, etc.
## Create new ones by duplicating a .tres of this (or embedding one in a
## building's scene) and editing the fields in the inspector.

enum Kind { UNIT, UPGRADE }

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

func get_population_cost() -> int:
	if kind == Kind.UNIT and unit_scene != null:
		var temp: Unit = unit_scene.instantiate()
		var result := temp.population_cost
		temp.free()
		return result
	return population_cost
