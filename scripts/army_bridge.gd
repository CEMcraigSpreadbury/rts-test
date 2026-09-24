class_name ArmyBridge
extends Node
## Feeds the native ArmySim the world it moves units through, host only:
##   - the movement grid, built once per match from the map's authored navmesh
##     (walkable terrain) and its TerraBrush heightmap;
##   - every solid thing on the map, stamped into that grid by footprint and
##     unstamped when it goes, polled like NavigationBlockers — a building is a
##     handful of cells, never a rebake;
##   - unit registration (Unit.sim_id), with teams mapped to the sim's small
##     team indices.
## Also owns the "cmd navgrid" debug overlay.

## Metres per grid cell. Small enough that the ~1 m gap between a Gate's posts
## stays open once footprints are inflated by a unit's body radius.
const CELL_SIZE: float = 0.5
## Room around the navmesh's bounds so a unit shoved just off the edge still
## has a cell to stand in.
const BOUNDS_MARGIN: float = 2.0
const POLL_INTERVAL: float = 0.25
## A shape whose underside is this far above its body's origin is overhead
## (a Gate's lintel) and leaves the ground under it open.
const OVERHEAD_CLEARANCE: float = 1.0
const OVERLAY_REFRESH: float = 0.5

## The bridge of the match in progress, for units to register through. Null
## on clients and between matches.
static var current: ArmyBridge = null

var sim: ArmySim
var _ready_for_units: bool = false
var _poll_timer: float = 0.0
## Instance id -> true, for everything currently stamped, kept apart so the
## hundreds of resource nodes are only walked when one of them changes.
var _stamped_buildings: Dictionary = {}
var _stamped_gatherables: Dictionary = {}
var _tree_changes_seen: int = -1
## Teams.team_of() result -> sim team index. 0 is neutral, as in Teams.
var _team_index: Dictionary = {Teams.NEUTRAL: 0}
var _overlay: Decal = null
var _overlay_timer: float = 0.0
var _formation_overlay: MeshInstance3D = null
## Sim id -> Unit, for writing the sim's results back.
var _units_by_id: Array[Unit] = []
## Units flagged wedged last tick, so the flag can be cleared on the next.
## Untyped: a unit freed since would fail a typed read.
var _wedged: Array = []
## Units the sim moved last tick, so the ones it did not move this tick can be
## told they are standing still. Untyped for the same reason.
var _moving: Array = []
## Sim formation -> the building it is attacking, so the attack can end when
## the building falls (the sim only follows units).
var _building_targets: Dictionary = {}

func _enter_tree() -> void:
	if multiplayer.is_server():
		current = self

func _exit_tree() -> void:
	if current == self:
		current = null

## Builds the grid. Call before NavigationBlockers swaps the authored navmesh
## for its first rebake: the authored one is terrain only, which is what the
## grid's walkability wants — trees and buildings are stamped separately.
func setup(region: NavigationRegion3D) -> void:
	if not multiplayer.is_server():
		set_process(false)
		return
	var mesh: NavigationMesh = region.navigation_mesh if region != null else null
	if mesh == null or mesh.get_polygon_count() == 0:
		push_warning("ArmyBridge: no navmesh to build the movement grid from")
		set_process(false)
		return
	var start := Time.get_ticks_usec()
	_build_grid(mesh, region.global_transform)
	_load_heightmap(region)
	_restamp()
	sim.finish_grid()
	_ready_for_units = true
	## Units authored into the map (objective guards, a scenario's cast) ran
	## their _ready before Main's, so before there was a grid to join.
	for node in get_tree().get_nodes_in_group(&"units"):
		var unit := node as Unit
		if unit != null and unit.sim_id < 0 and unit.is_inside_tree():
			unit.sim_id = register_unit(unit)
	if PerfStats.enabled:
		PerfStats.record_event(&"grid build", Time.get_ticks_usec() - start)

