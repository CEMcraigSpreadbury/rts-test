class_name RealmEconomy
extends Node
## The running costs of an army in a Realm match (see MatchRules.realm): every
## soldier eats food, and the bigger ones (population 2 and up — cavalry,
## mages, siege, monsters) draw gold wages as well. Villagers work the land
## and cost nothing to keep. Charged by the host every UPKEEP_INTERVAL, with
## fractions carried so a 1-food-a-minute soldier really does cost 1 a minute.
##
## An army that can't be fed isn't killed by it: the side is marked starving
## (is_starving), which the morale system reads. Unpaid wages just leave the
## purse at zero for now.
##
## Also pays food for hunting, which in other modes only feeds the Gnoll Pact.
##
## Lives on every peer so the host can tell each player their own upkeep; all
## the accounting is host-only.

## Local player's upkeep changed: whole units per minute, and whether they
## can't meet it.
signal upkeep_changed(food_per_minute: int, gold_per_minute: int, starving: bool)

const FOOD: ResourceType = preload("res://resources/food_resource_type.tres")
const GOLD: ResourceType = preload("res://resources/gold_resource_type.tres")

const UPKEEP_INTERVAL: float = 5.0
const FOOD_PER_POPULATION: float = 3.0
## A unit this big or bigger draws wages as well as rations.
const ELITE_POPULATION: int = 2
const GOLD_PER_ELITE_POPULATION: float = 1.0
## Food for each point of an animal's hunt_meat.
const HUNT_FOOD_PER_MEAT: int = 3
## What each side starts a Realm match with, on top of Main.STARTING_RESOURCES.
const STARTING_FOOD: int = 200

var main: Main

## --- Replenishment ---
## A regiment with its officer, standing on its own side's land and out of the
## fight, takes on a new man every REPLENISH_SECONDS until it is back to
## strength, paying the usual price for him.
const REPLENISH_SECONDS: float = 15.0
const REPLENISH_SAFE_RADIUS: float = 20.0
var _replenish_timer: float = REPLENISH_SECONDS

var _timer: float = UPKEEP_INTERVAL
## peer_id -> fractional food / gold owed but not yet charged.
var _food_carry: Dictionary = {}
var _gold_carry: Dictionary = {}
## peer_id -> true while their army goes hungry. Host only.
var _starving: Dictionary = {}
## peer_id -> Vector2(food, gold) per minute at the last charge. Host only.
var _rates: Dictionary = {}
## peer_id -> [food, gold, starving] as last sent, so only changes go out.
var _last_sent: Dictionary = {}

func _ready() -> void:
	set_physics_process(MatchRules.realm() and multiplayer.is_server())

## Host only.
func is_starving(peer_id: int) -> bool:
	return _starving.get(peer_id, false)

## Host only: food this side's army eats a minute, as of the last charge.
func food_per_minute(peer_id: int) -> float:
	return (_rates.get(peer_id, Vector2.ZERO) as Vector2).x

## Food and gold a unit costs to keep, per minute. Villagers, summons, animals
## and anything nobody owns cost nothing.
static func upkeep_of(unit: Unit) -> Vector2:
	if unit.owner_peer_id <= 0 or unit.can_gather or unit.summoned or unit.hunt_meat > 0 \
			or unit.has_meta(&"garrison"):
		return Vector2.ZERO
	if unit.status_activity == Unit.Activity.DEAD:
		return Vector2.ZERO
	var food: float = unit.population_cost * FOOD_PER_POPULATION
	var gold: float = unit.population_cost * GOLD_PER_ELITE_POPULATION if unit.population_cost >= ELITE_POPULATION else 0.0
	return Vector2(food, gold)

func _physics_process(delta: float) -> void:
	_replenish_timer -= delta
	if _replenish_timer <= 0.0:
		_replenish_timer = REPLENISH_SECONDS
		_replenish()
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = UPKEEP_INTERVAL
	## peer_id -> Vector2(food, gold) per minute.
	var rates: Dictionary = {}
	for peer_id in main.faction_by_peer:
		rates[peer_id] = Vector2.ZERO
	for node in get_tree().get_nodes_in_group(&"units"):
		var unit := node as Unit
		if unit == null or not rates.has(unit.owner_peer_id):
			continue
		rates[unit.owner_peer_id] += upkeep_of(unit)
	_rates = rates
	for peer_id in rates:
		var rate: Vector2 = rates[peer_id]
		var fed := _charge(peer_id, FOOD, rate.x, _food_carry)
		_charge(peer_id, GOLD, rate.y, _gold_carry)
		_starving[peer_id] = not fed
		_send(peer_id, roundi(rate.x), roundi(rate.y), not fed)

