class_name Faction
extends Resource
## What a player can build/produce and what they start the match with. Every
## player shares the one roster (see Main.available_factions); what sets
## players apart is their Ruler.

@export var faction_name: String = "Faction"
@export var building_types: Array[BuildingType] = []
## Placed pre-built at each of a map's PlayerSpawnPoint building markers, in
## order (index 0 -> the first BuildingSpawns marker, etc). Usually just one
## entry (Town Center equivalent) — more only matters for a map whose spawn
## points define extra building slots.
@export var starting_buildings: Array[PackedScene] = []
## Spawned at each of a map's PlayerSpawnPoint unit markers, in order.
## Usually two entries (Villager equivalent).
@export var starting_units: Array[PackedScene] = []
