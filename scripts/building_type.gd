class_name BuildingType
extends Resource
## One entry in the construction menu: what to build, its cost, and the
## footprint used for the placement ghost / overlap check.

@export var building_name: String = "Building"
## Shown on its command-card button; left null until real icon art exists,
## in which case the button falls back to showing just its hotkey letter.
@export var icon: Texture2D
@export var scene: PackedScene
## Only used as a fallback if scene is somehow unset — the real cost lives on
## the building scene itself (ProductionBuilding.costs / Gatherable.costs for
## Farm), editable right there for balancing. See get_costs().
@export var costs: Array[ResourceCost] = []
@export var footprint_radius: float = 2.2
@export var construction_time: float = 5.0
## When true, this building can only be placed exactly on top of an existing
## node instanced from `deposit_scene` (e.g. a Mine snapping onto a Gold
## Deposit) instead of freely on open ground.
@export var requires_deposit: bool = false
## Which scene qualifies as a valid placement target when requires_deposit is on.
@export var deposit_scene: PackedScene

## Peeks at scene's exported "costs" (ProductionBuilding or Gatherable both
## have one) without adding it to the tree, so its _ready()/_process() never
## run — just a duck-typed property read, then immediately freed. Untyped
## on purpose: a statically-typed Node would make GDScript demand a "costs"
## member on the Node base class itself before this even runs.
func get_costs() -> Array[ResourceCost]:
	if scene == null:
		return costs
	var temp = scene.instantiate()
	var result: Array[ResourceCost] = temp.costs
	temp.free()
	return result
