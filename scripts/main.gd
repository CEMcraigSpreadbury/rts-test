extends Node3D

@export var available_building_types: Array[BuildingType] = []

@onready var camera: Camera3D = $CameraRig/Yaw/Pitch/Camera3D
@onready var selection_box: ColorRect = $UI/SelectionBox
@onready var resource_label: Label = $UI/ResourceLabel
@onready var units_root: Node3D = $Units
@onready var dropoff_point: Node3D = $TownCenter/DropoffPoint

@onready var build_panel: PanelContainer = $UI/BuildPanel
@onready var build_panel_vbox: VBoxContainer = $UI/BuildPanel/VBox
@onready var build_panel_name_label: Label = $UI/BuildPanel/VBox/BuildingNameLabel
@onready var build_panel_queue_label: Label = $UI/BuildPanel/VBox/QueueLabel

@onready var construction_panel_vbox: VBoxContainer = $UI/ConstructionPanel/VBox

var selected_units: Array[Unit] = []
var selected_building: ProductionBuilding = null
var drag_start: Vector2 = Vector2.ZERO
var dragging: bool = false

const CLICK_DRAG_THRESHOLD: float = 6.0

const VALID_GHOST_COLOR: Color = Color(0.3, 1.0, 0.3, 0.45)
const INVALID_GHOST_COLOR: Color = Color(1.0, 0.3, 0.3, 0.45)

var placing_type: BuildingType = null
var placement_ghost: MeshInstance3D = null
var placement_valid: bool = false

func _ready() -> void:
	ResourceStockpile.changed.connect(_on_stockpile_changed)
	for building_type in available_building_types:
		var button := Button.new()
		button.text = "%s (%s)" % [building_type.building_name, _format_costs(building_type.costs)]
		button.pressed.connect(_start_placement.bind(building_type))
		construction_panel_vbox.add_child(button)

func _process(_delta: float) -> void:
	if selected_building:
		_update_queue_label()
	if placing_type:
		_update_placement_ghost()

func _unhandled_input(event: InputEvent) -> void:
	if placing_type:
		_handle_placement_input(event)
		return

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
		var collider: Object = _raycast(end_pos).get("collider")
		if collider is Unit:
			collider.selected = true
			selected_units.append(collider)
			_select_building(null)
		elif collider is ProductionBuilding:
			_select_building(collider)
		else:
			_select_building(null)
		return

	_select_building(null)
	for child in units_root.get_children():
		if child is Unit and not camera.is_position_behind(child.global_position):
			var screen_pos: Vector2 = camera.unproject_position(child.global_position)
			if rect.has_point(screen_pos):
				child.selected = true
				selected_units.append(child)

func _raycast(screen_pos: Vector2) -> Dictionary:
	var space_state := get_world_3d().direct_space_state
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 1000.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	return space_state.intersect_ray(query)

func _issue_move_order(screen_pos: Vector2) -> void:
	if selected_units.is_empty():
		return
	var result := _raycast(screen_pos)
	if result.is_empty():
		return

	if result.collider is Gatherable:
		for unit in selected_units:
			unit.command_gather(result.collider, dropoff_point)
		return

	var target: Vector3 = result.position
	for i in selected_units.size():
		var offset := Vector3((i % 4) * 1.2 - 1.8, 0.0, floor(i / 4.0) * 1.2)
		selected_units[i].command_move(target + offset)

func _on_stockpile_changed(resource_type: ResourceType, amount: int) -> void:
	resource_label.text = "%s: %d" % [resource_type.display_name, amount]

func _select_building(building: ProductionBuilding) -> void:
	selected_building = building
	build_panel.visible = building != null
	if building == null:
		return

	build_panel_name_label.text = building.building_name
	for child in build_panel_vbox.get_children():
		if child != build_panel_name_label and child != build_panel_queue_label:
			child.queue_free()

	if building.is_under_construction:
		build_panel_queue_label.text = "Constructing... %d%%" % int(building.construction_progress * 100)
		if not building.construction_finished.is_connected(_on_selected_building_constructed):
			building.construction_finished.connect(_on_selected_building_constructed.bind(building), CONNECT_ONE_SHOT)
		return

	for item in building.producibles:
		var button := Button.new()
		button.text = "%s (%s)" % [item.item_name, _format_costs(item.costs)]
		button.pressed.connect(_on_producible_button_pressed.bind(building, item, button))
		build_panel_vbox.add_child(button)

	_update_queue_label()

func _on_selected_building_constructed(building: ProductionBuilding) -> void:
	if selected_building == building:
		_select_building(building)

func _on_producible_button_pressed(building: ProductionBuilding, item: ProducibleItem, button: Button) -> void:
	if not building.enqueue(item):
		button.text = "%s (%s) - not enough resources" % [item.item_name, _format_costs(item.costs)]

func _update_queue_label() -> void:
	if selected_building.is_under_construction:
		build_panel_queue_label.text = "Constructing... %d%%" % int(selected_building.construction_progress * 100)
		return
	if selected_building.queue.is_empty():
		build_panel_queue_label.text = "Queue: empty"
		return
	var first: ProducibleItem = selected_building.queue[0]
	var extra: int = selected_building.queue.size() - 1
	build_panel_queue_label.text = "Building %s (%.1fs)%s" % [
		first.item_name, selected_building.time_remaining(),
		" + %d queued" % extra if extra > 0 else ""
	]

func _format_costs(costs: Array[ResourceCost]) -> String:
	var parts: Array[String] = []
	for cost in costs:
		parts.append("%d %s" % [cost.amount, cost.resource_type.display_name])
	return ", ".join(parts)

## --- Building placement ---

func _start_placement(building_type: BuildingType) -> void:
	_cancel_placement()
	placing_type = building_type
	_select_building(null)

	var mesh := CylinderMesh.new()
	mesh.top_radius = building_type.footprint_radius
	mesh.bottom_radius = building_type.footprint_radius
	mesh.height = 0.2

	placement_ghost = MeshInstance3D.new()
	placement_ghost.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	placement_ghost.set_surface_override_material(0, material)
	add_child(placement_ghost)

func _update_placement_ghost() -> void:
	var mouse_pos := get_viewport().get_mouse_position()
	var result := _raycast(mouse_pos)
	if result.is_empty():
		placement_ghost.visible = false
		return
	placement_ghost.visible = true
	placement_ghost.global_position = result.position

	placement_valid = _is_placement_valid(result.position, placing_type.footprint_radius)
	var material: StandardMaterial3D = placement_ghost.get_surface_override_material(0)
	material.albedo_color = VALID_GHOST_COLOR if placement_valid else INVALID_GHOST_COLOR

func _is_placement_valid(pos: Vector3, radius: float) -> bool:
	var space_state := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), pos)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	for result in space_state.intersect_shape(query, 8):
		if result.collider is ProductionBuilding or result.collider is Gatherable:
			return false
	return true

func _handle_placement_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_confirm_placement()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_placement()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_cancel_placement()

func _confirm_placement() -> void:
	if not placement_valid or not ResourceStockpile.can_afford(placing_type.costs):
		return
	ResourceStockpile.spend(placing_type.costs)

	var building: ProductionBuilding = placing_type.scene.instantiate()
	building.units_container_path = ^"../Units"
	add_child(building)
	building.global_position = placement_ghost.global_position
	building.begin_construction(placing_type.construction_time)

	_cancel_placement()

func _cancel_placement() -> void:
	if placement_ghost:
		placement_ghost.queue_free()
		placement_ghost = null
	placing_type = null
