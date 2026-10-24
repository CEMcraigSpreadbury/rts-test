class_name Research
extends Node
## Research points and the three faction powers players buy with them (see
## Faction.powers, bought in order). Points are host-authoritative and banked in ResourceStockpile
## like any other resource, so each player is only ever told their own total.
## Earned three ways: villagers reading in a Library (Unit's gather tick on its
## Books, see Gatherable.pays_at_once), kills (award_kill, called from
## Unit._die) and holding capture points (Objective._tick_research).
##
## Purchases are validated by the host (buy_as) but then broadcast to every
## peer, so every peer can draw any player's powers when they land.

## The local player's own purchases changed (see my_owned).
signal owned_changed

const RESOURCE: ResourceType = preload("res://resources/research_resource_type.tres")
## A kill is worth one point per this much of the victim's cost. Fractions
## carry over to the killer's next kill (see _kill_fraction), so a Soldier is
## about half a point and a Shrine monster about five.
const KILL_RESOURCES_PER_POINT: float = 75.0
## How long after a power hits a unit its death still counts as that power's kill.
const POWER_CREDIT_SECONDS: float = 2.0
const SUMMON_SPACING: float = 1.2

var main: Main

static var _instance: Research = null

## Every peer: peer_id -> Array[int] of bought indices into their faction's powers.
var _owned: Dictionary = {}
## The local player's own purchases.
var my_owned: Array[int] = []
## Host-only, for tuning: peer_id -> { &"reading" / &"kills" / &"points": total earned }.
var earned: Dictionary = {}

## Match clock for powers (see now()): paused with the game in single player,
## unlike the wall clock (Time.get_ticks_msec()).
var _time: float = 0.0
## Host-only: peer_id -> { node index: now() it's ready again }.
var _power_ready_at: Dictionary = {}
## The local player's own cooldowns: node index -> [ready_at, duration].
var _my_cooldowns: Dictionary = {}
## Host-only heals over time: [{target, per_second, remaining, carry}].
var _heals: Array = []
## Host-only summons: [{unit, until}].
var _summons: Array = []

## Host-only: peer_id -> kill value earned but not yet a whole point.
var _kill_fraction: Dictionary = {}

func _enter_tree() -> void:
	_instance = self

func _exit_tree() -> void:
	if _instance == self:
		_instance = null

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
## Host only. Anything not the killer's own counts — enemy players' units and
## neutral guards alike. `credit_peer` is who to credit when no attacking unit
## or building did it (a power, see Unit.power_credit_peer). Summons are worth
## nothing.
func award_kill(victim: Unit, attacker: Node3D, credit_peer: int = 0) -> void:
	if main.game_over or victim.summoned:
		return
	var killer := credit_peer
	if attacker != null and is_instance_valid(attacker) and "owner_peer_id" in attacker:
		killer = attacker.owner_peer_id
	if killer <= 0 or not Teams.is_enemy(killer, victim.owner_peer_id) or not main.is_peer_active(killer):
		return
	var fraction: float = _kill_fraction.get(killer, 0.0) + kill_value(victim)
	var whole := int(fraction)
	_kill_fraction[killer] = fraction - float(whole)
	earn(killer, whole, &"kills")

static func kill_value(victim: Unit) -> float:
	var total := 0
	for cost in victim.costs:
		total += cost.amount
	return total / KILL_RESOURCES_PER_POINT

## --- Buying ---

## The powers a player's faction has, in buying order (see Faction.powers).
static func powers_for(peer_id: int) -> Array[ResearchNode]:
	var none: Array[ResearchNode] = []
	if _instance == null or _instance.main == null:
		return none
	var faction: Faction = _instance.main.faction_by_peer.get(peer_id)
	if faction == null:
		faction = _instance.main._faction_for_peer(peer_id)
	return faction.powers if faction != null else none

static func node_costs(node: ResearchNode) -> Array[ResourceCost]:
	var cost := ResourceCost.new()
	cost.resource_type = RESOURCE
	cost.amount = node.cost
	var costs: Array[ResourceCost] = [cost]
	return costs

