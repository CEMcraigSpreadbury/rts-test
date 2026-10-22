extends RefCounted
## ui_shot --stage: the Pirate Haven set down on open ground by the base.

func stage(main: Node) -> void:
	var tc: Node3D = main.town_centers[1]
	var origin: Vector3 = tc.global_position + Vector3(8.0, 0.0, -9.0)
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin + Vector3.UP * 60.0, origin + Vector3.DOWN * 60.0)
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	main.building_spawner.spawn({"scene_path": "res://scenes/buildings/pirates/pirate_town_center_building.tscn",
			"peer_id": 1, "position": hit.position if not hit.is_empty() else origin, "tint": Color(0.25, 0.55, 1.0)})
	main.camera_rig.global_position = origin
	await main.get_tree().create_timer(1.0).timeout
