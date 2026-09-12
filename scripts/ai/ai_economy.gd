class_name AiEconomy
extends RefCounted
## AiPlayer's economy: Houses before the population cap bites, a steady
## stream of villagers, and every villager kept on a job — wood, gold (once a
## Mine is working, see AiProfile.gold_worker_share) or a construction site.

## How often the list of choppable trees is rebuilt — trees only disappear,
## and scanning every one on every think adds up on a big map.
const WOOD_CACHE_SECONDS: float = 6.0
## Trees further than this from home aren't worth the walk while nearer
## ones remain.
const MAX_WOOD_DISTANCE: float = 55.0
## A tree already this crowded is passed over for a quieter one nearby.
const MAX_GATHERERS_PER_TREE: int = 2
## Swap one worker between wood and gold only once the split is this far off
## target, so a single idle villager doesn't make them flip back and forth.
const REBALANCE_SLACK: int = 1
## Extra miners allowed over the gold target when no tree can be found.
const GOLD_OVERFLOW_SLACK: int = 2

var ai: AiPlayer
var _wood_nodes: Array = []
## When the tree list was last rebuilt; -INF so the first request builds it.
var _wood_cache_age: float = -INF

func _init(p_ai: AiPlayer) -> void:
	ai = p_ai

## --- Spending (see AiPlayer._think for where each sits in the priority) ---

func think_houses() -> void:
	_maybe_build_house()

func think_villagers() -> void:
	_maybe_train_villagers()

func _maybe_build_house() -> void:
	var houses: Array[BuildingType] = ai.types_with_role(AiPlayer.BuildingRole.HOUSE)
	if houses.is_empty():
		return
	var used: int = Population.get_used(ai.peer_id)
	var cap: int = Population.get_cap(ai.peer_id)
	var producers := 0
	for building in ai.my_buildings:
		if building.is_under_construction:
			## Still-rising Houses will add their capacity soon enough.
			if not ai.builder.is_abandoned(building):
				cap += building.population_capacity
		elif not building.producibles.is_empty():
			producers += 1
	if cap >= ai.profile.max_population:
		return
	if cap - used > ai.profile.house_headroom + producers:
		return
	ai.builder.try_construct(houses[0])

func _maybe_train_villagers() -> void:
	var count: int = ai.villagers.size()
	var producers: Array = []
	for building in ai.my_buildings:
		if building.is_under_construction:
			continue
		var index := _villager_item_index(building)
		if index < 0:
			continue
		producers.append([building, index])
		for item in building.queue:
			if item == building.producibles[index]:
				count += 1
	for entry in producers:
		if count >= ai.profile.target_villagers:
			return
		var building: ProductionBuilding = entry[0]
		var index: int = entry[1]
		if building.queue.size() >= ai.profile.villager_queue:
			continue
		var costs: Array[ResourceCost] = ai.item_costs(building.producibles[index])
		if not ai.can_afford(costs):
			ai.reserve(costs)
			return
		if ai.main.enqueue_as(ai.peer_id, building.get_path(), index):
			count += 1

func _villager_item_index(building: ProductionBuilding) -> int:
	for i in building.producibles.size():
		var item: ProducibleItem = building.producibles[i]
		if item.kind == ProducibleItem.Kind.UNIT and item.unit_scene != null \
				and ai.unit_role_of_scene(item.unit_scene) == AiPlayer.UnitRole.WORKER:
			return i
	return -1

## --- Orders (runs last) ---

func think_workers() -> void:
	_staff_construction_sites()
	var jobs := _count_jobs()
	var gold_sources := _gold_sources()
	var gatherers: int = jobs.wood + jobs.gold + jobs.idle.size()
	var want_gold: int = roundi(gatherers * _gold_share()) if not gold_sources.is_empty() else 0
	for villager in jobs.idle:
		if not ai.use_order():
			return
		var to_gold: bool = jobs.gold < want_gold
		if _send_to_gather(villager, to_gold, gold_sources):
			if to_gold:
				jobs.gold += 1
			else:
				jobs.wood += 1
		## No gold job going: try wood. The other way round (no tree found, so
		## mine instead) only once gold is actually short — otherwise a bad
		## tree pick quietly turns the whole economy into gold miners.
		elif to_gold and _send_to_gather(villager, false, gold_sources):
			jobs.wood += 1
		elif not to_gold and jobs.gold < want_gold + GOLD_OVERFLOW_SLACK and _send_to_gather(villager, true, gold_sources):
			jobs.gold += 1
	## One swap per think at most, never a villager carrying a load home.
	if jobs.gold < want_gold - REBALANCE_SLACK and not jobs.wood_workers.is_empty() and ai.use_order():
		_send_to_gather(_pick_unloaded(jobs.wood_workers), true, gold_sources)
	elif jobs.gold > want_gold + REBALANCE_SLACK and not jobs.gold_workers.is_empty() and ai.use_order():
		_send_to_gather(_pick_unloaded(jobs.gold_workers), false, gold_sources)

