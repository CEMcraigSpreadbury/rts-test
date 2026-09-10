class_name NavigationBlockers
extends Node

## Keeps the NavigationRegion3D's navmesh in sync with everything solid that
## exists or gets built during a match, so that the A* pathfinder units
## already run on (NavigationAgent3D -> NavigationServer3D.map_get_path)
## plans routes AROUND buildings, walls and resource nodes instead of straight
## through them.
##
## Why this is needed: the region's navmesh is baked from terrain alone, and
## buildings used to be nothing but a NavigationObstacle3D, i.e. pure runtime
## RVO avoidance. RVO is a local steering solver with a one-or-two-second
## horizon — it can sidestep a passing unit, but against a static footprint
## with the goal directly behind it there is nothing for it to do except push
## the unit into the wall and hold it there. That is the "units get stuck on
## buildings" problem: the *path* was wrong, and no amount of local avoidance
## can rescue a wrong path. RVO is still enabled and still does its job for
## the last couple of meters (unit-vs-unit jostling, and shaving the corner
## off a footprint the navmesh only knows to within a rasterization cell).
##
## How it works:
##   — At startup the region's authored navmesh (terrain, baked in the editor)
##     is converted back into source geometry and kept as the pristine
##     baseline. Every rebake starts from that same snapshot, so the
##     rasterize/erode round trip happens exactly once rather than compounding
##     a little more erosion onto the map with every building placed.
##   — Blockers come from PHYSICS, not from NavigationObstacle3D: every
##     collision shape on a "buildings"/"gatherables" body sitting on a layer
##     units actually collide with. That is exactly the set of things a unit's
##     move_and_slide() can get stuck on. Reading the obstacle radius instead
##     would be wrong in both directions — a Gate's obstacle radius is a
##     deliberately tiny 0.3 so RVO lets units squeeze through the arch (using
##     it here would carve the middle of the gateway and seal it), while a
##     Farm's is a large 1.7 even though a Farm sits on a collision layer that
##     units walk straight over.
##   — Each footprint is projected to XZ, inflated by the navmesh's own
##     agent_radius, and subtracted with
##     NavigationMeshSourceGeometryData3D.add_projected_obstruction(). Every
##     obstruction keeps the real vertical extent of the shape it came from,
##     which is what lets a Gate stay open: its two posts carve the ground,
##     its lintel only carves head height and leaves the floor beneath it
##     walkable.
##   — Rebaking runs on a worker thread into a scratch NavigationMesh, and the
##     region is only swapped onto it once the bake finishes, so no frame ever
##     queries a half-built mesh.
##
## Changes are detected by polling a cheap hash of the blocker set rather than
## by hooking the (many) places that spawn, finish, destroy or exhaust one.
## A quarter second of latency before a newly placed wall reaches the navmesh
## is imperceptible in an RTS, and polling cannot miss a path the way a
## forgotten call site can.

## Which collision layers count as "solid to a unit" — matches the
## collision_mask on scenes/units/unit.tscn. Buildings and resource nodes sit
## on layer 1 (the default); a Farm deliberately sits on layer 2 instead,
## because villagers walk onto it to work it, and so is skipped here.
const UNIT_COLLISION_MASK: int = 1
## Groups scanned for blockers. Units are NOT in here on purpose: they move,
## they are already handled by RVO, and rebaking around them would be both
## ruinously expensive and self-defeating (a unit standing in a doorway would
## delete the doorway).
const BLOCKER_GROUPS: Array[StringName] = [&"buildings", &"gatherables"]
const POLL_INTERVAL: float = 0.25
## Points used to approximate a round shape's outline. 12 is plenty at the
## 0.25m rasterization cell the navmesh bakes at.
const CIRCLE_SEGMENTS: int = 12
## How far below a shape's own underside its carve starts. Without a little
## slack, a footprint whose base sits exactly on the ground can rasterize just
## above the floor span it is supposed to remove. Downwards only — extending a
## carve *upwards* is what would wrongly seal a gateway.
const CARVE_FLOOR_MARGIN: float = 0.5
## Minimum clearance carved around every footprint — the radius of the unit's
## physical capsule in scenes/units/unit.tscn. Anything less and the navmesh
## keeps gaps a unit can't physically fit through (two trunks 0.7m apart in a
## generated forest), so paths send units into them and they wedge there.
const UNIT_BODY_RADIUS: float = 0.4

var _region: NavigationRegion3D = null
## Pristine terrain-only source geometry, snapshotted once (see class docs),
## as a de-indexed triangle soup (three corners per face).
var _base_faces := PackedVector3Array()
## Bake settings template — the authored navmesh's own settings with
## agent_radius zeroed, because the baseline geometry above is *already* the
## eroded walkable surface. Re-eroding it on every bake would shrink the map's
## walkable area a little further each time. Building footprints get that
## clearance applied explicitly instead, in _add_body_obstructions().
var _bake_template: NavigationMesh = null
var _clearance: float = UNIT_BODY_RADIUS
var _poll_timer: float = 0.0
var _blocker_signature: int = 0
var _bake_in_flight: bool = false
var _rebake_queued: bool = false

