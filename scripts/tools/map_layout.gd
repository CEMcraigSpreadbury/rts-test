@tool
class_name MapLayout
extends RefCounted
## The data half of MapGenerator: a height field on cell corners (rolling
## hills, organic plateaus and valleys joined by ramps, flattened pads), decal
## corner fields, and every object placement, all derived from the seed.
##
## Fairness comes from rotational symmetry. Every feature is authored once for
## player 0's slice (the "template") and then rotated by TAU / players for
## everyone else, so each base gets the same terrain, resources and distances.
## Object placements are only accepted if every rotated copy is valid. Noise is
## either read in the template frame or averaged over every rotation, so the
## terrain itself matches between copies too.

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
## Land is kept at least this far above the water unless the coast (or, later,
## a lake or river) deliberately takes it under.
const DRY_MARGIN: float = 0.5
## Water shallower than this is walkable (and navigable); deeper blocks.
const WADE_DEPTH: float = 0.3
## Objects and pads need their ground at least this far above the water.
const PLACE_ABOVE_WATER: float = 0.25

var size: int
var half: float
var players: int
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
## {centre, half: Vector2, radius, angle, symmetric, steps: Array[float] (height change per tier)}
var _features: Array[Dictionary] = []
var _ramps: Array[Dictionary] = []
var _objective_sites: Array[Dictionary] = []
## Flattened spots to build on away from base: {pos, radius}, template frame.
var _pockets: Array[Dictionary] = []
var _paths: Array[Dictionary] = []
var _dirt_shapes: Array[Dictionary] = []
var _grass_shapes: Array[Dictionary] = []
var _cliff_distance := PackedInt32Array()
## Spatial hash of placed bodies: {pos, radius, gap, group, solid}
var _bodies: Array[Dictionary] = []
var _hash: Dictionary = {}
var _next_group: int = 1
var _max_body_reach: float = 0.0
var _reach_cache: Dictionary = {}

func _init(generator: MapGenerator) -> void:
	_gen = generator

func generate() -> bool:
	size = _gen.map_size
	half = size * 0.5
	players = _gen.player_count
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

	_place_bases()
	_plan_objectives()
	_plan_features()
	_plan_pockets()
	_build_hills()
	_flatten_building_ground()
	_add_features()
	_place_ramps()
	_flatten_objectives()
	_shape_coast()
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
	_check_connectivity()
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
		best -= coast * _gen.coast_wobble * clampf(_symmetric_noise(_coast_noise, p) * 0.6 + 0.5, 0.0, 1.0)
	return best

## How much the map edge nearest p is coast (1) rather than forest border (0).
## Two waves around the map repeating once per player, so every slice matches;
## coast_fraction moves the threshold.
func coast_weight(p: Vector2) -> float:
	if _gen.coast_fraction <= 0.0:
		return 0.0
	var angle: float = p.angle() * players
	var wave: float = (sin(angle + _coast_phases.x) + 0.6 * sin(angle * 2.0 + _coast_phases.y)) / 1.6
	var threshold: float = 1.0 - 2.0 * _gen.coast_fraction
	return smoothstep(threshold - 0.15, threshold + 0.15, wave)

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

## Corners outside the grid take the nearest edge corner's height, sinking to
## the sea floor over shore_drop where that edge is coast, so the sea carries on
## past the map instead of stopping in straight strips.
func corner_height(corner: Vector2i) -> float:
	var c: Vector2i = corner.clamp(Vector2i.ZERO, Vector2i(size, size))
	var h: float = heights[c.y * (size + 1) + c.x]
	if c == corner:
		return h
	var p: Vector2 = _corner_position(corner.x, corner.y)
	var outside: float = (Vector2(corner) - Vector2(c)).length()
	var sea_floor: float = water_level - _gen.sea_depth
	return lerpf(h, minf(h, sea_floor), coast_weight(p) * smoothstep(0.0, _gen.shore_drop, outside))

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

func _rand_in_sector(r_min: float, r_max: float) -> Vector2:
	var angle: float = _angle0 + _rng.randf_range(-0.5, 0.5) * _step
	var reach: float = _edge_distance_along(angle)
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

## --- Bases ---

