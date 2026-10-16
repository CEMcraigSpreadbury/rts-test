extends RefCounted

## Throwaway: ui_shot --stage. Walls a settlement in, shuts its gates with an
## enemy outside, then marches a friend and an enemy at the hall.

func stage(main: Node) -> void:
	var tree := main.get_tree()
	await tree.create_timer(0.5).timeout
	var settlement: Objective = null
	for node in tree.get_nodes_in_group(&"objectives"):
		var f := node.get_node_or_null(^"Folk") as SettlementFolk
		if f != null and f._mmi.visible:
			settlement = node
	for g in settlement._guards:
		if is_instance_valid(g):
			g.queue_free()
	settlement._guards.clear()
	settlement._set_owner(1)
	settlement.owner_peer_id = 1
	settlement._build_walls()
	await tree.create_timer(2.0).timeout
	var scene: String = settlement._guard_roster[0].scene_path
	var centre: Vector3 = settlement.global_position
	var gate_dirs: Array = []
	for gate in settlement._gates:
		gate_dirs.append(rad_to_deg(atan2(gate.global_position.z - centre.z, gate.global_position.x - centre.x)))
	print("GATE race=%s gates=%s" % [settlement.race_name, gate_dirs])
	## Halfway between the first two gates, well outside the ring.
	var a: float = deg_to_rad((gate_dirs[0] + gate_dirs[1]) * 0.5) if gate_dirs.size() > 1 else 0.0
	var friend_at: Vector3 = centre + Vector3(cos(a), 0, sin(a)) * 22.0
	var foe_at: Vector3 = centre + Vector3(cos(a + PI), 0, sin(a + PI)) * 22.0
	var friend: Unit = main.unit_spawner.spawn({"scene_path": scene, "peer_id": 1, "tint": main.get_team_tint(1), "position": friend_at})
	var foe: Unit = main.unit_spawner.spawn({"scene_path": scene, "peer_id": 2, "tint": Color.RED, "position": foe_at})
	await tree.create_timer(1.5).timeout
	print("GATE shut=%s" % settlement._doors_shut)
	var hall_spot: Vector3 = centre + Vector3(0, 0, 5)
	friend.command_move(hall_spot)
	foe.command_move(hall_spot)
	for i in 10:
		await tree.create_timer(2.0).timeout
		print("GATE t=%d shut=%s friend %.1f from centre, foe %.1f (foe alive=%s)" % [i * 2, settlement._doors_shut,
				_flat(friend.global_position - centre), _flat(foe.global_position - centre) if is_instance_valid(foe) else -1.0,
				is_instance_valid(foe)])
	main.focus_camera_on(centre)

func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()
