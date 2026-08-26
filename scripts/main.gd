extends Node3D

const UNIT_SCENE: PackedScene = preload("res://scenes/units/unit.tscn")
const TOWN_CENTER_SCENE_PATH: String = "res://scenes/buildings/production_building.tscn"

const SPAWN_POINTS: Array[Vector3] = [
	Vector3(-3, 0, -3), Vector3(23, 0, -3), Vector3(-3, 0, 23), Vector3(23, 0, 23)
]
const TEAM_COLORS: Array[Color] = [
	Color(0.25, 0.55, 1.0), Color(1.0, 0.35, 0.3), Color(0.35, 1.0, 0.45), Color(1.0, 0.85, 0.3)
]

@export var available_building_types: Array[BuildingType] = []

@onready var camera: Camera3D = $CameraRig/Yaw/Pitch/Camera3D
@onready var selection_box: ColorRect = $UI/SelectionBox
@onready var resource_label: Label = $UI/ResourceLabel
@onready var units_root: Node3D = $Units
@onready var unit_spawner: MultiplayerSpawner = $UnitSpawner
@onready var buildings_root: Node3D = $Buildings
@onready var building_spawner: MultiplayerSpawner = $BuildingSpawner

@onready var build_panel: PanelContainer = $UI/BuildPanel
@onready var build_panel_vbox: VBoxContainer = $UI/BuildPanel/VBox
@onready var build_panel_name_label: Label = $UI/BuildPanel/VBox/BuildingNameLabel
@onready var build_panel_queue_label: Label = $UI/BuildPanel/VBox/QueueLabel

@onready var construction_panel_vbox: VBoxContainer = $UI/ConstructionPanel/VBox

@onready var chat_log: RichTextLabel = $UI/ChatLog
@onready var chat_input: LineEdit = $UI/ChatInput

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

## Host-only bookkeeping: which team index / Town Center belongs to each peer.
var team_index_by_peer: Dictionary = {}
var town_centers: Dictionary = {}

const MAX_CHAT_LINES: int = 8
## Extend this when new resource types (Stone, Gold, ...) are added.
const DEBUG_RESOURCE_TYPES: Array[ResourceType] = [preload("res://resources/wood_resource_type.tres")]
var chat_lines: Array[String] = []

func _ready() -> void:
	ResourceStockpile.changed.connect(_on_stockpile_changed)
	for building_type in available_building_types:
		var button := Button.new()
		button.text = "%s (%s)" % [building_type.building_name, _format_costs(building_type.costs)]
		button.pressed.connect(_start_placement.bind(building_type))
		construction_panel_vbox.add_child(button)

	unit_spawner.spawn_function = _spawn_unit_from_data
	building_spawner.spawn_function = _spawn_building_from_data
	if multiplayer.is_server():
		_spawn_all_players()

	chat_input.text_submitted.connect(_on_chat_submitted)

func _my_peer_id() -> int:
	return multiplayer.get_unique_id()

## --- Player / unit / building spawning (host only) ---

func _spawn_all_players() -> void:
	var peer_ids: Array = [1]
	if multiplayer.multiplayer_peer != null:
		peer_ids.append_array(multiplayer.get_peers())
	for i in peer_ids.size():
		_spawn_player_base(peer_ids[i], i)

func _spawn_player_base(peer_id: int, index: int) -> void:
	var base_pos: Vector3 = SPAWN_POINTS[index % SPAWN_POINTS.size()]
	var tint: Color = TEAM_COLORS[index % TEAM_COLORS.size()]
	team_index_by_peer[peer_id] = index

	for i in 2:
		unit_spawner.spawn({
			"peer_id": peer_id,
			"tint": tint,
			"position": base_pos + Vector3(i * 1.5, 0.0, 0.0),
		})

	var town_center: ProductionBuilding = building_spawner.spawn({
		"scene_path": TOWN_CENTER_SCENE_PATH,
		"peer_id": peer_id,
		"position": base_pos + Vector3(-4.0, 0.0, 4.0),
	})
	town_centers[peer_id] = town_center

func _spawn_unit_from_data(data: Dictionary) -> Node:
	var scene: PackedScene = load(data.scene_path) if data.has("scene_path") else UNIT_SCENE
	var unit: Unit = scene.instantiate()
	unit.owner_peer_id = data.peer_id
	unit.team_tint = data.tint
	unit.position = data.position
	unit.animation_changed.connect(_on_unit_animation_changed.bind(unit))
	return unit

## RPCs declared directly on dynamically-spawned Unit nodes weren't reaching
## clients, so units relay animation changes here and this (statically present,
## proven-reliable) node broadcasts them instead. Sprite flip is NOT relayed
## this way — it's inherently viewer-dependent, so each peer computes it locally
## from the unit's synced rotation and that peer's own camera (see Unit._process()).
func _on_unit_animation_changed(anim_name: String, unit: Unit) -> void:
	if multiplayer.is_server() and multiplayer.multiplayer_peer != null:
		_rpc_unit_animation.rpc(unit.get_path(), anim_name)

