class_name PlayerSpawnPoint
extends Node3D
## Placed once per potential player slot on a map. How many buildings/units
## spawn here — and exactly where — is entirely up to how many Marker3D
## children exist under BuildingSpawns/UnitSpawns (add more for a map that
## starts players with extra buildings). Which scene fills each slot comes
## from the spawning player's Faction (see Faction.starting_buildings/units),
## keeping per-faction rosters meaningful regardless of map layout.

@onready var building_spawns: Node3D = $BuildingSpawns
@onready var unit_spawns: Node3D = $UnitSpawns

func get_building_positions() -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for marker in building_spawns.get_children():
		positions.append(marker.global_position)
	return positions

func get_unit_positions() -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for marker in unit_spawns.get_children():
		positions.append(marker.global_position)
	return positions
