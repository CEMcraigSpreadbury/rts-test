class_name Pacts
extends Node
## Which allied races each player has a Pact with (see PactRace). Created by
## Main as `main.pacts`.
##
## Host-authoritative like Research: only the host decides a Pact is granted
## (a Pact Hall finishing a PACT producible, see Main._on_building_item_completed),
## but the result is broadcast to every peer rather than sent privately —
## which race someone allied with changes what every peer draws for their
## units, so it is not secret.

## The local player's own pacts changed (see my_races).
signal pacts_changed

var main: Main

static var _instance: Pacts = null

## peer_id -> { PactRace.race_name -> fractional currency not yet paid out }.
## The passive trickle is far slower than one unit a second, so it banks up
## here and is handed over a whole unit at a time.
var _income_carry: Dictionary = {}

## peer_id -> Array[String] of PactRace.race_name, in the order they were made.
var _pacted: Dictionary = {}
## Same list for the local player, kept separately so UI code can read it
## without caring whether it is running on the host.
var my_races: Array[String] = []

func _ready() -> void:
	_instance = self
	set_physics_process(multiplayer.is_server())

## The floor under every Pact: income a player earns just for holding it, with
## nothing built (see PactRace.passive_income_per_second). A race's buildings
## pay on top of this through PactGenerator.
func _physics_process(delta: float) -> void:
	for peer_id in _pacted:
		for race_name in _pacted[peer_id]:
			var race := find_race(race_name)
			if race == null or race.currency == null or race.passive_income_per_second <= 0.0:
				continue
			var night: float = 1.0
			if not is_equal_approx(race.passive_night_multiplier, 1.0) and main != null and main.day_night != null:
				night = lerpf(1.0, race.passive_night_multiplier, clampf(main.day_night.night_amount, 0.0, 1.0))
			var key := "%d:%s" % [peer_id, race_name]
			var carry: float = _income_carry.get(key, 0.0) + race.passive_income_per_second * night * delta
			var whole: int = int(floor(carry))
			if whole > 0:
				ResourceStockpile.add(peer_id, race.currency, whole)
				carry -= float(whole)
			_income_carry[key] = carry

func _exit_tree() -> void:
	if _instance == self:
		_instance = null

## Every race that exists, in menu order. Loaded from disk rather than an
## exported list so adding a race is a matter of dropping in a .tres, the
## same way Ruler.list_all works.
static func list_all() -> Array[PactRace]:
	var races: Array[PactRace] = []
	var dir := DirAccess.open("res://resources/pacts")
	if dir == null:
		return races
	var file_names := dir.get_files()
	file_names.sort()
	for file_name in file_names:
		## Exported builds hand back the .remap name instead of the source one.
		var clean_name := file_name.trim_suffix(".remap")
		if not clean_name.ends_with(".tres"):
			continue
		var race = load("res://resources/pacts/" + clean_name)
		if race is PactRace:
			races.append(race)
	return races

static func find_race(race_name: String) -> PactRace:
	for race in list_all():
		if race.race_name == race_name:
			return race
	return null

static func races_of(peer_id: int) -> Array[String]:
	if _instance == null:
		return []
	var names: Array[String] = []
	names.assign(_instance._pacted.get(peer_id, []))
	return names

static func has_pact(peer_id: int, race_name: String) -> bool:
	return races_of(peer_id).has(race_name)

## Every building `peer_id` may construct thanks to their Pacts, race by race.
## Returns pairs of {race: PactRace, buildings: Array[BuildingType]} so the
## build menu can page them per race (step 2).
static func building_pages(peer_id: int) -> Array[Dictionary]:
	var pages: Array[Dictionary] = []
	for race_name in races_of(peer_id):
		var race := find_race(race_name)
		if race != null:
			pages.append({"race": race, "buildings": race.building_types})
	return pages

## Host only. A Pact Hall finished its Pact. Returns false if this race was
## already allied with (two halls can't double up on one race).
func grant(peer_id: int, race_name: String) -> bool:
	if not multiplayer.is_server() or race_name.is_empty():
		return false
	if has_pact(peer_id, race_name):
		return false
	var races: Array = _pacted.get(peer_id, [])
	races.append(race_name)
	_pacted[peer_id] = races
	var typed: Array[String] = []
	typed.assign(races)
	_rpc_pacted.rpc(peer_id, typed)
	return true

@rpc("authority", "call_local", "reliable")
func _rpc_pacted(peer_id: int, races: Array[String]) -> void:
	_pacted[peer_id] = races
	if peer_id == multiplayer.get_unique_id():
		my_races = races
		pacts_changed.emit()


## --- Income from the dead ------------------------------------------------

