extends Node
## Top-down grid shots of the map for picking open ground. Each PNG is centred
## on the named world position at zoom 60 looking straight down.

const OUT: String = "C:/Users/craig/AppData/Local/Temp/claude/c--Users-craig-Documents-rts-test/89b7fb26-b1c5-43a8-afb8-da1e8e24d9b8/scratchpad/scout"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	while not (get_tree().current_scene is Main) or SceneLoader.is_transitioning:
		await get_tree().process_frame
	var main: Main = get_tree().current_scene
	main.ui_root.visible = false
	main.fog_of_war.reveal_all = true
	main.camera_rig.set_process(false)
	main.camera_rig.set_process_unhandled_input(false)
	var attrs := main.camera.attributes as CameraAttributesPractical
	if attrs:
		attrs.dof_blur_far_enabled = false
		attrs.dof_blur_near_enabled = false
	for cx in [-40, 0, 40]:
		for cz in [-40, 0, 40]:
			var rig := main.camera_rig
			rig.global_position = Vector3(cx, 0, cz)
			rig.yaw.rotation_degrees.y = 0.0
			rig.pitch.rotation_degrees.x = -89.0
			rig.zoom_distance = 75.0
			rig.camera.position.z = 75.0
			for f in 10:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("%s/top_%d_%d.png" % [OUT, cx, cz])
	get_tree().quit()
