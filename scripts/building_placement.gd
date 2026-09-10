class_name BuildingPlacement
extends Node3D
## Building placement split out of main.gd: the single-building ghost,
## deposit snapping, wall drag and the gate tool, plus the host-side build
## RPCs that validate and spawn what gets placed.
##
## Created by Main._enter_tree() under a fixed name, so its RPCs resolve to
## the same node path on every peer.

var main: Main

## Captured when a construction button is pressed while showing_build_submenu
## is true, so the host can send these units to build what gets placed.
var _pending_builder_paths: Array[NodePath] = []
## True once a placement has been confirmed with Shift held — the current
## placement (or the next one, even a different building type — see
## on_construction_button_pressed) continues that same builder chain rather
## than starting a fresh one. See _confirm_placement/_rpc_request_build.
var _build_queue_active: bool = false

const VALID_GHOST_COLOR: Color = Color(0.3, 1.0, 0.3, 0.45)
const INVALID_GHOST_COLOR: Color = Color(1.0, 0.3, 0.3, 0.45)
## Minimum surface-normal Y component a placement point must have to count as
## "flat enough to build on" — roughly cos(41°). Below this the raycast hit a
## slope/cliff face (e.g. TileMapLayer3D terrain) rather than open ground.
const MAX_BUILD_SLOPE_NORMAL_Y: float = 0.75
## How many points around a footprint's edge (in addition to its center) get
## checked for flatness — catches a building whose center sits on flat ground
## but whose edge would overhang a nearby cliff.
const FOOTPRINT_SAMPLE_COUNT: int = 8
## Max height difference tolerated between the footprint's center and any
## edge sample — rejects straddling a level change even where both sides are
## individually flat (e.g. half on a raised terrace, half on the ground below).
const MAX_FOOTPRINT_HEIGHT_VARIANCE: float = 0.3

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

## --- Wall drag placement (placing_type.is_wall) ---
## True from the moment the left mouse button goes down over valid ground
## until it's released — _update_wall_drag() only grows _wall_drag_points
## while this is true; before/after that a click just arms or ends the drag.
var _wall_dragging: bool = false
## Sampled every _process() frame while dragging, spaced ~wall_segment_length
## apart along the actual cursor path (not a straight line from start to
## current point) so the wall follows curves/turns the same way the mouse
## drew them — see _wall_extend_path_to().
var _wall_drag_points: Array[Vector3] = []
## One ghost Node3D per would-be segment/corner, rebuilt (not just
## repositioned) every time _wall_drag_points changes length, since the
## count of pieces changes as the drag grows. Tinted per-piece (unlike the
## single-ghost case) so one bad segment in an otherwise-clear run is visible
## without invalidating pieces that are actually fine.
var _wall_ghosts: Array[Node3D] = []
## Live "N segments — cost" readout shown while dragging — see its creation
## in setup() and updates in _rebuild_wall_ghost().
var _wall_drag_label: Label = null
const WALL_SEGMENT_FOOTPRINT_RADIUS: float = 0.9
const WALL_CORNER_FOOTPRINT_RADIUS: float = 0.45
## Minimum direction change (radians) between two consecutive straight runs
## of the drag path before a corner piece is inserted — small jitter in the
## mouse path shouldn't spam corner posts along an otherwise-straight wall.
const WALL_CORNER_ANGLE_THRESHOLD: float = 0.28
## Hard cap on segments per single drag — keeps one drag's RPC payload and
## cost bounded even if a player drags all the way across the map.
const WALL_MAX_SEGMENTS: int = 80

## --- Gate tool (placing_type.is_gate_tool) ---
## The owned wall segment/corner currently under the mouse that the gate
## would replace if clicked, or null when nothing valid is hovered.
var _gate_target: ProductionBuilding = null

## Live "N segments — cost" readout for the wall drag tool — built here
## rather than in main.tscn: a small always-on-top overlay isn't worth
## another hand-edit to an already enormous scene file. Hidden except
## mid-drag; see _rebuild_wall_ghost(). Called from Main._ready(), once Main's
## own @onready nodes exist.
func setup() -> void:
	_wall_drag_label = Label.new()
	_wall_drag_label.visible = false
	_wall_drag_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wall_drag_label.add_theme_font_size_override("font_size", 20)
	_wall_drag_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_wall_drag_label.add_theme_constant_override("shadow_offset_x", 1)
	_wall_drag_label.add_theme_constant_override("shadow_offset_y", 1)
	_wall_drag_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_wall_drag_label.position = Vector2(-100.0, 12.0)
	_wall_drag_label.custom_minimum_size = Vector2(200.0, 0.0)
	_wall_drag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main.ui_root.add_child(_wall_drag_label)

## Ticked by Main._process.
func update() -> void:
	if placing_type == null:
		return
	if placing_type.is_wall:
		_update_wall_drag()
	elif placing_type.is_gate_tool:
		_update_gate_ghost()
	else:
		_update_placement_ghost()

func is_placing() -> bool:
	return placing_type != null

## Build orders answer in a builder's voice, not the selection's: the builders
## are resolved separately (_pending_builder_paths) and a placement can be
## confirmed with the selection already changed. Falls back to the selection
## when no builder path resolves.
func _builder_speaker() -> Unit:
	var builders: Array[Unit] = []
	for path in _pending_builder_paths:
		var unit := get_node_or_null(path) as Unit
		if unit != null:
			builders.append(unit)
	if builders.is_empty():
		return main.feedback.command_speaker()
	return builders[randi() % builders.size()]

