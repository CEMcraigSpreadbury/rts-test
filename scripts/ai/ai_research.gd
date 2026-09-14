class_name AiResearch
extends RefCounted
## Spends the AI's research points down a fixed path through its Ruler's tree,
## and casts the powers it owns. Plays by a human's rules: every purchase and
## cast goes through Research.buy_as / cast_as with this AI's peer id, so the
## requirements, cost, cooldown and vision checks all apply.

## Buy order per Ruler (by Ruler.ruler_name), as indices into Ruler.nodes —
## every node's requirement comes before it. Army first for the Warlord,
## economy first for the Steward, spells first for the Mystic. A Ruler with no
## path here just buys whatever it can, in tree order.
const PATHS: Dictionary = {
	"Warlord": [2, 0, 1, 4, 6, 5, 9, 8, 11, 7, 10, 3],
	"Steward": [0, 2, 4, 6, 1, 5, 7, 11, 9, 3, 8, 10],
	"Mystic": [0, 3, 6, 1, 4, 9, 2, 11, 7, 5, 8, 10],
}
## A unit counts as hurt for Healing Light below this share of its health.
const HURT_FRACTION: float = 0.7
## Sanctuary waits for a fight that's going badly.
const SANCTUARY_HURT_FRACTION: float = 0.5
## Repair Crews: buildings below this share of their health.
const REPAIR_FRACTION: float = 0.75
## Fortify: a building below this share with enemies this close.
const FORTIFY_FRACTION: float = 0.98
const FORTIFY_THREAT_RADIUS: float = 10.0
## Villagers gathering in the ring before Bountiful Lands is worth it.
const BOUNTIFUL_MIN_VILLAGERS: int = 4
## Busy production buildings in the ring before Industrious Age is worth it.
const INDUSTRIOUS_MIN_BUILDINGS: int = 2
## Muster looks this many times further out than its own radius for a fight.
const MUSTER_SEARCH_SCALE: float = 3.0

var ai: AiPlayer
## For tests/tuning.
var nodes_bought: int = 0
var powers_cast: Dictionary = {}

func _init(p_ai: AiPlayer) -> void:
	ai = p_ai

func think() -> void:
	var ruler := Research.ruler_for(ai.peer_id)
	if ruler == null:
		return
	_buy_next(ruler)
	_cast_powers(ruler)

## --- Buying ---

func _buy_next(ruler: Ruler) -> void:
	var research: Research = ai.main.research
	var owned := research.owned_by(ai.peer_id)
	var path: Array = PATHS.get(ruler.ruler_name, range(ruler.nodes.size()))
	for index in path:
		if owned.has(index):
			continue
		var node: ResearchNode = ruler.nodes[index]
		if not Research.requirements_met(ruler, node, owned):
			continue
		## One at a time, in order — the next node waits for its points
		## rather than being skipped for something cheaper further down.
		if ResourceStockpile.can_afford(ai.peer_id, Research.node_costs(node)) and research.buy_as(ai.peer_id, index):
			nodes_bought += 1
		return

## --- Casting ---

func _cast_powers(ruler: Ruler) -> void:
	var research: Research = ai.main.research
	for index in research.owned_by(ai.peer_id):
		var node: ResearchNode = ruler.nodes[index]
		if node.kind != ResearchNode.Kind.POWER or not research.is_power_ready(ai.peer_id, index):
			continue
		var target: Variant = _power_target(node)
		if target != null and research.cast_as(ai.peer_id, index, target):
			powers_cast[node.node_name] = powers_cast.get(node.node_name, 0) + 1

## Where `node` is worth casting right now, or null.
func _power_target(node: ResearchNode) -> Variant:
	var min_units: int = ai.profile.ability_min_targets
	if min_units <= 0:
		return null
	if node.hit_ability != null or node.affects_enemy_units:
		return _best_spot(_positions(ai.combat.visible_enemies), node.radius, min_units)
	if node.affects_own_buildings:
		return _building_target(node)
	if node.summon_count > 0:
		return _best_spot(_positions(_fighting(ai.army)), node.radius * MUSTER_SEARCH_SCALE, min_units)
	if node.heal_fraction > 0.0:
		var hurt := ai.army.filter(func(u): return _health_fraction(u) < HURT_FRACTION)
		hurt.append_array(ai.villagers.filter(func(u): return _health_fraction(u) < HURT_FRACTION))
		return _best_spot(_positions(hurt), node.radius, min_units)
	if node.buffs.has(ResearchNode.Buff.GATHER_SPEED):
		var gathering := ai.villagers.filter(func(u): return u.status_activity == Unit.Activity.GATHERING)
		return _best_spot(_positions(gathering), node.radius, BOUNTIFUL_MIN_VILLAGERS)
	if node.buffs.has(ResearchNode.Buff.MOVE_SPEED):
		var closing := ai.army.filter(func(u): return u.status_activity == Unit.Activity.TO_TARGET)
		return _best_spot(_positions(closing), node.radius, min_units)
	if node.buffs.has(ResearchNode.Buff.INVULNERABLE):
		var losing := _fighting(ai.army).filter(func(u): return _health_fraction(u) < SANCTUARY_HURT_FRACTION)
		return _best_spot(_positions(losing), node.radius, min_units)
	return _best_spot(_positions(_fighting(ai.army)), node.radius, min_units)

func _building_target(node: ResearchNode) -> Variant:
	var picked: Array = []
	var needed := 1
	for building in ai.my_buildings:
		if building.is_under_construction:
			continue
		var fraction := float(building.current_health) / float(maxi(building.max_health, 1))
		if node.heal_fraction > 0.0:
			if fraction < REPAIR_FRACTION:
				picked.append(building)
		elif node.buffs.has(ResearchNode.Buff.DAMAGE_TAKEN_REDUCTION):
			if fraction < FORTIFY_FRACTION and _enemy_within(building.global_position, FORTIFY_THREAT_RADIUS):
				picked.append(building)
		elif node.buffs.has(ResearchNode.Buff.PRODUCTION_SPEED):
			needed = INDUSTRIOUS_MIN_BUILDINGS
			if not building.queue.is_empty():
				picked.append(building)
	return _best_spot(_positions(picked), node.radius, needed)

## The member of `points` with the most of `points` within `radius` of it —
## the same pick AiCombat makes for a monster's area ability — or null if even
## that catches fewer than `minimum`.
func _best_spot(points: Array[Vector3], radius: float, minimum: int) -> Variant:
	if points.size() < minimum:
		return null
	var best: Variant = null
	var best_count := 0
	for candidate in points:
		var count := 0
		for other in points:
			if Research._flat_distance(candidate, other) <= radius:
				count += 1
		if count > best_count:
			best_count = count
			best = candidate
	return best if best_count >= minimum else null

func _positions(nodes: Array) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for node in nodes:
		if is_instance_valid(node):
			out.append(node.global_position)
	return out

func _fighting(units: Array) -> Array:
	return units.filter(func(u): return is_instance_valid(u) \
			and (u.status_activity == Unit.Activity.ATTACKING or u.status_activity == Unit.Activity.TO_TARGET))

func _health_fraction(unit: Unit) -> float:
	return float(unit.status_current_health) / float(maxi(unit.max_health, 1))

func _enemy_within(pos: Vector3, radius: float) -> bool:
	for enemy in ai.combat.visible_enemies:
		if is_instance_valid(enemy) and Research._flat_distance(enemy.global_position, pos) <= radius:
			return true
	return false