@rpc("authority", "call_remote", "reliable")
func _rpc_unit_animation(unit_path: NodePath, anim_name: String) -> void:
	var unit := get_node_or_null(unit_path) as Unit
	if unit:
		unit.sprite.play(anim_name)

func _spawn_building_from_data(data: Dictionary) -> Node:
	var scene: PackedScene = load(data.scene_path)
	var building: ProductionBuilding = scene.instantiate()
	building.owner_peer_id = data.peer_id
	building.position = data.position
	building.item_completed.connect(_on_building_item_completed.bind(building))
	return building

func _on_building_item_completed(item: ProducibleItem, building: ProductionBuilding) -> void:
	if not multiplayer.is_server():
		return
	if item.kind != ProducibleItem.Kind.UNIT or item.unit_scene == null:
		return
	var spawn_point: Node3D = building.get_node_or_null(building.spawn_point_path)
	var spawn_pos: Vector3 = spawn_point.global_position if spawn_point else building.global_position
	var team_index: int = team_index_by_peer.get(building.owner_peer_id, 0)
	unit_spawner.spawn({
		"scene_path": item.unit_scene.resource_path,
		"peer_id": building.owner_peer_id,
		"tint": TEAM_COLORS[team_index % TEAM_COLORS.size()],
		"position": spawn_pos,
	})

func _get_dropoff_for(peer_id: int) -> Node3D:
	var town_center: ProductionBuilding = town_centers.get(peer_id)
	if town_center == null:
		return null
	return town_center.get_node_or_null("DropoffPoint")

func _process(_delta: float) -> void:
	if selected_building:
		_update_queue_label()
	if placing_type:
		_update_placement_ghost()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if chat_input.visible and event.keycode == KEY_ESCAPE:
			_close_chat_input()
			get_viewport().set_input_as_handled()
			return
		if not chat_input.visible and event.keycode == KEY_ENTER:
			_open_chat_input()
			get_viewport().set_input_as_handled()
			return
	if chat_input.visible:
		return

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
		if collider is Unit and collider.owner_peer_id == _my_peer_id():
			collider.selected = true
			selected_units.append(collider)
			_select_building(null)
		elif collider is ProductionBuilding and collider.owner_peer_id == _my_peer_id():
			_select_building(collider)
		else:
			_select_building(null)
		return

	_select_building(null)
	for child in units_root.get_children():
		if child is Unit and child.owner_peer_id == _my_peer_id() and not camera.is_position_behind(child.global_position):
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

## Selection is local, but actually moving/gathering only ever happens on the
## host, so the command is sent there and executed on its authoritative units.
func _issue_move_order(screen_pos: Vector2) -> void:
	if selected_units.is_empty():
		return
	var result := _raycast(screen_pos)
	if result.is_empty():
		return

	var unit_paths: Array[NodePath] = []
	for unit in selected_units:
		unit_paths.append(unit.get_path())

	var target_path := NodePath()
	if result.collider is Gatherable:
		target_path = result.collider.get_path()
	elif result.collider is Unit and result.collider.owner_peer_id != _my_peer_id():
		target_path = result.collider.get_path()

	_rpc_issue_command.rpc_id(1, unit_paths, target_path, result.position)

