class_name AiResearch
extends RefCounted
## Buys the AI's faction powers in order as its research points allow, and
## casts the ones it owns. Plays by a human's rules: every purchase and cast
## goes through Research.buy_as / cast_as with this AI's peer id, so the
## order, cost, cooldown and vision checks all apply.

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
## A summoning power looks this many times further out than its own radius for a fight.
const MUSTER_SEARCH_SCALE: float = 3.0

var ai: AiPlayer
## For tests/tuning.
var nodes_bought: int = 0
var powers_cast: Dictionary = {}

func _init(p_ai: AiPlayer) -> void:
	ai = p_ai

func think() -> void:
	var powers := Research.powers_for(ai.peer_id)
	_buy_next(powers)
	_cast_powers(powers)
	_steer_lance()

## --- Buying ---

func _buy_next(powers: Array[ResearchNode]) -> void:
	var research: Research = ai.main.research
	var index := research.owned_by(ai.peer_id).size()
	if index >= powers.size():
		return
	if ResourceStockpile.can_afford(ai.peer_id, Research.node_costs(powers[index])) and research.buy_as(ai.peer_id, index):
		nodes_bought += 1

## --- Casting ---

func _cast_powers(powers: Array[ResearchNode]) -> void:
	var research: Research = ai.main.research
	for index in research.owned_by(ai.peer_id):
		var node: ResearchNode = powers[index]
		if not research.is_power_ready(ai.peer_id, index):
			continue
		var target: Variant = _power_target(node)
		if target == null:
			continue
		var end: Vector3 = target
		if node.aim == ResearchNode.Aim.LINE:
			## Run the line through the crowd, the way the army faces it.
			var dir := _line_heading(target)
			end = target + dir * node.line_length * 0.5
			target = target - dir * node.line_length * 0.5
		if research.cast_as(ai.peer_id, index, target, end):
			powers_cast[node.node_name] = powers_cast.get(node.node_name, 0) + 1

## Where `node` is worth casting right now, or null.
func _power_target(node: ResearchNode) -> Variant:
	var min_units: int = ai.profile.ability_min_targets
	if min_units <= 0:
		return null
	match node.set_piece:
		&"volley", &"treasure", &"lance", &"colossus", &"charge", &"sword":
			return _best_spot(_positions(ai.combat.visible_enemies), node.radius, min_units)
		&"galleon":
			return _best_spot(_positions(ai.combat.visible_enemies), node.radius, min_units + 2)
		&"ghost_crew", &"overclock":
			## Where its own army is in the thick of it.
			return _best_spot(_positions(_fighting(ai.army)), node.radius, min_units)
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

## From the AI's army (or its base) toward `target`, flat.
func _line_heading(target: Vector3) -> Vector3:
	var from: Variant = null
	var best := INF
	for unit in ai.army:
		if not is_instance_valid(unit):
			continue
		var d: float = Research._flat_distance(unit.global_position, target)
		if d < best:
			best = d
			from = unit.global_position
	if from == null and not ai.my_buildings.is_empty() and is_instance_valid(ai.my_buildings[0]):
		from = ai.my_buildings[0].global_position
	var dir: Vector3 = target - (from if from != null else target + Vector3.BACK)
	dir.y = 0.0
	return dir.normalized() if dir.length_squared() > 0.01 else Vector3.FORWARD

## A Lance of this AI's in the sky: point it at the thickest crowd it can see.
func _steer_lance() -> void:
	var effects: PowerEffects = ai.main.power_effects
	if effects == null or not effects.is_steering(ai.peer_id):
		return
	var spot: Variant = _best_spot(_positions(ai.combat.visible_enemies), PowerEffects.LANCE_RADIUS * 2.0, 1)
	if spot != null:
		effects.set_steer(ai.peer_id, spot)

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
