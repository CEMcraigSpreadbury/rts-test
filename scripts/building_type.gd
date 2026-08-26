class_name BuildingType
extends Resource
## One entry in the construction menu: what to build, its cost, and the
## footprint used for the placement ghost / overlap check.

@export var building_name: String = "Building"
@export var scene: PackedScene
@export var costs: Array[ResourceCost] = []
@export var footprint_radius: float = 2.2
@export var construction_time: float = 5.0
