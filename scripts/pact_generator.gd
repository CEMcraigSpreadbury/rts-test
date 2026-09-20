class_name PactGenerator
extends Node
## Income a Pact building produces for whoever owns it — the "floor" every
## allied race has, so a player can never be locked out of the race they
## allied with by a bad match (see Pacts). Dropped as a child of a
## ProductionBuilding and configured in the inspector; host-authoritative,
## like every other source of resources.
##
## Two shapes, both driven from the same timer:
##   - a plain trickle (Altar, Observatory): `amount` every `interval`
##   - a conversion (Gnoll Den): the same, but only when the owner can pay
##     `cost_amount` of `cost_resource`, which is deducted
##
## `night_multiplier` scales the payout with DayNight.night_amount, which is
## what makes Starlight a nocturnal economy: 1.0 leaves income flat, 3.0 pays
## triple at midnight and tapers back through dusk and dawn.

@export var resource_type: ResourceType
@export var amount: int = 1
@export var interval: float = 5.0
## Spent each payout when set; no payout at all when the owner can't afford it.
@export var cost_resource: ResourceType
@export var cost_amount: int = 0
## Payout is scaled between 1.0 in full daylight and this at full night.
@export var night_multiplier: float = 1.0

var _timer: float = 0.0
var _building: ProductionBuilding
## Fractions carry over rather than rounding away, so a slow generator still
## pays exactly its configured rate over time.
var _carry: float = 0.0

func _ready() -> void:
	_building = get_parent() as ProductionBuilding
	set_physics_process(multiplayer.is_server() and _building != null and resource_type != null)

func _physics_process(delta: float) -> void:
	if _building.is_destroyed or _building.is_under_construction or _building.owner_peer_id <= 0:
		return
	_timer += delta
	if _timer < interval:
		return
	_timer -= interval
	if cost_resource != null and cost_amount > 0:
		if ResourceStockpile.get_amount(_building.owner_peer_id, cost_resource) < cost_amount:
			return
		var cost := ResourceCost.new()
		cost.resource_type = cost_resource
		cost.amount = cost_amount
		ResourceStockpile.spend(_building.owner_peer_id, [cost] as Array[ResourceCost])
	_carry += float(amount) * _night_scale()
	var whole: int = int(floor(_carry))
	if whole <= 0:
		return
	_carry -= float(whole)
	ResourceStockpile.add(_building.owner_peer_id, resource_type, whole)

## 1.0 by day, `night_multiplier` at the dead of night, sliding through the
## dusk/dawn fade so income never jumps.
func _night_scale() -> float:
	if is_equal_approx(night_multiplier, 1.0):
		return 1.0
	var main := get_tree().current_scene
	if not (main is Main) or main.day_night == null:
		return 1.0
	return lerpf(1.0, night_multiplier, clampf(main.day_night.night_amount, 0.0, 1.0))