func _build_grid(mesh: NavigationMesh, region_transform: Transform3D) -> void:
	var vertices := mesh.get_vertices()
	var flat := PackedVector2Array()
	flat.resize(vertices.size())
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for i in vertices.size():
		var world: Vector3 = region_transform * vertices[i]
		var point := Vector2(world.x, world.z)
		flat[i] = point
		low = low.min(point)
		high = high.max(point)
	low -= Vector2(BOUNDS_MARGIN, BOUNDS_MARGIN)
	high += Vector2(BOUNDS_MARGIN, BOUNDS_MARGIN)
	sim.configure_grid(low, high - low, CELL_SIZE)
	var points := PackedVector2Array()
	var starts := PackedInt32Array()
	for p in mesh.get_polygon_count():
		starts.append(points.size())
		for index in mesh.get_polygon(p):
			points.append(flat[index])
	starts.append(points.size())
	sim.mark_walkable_polygons(points, starts)

## TerraBrush maps are a single zone of N x N height samples, one per metre,
## centred on the terrain node (see MapTerrainBuilder.zones_size).
## Looked up under the region rather than through current_scene, which is not
## yet this map while its Main is still readying.
func _load_heightmap(region: NavigationRegion3D) -> void:
	var found: Array[Node] = region.find_children("*", "TerraBrush", true, false)
	var terrain: TerraBrush = found[0] if not found.is_empty() else null
	if terrain == null or terrain.terrainZones == null or terrain.terrainZones.zones.is_empty():
		push_warning("ArmyBridge: no TerraBrush heightmap; the grid has flat ground")
		return
	if terrain.terrainZones.zones.size() > 1:
		push_warning("ArmyBridge: only the first of %d terrain zones is used" % terrain.terrainZones.zones.size())
	var image: Image = terrain.terrainZones.zones[0].heightMapImage
	if image == null:
		return
	var heights_image: Image = image.duplicate()
	if heights_image.get_format() != Image.FORMAT_RF:
		heights_image.convert(Image.FORMAT_RF)
	var n: int = heights_image.get_width()
	var centre := Vector2(terrain.global_position.x, terrain.global_position.z)
	var origin := centre - Vector2.ONE * ((n - 1) * 0.5)
	sim.set_heightmap(heights_image.get_data().to_float32_array(), n, origin, 1.0)

## --- Blockers ---

func _process(delta: float) -> void:
	if _formation_overlay != null:
		_draw_formations()
	if _overlay != null:
		_overlay_timer -= delta
		if _overlay_timer <= 0.0:
			_overlay_timer = OVERLAY_REFRESH
			_refresh_overlay()
	if not _ready_for_units:
		return
	_poll_timer -= delta
	if _poll_timer > 0.0:
		return
	_poll_timer = POLL_INTERVAL
	var start := Time.get_ticks_usec() if PerfStats.enabled else 0
	_restamp()
	if PerfStats.enabled:
		PerfStats.record_event(&"grid poll", Time.get_ticks_usec() - start)

## Stamps what is newly solid and unstamps what no longer is. Buildings are
## checked every poll (few, and they finish, collapse and get demolished);
## the hundreds of resource nodes only when Gatherable.tree_changes says one
## came or went.
func _restamp() -> void:
	_sync_group(&"buildings", _stamped_buildings)
	if Gatherable.tree_changes != _tree_changes_seen:
		_tree_changes_seen = Gatherable.tree_changes
		_sync_group(&"gatherables", _stamped_gatherables)

## Brings the stamps for one group in line with what in it is solid now.
func _sync_group(group: StringName, stamped: Dictionary) -> void:
	var solid: Dictionary = {}
	for node in get_tree().get_nodes_in_group(group):
		_note_solid(node as CollisionObject3D, solid)
	for id in stamped.keys():
		if not solid.has(id):
			sim.clear_blocker(id)
			stamped.erase(id)
	for id in solid:
		if not stamped.has(id):
			sim.set_blocker(id, footprint(solid[id]))
			stamped[id] = true

func _note_solid(body: CollisionObject3D, solid: Dictionary) -> void:
	if body == null or not is_instance_valid(body) or body.is_queued_for_deletion():
		return
	if body.collision_layer & NavigationBlockers.UNIT_COLLISION_MASK == 0:
		return
	## Same rule as NavigationBlockers._is_blocking: a building mid-collapse
	## stops blocking the moment it starts.
	if body.get(&"is_destroyed") == true:
		return
	solid[body.get_instance_id()] = body

