class_name Research
extends Node
## Research points and what players buy with them from their Ruler's tree
## (see Ruler). Points are host-authoritative and banked in ResourceStockpile
## like any other resource, so each player is only ever told their own total.
## Earned three ways: a slow trickle (here), kills (award_kill, called from
## Unit._die) and holding capture points (Objective._tick_research).
##
## Purchases are validated by the host (buy_as) but then broadcast to every
## peer, since what someone owns changes numbers every peer shows — an enemy's
## health bars, your own fog of war. Passive effects are read through
## bonus(peer_id, stat); the ones that change a unit or building's own stats
## are written onto it once (apply_node_to).

## The local player's own purchases changed (see my_owned).
signal owned_changed

const RESOURCE: ResourceType = preload("res://resources/research_resource_type.tres")
const GOLD: ResourceType = preload("res://resources/gold_resource_type.tres")
const WOOD: ResourceType = preload("res://resources/wood_resource_type.tres")
const TRICKLE_PER_SECOND: float = 1.0 / 20.0
## A kill is worth one point per this much of the victim's cost. Fractions
## carry over to the killer's next kill (see _kill_fraction), so a Soldier is
## about half a point and a Shrine monster about five.
const KILL_RESOURCES_PER_POINT: float = 75.0
## Relentless (Stat.LOW_HEALTH_DAMAGE) kicks in below this fraction of max health.
const LOW_HEALTH_FRACTION: float = 0.3
const PERIODIC_INCOME_INTERVAL: float = 60.0
## Regeneration (Stat.REGENERATION) waits this long after a unit last took
## damage, and never heals a unit mid-swing.
const REGEN_COMBAT_COOLDOWN_MS: int = 5000
const REGEN_INTERVAL: float = 1.0
const APPLIED_META: StringName = &"research_applied"
## How long after a power hits a unit its death still counts as that power's kill.
const POWER_CREDIT_SECONDS: float = 2.0
const SUMMON_SPACING: float = 1.2

var main: Main

static var _instance: Research = null

## Every peer: peer_id -> Array[int] of bought indices into their Ruler's nodes.
var _owned: Dictionary = {}
## Every peer: peer_id -> { ResearchNode.Stat: float }, summed over _owned.
var _bonuses: Dictionary = {}
## The local player's own purchases.
var my_owned: Array[int] = []
## Host-only, for tuning: peer_id -> { &"trickle" / &"kills" / &"points": total earned }.
var earned: Dictionary = {}

## Match clock for powers (see now()): paused with the tree in single player,
## unlike Time.get_ticks_msec().
var _time: float = 0.0
## Host-only: peer_id -> { node index: now() it's ready again }.
var _power_ready_at: Dictionary = {}
## The local player's own cooldowns: node index -> [ready_at, duration].
var _my_cooldowns: Dictionary = {}
## Host-only heals over time: [{target, per_second, remaining, carry}].
var _heals: Array = []
## Host-only Muster summons: [{unit, until}].
var _summons: Array = []

## Host-only: peer_id -> trickle earned but not yet a whole point.
var _trickle_fraction: Dictionary = {}
## Host-only: peer_id -> kill value earned but not yet a whole point.
var _kill_fraction: Dictionary = {}
## Host-only: peer_id -> seconds towards the next Stat.PERIODIC_INCOME payout.
var _income_timer: Dictionary = {}
var _regen_timer: float = 0.0

func _enter_tree() -> void:
	_instance = self

func _exit_tree() -> void:
	if _instance == self:
		_instance = null

## 0.0 outside a match, for a peer with nothing that grants `stat`, or for
## neutral (peer 0).
static func bonus(peer_id: int, stat: ResearchNode.Stat) -> float:
	if _instance == null:
		return 0.0
	return _instance._bonuses.get(peer_id, {}).get(stat, 0.0)

## Host only. Every research point anyone earns comes through here.
static func earn(peer_id: int, amount: int, source: StringName) -> void:
	if amount <= 0:
		return
	ResourceStockpile.add(peer_id, RESOURCE, amount)
	if _instance != null:
		var tally: Dictionary = _instance.earned.get(peer_id, {})
		tally[source] = tally.get(source, 0) + amount
		_instance.earned[peer_id] = tally

static func now() -> float:
	return _instance._time if _instance != null else 0.0

func _physics_process(delta: float) -> void:
	_time += delta
	if not multiplayer.is_server() or main.game_over:
		return
	_tick_heals(delta)
	_tick_summons()
	for peer_id in main.main_base_count_by_peer.keys():
		if not main.is_peer_active(peer_id):
			continue
		_tick_trickle(peer_id, delta)
		_tick_periodic_income(peer_id, delta)
	_regen_timer += delta
	if _regen_timer >= REGEN_INTERVAL:
		_regen_timer -= REGEN_INTERVAL
		_tick_regeneration()

