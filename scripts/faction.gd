class_name Faction
extends Resource
## What a player can build/produce when they pick this faction in the lobby,
## and what they start the match with. Both lobby.tscn and main.tscn reference
## the same .tres files here (see resources/factions/) in the same order —
## that shared order is the "faction index" stored per-player in Network.players.

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