## Powers are bought in order: each needs the one before it in `owned`.
static func requirements_met(index: int, owned: Array[int]) -> bool:
	return index == 0 or owned.has(index - 1)

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
	var powers := powers_for(peer_id)
	if index < 0 or index >= powers.size():
		return false
	var owned := owned_by(peer_id)
	var node: ResearchNode = powers[index]
	if owned.has(index) or not requirements_met(index, owned):
		return false
	## A scenario can cap how far a faction's powers go, or shut them off entirely.
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
	return true

func owned_by(peer_id: int) -> Array[int]:
	var owned: Array[int] = []
	owned.assign(_owned.get(peer_id, []))
	return owned

@rpc("authority", "call_local", "reliable")
func _rpc_owned(peer_id: int, owned: Array) -> void:
	var list: Array[int] = []
	list.assign(owned)
	_owned[peer_id] = list
	if peer_id == multiplayer.get_unique_id():
		my_owned = list.duplicate()
		owned_changed.emit()

## --- Powers ---

## `end` is where a LINE power's drag finished (the same as target_pos for a
## POINT one).
func request_cast(index: int, target_pos: Vector3, end: Vector3 = target_pos) -> void:
	if multiplayer.is_server():
		cast_as(multiplayer.get_unique_id(), index, target_pos, end)
	else:
		_rpc_request_cast.rpc_id(1, index, target_pos, end)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_cast(index: int, target_pos: Vector3, end: Vector3) -> void:
	if multiplayer.is_server():
		cast_as(multiplayer.get_remote_sender_id(), index, target_pos, end)

## Host only — every cast, human or AI, is validated here. Returns whether it
## went off. A LINE power only needs its start, middle or end in sight.
func cast_as(peer_id: int, index: int, target_pos: Vector3, end: Vector3 = target_pos) -> bool:
	if main.game_over or not main.is_peer_active(peer_id):
		return false
	var powers := powers_for(peer_id)
	if index < 0 or index >= powers.size() or not owned_by(peer_id).has(index):
		return false
	var node: ResearchNode = powers[index]
	if not is_power_ready(peer_id, index):
		return false
	if node.aim == ResearchNode.Aim.LINE:
		end = line_end(node, target_pos, end)
		if not (can_see(peer_id, target_pos) or can_see(peer_id, target_pos.lerp(end, 0.5)) or can_see(peer_id, end)):
			return false
	elif not can_see(peer_id, target_pos):
		return false
	var cooldown := node.cooldown
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
	if node.set_piece != &"":
		main.power_effects.start(peer_id, node, target_pos, end)
		return true
	_apply_power(peer_id, node, target_pos)
	if node.hit_ability != null:
		main.feedback.relay_power_ability_impact(peer_id, index, target_pos)
	else:
		main.feedback.relay_power_effect(target_pos, node.radius, node.effect_color)
	return true

## A LINE power runs its full line_length from `start` toward `toward`; a drag
## too short to give a direction runs it north (into the screen).
## The line a drag aims: centred on where the button went down (`centre`),
## pointing at where it is now; [start, end].
static func line_centred(node: ResearchNode, centre: Vector3, toward: Vector3) -> Array[Vector3]:
	var dir := toward - centre
	dir.y = 0.0
	if dir.length_squared() < 1.0:
		dir = Vector3.FORWARD
	var half := dir.normalized() * node.line_length * 0.5
	var line: Array[Vector3] = [centre - half, centre + half]
	return line

static func line_end(node: ResearchNode, start: Vector3, toward: Vector3) -> Vector3:
	var dir := toward - start
	dir.y = 0.0
	if dir.length_squared() < 1.0:
		dir = Vector3.FORWARD
	return start + dir.normalized() * node.line_length

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
	if node.affects_own_buildings:
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

## A summoning power. Spread on a small ring so they don't spawn stacked.
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

## Host only: a power's summon (a Ghost Crew ghost) that leaves at `until`.
func track_summon(unit: Unit, until: float) -> void:
	_summons.append({"unit": unit, "until": until})

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
