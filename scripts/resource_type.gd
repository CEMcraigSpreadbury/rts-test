class_name ResourceType
extends Resource
## Defines a kind of harvestable resource (Wood, Gold, ...).
## Create new resource types by duplicating a .tres of this in the editor.

@export var display_name: String = "Wood"
@export var display_color: Color = Color(0.55, 0.35, 0.2)
@export var gather_amount_per_tick: int = 1
@export var gather_interval: float = 1.0
## Played when a purchase is refused for lack of this specific resource, so
## "not enough wood" and "not enough gold" are distinguishable by ear without
## having to watch the resource bar flash. One is picked at random, same
## convention as every other *_sound_effects array. Left empty for a resource
## nothing is ever bought with — that just means silence, no fallback.
@export var insufficient_sound_effects: Array[AudioStream] = []
