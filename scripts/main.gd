extends Node3D

const UNIT_SCENE: PackedScene = preload("res://scenes/units/unit.tscn")
const TOWN_CENTER_SCENE_PATH: String = "res://scenes/buildings/production_building.tscn"

const SPAWN_POINTS: Array[Vector3] = [
	Vector3(-3, 0, -3), Vector3(23, 0, -3), Vector3(-3, 0, 23), Vector3(23, 0, 23)
]
const TEAM_COLORS: Array[Color] = [
	Color(0.25, 0.55, 1.0), Color(1.0, 0.35, 0.3), Color(0.35, 1.0, 0.45), Color(1.0, 0.85, 0.3)
]

## Command-card hotkeys. The camera reads W/A/S/D/Q/E via raw Input.is_key_pressed()
## polling every frame (see rts_camera.gd), completely bypassing _unhandled_input,
## so none of these can safely use those letters — set_input_as_handled() would
## not stop the camera from also reacting to them.
const UNIT_MOVE_KEY: Key = KEY_M
const UNIT_STOP_KEY: Key = KEY_H
const UNIT_ATTACK_KEY: Key = KEY_F
const UNIT_PATROL_KEY: Key = KEY_P
## Only shown/live when at least one selected unit has can_build; opens the
## same construction menu the idle action panel shows, reusing BUILDING_HOTKEYS
## for the actual building choice — safe since only one of the two menus is
## ever live for a given selection state.
const UNIT_BUILD_KEY: Key = KEY_B
const PRODUCIBLE_HOTKEYS: Array[Key] = [KEY_I, KEY_J, KEY_K, KEY_L]
const BUILDING_HOTKEYS: Array[Key] = [KEY_Z, KEY_X, KEY_C, KEY_V, KEY_B]
## The action panel's grid always has exactly this many slots (4 columns x 3
## rows), padded with blank placeholders, so its size never changes with context.
const ACTION_PANEL_SLOT_COUNT: int = 12

@export var available_building_types: Array[BuildingType] = []

@onready var camera: Camera3D = $CameraRig/Yaw/Pitch/Camera3D
@onready var camera_rig: Node3D = $CameraRig
@onready var selection_box: ColorRect = $UI/SelectionBox
@onready var resource_label: Label = $UI/ResourceLabel
@onready var units_root: Node3D = $Units
@onready var unit_spawner: MultiplayerSpawner = $UnitSpawner
@onready var buildings_root: Node3D = $Buildings
@onready var building_spawner: MultiplayerSpawner = $BuildingSpawner

@onready var info_panel: PanelContainer = $UI/InfoPanel
@onready var info_panel_name_label: Label = $UI/InfoPanel/Margin/VBox/BuildingNameLabel
@onready var info_panel_content: VBoxContainer = $UI/InfoPanel/Margin/VBox/InfoContainer

## Single contextual action panel — always visible, its grid's contents and
## title change with the selection: nothing selected shows the construction
## menu, a selected building shows its producibles, selected units show the
## Move/Stop/Attack/Patrol commands.
@onready var action_panel_title: Label = $UI/ActionPanel/Margin/VBox/Title
@onready var action_panel_grid: GridContainer = $UI/ActionPanel/Margin/VBox/Grid

@onready var chat_log: RichTextLabel = $UI/ChatLog
@onready var chat_input: LineEdit = $UI/ChatInput

@onready var game_over_panel: PanelContainer = $UI/GameOverPanel
@onready var game_over_label: Label = $UI/GameOverPanel/Margin/VBox/ResultLabel

var selected_units: Array[Unit] = []
var selected_building: ProductionBuilding = null
## Left-click-selected resource node (tree/berry bush/gold deposit/farm),
## shown read-only in the info panel with its remaining amount — mutually
## exclusive with selected_building/selected_units, same as those are with
## each other.
var selected_resource: Gatherable = null
var drag_start: Vector2 = Vector2.ZERO
var dragging: bool = false

## "" | "move" | "attack" | "patrol" — armed by a command-card button/hotkey,
## consumed by the next left-click (see _handle_pending_order_input).
var pending_order_mode: String = ""
## True once the first click of the current patrol-targeting session has been
## sent, so later shift-clicks append a waypoint instead of starting a new patrol.
var _patrol_started_this_session: bool = false
## Which unit selection the command panel's buttons were last built for, so
## _process() only rebuilds them when the selection actually changed.
var _last_command_panel_units: Array[Unit] = []

## True while the action panel is showing the construction menu on behalf of
## a selected unit's Build button (as opposed to the always-available idle
## construction menu when nothing is selected).
var _showing_build_submenu: bool = false
## Captured when a construction button is pressed while _showing_build_submenu
## is true, so the host can send these units to build what gets placed.
var _pending_builder_paths: Array[NodePath] = []

## Command panel info section — built once per selection change, then only
## had their values (not structure) updated every frame, to avoid rebuilding
## Control nodes 60 times a second for something that just needs a number to move.
var _info_progress_bar: ProgressBar = null
var _info_empty_label: Label = null
var _info_slot_row: HBoxContainer = null
var _info_last_queue_size: int = -1
var _info_stats_label: Label = null
## Parallel to selected_units when more than one is selected.
var _info_unit_portrait_bars: Array[ProgressBar] = []
var _info_resource_label: Label = null

## Purely local UI state: which units/buildings belong to each numbered
## control group (Ctrl+1-9 assigns, 1-9 selects / recalls camera).
var control_groups: Dictionary = {}
## Which group number the CURRENT selection came from via a number-key press
## — cleared by any other selection action, so pressing the same digit twice
## in a row (with nothing else selected in between) means "snap the camera
## there" rather than "reselect it".
var _active_group_number: int = -1

const CLICK_DRAG_THRESHOLD: float = 6.0

const VALID_GHOST_COLOR: Color = Color(0.3, 1.0, 0.3, 0.45)
const INVALID_GHOST_COLOR: Color = Color(1.0, 0.3, 0.3, 0.45)

var placing_type: BuildingType = null
## Root of a stripped-down, translucent copy of the real building model (not
## the actual networked building) — purely a local visual preview.
var placement_ghost: Node3D = null
## (material, base_albedo_color) pairs collected while building the ghost, so
## its valid/invalid tint can be updated every frame without re-walking the
## node tree — see _set_ghost_valid().
var _ghost_surfaces: Array = []
var placement_valid: bool = false
## Only set when placing_type.requires_deposit — the specific world node the
## ghost is currently snapped to, sent to the host so it can position the
## building there itself rather than trusting a client-supplied position.
var _placement_target: Gatherable = null

