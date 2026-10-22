extends RefCounted
## ui_shot --stage: an Aldmere field and a Robot Charge Pad at the bare stage,
## and one of each grown, on the ground by the base.

func stage(main: Node) -> void:
	var tc: Node3D = main.town_centers[1]
	var origin: Vector3 = tc.global_position + Vector3(8.0, 0.0, -9.0)
	var blue := Color(0.25, 0.55, 1.0)
	var made: Array = []
	for i in 4:
		var path := "res://scenes/buildings/farm_building.tscn" if i % 2 == 0 else "res://scenes/buildings/robots/robot_farm_building.tscn"
		var at := _ground(main, origin + Vector3(-5.0 + i * 3.6, 0.0, 0.0))
		made.append(main.building_spawner.spawn({"scene_path": path, "peer_id": 1, "position": at, "tint": blue}))
	await main.get_tree().process_frame
	for i in [2, 3]:
		made[i]._enter_stage(FarmField.Stage.RIPE)
	main.camera_rig.global_position = origin
	await main.get_tree().create_timer(1.0).timeout

func _ground(main: Node, at: Vector3) -> Vector3:
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 60.0, at + Vector3.DOWN * 60.0)
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	return hit.position if not hit.is_empty() else at