## Call once, after this node is in the tree.
func setup(region: NavigationRegion3D) -> void:
	_region = region
	var authored: NavigationMesh = region.navigation_mesh if region != null else null
	if authored == null or authored.get_polygon_count() == 0:
		## Nothing baked to work from — leave navigation exactly as authored
		## rather than replacing it with an empty mesh.
		set_process(false)
		return
	_clearance = maxf(authored.agent_radius, UNIT_BODY_RADIUS)
	_bake_template = authored.duplicate()
	_bake_template.agent_radius = 0.0
	_snapshot_base_geometry(authored)
	_match_map_cell_height(authored)
	_blocker_signature = _blocker_state_hash()
	_rebake()

## The authored navmesh is baked at a much finer cell_height than the default
## navigation map rasterizes at, which the map only complains about when a
## mesh is assigned at runtime (as this class does) rather than on scene load.
## The mismatch is real either way — it costs precision on navmesh edges — so
## point the map at the mesh's own resolution, which is what the engine's own
## warning recommends. There is only ever the one region on this map.
func _match_map_cell_height(mesh: NavigationMesh) -> void:
	var map: RID = _region.get_navigation_map()
	if map.is_valid() and not is_equal_approx(NavigationServer3D.map_get_cell_height(map), mesh.cell_height):
		NavigationServer3D.map_set_cell_height(map, mesh.cell_height)

## --- Baseline geometry ---

## Turns the authored navmesh back into the triangle soup a bake consumes.
## Navmesh polygons can be n-gons, so each is fanned into triangles.
##
## Winding matters and is easy to get backwards: Recast decides walkability
## from the face normal and silently drops every downward-facing triangle (the
## symptom is a bake that completes cleanly and produces zero polygons), while
## add_faces() flips the winding of everything handed to it. So each triangle
## is stored pointing DOWN here, precisely so it comes back out of add_faces()
## pointing up.
func _snapshot_base_geometry(mesh: NavigationMesh) -> void:
	var vertices: PackedVector3Array = mesh.get_vertices()
	_base_faces = PackedVector3Array()
	for p in mesh.get_polygon_count():
		var polygon: PackedInt32Array = mesh.get_polygon(p)
		for k in range(1, polygon.size() - 1):
			_append_triangle(vertices[polygon[0]], vertices[polygon[k]], vertices[polygon[k + 1]])

