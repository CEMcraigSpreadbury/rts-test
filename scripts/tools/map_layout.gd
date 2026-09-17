@tool
class_name MapLayout
extends RefCounted
## The data half of MapGenerator: a height field on cell corners (rolling
## hills, organic plateaus and valleys joined by ramps, flattened pads, coast,
## lakes and rivers), decal corner fields, and every object placement, all
## derived from the seed.
##
## With MapGenerator.import_heightmap set, the heights come from that file
## instead (see MapHeightmapImport) and none of the procedural terrain is built.
## Imported maps are rarely rotationally symmetric, so bases come from the
## file's start positions (or the most spread-out flat spots) and per-player
## content is placed directly around each real base rather than stamped.
##
## Everything is authored in player 0's slice (the "template" frame) and
## stamped into the map at one or more player rotations, listed in the item's
## `copies`. With MapGenerator.symmetric on, each item is stamped for every
## player, so every base gets the same terrain, resources and distances, and
## placements are only accepted if every copy is valid. With it off, each
## player rolls their own items, stamped only into their own slice: the map is
## unique, and fairness comes from equal counts and parameter ranges, equal base
## distances and flat base areas, and gold and objectives being placed for
## every player or none (objectives at matching distances from each base).

const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const TC_OFFSET: Vector2 = Vector2(-4.0, 4.0)
const SPAWN_ATTEMPTS: int = 80
const GOLD_RADIUS: float = 1.7
const PROP_RADIUS: float = 0.6
const CLIFF_CLEARANCE_TREES: int = 3
const CLIFF_CLEARANCE_OBJECTS: int = 2
## A cell whose corners differ by more than this is a cliff face. Hills and
## ramps stay well under it (a ramp's diagonal rise is ramp_slope * sqrt(2)).
const CLIFF_RISE: float = 0.9
## Neighbouring cells further apart in height than this aren't walkable
## between, for the connectivity check.
const WALK_STEP: float = 0.8
## Flat ground kept at each end of a ramp.
const RAMP_LANDING: float = 1.5
## Distance flattened pads take to ease back into the surrounding terrain.
const BASE_FLAT_FALLOFF: float = 6.0
const POCKET_FALLOFF: float = 4.0
## Most height difference allowed under a footprint, per kind of object.
const RISE_OBJECTIVE: float = 0.5
const RISE_GOLD: float = 0.7
const RISE_TREE: float = 0.9
const RISE_PROP: float = 1.2
## Land is kept at least this far above the water unless the coast, a lake or a
## river deliberately takes it under.
const DRY_MARGIN: float = 0.5
## Water shallower than this is walkable (and navigable); deeper blocks.
const WADE_DEPTH: float = 0.3
## A ford's bed sits this far under the water: shallow enough to walk.
const FORD_DEPTH: float = 0.12
## Spacing of the points a river's course is sampled at.
const RIVER_STEP: float = 3.0
## The terrain always reaches at least this far past the map square on every
## side (MapTerrainBuilder.zones_size), room for the land to drop into the sea.
const OUTER_PADDING: int = 8
## Forest (non-coast) edges: the land ends at a wobbly line this far inside the
## map boundary, plus up to FOREST_EDGE_WOBBLE of the border width more, then
## drops steeply (FOREST_BANK_SLOPE per metre above water, FOREST_BANK_DROP
## metres to the sea floor below it).
const FOREST_EDGE_INSET: float = 1.5
const FOREST_EDGE_WOBBLE: float = 0.55
const FOREST_BANK_SLOPE: float = 0.8
const FOREST_BANK_DROP: float = 3.0
## Objects and pads need their ground at least this far above the water.
const PLACE_ABOVE_WATER: float = 0.25
## Unsymmetric maps: how far (as a fraction) each player's copy of an objective
## may differ from the first player's in distance from its own base.
const OBJECTIVE_DISTANCE_TOLERANCE: float = 0.15

var size: int
var half: float
var players: int
var symmetric: bool
var imported: bool
var water_level: float
## Horizontal room a ramp needs for the tallest possible climb, landings included.
var ramp_length: float
## (size + 1)^2 corner heights, row by row; corner (i, j) sits at (i - half, j - half).
var heights := PackedFloat32Array()
## Per cell: highest minus lowest of its four corners.
var cell_rise := PackedFloat32Array()
var cliff := PackedByteArray()
var playable := PackedByteArray()
var dirt := PackedByteArray()
var grass := PackedByteArray()

var base_centres: Array[Vector2] = []
var spawn_positions: Array[Vector3] = []
## {kind: StringName, scene: PackedScene, position: Vector3, yaw: float, scale: float, props: Dictionary}
var objects: Array[Dictionary] = []

var _gen: MapGenerator
var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
var _hill_noise := FastNoiseLite.new()
var _outline_noise := FastNoiseLite.new()
var _coast_noise := FastNoiseLite.new()
## Phases of the waves deciding which stretches of the map edge are coast.
var _coast_phases := Vector2.ZERO
var _angle0: float
var _step: float
## Every planned item below is in the template frame with `copies`: the player
## rotations it is stamped at. Items marked `symmetric` (the centre site and
## its plateau) sit on the rotation centre and are stamped once, unrotated.
## {centre, half: Vector2, radius, angle, symmetric, steps: Array[float] (height change per tier), copies}
var _features: Array[Dictionary] = []
## Ramps are in world space: {outer, inner, entrance, landing, tier, copy, on_centre}.
var _ramps: Array[Dictionary] = []
## {pos, scene, symmetric, footprint, props, copies}
var _objective_sites: Array[Dictionary] = []
## Flattened spots to build on away from base: {pos, radius, copies}.
var _pockets: Array[Dictionary] = []
## Lakes and ponds: {pos, radius, copies}.
var _lakes: Array[Dictionary] = []
## Rivers: {points: PackedVector2Array, arcs: PackedFloat32Array (distance along
## the river at each point), width, fords: Array[float] (arc positions), copies},
## running from the map edge inland.
var _rivers: Array[Dictionary] = []
## Decal strokes {a, b, width, copies}.
var _paths: Array[Dictionary] = []
var _dirt_shapes: Array[Dictionary] = []
var _grass_shapes: Array[Dictionary] = []
var _cliff_distance := PackedInt32Array()
## Spatial hash of placed bodies: {pos, radius, gap, group, solid}, world space.
var _bodies: Array[Dictionary] = []
var _hash: Dictionary = {}
var _next_group: int = 1
var _max_body_reach: float = 0.0
var _reach_cache: Dictionary = {}
## MapHeightmapImport.load_source result when importing.
var _import: Dictionary = {}

func _init(generator: MapGenerator) -> void:
	_gen = generator

func generate() -> bool:
	size = _gen.map_size
	half = size * 0.5
	players = _gen.player_count
	imported = not _gen.import_heightmap.is_empty()
	symmetric = _gen.symmetric and not imported
	water_level = _gen.water_level
	_step = TAU / players
	_angle0 = deg_to_rad(_gen.layout_rotation_degrees)
	_rng.seed = _gen.map_seed
	_noise.seed = _gen.map_seed
	_noise.frequency = 0.09
	_noise.fractal_octaves = 2
	_hill_noise.seed = _gen.map_seed + 101
	_hill_noise.frequency = _gen.hill_frequency
	_hill_noise.fractal_octaves = 3
	_outline_noise.seed = _gen.map_seed + 202
	_outline_noise.frequency = 0.06
	_outline_noise.fractal_octaves = 2
	_coast_noise.seed = _gen.map_seed + 303
	_coast_noise.frequency = 0.04
	_coast_noise.fractal_octaves = 2
	var coast_rng := RandomNumberGenerator.new()
	coast_rng.seed = _gen.map_seed + 404
	_coast_phases = Vector2(coast_rng.randf() * TAU, coast_rng.randf() * TAU)
	var tallest: float = maxf(_gen.plateau_height_range.y, _gen.valley_depth_range.y)
	ramp_length = maxf(tallest / _gen.ramp_slope, _gen.cliff_width + 2.0) + RAMP_LANDING * 2.0

	var cells: int = size * size
	playable.resize(cells)
	for z in size:
		for x in size:
			playable[z * size + x] = 1 if is_playable(cell_centre(Vector2i(x, z))) else 0

	if imported:
		_import = MapHeightmapImport.load_source(_gen.import_heightmap, _gen.import_image_water_height)
		if _import.has("error"):
			push_error("MapGenerator: " + _import.error)
			return false
		_import_heights()
		_compute_cells()
		_place_imported_bases()
	else:
		_place_bases()
	_plan_objectives()
	_plan_rivers()
	_plan_features()
	_plan_pockets()
	_plan_lakes()
	if not imported:
		_build_hills()
	_flatten_building_ground()
	_add_features()
	_place_ramps()
	_flatten_objectives()
	if not imported:
		_shape_coast()
		_carve_lakes()
		_carve_rivers()
	_compute_cells()
	for i in spawn_positions.size():
		spawn_positions[i].y = surface_height(Vector2(spawn_positions[i].x, spawn_positions[i].z))
	_place_objectives()
	_plan_paths()
	_place_base_resources()
	_place_neutral_resources()
	_plan_decals()
	_place_forest_clusters()
	_place_edge_forest()
	_place_border_trees()
	_place_props()
	_rasterize_decals()
	_ensure_connected()
	return true

## --- Geometry helpers ---

func index(c: Vector2i) -> int:
	return c.y * size + c.x

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < size and c.y < size

func cell_centre(c: Vector2i) -> Vector2:
	return Vector2(c.x - half + 0.5, c.y - half + 0.5)

func cell_at(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x + half), floori(p.y + half))

func rot(p: Vector2, k: int) -> Vector2:
	return p.rotated(k * _step)

func is_playable_cell(c: Vector2i) -> bool:
	return in_bounds(c) and playable[index(c)] == 1

func _all_copies() -> Array:
	var copies: Array = []
	for k in players:
		copies.append(k)
	return copies

## One entry per item a count setting ("per player") produces, as
## {copies: rotations to stamp at, base: the base index it belongs to}.
## Imported maps place each player's items unrotated around their own base.
func _placement_slots() -> Array:
	var slots: Array = []
	if imported:
		for k in players:
			slots.append({copies = [0], base = k})
	else:
		for copies in _copy_sets():
			slots.append({copies = copies, base = copies[0]})
	return slots

## Symmetric maps author one item stamped for everyone, others one per player.
func _copy_sets() -> Array:
	if symmetric:
		return [_all_copies()]
	var sets: Array = []
	for k in players:
		sets.append([k])
	return sets