## `body`'s solid ground footprint in world XZ, grown by a unit's body radius
## so a cell centre that is open is somewhere a unit fits. Shapes that start
## overhead are left out, which keeps a gateway open under its lintel.
static func footprint(body: CollisionObject3D) -> Array:
	var outlines: Array = []
	var ground_y: float = body.global_position.y
	for owner_id in body.get_shape_owners():
		if body.is_shape_owner_disabled(owner_id):
			continue
		var shape_transform: Transform3D = body.global_transform * body.shape_owner_get_transform(owner_id)
		for i in body.shape_owner_get_shape_count(owner_id):
			var points: PackedVector3Array = NavigationBlockers._shape_points(body.shape_owner_get_shape(owner_id, i))
			if points.is_empty():
				continue
			var flat := PackedVector2Array()
			var min_y: float = INF
			for point in points:
				var placed: Vector3 = shape_transform * point
				flat.append(Vector2(placed.x, placed.z))
				min_y = minf(min_y, placed.y)
			if min_y > ground_y + OVERHEAD_CLEARANCE:
				continue
			var hull: PackedVector2Array = Geometry2D.convex_hull(flat)
			if hull.size() > 1 and hull[0].is_equal_approx(hull[hull.size() - 1]):
				hull.remove_at(hull.size() - 1)
			if hull.size() < 3:
				continue
			for outline in Geometry2D.offset_polygon(hull, NavigationBlockers.UNIT_BODY_RADIUS, Geometry2D.JOIN_MITER):
				outlines.append(outline)
	return outlines

## --- Units ---

## The native half of UnitGrid: living units within `radius` of `pos`, nearest
## first; `not_team` >= 0 leaves out that sim team (see UnitGrid). Null
## while the sim can't answer (no grid yet).
func units_near(pos: Vector3, radius: float, not_team: int = -1) -> Variant:
	if not _ready_for_units:
		return null
	var found: Array[Unit] = []
	for id in sim.get_units_near(Vector2(pos.x, pos.z), radius, not_team):
		var unit: Unit = _units_by_id[id] if id < _units_by_id.size() else null
		if unit != null and unit.status_activity != Unit.Activity.DEAD:
			found.append(unit)
	return found

## Whether any living unit on `peer_id`'s team has `pos` in its sight (see
## CombatUtils.is_visible_to, which adds the buildings).
func team_sees(peer_id: int, pos: Vector3) -> bool:
	return sim.team_sees(sim_team(peer_id), Vector2(pos.x, pos.z))

## Every unit whose body reaches into the flat circle around `centre` — capture
## zones and the like, now that units have no physics body for an Area3D.
func units_in_circle(centre: Vector3, radius: float) -> Array[Unit]:
	var found: Array[Unit] = []
	for id in sim.get_units_in_circle(Vector2(centre.x, centre.z), radius):
		if id < _units_by_id.size() and _units_by_id[id] != null:
			found.append(_units_by_id[id])
	return found

## Registers `unit` with the sim; -1 on a client or before the grid exists.
func register_unit(unit: Unit) -> int:
	if not _ready_for_units:
		return -1
	var position := Vector2(unit.global_position.x, unit.global_position.z)
	var id: int = sim.add_unit(sim_team(unit.owner_peer_id), position, NavigationBlockers.UNIT_BODY_RADIUS, unit.move_speed)
	if unit.can_fight:
		sim.set_unit_combat(id, unit.attack_range, unit.aggro_range, unit.projectile_scene != null)
	sim.set_unit_vision(id, unit.vision_range)
	sim.set_unit_cooldown(id, unit.attack_cooldown)
	if id >= _units_by_id.size():
		_units_by_id.resize(id + 1)
	_units_by_id[id] = unit
	if unit.net_id < 0 and get_parent() is Main and (get_parent() as Main).army_net != null:
		(get_parent() as Main).army_net.assign_net_id(unit)
	return id

func unregister_unit(sim_id: int) -> void:
	if sim_id < 0:
		return
	sim.remove_unit(sim_id)
	if sim_id < _units_by_id.size():
		_units_by_id[sim_id] = null

