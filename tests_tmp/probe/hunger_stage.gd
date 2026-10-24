extends RefCounted
## ui_shot --stage: empties the local food store so the next upkeep charge
## starves the army, then reports what the units got.
func stage(main: Node) -> void:
	var me: int = main.my_peer_id()
	var held: int = ResourceStockpile.get_amount(me, RealmEconomy.FOOD)
	var cost := ResourceCost.new()
	cost.resource_type = RealmEconomy.FOOD
	cost.amount = held
	ResourceStockpile.spend(me, [cost] as Array[ResourceCost])
	await main.get_tree().create_timer(12.0).timeout
	var hungry := 0
	var total := 0
	for node in main.get_tree().get_nodes_in_group(&"units"):
		var unit := node as Unit
		if unit != null and unit.owner_peer_id == me:
			total += 1
			if unit.starving:
				hungry += 1
	print("HUNGER starving=%s units=%d hungry=%d" % [main.realm_economy.is_starving(me), total, hungry])
