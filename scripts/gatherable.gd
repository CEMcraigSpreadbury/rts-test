class_name Gatherable
extends StaticBody3D
## A harvestable resource node (tree, rock, ore vein, ...). Duplicate this
## scene and swap the resource_type, model, and collision/obstacle sizes to
## create new resource types (Stone, Gold, ...).

signal depleted

@export var resource_type: ResourceType
@export var amount_remaining: int = 500
## How close a gatherer needs to be before it starts harvesting.
@export var gather_range: float = 1.75
## 0 = neutral/natural resource (trees, berry bushes, gold deposits) that anyone
## can gather from. Player-built resources (Farm) are set to their owner's
## peer_id at spawn time so other players' villagers can't collect from them.
@export var owner_peer_id: int = 0
## When true, this node can't actually be harvested until a qualifying
## building has been constructed on top of it (see BuildingType.requires_deposit
## / main.gd's placement handling) — e.g. a Gold Deposit needs a Mine built on
## it first. Off by default so trees/berry bushes/farms are unaffected.
@export var requires_building_on_top: bool = false
## Set true once a qualifying building's construction finishes on this node,
## and back to false if that building is destroyed (see main.gd).
var has_required_building: bool = false
## True from the moment a building starts being placed here (even mid-
## construction) so a second building can't also claim the same node.
var is_claimed: bool = false

func can_be_gathered() -> bool:
	return not requires_building_on_top or has_required_building

## Returns the amount actually taken (may be less than requested near depletion).
func gather(amount: int) -> int:
	var taken: int = mini(amount, amount_remaining)
	amount_remaining -= taken
	if amount_remaining <= 0:
		depleted.emit()
		queue_free()
	return taken