func _place_bases() -> void:
	var r: float = _gen.spawn_distance * _edge_distance_along(_angle0)
	var base0: Vector2 = Vector2.from_angle(_angle0) * r
	for k in players:
		var centre: Vector2 = rot(base0, k)
		base_centres.append(centre)
		var spawn: Vector2 = centre - TC_OFFSET
		spawn_positions.append(Vector3(spawn.x, 0.0, spawn.y))
		_add_body(centre, _gen.base_clear_radius, 0.0, _new_group(), false)

## --- Objectives, plateaus & valleys (template frame) ---

## Width of the ledge a lower tier keeps around the tier above it: room for
## that tier's ramp and a little walking space.
func _tier_ring() -> float:
	return ramp_length + 3.0

func _objective_plateau_half() -> float:
	return _gen.objective_clear_radius + ramp_length * 0.5 + 2.5 + (_gen.objective_plateau_tiers - 1) * _tier_ring()

func _plan_objectives() -> void:
	var scenes: Array[PackedScene] = []
	scenes.assign(_gen.objective_scenes.filter(func(s): return s != null))
	var on_plateau: bool = _gen.objectives_on_plateaus
	var footprint: float = _objective_plateau_half() * 1.3 if on_plateau else _gen.objective_clear_radius
	var centre_scene: PackedScene = null
	match _gen.centre_site:
		MapGenerator.CentreSite.OBJECTIVE:
			centre_scene = scenes[_rng.randi() % scenes.size()] if not scenes.is_empty() else null
		MapGenerator.CentreSite.SHRINE:
			centre_scene = _gen.shrine_scene
	if centre_scene != null:
		_objective_sites.append({pos = Vector2.ZERO, scene = centre_scene, symmetric = true, footprint = footprint, props = {favour_per_second = _gen.centre_favour_per_second}})
	var requests: Array[Dictionary] = []
	if not scenes.is_empty():
		for j in _gen.objectives_per_player:
			requests.append({scene = scenes[_rng.randi() % scenes.size()], props = {}})
	if _gen.shrine_scene != null:
		for j in _gen.shrines_per_player:
			requests.append({scene = _gen.shrine_scene, props = {roll_group = StringName("shrine_%d" % j)}})
	for request in requests:
		var placed: bool = false
		for attempt in 300:
			var p: Vector2 = _rand_in_sector(0.25, 0.9)
			if edge_distance(p) < footprint + 4.0:
				continue
			if not _clear_of_bases(p, _gen.objective_min_base_distance):
				continue
			if not _clear_of_sites(p, footprint + 6.0):
				continue
			if _self_copies_too_close(p, footprint * 2.0 + 6.0):
				continue
			_objective_sites.append({pos = p, scene = request.scene, symmetric = false, footprint = footprint, props = request.props})
			placed = true
			break
		if not placed:
			push_warning("MapGenerator: no room for every objective/shrine — lower the per-player counts or Objective Min Base Distance, or use a bigger map.")

func _clear_of_bases(p: Vector2, min_distance: float) -> bool:
	for k in players:
		for base in base_centres:
			if rot(p, k).distance_to(base) < min_distance:
				return false
	return true

func _clear_of_sites(p: Vector2, extra: float) -> bool:
	for site in _objective_sites:
		for k in players:
			var q: Vector2 = rot(p, k)
			if q.distance_to(site.pos) < site.footprint + extra:
				return false
	return true

