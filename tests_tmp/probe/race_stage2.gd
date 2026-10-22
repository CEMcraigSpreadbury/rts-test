extends RefCounted
## ui_shot --stage: Pirate units, the three crewed siege engines (turned so
## their crew faces the camera) on open ground; prints each crew figure.

const PU := "res://scenes/units/pirates/pirate_%s_unit.tscn"

func stage(main: Node) -> void:
	var tc: Node3D = main.town_centers[1]
	var origin: Vector3 = tc.global_position + Vector3(8.0, 0.0, -9.0)
	var blue := Color(0.25, 0.55, 1.0)
	var red := Color(1.0, 0.35, 0.3)
	var pu := ["deckhand", "swabbie", "harpooner", "brute", "musketeer", "blunderbuss", "captain"]
	for i in pu.size():
		_unit(main, PU % pu[i], origin + Vector3(-4.0 + i * 1.3, 0.0, 2.5), blue, 0.0)
	var siege := [PU % "cannon", "res://scenes/units/robots/robot_rocket_unit.tscn", "res://scenes/units/ballista_unit.tscn"]
	var made: Array = []
	for i in siege.size():
		made.append(_unit(main, siege[i], origin + Vector3(-4.0 + i * 4.5, 0.0, -2.0), red if i == 1 else blue, PI))
	main.camera_rig.global_position = origin + Vector3(0.0, 0.0, 0.5)
	await main.get_tree().create_timer(2.0).timeout
	for u in made:
		var crew: Node3D = u.get("_crew_figure")
		print("CREW ", u.display_name, " ", crew != null, " ", crew != null and Main.figure_batcher_current.has_figure(crew))
		var wheels: Array = u.get("_wheel_figures")
		print("WHEELS ", u.display_name, " ", wheels.size(), " ", wheels.all(func(w): return Main.figure_batcher_current.has_figure(w)))
	## Drive them off, so a wheel turns.
	for u in made:
		u.command_move(u.global_position + Vector3(0.0, 0.0, 6.0))
	await main.get_tree().create_timer(1.5).timeout

func _ground(main: Node, at: Vector3) -> Vector3:
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 60.0, at + Vector3.DOWN * 60.0)
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	return hit.position if not hit.is_empty() else at

func _unit(main: Node, path: String, at: Vector3, tint: Color, yaw: float) -> Node3D:
	var u: Node3D = main.unit_spawner.spawn({"scene_path": path, "peer_id": 1, "position": _ground(main, at), "tint": tint})
	u.rotation.y = yaw
	return u
