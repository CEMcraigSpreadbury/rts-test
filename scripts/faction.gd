class_name Faction
extends Resource
## What a player can build/produce when they pick this faction in the lobby,
## and what they start the match with. Both lobby.tscn and main.tscn reference
## the same .tres files here (see resources/factions/) in the same order —
## that shared order is the "faction index" stored per-player in Network.players.

@export var faction_name: String = "Faction"
@export var building_types: Array[BuildingType] = []
## Placed pre-built at each starting position (Town Center equivalent).
@export var starting_building_scene: PackedScene
## Spawned x2 at match start (Villager equivalent).
@export var starting_unit_scene: PackedScene