## Signed distance (in metres) from p to the playable boundary: positive inside.
## Along coast the boundary is the waterline, pulled inland by a wobble.
func edge_distance(p: Vector2) -> float:
	var limit: float = half - _gen.border_width
	var best: float = INF
	for k in players:
		var q: Vector2 = rot(p, k)
		best = minf(best, limit - maxf(absf(q.x), absf(q.y)))
	var coast: float = coast_weight(p)
	if coast > 0.0:
		best -= coast * _gen.coast_wobble * clampf(_rotation_noise(_coast_noise, p) * 0.6 + 0.5, 0.0, 1.0)
	return best

## How much the map edge nearest p is coast (1) rather than forest border (0).
## Two waves around the map, repeating once per player on symmetric maps so
## every slice matches; coast_fraction moves the threshold.
func coast_weight(p: Vector2) -> float:
	if imported or _gen.coast_fraction <= 0.0:
		return 0.0
	var wave: float
	if symmetric:
		var angle: float = p.angle() * players
		wave = (sin(angle + _coast_phases.x) + 0.6 * sin(angle * 2.0 + _coast_phases.y)) / 1.6
	else:
		wave = (sin(p.angle() * 2.0 + _coast_phases.x) + 0.6 * sin(p.angle() * 3.0 + _coast_phases.y)) / 1.6
	var threshold: float = 1.0 - 2.0 * _gen.coast_fraction
	return smoothstep(threshold - 0.15, threshold + 0.15, wave)

## Signed distance from p to the map's outer boundary (the same rotated-square
## shape edge_distance uses, without the border or coast): positive inside.
func _boundary_distance(p: Vector2) -> float:
	var best: float = INF
	for k in players:
		var q: Vector2 = rot(p, k)
		best = minf(best, half - maxf(absf(q.x), absf(q.y)))
	return best

func is_deep_water(c: Vector2i) -> bool:
	return water_level - _cell_height(c) > WADE_DEPTH

func is_playable(p: Vector2) -> bool:
	return edge_distance(p) > 0.0

func _edge_distance_along(angle: float) -> float:
	var bucket: int = posmod(roundi(rad_to_deg(angle) * 2.0), 720)
	if _reach_cache.has(bucket):
		return _reach_cache[bucket]
	var direction := Vector2.from_angle(angle)
	var r: float = 0.0
	while r < half and is_playable(direction * (r + 0.5)):
		r += 0.5
	_reach_cache[bucket] = r
	return r

## Corners outside the grid take the nearest edge corner's height and sink to
## the sea floor within OUTER_PADDING, so every edge of the map (coast or forest
## border) falls away into the sea instead of ending in a cut-off wall.
func corner_height(corner: Vector2i) -> float:
	var c: Vector2i = corner.clamp(Vector2i.ZERO, Vector2i(size, size))
	var h: float = heights[c.y * (size + 1) + c.x]
	if c == corner:
		return h
	var outside: float = (Vector2(corner) - Vector2(c)).length()
	var sea_floor: float = water_level - _gen.sea_depth
	return lerpf(h, minf(h, sea_floor), smoothstep(0.0, minf(_gen.shore_drop, OUTER_PADDING - 1.0), outside))

func surface_height(p: Vector2) -> float:
	var x: float = clampf(p.x + half, 0.0, size)
	var z: float = clampf(p.y + half, 0.0, size)
	var i: int = mini(floori(x), size - 1)
	var j: int = mini(floori(z), size - 1)
	var fx: float = x - i
	var fz: float = z - j
	var corners: int = size + 1
	var top: float = lerpf(heights[j * corners + i], heights[j * corners + i + 1], fx)
	var bottom: float = lerpf(heights[(j + 1) * corners + i], heights[(j + 1) * corners + i + 1], fx)
	return lerpf(top, bottom, fz)

func _cell_height(c: Vector2i) -> float:
	var corners: int = size + 1
	var top: int = c.y * corners + c.x
	return (heights[top] + heights[top + 1] + heights[top + corners] + heights[top + corners + 1]) * 0.25

## A template-frame point in player 0's slice, scaled to how far the playable
## ground reaches in player k's slice (the coast differs between slices on
## unsymmetric maps).
func _rand_in_sector(r_min: float, r_max: float, k: int = 0) -> Vector2:
	if imported:
		return _rand_near_base(k)
	var angle: float = _angle0 + _rng.randf_range(-0.5, 0.5) * _step
	var reach: float = _edge_distance_along(angle + k * _step)
	return Vector2.from_angle(angle) * _rng.randf_range(r_min, r_max) * reach

func _noise01(p: Vector2) -> float:
	return _noise.get_noise_2dv(p) * 0.5 + 0.5

## Noise that is identical under every player rotation: the sum over all of
## them, rescaled so its spread doesn't shrink as player count grows.
func _symmetric_noise(noise: FastNoiseLite, p: Vector2) -> float:
	var total: float = 0.0
	for k in players:
		total += noise.get_noise_2dv(rot(p, k))
	return total / sqrt(float(players))

## Noise for map-wide terrain: rotation-symmetric on symmetric maps.
func _rotation_noise(noise: FastNoiseLite, p: Vector2) -> float:
	return _symmetric_noise(noise, p) if symmetric else noise.get_noise_2dv(p)

## Imported maps: a playable point closer to base k than to any other.
func _rand_near_base(k: int) -> Vector2:
	for attempt in 40:
		var p := Vector2(_rng.randf_range(-half, half), _rng.randf_range(-half, half))
		if is_playable(p) and _nearest_base(p) == k:
			return p
	return base_centres[k]

func _nearest_base(p: Vector2) -> int:
	var nearest: int = 0
	for k in base_centres.size():
		if p.distance_squared_to(base_centres[k]) < p.distance_squared_to(base_centres[nearest]):
			nearest = k
	return nearest

## Whether a candidate point belongs to this placement slot's share of the map:
## its rotational sector, or on imported maps its nearest base.
func _in_slot_region(p: Vector2, slot: Dictionary) -> bool:
	if imported:
		return _nearest_base(p) == slot.base
	return absf(wrapf(p.angle() - _angle0, -PI, PI)) <= _step * 0.5

## --- Heightmap import ---

## Resamples the source onto the corner grid: its water height lands on
## water_level and its full height range spans import_height_range metres.
func _import_heights() -> void:
	var corners: int = size + 1
	heights.resize(corners * corners)
	var span: float = maxf(float(_import.high) - float(_import.low), 0.0001)
	var scale: float = _gen.import_height_range / span
	for j in corners:
		for i in corners:
			var value: float = MapHeightmapImport.sample(_import, Vector2(float(i) / size, float(j) / size))
			heights[j * corners + i] = water_level + (value - float(_import.water)) * scale
	for pass_index in _gen.import_smoothing:
		var smoothed: PackedFloat32Array = heights.duplicate()
		for j in range(1, corners - 1):
			for i in range(1, corners - 1):
				var total: float = 0.0
				for dj in range(-1, 2):
					for di in range(-1, 2):
						total += heights[(j + dj) * corners + i + di]
				smoothed[j * corners + i] = total / 9.0
		heights = smoothed

func _uv_to_world(uv: Vector2) -> Vector2:
	return Vector2(uv.x * size - half, uv.y * size - half)

## Bases from the file's start positions (in order), each nudged to the nearest
## ground a base fits on; missing ones are filled with the flat spots of the
## largest walkable area that lie furthest from the bases already chosen.
func _place_imported_bases() -> void:
	var region: PackedByteArray = _largest_walkable_region()
	var starts: Array = _import.get("start_positions", [])
	var chosen: Array[Vector2] = []
	for uv in starts:
		if chosen.size() >= players:
			break
		var spot: Variant = _nearest_base_spot(_uv_to_world(uv), region)
		if spot != null:
			chosen.append(spot)
	if chosen.size() < players:
		var candidates: Array[Vector2] = []
		for z in range(0, size, 4):
			for x in range(0, size, 4):
				var p: Vector2 = cell_centre(Vector2i(x, z))
				if region[index(Vector2i(x, z))] == 1 and _base_spot_ok(p):
					candidates.append(p)
		while chosen.size() < players and not candidates.is_empty():
			var best: Vector2 = candidates[0]
			var best_distance: float = -1.0
			for p in candidates:
				var nearest: float = p.length() if chosen.is_empty() else INF
				for c in chosen:
					nearest = minf(nearest, p.distance_to(c))
				if nearest > best_distance:
					best_distance = nearest
					best = p
			chosen.append(best)
			candidates.erase(best)
	if chosen.size() < players:
		push_warning("MapGenerator: the heightmap only has room for %d of %d bases." % [chosen.size(), players])
	for centre in chosen:
		base_centres.append(centre)
		var spawn: Vector2 = centre - TC_OFFSET
		spawn_positions.append(Vector3(spawn.x, 0.0, spawn.y))
		_add_body(centre, _gen.base_clear_radius, 0.0, _new_group(), false)
	players = base_centres.size()

func _base_spot_ok(p: Vector2) -> bool:
	return _footprint_ok(p, _gen.base_clear_radius, 1.5, 2)

func _nearest_base_spot(p: Vector2, region: PackedByteArray) -> Variant:
	var r: float = 0.0
	while r <= 30.0:
		var count: int = 1 if r == 0.0 else maxi(8, int(TAU * r / 2.0))
		for i in count:
			var q: Vector2 = p + Vector2.from_angle(TAU * i / count) * r
			var c: Vector2i = cell_at(q)
			if in_bounds(c) and region[index(c)] == 1 and _base_spot_ok(q):
				return q
		r += 2.0
	return null

## 1 for cells in the biggest area units can walk around without crossing
## cliffs or deep water.
func _largest_walkable_region() -> PackedByteArray:
	var label := PackedInt32Array()
	label.resize(size * size)
	label.fill(-1)
	var best_label: int = -1
	var best_count: int = 0
	var next_label: int = 0
	for start in size * size:
		var start_cell := Vector2i(start % size, start / size)
		if label[start] != -1 or not _walkable_cell(start_cell):
			continue
		var frontier: Array[Vector2i] = [start_cell]
		label[start] = next_label
		var head: int = 0
		while head < frontier.size():
			var c: Vector2i = frontier[head]
			head += 1
			for d in DIRS:
				var n: Vector2i = c + d
				if in_bounds(n) and label[index(n)] == -1 and _walkable_cell(n) and absf(_cell_height(c) - _cell_height(n)) <= WALK_STEP:
					label[index(n)] = next_label
					frontier.append(n)
		if frontier.size() > best_count:
			best_count = frontier.size()
			best_label = next_label
		next_label += 1
	var region := PackedByteArray()
	region.resize(size * size)
	for i in size * size:
		region[i] = 1 if label[i] == best_label else 0
	return region