func _tick_trickle(peer_id: int, delta: float) -> void:
	var rate := TRICKLE_PER_SECOND * (1.0 + bonus(peer_id, ResearchNode.Stat.RESEARCH_TRICKLE))
	var fraction: float = _trickle_fraction.get(peer_id, 0.0) + rate * delta
	var whole := int(fraction)
	_trickle_fraction[peer_id] = fraction - float(whole)
	earn(peer_id, whole, &"trickle")

func _tick_periodic_income(peer_id: int, delta: float) -> void:
	var amount := roundi(bonus(peer_id, ResearchNode.Stat.PERIODIC_INCOME))
	if amount <= 0:
		return
	var timer: float = _income_timer.get(peer_id, 0.0) + delta
	if timer >= PERIODIC_INCOME_INTERVAL:
		timer -= PERIODIC_INCOME_INTERVAL
		ResourceStockpile.add(peer_id, GOLD, amount)
		ResourceStockpile.add(peer_id, WOOD, amount)
	_income_timer[peer_id] = timer

func _tick_regeneration() -> void:
	var now := Time.get_ticks_msec()
	for node in main.units_root.get_children():
		var unit := node as Unit
		if unit == null or unit.status_activity == Unit.Activity.DEAD or unit.status_current_health >= unit.max_health:
			continue
		var amount := bonus(unit.owner_peer_id, ResearchNode.Stat.REGENERATION) * REGEN_INTERVAL
		if amount <= 0.0 or now - unit.last_damaged_msec < REGEN_COMBAT_COOLDOWN_MS \
				or unit.status_activity == Unit.Activity.ATTACKING:
			continue
		unit.heal(maxi(roundi(amount), 1))

## Host only. Anything not the killer's own counts — enemy players' units and
## neutral guards alike. `credit_peer` is who to credit when no attacking unit
## or building did it (a power, see Unit.power_credit_peer). Summons are worth
## nothing.
func award_kill(victim: Unit, attacker: Node3D, credit_peer: int = 0) -> void:
	if main.game_over or victim.summoned:
		return
	var killer := credit_peer
	var by_unit := false
	if attacker != null and is_instance_valid(attacker) and "owner_peer_id" in attacker:
		killer = attacker.owner_peer_id
		by_unit = attacker is Unit
	if killer <= 0 or not Teams.is_enemy(killer, victim.owner_peer_id) or not main.is_peer_active(killer):
		return
	var fraction: float = _kill_fraction.get(killer, 0.0) + kill_value(victim)
	var whole := int(fraction)
	_kill_fraction[killer] = fraction - float(whole)
	earn(killer, whole, &"kills")
	var kill_heal := roundi(bonus(killer, ResearchNode.Stat.KILL_HEAL))
	if kill_heal > 0 and by_unit:
		attacker.heal(kill_heal)

static func kill_value(victim: Unit) -> float:
	var total := 0
	for cost in victim.costs:
		total += cost.amount
	return total / KILL_RESOURCES_PER_POINT

## --- Buying ---

## The Ruler a player picked. A pick still on Random here (running main.tscn
## straight from the editor never goes through the lobby) falls back to the
## first.
static func ruler_for(peer_id: int) -> Ruler:
	var rulers := Ruler.list_all()
	if rulers.is_empty():
		return null
	var index: int = Network.players.get(peer_id, {}).get("ruler_index", 0)
	return rulers[clampi(index, 0, rulers.size() - 1)]

static func node_costs(node: ResearchNode) -> Array[ResourceCost]:
	var cost := ResourceCost.new()
	cost.resource_type = RESOURCE
	cost.amount = node.cost
	var costs: Array[ResourceCost] = [cost]
	return costs

## Whether everything `node` requires is in `owned` (indices into ruler.nodes).
static func requirements_met(ruler: Ruler, node: ResearchNode, owned: Array[int]) -> bool:
	for required in node.requires:
		if not owned.has(ruler.nodes.find(required)):
			return false
	return true

func request_buy(index: int) -> void:
	if multiplayer.is_server():
		buy_as(multiplayer.get_unique_id(), index)
	else:
		_rpc_request_buy.rpc_id(1, index)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_buy(index: int) -> void:
	if multiplayer.is_server():
		buy_as(multiplayer.get_remote_sender_id(), index)

