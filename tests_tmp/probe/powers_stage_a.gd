extends RefCounted
## ui_shot --stage: the Galleon mid-voyage past a planted Sword of Aldmere.

func stage(main: Node) -> void:
	var tc: Node3D = main.town_centers[1]
	var origin: Vector3 = main.power_effects.ground_point(tc.global_position + Vector3(14.0, 0.0, -14.0))
	main.power_fx.play(&"sword", {"pos": origin + Vector3(8.0, 0.0, 0.0), "fall": 0.35, "seconds": 60.0, "aura": 12.0})
	main.power_fx.play(&"galleon", {"pos": origin + Vector3(-14.0, 0.0, -20.0), "end": origin + Vector3(-14.0, 0.0, 30.0),
			"run_in": 14.0, "speed": 14.0, "tint": Color(0.25, 0.55, 1.0)})
	main.camera_rig.global_position = origin + Vector3(-4.0, 0.0, 4.0)
	await main.get_tree().create_timer(1.4).timeout
	main.power_fx.play(&"cannon_volley", {"from": [origin + Vector3(-12.0, 0.0, 4.0), origin + Vector3(-16.0, 0.0, 6.0)],
			"to": [origin + Vector3(-2.0, 0.0, 6.0), origin + Vector3(-27.0, 0.0, 3.0)], "flight": 0.55})
	await main.get_tree().create_timer(0.35).timeout