## Purely local visual: only ever shown for the local player's own selected
## building, so it's built on demand rather than living in a networked scene.
var rally_marker: Node3D = null

## Purely local visual too — just feedback for whatever the mouse is
## currently over, built on demand like rally_marker.
var hover_ring: MeshInstance3D = null
## The last Unit/ProductionBuilding/Gatherable single-left-clicked (own or
## not) — keeps the hover ring showing on it even when the mouse moves away,
## until a different single-click or a click on empty space replaces/clears it.
var clicked_ring_target: Node3D = null

## Host-only bookkeeping: which team index / Town Center belongs to each peer.
var team_index_by_peer: Dictionary = {}
var town_centers: Dictionary = {}
## Host-only: peer_id -> how many is_main_base buildings they still have.
var main_base_count_by_peer: Dictionary = {}
var defeated_peers: Dictionary = {}
var game_over: bool = false

const MAX_CHAT_LINES: int = 8
## Extend this when new resource types (Stone, ...) are added.
const DEBUG_RESOURCE_TYPES: Array[ResourceType] = [
	preload("res://resources/wood_resource_type.tres"),
	preload("res://resources/food_resource_type.tres"),
	preload("res://resources/gold_resource_type.tres"),
]
var chat_lines: Array[String] = []

## resource_label shows every resource total plus population on one line;
## rebuilt in full on any single change since there are only a handful of values.
var _resource_totals: Dictionary = {}
var _population_used: int = 0
var _population_cap: int = 0

func _ready() -> void:
	ResourceStockpile.changed.connect(_on_stockpile_changed)
	Population.changed.connect(_on_population_changed)
	_populate_construction_buttons()

	unit_spawner.spawn_function = _spawn_unit_from_data
	building_spawner.spawn_function = _spawn_building_from_data
	if multiplayer.is_server():
		_spawn_all_players()

	chat_input.text_submitted.connect(_on_chat_submitted)

	game_over_panel.visible = false
	$UI/GameOverPanel/Margin/VBox/ReturnButton.pressed.connect(_on_return_to_lobby_pressed)

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

	## Free starting villagers never went through ProductionBuilding.enqueue()
	## (which is where population is normally reserved), so it has to be
	## reserved for them here instead or they'd stand outside the population
	## count entirely.
	for i in 2:
		var starting_unit: Unit = unit_spawner.spawn({
			"peer_id": peer_id,
			"tint": tint,
			"position": base_pos + Vector3(i * 1.5, 0.0, 0.0),
		})
		Population.reserve(peer_id, starting_unit.population_cost)

	var town_center: ProductionBuilding = building_spawner.spawn({
		"scene_path": TOWN_CENTER_SCENE_PATH,
		"peer_id": peer_id,
		"position": base_pos + Vector3(-4.0, 0.0, 4.0),
		"tint": tint,
	})
	town_centers[peer_id] = town_center
	## The starting Town Center is placed pre-built (begin_construction() is
	## never called for it), so its population capacity is granted immediately
	## rather than waiting on a construction_finished signal that will never fire.
	if town_center.population_capacity > 0:
		Population.add_cap(peer_id, town_center.population_capacity)
		town_center.destroyed.connect(
			func(): Population.add_cap(peer_id, -town_center.population_capacity), CONNECT_ONE_SHOT
		)

func _spawn_unit_from_data(data: Dictionary) -> Node:
	var scene: PackedScene = load(data.scene_path) if data.has("scene_path") else UNIT_SCENE
	var unit: Unit = scene.instantiate()
	unit.owner_peer_id = data.peer_id
	unit.team_tint = data.tint
	unit.position = data.position
	if data.has("population_cost"):
		unit.population_cost = data.population_cost
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

## Most buildable structures are ProductionBuildings (Town Center, Barracks,
## House), but Farm is a buildable Gatherable (no construction/production
## queue, just gathered from directly) — so this has to handle both instead
## of assuming ProductionBuilding.
func _spawn_building_from_data(data: Dictionary) -> Node:
	var scene: PackedScene = load(data.scene_path)
	var node: Node = scene.instantiate()
	node.position = data.position

	if node is ProductionBuilding:
		var building: ProductionBuilding = node
		building.owner_peer_id = data.peer_id
		building.team_tint = data.get("tint", Color.WHITE)
		building.item_completed.connect(_on_building_item_completed.bind(building))
		building.destroyed.connect(_on_building_destroyed.bind(building))
		if multiplayer.is_server() and building.is_main_base:
			main_base_count_by_peer[data.peer_id] = main_base_count_by_peer.get(data.peer_id, 0) + 1
		if data.has("deposit_path"):
			## Resolved independently on every peer (Gatherables aren't
			## networked nodes, but every peer has the same static resource
			## nodes at the same NodePath, so this still lines up correctly).
			building.linked_deposit = get_node_or_null(data.deposit_path) as Gatherable
	elif node is Gatherable:
		## Unlike natural resources (trees, berry bushes, gold mines — always
		## owner_peer_id 0), a player-built Farm is locked to whoever built it.
		node.owner_peer_id = data.peer_id

	return node

## --- Win condition (host only) ---

func _on_building_destroyed(building: ProductionBuilding) -> void:
	if not multiplayer.is_server() or not building.is_main_base or game_over:
		return
	var peer_id: int = building.owner_peer_id
	main_base_count_by_peer[peer_id] = maxi(main_base_count_by_peer.get(peer_id, 1) - 1, 0)
	if main_base_count_by_peer[peer_id] <= 0 and not defeated_peers.has(peer_id):
		defeated_peers[peer_id] = true
		_check_for_game_over()

func _check_for_game_over() -> void:
	var all_peers: Array = main_base_count_by_peer.keys()
	if all_peers.size() <= 1:
		return
	var remaining: Array = []
	for peer_id in all_peers:
		if not defeated_peers.has(peer_id):
			remaining.append(peer_id)
	if remaining.size() <= 1:
		game_over = true
		var winner_id: int = remaining[0] if remaining.size() == 1 else -1
		_rpc_game_over.rpc(winner_id)

@rpc("authority", "call_local", "reliable")
func _rpc_game_over(winner_peer_id: int) -> void:
	game_over = true
	game_over_panel.visible = true
	if winner_peer_id == -1:
		game_over_label.text = "Draw!"
	elif winner_peer_id == _my_peer_id():
		game_over_label.text = "Victory!"
	else:
		game_over_label.text = "Defeat"