## Idle construction menu and a unit's Build submenu both funnel through here:
## while the submenu is open this also captures which selected units (that
## can build) should be sent to build whatever gets placed.
## Holding Shift while picking the NEXT building (even a different type) keeps
## the same builders queued up from a chain already in progress — see
## _confirm_placement, which is what actually starts/continues _build_queue_active.
func on_construction_button_pressed(building_type: BuildingType) -> void:
	if not (_build_queue_active and Input.is_key_pressed(KEY_SHIFT)):
		_pending_builder_paths.clear()
		_build_queue_active = false
		if main.hud.showing_build_submenu:
			for unit in main.selected_units:
				if is_instance_valid(unit) and unit.can_build:
					_pending_builder_paths.append(unit.get_path())
	_start_placement(building_type)
	main.play_command_sound()

## --- Building placement ---

func _start_placement(building_type: BuildingType) -> void:
	_cancel_placement()
	placing_type = building_type
	## Only needed to close an open building panel — skipped when a unit's
	## Build submenu started this placement, since select_building(null)
	## would otherwise refresh the action panel back out of that submenu
	## (via refresh_command_panel()) while the ghost is still following the mouse.
	if main.selected_building != null:
		main.select_building(null)
	if building_type.is_wall or building_type.is_gate_tool:
		## Both use their own snap/rebuild logic each frame instead of a
		## single mouse-following ghost — see _update_wall_drag/_update_gate_ghost.
		return
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
			## Grass (grass_wind_material.tres) alpha-blends at render_priority 0
			## too, and a MultiMeshInstance3D sorts as one draw call against this
			## ghost's distance rather than per-blade — so without outranking it
			## here, whichever one's centroid happens to read as "farther" can
			## draw last and blot out the other. Bumping priority above 0 always
			## wins the tie, regardless of distance.
			ghost_material.render_priority = 1
			mesh_instance.set_surface_override_material(i, ghost_material)
			_ghost_surfaces.append({"material": ghost_material, "base_color": base_color})
	for child in node.get_children():
		_collect_ghost_surfaces(child)

func _set_ghost_valid(valid: bool) -> void:
	var tint: Color = VALID_GHOST_COLOR if valid else INVALID_GHOST_COLOR
	for entry in _ghost_surfaces:
		var material: StandardMaterial3D = entry["material"]
		var base_color: Color = entry["base_color"]
		## Multiplying straight through (base * tint) crushes to near-black on
		## a dark-shaded source model (e.g. base_basic_shaded.glb), making
		## valid/invalid unreadable — blending toward the tint instead keeps
		## some of the original hue while still guaranteeing the red/green
		## signal reads clearly regardless of how dark the source material is.
		var blended: Color = base_color.lerp(tint, 0.75)
		material.albedo_color = Color(blended.r, blended.g, blended.b, tint.a)

func _update_placement_ghost() -> void:
	if placing_type.requires_deposit:
		_update_deposit_snap_ghost()
		return

	var mouse_pos := get_viewport().get_mouse_position()
	var result := main.raycast(mouse_pos)
	if result.is_empty():
		placement_ghost.visible = false
		placement_valid = false
		return
	placement_ghost.visible = true
	placement_ghost.global_position = result.position

	## _is_placement_valid's overlap check alone only ever compared against
	## other buildings/resources, never terrain, so a ghost could sit embedded
	## in a slope/cliff (e.g. TileMapLayer3D terrain) and still read as valid.
	var on_flat_ground: bool = _footprint_is_flat(result.position, placing_type.footprint_radius)
	placement_valid = on_flat_ground \
			and _is_placement_valid(result.position, placing_type.footprint_radius) \
			and _has_nearby_host(result.position, placing_type, main.my_peer_id())
	_set_ghost_valid(placement_valid)

## Samples the footprint's center plus FOOTPRINT_SAMPLE_COUNT points around
## its edge (straight-down raycasts, not just the single cursor ray) so a
## building can't have a flat center while an edge overhangs a nearby
## slope/cliff or straddles a level change undetected.
func _footprint_is_flat(center: Vector3, radius: float) -> bool:
	var space_state := get_world_3d().direct_space_state
	for i in FOOTPRINT_SAMPLE_COUNT + 1:
		var offset := Vector3.ZERO
		if i > 0:
			var angle := TAU * (i - 1) / float(FOOTPRINT_SAMPLE_COUNT)
			offset = Vector3(cos(angle), 0.0, sin(angle)) * radius
		var sample_xz := center + offset
		var query := PhysicsRayQueryParameters3D.create(
			sample_xz + Vector3(0.0, 5.0, 0.0), sample_xz - Vector3(0.0, 5.0, 0.0)
		)
		var result := space_state.intersect_ray(query)
		if result.is_empty():
			return false
		if result.normal.y < MAX_BUILD_SLOPE_NORMAL_Y:
			return false
		if absf(result.position.y - center.y) > MAX_FOOTPRINT_HEIGHT_VARIANCE:
			return false
	return true

## Snap-to-target variant: the ghost only ever shows at an existing,
## unclaimed instance of placing_type.deposit_scene under the mouse, never
## following the mouse freely.
func _update_deposit_snap_ghost() -> void:
	var mouse_pos := get_viewport().get_mouse_position()
	var result := main.raycast(mouse_pos)
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

func _matches_any_scene(node: Node, scenes: Array[PackedScene]) -> bool:
	for scene in scenes:
		if _matches_scene(node, scene):
			return true
	return false

