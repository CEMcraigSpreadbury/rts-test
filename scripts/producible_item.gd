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
@export var costs: Array[ResourceCost] = []
## Only meaningful when kind == UNIT; ignored for upgrades.
@export var population_cost: int = 1
## Used when kind == UNIT; the scene instanced into the world on completion.
@export var unit_scene: PackedScene
