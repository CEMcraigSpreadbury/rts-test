extends RefCounted
## ui_shot --stage: an open Cursed Treasure, a Colossus by its drop pod, and the
## ghost knights riding past.

func stage(main: Node) -> void:
	var tc: Node3D = main.town_centers[1]
	var origin: Vector3 = main.power_effects.ground_point(tc.global_position + Vector3(14.0, 0.0, -14.0))
	main.power_fx.play(&"treasure", {"pos": origin + Vector3(-6.0, 0.0, 2.0), "seconds": 4.0, "radius": 12.0})
	main.power_fx.play(&"pod", {"pos": origin + Vector3(6.0, 0.0, -2.0), "fall": 0.5, "tint": Color(1.0, 0.35, 0.3)})
	var colossus: Node3D = main.unit_spawner.spawn({"scene_path": "res://scenes/units/robots/robot_colossus_unit.tscn",
			"peer_id": 1, "tint": Color(1.0, 0.35, 0.3), "position": origin + Vector3(6.0, 0.0, 2.5)})
	colossus.rotation.y = 0.0
	main.power_fx.play(&"charge", {"pos": origin + Vector3(-20.0, 0.0, 9.0), "end": origin + Vector3(24.0, 0.0, 9.0),
			"width": 8.0, "seconds": 2.6})
	main.camera_rig.global_position = origin + Vector3(0.0, 0.0, 3.0)
	await main.get_tree().create_timer(1.25).timeout
	for c in main.power_fx.get_children():
		if c is Node3D:
			print("FXCHILD ", c.name, " ", c.get_class(), " ", c.global_position, " vis ", c.visible, " scale ", c.scale)
		else:
			print("FXCHILD ", c.name, " ", c.get_class())
	var chest = main.power_fx.get_children().filter(func(n): return n.has_meta(&"at"))
	if not chest.is_empty():
		print("LID ", chest[0].find_child("Lid", true, false), " ", chest[0].get_children())