## The Farm/Mill rule: a building_type with requires_nearby_host may only go
## down within host_radius of a finished, same-owner instance of its
## host_scene. Every other building type passes straight through. Checked on
## both sides — locally for the ghost's red/green, and again host-side in
## _rpc_request_build so a client can't place a Farm out in open country.
func _has_nearby_host(pos: Vector3, building_type: BuildingType, peer_id: int) -> bool:
	if not building_type.requires_nearby_host:
		return true
	for node in get_tree().get_nodes_in_group("buildings"):
		var building := node as ProductionBuilding
		if building == null or building.owner_peer_id != peer_id or building.is_under_construction:
			continue
		if not _matches_scene(building, building_type.host_scene):
			continue
		if building.global_position.distance_to(pos) <= building_type.host_radius:
			return true
	return false

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

func handle_placement_input(event: InputEvent) -> void:
	if placing_type.is_wall:
		_handle_wall_drag_input(event)
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_confirm_placement()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_placement()
			_pending_builder_paths.clear()
			_build_queue_active = false
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_cancel_placement()
		_pending_builder_paths.clear()
		_build_queue_active = false

func _confirm_placement() -> void:
	if placing_type.is_gate_tool:
		_confirm_gate_placement()
		return
	## Staying armed (rather than dropping the ghost) is deliberate: a click
	## on unbuildable ground is nearly always a misjudged spot, not a change
	## of mind, so the tool stays live and the player just clicks again. Same
	## reasoning as the can't-afford branch below.
	if not placement_valid:
		main.play_placement_blocked_sound()
		return
	## Checked here (rather than only relying on the host's own can_afford
	## guard in _rpc_request_build) so an unaffordable click gets immediate
	## feedback instead of just silently doing nothing once the RPC reaches
	## the host and gets refused there. Placement mode is left running so the
	## player can keep waiting for resources and try the same spot again.
	if not main.hud.can_afford_locally(placing_type.get_costs()):
		main.hud.flash_missing_resources(placing_type.get_costs())
		return
	var my_building_types: Array[BuildingType] = main.my_faction().building_types
	var type_index: int = my_building_types.find(placing_type)
	var target_path := _placement_target.get_path() if _placement_target else NodePath()
	var placed_type := placing_type
	var shift_held := Input.is_key_pressed(KEY_SHIFT)
	var build_position := placement_ghost.global_position
	_rpc_request_build.rpc_id(1, type_index, build_position, target_path, _pending_builder_paths, shift_held)
	AudioUtils.play_random(main.command_audio_player, main.on_building_placed_sound_effects)
	main.feedback.spawn_command_popup("build", build_position, _builder_speaker())

	## Holding Shift keeps the same builders and stays in placement mode
	## (re-arming the same building type) so the next click queues another
	## one instead of ending the session — see _on_unit_order_completed on
	## the host side for how builders actually work through the chain.
	if shift_held:
		_build_queue_active = true
		for path in _pending_builder_paths:
			var builder := get_node_or_null(path) as Unit
			if builder:
				main.feedback.add_path_marker(builder, placement_ghost.global_position)
		_start_placement(placed_type)
		return

	for path in _pending_builder_paths:
		var builder := get_node_or_null(path) as Unit
		if builder:
			main.feedback.clear_path_markers(builder)
	_cancel_placement()
	_pending_builder_paths.clear()
	_build_queue_active = false
	if main.hud.showing_build_submenu:
		main.hud.close_build_submenu()