## Host only — every purchase, human or AI, is validated here. Returns
## whether it went through.
func buy_as(peer_id: int, index: int) -> bool:
	if main.game_over or not main.is_peer_active(peer_id):
		return false
	var ruler := ruler_for(peer_id)
	if ruler == null or index < 0 or index >= ruler.nodes.size():
		return false
	var owned := owned_by(peer_id)
	var node: ResearchNode = ruler.nodes[index]
	if owned.has(index) or not requirements_met(ruler, node, owned):
		return false
	## A scenario can cap how far a Ruler's tree goes, or shut it off entirely.
	if not MatchRules.active().research_allowed(peer_id, node):
		return false
	var costs := node_costs(node)
	if not ResourceStockpile.can_afford(peer_id, costs):
		return false
	ResourceStockpile.spend(peer_id, costs)
	owned.append(index)
	_rpc_owned.rpc(peer_id, owned)
	## Host-side already, and the buyer is known, so this goes straight in as
	## an event rather than through the client-input relay.
	if main.quests != null:
		main.quests.notify(&"player_input",
				{peer_id = peer_id, kind = "research_bought", detail = node.node_name})
	## One-off, host-side effects of the purchase itself.
	var population := roundi(node.effects.get(ResearchNode.Stat.POPULATION_CAP, 0.0))
	if population > 0:
		Population.add_cap(peer_id, population)
	return true

func owned_by(peer_id: int) -> Array[int]:
	var owned: Array[int] = []
	owned.assign(_owned.get(peer_id, []))
	return owned

@rpc("authority", "call_local", "reliable")
func _rpc_owned(peer_id: int, owned: Array) -> void:
	var previous := owned_by(peer_id)
	var list: Array[int] = []
	list.assign(owned)
	_owned[peer_id] = list
	var ruler := ruler_for(peer_id)
	var totals: Dictionary = {}
	for index in list:
		var node: ResearchNode = ruler.nodes[index]
		for stat in node.effects:
			totals[stat] = totals.get(stat, 0.0) + float(node.effects[stat])
	_bonuses[peer_id] = totals
	for index in list:
		if not previous.has(index):
			_apply_node_to_existing(peer_id, ruler.nodes[index])
	if peer_id == multiplayer.get_unique_id():
		my_owned = list.duplicate()
		owned_changed.emit()

## --- Powers ---

func power_cooldown(peer_id: int, node: ResearchNode) -> float:
	var seconds := node.cooldown * (1.0 - bonus(peer_id, ResearchNode.Stat.POWER_COOLDOWN_REDUCTION))
	if _is_upgraded(peer_id, node):
		seconds *= node.upgraded_cooldown_multiplier
	return seconds

static func _is_upgraded(peer_id: int, node: ResearchNode) -> bool:
	return node.upgraded_by != ResearchNode.Stat.NONE and bonus(peer_id, node.upgraded_by) > 0.0

func request_cast(index: int, target_pos: Vector3) -> void:
	if multiplayer.is_server():
		cast_as(multiplayer.get_unique_id(), index, target_pos)
	else:
		_rpc_request_cast.rpc_id(1, index, target_pos)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_cast(index: int, target_pos: Vector3) -> void:
	if multiplayer.is_server():
		cast_as(multiplayer.get_remote_sender_id(), index, target_pos)

## Host only — every cast, human or AI, is validated here. Returns whether it
## went off.
func cast_as(peer_id: int, index: int, target_pos: Vector3) -> bool:
	if main.game_over or not main.is_peer_active(peer_id):
		return false
	var ruler := ruler_for(peer_id)
	if ruler == null or index < 0 or index >= ruler.nodes.size() or not owned_by(peer_id).has(index):
		return false
	var node: ResearchNode = ruler.nodes[index]
	if node.kind != ResearchNode.Kind.POWER or not is_power_ready(peer_id, index) or not can_see(peer_id, target_pos):
		return false
	var cooldown := power_cooldown(peer_id, node)
	var ready_at: Dictionary = _power_ready_at.get(peer_id, {})
	ready_at[index] = _time + cooldown
	_power_ready_at[peer_id] = ready_at
	if main.quests != null:
		main.quests.notify(&"player_input",
				{peer_id = peer_id, kind = "power_cast", detail = node.node_name})
	if peer_id == multiplayer.get_unique_id():
		_start_my_cooldown(index, cooldown)
	elif Network.can_rpc_to(peer_id):
		_rpc_power_cooldown.rpc_id(peer_id, index, cooldown)
	_apply_power(peer_id, node, target_pos)
	if node.hit_ability != null:
		main.feedback.relay_power_ability_impact(peer_id, index, target_pos)
	else:
		main.feedback.relay_power_effect(target_pos, node.radius, node.effect_color)
	return true

