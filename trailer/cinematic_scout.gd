extends Node
## Lists Aldmere Vale's settlements and spawns, then a low 3/4 look at each
## one and at any extra spot passed as --spot=x,z.

const OUT: String = "C:/Users/craig/AppData/Local/Temp/claude/c--Users-craig-Documents-rts-test/a43835f9-4f5d-4d1c-9347-d739be632b2d/scratchpad/scout"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	while not (get_tree().current_scene is Main) or SceneLoader.is_transitioning:
		await get_tree().process_frame
	var main: Main = get_tree().current_scene
	main.ui_root.visible = false
	main.fog_of_war.reveal_all = true
	main.camera_rig.set_process(false)
	main.camera_rig.set_process_unhandled_input(false)
	for ai in main.ai_players.values():
		ai.process_mode = Node.PROCESS_MODE_DISABLED
	for f in 60:
		await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(OUT)
	var spots: Array = []
	var only_spots: bool = OS.get_cmdline_user_args().has("--spots-only")
	for node in get_tree().get_nodes_in_group(&"objectives"):
		var o := node as Objective
		print("OBJ %s race=%s tier=%d settlement=%s pos=(%.0f, %.0f)" % [o.name, o.race_name, o.tier, o.is_settlement(), o.global_position.x, o.global_position.z])
		if not only_spots:
			spots.append([o.name, o.global_position])
	for s in main.player_spawn_points.get_children():
		print("SPAWN %s pos=(%.0f, %.0f)" % [s.name, s.global_position.x, s.global_position.z])
		if not only_spots:
			spots.append([s.name, s.global_position])
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--spot="):
			var p: PackedStringArray = arg.trim_prefix("--spot=").split(",")
			spots.append(["spot_%s_%s" % [p[0], p[1]], Vector3(float(p[0]), 0, float(p[1]))])
	for spot in spots:
		for view in [[35.0, 30.0, 40.0], [0.0, 89.0, 70.0]]:
			var rig := main.camera_rig
			var pos: Vector3 = spot[1]
			rig.global_position = pos
			rig.yaw.rotation_degrees.y = view[0]
			rig.pitch_degrees = view[1]
			rig.pitch.rotation_degrees.x = -view[1]
			rig.zoom_distance = view[2]
			rig._zoom_target = view[2]
			rig._update_zoom()
			for i in 12:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("%s/%s_%d.png" % [OUT, spot[0], int(view[0])])
	## Overview straight down from high up.
	var rig := main.camera_rig
	rig.global_position = Vector3.ZERO
	rig.yaw.rotation_degrees.y = 0.0
	rig.pitch.rotation_degrees.x = -89.0
	rig.zoom_distance = 520.0
	rig._zoom_target = 520.0
	rig._update_zoom()
	for i in 20:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/overview.png" % OUT)
	get_tree().quit()
