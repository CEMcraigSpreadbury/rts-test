extends RefCounted
## ui_shot --stage: the ghost knights mid-charge, and a Cursed Treasure open.

func stage(main: Node) -> void:
	var tc: Node3D = main.town_centers[1]
	var origin: Vector3 = main.power_effects.ground_point(tc.global_position + Vector3(14.0, 0.0, -14.0))
	main.power_fx.play(&"charge", {"pos": origin + Vector3(-24.0, 0.0, 0.0), "end": origin + Vector3(20.0, 0.0, 0.0),
			"width": 8.0, "seconds": 12.0})
	main.power_fx.play(&"treasure", {"pos": origin + Vector3(4.0, 0.0, 7.0), "seconds": 4.0, "radius": 12.0})
	main.camera_rig.global_position = origin + Vector3(0.0, 0.0, 2.0)
	await main.get_tree().create_timer(4.5).timeout
	for c in main.power_fx.get_children():
		if c is Node3D and c.get_child_count() > 0 and c.get_child(0) is MeshInstance3D and c.get_child(0).name == "Cavalier":
			print("KNIGHT ", c.global_transform, " vis ", c.is_visible_in_tree(), " ov ", c.get_child(0).material_override)
	print("CAM ", main.camera_rig.global_position, " time_scale ", Engine.time_scale)