func _walkable_cell(c: Vector2i) -> bool:
	return is_playable_cell(c) and cliff[index(c)] == 0 and not is_deep_water(c)

## --- Bases ---

## Bases always sit at the same distance from the centre, in every mode, so
## the shortest reach of any slice decides it.
func _place_bases() -> void:
	var reach: float = INF
	for k in players:
		reach = minf(reach, _edge_distance_along(_angle0 + k * _step))
	var base0: Vector2 = Vector2.from_angle(_angle0) * _gen.spawn_distance * reach
	for k in players:
		var centre: Vector2 = rot(base0, k)
		base_centres.append(centre)
		var spawn: Vector2 = centre - TC_OFFSET
		spawn_positions.append(Vector3(spawn.x, 0.0, spawn.y))
		_add_body(centre, _gen.base_clear_radius, 0.0, _new_group(), false)

## --- Objectives, plateaus & valleys ---

## Width of the ledge a lower tier keeps around the tier above it: room for
## that tier's ramp and a little walking space.
func _tier_ring() -> float:
	return ramp_length + 3.0

func _objective_plateau_half() -> float:
	return _gen.objective_clear_radius + ramp_length * 0.5 + 2.5 + (_gen.objective_plateau_tiers - 1) * _tier_ring()

func _plan_objectives() -> void:
	var scenes: Array[PackedScene] = []
	scenes.assign(_gen.objective_scenes.filter(func(s): return s != null))
	var on_plateau: bool = _gen.objectives_on_plateaus and not imported
	var footprint: float = _objective_plateau_half() * 1.3 if on_plateau else _gen.objective_clear_radius
	var centre_scene: PackedScene = null
	match _gen.centre_site:
		MapGenerator.CentreSite.OBJECTIVE:
			centre_scene = scenes[_rng.randi() % scenes.size()] if not scenes.is_empty() else null
		MapGenerator.CentreSite.SHRINE:
			centre_scene = _gen.shrine_scene
	var centre: Vector2 = Vector2.ZERO
	if imported and centre_scene != null:
		## The middle of an imported map may be water or cliff: use the nearest
		## ground an objective fits on.
		var found: Variant = null
		var r: float = 0.0
		while found == null and r <= half * 0.5:
			var count: int = 1 if r == 0.0 else maxi(8, int(TAU * r / 3.0))
			for i in count:
				var q: Vector2 = Vector2.from_angle(TAU * i / count) * r
				if _footprint_ok(q, _gen.objective_clear_radius, 1.5, 1):
					found = q
					break
			r += 3.0
		if found == null:
			centre_scene = null
		else:
			centre = found
	if centre_scene != null:
		_objective_sites.append({pos = centre, scene = centre_scene, symmetric = true, footprint = footprint, props = {favour_per_second = _gen.centre_favour_per_second}, copies = [0]})
	var requests: Array[Dictionary] = []
	if not scenes.is_empty():
		for j in _gen.objectives_per_player:
			requests.append({scene = scenes[_rng.randi() % scenes.size()], props = {}})
	if _gen.shrine_scene != null:
		for j in _gen.shrines_per_player:
			requests.append({scene = _gen.shrine_scene, props = {roll_group = StringName("shrine_%d" % j)}})
	for request in requests:
		## Every player gets this objective or nobody does, and on unsymmetric
		## maps each copy stands about as far from its own base as the first.
		var added: Array[Dictionary] = []
		var first_distance: float = -1.0
		for slot in _placement_slots():
			var copies: Array = slot.copies
			var placed: bool = false
			for attempt in 300:
				var p: Vector2 = _rand_in_sector(0.25, 0.9, slot.base)
				if edge_distance(rot(p, copies[0])) < footprint + 4.0:
					continue
				if not _clear_of_bases(p, _gen.objective_min_base_distance, copies):
					continue
				if not _clear_of_sites(p, footprint + 6.0, copies):
					continue
				if _self_copies_too_close(p, footprint * 2.0 + 6.0, copies):
					continue
				## Imported terrain already exists at this point: only take ground
				## flat enough for the objective's small levelled pad to finish.
				if imported and not _footprint_ok(p, _gen.objective_clear_radius, 1.2, 2):
					continue
				var distance: float = rot(p, copies[0]).distance_to(base_centres[slot.base])
				if first_distance >= 0.0 and absf(distance - first_distance) > first_distance * OBJECTIVE_DISTANCE_TOLERANCE:
					continue
				var site := {pos = p, scene = request.scene, symmetric = false, footprint = footprint, props = request.props, copies = copies}
				_objective_sites.append(site)
				added.append(site)
				if first_distance < 0.0:
					first_distance = distance
				placed = true
				break
			if not placed:
				for site in added:
					_objective_sites.erase(site)
				push_warning("MapGenerator: no room for every objective/shrine — lower the per-player counts or Objective Min Base Distance, or use a bigger map.")
				break

func _clear_of_bases(p: Vector2, min_distance: float, copies: Array) -> bool:
	for k in copies:
		var q: Vector2 = rot(p, k)
		for base in base_centres:
			if q.distance_to(base) < min_distance:
				return false
	return true

func _clear_of_sites(p: Vector2, extra: float, copies: Array) -> bool:
	for k in copies:
		var q: Vector2 = rot(p, k)
		for site in _objective_sites:
			for sk in site.copies:
				if q.distance_to(rot(site.pos, sk)) < site.footprint + extra:
					return false
	return true

func _self_copies_too_close(p: Vector2, min_distance: float, copies: Array) -> bool:
	for a in copies:
		for b in copies:
			if a < b and rot(p, a).distance_to(rot(p, b)) < min_distance:
				return true
	return false

## Height change per tier. Objectives always stand on raised ground; other
## features are sometimes sunk into valleys instead.
func _roll_steps(tiers: int, allow_valley: bool) -> Array[float]:
	var sinks: bool = allow_valley and _rng.randf() < _gen.valley_chance
	var span: Vector2 = _gen.valley_depth_range if sinks else _gen.plateau_height_range
	var total: float = _rng.randf_range(span.x, span.y)
	var steps: Array[float] = []
	for t in tiers:
		steps.append(maxf(total / tiers, 1.2) * (-1.0 if sinks else 1.0))
	return steps

func _plan_features() -> void:
	if imported:
		return
	if _gen.objectives_on_plateaus:
		var h: float = _objective_plateau_half()
		for site in _objective_sites:
			var feature := {centre = site.pos, half = Vector2(h, h), radius = 3.0, angle = _rng.randf() * TAU, symmetric = site.symmetric, steps = _roll_steps(_gen.objective_plateau_tiers, false), copies = site.copies}
			if site.symmetric:
				feature.half = Vector2(h, h) * 1.05
				feature.radius = feature.half.x
			_features.append(feature)
	var min_half: float = maxf(_gen.plateau_half_size.x, ramp_length * 0.5 + 3.0 + (_gen.plateau_tiers - 1) * _tier_ring())
	var max_half: float = maxf(_gen.plateau_half_size.y, min_half)
	for slot in _placement_slots():
		var copies: Array = slot.copies
		for n in _gen.plateaus_per_player:
			var placed: bool = false
			for attempt in 300:
				var extents := Vector2(_rng.randf_range(min_half, max_half), _rng.randf_range(min_half, max_half))
				var reach: float = extents.length() + _gen.plateau_outline_noise
				var p: Vector2 = _rand_in_sector(0.2, 0.95, slot.base)
				if edge_distance(rot(p, copies[0])) < reach + 6.0:
					continue
				if not _clear_of_bases(p, _gen.base_clear_radius + reach + 10.0, copies):
					continue
				if not _clear_of_sites(p, reach + 5.0, copies):
					continue
				if not _clear_of_features(p, reach, copies):
					continue
				if not _clear_of_rivers(p, reach, copies):
					continue
				if _self_copies_too_close(p, reach * 2.0 + 6.0, copies):
					continue
				_features.append({centre = p, half = extents, radius = minf(extents.x, extents.y) * _rng.randf_range(0.3, 0.8), angle = _rng.randf() * TAU, symmetric = false, steps = _roll_steps(_gen.plateau_tiers, true), copies = copies})
				placed = true
				break
			if not placed:
				push_warning("MapGenerator: no room for extra plateau/valley %d." % (n + 1))

func _base_flat_reach() -> float:
	return maxf(_gen.base_flat_radius, _gen.base_clear_radius + 2.0) + BASE_FLAT_FALLOFF

## Spots flattened for building on, away from bases, objectives and features.
## Each gets a non-solid body so trees and gold leave the space free.
func _plan_pockets() -> void:
	if imported:
		return
	for slot in _placement_slots():
		var copies: Array = slot.copies
		for n in _gen.building_pockets_per_player:
			var placed: bool = false
			for attempt in 200:
				var radius: float = _rng.randf_range(_gen.building_pocket_radius.x, maxf(_gen.building_pocket_radius.y, _gen.building_pocket_radius.x))
				var reach: float = radius + POCKET_FALLOFF
				var p: Vector2 = _rand_in_sector(0.2, 0.9, slot.base)
				if edge_distance(rot(p, copies[0])) < reach + 4.0:
					continue
				if not _clear_of_bases(p, _base_flat_reach() + reach, copies):
					continue
				if not _clear_of_sites(p, reach + 4.0, copies):
					continue
				if not _clear_of_features(p, reach, copies):
					continue
				if not _clear_of_pockets(p, reach, copies):
					continue
				if not _clear_of_rivers(p, reach, copies):
					continue
				if _self_copies_too_close(p, reach * 2.0 + 4.0, copies):
					continue
				_pockets.append({pos = p, radius = radius, copies = copies})
				for k in copies:
					_add_body(rot(p, k), radius, 0.0, _new_group(), false)
				placed = true
				break
			if not placed:
				push_warning("MapGenerator: no room for building pocket %d." % (n + 1))