@rpc("any_peer", "call_local", "reliable")
func _rpc_request_build(type_index: int, world_pos: Vector3, target_path: NodePath, builder_paths: Array[NodePath], append: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = main.my_peer_id()

	## Resolved against the SENDER's own faction, never a shared/global list —
	## the same type_index means a different building depending on faction,
	## so trusting anything else here would let a client reference another
	## faction's roster.
	if not main.faction_by_peer.has(sender_id):
		return
	var sender_building_types: Array[BuildingType] = main.faction_by_peer[sender_id].building_types
	if type_index < 0 or type_index >= sender_building_types.size():
		return
	var building_type: BuildingType = sender_building_types[type_index]
	var costs := building_type.get_costs()
	if not ResourceStockpile.can_afford(sender_id, costs):
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
	elif not _footprint_is_flat(world_pos, building_type.footprint_radius) \
			or not _is_placement_valid(world_pos, building_type.footprint_radius) \
			or not _has_nearby_host(world_pos, building_type, sender_id):
		return

	ResourceStockpile.spend(sender_id, costs)
	if deposit:
		deposit.is_claimed = true

	var spawn_data: Dictionary = {
		"scene_path": building_type.scene.resource_path,
		"peer_id": sender_id,
		"position": build_pos,
		"tint": main.get_team_tint(sender_id),
	}
	if deposit:
		spawn_data["deposit_path"] = deposit.get_path()
	var spawned: Node = main.building_spawner.spawn(spawn_data)
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

		_dispatch_builders_to(building, builder_paths, sender_id, append)

## Sends whichever villager(s) opened the build menu to go build what they
## just placed, instead of leaving them standing idle next to it. Shared by
## the normal/wall/gate build RPCs. Shift-chained placements queue this after
## the builder's current order instead — see _confirm_placement/
## _on_unit_order_completed. Same "only actually queue if there's something to
## finish first" logic as _rpc_issue_command — an idle builder with nothing in
## flight would never have anything trigger order_completed to dispatch a
## queued order.
func _dispatch_builders_to(building: ProductionBuilding, builder_paths: Array[NodePath], sender_id: int, append: bool) -> void:
	for path in builder_paths:
		var builder := get_node_or_null(path) as Unit
		if builder == null or builder.owner_peer_id != sender_id:
			continue
		var builder_is_busy := builder.status_command != Unit.Command.NONE or not builder.order_queue.is_empty()
		if append and builder_is_busy:
			builder.queue_order(building.get_path(), building.global_position, false)
		else:
			builder.clear_order_queue()
			builder.command_build(building)

func _cancel_placement() -> void:
	if placement_ghost:
		placement_ghost.queue_free()
		placement_ghost = null
	_ghost_surfaces.clear()
	placing_type = null
	_placement_target = null
	_cancel_wall_drag()
	_gate_target = null

## --- Wall drag placement ---
## Click-drag a run of wall segments (Age of Empires IV-style): the path
## follows the actual cursor movement rather than snapping to a straight
## line, sampled every wall_segment_length along the way; a corner piece is
## auto-inserted wherever the path bends past WALL_CORNER_ANGLE_THRESHOLD.
## _wall_compute_pieces() is the single source of truth for what a drag would
## build — both the live ghost and the final RPC call it fresh off the same
## _wall_drag_points, so what's previewed is always exactly what gets built
## (no silent per-piece drop on confirm, unlike AoE4's own wall tool).

func _handle_wall_drag_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_wall_drag()
		elif _wall_dragging:
			_confirm_wall_placement()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_cancel_placement()
		_pending_builder_paths.clear()
		_build_queue_active = false
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_cancel_placement()
		_pending_builder_paths.clear()
		_build_queue_active = false

func _begin_wall_drag() -> void:
	var mouse_pos := get_viewport().get_mouse_position()
	var result := main.raycast(mouse_pos)
	if result.is_empty():
		return
	_wall_dragging = true
	_wall_drag_points = [result.position]
	_rebuild_wall_ghost()

func _update_wall_drag() -> void:
	if not _wall_dragging:
		return
	var mouse_pos := get_viewport().get_mouse_position()
	var result := main.raycast(mouse_pos)
	if result.is_empty():
		return
	## Backtracking over already-placed pieces takes priority over extending
	## forward — a player correcting a mistake by dragging back over the wall
	## should retract it, not simultaneously grow a new branch from wherever
	## the cursor happens to be.
	if _wall_try_backtrack(result.position):
		_rebuild_wall_ghost()
		return
	if _wall_extend_path_to(result.position):
		_rebuild_wall_ghost()

## How close the cursor needs to get to an already-placed piece (measured to
## the segment itself, not just its endpoints) to count as "hovering back
## over it" and retract the path there. Generous enough to be easy to land
## on, tight enough not to trigger from a normal straight forward drag.
const WALL_UNDO_THRESHOLD: float = WALL_SEGMENT_FOOTPRINT_RADIUS + 0.3

## Retracts _wall_drag_points back to just past the piece the cursor is now
## hovering, so moving the mouse back over a mistake undoes it (and every
## piece placed after it) in real time instead of requiring a full restart.
## Never considers the live frontier segment (the one currently being drawn
## toward the cursor) a backtrack target, and only fires when the cursor sits
## closer to that old piece than to the current end of the drag — otherwise a
## plain straight drag would trip it constantly, since the cursor is always
## incidentally near the extended line of earlier segments too.
func _wall_try_backtrack(target: Vector3) -> bool:
	if _wall_drag_points.size() < 3:
		return false
	var flat_target := Vector3(target.x, 0.0, target.z)
	var best_i := -1
	var best_dist := INF
	for i in _wall_drag_points.size() - 2:
		var flat_a := _wall_drag_points[i]
		flat_a.y = 0.0
		var flat_b := _wall_drag_points[i + 1]
		flat_b.y = 0.0
		var dist := _distance_point_to_segment(flat_target, flat_a, flat_b)
		if dist < best_dist:
			best_dist = dist
			best_i = i
	if best_i == -1 or best_dist > WALL_UNDO_THRESHOLD:
		return false
	## Compared against the frontier SEGMENT (not just its far endpoint) —
	## comparing to the endpoint alone would make the cursor read as "closer
	## to the old piece" for the whole near half of the segment currently
	## being drawn, retracting it during perfectly ordinary forward dragging.
	var frontier_a: Vector3 = _wall_drag_points[-2]
	frontier_a.y = 0.0
	var frontier_b: Vector3 = _wall_drag_points[-1]
	frontier_b.y = 0.0
	var frontier_dist := _distance_point_to_segment(flat_target, frontier_a, frontier_b)
	if frontier_dist <= best_dist:
		return false
	_wall_drag_points = _wall_drag_points.slice(0, best_i + 1)
	return true

func _distance_point_to_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 0.0001:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)

## Walks from the last committed point toward target in fixed
## wall_segment_length steps (re-sampling ground height at each new point),
## rather than just drawing one straight line from drag-start to the current
## mouse position — that's what lets the wall follow a curved drag instead of
## always being a single straight chord. Returns whether any point was added.
func _wall_extend_path_to(target: Vector3) -> bool:
	if _wall_drag_points.is_empty() or _wall_drag_points.size() > WALL_MAX_SEGMENTS:
		return false
	var seg_len: float = placing_type.wall_segment_length
	var added := false
	var last: Vector3 = _wall_drag_points[-1]
	var to_target := target - last
	to_target.y = 0.0
	while to_target.length() >= seg_len and _wall_drag_points.size() <= WALL_MAX_SEGMENTS:
		var dir := to_target.normalized()
		var next_point := last + dir * seg_len
		## A straight step that would clip a tree/resource gets bent sideways
		## just enough to clear it instead of just landing on an invalid,
		## red-tinted piece — see _wall_find_blocking_obstacle/_wall_deflect_around.
		var obstacle := _wall_find_blocking_obstacle(last, next_point)
		if obstacle != null:
			next_point = _wall_deflect_around(last, next_point, dir, obstacle)
		next_point.y = _sample_ground_y(next_point, next_point.y)
		_wall_drag_points.append(next_point)
		last = next_point
		to_target = target - last
		to_target.y = 0.0
		added = true
	return added