func _on_return_to_lobby_pressed() -> void:
	Network.leave_game()
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")

func _on_building_item_completed(item: ProducibleItem, building: ProductionBuilding) -> void:
	if not multiplayer.is_server():
		return
	if item.kind != ProducibleItem.Kind.UNIT or item.unit_scene == null:
		return
	var spawn_point: Node3D = building.get_node_or_null(building.spawn_point_path)
	var spawn_pos: Vector3 = spawn_point.global_position if spawn_point else building.global_position
	## A previously-spawned, un-ordered unit may still be standing exactly on the
	## spawn point; spawning a new one at those identical coordinates makes their
	## avoidance radii perfectly overlap, which sends NavigationAgent3D's RVO
	## avoidance into a degenerate case (near-zero separation) that can fling one
	## of them across the map trying to resolve it. A small jitter keeps spawns
	## from ever landing exactly on top of each other.
	spawn_pos += Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.6, 0.6))
	var team_index: int = team_index_by_peer.get(building.owner_peer_id, 0)
	var unit: Unit = unit_spawner.spawn({
		"scene_path": item.unit_scene.resource_path,
		"peer_id": building.owner_peer_id,
		"tint": TEAM_COLORS[team_index % TEAM_COLORS.size()],
		"position": spawn_pos,
		"population_cost": item.population_cost,
	})
	if building.can_rally and building.has_rally_point:
		unit.command_move(building.rally_point)

func _get_dropoff_for(peer_id: int) -> Node3D:
	var town_center: ProductionBuilding = town_centers.get(peer_id)
	if town_center == null:
		return null
	return town_center.get_node_or_null("DropoffPoint")

func _process(_delta: float) -> void:
	if selected_building:
		_refresh_building_info()
	elif not selected_units.is_empty():
		## Catches every way selected_units can change (drag-select, control
		## groups, a selected unit dying mid-fight) without needing a refresh
		## call at each individual mutation site; only rebuilds the panel's
		## buttons/info structure when the selection actually changed since
		## last frame — otherwise just updates the already-built info values
		## (health, etc.) in place.
		_prune_selected_units()
		if selected_units != _last_command_panel_units:
			_refresh_command_panel()
		else:
			_refresh_unit_info_values()
	elif selected_resource != null:
		## A gathered-out resource node frees itself (Gatherable.gather()),
		## so this also has to notice when it's no longer valid.
		if not is_instance_valid(selected_resource):
			_select_resource(null)
		else:
			_refresh_resource_info()
	if placing_type:
		_update_placement_ghost()
	_update_hover_ring()

func _unhandled_input(event: InputEvent) -> void:
	if game_over:
		return

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

	if _showing_build_submenu and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_close_build_submenu()
		get_viewport().set_input_as_handled()
		return

	if pending_order_mode != "":
		_handle_pending_order_input(event)
		return

	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode >= KEY_1 and event.keycode <= KEY_9:
		var group_number: int = event.keycode - KEY_1 + 1
		if event.ctrl_pressed:
			_assign_control_group(group_number)
		else:
			_activate_control_group(group_number)
		get_viewport().set_input_as_handled()
		return

	## Gated on nothing being selected (the idle construction menu) or the
	## build submenu being open (a unit's Build button) — the only two times
	## the action panel actually shows these buttons, matching what's on
	## screen instead of secretly still working while it shows something else.
	if event is InputEventKey and event.pressed and not event.echo \
			and ((selected_building == null and selected_units.is_empty()) or _showing_build_submenu):
		var building_index: int = BUILDING_HOTKEYS.find(event.keycode)
		if building_index != -1 and building_index < available_building_types.size():
			_on_construction_button_pressed(available_building_types[building_index])
			get_viewport().set_input_as_handled()
			return

	if event is InputEventKey and event.pressed and not event.echo and not selected_units.is_empty() \
			and not _showing_build_submenu:
		if event.keycode == UNIT_MOVE_KEY:
			pending_order_mode = "move"
			get_viewport().set_input_as_handled()
			return
		elif event.keycode == UNIT_STOP_KEY:
			_issue_stop_order()
			get_viewport().set_input_as_handled()
			return
		elif event.keycode == UNIT_ATTACK_KEY:
			pending_order_mode = "attack"
			get_viewport().set_input_as_handled()
			return
		elif event.keycode == UNIT_PATROL_KEY:
			pending_order_mode = "patrol"
			_patrol_started_this_session = false
			get_viewport().set_input_as_handled()
			return
		elif event.keycode == UNIT_BUILD_KEY and _any_selected_can_build():
			_open_build_submenu()
			get_viewport().set_input_as_handled()
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
			if selected_building != null and selected_building.can_rally:
				_set_rally_point(event.position)
			else:
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

## Units can die (and be freed) between selection and the next click/order, so
## any stored reference must be validity-checked before use, not just trusted.
func _prune_selected_units() -> void:
	for i in range(selected_units.size() - 1, -1, -1):
		if not is_instance_valid(selected_units[i]):
			selected_units.remove_at(i)

## --- Control groups ---

func _assign_control_group(number: int) -> void:
	_prune_selected_units()
	var members: Array[Node3D] = []
	for unit in selected_units:
		members.append(unit)
	if selected_building != null and is_instance_valid(selected_building):
		members.append(selected_building)
	control_groups[number] = members
	## Assigning doesn't change what's currently selected, but the group this
	## selection "came from" (if any) is no longer meaningfully this number
	## specifically — next press of it should reselect, not recenter.
	_active_group_number = -1

func _activate_control_group(number: int) -> void:
	var members: Array = control_groups.get(number, [])
	for i in range(members.size() - 1, -1, -1):
		if not is_instance_valid(members[i]):
			members.remove_at(i)
	control_groups[number] = members
	if members.is_empty():
		_active_group_number = -1
		return

	if _active_group_number == number:
		_center_camera_on(members)
		return

	for u in selected_units:
		u.selected = false
	selected_units.clear()
	_select_building(null)
	_select_resource(null)

	## A mixed group (units + a building) selects the units, same as
	## drag-select already does — only a building-only group opens its panel.
	var units_in_group: Array[Unit] = []
	var building_in_group: ProductionBuilding = null
	for member in members:
		if member is Unit:
			units_in_group.append(member)
		elif member is ProductionBuilding and building_in_group == null:
			building_in_group = member

	if not units_in_group.is_empty():
		for unit in units_in_group:
			unit.selected = true
			selected_units.append(unit)
	elif building_in_group != null:
		_select_building(building_in_group)

	_active_group_number = number