## Lakes and ponds, kept off bases, objectives, features, pockets and each
## other. Each gets a non-solid body so trees and gold stay out of the water.
func _plan_lakes() -> void:
	if imported:
		return
	for slot in _placement_slots():
		var copies: Array = slot.copies
		for n in _gen.lakes_per_player:
			var placed: bool = false
			for attempt in 200:
				var radius: float = _rng.randf_range(_gen.lake_radius.x, maxf(_gen.lake_radius.y, _gen.lake_radius.x))
				var reach: float = radius * 1.35
				var p: Vector2 = _rand_in_sector(0.15, 0.9, slot.base)
				if edge_distance(rot(p, copies[0])) < reach + 4.0:
					continue
				if not _clear_of_bases(p, _gen.base_flat_radius + reach, copies):
					continue
				## Objective plateaus are covered by the feature check; only the
				## objective's own clearing matters here.
				if not _clear_of_objective_pads(p, reach + 4.0, copies):
					continue
				if not _clear_of_features(p, reach, copies):
					continue
				if not _clear_of_pockets(p, reach, copies):
					continue
				if not _clear_of_lakes(p, reach, copies):
					continue
				if not _clear_of_rivers(p, reach, copies):
					continue
				if _gen.paths_to_centre and _near_centre_route(p, reach + _gen.path_width, copies):
					continue
				if _self_copies_too_close(p, reach * 2.0 + 8.0, copies):
					continue
				_lakes.append({pos = p, radius = radius, copies = copies})
				for k in copies:
					_add_body(rot(p, k), reach, 0.0, _new_group(), false)
				placed = true
				break
			if not placed:
				push_warning("MapGenerator: no room for lake %d." % (n + 1))

## --- Rivers ---

## Each river starts past the map edge between two bases (at the most coastal
## angle there, so it tends to run out to sea) and winds inland toward the
## middle, stopping river_length of the way. Rejected if its course comes near
## a base, an objective, a base-to-centre route, another river, or its own
## rotated copies.
func _plan_rivers() -> void:
	if imported:
		return
	for slot in _placement_slots():
		var copies: Array = slot.copies
		for n in _gen.rivers_per_player:
			var placed: bool = false
			for attempt in 60:
				var river: Dictionary = _roll_river(n, attempt, copies)
				if river.is_empty() or not _river_valid(river):
					continue
				_rivers.append(river)
				for k in copies:
					for p in river.points:
						_add_body(rot(p, k), river.width * 0.5 + 2.0, 0.0, _new_group(), false)
				placed = true
				break
			if not placed:
				push_warning("MapGenerator: no room for river %d." % (n + 1))

func _roll_river(n: int, attempt: int, copies: Array) -> Dictionary:
	var k: int = copies[0]
	var sector: float = _angle0 + _step * 0.5
	var spread: float = _step * 0.3
	var best_angle: float = sector + _rng.randf_range(-spread, spread)
	var best_coast: float = -1.0
	for i in 8:
		var angle: float = sector + _rng.randf_range(-spread, spread)
		var coast: float = coast_weight(Vector2.from_angle(angle + k * _step) * half)
		if coast > best_coast + 0.05:
			best_coast = coast
			best_angle = angle
	var reach: float = _edge_distance_along(best_angle + k * _step)
	if reach <= 0.0:
		return {}
	var start: Vector2 = Vector2.from_angle(best_angle) * (reach + _gen.border_width + 4.0)
	var finish: Vector2 = Vector2.from_angle(best_angle + _rng.randf_range(-0.3, 0.3)) * reach * (1.0 - _gen.river_length)
	var length: float = start.distance_to(finish)
	var count: int = maxi(2, ceili(length / RIVER_STEP))
	var across: Vector2 = (finish - start).normalized().orthogonal()
	var phase: float = _rng.randf_range(0.0, 1000.0) + n * 137.0 + attempt * 11.0
	var points := PackedVector2Array()
	var arcs := PackedFloat32Array()
	for i in count + 1:
		var t: float = float(i) / count
		var wander: float = _outline_noise.get_noise_2d(t * length * 0.08, phase) * _gen.river_meander * smoothstep(0.0, 0.25, t)
		var p: Vector2 = start.lerp(finish, t) + across * wander
		arcs.append(0.0 if points.is_empty() else arcs[arcs.size() - 1] + points[points.size() - 1].distance_to(p))
		points.append(p)
	var fords: Array[float] = []
	var total: float = arcs[arcs.size() - 1]
	for f in _gen.fords_per_river:
		fords.append(total * lerpf(0.3, 0.75, (f + 1.0) / (_gen.fords_per_river + 1.0)))
	return {points = points, arcs = arcs, width = _rng.randf_range(_gen.river_width.x, maxf(_gen.river_width.y, _gen.river_width.x)), fords = fords, copies = copies}

func _river_valid(river: Dictionary) -> bool:
	var margin: float = river.width * 0.5 + 4.0
	var copies: Array = river.copies
	for p in river.points:
		if not _clear_of_bases(p, _gen.base_flat_radius + margin, copies):
			return false
		if not _clear_of_sites(p, margin, copies):
			return false
		if _near_centre_route(p, margin + _gen.path_width, copies):
			return false
		for a in copies:
			for b in copies:
				if a < b:
					for q in river.points:
						if rot(q, b).distance_to(rot(p, a)) < river.width * 2.0 + 8.0:
							return false
		for other in _rivers:
			for a in copies:
				for b in other.copies:
					for q in other.points:
						if rot(q, b).distance_to(rot(p, a)) < (river.width + other.width) * 0.5 + 8.0:
							return false
	return true

func _clear_of_rivers(p: Vector2, reach: float, copies: Array) -> bool:
	for k in copies:
		var q: Vector2 = rot(p, k)
		for river in _rivers:
			for rk in river.copies:
				var local: Vector2 = q.rotated(-rk * _step)
				for point in river.points:
					if point.distance_to(local) < reach + river.width * 0.5 + 3.0:
						return false
	return true

## Half-width at a point along the river: narrows over its last stretch inland.
func _river_half_width(river: Dictionary, arc: float) -> float:
	var total: float = river.arcs[river.arcs.size() - 1]
	return river.width * 0.5 * lerpf(1.0, 0.35, smoothstep(0.7, 1.0, arc / total))

## For every corner near copy k of the river: {corner index: [signed distance
## to the bank (negative in the water), arc position along the river]}.
func _river_field(river: Dictionary, k: int, reach: float) -> Dictionary:
	var field: Dictionary = {}
	var corners: int = size + 1
	var points: PackedVector2Array = river.points
	for s in points.size() - 1:
		var a: Vector2 = rot(points[s], k)
		var b: Vector2 = rot(points[s + 1], k)
		var lo: Vector2i = cell_at(Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(reach, reach)).clamp(Vector2i.ZERO, Vector2i(size, size))
		var hi: Vector2i = cell_at(Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(reach, reach)).clamp(Vector2i.ZERO, Vector2i(size, size))
		var segment: float = a.distance_to(b)
		for j in range(lo.y, hi.y + 1):
			for i in range(lo.x, hi.x + 1):
				var p: Vector2 = _corner_position(i, j)
				var closest: Vector2 = Geometry2D.get_closest_point_to_segment(p, a, b)
				var t: float = a.distance_to(closest) / segment if segment > 0.0 else 0.0
				var arc: float = lerpf(river.arcs[s], river.arcs[s + 1], t)
				var d: float = p.distance_to(closest) - _river_half_width(river, arc)
				var key: int = j * corners + i
				if not field.has(key) or d < field[key][0]:
					field[key] = [d, arc]
	return field

## Lowers a channel along each river copy, banks sloping like a lake shore,
## then raises the fords back up to wading depth.
func _carve_rivers() -> void:
	var pads: Array[Vector3] = _flat_pads()
	var shore: float = (_gen.hill_height + DRY_MARGIN + 2.0) / _gen.lake_shore_slope
	for river in _rivers:
		for k in river.copies:
			var field: Dictionary = _river_field(river, k, river.width + shore)
			for key in field:
				var d: float = field[key][0]
				var arc: float = field[key][1]
				var half_width: float = _river_half_width(river, arc)
				var profile: float = water_level + d * _gen.lake_shore_slope if d >= 0.0 \
						else water_level - _gen.river_depth * smoothstep(0.0, half_width, -d)
				var h: float = heights[key]
				var p: Vector2 = _corner_position(key % (size + 1), key / (size + 1))
				heights[key] = lerpf(h, minf(h, profile), 1.0 - _pad_cover(pads, p))
			_raise_fords(river, k, river.fords, field)

func _raise_fords(river: Dictionary, k: int, fords: Array, field: Dictionary = {}) -> void:
	if fords.is_empty():
		return
	if field.is_empty():
		field = _river_field(river, k, river.width)
	var ford_level: float = water_level - FORD_DEPTH
	for key in field:
		if field[key][0] > 1.0:
			continue
		var arc: float = field[key][1]
		var weight: float = 0.0
		for ford in fords:
			weight = maxf(weight, 1.0 - smoothstep(_gen.ford_width * 0.5, _gen.ford_width * 0.5 + 2.0, absf(arc - ford)))
		if weight > 0.0:
			heights[key] = lerpf(heights[key], maxf(heights[key], ford_level), weight)

## Adds a ford halfway along every river and re-checks, once, if a base or
## objective can't be reached. Fords only raise the riverbed, which nothing
## has been placed in.
func _ensure_connected() -> void:
	if _check_connectivity(false) or _rivers.is_empty():
		_check_connectivity(true)
		return
	for river in _rivers:
		var middle: float = river.arcs[river.arcs.size() - 1] * 0.5
		river.fords.append(middle)
		for k in river.copies:
			_raise_fords(river, k, [middle])
	_compute_cells()
	_check_connectivity(true)

## Paths are planned later, but always run from a base toward the middle.
func _near_centre_route(p: Vector2, clearance: float, copies: Array) -> bool:
	for k in copies:
		var q: Vector2 = rot(p, k)
		for base in base_centres:
			if Geometry2D.get_closest_point_to_segment(q, base, Vector2.ZERO).distance_to(q) < clearance:
				return true
	return false

func _clear_of_objective_pads(p: Vector2, reach: float, copies: Array) -> bool:
	for k in copies:
		var q: Vector2 = rot(p, k)
		for site in _objective_sites:
			for sk in site.copies:
				if q.distance_to(rot(site.pos, sk)) < _gen.objective_clear_radius + reach:
					return false
	return true

func _clear_of_lakes(p: Vector2, reach: float, copies: Array) -> bool:
	for k in copies:
		var q: Vector2 = rot(p, k)
		for lake in _lakes:
			for lk in lake.copies:
				if q.distance_to(rot(lake.pos, lk)) < reach + lake.radius * 1.35 + 8.0:
					return false
	return true

func _clear_of_pockets(p: Vector2, reach: float, copies: Array) -> bool:
	for k in copies:
		var q: Vector2 = rot(p, k)
		for pocket in _pockets:
			for pk in pocket.copies:
				if q.distance_to(rot(pocket.pos, pk)) < reach + pocket.radius + POCKET_FALLOFF + 4.0:
					return false
	return true