func _append_triangle(a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal: Vector3 = (b - a).cross(c - a)
	if normal.y <= 0.0:
		_base_faces.append_array(PackedVector3Array([a, b, c]))
	else:
		_base_faces.append_array(PackedVector3Array([a, c, b]))

## --- Change detection ---

func _process(delta: float) -> void:
	_poll_timer -= delta
	if _poll_timer > 0.0:
		return
	_poll_timer = POLL_INTERVAL
	var signature: int = _blocker_state_hash()
	if signature == _blocker_signature:
		return
	_blocker_signature = signature
	_rebake()

## Cheap fingerprint of "which things are currently solid, and where".
## Instance ids cover spawns and frees, the quantized position covers a
## blocker that moved, and _is_blocking's destroyed check covers a building
## still in the tree playing its collapse animation but no longer in the way.
func _blocker_state_hash() -> int:
	var state: Array = []
	for group in BLOCKER_GROUPS:
		for node in get_tree().get_nodes_in_group(group):
			var body := node as CollisionObject3D
			if not _is_blocking(body):
				continue
			state.append(body.get_instance_id())
			state.append(roundi(body.global_position.x * 4.0))
			state.append(roundi(body.global_position.z * 4.0))
	return state.hash()

func _is_blocking(body: CollisionObject3D) -> bool:
	if body == null or not is_instance_valid(body) or body.is_queued_for_deletion():
		return false
	if body.collision_layer & UNIT_COLLISION_MASK == 0:
		return false
	## Untyped lookup on purpose: Gatherable has no such property and answers
	## null, while a ProductionBuilding mid-collapse is already sinking out of
	## the way and should stop blocking the moment it starts.
	return body.get(&"is_destroyed") != true

## --- Baking ---

func _rebake() -> void:
	if _bake_template == null:
		return
	if _bake_in_flight:
		## Coalesce — a wall drag places a dozen segments in as many frames.
		_rebake_queued = true
		return
	var geometry := NavigationMeshSourceGeometryData3D.new()
	## add_faces() rather than set_vertices()/set_indices(): the indexed
	## setters reject any mesh with more indices than vertex floats, which a
	## navmesh fanned into triangles routinely is.
	geometry.add_faces(_base_faces, Transform3D.IDENTITY)
	_collect_obstructions(geometry)
	var scratch: NavigationMesh = _bake_template.duplicate()
	_bake_in_flight = true
	NavigationServer3D.bake_from_source_geometry_data_async(scratch, geometry, _on_bake_finished.bind(scratch))

func _on_bake_finished(mesh: NavigationMesh) -> void:
	_bake_in_flight = false
	if is_instance_valid(_region) and mesh.get_polygon_count() > 0:
		_region.navigation_mesh = mesh
		_repath_units()
	if _rebake_queued:
		_rebake_queued = false
		_rebake()

## A unit already walking somewhere is holding a path planned against the
## previous navmesh — through the doorway that just got walled up, or the long
## way around a building that just got demolished. Re-issuing the target makes
## NavigationAgent3D run a fresh query against the mesh that just landed.
func _repath_units() -> void:
	for node in get_tree().get_nodes_in_group(&"units"):
		var unit := node as Unit
		if unit != null and is_instance_valid(unit):
			unit.repath()

## --- Footprints ---

func _collect_obstructions(geometry: NavigationMeshSourceGeometryData3D) -> void:
	## Obstruction outlines share the source geometry's space, and that came
	## out of the region's own navmesh — which is region-local, and the region
	## is not sitting at the origin.
	var to_local: Transform3D = _region.global_transform.affine_inverse()
	for group in BLOCKER_GROUPS:
		for node in get_tree().get_nodes_in_group(group):
			var body := node as CollisionObject3D
			if _is_blocking(body):
				_add_body_obstructions(geometry, body, to_local)

## Carving a Gate's two posts (rather than its NavigationObstacle3D, which is
## a single deliberately tiny radius sitting in the middle of the archway)
## leaves the gateway open: the posts are the only solid parts of it, so the
## navmesh keeps roughly a metre of corridor between them and paths thread it
## instead of walking around the wall.
func _add_body_obstructions(geometry: NavigationMeshSourceGeometryData3D, body: CollisionObject3D, to_local: Transform3D) -> void:
	for owner_id in body.get_shape_owners():
		if body.is_shape_owner_disabled(owner_id):
			continue
		var shape_transform: Transform3D = to_local * body.global_transform * body.shape_owner_get_transform(owner_id)
		for i in body.shape_owner_get_shape_count(owner_id):
			_add_shape_obstruction(geometry, body.shape_owner_get_shape(owner_id, i), shape_transform)

func _add_shape_obstruction(geometry: NavigationMeshSourceGeometryData3D, shape: Shape3D, shape_transform: Transform3D) -> void:
	var points: PackedVector3Array = _shape_points(shape)
	if points.is_empty():
		return
	var flat := PackedVector2Array()
	var min_y: float = INF
	var max_y: float = -INF
	for point in points:
		var placed: Vector3 = shape_transform * point
		flat.append(Vector2(placed.x, placed.z))
		min_y = minf(min_y, placed.y)
		max_y = maxf(max_y, placed.y)
	var hull: PackedVector2Array = Geometry2D.convex_hull(flat)
	## convex_hull() repeats the first point at the end to close the loop;
	## offset_polygon() wants an open ring.
	if hull.size() > 1 and hull[0].is_equal_approx(hull[hull.size() - 1]):
		hull.remove_at(hull.size() - 1)
	if hull.size() < 3:
		return
	for outline in Geometry2D.offset_polygon(hull, _clearance, Geometry2D.JOIN_MITER):
		var carve := PackedVector3Array()
		for point in outline:
			carve.append(Vector3(point.x, 0.0, point.y))
		geometry.add_projected_obstruction(carve, min_y - CARVE_FLOOR_MARGIN, (max_y - min_y) + CARVE_FLOOR_MARGIN, true)

## Points whose convex hull (in XZ) and vertical span describe the shape well
## enough to carve with. Round shapes get a real ring rather than their
## bounding box, which matters for a resource node: over-carving a Gold
## Deposit's corners would push the nearest walkable ground past the
## gather_range villagers stop at, and they would never reach it.
##
## ConcavePolygonShape3D (the terrain) is deliberately absent — it is already
## the baseline geometry, and it is never on a body in BLOCKER_GROUPS.
func _shape_points(shape: Shape3D) -> PackedVector3Array:
	if shape is BoxShape3D:
		return _box_points(shape.size * 0.5)
	if shape is CylinderShape3D:
		return _ring_points(shape.radius, shape.height * 0.5)
	if shape is CapsuleShape3D:
		return _ring_points(shape.radius, shape.height * 0.5)
	if shape is SphereShape3D:
		return _ring_points(shape.radius, shape.radius)
	if shape is ConvexPolygonShape3D:
		return shape.points
	return PackedVector3Array()

func _box_points(half: Vector3) -> PackedVector3Array:
	var points := PackedVector3Array()
	for x: float in [-half.x, half.x]:
		for y: float in [-half.y, half.y]:
			for z: float in [-half.z, half.z]:
				points.append(Vector3(x, y, z))
	return points

func _ring_points(radius: float, half_height: float) -> PackedVector3Array:
	var points := PackedVector3Array()
	for i in CIRCLE_SEGMENTS:
		var angle: float = TAU * float(i) / float(CIRCLE_SEGMENTS)
		var offset := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		points.append(offset + Vector3(0.0, -half_height, 0.0))
		points.append(offset + Vector3(0.0, half_height, 0.0))
	return points