## Shape-queries the corridor a straight step from a to b would sweep through
## (segment-length long, wall-width wide) and returns the nearest Gatherable
## overlapping it, or null if the step is clear.
func _wall_find_blocking_obstacle(a: Vector3, b: Vector3) -> Gatherable:
	var dir := b - a
	dir.y = 0.0
	if dir.length() < 0.001:
		return null
	dir = dir.normalized()
	var mid := (a + b) * 0.5
	var shape := BoxShape3D.new()
	shape.size = Vector3(a.distance_to(b), 2.0, WALL_SEGMENT_FOOTPRINT_RADIUS * 2.0 + 1.0)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(dir, Vector3.UP, dir.cross(Vector3.UP)), mid)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var closest: Gatherable = null
	var closest_dist := INF
	var space_state := get_world_3d().direct_space_state
	for result in space_state.intersect_shape(query, 8):
		if result.collider is Gatherable:
			var dist: float = mid.distance_to(result.collider.global_position)
			if dist < closest_dist:
				closest_dist = dist
				closest = result.collider
	return closest

## How far a resource node's own footprint extends, read off its
## NavigationObstacle3D the same way ProductionBuilding.get_footprint_radius()
## does — falls back to a generic clearance if a given Gatherable has none.
func _obstacle_radius(node: Node3D) -> float:
	var obstacle := node.get_node_or_null("NavigationObstacle3D") as NavigationObstacle3D
	return obstacle.radius if obstacle else 1.2

## Pushes next_point sideways, away from whichever side of the a->next_point
## line the obstacle sits on, by enough to clear its footprint plus the
## wall's own, then re-projects back onto the segment_length-from-`a` circle
## so the piece a player actually sees rejected/accepted is the one this
## directly targets. Not a real pathfinder — a long straight drag through a
## cluster of trees can still take a couple of separately-deflected pieces to
## fully clear (each step only reacts to what's directly in front of it) —
## but every individual step it produces is provably clear of what it was
## deflected for, unlike a pivot-around-`a` approach (which under-corrects
## for any obstacle not near the far end of the step: rotating a line around
## a fixed point can't move a point close to that pivot very far no matter
## how hard you rotate, so it would often still leave the piece invalid).
func _wall_deflect_around(a: Vector3, next_point: Vector3, dir: Vector3, obstacle: Gatherable) -> Vector3:
	var perp := dir.cross(Vector3.UP).normalized()
	var mid := (a + next_point) * 0.5
	var to_obstacle := obstacle.global_position - mid
	to_obstacle.y = 0.0
	var lateral: float = perp.dot(to_obstacle)
	var clearance: float = _obstacle_radius(obstacle) + WALL_SEGMENT_FOOTPRINT_RADIUS + 0.4
	var needed: float = clearance - absf(lateral)
	if needed <= 0.0:
		return next_point
	var side := signf(lateral) if lateral != 0.0 else 1.0
	## Only next_point moves (a is already committed), so the midpoint only
	## moves by half of whatever next_point shifts by — shifting next_point by
	## 2x what the midpoint needs is what actually gets the midpoint clear.
	return next_point - perp * side * (needed * 2.0)

func _sample_ground_y(pos: Vector3, fallback_y: float) -> float:
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(pos + Vector3(0.0, 5.0, 0.0), pos - Vector3(0.0, 5.0, 0.0))
	var result := space_state.intersect_ray(query)
	return result.position.y if not result.is_empty() else fallback_y

## Turns _wall_drag_points into the actual list of pieces a confirm would
## build: one "segment" per consecutive pair of points, plus a "corner" at
## any interior point where the path bends more than WALL_CORNER_ANGLE_THRESHOLD.
## Deterministic and side-effect-free (only reads _wall_drag_points/placing_type
## and runs placement-validity queries) so the ghost and the confirm RPC can
## both call it and always agree.
func _wall_compute_pieces() -> Array[Dictionary]:
	var pieces: Array[Dictionary] = []
	var pts := _wall_drag_points
	## Segment midpoints placed so far, checked below against every new
	## segment — legitimate end-to-end neighbors sit wall_segment_length apart
	## (comfortably more than twice the footprint radius), so this only ever
	## trips when the drag genuinely doubles back over ground it already
	## covered (a hairpin or a literal backtrack), which _is_placement_valid
	## alone can't catch since stripped ghosts carry no collision shape.
	var segment_positions: Array[Vector3] = []
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var dir := b - a
		dir.y = 0.0
		if dir.length() < 0.001:
			continue
		dir = dir.normalized()
		var mid := (a + b) * 0.5
		var valid: bool = _footprint_is_flat(mid, WALL_SEGMENT_FOOTPRINT_RADIUS) \
				and _is_placement_valid(mid, WALL_SEGMENT_FOOTPRINT_RADIUS) \
				and not _wall_overlaps_own_run(segment_positions, mid, WALL_SEGMENT_FOOTPRINT_RADIUS)
		segment_positions.append(mid)
		pieces.append({"kind": "segment", "position": mid, "direction": dir, "valid": valid})

		if i > 0 and placing_type.wall_corner_scene:
			var prev_dir: Vector3 = pts[i] - pts[i - 1]
			prev_dir.y = 0.0
			if prev_dir.length() > 0.001:
				prev_dir = prev_dir.normalized()
				if prev_dir.angle_to(dir) > WALL_CORNER_ANGLE_THRESHOLD:
					var bisector := prev_dir + dir
					bisector = bisector.normalized() if bisector.length() > 0.001 else dir
					var corner_valid: bool = _footprint_is_flat(pts[i], WALL_CORNER_FOOTPRINT_RADIUS) \
							and _is_placement_valid(pts[i], WALL_CORNER_FOOTPRINT_RADIUS)
					pieces.append({"kind": "corner", "position": pts[i], "direction": bisector, "valid": corner_valid})
	return pieces

