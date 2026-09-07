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

## When true, this entry places as a click-and-drag wall run instead of a
## single ghost: main.gd's wall drag flow (_start_wall_drag/_update_wall_drag/
## _confirm_wall_placement) takes over instead of the normal single-ghost path.
@export var is_wall: bool = false
## Distance between two straight wall segments' centers along the drag path.
@export var wall_segment_length: float = 2.0
## Auto-inserted at every point the drag path changes direction, closing the
## visual gap between two segments meeting at an angle. Same cost/construction
## shape as `scene` (both must have ProductionBuilding's `costs` export).
@export var wall_corner_scene: PackedScene
## Alternate scene a completed (or in-progress) segment of this wall can be
## swapped for via the Gate tool. Left null for a wall type with no gate option.
@export var wall_gate_scene: PackedScene

## When true, this entry isn't placed on open ground at all — clicking an
## owned instance of any scene in `gate_target_scenes` replaces it with
## `scene` (expected to be a gate) instead. See main.gd's _update_gate_ghost.
@export var is_gate_tool: bool = false
## Which built scenes this gate tool may replace (typically both the wall
## segment and corner scenes, so a gate isn't limited to straight runs).
## Matched by scene_file_path, same convention as requires_deposit/deposit_scene.
@export var gate_target_scenes: Array[PackedScene] = []

## Peeks at scene's exported "costs" (ProductionBuilding or Gatherable both
## have one) without adding it to the tree, so its _ready()/_process() never
## run — just a duck-typed property read, then immediately freed. Untyped
## on purpose: a statically-typed Node would make GDScript demand a "costs"
## member on the Node base class itself before this even runs.
func get_costs() -> Array[ResourceCost]:
	return _peek_costs(scene, costs)

func get_corner_costs() -> Array[ResourceCost]:
	return _peek_costs(wall_corner_scene, costs)

func get_gate_costs() -> Array[ResourceCost]:
	return _peek_costs(wall_gate_scene, costs)

func _peek_costs(target_scene: PackedScene, fallback: Array[ResourceCost]) -> Array[ResourceCost]:
	if target_scene == null:
		return fallback
	var temp = target_scene.instantiate()
	var result: Array[ResourceCost] = temp.costs
	temp.free()
	return result
