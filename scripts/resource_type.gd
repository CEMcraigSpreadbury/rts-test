class_name ResourceType
extends Resource
## Defines a kind of harvestable resource (Wood, Gold, ...).
## Create new resource types by duplicating a .tres of this in the editor.

@export var display_name: String = "Wood"
@export var display_color: Color = Color(0.55, 0.35, 0.2)
@export var gather_amount_per_tick: int = 1
@export var gather_interval: float = 1.0
