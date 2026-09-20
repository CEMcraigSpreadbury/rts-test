class_name AiMilitary
extends RefCounted
## AiPlayer's army production: keeps every military building it owns (its
## own Barracks/Stables and any captured objective building that trains
## soldiers) queued with whichever unit best fills out the target army mix
## (AiProfile's "Military" group). Lowest spending priority — it only spends
## what the economy and build order haven't set aside. New units walk to the
## base's staging point via the rally point AiBaseBuilder sets.

var ai: AiPlayer

func _init(p_ai: AiPlayer) -> void:
	ai = p_ai

func think() -> void:
	_train_monsters()
	_research_unlocks()
	_train()

## An item this player may actually order right now — anything still waiting
## on an upgrade elsewhere in the base (see the UnitUnlocks autoload) is skipped
## rather than offered to enqueue_as, which would only refuse it.
func _is_available(item: ProducibleItem) -> bool:
	return UnitUnlocks.has(ai.peer_id, item.requires_unlock)

## Buys the upgrades that open a better unit — Shields, Crossbows, Halberds,
## Lances, Ancient Texts — as soon as one is affordable and its building is idle.
## Plain weapon/armor upgrades are deliberately left alone: those are a
## balance choice, while these decide whether the AI can field the unit at all.
func _research_unlocks() -> void:
	if not ai.profile.buys_unit_unlocks:
		return
	for building in ai.my_buildings:
		## Room in the queue is enough — an Arcane Sanctum is nearly always
		## training something, and waiting for it to fall idle would mean
		## Ancient Texts never being bought at all. enqueue() refuses an
		## upgrade that is already queued here, so this can't stack.
		if building.is_under_construction or building.queue.size() >= ProductionBuilding.MAX_QUEUE_SIZE:
			continue
		for i in building.producibles.size():
			var item: ProducibleItem = building.producibles[i]
			if item.kind != ProducibleItem.Kind.UPGRADE or item.grants_unlock == &"":
				continue
			if UnitUnlocks.has(ai.peer_id, item.grants_unlock) or not _is_available(item):
				continue
			if ai.can_afford(ai.item_costs(item)) and ai.main.enqueue_as(ai.peer_id, building.get_path(), i):
				break

## Soldiers we want before saving up for a monster rather than just buying
## one whenever the money happens to be there.
const MONSTER_SAVE_MIN_ARMY: int = 6

## Owned Shrines (captured points) come first: a monster is worth several
## soldiers, and each Shrine only lets its owner have a couple alive. The
## strongest one on offer that fits under the Shrine's limit is bought; on
## difficulties that save for them, its cost is set aside until it can be.
func _train_monsters() -> void:
	for building in ai.my_buildings:
		if building.is_under_construction or not building.queue.is_empty():
			continue
		if building.is_at_unit_limit(ai.peer_id):
			continue
		var best := -1
		var best_strength := -1.0
		for i in building.producibles.size():
			var item: ProducibleItem = building.producibles[i]
			if item.kind != ProducibleItem.Kind.UNIT or item.unit_scene == null:
				continue
			if ai.unit_role_of_scene(item.unit_scene) != AiPlayer.UnitRole.MONSTER:
				continue
			if not _is_available(item):
				continue
			var strength: float = ai.unit_strength_of_scene(item.unit_scene)
			if strength > best_strength:
				best_strength = strength
				best = i
		if best < 0:
			continue
		var costs: Array[ResourceCost] = ai.item_costs(building.producibles[best])
		if ai.can_afford(costs):
			ai.main.enqueue_as(ai.peer_id, building.get_path(), best)
		elif ai.profile.save_for_monsters and ai.army.size() >= MONSTER_SAVE_MIN_ARMY:
			ai.reserve(costs)

func _train() -> void:
	var counts := _role_counts()
	var total := 0
	for role in counts:
		if role != AiPlayer.UnitRole.WORKER:
			total += int(counts[role])
	for building in ai.my_buildings:
		if total >= ai.profile.max_army:
			return
		if building.is_under_construction or building.queue.size() >= ai.profile.military_queue:
			continue
		if ai.building_role(building) != AiPlayer.BuildingRole.MILITARY:
			continue
		var index := _choose_item(building, counts)
		if index < 0:
			continue
		var item: ProducibleItem = building.producibles[index]
		if not ai.can_afford(ai.item_costs(item)):
			continue
		if ai.main.enqueue_as(ai.peer_id, building.get_path(), index):
			var role: int = ai.unit_role_of_scene(item.unit_scene)
			counts[role] = int(counts.get(role, 0)) + 1
			total += 1

## UnitRole -> how many we have, living or queued.
func _role_counts() -> Dictionary:
	var counts: Dictionary = {}
	for unit in ai.army:
		var role: int = AiPlayer.unit_role(unit)
		counts[role] = int(counts.get(role, 0)) + 1
	for building in ai.my_buildings:
		for item in building.queue:
			if item.kind == ProducibleItem.Kind.UNIT and item.unit_scene != null:
				var role: int = ai.unit_role_of_scene(item.unit_scene)
				counts[role] = int(counts.get(role, 0)) + 1
	return counts

func _weight(role: int) -> float:
	match role:
		AiPlayer.UnitRole.INFANTRY:
			return ai.profile.infantry_weight
		AiPlayer.UnitRole.SPEAR:
			return ai.profile.spear_weight
		AiPlayer.UnitRole.RANGED:
			return ai.profile.ranged_weight
		AiPlayer.UnitRole.CAVALRY:
			return ai.profile.cavalry_weight
	return 0.0

## The item at `building` whose role is furthest below its share of the
## army — judged only among the roles this building can train, so a Stables
## always trains cavalry and a Barracks balances its own two.
func _choose_item(building: ProductionBuilding, counts: Dictionary) -> int:
	var options: Array = []
	var total_weight := 0.0
	var total_count := 0
	## role -> [index, strength]. One entry per role, and where a building
	## trains two of the same role it's the stronger one — that's how a
	## researched unlock actually reaches the field: once Crossbows is bought
	## the Archery Range starts turning out Crossbowmen instead of Archers.
	var best_of_role: Dictionary = {}
	for i in building.producibles.size():
		var item: ProducibleItem = building.producibles[i]
		if item.kind != ProducibleItem.Kind.UNIT or item.unit_scene == null:
			continue
		if not _is_available(item):
			continue
		var role: int = ai.unit_role_of_scene(item.unit_scene)
		if role == AiPlayer.UnitRole.WORKER or role == AiPlayer.UnitRole.MONSTER:
			continue
		var strength: float = ai.unit_strength_of_scene(item.unit_scene)
		var held: Variant = best_of_role.get(role)
		if held == null or strength > float(held[1]):
			best_of_role[role] = [i, strength]
	for role in best_of_role:
		## A captured building's own roster (e.g. beastmen) may not map onto
		## the weights at all; everything it trains still gets a fair share.
		var weight: float = maxf(_weight(role), 0.1)
		options.append([best_of_role[role][0], role, weight])
		total_weight += weight
		total_count += int(counts.get(role, 0))
	var best := -1
	var best_deficit := -INF
	for option in options:
		var share: float = option[2] / total_weight
		var have: float = float(counts.get(option[1], 0)) / maxf(total_count, 1.0)
		var deficit: float = share - have
		if deficit > best_deficit:
			best_deficit = deficit
			best = option[0]
	return best
