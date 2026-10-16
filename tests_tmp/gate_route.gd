extends RefCounted

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
	await tree.create_timer(3.0).timeout
	var centre: Vector3 = settlement.global_position
	var scene: String = settlement._guard_roster[0].scene_path
	for gi in settlement._gates.size():
		var gate: Node3D = settlement._gates[gi]
		var out: Vector3 = (gate.global_position - centre)
		out.y = 0.0
		out = out.normalized()
		var unit: Unit = main.unit_spawner.spawn({"scene_path": scene, "peer_id": 1, "tint": main.get_team_tint(1), "position": centre + out * 19.0})
		await tree.create_timer(0.5).timeout
		unit.command_move(centre + out * 6.0)
		var closest: Array = []
		for g in settlement._gates:
			closest.append(999.0)
		var t: float = 0.0
		while t < 20.0:
			await tree.create_timer(0.25).timeout
			t += 0.25
			for k in settlement._gates.size():
				closest[k] = minf(closest[k], unit.global_position.distance_to(settlement._gates[k].global_position))
			if Vector2(unit.global_position.x - centre.x, unit.global_position.z - centre.z).length() < 8.0:
				break
		print("ROUTE gate %d: arrived=%s in %.1f s, closest to each gate %s" % [gi, t < 20.0, t, closest.map(func(d): return snappedf(d, 0.1))])
		unit.queue_free()
