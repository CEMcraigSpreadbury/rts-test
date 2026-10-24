extends RefCounted
## ui_shot --stage: a Robot squad under Overclock beside one that isn't.

func stage(main: Node) -> void:
	var tc: Node3D = main.town_centers[1]
	var origin: Vector3 = main.power_effects.ground_point(tc.global_position + Vector3(14.0, 0.0, -14.0))
	var hot: Array = []
	var paths: Array = []
	for i in 24:
		var at: Vector3 = origin + Vector3((i % 6) * 1.4 - (8.0 if i < 12 else -2.0), 0.0, (i / 6 % 2) * 1.4)
		var u: Node3D = main.unit_spawner.spawn({"scene_path": "res://scenes/units/robots/robot_trooper_unit.tscn",
				"peer_id": 1, "tint": Color(0.25, 0.55, 1.0), "position": main.power_effects.ground_point(at)})
		if i < 12:
			hot.append(u)
	await main.get_tree().create_timer(0.5).timeout
	for u in hot:
		paths.append(u.get_path())
	main.feedback.relay_buff_tints(hot, PowerEffects.OVERCLOCK_COLOR, 30.0, PowerEffects.OVERCLOCK_TINT_STRENGTH)
	main.power_fx.play(&"overclock", {"pos": origin + Vector3(-4.0, 0, 0), "radius": 9.0, "paths": paths, "seconds": 30.0})
	main.camera_rig.global_position = origin + Vector3(-1.0, 0.0, 1.0)
	await main.get_tree().create_timer(1.0).timeout
