extends Node3D

@onready var camera: Camera3D = $CameraRig/Yaw/Pitch/Camera3D
@onready var selection_box: ColorRect = $UI/SelectionBox
@onready var units_root: Node3D = $Units

var selected_units: Array[Unit] = []
var drag_start: Vector2 = Vector2.ZERO
var dragging: bool = false

const CLICK_DRAG_THRESHOLD: float = 6.0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				drag_start = event.position
				dragging = true
			elif dragging:
				dragging = false
				selection_box.visible = false
				_finish_selection(drag_start, event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_issue_move_order(event.position)
	elif event is InputEventMouseMotion and dragging:
		if drag_start.distance_to(event.position) > CLICK_DRAG_THRESHOLD:
			selection_box.visible = true
			_update_selection_box(event.position)

func _update_selection_box(current_pos: Vector2) -> void:
	var top_left := Vector2(min(drag_start.x, current_pos.x), min(drag_start.y, current_pos.y))
	var size := (current_pos - drag_start).abs()
	selection_box.position = top_left
	selection_box.size = size

func _finish_selection(start_pos: Vector2, end_pos: Vector2) -> void:
	var rect := Rect2(
		Vector2(min(start_pos.x, end_pos.x), min(start_pos.y, end_pos.y)),
		(end_pos - start_pos).abs()
	)

	for u in selected_units:
		u.selected = false
	selected_units.clear()

	if start_pos.distance_to(end_pos) <= CLICK_DRAG_THRESHOLD:
		var result: Unit = _raycast_unit(end_pos)
		if result:
			result.selected = true
			selected_units.append(result)
		return

	for child in units_root.get_children():
		if child is Unit and not camera.is_position_behind(child.global_position):
			var screen_pos: Vector2 = camera.unproject_position(child.global_position)
			if rect.has_point(screen_pos):
				child.selected = true
				selected_units.append(child)

func _raycast_unit(screen_pos: Vector2) -> Unit:
	var space_state := get_world_3d().direct_space_state
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 1000.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var result := space_state.intersect_ray(query)
	if result and result.collider is Unit:
		return result.collider
	return null

func _issue_move_order(screen_pos: Vector2) -> void:
	if selected_units.is_empty():
		return
	var space_state := get_world_3d().direct_space_state
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 1000.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var result := space_state.intersect_ray(query)
	if not result:
		return
	var target: Vector3 = result.position
	for i in selected_units.size():
		var offset := Vector3((i % 4) * 1.2 - 1.8, 0.0, floor(i / 4.0) * 1.2)
		selected_units[i].move_to(target + offset)
