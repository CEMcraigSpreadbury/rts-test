class_name Morale
extends Node
## Whether a man stands or runs. Every soldier has a morale from 0 to 100
## (Unit.morale): hits, flank and rear blows, charges and friends dying around
## him wear it down; enemies dying lift it; time away from the fighting, or a
## living officer beside him, brings it back.
##
##   STEADY     fights as normal
##   WAVERING   below WAVER_BELOW: hits for WAVERING_DAMAGE of normal
##   ROUTING    below ROUT_BELOW: runs for home, can't be ordered, won't fight,
##              takes ROUTING_DAMAGE_TAKEN; rallies once clear and steadied
##   SHATTERED  broke a second time: runs all the way home before he rallies
##
## A regiment breaks together: once most of its men are running, the rest go
## with them. Monsters, siege engines, villagers and anything nobody owns never
## break. In a Realm match a starving army loses heart (RealmEconomy).
##
## All of it is host-only; Unit.morale_state and morale_level are replicated.

enum State { STEADY, WAVERING, ROUTING, SHATTERED }

const UnitGrid = preload("res://scripts/unit_grid.gd")

const MAX_MORALE: float = 100.0
## morale_level runs 0..LEVELS, for the HUD.
const LEVELS: int = 10
const WAVER_BELOW: float = 45.0
const STEADY_ABOVE: float = 55.0
const ROUT_BELOW: float = 15.0
const RALLY_ABOVE: float = 60.0

const WAVERING_DAMAGE: float = 0.8
const ROUTING_DAMAGE_TAKEN: float = 1.25

## A hit costs this much for a blow that takes a whole health bar.
const HIT_SHOCK: float = 25.0
const FLANK_SHOCK: float = 3.0
const CHARGED: float = 15.0
## A friend falling within DEATH_RADIUS (less at the edge of it).
const ALLY_DEATH_SHOCK: float = 2.5
const DEATH_RADIUS: float = 8.0
## Every man lost costs the rest of his regiment this, wherever they stand.
const REGIMENT_LOSS_SHOCK: float = 1.5
const OFFICER_LOSS_SHOCK: float = 20.0
const ENEMY_DEATH_LIFT: float = 1.5
## An enemy breaking within ENEMY_ROUT_RADIUS.
const ENEMY_ROUT_LIFT: float = 3.0
const ENEMY_ROUT_RADIUS: float = 15.0

const TICK: float = 0.5
## No enemy this close: out of the fight, and recovering.
const CLEAR_RADIUS: float = 16.0
const RECOVER_CLEAR: float = 8.0
## Per second, in the thick of it, with his regiment's officer this close.
const RECOVER_WITH_OFFICER: float = 1.5
const OFFICER_RADIUS: float = 20.0
const STARVING_DRAIN: float = 0.5
## Shocks to a man within a Lord's command are this much of the usual.
const LORD_STEADYING: float = 0.75
## Share of a regiment running that takes the rest with it.
const REGIMENT_BREAK_SHARE: float = 0.5
## Close enough to the refuge that a shattered man stops running.
const HOME_REACHED: float = 12.0
## With no refuge of his own, a man runs this far from the nearest enemy.
const FLEE_DISTANCE: float = 30.0

var main: Main
var _timer: float = TICK

func _ready() -> void:
	set_physics_process(multiplayer.is_server())

static func unbreakable(unit: Unit) -> bool:
	return unit.owner_peer_id <= 0 or unit.can_gather or not unit.can_fight or unit.summoned or unit.is_lord \
			or unit.hunt_meat > 0 or unit.is_monster() or unit.armor_class == Unit.ArmorClass.SIEGE

## Host only: something shook `unit`. Its state follows on the next tick.
static func shake(unit: Unit, amount: float) -> void:
	if unbreakable(unit) or unit.status_activity == Unit.Activity.DEAD:
		return
	## Under a Lord's eye a blow to the nerve lands softer.
	if amount > 0.0 and unit.lord_morale > 0.0:
		amount *= LORD_STEADYING
	unit.morale -= amount

static func shaken_by_hit(unit: Unit, damage: int, flanked: bool) -> void:
	var amount: float = HIT_SHOCK * float(damage) / float(maxi(unit.max_health, 1))
	if flanked:
		amount += FLANK_SHOCK
	shake(unit, amount)

## Host only, from Unit._die.
func on_death(victim: Unit, _attacker) -> void:
	if victim.owner_peer_id <= 0 and victim.hunt_meat > 0:
		return
	var pos := victim.global_position
	for unit in UnitGrid.units_near(get_tree(), pos, DEATH_RADIUS):
		if unit == victim or not is_instance_valid(unit):
			continue
		if Teams.is_friendly(unit.owner_peer_id, victim.owner_peer_id):
			var falloff: float = 1.0 - 0.5 * unit.global_position.distance_to(pos) / DEATH_RADIUS
			shake(unit, ALLY_DEATH_SHOCK * falloff)
		elif Teams.is_enemy(unit.owner_peer_id, victim.owner_peer_id):
			shake(unit, -ENEMY_DEATH_LIFT)
	var regiment: Regiment = main.regiments.get(victim.regiment_id)
	if regiment != null:
		var shock: float = REGIMENT_LOSS_SHOCK + (OFFICER_LOSS_SHOCK if victim.is_officer else 0.0)
		for unit in regiment.all_units():
			if is_instance_valid(unit) and unit != victim:
				shake(unit, shock)