func _center_camera_on(members: Array) -> void:
	var sum := Vector3.ZERO
	var count := 0
	for member in members:
		if is_instance_valid(member):
			sum += member.global_position
			count += 1
	if count == 0:
		return
	var avg := sum / count
	camera_rig.global_position.x = avg.x
	camera_rig.global_position.z = avg.z

func _finish_selection(start_pos: Vector2, end_pos: Vector2) -> void:
	_prune_selected_units()
	_active_group_number = -1
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
			_select_resource(null)
			clicked_ring_target = collider
		elif collider is ProductionBuilding and collider.owner_peer_id == _my_peer_id():
			_select_building(collider)
			_select_resource(null)
			clicked_ring_target = collider
		elif collider is Gatherable:
			## Any resource node (own or not — trees/berries/gold deposits have
			## no owner) shows its remaining amount in the info panel; unlike
			## a unit/building this isn't "yours to command", just informational.
			_select_building(null)
			_select_resource(collider)
			clicked_ring_target = collider
		elif collider is Unit or collider is ProductionBuilding:
			## Not "selectable" (enemy unit/building) but still a valid thing
			## to click-highlight.
			_select_building(null)
			_select_resource(null)
			clicked_ring_target = collider
		else:
			_select_building(null)
			_select_resource(null)
			clicked_ring_target = null
		return

	_select_building(null)
	_select_resource(null)
	clicked_ring_target = null
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

## Gatherable / enemy Unit / enemy-or-under-construction-or-deposit-linked
## ProductionBuilding -> its path, else an empty path meaning "plain ground".
func _resolve_order_target_path(result: Dictionary) -> NodePath:
	if result.collider is Gatherable:
		return result.collider.get_path()
	elif result.collider is Unit and result.collider.owner_peer_id != _my_peer_id():
		return result.collider.get_path()
	## A friendly building under construction is also a valid target (to send
	## builders to it), and so is a friendly building with a linked_deposit
	## (e.g. a Mine — right-clicking the mine itself should still gather from
	## the deposit it sits on), alongside the existing enemy-building-attack case.
	elif result.collider is ProductionBuilding and \
			(result.collider.owner_peer_id != _my_peer_id() or result.collider.is_under_construction \
				or result.collider.linked_deposit != null):
		return result.collider.get_path()
	return NodePath()

## Selection is local, but actually moving/gathering only ever happens on the
## host, so the command is sent there and executed on its authoritative units.
func _issue_move_order(screen_pos: Vector2) -> void:
	_prune_selected_units()
	if selected_units.is_empty():
		return
	var result := _raycast(screen_pos)
	if result.is_empty():
		return

	var unit_paths: Array[NodePath] = []
	for unit in selected_units:
		unit_paths.append(unit.get_path())

	var target_path := _resolve_order_target_path(result)
	_rpc_issue_command.rpc_id(1, unit_paths, target_path, result.position, false)

## Same target inference as a plain move order, except empty ground issues an
## attack-move instead of a plain move — see _rpc_issue_command's attack_move_fallback.
func _issue_attack_order(screen_pos: Vector2) -> void:
	_prune_selected_units()
	if selected_units.is_empty():
		return
	var result := _raycast(screen_pos)
	if result.is_empty():
		return

	var unit_paths: Array[NodePath] = []
	for unit in selected_units:
		unit_paths.append(unit.get_path())

	var target_path := _resolve_order_target_path(result)
	_rpc_issue_command.rpc_id(1, unit_paths, target_path, result.position, true)

func _issue_stop_order() -> void:
	_prune_selected_units()
	if selected_units.is_empty():
		return
	var unit_paths: Array[NodePath] = []
	for unit in selected_units:
		unit_paths.append(unit.get_path())
	_rpc_issue_stop.rpc_id(1, unit_paths)

@rpc("any_peer", "call_local", "reliable")
func _rpc_issue_command(unit_paths: Array[NodePath], target_path: NodePath, world_pos: Vector3, attack_move_fallback: bool) -> void:
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
		## Natural resources (owner_peer_id 0) are gatherable by anyone; a
		## player-built Farm is locked to whoever built it. A resource that
		## requires_building_on_top (e.g. a Gold Deposit) also isn't gatherable
		## until that building has actually finished — this is the
		## authoritative check, since the client only proposes a target and
		## the host decides what actually happens.
		if target_node is Gatherable and target_node.can_be_gathered() \
				and (target_node.owner_peer_id == 0 or target_node.owner_peer_id == unit.owner_peer_id):
			unit.command_gather(target_node, _get_dropoff_for(sender_id))
		## Right-clicking a finished building built on a deposit (e.g. a Mine)
		## should gather from what it sits on, same as clicking the deposit
		## directly — checked before the attack/build branches since a
		## same-owner building would never match attack anyway, and this only
		## applies once construction is done (still-building falls through to
		## the command_build branch below).
		elif target_node is ProductionBuilding and target_node.linked_deposit != null \
				and not target_node.is_under_construction and target_node.linked_deposit.can_be_gathered():
			unit.command_gather(target_node.linked_deposit, _get_dropoff_for(sender_id))
		elif (target_node is Unit or target_node is ProductionBuilding) and target_node.owner_peer_id != unit.owner_peer_id:
			unit.command_attack(target_node)
		elif target_node is ProductionBuilding and target_node.is_under_construction:
			unit.command_build(target_node)
		else:
			var offset := Vector3((i % 4) * 1.2 - 1.8, 0.0, floor(i / 4.0) * 1.2)
			if attack_move_fallback:
				unit.command_attack_move(world_pos + offset)
			else:
				unit.command_move(world_pos + offset)