func _self_copies_too_close(p: Vector2, min_distance: float) -> bool:
	for k in range(1, players):
		if rot(p, k).distance_to(p) < min_distance:
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
	if _gen.objectives_on_plateaus:
		var h: float = _objective_plateau_half()
		for site in _objective_sites:
			var feature := {centre = site.pos, half = Vector2(h, h), radius = 3.0, angle = _rng.randf() * TAU, symmetric = site.symmetric, steps = _roll_steps(_gen.objective_plateau_tiers, false)}
			if site.symmetric:
				feature.half = Vector2(h, h) * 1.05
				feature.radius = feature.half.x
			_features.append(feature)
	var min_half: float = maxf(_gen.plateau_half_size.x, ramp_length * 0.5 + 3.0 + (_gen.plateau_tiers - 1) * _tier_ring())
	var max_half: float = maxf(_gen.plateau_half_size.y, min_half)
	for n in _gen.plateaus_per_player:
		var placed: bool = false
		for attempt in 300:
			var extents := Vector2(_rng.randf_range(min_half, max_half), _rng.randf_range(min_half, max_half))
			var reach: float = extents.length() + _gen.plateau_outline_noise
			var p: Vector2 = _rand_in_sector(0.2, 0.95)
			if edge_distance(p) < reach + 6.0:
				continue
			if not _clear_of_bases(p, _gen.base_clear_radius + reach + 10.0):
				continue
			if not _clear_of_sites(p, reach + 5.0):
				continue
			if not _clear_of_features(p, reach):
				continue
			if _self_copies_too_close(p, reach * 2.0 + 6.0):
				continue
			_features.append({centre = p, half = extents, radius = minf(extents.x, extents.y) * _rng.randf_range(0.3, 0.8), angle = _rng.randf() * TAU, symmetric = false, steps = _roll_steps(_gen.plateau_tiers, true)})
			placed = true
			break
		if not placed:
			push_warning("MapGenerator: no room for extra plateau/valley %d." % (n + 1))

func _base_flat_reach() -> float:
	return maxf(_gen.base_flat_radius, _gen.base_clear_radius + 2.0) + BASE_FLAT_FALLOFF

## Spots flattened for building on, away from bases, objectives and features.
## Each gets a non-solid body so trees and gold leave the space free.
func _plan_pockets() -> void:
	for n in _gen.building_pockets_per_player:
		var placed: bool = false
		for attempt in 200:
			var radius: float = _rng.randf_range(_gen.building_pocket_radius.x, maxf(_gen.building_pocket_radius.y, _gen.building_pocket_radius.x))
			var reach: float = radius + POCKET_FALLOFF
			var p: Vector2 = _rand_in_sector(0.2, 0.9)
			if edge_distance(p) < reach + 4.0:
				continue
			if not _clear_of_bases(p, _base_flat_reach() + reach):
				continue
			if not _clear_of_sites(p, reach + 4.0):
				continue
			if not _clear_of_features(p, reach):
				continue
			if not _clear_of_pockets(p, reach):
				continue
			if _self_copies_too_close(p, reach * 2.0 + 4.0):
				continue
			_pockets.append({pos = p, radius = radius})
			for k in players:
				_add_body(rot(p, k), radius, 0.0, _new_group(), false)
			placed = true
			break
		if not placed:
			push_warning("MapGenerator: no room for building pocket %d." % (n + 1))

func _clear_of_pockets(p: Vector2, reach: float) -> bool:
	for pocket in _pockets:
		for k in players:
			if rot(p, k).distance_to(pocket.pos) < reach + pocket.radius + POCKET_FALLOFF + 4.0:
				return false
	return true

func _clear_of_features(p: Vector2, reach: float) -> bool:
	for feature in _features:
		var other: float = (feature.half as Vector2).length() + _gen.plateau_outline_noise
		for k in players:
			if rot(p, k).distance_to(feature.centre) < reach + other + 6.0:
				return false
	return true

func _feature_copies(feature: Dictionary) -> int:
	return 1 if feature.symmetric else players

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
	var wobble: float = _symmetric_noise(_outline_noise, p) if feature.symmetric else _outline_noise.get_noise_2dv(rot(p, -k))
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
			heights[j * corners + i] = _symmetric_noise(_hill_noise, _corner_position(i, j)) * _gen.hill_height

## Plateaus and valleys are added on top of the hills, so flattening before
## them levels bases and pockets without shaving off a nearby cliff.
func _add_features() -> void:
	var corners: int = size + 1
	for feature in _features:
		var reach: float = (feature.half as Vector2).length() + _gen.plateau_outline_noise + _gen.cliff_width
		for k in _feature_copies(feature):
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
## the tier below, so climbing means walking round the ledge in between.
func _place_ramps() -> void:
	for feature in _features:
		var turn: float = _step * 0.5 if feature.symmetric else PI * 0.5
		for t in (feature.steps as Array).size():
			for base_dir in _ramp_directions(feature):
				var v: Vector2 = base_dir.rotated(turn * t)
				for k in players:
					var copy: int = 0 if feature.symmetric else k
					var ramp: Dictionary = _find_ramp(feature, copy, t, rot(v, k))
					_commit_ramp(ramp, k, feature.symmetric)

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
		_flatten(base, _base_flat_reach() - BASE_FLAT_FALLOFF, BASE_FLAT_FALLOFF)
	for pocket in _pockets:
		for k in players:
			_flatten(rot(pocket.pos, k), pocket.radius, POCKET_FALLOFF)