## Takes one interval's worth of `per_minute` from the stockpile. False when
## there wasn't enough to cover it (what there was is still taken).
func _charge(peer_id: int, type: ResourceType, per_minute: float, carry: Dictionary) -> bool:
	var owed: float = per_minute * UPKEEP_INTERVAL / 60.0 + float(carry.get(peer_id, 0.0))
	var whole: int = floori(owed)
	carry[peer_id] = owed - whole
	if whole <= 0:
		return true
	var held: int = ResourceStockpile.get_amount(peer_id, type)
	var cost := ResourceCost.new()
	cost.resource_type = type
	cost.amount = mini(whole, held)
	if cost.amount > 0:
		ResourceStockpile.spend(peer_id, [cost] as Array[ResourceCost])
	return held >= whole

func _send(peer_id: int, food: int, gold: int, starving: bool) -> void:
	var state := [food, gold, starving]
	if _last_sent.get(peer_id) == state:
		return
	_last_sent[peer_id] = state
	if peer_id == multiplayer.get_unique_id():
		upkeep_changed.emit(food, gold, starving)
	elif Network.can_rpc_to(peer_id):
		_rpc_upkeep.rpc_id(peer_id, food, gold, starving)

@rpc("authority", "call_remote", "reliable")
func _rpc_upkeep(food: int, gold: int, starving: bool) -> void:
	upkeep_changed.emit(food, gold, starving)

## Gnolls strip the dead: food for every other side with a gnoll this close to
## a body. (Their Meat, outside Realm.)
const SCAVENGE_RADIUS: float = 8.0
const SCAVENGE_FOOD: int = 2
const UnitGrid = preload("res://scripts/unit_grid.gd")

## Host only, from Unit._die: the hunter's side eats what they brought down,
## and any gnolls nearby scavenge.
func award_hunt(victim: Unit, attacker) -> void:
	if not MatchRules.realm() or not multiplayer.is_server():
		return
	var fed: Dictionary = {}
	for unit in UnitGrid.units_near(get_tree(), victim.global_position, SCAVENGE_RADIUS):
		if unit == victim or not is_instance_valid(unit) or not unit.pack_member or unit.owner_peer_id <= 0:
			continue
		if unit.owner_peer_id == victim.owner_peer_id or fed.has(unit.owner_peer_id):
			continue
		fed[unit.owner_peer_id] = true
		ResourceStockpile.add(unit.owner_peer_id, FOOD, SCAVENGE_FOOD)
	if victim.hunt_meat <= 0:
		return
	if attacker == null or not is_instance_valid(attacker) or not "owner_peer_id" in attacker:
		return
	var killer: int = attacker.owner_peer_id
	if killer > 0:
		ResourceStockpile.add(killer, FOOD, victim.hunt_meat * HUNT_FOOD_PER_MEAT)

func _replenish() -> void:
	for id in main.regiments.keys():
		var regiment: Regiment = main.regiments[id]
		regiment.prune()
		if not regiment.has_officer() or not regiment.is_under_strength() or regiment.members.is_empty():
			continue
		var officer: Unit = regiment.officer
		var peer: int = regiment.owner_peer_id
		if Objective.territory_owner(get_tree(), officer.global_position) != peer:
			continue
		if not UnitGrid.enemies_near(get_tree(), officer.global_position, REPLENISH_SAFE_RADIUS, peer).is_empty():
			continue
		var template: Unit = regiment.members[0]
		var costs: Array[ResourceCost] = MatchRules.realm_unit_costs(template.costs, false)
		if not ResourceStockpile.can_afford(peer, costs) or not Population.has_room(peer, template.population_cost):
			continue
		ResourceStockpile.spend(peer, costs)
		Population.reserve(peer, template.population_cost)
		var behind: Vector3 = officer.global_position - template.formation_facing * 2.0
		var recruit: Unit = main.unit_spawner.spawn({
			"scene_path": template.scene_file_path,
			"peer_id": peer,
			"tint": main.get_team_tint(peer),
			"position": behind,
		})
		main.reinforce_regiment(regiment, [recruit] as Array[Unit], [] as Array[Unit])