func _clear_of_features(p: Vector2, reach: float, copies: Array) -> bool:
	for k in copies:
		var q: Vector2 = rot(p, k)
		for feature in _features:
			var other: float = (feature.half as Vector2).length() + _gen.plateau_outline_noise
			for fk in feature.copies:
				if q.distance_to(_feature_centre(feature, fk)) < reach + other + 6.0:
					return false
	return true

func _feature_centre(feature: Dictionary, k: int) -> Vector2:
	return feature.centre if feature.symmetric else rot(feature.centre, k)

## Signed distance (negative inside) from p to tier t's outline in copy k: a
## rotated rounded rectangle whose edge is pushed in and out by noise read in
## the template frame, so every copy gets the same wobble.
func _feature_distance(feature: Dictionary, k: int, t: int, p: Vector2) -> float:
	var angle: float = feature.angle + (0.0 if feature.symmetric else k * _step)
	var q: Vector2 = (p - _feature_centre(feature, k)).rotated(-angle)
	var extents: Vector2 = feature.half - Vector2.ONE * _tier_ring() * t
	if extents.x <= 0.0 or extents.y <= 0.0:
		return INF
	var r: float = minf(feature.radius, minf(extents.x, extents.y))
	var d: Vector2 = q.abs() - (extents - Vector2(r, r))
	var distance: float = Vector2(maxf(d.x, 0.0), maxf(d.y, 0.0)).length() + minf(maxf(d.x, d.y), 0.0) - r
	var wobble: float = _rotation_noise(_outline_noise, p) if feature.symmetric else _outline_noise.get_noise_2dv(rot(p, -k))
	return distance + wobble * _gen.plateau_outline_noise

## How far into tier t's raised/sunk area p is: 0 outside, 1 inside, easing
## across the cliff band.
func _feature_mask(feature: Dictionary, k: int, t: int, p: Vector2) -> float:
	var band: float = _gen.cliff_width * 0.5
	return 1.0 - smoothstep(-band, band, _feature_distance(feature, k, t, p))

## --- Height field ---

func _corner_position(i: int, j: int) -> Vector2:
	return Vector2(i - half, j - half)

func _build_hills() -> void:
	var corners: int = size + 1
	heights.resize(corners * corners)
	for j in corners:
		for i in corners:
			heights[j * corners + i] = _rotation_noise(_hill_noise, _corner_position(i, j)) * _gen.hill_height

## Plateaus and valleys are added on top of the hills, so flattening before
## them levels bases and pockets without shaving off a nearby cliff.
func _add_features() -> void:
	var corners: int = size + 1
	for feature in _features:
		var reach: float = (feature.half as Vector2).length() + _gen.plateau_outline_noise + _gen.cliff_width
		for k in feature.copies:
			var centre: Vector2 = _feature_centre(feature, k)
			var lo: Vector2i = cell_at(centre - Vector2(reach, reach)).clamp(Vector2i.ZERO, Vector2i(size, size))
			var hi: Vector2i = cell_at(centre + Vector2(reach, reach)).clamp(Vector2i.ZERO, Vector2i(size, size))
			for j in range(lo.y, hi.y + 1):
				for i in range(lo.x, hi.x + 1):
					var p: Vector2 = _corner_position(i, j)
					var offset: float = 0.0
					for t in (feature.steps as Array).size():
						var mask: float = _feature_mask(feature, k, t, p)
						if mask <= 0.0:
							break
						offset += feature.steps[t] * mask
					heights[j * corners + i] += offset

## Each tier's ramps turn a quarter (or, on the centre, half a slice) from
## the tier below, so climbing means walking round the ledge in between. The
## centre feature gets one ramp facing each base, in every mode.
func _place_ramps() -> void:
	for feature in _features:
		var turn: float = _step * 0.5 if feature.symmetric else PI * 0.5
		for t in (feature.steps as Array).size():
			for base_dir in _ramp_directions(feature):
				var v: Vector2 = base_dir.rotated(turn * t)
				if feature.symmetric:
					for k in players:
						_commit_ramp(_find_ramp(feature, 0, t, rot(v, k)), k, true)
				else:
					for k in feature.copies:
						_commit_ramp(_find_ramp(feature, k, t, rot(v, k)), k, false)

## Template-frame directions a feature's ramps leave by: the first faces the
## nearest base (or, for the centre, one ramp per player).
func _ramp_directions(feature: Dictionary) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if feature.symmetric:
		result.append(base_centres[0].normalized())
		return result
	var centre: Vector2 = feature.centre
	var primary: Vector2 = (base_centres[0] - centre).normalized()
	var toward_middle: Vector2 = -centre.normalized()
	var candidates: Array[Vector2] = [primary, -primary, toward_middle, primary.orthogonal(), -primary.orthogonal()]
	for v in candidates:
		if result.size() >= _gen.ramps_per_plateau:
			break
		var taken: bool = false
		for existing in result:
			if existing.dot(v) > 0.5:
				taken = true
		if not taken:
			result.append(v)
	return result

## Walks out from the feature centre along v to tier t's edge, then lays the
## ramp across it, nudging the direction a little until both ends fit.
func _find_ramp(feature: Dictionary, k: int, t: int, v: Vector2) -> Dictionary:
	var centre: Vector2 = _feature_centre(feature, k)
	var reach: float = (feature.half as Vector2).length() + _gen.plateau_outline_noise + 2.0
	var climb: float = absf(feature.steps[t])
	var length: float = maxf(climb / _gen.ramp_slope, _gen.cliff_width + 2.0)
	for nudge in [0.0, 0.15, -0.15, 0.3, -0.3, 0.5, -0.5]:
		var dir: Vector2 = v.rotated(nudge)
		var s: float = 0.0
		while s < reach and _feature_distance(feature, k, t, centre + dir * s) < 0.0:
			s += 0.25
		if s >= reach:
			continue
		var edge: Vector2 = centre + dir * s
		var ramp := {outer = edge + dir * (length * 0.5), inner = edge - dir * (length * 0.5), tier = t, feature = feature, copy_index = k}
		if _ramp_valid(ramp):
			return ramp
	return {}

func _ramp_valid(ramp: Dictionary) -> bool:
	var feature: Dictionary = ramp.feature
	var k: int = ramp.copy_index
	var t: int = ramp.tier
	var dir: Vector2 = (Vector2(ramp.inner) - Vector2(ramp.outer)).normalized()
	var outer_landing: Vector2 = ramp.outer - dir * RAMP_LANDING
	var inner_landing: Vector2 = ramp.inner + dir * RAMP_LANDING
	var side: Vector2 = dir.orthogonal() * (_gen.ramp_width * 0.5)
	for p in [outer_landing, outer_landing + side, outer_landing - side]:
		if edge_distance(p) < 1.0 or _feature_distance(feature, k, t, p) < 1.0:
			return false
		if t > 0 and _feature_distance(feature, k, t - 1, p) > -1.0:
			return false
	for p in [inner_landing, inner_landing + side, inner_landing - side]:
		if _feature_distance(feature, k, t, p) > -1.0:
			return false
	## Another feature overlapping this edge would leave the drop the wrong size.
	var drop: float = surface_height(inner_landing) - surface_height(outer_landing)
	return absf(drop - feature.steps[t]) < absf(feature.steps[t]) * 0.5

func _commit_ramp(ramp: Dictionary, copy: int, on_centre: bool) -> void:
	if ramp.is_empty():
		push_warning("MapGenerator: a plateau/valley could not fit a ramp — it will be unreachable unless another ramp exists.")
		return
	_apply_ramp(ramp)
	var dir: Vector2 = (Vector2(ramp.inner) - Vector2(ramp.outer)).normalized()
	ramp.entrance = ramp.outer - dir * 2.0
	ramp.landing = ramp.inner + dir * 1.0
	ramp.copy = copy
	ramp.on_centre = on_centre
	ramp.erase("feature")
	_ramps.append(ramp)
	var length: float = (ramp.inner as Vector2).distance_to(ramp.outer)
	_add_body(ramp.entrance, _gen.ramp_width * 0.5 + 2.5, 0.0, _new_group(), false)
	_add_body(ramp.landing, _gen.ramp_width * 0.5 + 1.5, 0.0, _new_group(), false)
	_add_body((ramp.inner + ramp.outer) * 0.5, (length + _gen.ramp_width) * 0.5, 0.0, _new_group(), false)

## Pulls corners along the ramp's corridor onto a straight slope between its
## two ends, fading back to the untouched terrain past its sides and landings.
func _apply_ramp(ramp: Dictionary) -> void:
	var outer: Vector2 = ramp.outer
	var inner: Vector2 = ramp.inner
	var length: float = outer.distance_to(inner)
	var axis: Vector2 = (inner - outer) / length
	var across: Vector2 = axis.orthogonal()
	var h_outer: float = surface_height(outer - axis * RAMP_LANDING)
	var h_inner: float = surface_height(inner + axis * RAMP_LANDING)
	var half_width: float = _gen.ramp_width * 0.5
	var reach: float = length * 0.5 + RAMP_LANDING + half_width + 2.0
	var middle: Vector2 = (outer + inner) * 0.5
	var corners: int = size + 1
	var lo: Vector2i = cell_at(middle - Vector2(reach, reach)).clamp(Vector2i.ZERO, Vector2i(size, size))
	var hi: Vector2i = cell_at(middle + Vector2(reach, reach)).clamp(Vector2i.ZERO, Vector2i(size, size))
	for j in range(lo.y, hi.y + 1):
		for i in range(lo.x, hi.x + 1):
			var rel: Vector2 = _corner_position(i, j) - outer
			var along: float = rel.dot(axis)
			var beyond: float = maxf(-RAMP_LANDING - along, along - length - RAMP_LANDING)
			if beyond > 1.0:
				continue
			var weight: float = (1.0 - smoothstep(half_width, half_width + 1.0, absf(rel.dot(across)))) * (1.0 - smoothstep(0.0, 1.0, beyond))
			if weight <= 0.0:
				continue
			var target: float = lerpf(h_outer, h_inner, clampf(along / length, 0.0, 1.0))
			heights[j * corners + i] = lerpf(heights[j * corners + i], target, weight)

## Levels the hills under bases and building pockets.
func _flatten_building_ground() -> void:
	for base in base_centres:
		if imported:
			## Just room for the Town Center: the file's terrain is the point.
			_flatten(base, _gen.base_clear_radius + 2.0, 4.0)
		else:
			_flatten(base, _base_flat_reach() - BASE_FLAT_FALLOFF, BASE_FLAT_FALLOFF)
	for pocket in _pockets:
		for k in pocket.copies:
			_flatten(rot(pocket.pos, k), pocket.radius, POCKET_FALLOFF)