## After each sim tick: every unit the sim moved is put where it now stands,
## and every unit that could not go where it wanted is told so (see
## Unit._track_blocked). Idle units are not touched at all.
func apply_sim_results() -> void:
	var moved: PackedFloat32Array = sim.get_moved_units()
	for unit in _moving:
		if is_instance_valid(unit):
			(unit as Unit).sim_velocity = Vector2.ZERO
	var was_moving := _moving
	_moving = []
	for i in range(0, moved.size(), 6):
		var unit: Unit = _units_by_id[int(moved[i])]
		if unit != null:
			unit.global_position = Vector3(moved[i + 1], moved[i + 2], moved[i + 3])
			unit.sim_velocity = Vector2(moved[i + 4], moved[i + 5])
			_moving.append(unit)
			if unit.quiet:
				unit.quiet_motion(unit.sim_velocity)
	## Men asleep who stopped this tick stand.
	for unit in was_moving:
		if is_instance_valid(unit) and (unit as Unit).quiet and (unit as Unit).sim_velocity == Vector2.ZERO:
			(unit as Unit).quiet_motion(Vector2.ZERO)
	## Who each man fighting from his place should hit.
	var targets: PackedInt32Array = sim.get_fight_targets()
	for i in range(0, targets.size(), 2):
		var unit: Unit = _units_by_id[targets[i]]
		if unit != null:
			unit.sim_target = _units_by_id[targets[i + 1]] if targets[i + 1] >= 0 else null
	## The blows due this tick, asleep or awake.
	var swings: PackedInt32Array = sim.get_swings()
	for i in range(0, swings.size(), 2):
		var attacker: Unit = _units_by_id[swings[i]]
		var target: Unit = _units_by_id[swings[i + 1]]
		if attacker != null and target != null:
			attacker.sim_swing(target)
	## A block going for an enemy faces it: its men's front (for flanks and
	## braces) turns with it.
	var attacking: PackedFloat32Array = sim.get_attacking_formations()
	for i in range(0, attacking.size(), 3):
		var facing := Vector3(cos(attacking[i + 1]), 0.0, sin(attacking[i + 1]))
		for id in sim.get_formation_members(int(attacking[i])):
			var member: Unit = _units_by_id[id]
			if member != null and member.sim_follow:
				member.formation_facing = facing
	for formation in _building_targets.keys():
		var building: ProductionBuilding = _building_targets[formation]
		if not is_instance_valid(building) or not building.can_be_attacked():
			_building_targets.erase(formation)
			sim.order_hold(formation)
			_finish_block_order(formation)
	## An enemy near a block: its sleeping men wake to look for themselves.
	for formation in sim.get_enemy_alerts():
		for id in sim.get_formation_members(formation):
			var member: Unit = _units_by_id[id]
			## Already in its block's fight: nothing of his own to look for.
			if member != null and member.quiet and not member.in_formation_fight:
				member.wake()
	## A block that has marched its last leg, or has nobody left to fight:
	## its men stand as a block, or pick their attack-move back up.
	for formation in sim.get_arrived_formations():
		_building_targets.erase(formation)
		_finish_block_order(formation)
	for unit in _wedged:
		if is_instance_valid(unit):
			(unit as Unit).sim_wedged = false
	_wedged.clear()
	for id in sim.get_wedged_units():
		var unit: Unit = _units_by_id[id]
		if unit != null:
			unit.sim_wedged = true
			_wedged.append(unit)

func _finish_block_order(formation: int) -> void:
	var block: Array[Unit] = []
	for id in sim.get_formation_members(formation):
		var member: Unit = _units_by_id[id]
		if member != null and member.sim_solo and not member.sim_follow:
			member.solo_arrived = true
		elif member != null and member.sim_follow:
			block.append(member)
	if block.is_empty():
		return
	var order: Dictionary = block[0].attack_move_order
	if block[0].status_command == Unit.Command.ATTACK and not order.is_empty():
		order_blocks(block, order["target"], true, false, order["type"], Vector3.ZERO)
		return
	for member in block:
		member.arrive_in_block(block)

## The sim's team index for `peer_id`: 0 neutral, then one small index per
## team in the order they are first seen.
func sim_team(peer_id: int) -> int:
	var team: int = Teams.team_of(peer_id)
	if not _team_index.has(team):
		_team_index[team] = _team_index.size()
	return _team_index[team]