## Host only.
func is_power_ready(peer_id: int, index: int) -> bool:
	return _time >= _power_ready_at.get(peer_id, {}).get(index, 0.0)

## Host only: whether anything `peer_id` owns has `pos` within its vision
## range — the same reach their fog of war draws.
func can_see(peer_id: int, pos: Vector3) -> bool:
	for root in [main.units_root, main.buildings_root]:
		for child in root.get_children():
			## An ally's eyes count, the same way the fog shares their vision.
			if not (child is Unit or child is ProductionBuilding) or Teams.is_enemy(peer_id, child.owner_peer_id):
				continue
			if (child is Unit and child.status_activity == Unit.Activity.DEAD) or (child is ProductionBuilding and child.is_destroyed):
				continue
			if _flat_distance(child.global_position, pos) <= child.vision_range:
				return true
	return false

static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _apply_power(peer_id: int, node: ResearchNode, pos: Vector3) -> void:
	var targets: Array[Node3D] = []
	var enemies: Array[Unit] = []
	## The "units" group rather than units_root, so objective guards count too.
	for child in get_tree().get_nodes_in_group(&"units"):
		var unit := child as Unit
		if unit == null or unit.status_activity == Unit.Activity.DEAD or _flat_distance(unit.global_position, pos) > node.radius:
			continue
		## An ally's units count as your own here: friendly powers help them,
		## hostile ones never touch them.
		if not Teams.is_enemy(peer_id, unit.owner_peer_id):
			if node.affects_own_units:
				targets.append(unit)
		else:
			enemies.append(unit)
			if node.affects_enemy_units:
				targets.append(unit)
	if node.affects_own_buildings or (node.upgraded_affects_own_buildings and _is_upgraded(peer_id, node)):
		for child in main.buildings_root.get_children():
			var building := child as ProductionBuilding
			if building == null or Teams.is_enemy(peer_id, building.owner_peer_id) or building.is_destroyed or building.is_under_construction \
					or _flat_distance(building.global_position, pos) > node.radius:
				continue
			targets.append(building)
	for target in targets:
		if node.heal_fraction > 0.0:
			var total: float = target.max_health * node.heal_fraction
			if node.duration > 0.0:
				_heals.append({"target": target, "per_second": total / node.duration, "remaining": node.duration, "carry": 0.0})
			else:
				target.heal(roundi(total))
		for buff in node.buffs:
			target.buffs.add(buff, float(node.buffs[buff]), node.duration)
	## Anything a lasting power landed on is washed in its colour until it ends.
	if node.duration > 0.0 and (not node.buffs.is_empty() or node.heal_fraction > 0.0) and not targets.is_empty():
		main.feedback.relay_buff_tints(targets, node.effect_color, node.duration)
	if node.hit_ability != null:
		for victim in enemies:
			if not is_instance_valid(victim):
				continue
			victim.power_credit_peer = peer_id
			victim.power_credit_time = _time
			victim.apply_ability_hit(node.hit_ability, null)
		if node.hit_ability.linger_duration > 0.0:
			AbilityZone.spawn(main, node.hit_ability, pos, peer_id, null)
	for i in node.summon_count:
		_summon(peer_id, node, pos, i)

## Muster. Spread on a small ring so they don't spawn stacked.
func _summon(peer_id: int, node: ResearchNode, pos: Vector3, i: int) -> void:
	if node.summon_scene == null:
		return
	var offset := Vector3.ZERO
	if node.summon_count > 1:
		var angle := TAU * float(i) / float(node.summon_count)
		offset = Vector3(cos(angle), 0.0, sin(angle)) * SUMMON_SPACING
	var unit: Unit = main.unit_spawner.spawn({
		"scene_path": node.summon_scene.resource_path,
		"peer_id": peer_id,
		"tint": main.get_team_tint(peer_id),
		"position": pos + offset,
	})
	unit.summoned = true
	_summons.append({"unit": unit, "until": _time + node.duration})

func _tick_summons() -> void:
	for i in range(_summons.size() - 1, -1, -1):
		var unit = _summons[i]["unit"]
		if not is_instance_valid(unit) or unit.status_activity == Unit.Activity.DEAD:
			_summons.remove_at(i)
		elif _time >= _summons[i]["until"]:
			_summons.remove_at(i)
			unit.expire()