## Levels the pad each objective stands on (a plateau top has hills too).
func _flatten_objectives() -> void:
	for site in _objective_sites:
		for k in (1 if site.symmetric else players):
			_flatten(rot(site.pos, k) if not site.symmetric else site.pos, _gen.objective_clear_radius + 0.5, 2.0)

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
## beach sloping to the waterline (edge_distance 0) and down to the sea floor.
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
			if coast > 0.0:
				var d: float = edge_distance(p)
				var profile: float = water_level + d * _gen.beach_slope if d >= 0.0 \
						else water_level - _gen.sea_depth * smoothstep(0.0, _gen.shore_drop, -d)
				h = lerpf(h, minf(h, profile), coast * (1.0 - _pad_cover(pads, p)))
			heights[index_ij] = h

## Every flattened pad as (x, z, radius including falloff): bases, building
## pockets and objective sites, in every copy.
func _flat_pads() -> Array[Vector3]:
	var pads: Array[Vector3] = []
	for base in base_centres:
		pads.append(Vector3(base.x, base.y, _base_flat_reach()))
	for pocket in _pockets:
		for k in players:
			var p: Vector2 = rot(pocket.pos, k)
			pads.append(Vector3(p.x, p.y, pocket.radius + POCKET_FALLOFF))
	for site in _objective_sites:
		for k in (1 if site.symmetric else players):
			var p: Vector2 = site.pos if site.symmetric else rot(site.pos, k)
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
		for k in players:
			var a: Vector2 = rot(path.a, k)
			var b: Vector2 = rot(path.b, k)
			if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) < path.width * 0.5 + clearance:
				return true
	return false

## Validates every rotated copy of the template points together; commits all
## or nothing. `spec`: {radius, gap, rise, cliff, solid, avoid_paths}.
func _try_place_symmetric(points: Array[Vector2], spec: Dictionary) -> bool:
	var pending: Array = []
	var groups: Array[int] = []
	for k in players:
		groups.append(_new_group())
	for k in players:
		for p in points:
			var q: Vector2 = rot(p, k)
			if not _footprint_ok(q, spec.radius, spec.rise, spec.cliff):
				return false
			if spec.get("avoid_paths", false) and _near_path(q, spec.radius + 1.0):
				return false
			if _body_conflict(q, spec.radius, spec.gap, groups[k], pending):
				return false
			pending.append({pos = q, radius = spec.radius, gap = spec.gap, group = groups[k], solid = spec.solid})
	for body in pending:
		_add_body(body.pos, body.radius, body.gap, body.group, body.solid)
	return true

## Like _try_place_symmetric but drops individual points that fail (in every
## copy at once) instead of rejecting the whole set. Returns accepted points.
func _place_symmetric_each(points: Array[Vector2], spec: Dictionary) -> Array[Vector2]:
	var accepted: Array[Vector2] = []
	var groups: Array[int] = []
	for k in players:
		groups.append(spec.get("group", _new_group()) if k == 0 else _new_group())
	for p in points:
		var pending: Array = []
		var ok: bool = true
		for k in players:
			var q: Vector2 = rot(p, k)
			if not _footprint_ok(q, spec.radius, spec.rise, spec.cliff) \
					or (spec.get("avoid_paths", false) and _near_path(q, spec.radius + 1.0)) \
					or _body_conflict(q, spec.radius, spec.gap, groups[k], pending):
				ok = false
				break
			pending.append({pos = q, radius = spec.radius, gap = spec.gap, group = groups[k], solid = spec.solid})
		if not ok:
			continue
		for body in pending:
			_add_body(body.pos, body.radius, body.gap, body.group, body.solid)
		accepted.append(p)
	return accepted

