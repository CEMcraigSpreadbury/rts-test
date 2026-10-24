class_name Faction
extends Resource
## What a player can build/produce and what they start the match with: one
## per playable people, picked per player in the lobby / single player setup
## (Network.players "race_index", see PLAYABLE).

## The playable peoples in race_index order: Knights first, so a player who
## never picked (a scenario, the campaign, an old lobby) plays it.
const PLAYABLE: Array[String] = [
	"res://resources/factions/faction_one.tres",
	"res://resources/factions/faction_pirates.tres",
	"res://resources/factions/faction_robots.tres",
]
## Their names in PLAYABLE order, for the setup screens: loading a faction
## loads every building and unit it has.
const NAMES: Array[String] = ["Knights", "Pirates", "Robots"]
## A race_index still to be rolled — resolved by the host just before the
## match loads (see Network.resolve_random_races).
const RANDOM: int = -1

@export var faction_name: String = "Faction"
## Its people as RaceTraits and RealmRoster know them ("Human", "Pirates"...).
@export var race_name: String = "Human"
@export var building_types: Array[BuildingType] = []
## Placed pre-built at each of a map's PlayerSpawnPoint building markers, in
## order (index 0 -> the first BuildingSpawns marker, etc). Usually just one
## entry (Town Center equivalent) — more only matters for a map whose spawn
## points define extra building slots.
@export var starting_buildings: Array[PackedScene] = []
## Spawned at each of a map's PlayerSpawnPoint unit markers, in order.
## Usually two entries (Villager equivalent).
@export var starting_units: Array[PackedScene] = []
## Its three powers in the Research panel, bought in this order (see Research).
@export var powers: Array[ResearchNode] = []

static var _all: Array[Faction] = []

static func list_all() -> Array[Faction]:
	if _all.is_empty():
		for path in PLAYABLE:
			_all.append(load(path) as Faction)
	return _all

## The faction for a race_index; anything out of range (RANDOM included) is Knights.
static func for_index(race_index: int) -> Faction:
	var all := list_all()
	return all[race_index] if race_index >= 0 and race_index < all.size() else all[0]

static func display_name_for(race_index: int) -> String:
	if race_index == RANDOM:
		return "Random"
	return NAMES[race_index] if race_index >= 0 and race_index < NAMES.size() else NAMES[0]