## append: true once the current patrol-targeting session's first click has
## already gone out, so further shift-clicks extend the loop instead of
## restarting it (see _handle_pending_order_input).
@rpc("any_peer", "call_local", "reliable")
func _rpc_issue_patrol(unit_paths: Array[NodePath], world_pos: Vector3, append: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = _my_peer_id()

	for path in unit_paths:
		var unit := get_node_or_null(path) as Unit
		if unit == null or unit.owner_peer_id != sender_id:
			continue
		if append and unit.status_command == Unit.Command.PATROL:
			unit.command_patrol_add_waypoint(world_pos)
		else:
			unit.command_patrol([unit.global_position, world_pos])

@rpc("any_peer", "call_local", "reliable")
func _rpc_issue_stop(unit_paths: Array[NodePath]) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = _my_peer_id()

	for path in unit_paths:
		var unit := get_node_or_null(path) as Unit
		if unit == null or unit.owner_peer_id != sender_id:
			continue
		unit.command_stop()

## Mirrors _handle_placement_input's pattern: Escape/right-click cancels,
## left-click dispatches based on which order is currently armed. Move/Attack
## are single-shot; Patrol stays armed while Shift is held so multiple clicks
## chain into one patrol loop.
func _handle_pending_order_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		pending_order_mode = ""
		return
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		pending_order_mode = ""
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	match pending_order_mode:
		"move":
			_issue_move_order(event.position)
			pending_order_mode = ""
		"attack":
			_issue_attack_order(event.position)
			pending_order_mode = ""
		"patrol":
			var result := _raycast(event.position)
			if result.is_empty():
				return
			_prune_selected_units()
			if selected_units.is_empty():
				pending_order_mode = ""
				return
			var unit_paths: Array[NodePath] = []
			for unit in selected_units:
				unit_paths.append(unit.get_path())
			_rpc_issue_patrol.rpc_id(1, unit_paths, result.position, _patrol_started_this_session)
			_patrol_started_this_session = true
			if not event.shift_pressed:
				pending_order_mode = ""

func _on_stockpile_changed(resource_name: String, amount: int) -> void:
	_resource_totals[resource_name] = amount
	_update_resource_label()

func _on_population_changed(used: int, cap: int) -> void:
	_population_used = used
	_population_cap = cap
	_update_resource_label()

func _update_resource_label() -> void:
	var parts: Array[String] = []
	for resource_type in DEBUG_RESOURCE_TYPES:
		parts.append("%s: %d" % [resource_type.display_name, _resource_totals.get(resource_type.display_name, 0)])
	parts.append("Population: %d/%d" % [_population_used, _population_cap])
	resource_label.text = "   ".join(parts)

func _select_building(building: ProductionBuilding) -> void:
	selected_building = building
	_update_rally_marker()
	if building == null:
		_refresh_command_panel()
		return
	selected_resource = null

	info_panel.visible = true
	info_panel_name_label.text = building.building_name
	action_panel_title.text = building.building_name
	for child in action_panel_grid.get_children():
		child.queue_free()
	_build_building_info(building)

	if building.is_under_construction:
		if not building.construction_finished.is_connected(_on_selected_building_constructed):
			building.construction_finished.connect(_on_selected_building_constructed.bind(building), CONNECT_ONE_SHOT)
		_fill_action_panel_grid([])
		return

	var buttons: Array[Control] = []
	for i in building.producibles.size():
		var item: ProducibleItem = building.producibles[i]
		var hotkey: String = OS.get_keycode_string(PRODUCIBLE_HOTKEYS[i]) if i < PRODUCIBLE_HOTKEYS.size() else "?"
		var tooltip := "%s (%s)" % [item.item_name, _format_item_costs(item)]
		buttons.append(_make_command_button(hotkey, tooltip, item.icon, _on_producible_button_pressed.bind(building, i)))
	_fill_action_panel_grid(buttons)

## The action panel is always visible; this only rebuilds its grid/title and
## the info panel for the current selection when no building is selected:
## the four unit-command buttons if units are selected, a resource node's
## remaining amount if one is selected, otherwise the construction menu.
## (Building content is built directly in _select_building.)
func _refresh_command_panel() -> void:
	if selected_building != null:
		return
	for child in action_panel_grid.get_children():
		child.queue_free()
	for child in info_panel_content.get_children():
		child.queue_free()
	_info_stats_label = null
	_info_unit_portrait_bars.clear()
	_info_resource_label = null
	_last_command_panel_units = selected_units.duplicate()
	_showing_build_submenu = false

	if not selected_units.is_empty():
		info_panel.visible = true
		_populate_unit_command_buttons()
		_build_unit_info()
		_refresh_unit_info_values()
		return

	action_panel_title.text = "Construct"
	_populate_construction_buttons()

	if selected_resource != null and is_instance_valid(selected_resource):
		info_panel.visible = true
		info_panel_name_label.text = selected_resource.display_name
		_info_resource_label = Label.new()
		info_panel_content.add_child(_info_resource_label)
		_refresh_resource_info()
		return

	info_panel.visible = false

## Left-click select/deselect a resource node (see selected_resource);
## null clears it back to whatever the rest of the selection implies.
func _select_resource(resource: Gatherable) -> void:
	selected_resource = resource
	if resource != null:
		for u in selected_units:
			if is_instance_valid(u):
				u.selected = false
		selected_units.clear()
		selected_building = null
	_refresh_command_panel()

func _refresh_resource_info() -> void:
	if _info_resource_label and is_instance_valid(selected_resource):
		_info_resource_label.text = "%d remaining" % selected_resource.amount_remaining

func _populate_construction_buttons() -> void:
	var buttons: Array[Control] = []
	for i in available_building_types.size():
		var building_type: BuildingType = available_building_types[i]
		var hotkey: String = OS.get_keycode_string(BUILDING_HOTKEYS[i]) if i < BUILDING_HOTKEYS.size() else "?"
		var tooltip := "%s (%s)" % [building_type.building_name, _format_costs(building_type.costs)]
		buttons.append(_make_command_button(hotkey, tooltip, building_type.icon, _on_construction_button_pressed.bind(building_type)))
	_fill_action_panel_grid(buttons)

## The action panel's grid is a fixed-size 4-column layout (see
## ACTION_PANEL_SLOT_COUNT) regardless of how many real buttons a given
## context has, so its on-screen size/shape never changes with selection —
## needed so a frame image can be overlaid on top of it consistently. Unused
## slots are filled with an invisible, non-interactive placeholder of the
## same size instead of just leaving the grid short.
func _fill_action_panel_grid(buttons: Array[Control]) -> void:
	for button in buttons:
		action_panel_grid.add_child(button)
	for i in range(buttons.size(), ACTION_PANEL_SLOT_COUNT):
		action_panel_grid.add_child(_make_empty_action_slot())

func _make_empty_action_slot() -> Control:
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(56, 56)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return slot

## Idle construction menu and a unit's Build submenu both funnel through here:
## while the submenu is open this also captures which selected units (that
## can build) should be sent to build whatever gets placed.
func _on_construction_button_pressed(building_type: BuildingType) -> void:
	_pending_builder_paths.clear()
	if _showing_build_submenu:
		for unit in selected_units:
			if is_instance_valid(unit) and unit.can_build:
				_pending_builder_paths.append(unit.get_path())
	_start_placement(building_type)

func _any_selected_can_build() -> bool:
	for unit in selected_units:
		if is_instance_valid(unit) and unit.can_build:
			return true
	return false

func _open_build_submenu() -> void:
	_showing_build_submenu = true
	action_panel_title.text = "Build"
	for child in action_panel_grid.get_children():
		child.queue_free()
	_populate_construction_buttons()

func _close_build_submenu() -> void:
	_showing_build_submenu = false
	for child in action_panel_grid.get_children():
		child.queue_free()
	_populate_unit_command_buttons()

## --- Command panel info section ---

func _make_progress_bar_with_overlay() -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 20)
	bar.max_value = 1.0
	bar.show_percentage = false
	var overlay := Label.new()
	overlay.name = "Overlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	overlay.add_theme_font_size_override("font_size", 12)
	bar.add_child(overlay)
	return bar