## --- Formations ---

## A ground order (move or attack-move) for `units`, from a player or an AI.
## The selection splits into blocks — each regiment on its own, and the loose
## units one block per unit type — and every block marches to the ordered
## point offset by where it stands in the group, so a line of blocks arrives
## as a line of blocks. The men then hold their places (Unit.sim_follow) until
## given something else to do. `facing` is a right-drag's facing, or zero to
## face the way the group is going. `append` queues the leg after whatever
## each block is already doing.
func order_blocks(units: Array[Unit], world_pos: Vector3, attack_move: bool, append: bool, formation_type: Formation.Type, facing: Vector3) -> void:
	var blocks := _split_blocks(units)
	if blocks.is_empty():
		return
	var centre := GroupMovement.group_centroid_of(units)
	var forward := facing
	if forward == Vector3.ZERO:
		forward = (world_pos - centre) * Vector3(1, 0, 1)
	if forward.length_squared() < 0.0001:
		forward = _held_forward(units)
	forward = forward.normalized()
	## One order shared by every block, so a block that meets an enemy on an
	## attack-move can bring the whole group round (block_contact).
	var order := {}
	if attack_move:
		order = {"units": units.duplicate(), "target": world_pos, "type": formation_type, "forward": forward, "front_width": -1.0}
	for block: Array[Unit] in blocks:
		var offset := Vector3.ZERO
		if blocks.size() > 1:
			offset = (GroupMovement.group_centroid_of(block) - centre) * Vector3(1, 0, 1)
		_order_block(block, world_pos + offset, forward, attack_move, append, formation_type, order)

## One unit walking somewhere on its own (Unit.move_to): out of any block it
## was in, and its formation of one sent there at its own pace. The sim plans
## the route, as it does for a block.
func solo_move(unit: Unit, target: Vector3) -> void:
	if not _ready_for_units or unit.sim_id < 0:
		return
	var here := Vector2(unit.global_position.x, unit.global_position.z)
	var formation: int = sim.get_unit_formation(unit.sim_id)
	if formation < 0 or sim.get_formation_members(formation).size() > 1:
		formation = sim.release(unit.sim_id, here)
	if formation < 0:
		return
	sim.set_speed(formation, unit.move_speed * unit._slow_multiplier() * unit._buff_speed_multiplier())
	sim.order_move(formation, Vector2(target.x, target.z), false, 0.0)

## A group attack on `target`: every block goes in (Very War's attack order),
## melee into contact, ranged to shooting distance, and its men fight from
## their places. `order` is an attack-move to resume once it is over.
func attack_blocks(units: Array[Unit], target: Node3D, formation_type: Formation.Type, order: Dictionary = {}) -> void:
	var target_unit := target as Unit
	var target_id: int = target_unit.sim_id if target_unit != null else -1
	var point := Vector2(target.global_position.x, target.global_position.z)
	for block: Array[Unit] in _split_blocks(units):
		var forward := (target.global_position - GroupMovement.group_centroid_of(block)) * Vector3(1, 0, 1)
		forward = forward.normalized() if forward.length_squared() > 0.0001 else _held_forward(block)
		var formation: int = _existing_formation(block)
		if formation < 0:
			formation = _form_block(block, forward, formation_type)
			if formation < 0:
				continue
		var speed: float = INF
		var reach: float = INF
		for unit in block:
			speed = minf(speed, unit.move_speed)
			if not unit.is_officer:
				reach = minf(reach, unit.attack_range)
		if target is ProductionBuilding:
			reach += (target as ProductionBuilding).get_footprint_radius()
			_building_targets[formation] = target
		sim.set_speed(formation, speed)
		## The front rank stops a little inside its reach of the enemy
		## (GroupMovement.ENGAGE_RANGE_FRACTION): in contact for melee, at
		## shooting distance for ranged. Never on top of it, where the block's
		## facing would swing with every shove.
		var engage: float = reach * GroupMovement.ENGAGE_RANGE_FRACTION
		sim.order_attack(formation, target_id, point, engage)
		for unit in block:
			unit.fight_in_block(target, order)

