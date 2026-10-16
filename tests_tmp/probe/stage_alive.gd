extends RefCounted
func stage(main: Node) -> void:
	var tc: Vector3 = (main.player_spawn_points.get_child(0) as Node3D).global_position
	var best: Unit = null
	for u in main.get_tree().get_nodes_in_group(&"units"):
		if u is Unit and u.hunt_meat > 0 and u.display_name == "Deer" and (best == null or u.global_position.distance_to(tc) < best.global_position.distance_to(tc)):
			best = u
	print("STAGE ", best.display_name, " at ", best.global_position)
	main.fog_of_war.reveal_all = true
	main.focus_camera_on(best.global_position)
	await main.get_tree().create_timer(5.0).timeout
