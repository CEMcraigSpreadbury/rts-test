class_name NavigationBlockers
extends Node

## Keeps the NavigationRegion3D's navmesh in sync with everything solid that
## exists or gets built during a match, so that NavigationServer3D.map_get_path
## (which the AI plans with) routes AROUND buildings, walls and resource nodes
## instead of straight through them. Units themselves are routed by the native
## sim, over its own grid (ArmyBridge stamps the same blockers onto it).
##
## Why this is needed: the region's navmesh is baked from terrain alone, and
## buildings used to be nothing but a NavigationObstacle3D, i.e. pure runtime
## RVO avoidance. RVO is a local steering solver with a one-or-two-second
## horizon — it can sidestep a passing unit, but against a static footprint
## with the goal directly behind it there is nothing for it to do except push
## the unit into the wall and hold it there. That is the "units get stuck on
## buildings" problem: the *path* was wrong, and no amount of local avoidance
## can rescue a wrong path.
##
## How it works:
##   — At startup the region's authored navmesh (terrain, baked in the editor)
##     is converted back into source geometry and kept as the pristine
##     baseline. Every rebake starts from that same snapshot, so the
##     rasterize/erode round trip happens exactly once rather than compounding
##     a little more erosion onto the map with every building placed.
##   — Blockers come from PHYSICS, not from NavigationObstacle3D: every
##     collision shape on a "buildings"/"gatherables" body sitting on a layer
##     units actually collide with — the set of things that are solid to a
##     unit. Reading the obstacle radius instead
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
##   — The map is baked in TILE_SIZE tiles, each its own region, cut exactly at
##     the tile edge (NavigationMesh.border_size) so neighbours join up in the
##     navigation map. One whole-map mesh at this cell size stops baking at all
##     somewhere under 1 km across (Recast runs out of region ids), and handing
##     the server a whole map's mesh after every change stalls a frame for tens
##     of milliseconds; a change now rebakes only the tiles it touches.
##   — Rebaking runs on worker threads into scratch NavigationMeshes, and a tile
##     region is only swapped onto its new mesh once that bake finishes, so no
##     frame ever queries a half-built mesh. The authored whole-map region
##     stays in use until every tile has baked once, then is switched off.
##
## Changes are detected by polling the blocker set rather than by hooking the
## (many) places that spawn, finish, destroy or exhaust one; felled trees come
## from Forest.tree_removed, which already says where.
## A quarter second of latency before a newly placed wall reaches the navmesh
## is imperceptible in an RTS, and polling cannot miss a path the way a
## forgotten call site can.

## Which collision layers count as "solid to a unit". Buildings and resource nodes sit
## on layer 1 (the default); a Farm deliberately sits on layer 2 instead,
## because villagers walk onto it to work it, and so is skipped here.
const UNIT_COLLISION_MASK: int = 1
## Groups scanned for blockers. Units are NOT in here on purpose: they move,
## the sim keeps them apart, and rebaking around them would be both ruinously
## expensive and self-defeating (a unit standing in a doorway would delete the
## doorway).
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
## Minimum clearance carved around every footprint — the radius of a unit's
## body (as the sim has it, see ArmyBridge.register_unit). Anything less and the navmesh
## keeps gaps a unit can't physically fit through (two trunks 0.7m apart in a
## generated forest), so paths send units into them and they wedge there.
const UNIT_BODY_RADIUS: float = 0.4
## How tall a tree's trunk carves (the collision cylinder trees used to have).
const TRUNK_HEIGHT: float = 3.0
## Metres per navmesh tile, and how far past its edge each tile's bake reads
## so the cut at the edge matches its neighbour's (a whole number of cells).
const TILE_SIZE: float = 128.0
const TILE_BORDER: float = 4.0
## Tile bakes running at once.
const MAX_BAKES_IN_FLIGHT: int = 3
## How far a building's solid footprint can reach from its origin: a change
## to one dirties every tile within this of it.
const BLOCKER_REACH: float = 12.0