## Gold only pays for soldiers (villagers, Houses and buildings are all wood),
## so the profile's share is only a starting point: kept low until there's a
## military building to spend it in, and nudged whichever way the stockpile
## is lopsided.
const GOLD_SHARE_BEFORE_ARMY: float = 0.2
const STOCK_IMBALANCE: int = 150

func _gold_share() -> float:
	var share: float = ai.profile.gold_worker_share
	var has_military := false
	for building in ai.my_buildings:
		if not building.is_under_construction and ai.building_role(building) == AiPlayer.BuildingRole.MILITARY:
			has_military = true
			break
	if not has_military:
		share = minf(share, GOLD_SHARE_BEFORE_ARMY)
	var wood: int = ai.stock(AiPlayer.WOOD)
	var gold: int = ai.stock(AiPlayer.GOLD)
	if gold > wood + STOCK_IMBALANCE:
		share *= 0.4
	elif wood > gold + STOCK_IMBALANCE * 3:
		## Wood piling up while gold holds the army back.
		share = MAX_GOLD_SHARE
	elif wood > gold + STOCK_IMBALANCE:
		share = minf(share * 1.5, MAX_GOLD_SHARE)
	return share

const MAX_GOLD_SHARE: float = 0.7

## {wood: int, gold: int, idle: Array[Unit], wood_workers, gold_workers}.
## Builders and anyone fighting count as neither.
func _count_jobs() -> Dictionary:
	var jobs := {wood = 0, gold = 0, idle = [] as Array[Unit], wood_workers = [] as Array[Unit], gold_workers = [] as Array[Unit]}
	for villager in ai.villagers:
		match villager.status_command:
			Unit.Command.NONE:
				jobs.idle.append(villager)
			Unit.Command.GATHER:
				## Untyped: a felled tree is freed before the villager lets go
				## of it, and a freed object can't go in a typed variable.
				var node = villager.target_resource
				var type: ResourceType = node.resource_type if is_instance_valid(node) else villager.status_carried_type
				if type == AiPlayer.GOLD:
					jobs.gold += 1
					jobs.gold_workers.append(villager)
				else:
					jobs.wood += 1
					jobs.wood_workers.append(villager)
	return jobs

func _pick_unloaded(workers: Array[Unit]) -> Unit:
	var best: Unit = workers[0]
	for worker in workers:
		if worker.status_carried_amount < best.status_carried_amount:
			best = worker
	return best

func _send_to_gather(villager: Unit, gold: bool, gold_sources: Array) -> bool:
	var node: Gatherable = _best_gold_source(villager, gold_sources) if gold else _best_tree(villager)
	if node == null:
		return false
	ai.order_target([villager], node)
	return true

## Deposits under our own finished Mines (anyone can technically gather a
## mined deposit, but walking to another player's is asking to die).
func _gold_sources() -> Array:
	var sources: Array = []
	for building in ai.my_buildings:
		if building.is_under_construction:
			continue
		var deposit = building.linked_deposit
		if is_instance_valid(deposit) and deposit.can_be_gathered() and deposit.amount_remaining > 0:
			sources.append(deposit)
	return sources

func _best_gold_source(villager: Unit, sources: Array) -> Gatherable:
	var best: Gatherable = null
	var best_score := INF
	for deposit in sources:
		if not is_instance_valid(deposit) or not deposit.can_accept_gatherer() or ai.combat.is_threatened(deposit.global_position):
			continue
		var score: float = villager.global_position.distance_to(deposit.global_position) + deposit.gatherers.size() * 2.0
		if score < best_score:
			best_score = score
			best = deposit
	return best

