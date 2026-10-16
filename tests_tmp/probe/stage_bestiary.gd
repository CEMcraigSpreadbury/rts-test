extends RefCounted
func stage(main: Node) -> void:
	var tc: Vector3 = (main.player_spawn_points.get_child(0) as Node3D).global_position
	var b = main.building_spawner.spawn({"scene_path": "res://scenes/buildings/bestiary_building.tscn", "peer_id": 1, "tint": main.get_team_tint(1), "position": tc + Vector3(7, 0, 5)})
	main.focus_camera_on(b.global_position)
	await main.get_tree().create_timer(2.0).timeout
	print("BEAST ", b.get_node_or_null("BeastFigure"))