func _wall_overlaps_own_run(existing_midpoints: Array[Vector3], mid: Vector3, radius: float) -> bool:
	for other in existing_midpoints:
		if other.distance_to(mid) < radius * 2.0:
			return true
	return false

func _wall_all_pieces_valid(pieces: Array[Dictionary]) -> bool:
	for piece in pieces:
		if not piece["valid"]:
			return false
	return true

## Sums per-piece costs into one merged ResourceCost per resource type —
## ResourceStockpile.can_afford()/spend() check each array entry independently
## against the live balance, so N separate "8 wood" entries would each pass
## the same affordability check without ever accounting for each other.
func _wall_total_cost(pieces: Array[Dictionary]) -> Array[ResourceCost]:
	var totals: Dictionary = {}
	for piece in pieces:
		var unit_costs: Array[ResourceCost] = placing_type.get_costs() if piece["kind"] == "segment" else placing_type.get_corner_costs()
		for cost in unit_costs:
			totals[cost.resource_type] = totals.get(cost.resource_type, 0) + cost.amount
	return _totals_to_costs(totals)

func _totals_to_costs(totals: Dictionary) -> Array[ResourceCost]:
	var result: Array[ResourceCost] = []
	for resource_type in totals:
		var cost := ResourceCost.new()
		cost.resource_type = resource_type
		cost.amount = totals[resource_type]
		result.append(cost)
	return result

func _rebuild_wall_ghost() -> void:
	for ghost in _wall_ghosts:
		if is_instance_valid(ghost):
			ghost.queue_free()
	_wall_ghosts.clear()
	var pieces := _wall_compute_pieces()
	for piece in pieces:
		var scene: PackedScene = placing_type.scene if piece["kind"] == "segment" else placing_type.wall_corner_scene
		if scene == null:
			continue
		_wall_ghosts.append(_build_wall_piece_ghost(scene, piece["position"], piece["direction"], piece["valid"]))
	_update_wall_drag_label(pieces)

## Segment/corner counts and a live running total, refreshed every time the
## drag grows — this is the gap AoE4 itself leaves (you only learn the true
## cost after releasing the drag); showing it live is a deliberate improvement.
func _update_wall_drag_label(pieces: Array[Dictionary]) -> void:
	if pieces.is_empty():
		_wall_drag_label.visible = false
		return
	var segment_count := 0
	var corner_count := 0
	for piece in pieces:
		if piece["kind"] == "segment":
			segment_count += 1
		else:
			corner_count += 1
	var cost_text := main.hud.format_costs(_wall_total_cost(pieces))
	var piece_text := "%d wall%s" % [segment_count, "" if segment_count == 1 else "s"]
	if corner_count > 0:
		piece_text += " + %d corner%s" % [corner_count, "" if corner_count == 1 else "s"]
	_wall_drag_label.text = "%s — %s" % [piece_text, cost_text]
	_wall_drag_label.modulate = Color.WHITE if _wall_all_pieces_valid(pieces) else Color(1.0, 0.55, 0.5)
	_wall_drag_label.visible = true

func _build_wall_piece_ghost(scene: PackedScene, pos: Vector3, dir: Vector3, valid: bool) -> Node3D:
	var ghost: Node3D = scene.instantiate()
	ghost.set_script(null)
	_strip_ghost_children(ghost)
	var surfaces: Array = []
	_collect_ghost_surfaces_into(ghost, surfaces)
	ghost.set_meta(&"ghost_surfaces", surfaces)
	add_child(ghost)
	ghost.global_position = pos
	ghost.global_basis = Basis(dir, Vector3.UP, dir.cross(Vector3.UP))
	_tint_wall_ghost(ghost, valid)
	return ghost

## Same per-surface translucent-material approach as _collect_ghost_surfaces(),
## but writing into a caller-supplied array instead of the single shared
## _ghost_surfaces list — a wall drag has many ghosts on screen at once, each
## needing its own independent valid/invalid tint, unlike every other
## placement type's single ghost.
func _collect_ghost_surfaces_into(node: Node, out: Array) -> void:
	if node is MeshInstance3D:
		var mesh_instance: MeshInstance3D = node
		var surface_count: int = mesh_instance.mesh.get_surface_count() if mesh_instance.mesh else 0
		for i in surface_count:
			var base: Material = mesh_instance.get_active_material(i)
			var base_color: Color = base.albedo_color if base is StandardMaterial3D else Color.WHITE
			var ghost_material := StandardMaterial3D.new()
			ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			ghost_material.render_priority = 1
			mesh_instance.set_surface_override_material(i, ghost_material)
			out.append({"material": ghost_material, "base_color": base_color})
	for child in node.get_children():
		_collect_ghost_surfaces_into(child, out)