const GNOLLS: String = "Gnolls"
const DARK_ELVES: String = "Dark Elves"
## How far a gnoll has to be from a kill to strip it (scavenging), and how far
## a Dark Elf player's eyes have to be to catch a soul.
const SCAVENGE_RADIUS: float = 14.0
## One soul per this much of the victim's cost, so a villager is worth little
## and a Paladin a good deal. Animals pay their hunt_meat instead.
const SOUL_RESOURCES_PER_POINT: float = 60.0
## What a hunted animal is worth in souls regardless of its (zero) cost.
const ANIMAL_SOULS: int = 1

## peer_id -> fractional souls not yet paid out, same carry trick as the
## passive trickle.
var _soul_carry: Dictionary = {}

## Host only, called from Unit._die for every death in the match.
##
## Meat goes to the killer when they hold the Gnoll Pact — animals pay their
## hunt_meat, other kills pay half of it as scavenged scraps, and only if the
## killer has a gnoll close enough to strip the body.
##
## Souls go to EVERY Dark Elf player who could see the death, not just the
## one who caused it: that is what stops a losing Dark Elf player from being
## cut off from their own race (see the design note in project-pacts).
func award_death(victim: Unit, attacker) -> void:
	if not multiplayer.is_server() or victim == null:
		return
	var killer: int = 0
	if attacker != null and is_instance_valid(attacker) and "owner_peer_id" in attacker:
		killer = attacker.owner_peer_id
	if killer > 0 and has_pact(killer, GNOLLS):
		var meat: int = victim.hunt_meat
		if meat <= 0 and victim.owner_peer_id != killer:
			## Not a hunt, but a body all the same.
			meat = 1
		if meat > 0 and _has_scavenger_near(killer, victim.global_position):
			var race := find_race(GNOLLS)
			if race != null and race.currency != null:
				ResourceStockpile.add(killer, race.currency, meat)
	_award_souls(victim, killer)

## A gnoll (or the Den's own hunter) has to be near the body; a Dark Elf ally
## killing something across the map earns a Gnoll player nothing.
func _has_scavenger_near(peer_id: int, position: Vector3) -> bool:
	var radius_squared: float = SCAVENGE_RADIUS * SCAVENGE_RADIUS
	for node in get_tree().get_nodes_in_group("units"):
		var unit := node as Unit
		if unit == null or not is_instance_valid(unit) or unit.owner_peer_id != peer_id:
			continue
		if unit.status_activity == Unit.Activity.DEAD:
			continue
		if position.distance_squared_to(unit.global_position) <= radius_squared:
			return true
	return false

func _award_souls(victim: Unit, killer: int) -> void:
	var race := find_race(DARK_ELVES)
	if race == null or race.currency == null:
		return
	var worth: float = float(ANIMAL_SOULS) if victim.hunt_meat > 0 else 0.0
	if worth <= 0.0:
		var cost: int = 0
		for entry in victim.costs:
			cost += entry.amount
		worth = float(cost) / SOUL_RESOURCES_PER_POINT
	if worth <= 0.0:
		return
	for peer_id in _pacted:
		if not has_pact(peer_id, DARK_ELVES):
			continue
		## Your own dead are no use to you, but everyone else's are — as long
		## as you were watching.
		if peer_id == victim.owner_peer_id:
			continue
		if peer_id != killer and not _can_see(peer_id, victim.global_position):
			continue
		var carry: float = _soul_carry.get(peer_id, 0.0) + worth
		var whole: int = int(floor(carry))
		if whole > 0:
			ResourceStockpile.add(peer_id, race.currency, whole)
			carry -= float(whole)
		_soul_carry[peer_id] = carry

## Anything of this player's — unit or building — with the spot inside its
## vision. Same test Research.cast_as uses for casting a power.
func _can_see(peer_id: int, position: Vector3) -> bool:
	for node in get_tree().get_nodes_in_group("units"):
		var unit := node as Unit
		if unit == null or not is_instance_valid(unit) or unit.owner_peer_id != peer_id:
			continue
		if unit.status_activity == Unit.Activity.DEAD:
			continue
		if position.distance_to(unit.global_position) <= unit.vision_range:
			return true
	for node in get_tree().get_nodes_in_group("buildings"):
		var building := node as ProductionBuilding
		if building == null or not is_instance_valid(building) or building.owner_peer_id != peer_id:
			continue
		if building.is_destroyed:
			continue
		if position.distance_to(building.global_position) <= building.vision_range:
			return true
	return false


## Public form of _can_see, for anything outside this class that needs the
## same "could this player see that spot" test (the Star Gate).
func can_see_position(peer_id: int, position: Vector3) -> bool:
	return _can_see(peer_id, position)