## Levels the pad each objective stands on (a plateau top has hills too).
func _flatten_objectives() -> void:
	for site in _objective_sites:
		for k in site.copies:
			_flatten(rot(site.pos, k), _gen.objective_clear_radius + 0.5, 2.0)

## Pulls corners within `radius` to the height at `centre`, easing back into
## the surrounding terrain over `falloff` metres.
func _flatten(centre: Vector2, radius: float, falloff: float) -> void:
	var level: float = surface_height(centre)
	var reach: float = radius + falloff
	var corners: int = size + 1
	var lo: Vector2i = cell_at(centre - Vector2(reach, reach)).clamp(Vector2i.ZERO, Vector2i(size, size))
	var hi: Vector2i = cell_at(centre + Vector2(reach, reach)).clamp(Vector2i.ZERO, Vector2i(size, size))
	for j in range(lo.y, hi.y + 1):
		for i in range(lo.x, hi.x + 1):
			var weight: float = 1.0 - smoothstep(radius, reach, _corner_position(i, j).distance_to(centre))
			if weight > 0.0:
				heights[j * corners + i] = lerpf(heights[j * corners + i], level, weight)

## Keeps land above the water, then along the coast lowers the ground onto a
## beach sloping to the waterline (edge_distance 0) and down to the sea floor;
## along forest edges, a steep bank at a wobbly line inside the border strip.
## Only ever lowers, so plateaus by the sea end in cliffs rather than beaches.
func _shape_coast() -> void:
	var corners: int = size + 1
	var dry: float = water_level + DRY_MARGIN
	var pads: Array[Vector3] = _flat_pads()
	for j in corners:
		for i in corners:
			var index_ij: int = j * corners + i
			var h: float = maxf(heights[index_ij], dry)
			var p: Vector2 = _corner_position(i, j)
			var coast: float = coast_weight(p)
			var cover: float = _pad_cover(pads, p)
			if coast > 0.0:
				var d: float = edge_distance(p)
				var profile: float = water_level + d * _gen.beach_slope if d >= 0.0 \
						else water_level - _gen.sea_depth * smoothstep(0.0, _gen.shore_drop, -d)
				h = lerpf(h, minf(h, profile), coast * (1.0 - cover))
			if coast < 1.0:
				var wobble: float = clampf(_rotation_noise(_coast_noise, p * 1.7) * 0.6 + 0.5, 0.0, 1.0) * _gen.border_width * FOREST_EDGE_WOBBLE
				var bank: float = _boundary_distance(p) - FOREST_EDGE_INSET - wobble
				if bank < (h - water_level) / FOREST_BANK_SLOPE:
					var profile: float = water_level + bank * FOREST_BANK_SLOPE if bank >= 0.0 \
							else water_level - _gen.sea_depth * smoothstep(0.0, FOREST_BANK_DROP, -bank)
					h = lerpf(h, minf(h, profile), (1.0 - coast) * (1.0 - cover))
			heights[index_ij] = h

## Signed distance (negative inside) from p to copy k of a lake's shoreline,
## wobbled by noise read in the template frame.
func _lake_distance(lake: Dictionary, k: int, p: Vector2) -> float:
	var wobble: float = _outline_noise.get_noise_2dv(rot(p, -k) * 1.3) * lake.radius * 0.35
	return p.distance_to(rot(lake.pos, k)) - lake.radius - wobble

## Lowers the ground into each lake: a shore sloping to the waterline, then
## down to lake_depth. Only ever lowers, and never under a flattened pad.
func _carve_lakes() -> void:
	var corners: int = size + 1
	var pads: Array[Vector3] = _flat_pads()
	var shore: float = (_gen.hill_height + DRY_MARGIN + 2.0) / _gen.lake_shore_slope
	for lake in _lakes:
		var reach: float = lake.radius * 1.35 + shore
		for k in lake.copies:
			var centre: Vector2 = rot(lake.pos, k)
			var lo: Vector2i = cell_at(centre - Vector2(reach, reach)).clamp(Vector2i.ZERO, Vector2i(size, size))
			var hi: Vector2i = cell_at(centre + Vector2(reach, reach)).clamp(Vector2i.ZERO, Vector2i(size, size))
			for j in range(lo.y, hi.y + 1):
				for i in range(lo.x, hi.x + 1):
					var p: Vector2 = _corner_position(i, j)
					var d: float = _lake_distance(lake, k, p)
					var profile: float = water_level + d * _gen.lake_shore_slope if d >= 0.0 \
							else water_level - _gen.lake_depth * smoothstep(0.0, lake.radius * 0.6, -d)
					var h: float = heights[j * corners + i]
					heights[j * corners + i] = lerpf(h, minf(h, profile), 1.0 - _pad_cover(pads, p))

## Every flattened pad as (x, z, radius including falloff): bases, building
## pockets and objective sites, in every copy.
func _flat_pads() -> Array[Vector3]:
	var pads: Array[Vector3] = []
	for base in base_centres:
		pads.append(Vector3(base.x, base.y, _base_flat_reach()))
	for pocket in _pockets:
		for k in pocket.copies:
			var p: Vector2 = rot(pocket.pos, k)
			pads.append(Vector3(p.x, p.y, pocket.radius + POCKET_FALLOFF))
	for site in _objective_sites:
		for k in site.copies:
			var p: Vector2 = rot(site.pos, k)
			pads.append(Vector3(p.x, p.y, _gen.objective_clear_radius + 2.5))
	return pads

## 1 inside a pad, easing to 0 over a few metres past its edge.
func _pad_cover(pads: Array[Vector3], p: Vector2) -> float:
	var cover: float = 0.0
	for pad in pads:
		cover = maxf(cover, 1.0 - smoothstep(pad.z, pad.z + 3.0, p.distance_to(Vector2(pad.x, pad.y))))
	return cover

## Per-cell rise and cliff flags, plus BFS distance (in cells) to the nearest cliff.
func _compute_cells() -> void:
	var corners: int = size + 1
	cell_rise.resize(size * size)
	cliff.resize(size * size)
	_cliff_distance.resize(size * size)
	_cliff_distance.fill(1 << 20)
	var frontier: Array[Vector2i] = []
	for z in size:
		for x in size:
			var top: int = z * corners + x
			var values: Array[float] = [heights[top], heights[top + 1], heights[top + corners], heights[top + corners + 1]]
			var rise: float = values.max() - values.min()
			var i: int = z * size + x
			cell_rise[i] = rise
			cliff[i] = 1 if rise > CLIFF_RISE else 0
			if cliff[i] == 1:
				_cliff_distance[i] = 0
				frontier.append(Vector2i(x, z))
	var head: int = 0
	while head < frontier.size():
		var c: Vector2i = frontier[head]
		head += 1
		var next: int = _cliff_distance[index(c)] + 1
		for d in DIRS:
			var n: Vector2i = c + d
			if in_bounds(n) and _cliff_distance[index(n)] > next:
				_cliff_distance[index(n)] = next
				frontier.append(n)

## --- Object placement ---

func _new_group() -> int:
	_next_group += 1
	return _next_group

func _add_body(p: Vector2, radius: float, gap: float, group: int, solid: bool) -> void:
	var body := {pos = p, radius = radius, gap = gap, group = group, solid = solid}
	_bodies.append(body)
	var key := Vector2i(floori(p.x / 4.0), floori(p.y / 4.0))
	if not _hash.has(key):
		_hash[key] = []
	_hash[key].append(body)
	_max_body_reach = maxf(_max_body_reach, radius + gap)

func _body_conflict(p: Vector2, radius: float, gap: float, group: int, pending: Array, own_group_only: bool = false) -> bool:
	var reach: float = radius + gap + _max_body_reach
	var lo := Vector2i(floori((p.x - reach) / 4.0), floori((p.y - reach) / 4.0))
	var hi := Vector2i(floori((p.x + reach) / 4.0), floori((p.y + reach) / 4.0))
	for bz in range(lo.y, hi.y + 1):
		for bx in range(lo.x, hi.x + 1):
			for body in _hash.get(Vector2i(bx, bz), []):
				if own_group_only and body.group != group:
					continue
				if _bodies_touch(p, radius, gap, group, body):
					return true
	for body in pending:
		if own_group_only and body.group != group:
			continue
		if _bodies_touch(p, radius, gap, group, body):
			return true
	return false

func _bodies_touch(p: Vector2, radius: float, gap: float, group: int, body: Dictionary) -> bool:
	var need: float = radius + body.radius
	if body.group != group:
		need += maxf(gap, body.gap)
	return p.distance_squared_to(body.pos) < need * need

## True if the disc at p sits on playable ground with no cliff under it, at
## most `max_rise` between its lowest and highest point, and the required
## clearance from cliffs.
func _footprint_ok(p: Vector2, radius: float, max_rise: float, cliff_clearance: int) -> bool:
	var centre: Vector2i = cell_at(p)
	if not is_playable_cell(centre):
		return false
	if edge_distance(p) < radius + 0.5:
		return false
	if _cliff_distance[index(centre)] < cliff_clearance:
		return false
	var low: float = INF
	var high: float = -INF
	var r: int = ceili(radius + 0.5)
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var c: Vector2i = centre + Vector2i(dx, dz)
			if cell_centre(c).distance_to(p) > radius + 0.75:
				continue
			if not is_playable_cell(c) or cliff[index(c)] == 1:
				return false
			var h: float = _cell_height(c)
			if h < water_level + PLACE_ABOVE_WATER:
				return false
			low = minf(low, h)
			high = maxf(high, h)
	return high - low <= max_rise

func _near_path(p: Vector2, clearance: float) -> bool:
	for path in _paths:
		for k in path.copies:
			var a: Vector2 = rot(path.a, k)
			var b: Vector2 = rot(path.b, k)
			if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) < path.width * 0.5 + clearance:
				return true
	return false

## Validates the template points at every rotation in `copies` together. On
## success appends their bodies to `pending` (commit with _commit_bodies); on
## failure leaves it untouched. `spec`: {radius, gap, rise, cliff, solid, avoid_paths}.
func _try_place(points: Array[Vector2], spec: Dictionary, copies: Array, pending: Array) -> bool:
	var local: Array = []
	for k in copies:
		var group: int = _new_group()
		for p in points:
			var q: Vector2 = rot(p, k)
			if not _footprint_ok(q, spec.radius, spec.rise, spec.cliff):
				return false
			if spec.get("avoid_paths", false) and _near_path(q, spec.radius + 1.0):
				return false
			if _body_conflict(q, spec.radius, spec.gap, group, pending + local):
				return false
			local.append({pos = q, radius = spec.radius, gap = spec.gap, group = group, solid = spec.solid})
	pending.append_array(local)
	return true