## `unit`'s block meeting `enemy`: on an attack-move (`resume`), the whole
## group still marching that order goes in and picks the march back up after;
## an idle block goes in as it stands. False if there is no block to bring.
func block_contact(unit: Unit, enemy: Node3D, resume: bool) -> bool:
	if not _ready_for_units or enemy == null or not is_instance_valid(enemy):
		return false
	var members: Array[Unit] = []
	var order: Dictionary = unit.attack_move_order if resume else {}
	if resume and not order.is_empty():
		for other in order.get("units", []):
			if is_instance_valid(other) and other.sim_follow and other.can_fight \
					and other.status_activity != Unit.Activity.DEAD and is_same(other.attack_move_order, order) \
					and other.status_command == Unit.Command.ATTACK_MOVE:
				members.append(other)
	else:
		var formation: int = sim.get_unit_formation(unit.sim_id)
		for id in sim.get_formation_members(formation):
			var member: Unit = _units_by_id[id]
			if member != null and member.sim_follow and member.can_fight and member.status_activity != Unit.Activity.DEAD:
				members.append(member)
	if members.size() < 2 or not members.has(unit):
		return false
	for member in members:
		if not Teams.is_enemy(member.owner_peer_id, enemy.owner_peer_id):
			return false
	attack_blocks(members, enemy, order.get("type", Formation.DEFAULT_TYPE), order)
	return true

## Main._engage_at_attack_move_destination, for blocks the sim moves.
func order_contact(order: Dictionary, enemy: Node3D) -> bool:
	for other in order.get("units", []):
		if is_instance_valid(other) and other.sim_follow:
			return block_contact(other, enemy, true)
	return false

## Regiments whole (officer last, men in their fixed places), then the loose
## units by type.
func _split_blocks(units: Array[Unit]) -> Array:
	var by_regiment: Dictionary = {}
	var by_type: Dictionary = {}
	for unit in units:
		if unit.sim_id < 0 or unit.status_activity == Unit.Activity.DEAD:
			continue
		if unit.regiment_id >= 0:
			if not by_regiment.has(unit.regiment_id):
				by_regiment[unit.regiment_id] = [] as Array[Unit]
			by_regiment[unit.regiment_id].append(unit)
		else:
			if not by_type.has(unit.display_name):
				by_type[unit.display_name] = [] as Array[Unit]
			by_type[unit.display_name].append(unit)
	var blocks: Array = []
	for id in by_regiment:
		var men: Array[Unit] = by_regiment[id]
		men.sort_custom(func(a: Unit, b: Unit) -> bool: return a.regiment_rank < b.regiment_rank)
		blocks.append(men)
	for key in by_type:
		blocks.append(by_type[key])
	return blocks

## The front the units were last holding, for an order given on the spot.
func _held_forward(units: Array[Unit]) -> Vector3:
	for unit in units:
		if unit.formation_facing != Vector3.ZERO:
			return unit.formation_facing
	return Vector3.RIGHT

func _order_block(block: Array[Unit], dest: Vector3, forward: Vector3, attack_move: bool, append: bool, formation_type: Formation.Type, order: Dictionary) -> void:
	var facing_angle: float = atan2(forward.z, forward.x)
	var formation: int = _existing_formation(block)
	if formation < 0:
		formation = _form_block(block, forward, formation_type)
		if formation < 0:
			return
	var speed: float = INF
	for unit in block:
		speed = minf(speed, unit.move_speed)
	## The block leads at its men's own pace; they run a little over it to
	## catch their places up (Very War's feel).
	sim.set_speed(formation, speed)
	var point := Vector2(dest.x, dest.z)
	if append:
		sim.queue_move(formation, point, true, facing_angle)
	else:
		sim.order_move(formation, point, true, facing_angle)
	_sync_regiment_ranks(block, formation)
	var group: Array[Unit] = block.duplicate()
	for unit in block:
		unit.follow_block(attack_move, append, dest, forward, group, order)

## The sim formation `block` already is, exactly — so re-ordering a block
## mid-march, or queueing it another leg, keeps its ranks and its momentum.
func _existing_formation(block: Array[Unit]) -> int:
	var formation: int = sim.get_unit_formation(block[0].sim_id)
	if formation < 0:
		return -1
	var members: PackedInt32Array = sim.get_formation_members(formation)
	if members.size() != block.size():
		return -1
	for unit in block:
		if not members.has(unit.sim_id):
			return -1
	return formation

