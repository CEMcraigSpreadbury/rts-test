class_name AiTactics
extends RefCounted
## Battlefield tactics on top of AiCombat's waves: the things a player does
## with an army once it's in a fight, rather than where to send it.
##
## Re-facing: a block taking hits in its flank or rear (see Unit.last_flanked_ms)
## turns to meet the attacker after AiProfile.reface_reaction_seconds — the
## whole block if most of it is caught, otherwise just the part that is, so
## the front isn't handed to the enemy it was already fighting. Blocks never
## turn on their own (Unit._flank_multiplier), so without this an AI army
## would stand and die to any flank attack.
##
## Cavalry: a wave's chargers (Unit.can_charge) leave the block once there's
## an enemy about, pick a target — archers and siege first, spearmen last —
## and ride round to its rear quarter before charging, so a block's front (and
## any braced spears in it) never takes the charge. With
## AiProfile.cavalry_recharge they then wheel away to charge again once their
## charge is spent, instead of staying locked in a melee they're poor at.

## Hits from the flank/rear this recent count as the block being flanked now.
const FLANK_RECENT_MS: int = 3000
## A group turns as a whole once at least this share of it is being flanked
## (or anything is, with nothing in front of it); otherwise the flanked part
## turns on its own, once there are at least FLANKED_MIN_UNITS of it.
const WHOLE_BLOCK_SHARE: float = 0.5
const FLANKED_MIN_UNITS: int = 2
## A group isn't re-faced again within this long.
const REFACE_COOLDOWN: float = 6.0

## Enemies within this of the wave's middle are what its cavalry goes after.
const CAV_ENGAGE_RADIUS: float = 30.0
## How far out beside/behind a block the cavalry forms up to charge from.
const FLANK_OFFSET: float = 8.0
## The cavalry counts as formed up this close to its flank point...
const FLANK_ARRIVE_RADIUS: float = 3.0
## ...and charges anyway after this long getting there.
const FLANK_TIMEOUT: float = 12.0
## Wheeling away to charge again: how far, when (spent and fighting this
## long), and the longest it takes before turning back in.
const WHEEL_DISTANCE: float = 12.0
const WHEEL_AFTER: float = 3.0
const WHEEL_TIMEOUT: float = 6.0
## Target preference, as meters of distance: negative is more wanted.
const ARCHER_PREFERENCE: float = -15.0
const SIEGE_PREFERENCE: float = -20.0
const SPEAR_AVOIDANCE: float = 25.0
const CAVALRY_AVOIDANCE: float = 5.0

enum CavState { WITH_WAVE, FLANKING, CHARGING, WHEELING }

var ai: AiPlayer
var combat: AiCombat

var _cav_state: CavState = CavState.WITH_WAVE
var _cav_target: Unit = null
var _cav_point: Vector3 = Vector3.ZERO
var _cav_state_since: float = 0.0
var _cavalry: Array[Unit] = []

## Group key (see _reface) -> game_time it was last re-faced / first seen flanked.
var _last_reface: Dictionary = {}
var _flank_first_seen: Dictionary = {}

func _init(p_ai: AiPlayer, p_combat: AiCombat) -> void:
	ai = p_ai
	combat = p_combat

func think() -> void:
	_update_cavalry()
	var block: Array[Unit] = []
	for unit in combat.wave:
		if not is_detached(unit):
			block.append(unit)
	_reface(&"wave", block)
	_reface(&"home", combat._home_army())

## Off on a cavalry manoeuvre rather than moving with the wave — the wave's
## own re-sending (stragglers, targets) leaves these alone.
func is_detached(unit: Unit) -> bool:
	return _cav_state != CavState.WITH_WAVE and _cavalry.has(unit)

## The wave was re-ordered as a whole (new target, sent home): the cavalry
## went with it.
func reset() -> void:
	_cav_state = CavState.WITH_WAVE
	_cav_target = null
	_cavalry.clear()

## --- Re-facing ---

func _reface(key: StringName, group: Array[Unit]) -> void:
	if ai.profile.reface_reaction_seconds < 0.0 or group.size() < 2:
		return
	var now := Time.get_ticks_msec()
	var flanked: Array[Unit] = []
	var flanker: Unit = null
	var flanker_dist := INF
	for unit in group:
		if now - unit.last_flanked_ms > FLANK_RECENT_MS:
			continue
		flanked.append(unit)
		if not is_instance_valid(unit.last_flanker):
			continue
		var attacker := unit.last_flanker as Unit
		if attacker != null and attacker.status_activity != Unit.Activity.DEAD:
			var dist := unit.global_position.distance_to(attacker.global_position)
			if dist < flanker_dist:
				flanker = attacker
				flanker_dist = dist
	if flanked.is_empty() or flanker == null:
		_flank_first_seen.erase(key)
		return
	if not _flank_first_seen.has(key):
		_flank_first_seen[key] = ai.game_time
	if ai.game_time - float(_flank_first_seen[key]) < ai.profile.reface_reaction_seconds:
		return
	if ai.game_time - float(_last_reface.get(key, -INF)) < REFACE_COOLDOWN:
		return
	var whole: bool = flanked.size() >= group.size() * WHOLE_BLOCK_SHARE or not _enemy_in_front(flanked[0])
	if not whole and flanked.size() < FLANKED_MIN_UNITS:
		return
	ai.order_target(group if whole else flanked, flanker)
	_last_reface[key] = ai.game_time
	_flank_first_seen.erase(key)

