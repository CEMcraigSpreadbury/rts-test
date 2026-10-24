extends RefCounted
## ui_shot --stage: two linked Telepads, one partway through its recharge.

func stage(main: Node) -> void:
	var tc: Node3D = main.town_centers[1]
	var origin: Vector3 = main.power_effects.ground_point(tc.global_position + Vector3(14.0, 0.0, -14.0))
	var a: Telepad = main.building_spawner.spawn({"scene_path": "res://scenes/buildings/robots/robot_telepad_building.tscn",
			"peer_id": 1, "position": origin, "tint": Color(0.25, 0.55, 1.0)})
	var b: Telepad = main.building_spawner.spawn({"scene_path": "res://scenes/buildings/robots/robot_telepad_building.tscn",
			"peer_id": 1, "position": main.power_effects.ground_point(origin + Vector3(8.0, 0.0, 0.0)), "tint": Color(0.25, 0.55, 1.0)})
	await main.get_tree().process_frame
	a.link_to(b)
	a._rpc_recharge(0.0, 4.0)
	b._rpc_recharge(0.1, 60.0)
	main.select_building(a) if main.has_method("select_building") else null
	main.camera_rig.global_position = origin + Vector3(4.0, 0.0, 1.0)
	await main.get_tree().create_timer(1.0).timeout