## Node yaw turns the opposite way to Vector2.rotated() in the XZ plane.
func _emit(kind: StringName, scene: PackedScene, template_point: Vector2, yaw: float, scale: float = 1.0, symmetric: bool = false, props: Dictionary = {}) -> void:
	for k in (1 if symmetric else players):
		var q: Vector2 = rot(template_point, k)
		objects.append({kind = kind, scene = scene, position = Vector3(q.x, surface_height(q), q.y), yaw = yaw - k * _step, scale = scale, props = props})

## Ramp keep-out zones overlap an objective's plateau by design, so objectives
## only need their flattened pad, not the usual body check.
func _place_objectives() -> void:
	for site in _objective_sites:
		var pos: Vector2 = site.pos
		var copies: int = 1 if site.symmetric else players
		var ok: bool = true
		for k in copies:
			if not _footprint_ok(rot(pos, k), _gen.objective_clear_radius, RISE_OBJECTIVE, 0):
				ok = false
		if not ok:
			push_warning("MapGenerator: an objective lost its flat ground and was skipped.")
			continue
		for k in copies:
			_add_body(rot(pos, k), _gen.objective_clear_radius, 0.0, _new_group(), false)
		_emit(&"objective", site.scene, pos, 0.0, 1.0, site.symmetric, site.props)

func _around_base(distance: Vector2) -> Vector2:
	return base_centres[0] + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(distance.x, distance.y)

func _place_base_resources() -> void:
	var gold_spec := {radius = GOLD_RADIUS, gap = 1.5, rise = RISE_GOLD, cliff = CLIFF_CLEARANCE_OBJECTS, solid = true, avoid_paths = true}
	for n in _gen.base_gold_mines:
		_place_with_retries(&"gold", _gen.gold_mine_scene, func(): return [_around_base(_gen.base_gold_distance)], gold_spec)
	if _gen.base_trees > 0:
		var per_clump: int = maxi(1, int(float(_gen.base_trees) / _gen.base_tree_clumps))
		for n in _gen.base_tree_clumps:
			for attempt in SPAWN_ATTEMPTS:
				var centre: Vector2 = _around_base(_gen.base_tree_distance)
				var placed: Array[Vector2] = _place_tree_clump(centre, per_clump)
				if placed.size() >= per_clump * 0.6:
					break

func _place_with_retries(kind: StringName, scene: PackedScene, candidates: Callable, spec: Dictionary) -> bool:
	for attempt in SPAWN_ATTEMPTS:
		var points: Array[Vector2] = []
		points.assign(candidates.call())
		if _try_place_symmetric(points, spec):
			for p in points:
				_emit(kind, scene, p, _rng.randf() * TAU)
			return true
	push_warning("MapGenerator: could not fit %s — try another seed or lower counts." % kind)
	return false

## Grows an organic blob of trunk positions, then keeps whichever points are
## valid in every rotated copy.
func _place_tree_clump(centre: Vector2, count: int) -> Array[Vector2]:
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
	var accepted: Array[Vector2] = _place_symmetric_each(points, spec)
	for p in accepted:
		_emit(&"tree", _gen.tree_scene, p, _rng.randf() * TAU)
	return accepted

func _place_neutral_resources() -> void:
	var keep_out: float = _gen.base_clear_radius + 16.0
	var gold_spec := {radius = GOLD_RADIUS, gap = 2.0, rise = RISE_GOLD, cliff = CLIFF_CLEARANCE_OBJECTS, solid = true, avoid_paths = true}
	for n in _gen.neutral_gold_per_player:
		_place_with_retries(&"gold", _gen.gold_mine_scene, func(): return [_neutral_point(keep_out)], gold_spec)

func _neutral_point(keep_out: float) -> Vector2:
	for attempt in 40:
		var p: Vector2 = _rand_in_sector(0.2, 0.9)
		if _clear_of_bases(p, keep_out):
			return p
	return _rand_in_sector(0.2, 0.9)