## Builds the (structural) queue/construction display once per selection
## change; _refresh_building_info() then just updates values every frame.
func _build_building_info(building: ProductionBuilding) -> void:
	for child in info_panel_content.get_children():
		child.queue_free()
	_info_progress_bar = null
	_info_empty_label = null
	_info_slot_row = null
	_info_last_queue_size = -1

	_info_progress_bar = _make_progress_bar_with_overlay()
	info_panel_content.add_child(_info_progress_bar)

	if building.is_under_construction:
		return

	_info_empty_label = Label.new()
	_info_empty_label.text = "Queue: empty"
	info_panel_content.add_child(_info_empty_label)
	_info_slot_row = HBoxContainer.new()
	_info_slot_row.add_theme_constant_override("separation", 6)
	info_panel_content.add_child(_info_slot_row)

func _refresh_building_info() -> void:
	var building := selected_building
	if _info_progress_bar == null:
		_build_building_info(building)

	if building.is_under_construction:
		_info_progress_bar.value = building.construction_progress
		(_info_progress_bar.get_node("Overlay") as Label).text = _format_construction_status(building)
		return

	if building.synced_queue_size <= 0:
		_info_progress_bar.visible = false
		_info_empty_label.visible = true
		_info_slot_row.visible = false
		return

	_info_progress_bar.visible = true
	_info_empty_label.visible = false
	_info_slot_row.visible = true
	_info_progress_bar.value = building.synced_current_item_progress
	(_info_progress_bar.get_node("Overlay") as Label).text = "%s (%.1fs)" % [
		building.synced_current_item_name, building.synced_time_remaining
	]

	## Items queued behind the current one (synced_queue_size includes it),
	## shown as blank slots rather than icons since there's no per-item icon
	## art yet — just enough to see how deep the queue is at a glance.
	var queued_behind: int = building.synced_queue_size - 1
	if queued_behind != _info_last_queue_size:
		_info_last_queue_size = queued_behind
		for child in _info_slot_row.get_children():
			child.queue_free()
		for i in queued_behind:
			var slot := ColorRect.new()
			slot.custom_minimum_size = Vector2(20, 20)
			slot.color = Color(1, 1, 1, 0.2)
			_info_slot_row.add_child(slot)

## Builds either a single unit's stat readout or a grid of portrait+health
## widgets for a multi-unit selection — structural, called once per selection
## change; _refresh_unit_info_values() updates values every frame after.
func _build_unit_info() -> void:
	if selected_units.size() == 1:
		var unit := selected_units[0]
		info_panel_name_label.text = unit.display_name
		_info_stats_label = Label.new()
		_info_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		info_panel_content.add_child(_info_stats_label)
		return

	info_panel_name_label.text = "%d units selected" % selected_units.size()
	var portrait_grid := GridContainer.new()
	portrait_grid.columns = 4
	portrait_grid.add_theme_constant_override("h_separation", 6)
	portrait_grid.add_theme_constant_override("v_separation", 6)
	for unit in selected_units:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 3)
		var portrait := ColorRect.new()
		portrait.custom_minimum_size = Vector2(36, 36)
		portrait.color = unit.team_tint
		cell.add_child(portrait)
		var health_bar := ProgressBar.new()
		health_bar.custom_minimum_size = Vector2(36, 6)
		health_bar.max_value = 1.0
		health_bar.show_percentage = false
		cell.add_child(health_bar)
		portrait_grid.add_child(cell)
		_info_unit_portrait_bars.append(health_bar)
	info_panel_content.add_child(portrait_grid)

func _refresh_unit_info_values() -> void:
	if selected_units.size() == 1:
		if _info_stats_label:
			_info_stats_label.text = _format_unit_stats(selected_units[0])
		return
	for i in _info_unit_portrait_bars.size():
		if i < selected_units.size() and is_instance_valid(selected_units[i]):
			var unit := selected_units[i]
			_info_unit_portrait_bars[i].value = float(unit.status_current_health) / float(maxi(unit.max_health, 1))

func _format_unit_stats(unit: Unit) -> String:
	var lines: Array[String] = ["HP: %d / %d" % [unit.status_current_health, unit.max_health]]
	if unit.can_fight:
		lines.append("Attack: %d dmg every %.1fs (range %.1f)" % [unit.attack_damage, unit.attack_cooldown, unit.attack_range])
	if unit.can_gather:
		lines.append("Gather level %d (carries %d)" % [unit.gather_level, unit.carry_capacity])
	lines.append("Move speed: %.1f" % unit.move_speed)
	return "\n".join(lines)

func _populate_unit_command_buttons() -> void:
	action_panel_title.text = "Commands"
	var buttons: Array[Control] = [
		_make_command_button(OS.get_keycode_string(UNIT_MOVE_KEY), "Move", null, func(): pending_order_mode = "move"),
		_make_command_button(OS.get_keycode_string(UNIT_STOP_KEY), "Stop", null, _issue_stop_order),
		_make_command_button(OS.get_keycode_string(UNIT_ATTACK_KEY), "Attack", null, func(): pending_order_mode = "attack"),
		_make_command_button(OS.get_keycode_string(UNIT_PATROL_KEY), "Patrol", null, _arm_patrol_mode),
	]
	if _any_selected_can_build():
		buttons.append(_make_command_button(OS.get_keycode_string(UNIT_BUILD_KEY), "Build", null, _open_build_submenu))
	_fill_action_panel_grid(buttons)

func _arm_patrol_mode() -> void:
	pending_order_mode = "patrol"
	_patrol_started_this_session = false

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

