class_name BuildingType
extends Resource
## One entry in the construction menu: what to build, its cost, and the
## footprint used for the placement ghost / overlap check.

@export var building_name: String = "Building"
@export var scene: PackedScene
@export var costs: Array[ResourceCost] = []
@export var footprint_radius: float = 2.2
@export var construction_time: float = 5.0
## When true, this building can only be placed exactly on top of an existing
## node instanced from `deposit_scene` (e.g. a Mine snapping onto a Gold
## Deposit) instead of freely on open ground.
@export var requires_deposit: bool = false
## Which scene qualifies as a valid placement target when requires_deposit is on.
@export var deposit_scene: PackedScene