## Woodland patches sized by radius: a noise-edged disc filled at tree
## spacing. A site is only used if most of the patch fits, so failed attempts
## don't leave stray fragments behind.
func _place_forest_clusters() -> void:
	var min_radius: float = maxf(_gen.forest_cluster_radius.x, _gen.tree_spacing)
	var max_radius: float = maxf(_gen.forest_cluster_radius.y, min_radius)
	var spacing: float = _gen.tree_spacing
	var spec := {radius = spacing * 0.5, gap = _gen.forest_corridor, rise = RISE_TREE, cliff = CLIFF_CLEARANCE_TREES, solid = true, avoid_paths = true}
	for n in _gen.forest_clusters_per_player:
		for attempt in SPAWN_ATTEMPTS:
			var radius: float = _rng.randf_range(min_radius, max_radius)
			var centre: Vector2 = _rand_in_sector(0.15, 0.95)
			if not _clear_of_bases(centre, _gen.base_clear_radius + radius + 8.0):
				continue
			var points: Array[Vector2] = _forest_blob(centre, radius, spacing)
			if _count_fitting(points, spec) < points.size() * 0.7:
				continue
			for p in _place_symmetric_each(points, spec):
				_emit(&"tree", _gen.tree_scene, p, _rng.randf() * TAU)
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
func _count_fitting(points: Array[Vector2], spec: Dictionary) -> int:
	var probe_group: int = _new_group()
	var fitting: int = 0
	for p in points:
		var ok: bool = true
		for k in players:
			var q: Vector2 = rot(p, k)
			if not _footprint_ok(q, spec.radius, spec.rise, spec.cliff) or _near_path(q, spec.radius + 1.0) \
					or _body_conflict(q, spec.radius, spec.gap, probe_group, []):
				ok = false
				break
		if ok:
			fitting += 1
	return fitting

## Gatherable trees hugging the playable edge, with noise-varied depth and gaps.
func _place_edge_forest() -> void:
	var depth: float = _gen.edge_forest_depth
	if depth <= 0.0:
		return
	var spacing: float = _gen.tree_spacing
	var spec := {radius = spacing * 0.5, gap = _gen.forest_corridor, rise = RISE_TREE, cliff = CLIFF_CLEARANCE_TREES, solid = true, avoid_paths = true, group = _new_group()}
	var candidates: Array[Vector2] = []
	var limit: float = half - _gen.border_width
	var pitch: float = spacing * 1.08
	var steps: int = ceili(limit * 2.0 / pitch)
	var grid_points: Array[Vector2] = []
	for gz in steps:
		for gx in steps:
			grid_points.append(Vector2(-limit + (gx + 0.5) * pitch, -limit + (gz + 0.5) * pitch) + Vector2(_rng.randf_range(-0.2, 0.2), _rng.randf_range(-0.2, 0.2)) * spacing)
	for p in grid_points:
		if absf(wrapf(p.angle() - _angle0, -PI, PI)) > _step * 0.5 or coast_weight(p) > 0.3:
			continue
		var inside: float = edge_distance(p)
		if inside <= 0.0:
			continue
		var local_depth: float = depth * lerpf(0.3, 1.0, clampf(_noise01(p * 0.6) * 1.6 - 0.3, 0.0, 1.0))
		if inside < local_depth:
			candidates.append(p)
	for p in _place_symmetric_each(candidates, spec):
		_emit(&"tree", _gen.tree_scene, p, _rng.randf() * TAU)

func _place_border_trees() -> void:
	var scenes: Array[PackedScene] = []
	scenes.assign(_gen.border_tree_scenes.filter(func(s): return s != null))
	if scenes.is_empty() or _gen.border_width <= 0:
		return
	var spacing: float = _gen.border_tree_spacing
	var group: int = _new_group()
	var attempts: int = int(size * size / (spacing * spacing) * 8.0 / players)
	for n in attempts:
		var p := Vector2(_rng.randf_range(-half + 0.4, half - 0.4), _rng.randf_range(-half + 0.4, half - 0.4))
		if absf(wrapf(p.angle() - _angle0, -PI, PI)) > _step * 0.5 or edge_distance(p) > -0.6 or coast_weight(p) > 0.3:
			continue
		var copies_ok: bool = true
		var pending: Array = []
		for k in players:
			var q: Vector2 = rot(p, k)
			if absf(q.x) > half - 0.4 or absf(q.y) > half - 0.4 or _body_conflict(q, spacing * 0.5, 0.0, group, pending, true):
				copies_ok = false
				break
			pending.append({pos = q, radius = spacing * 0.5, gap = 0.0, group = group, solid = false})
		if not copies_ok:
			continue
		for body in pending:
			_add_body(body.pos, body.radius, body.gap, body.group, body.solid)
		_emit(&"border_tree", scenes[_rng.randi() % scenes.size()], p, _rng.randf() * TAU, _rng.randf_range(0.85, 1.25))

