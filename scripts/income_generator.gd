class_name IncomeGenerator
extends Node
## Income a building produces for whoever owns it: `amount` of
## `resource_type` every `interval` (a settlement's Granary, Market and
## Lumberyard). Dropped as a child of a ProductionBuilding and configured in
## the inspector; host-authoritative, like every other source of resources.

@export var resource_type: ResourceType
@export var amount: int = 1
@export var interval: float = 5.0

var _timer: float = 0.0
var _building: ProductionBuilding
## Show each payout over the building (see WorldFeedback.show_income_popup).
@export var show_payouts: bool = true

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
	if amount <= 0:
		return
	ResourceStockpile.add(_building.owner_peer_id, resource_type, amount)
	var main := get_tree().current_scene
	if show_payouts and main is Main:
		main.feedback.show_income_popup(_building, _building.owner_peer_id, [[amount, resource_type.display_color]])
