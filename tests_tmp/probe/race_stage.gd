extends RefCounted
## ui_shot --stage: Pirate buildings and units (blue) and Robot ones (red) set
## down near the player's base, the camera over them.

const P := "res://scenes/buildings/pirates/pirate_%s_building.tscn"
const R := "res://scenes/buildings/robots/robot_%s_building.tscn"
const PU := "res://scenes/units/pirates/pirate_%s_unit.tscn"
const RU := "res://scenes/units/robots/robot_%s_unit.tscn"

func stage(main: Node) -> void:
	var tc: Node3D = main.town_centers[1]
	var origin: Vector3 = tc.global_position + Vector3(8.0, 0.0, -9.0)
	var blue := Color(0.25, 0.55, 1.0)
	var red := Color(1.0, 0.35, 0.3)
	var row_p := ["town_center", "barracks", "range", "sanctum"]
	var row_r := ["town_center", "barracks", "range", "sanctum"]
	for i in row_p.size():
		_building(main, P % row_p[i], origin + Vector3(-9.0 + i * 6.0, 0.0, -6.0), blue)
	for i in row_r.size():
		_building(main, R % row_r[i], origin + Vector3(-9.0 + i * 6.0, 0.0, 5.0), red)
	var pu := ["deckhand", "swabbie", "harpooner", "brute", "musketeer", "blunderbuss", "voodoo", "captain", "crab_rider"]
	var ru := ["worker", "trooper", "driller", "boiler", "ray_gunner", "tesla", "mechanist", "hound_rider"]
	for i in pu.size():
		_unit(main, PU % pu[i], origin + Vector3(-8.0 + i * 1.6, 0.0, -1.5), blue)
	for i in ru.size():
		_unit(main, RU % ru[i], origin + Vector3(-8.0 + i * 1.6, 0.0, 1.0), red)
	_unit(main, PU % "cannon", origin + Vector3(-6.0, 0.0, 3.0), blue)
	_unit(main, RU % "rocket", origin + Vector3(-1.0, 0.0, 3.0), red)
	_unit(main, "res://scenes/units/ballista_unit.tscn", origin + Vector3(4.0, 0.0, 3.0), blue)
	main.camera_rig.global_position = origin + Vector3(-2.0, 0.0, 0.5)
	await main.get_tree().create_timer(3.0).timeout

func _ground(main: Node, at: Vector3) -> Vector3:
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 60.0, at + Vector3.DOWN * 60.0)
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	return hit.position if not hit.is_empty() else at

func _building(main: Node, path: String, at: Vector3, tint: Color) -> void:
	main.building_spawner.spawn({"scene_path": path, "peer_id": 1, "position": _ground(main, at), "tint": tint})

func _unit(main: Node, path: String, at: Vector3, tint: Color) -> void:
	var u: Node3D = main.unit_spawner.spawn({"scene_path": path, "peer_id": 1, "position": _ground(main, at), "tint": tint})
	u.rotation.y = 0.0
