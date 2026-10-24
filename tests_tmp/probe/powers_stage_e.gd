extends RefCounted
## ui_shot --stage: the Sword of Aldmere planted, and the ghost knights riding.

func stage(main: Node) -> void:
	var tc: Node3D = main.town_centers[1]
	var origin: Vector3 = main.power_effects.ground_point(tc.global_position + Vector3(14.0, 0.0, -14.0))
	main.power_fx.play(&"sword", {"pos": origin + Vector3(6.0, 0.0, -2.0), "fall": 0.35, "seconds": 60.0, "aura": 12.0})
	main.power_fx.play(&"charge", {"pos": origin + Vector3(-30.0, 0.0, 6.0), "end": origin + Vector3(14.0, 0.0, 6.0),
			"width": 11.0, "seconds": 14.0})
	main.camera_rig.global_position = origin + Vector3(0.0, 0.0, 2.0)
	await main.get_tree().create_timer(4.0).timeout