var _region: NavigationRegion3D = null
## Trunk radius -> the cylinder carved for it, shared by every tree.
var _trunk_shapes: Dictionary = {}
## Bake settings template — the authored navmesh's own settings with
## agent_radius zeroed, because the baseline geometry below is *already* the
## eroded walkable surface. Re-eroding it on every bake would shrink the map's
## walkable area a little further each time. Building footprints get that
## clearance applied explicitly instead, in _add_body_obstructions().
var _bake_template: NavigationMesh = null
var _clearance: float = UNIT_BODY_RADIUS
var _poll_timer: float = 0.0
## Region-local bounds of the whole walkable surface, and the tile grid over it.
var _bounds: AABB
var _tile_count: Vector2i = Vector2i.ZERO
## Tile -> its pristine terrain-only source triangles (see class docs), as a
## de-indexed soup (three corners per face): every face reaching into the
## tile's bake area.
var _tile_faces: Dictionary = {}
## Tile -> its NavigationRegion3D.
var _tile_regions: Dictionary = {}
## Tiles waiting to bake, in the order they were dirtied (a dictionary used as
## an ordered set), and the ones baking now.
var _dirty: Dictionary = {}
var _in_flight: Dictionary = {}
## Until every tile has baked once the authored region stays on.
var _tiles_live: bool = false
## Blocker instance id -> [a key that changes when it moves, its origin].
var _known: Dictionary = {}
var _forest: Forest = null

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
	## Settings only: every tile bake duplicates this, and a copy of a whole
	## map's polygons each time cost tens of milliseconds on a 2 km map.
	_bake_template.clear()
	_bake_template.agent_radius = 0.0
	_bake_template.border_size = TILE_BORDER
	## Tile edges only line up with an edge error this low (see border_size).
	_bake_template.edge_max_error = minf(_bake_template.edge_max_error, 1.0)
	_match_map_cell_height(authored)
	_snapshot_base_geometry(authored)
	_known = _blocker_state()
	for tile in _tile_faces:
		_make_tile_region(tile)
		_dirty[tile] = true
	_pump()

## The authored navmesh is baked at a much finer cell_height than the default
## navigation map rasterizes at, which the map only complains about when a
## mesh is assigned at runtime (as this class does) rather than on scene load.
## The mismatch is real either way — it costs precision on navmesh edges — so
## point the map at the mesh's own resolution, which is what the engine's own
## warning recommends. Tiles join along shared edges found by position, so
## those are merged at a far finer scale than a cell.
func _match_map_cell_height(mesh: NavigationMesh) -> void:
	var map: RID = _region.get_navigation_map()
	if not map.is_valid():
		return
	if not is_equal_approx(NavigationServer3D.map_get_cell_height(map), mesh.cell_height):
		NavigationServer3D.map_set_cell_height(map, mesh.cell_height)
	NavigationServer3D.map_set_merge_rasterizer_cell_scale(map, 0.001)

## --- Baseline geometry ---

## Turns the authored navmesh back into the triangle soup a bake consumes, and
## sorts it into tiles. Navmesh polygons can be n-gons, so each is fanned into
## triangles.
##
## Winding matters and is easy to get backwards: Recast decides walkability
## from the face normal and silently drops every downward-facing triangle (the
## symptom is a bake that completes cleanly and produces zero polygons), while
## add_faces() flips the winding of everything handed to it. So each triangle
## is stored pointing DOWN here, precisely so it comes back out of add_faces()
## pointing up.
func _snapshot_base_geometry(mesh: NavigationMesh) -> void:
	var vertices: PackedVector3Array = mesh.get_vertices()
	_bounds = AABB(vertices[0], Vector3.ZERO)
	for v in vertices:
		_bounds = _bounds.expand(v)
	_tile_count = Vector2i(maxi(ceili(_bounds.size.x / TILE_SIZE), 1), maxi(ceili(_bounds.size.z / TILE_SIZE), 1))
	for p in mesh.get_polygon_count():
		var polygon: PackedInt32Array = mesh.get_polygon(p)
		for k in range(1, polygon.size() - 1):
			_add_triangle(vertices[polygon[0]], vertices[polygon[k]], vertices[polygon[k + 1]])