## --- Rally points ---

## Applied to our own local copy immediately (for instant marker feedback and,
## if we're the host, because that copy IS the authoritative one), and also
## sent to the host so a non-host owner's rally point actually affects spawning.
func _set_rally_point(screen_pos: Vector2) -> void:
	var result := _raycast(screen_pos)
	if result.is_empty():
		return
	selected_building.rally_point = result.position
	selected_building.has_rally_point = true
	_update_rally_marker()
	_rpc_set_rally_point.rpc_id(1, selected_building.get_path(), result.position)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_rally_point(building_path: NodePath, world_pos: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = _my_peer_id()

	var building := get_node_or_null(building_path) as ProductionBuilding
	if building == null or building.owner_peer_id != sender_id or not building.can_rally:
		return
	building.rally_point = world_pos
	building.has_rally_point = true

func _update_rally_marker() -> void:
	if selected_building != null and selected_building.can_rally and selected_building.has_rally_point:
		_ensure_rally_marker()
		rally_marker.visible = true
		rally_marker.global_position = selected_building.rally_point
	elif rally_marker:
		rally_marker.visible = false

func _ensure_rally_marker() -> void:
	if rally_marker:
		return
	rally_marker = Node3D.new()
	add_child(rally_marker)

	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.05
	pole_mesh.bottom_radius = 0.05
	pole_mesh.height = 1.4
	pole.mesh = pole_mesh
	pole.position = Vector3(0, 0.7, 0)
	var pole_mat := StandardMaterial3D.new()
	pole_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pole_mat.albedo_color = Color(0.9, 0.9, 0.9)
	pole.set_surface_override_material(0, pole_mat)
	rally_marker.add_child(pole)

	var flag := MeshInstance3D.new()
	var flag_mesh := BoxMesh.new()
	flag_mesh.size = Vector3(0.5, 0.3, 0.02)
	flag.mesh = flag_mesh
	flag.position = Vector3(0.27, 1.15, 0)
	var flag_mat := StandardMaterial3D.new()
	flag_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flag_mat.albedo_color = Color(1.0, 0.85, 0.2)
	flag.set_surface_override_material(0, flag_mat)
	rally_marker.add_child(flag)

## --- Hover highlight ---

const HOVER_RING_COLOR: Color = Color(1.0, 1.0, 1.0, 0.55)
## Units have no NavigationObstacle3D to read a radius from, so this is just
## a reasonable fixed size matching their own SelectionRing.
const HOVER_RING_UNIT_RADIUS: float = 0.75

func _ensure_hover_ring() -> void:
	if hover_ring:
		return
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.9
	mesh.outer_radius = 1.0
	hover_ring = MeshInstance3D.new()
	hover_ring.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = HOVER_RING_COLOR
	hover_ring.set_surface_override_material(0, material)
	hover_ring.visible = false
	add_child(hover_ring)

func _is_ring_target(node: Object) -> bool:
	return node is Unit or node is ProductionBuilding or node is Gatherable

## Not shown while some other exclusive mode already owns the mouse
## (placing a building, dragging a selection box, chatting, game over).
## Otherwise prefers whatever's currently under the mouse (fog-of-war-hidden
## things don't count, even if their collider is still technically hit), and
## falls back to the last single-clicked target so the ring keeps showing on
## it even once the mouse moves away — see clicked_ring_target.
func _update_hover_ring() -> void:
	if placing_type or dragging or chat_input.visible or game_over:
		if hover_ring:
			hover_ring.visible = false
		return

	var collider: Object = _raycast(get_viewport().get_mouse_position()).get("collider")
	var hovered: Node3D = collider if (collider != null and _is_ring_target(collider) and collider.visible) else null
	var target: Node3D = hovered if hovered else (clicked_ring_target if is_instance_valid(clicked_ring_target) else null)

	## Selected units already show their own green SelectionRing — showing
	## this one too on top would be redundant.
	if target == null or (target is Unit and target.selected):
		if hover_ring:
			hover_ring.visible = false
		return

	_ensure_hover_ring()
	var radius: float = _hover_ring_radius(target)
	var mesh: TorusMesh = hover_ring.mesh
	mesh.outer_radius = radius
	mesh.inner_radius = maxf(radius - 0.08, 0.01)
	hover_ring.global_position = target.global_position + Vector3(0, 0.05, 0)
	hover_ring.visible = true

func _hover_ring_radius(node: Node) -> float:
	if node is Unit:
		return HOVER_RING_UNIT_RADIUS
	var obstacle: NavigationObstacle3D = node.get_node_or_null("NavigationObstacle3D")
	return obstacle.radius + 0.2 if obstacle else 1.0

func _format_construction_status(building: ProductionBuilding) -> String:
	var percent := int(building.construction_progress * 100)
	if building.synced_builder_count <= 0:
		return "Constructing... %d%% (needs a builder)" % percent
	return "Constructing... %d%% (%d building)" % [percent, building.synced_builder_count]

## Shared by the construction menu, a building's production menu, and the new
## unit-command panel: a square button showing only its hotkey letter (icon
## stays null everywhere today — no icon art exists yet, but the field is
## wired so real art can be dropped in later without touching this code).
func _make_command_button(hotkey_label: String, tooltip: String, icon: Texture2D, callback: Callable) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(56, 56)
	button.text = hotkey_label
	button.tooltip_text = tooltip
	button.icon = icon
	button.pressed.connect(callback)
	return button

func _format_costs(costs: Array[ResourceCost]) -> String:
	var parts: Array[String] = []
	for cost in costs:
		parts.append("%d %s" % [cost.amount, cost.resource_type.display_name])
	return ", ".join(parts)

func _format_item_costs(item: ProducibleItem) -> String:
	var text := _format_costs(item.costs)
	if item.kind == ProducibleItem.Kind.UNIT:
		text += ", %d Pop" % item.population_cost
	return text

## --- Building placement ---

func _start_placement(building_type: BuildingType) -> void:
	_cancel_placement()
	placing_type = building_type
	## Only needed to close an open building panel — skipped when a unit's
	## Build submenu started this placement, since _select_building(null)
	## would otherwise refresh the action panel back out of that submenu
	## (via _refresh_command_panel()) while the ghost is still following the mouse.
	if selected_building != null:
		_select_building(null)
	placement_ghost = _build_ghost(building_type.scene)
	add_child(placement_ghost)

## Builds a translucent, script-less, collision-less copy of a building's
## real scene for the placement preview — so the ghost always looks exactly
## like what will actually be built, not a generic stand-in shape.
func _build_ghost(scene: PackedScene) -> Node3D:
	var ghost: Node3D = scene.instantiate()
	ghost.set_script(null)
	_strip_ghost_children(ghost)
	_ghost_surfaces.clear()
	_collect_ghost_surfaces(ghost)
	return ghost

## Removes anything that would make the preview behave like a real building
## (collide, block pathing, replicate) — it's purely a harmless visual.
func _strip_ghost_children(node: Node) -> void:
	for child in node.get_children():
		var should_strip := child.name == "HealthBar" \
			or child is CollisionShape3D \
			or child is NavigationObstacle3D \
			or child is MultiplayerSynchronizer
		if should_strip:
			child.free()
		else:
			_strip_ghost_children(child)

## Applies a translucent material to every mesh surface and remembers each
## one's original color, so _set_ghost_valid() can re-tint them green/red
## every frame without re-walking the tree or losing each part's own color.
func _collect_ghost_surfaces(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance: MeshInstance3D = node
		var surface_count: int = mesh_instance.mesh.get_surface_count() if mesh_instance.mesh else 0
		for i in surface_count:
			var base: Material = mesh_instance.get_active_material(i)
			var base_color: Color = base.albedo_color if base is StandardMaterial3D else Color.WHITE
			var ghost_material := StandardMaterial3D.new()
			ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mesh_instance.set_surface_override_material(i, ghost_material)
			_ghost_surfaces.append({"material": ghost_material, "base_color": base_color})
	for child in node.get_children():
		_collect_ghost_surfaces(child)

func _set_ghost_valid(valid: bool) -> void:
	var tint: Color = VALID_GHOST_COLOR if valid else INVALID_GHOST_COLOR
	for entry in _ghost_surfaces:
		var material: StandardMaterial3D = entry["material"]
		var base_color: Color = entry["base_color"]
		material.albedo_color = Color(base_color.r * tint.r, base_color.g * tint.g, base_color.b * tint.b, tint.a)

func _update_placement_ghost() -> void:
	if placing_type.requires_deposit:
		_update_deposit_snap_ghost()
		return

	var mouse_pos := get_viewport().get_mouse_position()
	var result := _raycast(mouse_pos)
	if result.is_empty():
		placement_ghost.visible = false
		return
	placement_ghost.visible = true
	placement_ghost.global_position = result.position

	placement_valid = _is_placement_valid(result.position, placing_type.footprint_radius)
	_set_ghost_valid(placement_valid)

## Snap-to-target variant: the ghost only ever shows at an existing,
## unclaimed instance of placing_type.deposit_scene under the mouse, never
## following the mouse freely.
func _update_deposit_snap_ghost() -> void:
	var mouse_pos := get_viewport().get_mouse_position()
	var result := _raycast(mouse_pos)
	_placement_target = _find_valid_deposit(result.get("collider"))

	if _placement_target == null:
		placement_ghost.visible = false
		placement_valid = false
		return

	placement_ghost.visible = true
	placement_ghost.global_position = _placement_target.global_position
	placement_valid = true
	_set_ghost_valid(true)

func _find_valid_deposit(collider: Object) -> Gatherable:
	if collider == null or not (collider is Gatherable):
		return null
	var deposit: Gatherable = collider
	if deposit.is_claimed or not _matches_scene(deposit, placing_type.deposit_scene):
		return null
	return deposit

func _matches_scene(node: Node, scene: PackedScene) -> bool:
	return scene != null and node.scene_file_path == scene.resource_path

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
	var target_path := _placement_target.get_path() if _placement_target else NodePath()
	_rpc_request_build.rpc_id(1, type_index, placement_ghost.global_position, target_path, _pending_builder_paths)
	_cancel_placement()
	_pending_builder_paths.clear()
	if _showing_build_submenu:
		_close_build_submenu()

@rpc("any_peer", "call_local", "reliable")
func _rpc_request_build(type_index: int, world_pos: Vector3, target_path: NodePath, builder_paths: Array[NodePath]) -> void:
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

	## Deposit-snapped buildings ignore the client's proposed position — the
	## host looks the target up itself and uses its real position, so a
	## tampered/stale client position can't matter.
	var build_pos := world_pos
	var deposit: Gatherable = null
	if building_type.requires_deposit:
		deposit = get_node_or_null(target_path) as Gatherable
		if deposit == null or deposit.is_claimed or not _matches_scene(deposit, building_type.deposit_scene):
			return
		build_pos = deposit.global_position
	elif not _is_placement_valid(world_pos, building_type.footprint_radius):
		return

	ResourceStockpile.spend(sender_id, building_type.costs)
	if deposit:
		deposit.is_claimed = true

	var team_index: int = team_index_by_peer.get(sender_id, 0)
	var spawn_data: Dictionary = {
		"scene_path": building_type.scene.resource_path,
		"peer_id": sender_id,
		"position": build_pos,
		"tint": TEAM_COLORS[team_index % TEAM_COLORS.size()],
	}
	if deposit:
		spawn_data["deposit_path"] = deposit.get_path()
	var spawned: Node = building_spawner.spawn(spawn_data)
	## Farm (a buildable Gatherable, not a ProductionBuilding) has no
	## construction phase — it just appears complete.
	if spawned is ProductionBuilding:
		var building: ProductionBuilding = spawned
		building.begin_construction(building_type.construction_time)
		if building.population_capacity > 0:
			building.construction_finished.connect(func():
				Population.add_cap(sender_id, building.population_capacity)
				building.destroyed.connect(
					func(): Population.add_cap(sender_id, -building.population_capacity), CONNECT_ONE_SHOT
				)
			, CONNECT_ONE_SHOT)
		if deposit:
			building.construction_finished.connect(func():
				deposit.has_required_building = true
			, CONNECT_ONE_SHOT)
			building.destroyed.connect(func():
				deposit.has_required_building = false
				deposit.is_claimed = false
			, CONNECT_ONE_SHOT)

		## Sends whichever villager(s) opened the build menu to go build what
		## they just placed, instead of leaving them standing idle next to it.
		for path in builder_paths:
			var builder := get_node_or_null(path) as Unit
			if builder != null and builder.owner_peer_id == sender_id:
				builder.command_build(building)

func _cancel_placement() -> void:
	if placement_ghost:
		placement_ghost.queue_free()
		placement_ghost = null
	_ghost_surfaces.clear()
	placing_type = null
	_placement_target = null

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
