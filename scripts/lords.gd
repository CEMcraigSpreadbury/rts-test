class_name Lords
extends Node
## Lords lead armies in a Realm match. A Lord is trained at the Town Centre —
## one to start with, and one more for every two settlements held — and every
## unit of his side within COMMAND_RADIUS fights under him: harder hitting,
## better armoured, and steadier (see Morale). That radius is his army; there is
## no roster to manage.
##
## He learns: kills made near him and settlements taken near him are
## experience, and each level makes his command stronger. Your Ruler gives every
## Lord a lean (a Warlord's hit harder, a Steward's are tougher, a Mystic's keep
## their nerve). When he falls the men around him are shaken, and the next Lord
## you raise, after REHIRE_SECONDS, takes up his level.
##
## All host-only; Unit.lord_level and lord_progress are replicated for the HUD.

const UnitGrid = preload("res://scripts/unit_grid.gd")

const COMMAND_RADIUS: float = 30.0
const TICK: float = 0.5
## Experience needed for levels 2, 3, 4 and 5.
const LEVEL_XP: Array[float] = [0.0, 40.0, 120.0, 250.0, 450.0]
const MAX_LEVEL: int = 5
## Experience per point of a slain enemy's price, and for a capture.
const XP_PER_COST: float = 0.1
const XP_PER_CAPTURE: float = 30.0
## His command at level 1, and what each level adds.
const DAMAGE_BASE: float = 0.05
const DAMAGE_PER_LEVEL: float = 0.03
const ARMOR_BASE: int = 1
## Morale regained per second near him, fighting or not.
const MORALE_BASE: float = 2.0
const MORALE_PER_LEVEL: float = 0.5
## A Ruler's lean.
const WARLORD_DAMAGE: float = 0.05
const STEWARD_ARMOR: int = 1
const MYSTIC_MORALE: float = 1.5
## Morale lost by his men when he falls.
const DEATH_SHOCK: float = 25.0
const REHIRE_SECONDS: float = 60.0
## One Lord to start with, one more per this many settlements held.
const SETTLEMENTS_PER_LORD: int = 2

var main: Main
var _timer: float = TICK
## peer_id -> [level, xp] of the best Lord they have lost, for the next one.
var _fallen: Dictionary = {}
## peer_id -> seconds left before another Lord can be raised.
var _rehire: Dictionary = {}

func _ready() -> void:
	set_physics_process(multiplayer.is_server() and MatchRules.realm())

static func level_for(xp: float) -> int:
	var level := 1
	for i in range(1, LEVEL_XP.size()):
		if xp >= LEVEL_XP[i]:
			level = i + 1
	return mini(level, MAX_LEVEL)

## How many more Lords `peer_id` may raise right now, counting any already in
## training (`queued`).
func can_hire(peer_id: int, queued: int) -> bool:
	if float(_rehire.get(peer_id, 0.0)) > 0.0:
		return false
	var settlements := 0
	for node in get_tree().get_nodes_in_group(&"objectives"):
		if node is Objective and node.is_settlement() and node.owner_peer_id == peer_id:
			settlements += 1
	var allowed: int = 1 + settlements / SETTLEMENTS_PER_LORD
	return _lords_of(peer_id).size() + queued < allowed

func _lords_of(peer_id: int) -> Array[Unit]:
	var out: Array[Unit] = []
	for node in get_tree().get_nodes_in_group(&"units"):
		var unit := node as Unit
		if unit != null and unit.is_lord and unit.owner_peer_id == peer_id and unit.status_activity != Unit.Activity.DEAD:
			out.append(unit)
	return out

