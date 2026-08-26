extends Node
## Autoload singleton tracking totals per ResourceType. Generic across any
## number of resource types so new ones (Gold, Stone, ...) need no new code here.

signal changed(resource_type: ResourceType, amount: int)

var _totals: Dictionary = {}

func add(resource_type: ResourceType, amount: int) -> void:
	if amount <= 0 or resource_type == null:
		return
	var new_amount: int = _totals.get(resource_type, 0) + amount
	_totals[resource_type] = new_amount
	changed.emit(resource_type, new_amount)

func get_amount(resource_type: ResourceType) -> int:
	return _totals.get(resource_type, 0)

func can_afford(costs: Array[ResourceCost]) -> bool:
	for cost in costs:
		if get_amount(cost.resource_type) < cost.amount:
			return false
	return true

## Caller must have already checked can_afford(); this does not clamp or refuse.
func spend(costs: Array[ResourceCost]) -> void:
	for cost in costs:
		var new_amount: int = _totals.get(cost.resource_type, 0) - cost.amount
		_totals[cost.resource_type] = new_amount
		changed.emit(cost.resource_type, new_amount)
