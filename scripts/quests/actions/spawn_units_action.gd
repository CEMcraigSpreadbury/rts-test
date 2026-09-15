class_name SpawnUnitsAction
extends QuestAction
## Reinforcements, or the raiding party a step sets loose. Spawned for a
## scenario slot at a named zone or marker, optionally ordered to attack-move
## somewhere as soon as they arrive.

@export var unit_scene: PackedScene
@export var count: int = 1
## Which side they belong to (index into the scenario's Slots).
@export var slot_index: int = 0
## Zone or marker they appear at.
@export var at: StringName = &""
## How far apart they are scattered, so they don't spawn inside each other.
@export var spread: float = 2.0
## Zone or marker to attack-move to; empty leaves them standing.
@export var attack_move_to: StringName = &""
## Names what arrives, the way a unit placed in the scene is named, so a later
## step can refer to it — "slay the Skeleton Dragon" (DestroyTargets) when the
## dragon only turns up mid-mission. One unit takes the name as it is; more
## than one are numbered from 1 ("Raider1", "Raider2", ...). Host-side only,
## like the conditions that read it.
@export var name_as: String = ""

func run(runner) -> void:
	if unit_scene == null or count <= 0:
		return
	var peer_id: int = runner.peer_for_slot(slot_index)
	if peer_id <= 0:
		return
	var origin: Vector3 = runner.position_of(at)
	var target: Vector3 = runner.position_of(attack_move_to) if attack_move_to != &"" else Vector3.ZERO
	var tint: Color = runner.main.get_team_tint(peer_id)
	## An enemy wave grows or shrinks with the campaign difficulty;
	## reinforcements for the player's own side are exactly what was written.
	var wave: int = count
	if Teams.team_of(peer_id) != runner.player_team():
		wave = maxi(1, roundi(count * MatchRules.enemy_scale()))
	var nav_map: RID = runner.main.get_world_3d().navigation_map
	var on_navmesh: bool = NavigationServer3D.map_get_iteration_id(nav_map) > 0
	for i in wave:
		var angle: float = TAU * float(i) / float(wave)
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * spread * (1.0 if wave > 1 else 0.0)
		## A zone or marker sits wherever it was dropped, often at y = 0, and
		## the ground is not flat: a unit spawned under a rise falls through the
		## world for ever. The navmesh's nearest point is on the ground and clear
		## of trees and buildings.
		var spot: Vector3 = origin + offset
		if on_navmesh:
			spot = NavigationServer3D.map_get_closest_point(nav_map, spot)
		var unit: Unit = runner.main.unit_spawner.spawn({
			"scene_path": unit_scene.resource_path,
			"peer_id": peer_id,
			"tint": tint,
			"position": spot,
		})
		if unit == null:
			continue
		## Counted against population like anything else that side fields.
		Population.reserve(peer_id, unit.population_cost)
		if name_as != "":
			runner.main.scenario_entities[name_as if wave == 1 else "%s%d" % [name_as, i + 1]] = unit
		if attack_move_to != &"":
			unit.command_attack_move(target)
