extends RefCounted

## Throwaway: ui_shot --stage. Walls a settlement in and prints the sim grid's
## walkability through and across each gate.

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
	var sim: ArmySim = ArmyBridge.current.sim
	var centre: Vector3 = settlement.global_position
	print("CELLS race=%s" % settlement.race_name)
	for gate in settlement._gates:
		var g: Vector3 = gate.global_position
		var out := Vector2(g.x - centre.x, g.z - centre.z).normalized()
		var side := Vector2(-out.y, out.x)
		var radial := ""
		for k in range(-24, 25):
			var p := Vector2(g.x, g.z) + out * (k * 0.25)
			radial += "#" if not sim.is_walkable(p) else "."
		var across := ""
		for k in range(-12, 13):
			var p := Vector2(g.x, g.z) + side * (k * 0.25)
			across += "#" if not sim.is_walkable(p) else "."
		print("CELLS gate %s angle %.0f  in->out %s  across %s  shapes=%s" % [gate.name,
				rad_to_deg(atan2(out.y, out.x)), radial, across, _shapes(gate)])
	## What stands near each gate inside the ring.
	for gate in settlement._gates:
		for node in tree.get_nodes_in_group(&"buildings"):
			if node != gate and node.global_position.distance_to(gate.global_position) < 4.0 and not node.get_meta(&"wall_piece", false):
				print("CELLS near %s: %s at %.1f" % [gate.name, node.name, node.global_position.distance_to(gate.global_position)])
		for house in settlement._houses:
			if house.global_position.distance_to(gate.global_position) < 4.0:
				print("CELLS near %s: house at %.1f" % [gate.name, house.global_position.distance_to(gate.global_position)])

func _shapes(gate: Node) -> Array:
	var out: Array = []
	for child in gate.get_children():
		if child is CollisionShape3D:
			out.append([child.name, child.position, child.shape.get_class(), child.disabled])
		if child is StaticBody3D:
			out.append(["body:" + child.name, (child as Node3D).visible])
	return out