## A new block for `block`, front rank first, laid out as `formation_type` and
## standing where the men already are.
func _form_block(block: Array[Unit], forward: Vector3, formation_type: Formation.Type) -> int:
	var right := Vector3(forward.z, 0.0, -forward.x)
	var men: Array[Unit] = []
	var officers: Array[Unit] = []
	for unit in block:
		if unit.is_officer and block.size() > 1:
			officers.append(unit)
		else:
			men.append(unit)
	var centroid := GroupMovement.group_centroid_of(men)
	## A regiment keeps its fixed places; anyone else takes the place nearest
	## where they stand in the group, so the block forms without men crossing.
	if men.is_empty() or men[0].regiment_rank < 0:
		var keyed: Array = []
		for unit in men:
			var rel: Vector3 = unit.global_position - centroid
			keyed.append([roundi(-rel.dot(forward) / Formation.SPACING), rel.dot(right), unit])
		keyed.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
		men.clear()
		for entry in keyed:
			men.append(entry[2])
	var ids := PackedInt32Array()
	for unit in men:
		ids.append(unit.sim_id)
	for unit in officers:
		ids.append(unit.sim_id)
	var layout := block_layout(formation_type, men.size(), block_spacing(block))
	var rows: int = ceili(float(men.size()) / maxi(int(layout.columns), 1))
	var front := centroid + forward * ((rows - 1) * float(layout.spacing) * 0.5)
	var formation: int = sim.form(ids, Vector2(front.x, front.z), atan2(forward.z, forward.x), officers.size())
	if formation >= 0:
		_apply_shape(formation, formation_type, men.size(), block_spacing(block))
	return formation

## Metres between neighbours in a block of horse, as Very War's riders.
const CAVALRY_SPACING: float = 1.8

## Columns, spacing and roughness for a block of `count` men in `formation_type`.
static func block_layout(formation_type: Formation.Type, count: int, spacing: float = Formation.SPACING) -> Dictionary:
	match formation_type:
		Formation.Type.LINE:
			return {"columns": clampi(count, 1, Formation.LINE_MAX_PER_RANK), "spacing": spacing, "loose": false}
		Formation.Type.LOOSE:
			return {"columns": clampi(ceili(sqrt(count)), 1, Formation.BOX_COLUMNS), "spacing": spacing * Formation.LOOSE_SPACING_SCALE, "loose": true}
		_:
			return {"columns": clampi(ceili(sqrt(count)), 1, Formation.BOX_COLUMNS), "spacing": spacing * Formation.BOX_SPACING_SCALE, "loose": false}

## Horse stand further apart than foot.
static func block_spacing(block: Array) -> float:
	for unit in block:
		if not (unit as Unit).is_officer:
			return CAVALRY_SPACING if (unit as Unit).can_charge else Formation.SPACING
	return Formation.SPACING

func _apply_shape(formation: int, formation_type: Formation.Type, men: int, spacing: float = Formation.SPACING) -> void:
	var layout := block_layout(formation_type, men, spacing)
	sim.set_layout(formation, layout.columns, layout.spacing, layout.loose)

## Re-lays every block the given units are holding places in as `formation_type`,
## on the spot — mid-march included.
func set_shape(units: Array[Unit], formation_type: Formation.Type) -> void:
	var done: Dictionary = {}
	for unit in units:
		if unit.sim_id < 0 or not unit.sim_follow:
			continue
		var formation: int = sim.get_unit_formation(unit.sim_id)
		if formation < 0 or done.has(formation):
			continue
		done[formation] = true
		var men: Array[Unit] = []
		for id in sim.get_formation_members(formation):
			var member: Unit = _units_by_id[id]
			if member != null and not member.is_officer:
				men.append(member)
		_apply_shape(formation, formation_type, maxi(men.size(), 1), block_spacing(men))
		if unit.regiment_id >= 0 and get_parent() is Main and (get_parent() as Main).regiments.has(unit.regiment_id):
			((get_parent() as Main).regiments[unit.regiment_id] as Regiment).formation_type = formation_type

