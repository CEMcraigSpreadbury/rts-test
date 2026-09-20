extends Node
## Creek survey: an ASCII grid of water/walkability and top-down shots.

const OUT: String = "C:/Users/craig/AppData/Local/Temp/claude/c--Users-craig-Documents-rts-test/32ae6fcf-3708-4121-8bf9-598249988924/scratchpad/scout"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	while not (get_tree().current_scene is Main) or SceneLoader.is_transitioning:
		await get_tree().process_frame
	var main: Main = get_tree().current_scene
	main.ui_root.visible = false
	main.fog_of_war.reveal_all = true
	main.camera_rig.set_process(false)
	main.camera_rig.set_process_unhandled_input(false)
	for f in 30:
		await get_tree().process_frame
	var terrain := GroundHeight.terrain(get_tree())
	var walk := NavWalkability.current
	var lines: PackedStringArray = []
	for zi in range(-32, 33):
		var z: float = zi * 4.0
		var line: String = "%5d " % int(z)
		for xi in range(-32, 33):
			var x: float = xi * 4.0
			var h: float = terrain.getHeightAtPosition(x, z, true)
			var w: bool = walk != null and walk.is_walkable(Vector3(x, h, z))
			var c: String
			if h < -2.5:
				c = "W" if w else "~"
			elif h > 1.0:
				c = "^" if w else "#"
			else:
				c = "." if w else "x"
			line += c
		lines.append(line)
	var f := FileAccess.open(OUT + "/grid.txt", FileAccess.WRITE)
	f.store_string("x from -128 step 4; W walkable water, ~ water, . land, x blocked land, ^ high walkable, # high blocked\n" + "\n".join(lines))
	f.close()
	var attrs := main.camera.attributes as CameraAttributesPractical
	if attrs:
		attrs.dof_blur_far_enabled = false
		attrs.dof_blur_near_enabled = false
	for cx in [-64, 0, 64]:
		for cz in [-64, 0, 64]:
			var rig := main.camera_rig
			rig.global_position = Vector3(cx, 0, cz)
			rig.yaw.rotation_degrees.y = 0.0
			rig.pitch.rotation_degrees.x = -89.0
			rig.zoom_distance = 110.0
			rig._zoom_target = 110.0
			rig._update_zoom()
			for i in 10:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("%s/top_%d_%d.png" % [OUT, cx, cz])
	get_tree().quit()