## Whether anything hostile stands in the front arc of `unit`'s block — if
## not, there's no front to keep and the whole block turns.
func _enemy_in_front(unit: Unit) -> bool:
	for enemy in combat._hostiles_near(unit.global_position, AiCombat.LOCAL_FIGHT_RADIUS):
		if unit._flank_multiplier(enemy.global_position) <= 1.0:
			return true
	return false

## --- Cavalry ---

func _update_cavalry() -> void:
	_cavalry.clear()
	if not ai.profile.cavalry_tactics:
		return
	for unit in combat.wave:
		if unit.can_charge:
			_cavalry.append(unit)
	if _cavalry.is_empty():
		_cav_state = CavState.WITH_WAVE
		return
	var enemies := combat._hostiles_near(ai.group_centroid(combat.wave), CAV_ENGAGE_RADIUS)
	if enemies.is_empty():
		if _cav_state != CavState.WITH_WAVE:
			ai.order_move(_cavalry, combat.wave_target, true)
			_cav_state = CavState.WITH_WAVE
			_cav_target = null
		return
	var target_alive := _cav_target != null and is_instance_valid(_cav_target) \
			and _cav_target.status_activity != Unit.Activity.DEAD
	if not target_alive:
		_cav_target = _pick_cavalry_target(enemies)
		if _cav_target == null:
			return
		_approach(_cav_target)
		return
	var elapsed := ai.game_time - _cav_state_since
	var centre := ai.group_centroid(_cavalry)
	match _cav_state:
		CavState.WITH_WAVE:
			_approach(_cav_target)
		CavState.FLANKING:
			if _flat(centre, _cav_point) <= FLANK_ARRIVE_RADIUS or elapsed >= FLANK_TIMEOUT:
				_charge(_cav_target)
		CavState.CHARGING:
			if ai.profile.cavalry_recharge and elapsed >= WHEEL_AFTER and _all_spent():
				var away := centre - _cav_target.global_position
				away.y = 0.0
				away = away.normalized() if away.length_squared() > 0.0001 else Vector3.BACK
				_set_state(CavState.WHEELING, ai.nearest_navmesh_point(centre + away * WHEEL_DISTANCE))
				ai.order_move(_cavalry, _cav_point)
		CavState.WHEELING:
			if _flat(centre, _cav_point) <= FLANK_ARRIVE_RADIUS or elapsed >= WHEEL_TIMEOUT:
				_approach(_cav_target)

## Nearest by distance, weighted toward what cavalry is for (archers, siege)
## and away from what it isn't (spearmen, other cavalry).
func _pick_cavalry_target(enemies: Array[Unit]) -> Unit:
	var from := ai.group_centroid(_cavalry)
	var best: Unit = null
	var best_score := INF
	for enemy in enemies:
		var score := from.distance_to(enemy.global_position)
		match enemy.armor_class:
			Unit.ArmorClass.ARCHER:
				score += ARCHER_PREFERENCE
			Unit.ArmorClass.SIEGE:
				score += SIEGE_PREFERENCE
			Unit.ArmorClass.CAVALRY:
				score += CAVALRY_AVOIDANCE
		if enemy.can_brace:
			score += SPEAR_AVOIDANCE
		if score < best_score:
			best = enemy
			best_score = score
	return best

## A target standing in a block is ridden round to its rear quarter first —
## out wide on the nearer side, then in behind — so the charge never meets
## its front (or braced spears). Anything else is charged straight away.
func _approach(target: Unit) -> void:
	var facing: Vector3 = target.formation_facing
	if facing == Vector3.ZERO:
		_charge(target)
		return
	var centre := ai.group_centroid(_cavalry)
	## Already round its side or behind it, charge ready: straight in. Spent,
	## the ride round is what rearms it (Unit.CHARGE_REARM_DISTANCE).
	if target._flank_multiplier(centre) > 1.0 and not _all_spent():
		_charge(target)
		return
	var right := Vector3(facing.z, 0.0, -facing.x)
	var side := 1.0 if (centre - target.global_position).dot(right) >= 0.0 else -1.0
	var wide := ai.nearest_navmesh_point(target.global_position + right * side * (FLANK_OFFSET + 4.0))
	var behind := ai.nearest_navmesh_point(target.global_position + right * side * FLANK_OFFSET - facing * FLANK_OFFSET * 0.75)
	_set_state(CavState.FLANKING, behind)
	ai.order_move(_cavalry, wide)
	ai.order_move(_cavalry, behind, false, true)

func _charge(target: Unit) -> void:
	_set_state(CavState.CHARGING, target.global_position)
	ai.order_target(_cavalry, target)

func _set_state(state: CavState, point: Vector3) -> void:
	_cav_state = state
	_cav_point = point
	_cav_state_since = ai.game_time

func _all_spent() -> bool:
	for unit in _cavalry:
		if unit.is_charge_ready():
			return false
	return true

static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