## Near home first, then near the villager, then least crowded — skipping
## any tree no path leads to (the inside of a thick forest, a cut-off ledge).
func _best_tree(villager: Unit) -> Gatherable:
	_refresh_wood_cache()
	for attempt in TREE_REACH_ATTEMPTS:
		var best: Gatherable = null
		var best_score := INF
		for node in _wood_nodes:
			if not is_instance_valid(node) or not node.can_accept_gatherer() or node.gatherers.size() >= MAX_GATHERERS_PER_TREE:
				continue
			if _judged_unreachable(node.get_instance_id()) or ai.combat.is_threatened(node.global_position):
				continue
			var score: float = node.global_position.distance_to(ai.home) \
					+ node.global_position.distance_to(villager.global_position) * 0.5 \
					+ node.gatherers.size() * 4.0
			if score < best_score:
				best_score = score
				best = node
		if best == null:
			return null
		## No settled navmesh to judge by (none yet, or mid re-bake): take it,
		## and judge it next time.
		if not ai.nav_settled():
			return best
		var id: int = best.get_instance_id()
		if _tree_reachable.get(id) != true:
			if ai.is_reachable(best.global_position, best.gather_range + TREE_REACH_SLACK):
				_tree_reachable[id] = true
			else:
				_tree_reachable[id] = ai.game_time
		if _tree_reachable[id] == true:
			return best
	return null

## Whether this tree was found unreachable recently enough to still trust.
func _judged_unreachable(id: int) -> bool:
	var verdict = _tree_reachable.get(id)
	return verdict != null and verdict != true and ai.game_time - float(verdict) < TREE_UNREACHABLE_RECHECK_SECONDS

## Trees tried per pick before giving up for this think. Generous: some
## corners have a dozen or two unreachable trees nearest home that would
## otherwise make every pick fail (and send the villager to gold instead)
## until they'd all been tried.
const TREE_REACH_ATTEMPTS: int = 40
const TREE_REACH_SLACK: float = 1.5
## Tree instance id -> true once a path from home is known to reach it (kept
## for good — trees don't move), or the game_time it was last found
## unreachable. That verdict is only trusted for
## TREE_UNREACHABLE_RECHECK_SECONDS: the navmesh is re-baked whenever a
## building goes up or comes down (the very start of a match included), and a
## tree checked mid-bake can read as cut off when it isn't.
var _tree_reachable: Dictionary = {}
const TREE_UNREACHABLE_RECHECK_SECONDS: float = 45.0

func _refresh_wood_cache() -> void:
	if ai.game_time - _wood_cache_age < WOOD_CACHE_SECONDS:
		return
	_wood_cache_age = ai.game_time
	_wood_nodes.clear()
	for node in ai.get_tree().get_nodes_in_group("gatherables"):
		var gatherable := node as Gatherable
		if gatherable == null or gatherable.resource_type != AiPlayer.WOOD or not gatherable.can_be_gathered():
			continue
		if gatherable.owner_peer_id != 0 and gatherable.owner_peer_id != ai.peer_id:
			continue
		if gatherable.global_position.distance_to(ai.home) > MAX_WOOD_DISTANCE or ai.is_dangerous(gatherable.global_position):
			continue
		_wood_nodes.append(gatherable)

## Every site of ours with nobody on the way to it gets someone sent — the
## original builders can die, or get pulled off by being attacked.
func _staff_construction_sites() -> void:
	for building in ai.my_buildings:
		if not building.is_under_construction or ai.builder.is_abandoned(building):
			continue
		var assigned := 0
		for villager in ai.villagers:
			if villager.build_target == building:
				assigned += 1
		if assigned > 0 or not ai.use_order():
			continue
		var builders := pick_builders(building.global_position, 1)
		if not builders.is_empty():
			ai.order_target(builders, building)

## The `count` villagers best suited to leave what they're doing and build at
## `pos`: idle first, then wood cutters, nearest first — gold miners and
## anyone already building are left alone.
func pick_builders(pos: Vector3, count: int) -> Array[Unit]:
	var candidates: Array[Unit] = []
	for villager in ai.villagers:
		if villager.status_command == Unit.Command.NONE:
			candidates.append(villager)
		elif villager.status_command == Unit.Command.GATHER and is_instance_valid(villager.target_resource) \
				and villager.target_resource.resource_type == AiPlayer.WOOD:
			candidates.append(villager)
	candidates.sort_custom(func(a: Unit, b: Unit) -> bool:
		var a_idle := a.status_command == Unit.Command.NONE
		var b_idle := b.status_command == Unit.Command.NONE
		if a_idle != b_idle:
			return a_idle
		return a.global_position.distance_squared_to(pos) < b.global_position.distance_squared_to(pos))
	if candidates.size() > count:
		candidates.resize(count)
	return candidates