func _tint_wall_ghost(ghost: Node3D, valid: bool) -> void:
	var tint: Color = VALID_GHOST_COLOR if valid else INVALID_GHOST_COLOR
	for entry in ghost.get_meta(&"ghost_surfaces", []):
		var material: StandardMaterial3D = entry["material"]
		var base_color: Color = entry["base_color"]
		var blended: Color = base_color.lerp(tint, 0.75)
		material.albedo_color = Color(blended.r, blended.g, blended.b, tint.a)

func _confirm_wall_placement() -> void:
	_wall_dragging = false
	var pieces := _wall_compute_pieces()
	if pieces.is_empty() or not _wall_all_pieces_valid(pieces):
		main.play_placement_blocked_sound()
		_cancel_wall_drag()
		return
	var costs := _wall_total_cost(pieces)
	if not main.hud.can_afford_locally(costs):
		main.hud.flash_missing_resources(costs)
		return

	var my_building_types: Array[BuildingType] = main.my_faction().building_types
	var type_index: int = my_building_types.find(placing_type)
	var positions: Array[Vector3] = []
	var directions: Array[Vector3] = []
	var kinds: Array[String] = []
	for piece in pieces:
		positions.append(piece["position"])
		directions.append(piece["direction"])
		kinds.append(piece["kind"])
	_rpc_request_build_wall.rpc_id(1, type_index, positions, directions, kinds, _pending_builder_paths)
	AudioUtils.play_random(main.command_audio_player, main.on_building_placed_sound_effects)
	## Last piece rather than the first: that is where the drag ended, so it is
	## where the player is actually looking when the line pops.
	main.feedback.spawn_command_popup("build", positions[positions.size() - 1], _builder_speaker())

	for path in _pending_builder_paths:
		var builder := get_node_or_null(path) as Unit
		if builder:
			main.feedback.clear_path_markers(builder)
	_cancel_wall_drag()
	_pending_builder_paths.clear()
	_build_queue_active = false
	if main.hud.showing_build_submenu:
		main.hud.close_build_submenu()

func _cancel_wall_drag() -> void:
	_wall_dragging = false
	_wall_drag_points.clear()
	for ghost in _wall_ghosts:
		if is_instance_valid(ghost):
			ghost.queue_free()
	_wall_ghosts.clear()
	if _wall_drag_label:
		_wall_drag_label.visible = false

@rpc("any_peer", "call_local", "reliable")
func _rpc_request_build_wall(type_index: int, positions: Array[Vector3], directions: Array[Vector3], kinds: Array[String], builder_paths: Array[NodePath]) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = main.my_peer_id()
	if not main.faction_by_peer.has(sender_id):
		return
	var sender_building_types: Array[BuildingType] = main.faction_by_peer[sender_id].building_types
	if type_index < 0 or type_index >= sender_building_types.size():
		return
	var building_type: BuildingType = sender_building_types[type_index]
	if not building_type.is_wall:
		return
	var count: int = positions.size()
	if count == 0 or count != directions.size() or count != kinds.size() or count > WALL_MAX_SEGMENTS * 2:
		return

	## Re-validated piece-by-piece against the host's own world state rather
	## than trusting the client's ghost — the drag may be stale (something
	## else got built in that spot meanwhile) or the client tampered with it.
	## Any single invalid piece rejects the whole run instead of silently
	## building the rest, so what the player saw as "valid" is exactly what
	## either does or doesn't appear.
	var totals: Dictionary = {}
	var sanitized_dirs: Array[Vector3] = []
	var segment_positions: Array[Vector3] = []
	for i in count:
		var kind: String = kinds[i]
		if kind != "segment" and kind != "corner":
			return
		if kind == "corner" and building_type.wall_corner_scene == null:
			return
		var radius: float = WALL_SEGMENT_FOOTPRINT_RADIUS if kind == "segment" else WALL_CORNER_FOOTPRINT_RADIUS
		if not _footprint_is_flat(positions[i], radius) or not _is_placement_valid(positions[i], radius):
			return
		## A client's ghost only ever sends a normalized, horizontal direction
		## (see _wall_compute_pieces) — never trust that blindly, since this
		## gets written straight into a replicated Basis/rotation below and a
		## degenerate or non-horizontal vector there can produce NaN that
		## propagates to every peer.
		var dir: Vector3 = directions[i]
		dir.y = 0.0
		if dir.length() < 0.01:
			return
		dir = dir.normalized()
		sanitized_dirs.append(dir)
		if kind == "segment":
			if _wall_overlaps_own_run(segment_positions, positions[i], WALL_SEGMENT_FOOTPRINT_RADIUS):
				return
			segment_positions.append(positions[i])
		var unit_costs: Array[ResourceCost] = building_type.get_costs() if kind == "segment" else building_type.get_corner_costs()
		for cost in unit_costs:
			totals[cost.resource_type] = totals.get(cost.resource_type, 0) + cost.amount

	var merged_costs := _totals_to_costs(totals)
	if not ResourceStockpile.can_afford(sender_id, merged_costs):
		return
	ResourceStockpile.spend(sender_id, merged_costs)

	var spawned_buildings: Array[ProductionBuilding] = []
	for i in count:
		var kind: String = kinds[i]
		var scene: PackedScene = building_type.scene if kind == "segment" else building_type.wall_corner_scene
		var duration: float = building_type.construction_time if kind == "segment" else building_type.construction_time * 0.5
		var dir: Vector3 = sanitized_dirs[i]
		var rot_basis := Basis(dir, Vector3.UP, dir.cross(Vector3.UP))
		var spawn_data: Dictionary = {
			"scene_path": scene.resource_path,
			"peer_id": sender_id,
			"position": positions[i],
			"rotation": rot_basis.get_euler(),
			"tint": main.get_team_tint(sender_id),
		}
		var spawned: Node = main.building_spawner.spawn(spawn_data)
		if spawned is ProductionBuilding:
			var building: ProductionBuilding = spawned
			building.begin_construction(duration)
			spawned_buildings.append(building)

	_dispatch_builders_across(spawned_buildings, builder_paths, sender_id)