@rpc("any_peer", "call_local", "reliable")
func _rpc_issue_command(unit_paths: Array[NodePath], target_path: NodePath, world_pos: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = _my_peer_id()

	var target_node: Node = get_node_or_null(target_path) if target_path != NodePath() else null

	for i in unit_paths.size():
		var unit := get_node_or_null(unit_paths[i]) as Unit
		if unit == null or unit.owner_peer_id != sender_id:
			continue
		if target_node is Gatherable:
			unit.command_gather(target_node, _get_dropoff_for(sender_id))
		elif target_node is Unit and target_node.owner_peer_id != unit.owner_peer_id:
			unit.command_attack(target_node)
		else:
			var offset := Vector3((i % 4) * 1.2 - 1.8, 0.0, floor(i / 4.0) * 1.2)
			unit.command_move(world_pos + offset)

func _on_stockpile_changed(resource_name: String, amount: int) -> void:
	resource_label.text = "%s: %d" % [resource_name, amount]

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

	for i in building.producibles.size():
		var item: ProducibleItem = building.producibles[i]
		var button := Button.new()
		button.text = "%s (%s)" % [item.item_name, _format_costs(item.costs)]
		button.pressed.connect(_on_producible_button_pressed.bind(building, i))
		build_panel_vbox.add_child(button)

	_update_queue_label()

func _on_selected_building_constructed(building: ProductionBuilding) -> void:
	if selected_building == building:
		_select_building(building)

func _on_producible_button_pressed(building: ProductionBuilding, item_index: int) -> void:
	_rpc_enqueue.rpc_id(1, building.get_path(), item_index)

@rpc("any_peer", "call_local", "reliable")
func _rpc_enqueue(building_path: NodePath, item_index: int) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = _my_peer_id()

	var building := get_node_or_null(building_path) as ProductionBuilding
	if building == null or building.owner_peer_id != sender_id:
		return
	if item_index < 0 or item_index >= building.producibles.size():
		return
	building.enqueue(building.producibles[item_index])

func _update_queue_label() -> void:
	if selected_building.is_under_construction:
		build_panel_queue_label.text = "Constructing... %d%%" % int(selected_building.construction_progress * 100)
		return
	if selected_building.synced_queue_size <= 0:
		build_panel_queue_label.text = "Queue: empty"
		return
	var extra: int = selected_building.synced_queue_size - 1
	build_panel_queue_label.text = "Building %s (%.1fs)%s" % [
		selected_building.synced_current_item_name, selected_building.synced_time_remaining,
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
	if not placement_valid:
		_cancel_placement()
		return
	var type_index: int = available_building_types.find(placing_type)
	_rpc_request_build.rpc_id(1, type_index, placement_ghost.global_position)
	_cancel_placement()

@rpc("any_peer", "call_local", "reliable")
func _rpc_request_build(type_index: int, world_pos: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = _my_peer_id()

	if type_index < 0 or type_index >= available_building_types.size():
		return
	var building_type: BuildingType = available_building_types[type_index]
	if not ResourceStockpile.can_afford(sender_id, building_type.costs):
		return
	if not _is_placement_valid(world_pos, building_type.footprint_radius):
		return
	ResourceStockpile.spend(sender_id, building_type.costs)

	var building: ProductionBuilding = building_spawner.spawn({
		"scene_path": building_type.scene.resource_path,
		"peer_id": sender_id,
		"position": world_pos,
	})
	building.begin_construction(building_type.construction_time)

func _cancel_placement() -> void:
	if placement_ghost:
		placement_ghost.queue_free()
		placement_ghost = null
	placing_type = null

## --- Chat / debug console ---
## Type a normal message to broadcast it to everyone, or "cmd ..." for a
## debug command (currently: "cmd add <resource> <amount>" grants yourself
## that resource without playing, e.g. "cmd add wood 10").

func _open_chat_input() -> void:
	chat_input.visible = true
	chat_input.text = ""
	chat_input.grab_focus()

func _close_chat_input() -> void:
	chat_input.visible = false
	chat_input.text = ""
	chat_input.release_focus()

func _on_chat_submitted(text: String) -> void:
	_close_chat_input()
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return
	_rpc_submit_chat.rpc_id(1, trimmed)

@rpc("any_peer", "call_local", "reliable")
func _rpc_submit_chat(text: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = _my_peer_id()

	if text.begins_with("cmd "):
		_execute_debug_command(sender_id, text.substr(4))
	else:
		_rpc_display_chat.rpc("Player %d: %s" % [sender_id, text])

func _execute_debug_command(sender_id: int, args_string: String) -> void:
	var parts: PackedStringArray = args_string.strip_edges().split(" ", false)
	if parts.is_empty():
		return

	match parts[0].to_lower():
		"add":
			if parts.size() < 3:
				_rpc_display_chat.rpc_id(sender_id, "[debug] usage: cmd add <resource> <amount>")
				return
			var resource_type: ResourceType = _find_resource_type_by_name(parts[1])
			if resource_type == null:
				_rpc_display_chat.rpc_id(sender_id, "[debug] unknown resource '%s'" % parts[1])
				return
			var amount: int = int(parts[2])
			ResourceStockpile.add(sender_id, resource_type, amount)
			_rpc_display_chat.rpc_id(sender_id, "[debug] +%d %s" % [amount, resource_type.display_name])
		"help":
			_rpc_display_chat.rpc_id(sender_id, "[debug] commands: cmd add <resource> <amount>")
		_:
			_rpc_display_chat.rpc_id(sender_id, "[debug] unknown command '%s'" % parts[0])

func _find_resource_type_by_name(resource_name: String) -> ResourceType:
	for resource_type in DEBUG_RESOURCE_TYPES:
		if resource_type.display_name.to_lower() == resource_name.to_lower():
			return resource_type
	return null

@rpc("authority", "call_local", "reliable")
func _rpc_display_chat(line: String) -> void:
	chat_lines.append(line)
	if chat_lines.size() > MAX_CHAT_LINES:
		chat_lines.pop_front()
	chat_log.text = "\n".join(chat_lines)
