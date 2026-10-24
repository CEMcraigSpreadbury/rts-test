extends RefCounted
## ui_shot --stage: the Galleon sailing slowly across, broadsides going off.

func stage(main: Node) -> void:
	var tc: Node3D = main.town_centers[1]
	var origin: Vector3 = main.power_effects.ground_point(tc.global_position + Vector3(14.0, 0.0, -14.0))
	main.power_fx.play(&"galleon", {"pos": origin + Vector3(-30.0, 0.0, 0.0), "end": origin + Vector3(30.0, 0.0, 0.0),
			"run_in": 0.0, "speed": 3.0, "tint": Color(0.25, 0.55, 1.0)})
	main.camera_rig.global_position = origin + Vector3(-18.0, 0.0, 3.0)
	for i in 12:
		await main.get_tree().create_timer(0.5).timeout
		var at: Vector3 = origin + Vector3(-30.0 + 3.0 * 0.5 * (i + 1), 0.0, 0.0)
		main.power_fx.play(&"cannon_volley", {"from": [at + Vector3(0, 0, 2.0), at + Vector3(0, 0, -2.0)],
				"to": [main.power_effects.ground_point(at + Vector3(2.0, 0, 9.0)), main.power_effects.ground_point(at + Vector3(-1.0, 0, -10.0))], "flight": 0.9})