## A regiment's ranks follow its block's slot order, which a turn about in the
## sim reverses — kept in step so the older formation code places them alike.
func _sync_regiment_ranks(block: Array[Unit], formation: int) -> void:
	if block[0].regiment_id < 0:
		return
	var rank := 0
	for id in sim.get_formation_members(formation):
		var unit: Unit = _units_by_id[id]
		if unit != null and not unit.is_officer:
			unit.regiment_rank = rank
			rank += 1

## --- Debug overlay ("cmd formations") ---

func toggle_formation_overlay() -> bool:
	if _formation_overlay != null:
		_formation_overlay.queue_free()
		_formation_overlay = null
		return false
	_formation_overlay = MeshInstance3D.new()
	_formation_overlay.name = "FormationOverlay"
	_formation_overlay.mesh = ImmediateMesh.new()
	_formation_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	_formation_overlay.material_override = material
	add_child(_formation_overlay)
	return true

## Each block of two or more: its front centre and facing (yellow), the route
## still ahead of it (cyan), and every member's place (white).
func _draw_formations() -> void:
	var mesh := _formation_overlay.mesh as ImmediateMesh
	mesh.clear_surfaces()
	var states: PackedFloat32Array = sim.get_formation_states(2)
	var places: PackedVector3Array = sim.get_slot_targets(2)
	if states.is_empty():
		return
	var lift := Vector3(0.0, 0.3, 0.0)
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(0, states.size(), 8):
		var front := Vector3(states[i + 1], states[i + 3], states[i + 2]) + lift
		var facing: float = states[i + 4]
		var ahead := Vector3(cos(facing), 0.0, sin(facing))
		var side := Vector3(ahead.z, 0.0, -ahead.x)
		mesh.surface_set_color(Color.YELLOW)
		mesh.surface_add_vertex(front)
		mesh.surface_add_vertex(front + ahead * 2.5)
		mesh.surface_add_vertex(front + side * 1.5)
		mesh.surface_add_vertex(front - side * 1.5)
		var route: PackedVector3Array = sim.get_formation_path(int(states[i]))
		mesh.surface_set_color(Color.CYAN)
		for k in range(1, route.size()):
			mesh.surface_add_vertex(route[k - 1] + lift)
			mesh.surface_add_vertex(route[k] + lift)
	mesh.surface_set_color(Color.WHITE)
	for place in places:
		var p := place + lift
		mesh.surface_add_vertex(p + Vector3(-0.25, 0.0, 0.0))
		mesh.surface_add_vertex(p + Vector3(0.25, 0.0, 0.0))
		mesh.surface_add_vertex(p + Vector3(0.0, 0.0, -0.25))
		mesh.surface_add_vertex(p + Vector3(0.0, 0.0, 0.25))
	mesh.surface_end()

## --- Debug overlay ("cmd navgrid") ---

func toggle_overlay() -> bool:
	if _overlay != null:
		_overlay.queue_free()
		_overlay = null
		return false
	var info: Dictionary = sim.get_grid_info()
	var cell: float = info.cell
	var size := Vector2(int(info.cols) * cell, int(info.rows) * cell)
	var origin: Vector2 = info.origin
	_overlay = Decal.new()
	_overlay.name = "NavGridOverlay"
	_overlay.size = Vector3(size.x, 400.0, size.y)
	_overlay.position = Vector3(origin.x + size.x * 0.5, 0.0, origin.y + size.y * 0.5)
	add_child(_overlay)
	_overlay_timer = 0.0
	return true

## Unwalkable terrain blue, stamped footprints red, open ground clear.
func _refresh_overlay() -> void:
	var info: Dictionary = sim.get_grid_info()
	var image := Image.create_from_data(int(info.cols), int(info.rows), false, Image.FORMAT_RGBA8, sim.get_grid_debug_rgba())
	if _overlay.texture_albedo is ImageTexture and _overlay.texture_albedo.get_size() == Vector2(image.get_size()):
		(_overlay.texture_albedo as ImageTexture).update(image)
	else:
		_overlay.texture_albedo = ImageTexture.create_from_image(image)