func _commit_bodies(bodies: Array) -> void:
	for body in bodies:
		_add_body(body.pos, body.radius, body.gap, body.group, body.solid)

## Like _try_place but drops individual points that fail (in any of `copies`)
## instead of rejecting the whole set, committing the rest. Returns accepted points.
func _place_each(points: Array[Vector2], spec: Dictionary, copies: Array) -> Array[Vector2]:
	var accepted: Array[Vector2] = []
	var groups: Dictionary = {}
	for k in copies:
		groups[k] = spec.get("group", _new_group()) if k == copies[0] else _new_group()
	for p in points:
		var pending: Array = []
		var ok: bool = true
		for k in copies:
			var q: Vector2 = rot(p, k)
			if not _footprint_ok(q, spec.radius, spec.rise, spec.cliff) \
					or (spec.get("avoid_paths", false) and _near_path(q, spec.radius + 1.0)) \
					or _body_conflict(q, spec.radius, spec.gap, groups[k], pending):
				ok = false
				break
			pending.append({pos = q, radius = spec.radius, gap = spec.gap, group = groups[k], solid = spec.solid})
		if not ok:
			continue
		_commit_bodies(pending)
		accepted.append(p)
	return accepted

## Node yaw turns the opposite way to Vector2.rotated() in the XZ plane.
func _emit(kind: StringName, scene: PackedScene, template_point: Vector2, yaw: float, scale: float, copies: Array, props: Dictionary = {}) -> void:
	for k in copies:
		var q: Vector2 = rot(template_point, k)
		objects.append({kind = kind, scene = scene, position = Vector3(q.x, surface_height(q), q.y), yaw = yaw - k * _step, scale = scale, props = props})

## Ramp keep-out zones overlap an objective's plateau by design, so objectives
## only need their flattened pad, not the usual body check.
func _place_objectives() -> void:
	for site in _objective_sites:
		var ok: bool = true
		for k in site.copies:
			if not _footprint_ok(rot(site.pos, k), _gen.objective_clear_radius, RISE_OBJECTIVE, 0):
				ok = false
		if not ok:
			push_warning("MapGenerator: an objective lost its flat ground and was skipped.")
			continue
		for k in site.copies:
			_add_body(rot(site.pos, k), _gen.objective_clear_radius, 0.0, _new_group(), false)
		_emit(&"objective", site.scene, site.pos, 0.0, 1.0, site.copies, site.props)

## Template point around player 0's base (stamping rotates it to the others),
## or on imported maps a world point around base k itself.
func _around_base(distance: Vector2, k: int) -> Vector2:
	var base: Vector2 = base_centres[k] if imported else base_centres[0]
	return base + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(distance.x, distance.y)

func _place_base_resources() -> void:
	var gold_spec := {radius = GOLD_RADIUS, gap = 1.5, rise = RISE_GOLD, cliff = CLIFF_CLEARANCE_OBJECTS, solid = true, avoid_paths = true}
	if _use_metal_gold():
		_place_metal_gold()
	else:
		for n in _gen.base_gold_mines:
			_place_fair(&"gold", _gen.gold_mine_scene, func(slot: Dictionary): return [_around_base(_gen.base_gold_distance, slot.base)], gold_spec)
	if _gen.base_trees > 0:
		var per_clump: int = maxi(1, int(float(_gen.base_trees) / _gen.base_tree_clumps))
		for slot in _placement_slots():
			var copies: Array = slot.copies
			for n in _gen.base_tree_clumps:
				for attempt in SPAWN_ATTEMPTS:
					var centre: Vector2 = _around_base(_gen.base_tree_distance, slot.base)
					var placed: Array[Vector2] = _place_tree_clump(centre, per_clump, copies)
					if placed.size() >= per_clump * 0.6:
						break

## Places one set of points for every placement slot (every player, or all at
## once when symmetric), each rolled from `candidates.call(slot)`, and commits
## only if all of them fit — so every player gets it or nobody does.
func _place_fair(kind: StringName, scene: PackedScene, candidates: Callable, spec: Dictionary) -> bool:
	var pending: Array = []
	var plans: Array = []
	for slot in _placement_slots():
		var copies: Array = slot.copies
		var found: bool = false
		for attempt in SPAWN_ATTEMPTS:
			var points: Array[Vector2] = []
			points.assign(candidates.call(slot))
			if _try_place(points, spec, copies, pending):
				plans.append([points, copies])
				found = true
				break
		if not found:
			push_warning("MapGenerator: could not fit %s for every player — try another seed or lower counts." % kind)
			return false
	_commit_bodies(pending)
	for plan in plans:
		for p in plan[0]:
			_emit(kind, scene, p, _rng.randf() * TAU, 1.0, plan[1])
	return true

## Grows an organic blob of trunk positions, then keeps whichever points are
## valid in every copy.
func _place_tree_clump(centre: Vector2, count: int, copies: Array) -> Array[Vector2]:
	var spacing: float = _gen.tree_spacing
	var points: Array[Vector2] = [centre]
	var tries: int = 0
	while points.size() < count and tries < count * 40:
		tries += 1
		var from: Vector2 = points[_rng.randi() % points.size()]
		var candidate: Vector2 = from + Vector2.from_angle(_rng.randf() * TAU) * spacing * _rng.randf_range(1.0, 1.3)
		var clear: bool = true
		for q in points:
			if q.distance_squared_to(candidate) < spacing * spacing * 0.96:
				clear = false
				break
		if clear:
			points.append(candidate)
	var spec := {radius = spacing * 0.5, gap = _gen.forest_corridor, rise = RISE_TREE, cliff = CLIFF_CLEARANCE_TREES, solid = true, avoid_paths = true}
	var accepted: Array[Vector2] = _place_each(points, spec, copies)
	for p in accepted:
		_emit(&"tree", _gen.tree_scene, p, _rng.randf() * TAU, 1.0, copies)
	return accepted

func _place_neutral_resources() -> void:
	var keep_out: float = _gen.base_clear_radius + 16.0
	var gold_spec := {radius = GOLD_RADIUS, gap = 2.0, rise = RISE_GOLD, cliff = CLIFF_CLEARANCE_OBJECTS, solid = true, avoid_paths = true}
	if _use_metal_gold():
		return
	for n in _gen.neutral_gold_per_player:
		_place_fair(&"gold", _gen.gold_mine_scene, func(slot: Dictionary): return [_neutral_point(keep_out, slot)], gold_spec)

func _neutral_point(keep_out: float, slot: Dictionary) -> Vector2:
	for attempt in 40:
		var p: Vector2 = _rand_in_sector(0.2, 0.9, slot.base)
		if _clear_of_bases(p, keep_out, slot.copies):
			return p
	return _rand_in_sector(0.2, 0.9, slot.base)

func _use_metal_gold() -> bool:
	return imported and _gen.import_metal_as_gold and not (_import.get("metal_spots", []) as Array).is_empty()

## Imported maps with a metal map: each base takes the base_gold_mines metal
## spots nearest it (within reach), then neutral gold goes on the remaining
## spots furthest from everything placed so far.
func _place_metal_gold() -> void:
	var spots: Array[Vector2] = []
	for uv in _import.metal_spots:
		spots.append(_uv_to_world(uv))
	var spec := {radius = GOLD_RADIUS, gap = 1.5, rise = RISE_GOLD, cliff = CLIFF_CLEARANCE_OBJECTS, solid = true, avoid_paths = false}
	var taken: Array[Vector2] = []
	var reach: float = _gen.base_gold_distance.y + 20.0
	for base in base_centres:
		var near: Array[Vector2] = []
		near.assign(spots.filter(func(s): return s.distance_to(base) <= reach))
		near.sort_custom(func(a, b): return a.distance_to(base) < b.distance_to(base))
		var placed: int = 0
		for spot in near:
			if placed >= _gen.base_gold_mines:
				break
			if _try_place_metal(spot, spec):
				taken.append(spot)
				placed += 1
	var neutral: int = _gen.neutral_gold_per_player * players
	var keep_out: float = _gen.base_clear_radius + 16.0
	var remaining: Array[Vector2] = []
	remaining.assign(spots.filter(func(s): return not taken.has(s) and _clear_of_bases(s, keep_out, [0])))
	while neutral > 0 and not remaining.is_empty():
		var best: Vector2 = remaining[0]
		var best_distance: float = -1.0
		for s in remaining:
			var nearest: float = INF
			for t in taken:
				nearest = minf(nearest, s.distance_to(t))
			for b in base_centres:
				nearest = minf(nearest, s.distance_to(b))
			if nearest > best_distance:
				best_distance = nearest
				best = s
		remaining.erase(best)
		if _try_place_metal(best, spec):
			taken.append(best)
			neutral -= 1

func _try_place_metal(spot: Vector2, spec: Dictionary) -> bool:
	var pending: Array = []
	var points: Array[Vector2] = [spot]
	if not _try_place(points, spec, [0], pending):
		return false
	_commit_bodies(pending)
	_emit(&"gold", _gen.gold_mine_scene, spot, _rng.randf() * TAU, 1.0, [0])
	return true

## Woodland patches sized by radius: a noise-edged disc filled at tree
## spacing. A site is only used if most of the patch fits, so failed attempts
## don't leave stray fragments behind.
func _place_forest_clusters() -> void:
	var min_radius: float = maxf(_gen.forest_cluster_radius.x, _gen.tree_spacing)
	var max_radius: float = maxf(_gen.forest_cluster_radius.y, min_radius)
	var spacing: float = _gen.tree_spacing
	var spec := {radius = spacing * 0.5, gap = _gen.forest_corridor, rise = RISE_TREE, cliff = CLIFF_CLEARANCE_TREES, solid = true, avoid_paths = true}
	for slot in _placement_slots():
		var copies: Array = slot.copies
		for n in _gen.forest_clusters_per_player:
			for attempt in SPAWN_ATTEMPTS:
				var radius: float = _rng.randf_range(min_radius, max_radius)
				var centre: Vector2 = _rand_in_sector(0.15, 0.95, slot.base)
				if not _clear_of_bases(centre, _gen.base_clear_radius + radius + 8.0, copies):
					continue
				var points: Array[Vector2] = _forest_blob(centre, radius, spacing)
				if _count_fitting(points, spec, copies) < points.size() * 0.7:
					continue
				for p in _place_each(points, spec, copies):
					_emit(&"tree", _gen.tree_scene, p, _rng.randf() * TAU, 1.0, copies)
				break