## Files the triangle under every tile whose bake area it reaches into.
func _add_triangle(a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal: Vector3 = (b - a).cross(c - a)
	var face := PackedVector3Array([a, b, c]) if normal.y <= 0.0 else PackedVector3Array([a, c, b])
	var margin := Vector2(TILE_BORDER, TILE_BORDER)
	var first := _tile_at(Vector2(minf(a.x, minf(b.x, c.x)), minf(a.z, minf(b.z, c.z))) - margin)
	var last := _tile_at(Vector2(maxf(a.x, maxf(b.x, c.x)), maxf(a.z, maxf(b.z, c.z))) + margin)
	for z in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var tile := Vector2i(x, z)
			if not _tile_faces.has(tile):
				_tile_faces[tile] = PackedVector3Array()
			_tile_faces[tile].append_array(face)

## The tile holding region-local point (x, z), clamped onto the grid.
func _tile_at(local: Vector2) -> Vector2i:
	var x: int = floori((local.x - _bounds.position.x) / TILE_SIZE)
	var z: int = floori((local.y - _bounds.position.z) / TILE_SIZE)
	return Vector2i(clampi(x, 0, _tile_count.x - 1), clampi(z, 0, _tile_count.y - 1))

## The tile's own square, region-local, full height.
func _tile_bounds(tile: Vector2i) -> AABB:
	return AABB(Vector3(_bounds.position.x + tile.x * TILE_SIZE, _bounds.position.y - 5.0, _bounds.position.z + tile.y * TILE_SIZE),
			Vector3(TILE_SIZE, _bounds.size.y + 10.0, TILE_SIZE))

func _make_tile_region(tile: Vector2i) -> void:
	var tile_region := NavigationRegion3D.new()
	tile_region.name = "NavTile_%d_%d" % [tile.x, tile.y]
	tile_region.enabled = false
	add_child(tile_region)
	## This node is not a Node3D, so the region's transform is its global one.
	tile_region.transform = _region.global_transform
	_tile_regions[tile] = tile_region

## --- Change detection ---

func _process(delta: float) -> void:
	_poll_timer -= delta
	if _poll_timer > 0.0:
		return
	_poll_timer = POLL_INTERVAL
	var poll_start := Time.get_ticks_usec() if PerfStats.enabled else 0
	_watch_forest()
	var now: Dictionary = _blocker_state()
	for id in now:
		if not _known.has(id) or _known[id][0] != now[id][0]:
			_dirty_around(now[id][1], BLOCKER_REACH)
			if _known.has(id):
				_dirty_around(_known[id][1], BLOCKER_REACH)
	for id in _known:
		if not now.has(id):
			_dirty_around(_known[id][1], BLOCKER_REACH)
	_known = now
	if PerfStats.enabled:
		PerfStats.record_event(&"nav poll", Time.get_ticks_usec() - poll_start)
	_pump()

## Felled trees (see Forest) dirty the tile they stood in.
func _watch_forest() -> void:
	if _forest == Forest.active or Forest.active == null:
		return
	_forest = Forest.active
	_forest.tree_removed.connect(func(_id: int, at: Vector3): _dirty_around(at, 2.0))

## "Which things are currently solid, and where": instance id -> [a key that
## changes when it moves, its origin]. Anything that stops blocking drops out
## — including, through _is_blocking's destroyed check, a building still in
## the tree playing its collapse animation but no longer in the way. Trees
## are not in these groups (see Forest), so this only ever walks buildings,
## gold and farms.
func _blocker_state() -> Dictionary:
	var state: Dictionary = {}
	for group in BLOCKER_GROUPS:
		for node in get_tree().get_nodes_in_group(group):
			var body := node as CollisionObject3D
			if not _is_blocking(body):
				continue
			var at: Vector3 = body.global_position
			state[body.get_instance_id()] = [Vector2i(roundi(at.x * 4.0), roundi(at.z * 4.0)), at]
	return state

## Marks every tile within `reach` of world point `world` for a rebake.
func _dirty_around(world: Vector3, reach: float) -> void:
	if _tile_count == Vector2i.ZERO:
		return
	var local: Vector3 = _region.global_transform.affine_inverse() * world
	var margin := Vector2(reach + TILE_BORDER, reach + TILE_BORDER)
	var first := _tile_at(Vector2(local.x, local.z) - margin)
	var last := _tile_at(Vector2(local.x, local.z) + margin)
	for z in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var tile := Vector2i(x, z)
			if _tile_faces.has(tile):
				_dirty[tile] = true

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

## Starts dirty tiles baking, up to MAX_BAKES_IN_FLIGHT. A tile dirtied again
## while it bakes waits for that bake to land and then goes again — which also
## coalesces a wall drag placing a dozen segments in as many frames.
func _pump() -> void:
	if _bake_template == null:
		return
	for tile in _dirty.keys():
		if _in_flight.size() >= MAX_BAKES_IN_FLIGHT:
			return
		if _in_flight.has(tile):
			continue
		_dirty.erase(tile)
		_bake_tile(tile)

## Only what needs the scene tree happens here — which buildings are in
## reach, and where the trees stand. Building the geometry, carving a
## forest's worth of trunks and the bake itself all run on a worker thread:
## on a 2 km map that preparation alone took up to 80 ms a tile.
func _bake_tile(tile: Vector2i) -> void:
	var prep_start := Time.get_ticks_usec() if PerfStats.enabled else 0
	var area: AABB = _tile_bounds(tile).grow(TILE_BORDER)
	var carves: Array = []
	var trees: Array = []
	_collect_obstructions(carves, trees, area)
	var scratch: NavigationMesh = _bake_template.duplicate()
	scratch.filter_baking_aabb = area
	_in_flight[tile] = true
	if PerfStats.enabled:
		PerfStats.record_event(&"nav tile prep", Time.get_ticks_usec() - prep_start)
	WorkerThreadPool.add_task(_bake_on_worker.bind(tile, scratch, _tile_faces[tile], carves, trees))

## Worker thread: touches no nodes, only the data handed over.
func _bake_on_worker(tile: Vector2i, scratch: NavigationMesh, faces: PackedVector3Array, carves: Array, trees: Array) -> void:
	for tree in trees:
		_add_shape_obstruction(carves, tree[0], tree[1])
	var geometry := NavigationMeshSourceGeometryData3D.new()
	## add_faces() rather than set_vertices()/set_indices(): the indexed
	## setters reject any mesh with more indices than vertex floats, which a
	## navmesh fanned into triangles routinely is.
	geometry.add_faces(faces, Transform3D.IDENTITY)
	for carve in carves:
		geometry.add_projected_obstruction(carve[0], carve[1], carve[2], true)
	NavigationServer3D.bake_from_source_geometry_data(scratch, geometry)
	_on_bake_finished.call_deferred(tile, scratch)

## True from the moment a change is spotted until the navmesh reflects it —
## paths asked for in between are planned on the old mesh (or, at the very
## start of a match, the authored terrain-only one) and can be wrong.
func is_baking() -> bool:
	return not _in_flight.is_empty() or not _dirty.is_empty() or (_bake_template != null and not _tiles_live)

func _on_bake_finished(tile: Vector2i, mesh: NavigationMesh) -> void:
	_in_flight.erase(tile)
	var tile_region: NavigationRegion3D = _tile_regions.get(tile)
	if is_instance_valid(tile_region):
		## Lands on the main thread, however the bake itself was produced.
		## Units don't walk it (the sim routes them); the AI plans on it.
		var swap_start := Time.get_ticks_usec() if PerfStats.enabled else 0
		mesh.filter_baking_aabb = AABB()
		tile_region.navigation_mesh = mesh
		if PerfStats.enabled:
			PerfStats.record_event(&"nav mesh swap", Time.get_ticks_usec() - swap_start)
	if not _tiles_live and _in_flight.is_empty() and _dirty.is_empty():
		_tiles_live = true
		for key in _tile_regions:
			_tile_regions[key].enabled = true
		## Taken out of the map outright: switching the node off left the
		## region answering queries in the server.
		if is_instance_valid(_region):
			_region.enabled = false
			NavigationServer3D.region_set_map(_region.get_rid(), RID())
	_pump()

## --- Generator bake ---

## Bakes `faces` (a de-indexed soup, pointing down — see
## _snapshot_base_geometry) with `settings` one TILE_SIZE tile at a time and
## joins the tiles into one mesh: the map generator's bake, which as a single
## whole-map bake gives up on a 2 km map. Blocking; editor and tools only.
static func bake_tiled(settings: NavigationMesh, faces: PackedVector3Array) -> NavigationMesh:
	var bounds := AABB(faces[0], Vector3.ZERO)
	for v in faces:
		bounds = bounds.expand(v)
	var tiles := Vector2i(maxi(ceili(bounds.size.x / TILE_SIZE), 1), maxi(ceili(bounds.size.z / TILE_SIZE), 1))
	var buckets: Dictionary = {}
	for i in range(0, faces.size(), 3):
		var a: Vector3 = faces[i]
		var b: Vector3 = faces[i + 1]
		var c: Vector3 = faces[i + 2]
		var x0: int = clampi(floori((minf(a.x, minf(b.x, c.x)) - TILE_BORDER - bounds.position.x) / TILE_SIZE), 0, tiles.x - 1)
		var x1: int = clampi(floori((maxf(a.x, maxf(b.x, c.x)) + TILE_BORDER - bounds.position.x) / TILE_SIZE), 0, tiles.x - 1)
		var z0: int = clampi(floori((minf(a.z, minf(b.z, c.z)) - TILE_BORDER - bounds.position.z) / TILE_SIZE), 0, tiles.y - 1)
		var z1: int = clampi(floori((maxf(a.z, maxf(b.z, c.z)) + TILE_BORDER - bounds.position.z) / TILE_SIZE), 0, tiles.y - 1)
		for z in range(z0, z1 + 1):
			for x in range(x0, x1 + 1):
				var key := Vector2i(x, z)
				if not buckets.has(key):
					buckets[key] = PackedVector3Array()
				buckets[key].append_array(PackedVector3Array([a, b, c]))
	var merged := NavigationMesh.new()
	merged.cell_size = settings.cell_size
	merged.cell_height = settings.cell_height
	merged.agent_radius = settings.agent_radius
	merged.agent_max_slope = settings.agent_max_slope
	var vertices := PackedVector3Array()
	for key: Vector2i in buckets:
		var tile := settings.duplicate() as NavigationMesh
		tile.border_size = TILE_BORDER
		tile.edge_max_error = minf(tile.edge_max_error, 1.0)
		tile.filter_baking_aabb = AABB(Vector3(bounds.position.x + key.x * TILE_SIZE, bounds.position.y - 5.0, bounds.position.z + key.y * TILE_SIZE),
				Vector3(TILE_SIZE, bounds.size.y + 10.0, TILE_SIZE)).grow(TILE_BORDER)
		var geometry := NavigationMeshSourceGeometryData3D.new()
		geometry.add_faces(buckets[key], Transform3D.IDENTITY)
		NavigationServer3D.bake_from_source_geometry_data(tile, geometry)
		var offset: int = vertices.size()
		vertices.append_array(tile.get_vertices())
		for p in tile.get_polygon_count():
			var polygon: PackedInt32Array = tile.get_polygon(p)
			for i in polygon.size():
				polygon[i] += offset
			merged.add_polygon(polygon)
	merged.set_vertices(vertices)
	return merged

## --- Queries ---
##
## The navigation server answers "nearest point on the navmesh" (and the start
## and end of every path) by checking every polygon on the map: about 8 ms a
## lookup on a 1 km map with its forests carved. These ask only the tiles
## around the question instead.

## The nearest navmesh point to `world` among the tiles around it, or null
## until the tiles are live (ask the map instead).
func closest_point(world: Vector3) -> Variant:
	if not _tiles_live:
		return null
	var local: Vector3 = _region.global_transform.affine_inverse() * world
	var centre := _tile_at(Vector2(local.x, local.z))
	var best: Variant = null
	var best_distance: float = INF
	for z in range(centre.y - 1, centre.y + 2):
		for x in range(centre.x - 1, centre.x + 2):
			var tile_region: NavigationRegion3D = _tile_regions.get(Vector2i(x, z))
			if tile_region == null or tile_region.navigation_mesh == null or tile_region.navigation_mesh.get_polygon_count() == 0:
				continue
			var point: Vector3 = NavigationServer3D.region_get_closest_point(tile_region.get_rid(), world)
			var distance: float = point.distance_squared_to(world)
			if distance < best_distance:
				best_distance = distance
				best = point
	return best

## The tile regions a path from `a` to `b` should be searched over: every tile
## in the box around both, `margin` tiles wider for detours. Empty until the
## tiles are live, which a path query reads as "the whole map".
func regions_between(a: Vector3, b: Vector3, margin: int = 1) -> Array[RID]:
	var found: Array[RID] = []
	if not _tiles_live:
		return found
	var to_local: Transform3D = _region.global_transform.affine_inverse()
	var la: Vector3 = to_local * a
	var lb: Vector3 = to_local * b
	var first := _tile_at(Vector2(minf(la.x, lb.x), minf(la.z, lb.z)))
	var last := _tile_at(Vector2(maxf(la.x, lb.x), maxf(la.z, lb.z)))
	for z in range(first.y - margin, last.y + margin + 1):
		for x in range(first.x - margin, last.x + margin + 1):
			var tile_region: NavigationRegion3D = _tile_regions.get(Vector2i(x, z))
			if tile_region != null:
				found.append(tile_region.get_rid())
	return found

## --- Footprints ---

## Everything solid in reach of `area` (region-local): buildings as finished
## carves in `carves`, trees as [shape, transform] in `trees` for the worker
## to carve.
func _collect_obstructions(carves: Array, trees: Array, area: AABB) -> void:
	## Obstruction outlines share the source geometry's space, and that came
	## out of the region's own navmesh — which is region-local, and the region
	## is not sitting at the origin.
	var to_local: Transform3D = _region.global_transform.affine_inverse()
	var reach: AABB = area.grow(BLOCKER_REACH)
	for group in BLOCKER_GROUPS:
		for node in get_tree().get_nodes_in_group(group):
			var body := node as CollisionObject3D
			if _is_blocking(body) and _within(reach, to_local * body.global_position):
				_add_body_obstructions(carves, body, to_local)
	## Trees have no shape (see Forest): each carves the upright cylinder its
	## old collision shape was.
	if Forest.active != null:
		var trunk_area: AABB = area.grow(1.0)
		var centre: Vector3 = _region.global_transform * area.get_center()
		var radius: float = Vector2(area.size.x, area.size.z).length() * 0.5 + 1.0
		for tree in Forest.active.trees_in_circle(centre, radius):
			if not _within(trunk_area, to_local * tree.global_position):
				continue
			var cylinder_transform: Transform3D = to_local * Transform3D(Basis(), tree.global_position + Vector3(0.0, TRUNK_HEIGHT * 0.5, 0.0))
			trees.append([_trunk_shape(tree.trunk_radius), cylinder_transform])

## Flat containment: heights are the bake's business.
static func _within(area: AABB, local: Vector3) -> bool:
	return local.x >= area.position.x and local.x <= area.end.x and local.z >= area.position.z and local.z <= area.end.z

func _trunk_shape(radius: float) -> CylinderShape3D:
	if not _trunk_shapes.has(radius):
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = TRUNK_HEIGHT
		_trunk_shapes[radius] = shape
	return _trunk_shapes[radius]

## Carving a Gate's two posts (rather than its NavigationObstacle3D, which is
## a single deliberately tiny radius sitting in the middle of the archway)
## leaves the gateway open: the posts are the only solid parts of it, so the
## navmesh keeps roughly a metre of corridor between them and paths thread it
## instead of walking around the wall.
func _add_body_obstructions(carves: Array, body: CollisionObject3D, to_local: Transform3D) -> void:
	for owner_id in body.get_shape_owners():
		if body.is_shape_owner_disabled(owner_id):
			continue
		var shape_transform: Transform3D = to_local * body.global_transform * body.shape_owner_get_transform(owner_id)
		for i in body.shape_owner_get_shape_count(owner_id):
			_add_shape_obstruction(carves, body.shape_owner_get_shape(owner_id, i), shape_transform)

## Appends [outline, bottom, height] for add_projected_obstruction. Pure (no
## nodes), so the worker thread can carve with it too.
func _add_shape_obstruction(carves: Array, shape: Shape3D, shape_transform: Transform3D) -> void:
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
		carves.append([carve, min_y - CARVE_FLOOR_MARGIN, (max_y - min_y) + CARVE_FLOOR_MARGIN])

## Points whose convex hull (in XZ) and vertical span describe the shape well
## enough to carve with. Round shapes get a real ring rather than their
## bounding box, which matters for a resource node: over-carving a Gold
## Deposit's corners would push the nearest walkable ground past the
## gather_range villagers stop at, and they would never reach it.
##
## ConcavePolygonShape3D (the terrain) is deliberately absent — it is already
## the baseline geometry, and it is never on a body in BLOCKER_GROUPS.
static func _shape_points(shape: Shape3D) -> PackedVector3Array:
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

static func _box_points(half: Vector3) -> PackedVector3Array:
	var points := PackedVector3Array()
	for x: float in [-half.x, half.x]:
		for y: float in [-half.y, half.y]:
			for z: float in [-half.z, half.z]:
				points.append(Vector3(x, y, z))
	return points

static func _ring_points(radius: float, half_height: float) -> PackedVector3Array:
	var points := PackedVector3Array()
	for i in CIRCLE_SEGMENTS:
		var angle: float = TAU * float(i) / float(CIRCLE_SEGMENTS)
		var offset := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		points.append(offset + Vector3(0.0, -half_height, 0.0))
		points.append(offset + Vector3(0.0, half_height, 0.0))
	return points