func _physics_process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = TICK
	## regiment id -> [men, running]
	var bodies: Dictionary = {}
	for node in get_tree().get_nodes_in_group(&"units"):
		var unit := node as Unit
		if unit == null or unit.status_activity == Unit.Activity.DEAD or unbreakable(unit):
			continue
		_tick_unit(unit)
		if unit.regiment_id >= 0 and not unit.is_officer:
			var count: Array = bodies.get(unit.regiment_id, [0, 0])
			count[0] += 1
			if unit.is_routing():
				count[1] += 1
			bodies[unit.regiment_id] = count
	for id in bodies:
		var count: Array = bodies[id]
		if count[1] > 0 and float(count[1]) / float(count[0]) > REGIMENT_BREAK_SHARE:
			var regiment: Regiment = main.regiments.get(id)
			if regiment == null:
				continue
			for unit in regiment.all_units():
				if is_instance_valid(unit) and not unit.is_routing() and not unbreakable(unit) \
						and unit.status_activity != Unit.Activity.DEAD:
					_rout(unit)

func _tick_unit(unit: Unit) -> void:
	var threatened: bool = not UnitGrid.enemies_near(get_tree(), unit.global_position, CLEAR_RADIUS, unit.owner_peer_id).is_empty()
	var rate: float = 0.0
	if not threatened:
		rate = RECOVER_CLEAR
	elif _officer_near(unit):
		rate = RECOVER_WITH_OFFICER
	rate += unit.lord_morale
	if MatchRules.realm() and main.realm_economy.is_starving(unit.owner_peer_id):
		rate = minf(rate, 0.0) - STARVING_DRAIN
	unit.morale += rate * TICK
	match unit.morale_state:
		State.STEADY:
			if unit.morale < ROUT_BELOW:
				_rout(unit)
			elif unit.morale < WAVER_BELOW:
				unit.morale_state = State.WAVERING
		State.WAVERING:
			if unit.morale < ROUT_BELOW:
				_rout(unit)
			elif unit.morale > STEADY_ABOVE:
				unit.morale_state = State.STEADY
		State.ROUTING:
			if unit.morale >= RALLY_ABOVE and not threatened:
				_rally(unit)
			elif unit.status_command == Unit.Command.NONE and threatened:
				_flee(unit)
		State.SHATTERED:
			var home = _refuge(unit)
			var home_reached: bool = home is Vector3 and unit.global_position.distance_to(home) <= HOME_REACHED
			if home_reached and not threatened:
				unit.morale = maxf(unit.morale, RALLY_ABOVE)
				_rally(unit)
			elif unit.status_command == Unit.Command.NONE:
				_flee(unit)

func _officer_near(unit: Unit) -> bool:
	var regiment: Regiment = main.regiments.get(unit.regiment_id)
	if regiment == null or not regiment.has_officer():
		return false
	return regiment.officer.global_position.distance_to(unit.global_position) <= OFFICER_RADIUS

func _rout(unit: Unit) -> void:
	unit.routs += 1
	unit.morale = minf(unit.morale, ROUT_BELOW)
	unit.morale_state = State.SHATTERED if unit.routs >= 2 else State.ROUTING
	_flee(unit)
	for other in UnitGrid.enemies_near(get_tree(), unit.global_position, ENEMY_ROUT_RADIUS, unit.owner_peer_id):
		shake(other, -ENEMY_ROUT_LIFT)

func _rally(unit: Unit) -> void:
	unit.morale_state = State.STEADY
	unit.clear_order_queue()
	unit.command_stop()

func _flee(unit: Unit) -> void:
	unit.clear_order_queue()
	var home = _refuge(unit)
	if home is Vector3:
		unit.command_move(home)
		return
	var enemies: Array[Unit] = UnitGrid.enemies_near(get_tree(), unit.global_position, CLEAR_RADIUS, unit.owner_peer_id)
	if enemies.is_empty():
		unit.command_stop()
		return
	var away: Vector3 = unit.global_position - enemies[0].global_position
	away.y = 0.0
	unit.command_move(unit.global_position + away.normalized() * FLEE_DISTANCE)

## Where a broken man runs: the nearest of his side's Town Centres and held
## capture points, or null when there is none.
func _refuge(unit: Unit) -> Variant:
	var best: Variant = null
	var best_distance: float = INF
	var places: Array = []
	var centre = main.town_centers.get(unit.owner_peer_id)
	if centre != null and is_instance_valid(centre):
		places.append(centre)
	for node in get_tree().get_nodes_in_group(&"objectives"):
		if node.owner_peer_id == unit.owner_peer_id:
			places.append(node)
	for place in places:
		var distance: float = unit.global_position.distance_to(place.global_position)
		if distance < best_distance:
			best_distance = distance
			best = place.global_position
	return best