func _forest_blob(centre: Vector2, radius: float, spacing: float) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var pitch: float = spacing * 1.08
	var reach: float = radius * 1.3
	var steps: int = ceili(reach * 2.0 / pitch)
	var seed_offset := Vector2(_rng.randf_range(-500.0, 500.0), _rng.randf_range(-500.0, 500.0))
	for gz in steps:
		for gx in steps:
			var offset := Vector2(-reach + (gx + 0.5) * pitch, -reach + (gz + 0.5) * pitch)
			offset += Vector2(_rng.randf_range(-0.2, 0.2), _rng.randf_range(-0.2, 0.2)) * spacing
			var edge: float = radius * (0.7 + 0.6 * _noise01((centre + offset) * 0.8 + seed_offset))
			if offset.length() < edge:
				points.append(centre + offset)
	return points

## How many template points would pass placement checks in every copy,
## ignoring the points' effect on each other (they share one group).
func _count_fitting(points: Array[Vector2], spec: Dictionary, copies: Array) -> int:
	var probe_group: int = _new_group()
	var fitting: int = 0
	for p in points:
		var ok: bool = true
		for k in copies:
			var q: Vector2 = rot(p, k)
			if not _footprint_ok(q, spec.radius, spec.rise, spec.cliff) or _near_path(q, spec.radius + 1.0) \
					or _body_conflict(q, spec.radius, spec.gap, probe_group, []):
				ok = false
				break
		if ok:
			fitting += 1
	return fitting

## Gatherable trees hugging the playable edge (not along the coast), with
## noise-varied depth and gaps.
func _place_edge_forest() -> void:
	var depth: float = _gen.edge_forest_depth
	if depth <= 0.0:
		return
	var spacing: float = _gen.tree_spacing
	var limit: float = half - _gen.border_width
	var pitch: float = spacing * 1.08
	var steps: int = ceili(limit * 2.0 / pitch)
	var grid_points: Array[Vector2] = []
	for gz in steps:
		for gx in steps:
			grid_points.append(Vector2(-limit + (gx + 0.5) * pitch, -limit + (gz + 0.5) * pitch) + Vector2(_rng.randf_range(-0.2, 0.2), _rng.randf_range(-0.2, 0.2)) * spacing)
	for slot in _placement_slots():
		var copies: Array = slot.copies
		var spec := {radius = spacing * 0.5, gap = _gen.forest_corridor, rise = RISE_TREE, cliff = CLIFF_CLEARANCE_TREES, solid = true, avoid_paths = true, group = _new_group()}
		var candidates: Array[Vector2] = []
		for p in grid_points:
			if not _in_slot_region(p, slot):
				continue
			var local_depth: float = depth * lerpf(0.3, 1.0, clampf(_noise01(p * 0.6) * 1.6 - 0.3, 0.0, 1.0))
			var fits: bool = true
			for k in copies:
				var q: Vector2 = rot(p, k)
				var inside: float = edge_distance(q)
				if coast_weight(q) > 0.3 or inside <= 0.0 or inside >= local_depth:
					fits = false
					break
			if fits:
				candidates.append(p)
		for p in _place_each(candidates, spec, copies):
			_emit(&"tree", _gen.tree_scene, p, _rng.randf() * TAU, 1.0, copies)

func _place_border_trees() -> void:
	var scenes: Array[PackedScene] = []
	scenes.assign(_gen.border_tree_scenes.filter(func(s): return s != null))
	if scenes.is_empty() or _gen.border_width <= 0:
		return
	var spacing: float = _gen.border_tree_spacing
	var group: int = _new_group()
	var attempts: int = int(size * size / (spacing * spacing) * 8.0 / players)
	for slot in _placement_slots():
		var copies: Array = slot.copies
		for n in attempts:
			var p := Vector2(_rng.randf_range(-half + 0.4, half - 0.4), _rng.randf_range(-half + 0.4, half - 0.4))
			if not _in_slot_region(p, slot):
				continue
			var copies_ok: bool = true
			var pending: Array = []
			for k in copies:
				var q: Vector2 = rot(p, k)
				if absf(q.x) > half - 0.4 or absf(q.y) > half - 0.4 or edge_distance(q) > -0.6 or coast_weight(q) > 0.3 \
						or surface_height(q) < water_level + PLACE_ABOVE_WATER \
						or _body_conflict(q, spacing * 0.5, 0.0, group, pending, true):
					copies_ok = false
					break
				pending.append({pos = q, radius = spacing * 0.5, gap = 0.0, group = group, solid = false})
			if not copies_ok:
				continue
			_commit_bodies(pending)
			_emit(&"border_tree", scenes[_rng.randi() % scenes.size()], p, _rng.randf() * TAU, _rng.randf_range(0.85, 1.25), copies)

func _place_props() -> void:
	var scenes: Array[PackedScene] = []
	scenes.assign(_gen.prop_scenes.filter(func(s): return s != null))
	if scenes.is_empty():
		return
	var spec := {radius = PROP_RADIUS, gap = 0.4, rise = RISE_PROP, cliff = 1, solid = false}
	for slot in _placement_slots():
		var copies: Array = slot.copies
		var placed: int = 0
		for attempt in _gen.props_per_player * 12:
			if placed >= _gen.props_per_player:
				break
			var points: Array[Vector2] = [_rand_in_sector(0.05, 1.0, slot.base)]
			var pending: Array = []
			if _try_place(points, spec, copies, pending):
				_commit_bodies(pending)
				_emit(&"prop", scenes[_rng.randi() % scenes.size()], points[0], _rng.randf() * TAU, _rng.randf_range(0.8, 1.2), copies)
				placed += 1

## --- Decals ---

## Paths run from each base to its nearest centre-feature ramp (or the middle).
func _plan_paths() -> void:
	if not _gen.paths_to_centre or imported:
		return
	var base0: Vector2 = base_centres[0]
	for slot in _placement_slots():
		var copies: Array = slot.copies
		var k: int = copies[0]
		var target: Vector2 = Vector2.ZERO
		for ramp in _ramps:
			if ramp.on_centre and ramp.tier == 0 and ramp.copy == k:
				var entrance: Vector2 = (ramp.entrance as Vector2).rotated(-k * _step)
				if entrance.distance_to(base0) < target.distance_to(base0):
					target = entrance
		_paths.append({a = base0, b = target, width = _gen.path_width, copies = copies})

func _plan_decals() -> void:
	if imported:
		for base in base_centres:
			_dirt_shapes.append({a = base, b = base, width = _gen.base_clear_radius * 1.5, copies = [0]})
	else:
		var base0: Vector2 = base_centres[0]
		_dirt_shapes.append({a = base0, b = base0, width = _gen.base_clear_radius * 1.5, copies = _all_copies()})
	_dirt_shapes.append_array(_paths)
	for ramp in _ramps:
		if ramp.tier == 0:
			_dirt_shapes.append({a = ramp.entrance, b = ramp.entrance, width = _gen.ramp_width + 2.0, copies = [0]})
	if not _gen.objectives_on_plateaus:
		for site in _objective_sites:
			_dirt_shapes.append({a = site.pos, b = site.pos, width = _gen.objective_clear_radius * 1.3, copies = site.copies})
	for slot in _placement_slots():
		var copies: Array = slot.copies
		for n in _gen.dirt_patches_per_player:
			var p: Vector2 = _rand_in_sector(0.1, 0.95, slot.base)
			_dirt_shapes.append({a = p, b = p + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0.0, 5.0), width = _rng.randf_range(3.0, 7.0), copies = copies})
		for n in _gen.grass_patches_per_player:
			var p: Vector2 = _rand_in_sector(0.05, 1.0, slot.base)
			_grass_shapes.append({a = p, b = p + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0.0, 8.0), width = _rng.randf_range(4.0, 10.0), copies = copies})

func _rasterize_decals() -> void:
	dirt = _corner_field(_dirt_shapes)
	grass = _corner_field(_grass_shapes)

## Samples shapes at cell corners. Noise is read in the template frame so
## copies match.
func _corner_field(shapes: Array[Dictionary]) -> PackedByteArray:
	var corners: int = size + 1
	var field := PackedByteArray()
	field.resize(corners * corners)
	field.fill(0)
	for shape in shapes:
		var radius: float = shape.width * 0.5
		var reach: float = radius * 1.35 + 1.0
		for k in shape.copies:
			var a: Vector2 = rot(shape.a, k)
			var b: Vector2 = rot(shape.b, k)
			var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(reach, reach)
			var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(reach, reach)
			for j in range(maxi(0, floori(lo.y + half)), mini(corners - 1, ceili(hi.y + half)) + 1):
				for i in range(maxi(0, floori(lo.x + half)), mini(corners - 1, ceili(hi.x + half)) + 1):
					var p := Vector2(i - half, j - half)
					var d: float = Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p)
					if d > reach:
						continue
					if d < radius * (0.7 + 0.6 * _noise01(rot(p, -k) * 1.7)):
						field[j * corners + i] = 1
	return field

## --- Validation ---

## True if every base and objective is reachable from player 1's base; with
## `report`, warns about each one that isn't.
func _check_connectivity(report: bool) -> bool:
	var blocked := PackedByteArray()
	blocked.resize(size * size)
	blocked.fill(0)
	for body in _bodies:
		if not body.solid:
			continue
		var c: Vector2i = cell_at(body.pos)
		if in_bounds(c) and cell_centre(c).distance_to(body.pos) < body.radius + 0.3:
			blocked[index(c)] = 1
	var start: Vector2i = cell_at(base_centres[0])
	var seen := PackedByteArray()
	seen.resize(size * size)
	seen.fill(0)
	var frontier: Array[Vector2i] = [start]
	seen[index(start)] = 1
	var head: int = 0
	while head < frontier.size():
		var c: Vector2i = frontier[head]
		head += 1
		for d in 4:
			var n: Vector2i = c + DIRS[d]
			if not is_playable_cell(n) or seen[index(n)] == 1 or blocked[index(n)] == 1 or cliff[index(n)] == 1 or is_deep_water(n):
				continue
			if absf(_cell_height(c) - _cell_height(n)) > WALK_STEP:
				continue
			seen[index(n)] = 1
			frontier.append(n)
	var targets: Array[Vector2] = base_centres.duplicate()
	for entry in objects:
		if entry.kind == &"objective":
			targets.append(Vector2(entry.position.x, entry.position.z))
	var connected: bool = true
	for t in targets:
		if seen[index(cell_at(t))] == 0:
			connected = false
			if report:
				push_warning("MapGenerator: %s is not reachable from player 1's base on this seed." % t)
	return connected
