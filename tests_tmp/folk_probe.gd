extends RefCounted

## Throwaway: ui_shot --stage for SettlementFolk. Owns the looked-at settlement,
## builds slots, logs peg states, then walks in an enemy to check hiding.

func stage(main: Node) -> void:
	var tree := main.get_tree()
	await tree.create_timer(0.5).timeout
	var folk: SettlementFolk = null
	for node in tree.get_nodes_in_group(&"objectives"):
		var f := node.get_node_or_null(^"Folk") as SettlementFolk
		if f != null and f._mmi.visible:
			folk = f
	if folk == null:
		print("PROBE no visible folk")
		return
	var settlement: Objective = folk._settlement
	settlement._set_owner(1)
	settlement.owner_peer_id = 1
	for want in ["Granary", "Market", "Barracks"]:
		for item in settlement.hall.producibles:
			if item.kind == ProducibleItem.Kind.SLOT and item.item_name == want:
				settlement.place_slot(item)
				break
	for i in int(OS.get_environment("FOLK_STEPS") if OS.get_environment("FOLK_STEPS") != "" else "12"):
		await tree.create_timer(2.0).timeout
		_log(folk, "t=%d" % (i * 2))
	var enemy_peer: int = 0
	for node in tree.get_nodes_in_group(&"units"):
		if node is Unit and node.owner_peer_id > 1:
			enemy_peer = node.owner_peer_id
			break
	var guard_scene: String = settlement._guard_roster[0].scene_path if not settlement._guard_roster.is_empty() else ""
	print("PROBE enemy peer %d scene %s" % [enemy_peer, guard_scene])
	if enemy_peer > 0 and guard_scene != "" and OS.get_environment("FOLK_ENEMY") != "":
		main.unit_spawner.spawn({"scene_path": guard_scene, "peer_id": enemy_peer, "tint": Color.RED,
				"position": settlement.global_position + Vector3(4, 0, 4)})
	aim_at_chimney(main, folk)
	for i in 3:
		await tree.create_timer(1.5).timeout
		_log(folk, "enemy t=%.1f" % (i * 1.5))

func _log(folk: SettlementFolk, label: String) -> void:
	var counts: Dictionary = {}
	var moving: int = 0
	for peg in folk._pegs:
		var key: String = SettlementFolk.State.keys()[peg.state]
		counts[key] = counts.get(key, 0) + 1
		if peg.pos.distance_to(peg.home) > 0.2:
			moving += 1
	var roles: Array = []
	for peg in folk._pegs:
		roles.append("%s:%s%s" % [SettlementFolk.Role.keys()[peg.role][0], SettlementFolk.State.keys()[peg.state].substr(0, 4), "*" if peg.carrying else ""])
	print("PROBE chimneys=%d smoke_inst=%d lanterns=%d houses=%s" % [folk._chimneys.size(), folk._smoke.multimesh.instance_count, folk._lanterns.multimesh.instance_count, folk._settlement._houses.map(func(h): return [h.get_meta(&"folk_radius", -1.0), h.get_meta(&"folk_top", -1.0)])])
	print("PROBE %s pegs=%d away=%d threat=%s %s %s" % [label, folk._pegs.size(), moving, folk._threatened, counts, roles])

static func aim_at_chimney(main: Node, folk: SettlementFolk) -> void:
	if folk._chimneys.is_empty():
		return
	var at: Vector3 = folk.to_global(folk._chimneys[0][0])
	print("PROBE chimney at %s smoke visible=%s" % [at, folk._smoke.visible])
	main.focus_camera_on(at)