## Distributes wall pieces round-robin across however many builders were
## selected, so a long drag with e.g. 3 villagers queued has each of them
## start on a different segment and then work down their own third of the
## run, instead of all piling onto the first piece one at a time.
func _dispatch_builders_across(buildings: Array[ProductionBuilding], builder_paths: Array[NodePath], sender_id: int) -> void:
	var builders: Array[Unit] = []
	for path in builder_paths:
		var builder := get_node_or_null(path) as Unit
		if builder and builder.owner_peer_id == sender_id:
			builders.append(builder)
	if builders.is_empty() or buildings.is_empty():
		return
	for i in buildings.size():
		var builder: Unit = builders[i % builders.size()]
		var building: ProductionBuilding = buildings[i]
		if i < builders.size():
			builder.clear_order_queue()
			builder.command_build(building)
		else:
			builder.queue_order(building.get_path(), building.global_position, false)

## --- Gate tool ---
## A second construction-menu entry (is_gate_tool) rather than a drag
## modifier: click an already-placed (fully built) wall segment/corner
## matching gate_target_scenes to swap it for wall_gate_scene. Reuses the single-ghost
## machinery (placement_ghost/_ghost_surfaces/_set_ghost_valid) since, unlike
## the wall drag, this only ever shows one ghost at a time.

func _update_gate_ghost() -> void:
	var mouse_pos := get_viewport().get_mouse_position()
	var result := main.raycast(mouse_pos)
	_gate_target = _find_valid_gate_target(result.get("collider"))

	if _gate_target == null:
		if placement_ghost:
			placement_ghost.visible = false
		placement_valid = false
		return

	if placement_ghost == null:
		placement_ghost = _build_ghost(placing_type.scene)
		add_child(placement_ghost)
	placement_ghost.visible = true
	placement_ghost.global_transform = _gate_target.global_transform
	placement_valid = true
	_set_ghost_valid(true)

## Only a fully-built segment can become a gate — a segment still under
## construction has (possibly several) builders actively referencing it as
## their build_target, and there's no clean way to hand that work off to a
## brand new node mid-build, so it's simplest and safest to just require the
## wall to finish first, same as AoE4's normal (non-blueprint-conversion) flow.
func _find_valid_gate_target(collider: Object) -> ProductionBuilding:
	if collider == null or not (collider is ProductionBuilding):
		return null
	var target: ProductionBuilding = collider
	if target.is_destroyed or target.is_under_construction or target.owner_peer_id != main.my_peer_id():
		return null
	if not _matches_any_scene(target, placing_type.gate_target_scenes):
		return null
	return target

func _confirm_gate_placement() -> void:
	if _gate_target == null or not is_instance_valid(_gate_target):
		main.play_placement_blocked_sound()
		return
	if not main.hud.can_afford_locally(placing_type.get_costs()):
		main.hud.flash_missing_resources(placing_type.get_costs())
		return

	var my_building_types: Array[BuildingType] = main.my_faction().building_types
	var type_index: int = my_building_types.find(placing_type)
	var target_path := _gate_target.get_path()
	var gate_position := _gate_target.global_position
	_rpc_request_build_gate.rpc_id(1, type_index, target_path, _pending_builder_paths)
	AudioUtils.play_random(main.command_audio_player, main.on_building_placed_sound_effects)
	main.feedback.spawn_command_popup("build", gate_position, _builder_speaker())

	for path in _pending_builder_paths:
		var builder := get_node_or_null(path) as Unit
		if builder:
			main.feedback.clear_path_markers(builder)
	_cancel_placement()
	_pending_builder_paths.clear()
	_build_queue_active = false
	if main.hud.showing_build_submenu:
		main.hud.close_build_submenu()

@rpc("any_peer", "call_local", "reliable")
func _rpc_request_build_gate(type_index: int, target_path: NodePath, builder_paths: Array[NodePath]) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = main.my_peer_id()
	if not main.faction_by_peer.has(sender_id):
		return
	var sender_building_types: Array[BuildingType] = main.faction_by_peer[sender_id].building_types
	if type_index < 0 or type_index >= sender_building_types.size():
		return
	var building_type: BuildingType = sender_building_types[type_index]
	if not building_type.is_gate_tool:
		return
	var target := get_node_or_null(target_path) as ProductionBuilding
	if target == null or target.is_destroyed or target.is_under_construction or target.owner_peer_id != sender_id:
		return
	if not _matches_any_scene(target, building_type.gate_target_scenes):
		return
	var costs := building_type.get_costs()
	if not ResourceStockpile.can_afford(sender_id, costs):
		return
	ResourceStockpile.spend(sender_id, costs)

	var replace_pos: Vector3 = target.global_position
	var replace_rot: Vector3 = target.rotation
	target.queue_free()

	var spawn_data: Dictionary = {
		"scene_path": building_type.scene.resource_path,
		"peer_id": sender_id,
		"position": replace_pos,
		"rotation": replace_rot,
		"tint": main.get_team_tint(sender_id),
	}
	var spawned: Node = main.building_spawner.spawn(spawn_data)
	if spawned is ProductionBuilding:
		var building: ProductionBuilding = spawned
		building.begin_construction(building_type.construction_time)
		_dispatch_builders_to(building, builder_paths, sender_id, false)