func _place_props() -> void:
	var scenes: Array[PackedScene] = []
	scenes.assign(_gen.prop_scenes.filter(func(s): return s != null))
	if scenes.is_empty():
		return
	var spec := {radius = PROP_RADIUS, gap = 0.4, rise = RISE_PROP, cliff = 1, solid = false}
	var placed: int = 0
	for attempt in _gen.props_per_player * 12:
		if placed >= _gen.props_per_player:
			break
		var points: Array[Vector2] = [_rand_in_sector(0.05, 1.0)]
		if _try_place_symmetric(points, spec):
			_emit(&"prop", scenes[_rng.randi() % scenes.size()], points[0], _rng.randf() * TAU, _rng.randf_range(0.8, 1.2))
			placed += 1

## --- Decals ---

## Paths run from each base to the nearest centre-feature ramp (or the middle).
func _plan_paths() -> void:
	if not _gen.paths_to_centre:
		return
	var base0: Vector2 = base_centres[0]
	var target: Vector2 = Vector2.ZERO
	for ramp in _ramps:
		if ramp.on_centre and ramp.tier == 0 and (ramp.entrance as Vector2).distance_to(base0) < target.distance_to(base0):
			target = ramp.entrance
	_paths.append({a = base0, b = target, width = _gen.path_width, symmetric = false})

func _plan_decals() -> void:
	var base0: Vector2 = base_centres[0]
	_dirt_shapes.append({a = base0, b = base0, width = _gen.base_clear_radius * 1.5, symmetric = false})
	_dirt_shapes.append_array(_paths)
	for ramp in _ramps:
		if ramp.copy == 0 and ramp.tier == 0:
			_dirt_shapes.append({a = ramp.entrance, b = ramp.entrance, width = _gen.ramp_width + 2.0, symmetric = false})
	if not _gen.objectives_on_plateaus:
		for site in _objective_sites:
			_dirt_shapes.append({a = site.pos, b = site.pos, width = _gen.objective_clear_radius * 1.3, symmetric = site.symmetric})
	for n in _gen.dirt_patches_per_player:
		var p: Vector2 = _rand_in_sector(0.1, 0.95)
		_dirt_shapes.append({a = p, b = p + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0.0, 5.0), width = _rng.randf_range(3.0, 7.0), symmetric = false})
	for n in _gen.grass_patches_per_player:
		var p: Vector2 = _rand_in_sector(0.05, 1.0)
		_grass_shapes.append({a = p, b = p + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0.0, 8.0), width = _rng.randf_range(4.0, 10.0), symmetric = false})

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
		for k in (1 if shape.symmetric else players):
			var a: Vector2 = rot(shape.a, k) if not shape.symmetric else shape.a
			var b: Vector2 = rot(shape.b, k) if not shape.symmetric else shape.b
			var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(reach, reach)
			var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(reach, reach)
			for j in range(maxi(0, floori(lo.y + half)), mini(corners - 1, ceili(hi.y + half)) + 1):
				for i in range(maxi(0, floori(lo.x + half)), mini(corners - 1, ceili(hi.x + half)) + 1):
					var p := Vector2(i - half, j - half)
					var d: float = Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p)
					if d > reach:
						continue
					var q: Vector2 = rot(p, -k) if not shape.symmetric else p
					if d < radius * (0.7 + 0.6 * _noise01(q * 1.7)):
						field[j * corners + i] = 1
	return field

## --- Validation ---

func _check_connectivity() -> void:
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
	for t in targets:
		if seen[index(cell_at(t))] == 0:
			push_warning("MapGenerator: %s is not reachable from player 1's base on this seed." % t)
