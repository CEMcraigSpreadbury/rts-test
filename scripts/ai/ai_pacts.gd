class_name AiPacts
extends RefCounted
## The AI's side of Pacts: pick an allied race, put up a Pact Hall, seal the
## Pact, then build that race's buildings. Training the race's units needs no
## code here — an allied barracks reads as MILITARY to AiPlayer.building_role,
## so AiMilitary picks it up with every other production building.
##
## Owned by AiPlayer as `ai.pacts`, thought after the base builder so the
## ordinary build order (houses, mines, barracks) always comes first: a Pact
## is a mid-game luxury, not an opening.

## Nothing is spent on a Pact until the economy is on its feet, measured the
## same way AiPlayer gates its army.
const MIN_VILLAGERS_BEFORE_PACT: int = 10
## Race buildings go up one at a time, with a gap, so an AI doesn't empty its
## treasury into a race it has only just met.
const BUILD_INTERVAL: float = 25.0

var ai: AiPlayer
## Chosen once, at random, the first time this AI thinks — every race is a
## fair opening for any Ruler (see project-pacts).
var race: PactRace = null
var _next_build_time: float = 0.0
## Race building types registered into ai.building_type_index, so try_construct
## can resolve them the same way it resolves the Human roster.
var _registered: bool = false
## The income building is registered first and alone; see _register_race_buildings.
var _income_registered: bool = false

func _init(p_ai: AiPlayer) -> void:
	ai = p_ai

func think() -> void:
	## No Pacts in Realm: races come from their settlements.
	if MatchRules.realm():
		return
	if race == null:
		var races := Pacts.list_all()
		if races.is_empty():
			return
		race = races[randi() % races.size()]
	if ai.villagers.size() < MIN_VILLAGERS_BEFORE_PACT:
		return
	if not Pacts.has_pact(ai.peer_id, race.race_name):
		_work_towards_pact()
		return
	_register_race_buildings()
	_build_race_buildings()

## Either put up the hall or, if one is standing idle, seal the Pact in it.
func _work_towards_pact() -> void:
	var hall := _my_pact_hall()
	if hall == null:
		var type := _faction_type_named("Pact Hall")
		if type != null:
			## try_construct reserves the cost itself when it can't pay yet.
			ai.builder.try_construct(type)
		return
	if hall.is_under_construction or not hall.queue.is_empty():
		return
	for i in hall.producibles.size():
		var item: ProducibleItem = hall.producibles[i]
		if item.kind != ProducibleItem.Kind.PACT or item.pact_race != race:
			continue
		if ai.can_afford(item.costs):
			ai.main.enqueue_as(ai.peer_id, hall.get_path(), i)
		else:
			## Held back from this think's other spenders, or an AI that keeps
			## its army topped up never has the 200 gold spare and leaves an
			## empty hall standing for the rest of the match.
			ai.reserve(item.costs)
		return

func _my_pact_hall() -> ProductionBuilding:
	for building in ai.my_buildings:
		if building.building_name == "Pact Hall" and building.synced_pact_name.is_empty():
			return building
	return null

func _faction_type_named(type_name: String) -> BuildingType:
	for type in ai.building_type_index:
		if type.building_name == type_name:
			return type
	return null

## Pact buildings live past the end of the faction roster in
## Main.buildable_types_for, which is the index space both the build request
## and the host's validation use — so they are registered by looking that
## list up rather than by counting.
##
## The income building (first in the roster: Den, Altar, Observatory) is
## registered on its own to begin with. Registering the whole race at once
## hands its barracks to AiBaseBuilder, which judges buildings by role and
## happily puts up two Dark Spires before the Altar that pays for anything
## they train — an AI that then stands at zero Souls with nothing to train.
func _register_race_buildings() -> void:
	if _registered or race.building_types.is_empty():
		return
	var income_type: BuildingType = race.building_types[0]
	var income_built: bool = _has_building_named(income_type.building_name)
	if _income_registered and not income_built:
		return
	var all: Array[BuildingType] = ai.main.buildable_types_for(ai.peer_id)
	for i in all.size():
		var type: BuildingType = all[i]
		if not race.building_types.has(type):
			continue
		if not income_built and type != income_type:
			continue
		ai.building_type_index[type] = i
		ai.building_costs[type] = type.get_costs()
		ai.building_type_by_scene[type.scene.resource_path] = type
		ai.building_roles[type] = ai._role_of_building_type(type)
	_income_registered = true
	_registered = income_built

## In roster order, which is deliberately income-first: the Den/Altar/
## Observatory pays for everything the race builds afterwards.
func _build_race_buildings() -> void:
	if ai.game_time < _next_build_time:
		return
	for type in race.building_types:
		if _has_building_named(type.building_name):
			continue
		if not ai.building_type_index.has(type):
			return
		var costs: Array[ResourceCost] = ai.building_costs.get(type, type.get_costs())
		if not ai.can_afford(costs):
			ai.reserve(costs)
			return
		if ai.builder.try_construct(type):
			_next_build_time = ai.game_time + BUILD_INTERVAL
		return

func _has_building_named(building_name: String) -> bool:
	for building in ai.my_buildings:
		if building.building_name == building_name:
			return true
	return false
