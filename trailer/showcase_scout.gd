extends Node
## Top-down looks at candidate arenas, with the clouds and the depth-of-field
## turned off so tree cover is actually visible.

const OUT: String = "C:/Users/craig/AppData/Local/Temp/claude/c--Users-craig-Documents-rts-test/32ae6fcf-3708-4121-8bf9-598249988924/scratchpad/scout2"

const SPOTS: Array = [
	Vector2(10, -52), Vector2(47, -40), Vector2(-52, 26),
	Vector2(-20, 60), Vector2(30, -60), Vector2(70, 20),
]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for key in [&"clouds", &"depth_of_field"]:
		Settings.values[key] = false
		Settings._apply(key, false)
		Settings.changed.emit(key)
	while not (get_tree().current_scene is Main) or SceneLoader.is_transitioning:
		await get_tree().process_frame
	var main: Main = get_tree().current_scene
	main.ui_root.visible = false
	main.fog_of_war.reveal_all = true
	main.camera_rig.set_process(false)
	main.camera_rig.set_process_unhandled_input(false)
	for f in 30:
		await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(OUT)
	var attrs := main.camera.attributes as CameraAttributesPractical
	if attrs:
		attrs.dof_blur_far_enabled = false
		attrs.dof_blur_near_enabled = false
	for spot in SPOTS:
		var rig := main.camera_rig
		rig.global_position = Vector3(spot.x, 0, spot.y)
		rig.yaw.rotation_degrees.y = 0.0
		rig.pitch.rotation_degrees.x = -89.0
		rig.zoom_distance = 45.0
		rig._zoom_target = 45.0
		rig._update_zoom()
		for i in 10:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/spot_%d_%d.png" % [OUT, spot.x, spot.y])
	get_tree().quit()