func _tick_heals(delta: float) -> void:
	for i in range(_heals.size() - 1, -1, -1):
		var entry: Dictionary = _heals[i]
		var target = entry["target"]
		if not is_instance_valid(target) or (target is Unit and target.status_activity == Unit.Activity.DEAD) \
				or (target is ProductionBuilding and target.is_destroyed):
			_heals.remove_at(i)
			continue
		var step := minf(delta, entry["remaining"])
		entry["remaining"] -= step
		entry["carry"] += entry["per_second"] * step
		var whole := int(entry["carry"])
		if whole > 0:
			entry["carry"] -= float(whole)
			target.heal(whole)
		if entry["remaining"] <= 0.0:
			_heals.remove_at(i)

@rpc("authority", "call_remote", "reliable")
func _rpc_power_cooldown(index: int, duration: float) -> void:
	_start_my_cooldown(index, duration)

func _start_my_cooldown(index: int, duration: float) -> void:
	_my_cooldowns[index] = [_time + duration, duration]

## The local player's own view of a power's cooldown: 1 just cast, 0 ready.
func power_cooldown_remaining_fraction(index: int) -> float:
	var entry = _my_cooldowns.get(index)
	if entry == null:
		return 0.0
	return clampf((entry[0] - _time) / maxf(entry[1], 0.01), 0.0, 1.0)

## --- Per-unit / per-building stats ---

## Every peer, for each unit/building as it spawns (see Main's spawn
## functions): catches it up on everything its owner already bought.
func apply_all_to(entity: Node) -> void:
	var peer_id: int = entity.owner_peer_id
	var ruler := ruler_for(peer_id)
	if ruler == null:
		return
	for index in owned_by(peer_id):
		apply_node_to(entity, ruler.nodes[index])

func _apply_node_to_existing(peer_id: int, node: ResearchNode) -> void:
	for child in main.units_root.get_children():
		if child is Unit and child.owner_peer_id == peer_id:
			apply_node_to(child, node)
	for child in main.buildings_root.get_children():
		if child is ProductionBuilding and child.owner_peer_id == peer_id:
			apply_node_to(child, node)

## Once per entity per node, however often it's asked — a unit spawned on the
## same tick as a purchase can hear about it from both apply_all_to and the
## purchase broadcast.
func apply_node_to(entity: Node, node: ResearchNode) -> void:
	var applied: Array = entity.get_meta(APPLIED_META, [])
	if applied.has(node):
		return
	applied.append(node)
	entity.set_meta(APPLIED_META, applied)
	for stat in node.effects:
		var amount := float(node.effects[stat])
		if entity is Unit:
			_apply_unit_stat(entity, stat, amount)
		elif entity is ProductionBuilding:
			_apply_building_stat(entity, stat, amount)

func _apply_unit_stat(unit: Unit, stat: int, amount: float) -> void:
	match stat:
		ResearchNode.Stat.COMBAT_MOVE_SPEED:
			if not unit.can_gather:
				unit.move_speed *= 1.0 + amount
		ResearchNode.Stat.INFANTRY_CAVALRY_HEALTH:
			if unit.unit_category == Unit.UnitCategory.INFANTRY or unit.unit_category == Unit.UnitCategory.CAVALRY:
				_raise_unit_health(unit, amount)
		ResearchNode.Stat.MONSTER_HEALTH:
			if unit.is_monster():
				_raise_unit_health(unit, amount)
		ResearchNode.Stat.VISION:
			unit.vision_range *= 1.0 + amount

func _apply_building_stat(building: ProductionBuilding, stat: int, amount: float) -> void:
	match stat:
		ResearchNode.Stat.BUILDING_HEALTH:
			_raise_building_health(building, amount)
		ResearchNode.Stat.WALL_HEALTH:
			if building.role == ProductionBuilding.Role.WALL:
				_raise_building_health(building, amount)
		ResearchNode.Stat.TOWER_DAMAGE:
			if building.attack_range > 0.0:
				building.attack_damage = roundi(building.attack_damage * (1.0 + amount))
		ResearchNode.Stat.TOWER_RANGE:
			if building.attack_range > 0.0:
				building.attack_range *= 1.0 + amount

## Max health everywhere (health bars read it); the host also adds the extra
## to current health, which it alone owns.
func _raise_unit_health(unit: Unit, amount: float) -> void:
	var extra := roundi(unit.max_health * amount)
	unit.max_health += extra
	if multiplayer.is_server():
		unit.status_current_health += extra

func _raise_building_health(building: ProductionBuilding, amount: float) -> void:
	var extra := roundi(building.max_health * amount)
	building.max_health += extra
	if multiplayer.is_server():
		building.current_health += extra
		building.health_fraction = float(building.current_health) / float(maxi(building.max_health, 1))