func _physics_process(delta: float) -> void:
	for peer in _rehire.keys():
		_rehire[peer] = float(_rehire[peer]) - delta
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = TICK
	var lords: Array[Unit] = []
	for node in get_tree().get_nodes_in_group(&"units"):
		var unit := node as Unit
		if unit == null:
			continue
		unit.lord_damage = 0.0
		unit.lord_armor = 0
		unit.lord_morale = 0.0
		if unit.is_lord and unit.status_activity != Unit.Activity.DEAD:
			lords.append(unit)
	for lord in lords:
		_take_up_fallen(lord)
		var damage: float = DAMAGE_BASE + DAMAGE_PER_LEVEL * (lord.lord_level - 1)
		var armor: int = ARMOR_BASE + (lord.lord_level - 1) / 2
		var steady: float = MORALE_BASE + MORALE_PER_LEVEL * (lord.lord_level - 1)
		match _ruler_name(lord.owner_peer_id):
			"Warlord":
				damage += WARLORD_DAMAGE
			"Steward":
				armor += STEWARD_ARMOR
			"Mystic":
				steady += MYSTIC_MORALE
		for unit in UnitGrid.units_near(get_tree(), lord.global_position, COMMAND_RADIUS):
			if unit == lord or unit.owner_peer_id != lord.owner_peer_id or unit.can_gather:
				continue
			unit.lord_damage = maxf(unit.lord_damage, damage)
			unit.lord_armor = maxi(unit.lord_armor, armor)
			unit.lord_morale = maxf(unit.lord_morale, steady)

## A new Lord inherits the best one his side has lost, once.
func _take_up_fallen(lord: Unit) -> void:
	if lord.has_meta(&"lord_ready"):
		return
	lord.set_meta(&"lord_ready", true)
	var fallen: Array = _fallen.get(lord.owner_peer_id, [])
	if not fallen.is_empty():
		_fallen.erase(lord.owner_peer_id)
		_gain(lord, float(fallen[1]))

static func _ruler_name(peer_id: int) -> String:
	var ruler: Ruler = Research.ruler_for(peer_id)
	return ruler.ruler_name if ruler != null else ""

func _gain(lord: Unit, xp: float) -> void:
	lord.lord_xp += xp
	lord.lord_level = level_for(lord.lord_xp)
	var here: float = LEVEL_XP[lord.lord_level - 1]
	var next: float = LEVEL_XP[lord.lord_level] if lord.lord_level < MAX_LEVEL else here
	lord.lord_progress = 10 if next <= here else clampi(int((lord.lord_xp - here) / (next - here) * 10.0), 0, 10)

func _lords_near(peer_id: int, pos: Vector3) -> Array[Unit]:
	var out: Array[Unit] = []
	for lord in _lords_of(peer_id):
		if lord.global_position.distance_to(pos) <= COMMAND_RADIUS:
			out.append(lord)
	return out

## Host only, from Unit._die.
func on_death(victim: Unit, attacker) -> void:
	if not MatchRules.realm() or not multiplayer.is_server():
		return
	if victim.is_lord:
		var best: Array = _fallen.get(victim.owner_peer_id, [0, 0.0])
		if victim.lord_xp >= float(best[1]):
			_fallen[victim.owner_peer_id] = [victim.lord_level, victim.lord_xp]
		_rehire[victim.owner_peer_id] = REHIRE_SECONDS
		for unit in UnitGrid.units_near(get_tree(), victim.global_position, COMMAND_RADIUS):
			if unit.owner_peer_id == victim.owner_peer_id:
				Morale.shake(unit, DEATH_SHOCK)
	if attacker == null or not is_instance_valid(attacker) or not ("owner_peer_id" in attacker):
		return
	var killer: int = attacker.owner_peer_id
	if killer <= 0 or killer == victim.owner_peer_id or victim.hunt_meat > 0:
		return
	var worth := 0
	for cost in victim.costs:
		worth += cost.amount
	for lord in _lords_near(killer, victim.global_position):
		_gain(lord, worth * XP_PER_COST)

## Host only, when a settlement changes hands.
func on_capture(pos: Vector3, new_owner: int) -> void:
	if not MatchRules.realm() or new_owner <= 0:
		return
	for lord in _lords_near(new_owner, pos):
		_gain(lord, XP_PER_CAPTURE)
