@tool
class_name MapLayout
extends RefCounted
## The data half of MapGenerator: a height grid (ground / plateau / ramp),
## decal corner fields, and every object placement, all derived from the seed.
##
## Fairness comes from rotational symmetry. Every feature is authored once for
## player 0's slice (the "template") and then rotated by TAU / players for
## everyone else, so each base gets the same terrain, resources and distances.
## Object placements are only accepted if every rotated copy is valid. With 2
## or 4 players the rotations map grid cells onto grid cells exactly; with
## other counts terrain matches to within a tile.

const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const TC_OFFSET: Vector2 = Vector2(-4.0, 4.0)
const SPAWN_ATTEMPTS: int = 80
const GOLD_RADIUS: float = 1.7
const PROP_RADIUS: float = 0.6
const CLIFF_CLEARANCE_TREES: int = 3
const CLIFF_CLEARANCE_OBJECTS: int = 2

var size: int
var half: float
var players: int
var height: int
var ramp_length: int

var level := PackedInt32Array()
var ramp_dir := PackedInt32Array()
var ramp_step := PackedInt32Array()
## Surface height a ramp climbs from (0 for ground ramps, higher for tiers).
var ramp_base := PackedInt32Array()
var playable := PackedByteArray()
var dirt := PackedByteArray()
var grass := PackedByteArray()

var base_centres: Array[Vector2] = []
var spawn_positions: Array[Vector3] = []
## {kind: StringName, scene: PackedScene, position: Vector3, yaw: float, scale: float}
var objects: Array[Dictionary] = []

var _gen: MapGenerator
var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
var _angle0: float
var _step: float
var _exact_grid_symmetry: bool
var _plateaus: Array[Dictionary] = []
var _ramps: Array[Dictionary] = []
var _objective_sites: Array[Dictionary] = []
var _paths: Array[Dictionary] = []
var _dirt_shapes: Array[Dictionary] = []
var _grass_shapes: Array[Dictionary] = []
var _cliff_distance := PackedInt32Array()
## Placement blockers: {pos: Vector2, radius: float, gap: float, group: int, solid: bool}
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
	height = _gen.plateau_height
	ramp_length = height * 2
	_step = TAU / players
	_angle0 = deg_to_rad(_gen.layout_rotation_degrees)
	_exact_grid_symmetry = 4 % players == 0
	_rng.seed = _gen.map_seed
	_noise.seed = _gen.map_seed
	_noise.frequency = 0.09
	_noise.fractal_octaves = 2

	var cells: int = size * size
	level.resize(cells)
	level.fill(0)
	ramp_dir.resize(cells)
	ramp_dir.fill(-1)
	ramp_step.resize(cells)
	ramp_step.fill(0)
	ramp_base.resize(cells)
	ramp_base.fill(0)
	playable.resize(cells)
	for z in size:
		for x in size:
			playable[z * size + x] = 1 if is_playable(cell_centre(Vector2i(x, z))) else 0

	_place_bases()
	_plan_objectives()
	_plan_plateaus()
	_rasterize_plateaus()
	_clean_plateaus()
	_place_ramps()
	_compute_cliff_distance()
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

func is_ramp(c: Vector2i) -> bool:
	return ramp_dir[index(c)] >= 0

func is_playable_cell(c: Vector2i) -> bool:
	return in_bounds(c) and playable[index(c)] == 1

## Signed distance (in metres) from p to the playable boundary: positive inside.
func edge_distance(p: Vector2) -> float:
	var limit: float = half - _gen.border_width
	var best: float = INF
	for k in players:
		var q: Vector2 = rot(p, k)
		best = minf(best, limit - maxf(absf(q.x), absf(q.y)))
	return best

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

## Height of the walkable surface at the given edge of a cell, which is what
## decides whether a cliff wall is needed between two neighbours.
func edge_height(c: Vector2i, dir_index: int) -> float:
	var i: int = index(c)
	var d: int = ramp_dir[i]
	if d < 0:
		return float(level[i])
	var slope: float = float(height) / ramp_length
	if dir_index == d:
		return ramp_base[i] + ramp_step[i] * slope
	if dir_index == (d + 2) % 4:
		return ramp_base[i] + (ramp_step[i] + 1) * slope
	return ramp_base[i] + (ramp_step[i] + 0.5) * slope

func surface_height(p: Vector2) -> float:
	var c: Vector2i = cell_at(p)
	if not in_bounds(c):
		return 0.0
	var i: int = index(c)
	if ramp_dir[i] < 0:
		return float(level[i])
	var d: Vector2 = Vector2(DIRS[ramp_dir[i]])
	var slope: float = float(height) / ramp_length
	return ramp_base[i] + (ramp_step[i] + 0.5) * slope - (p - cell_centre(c)).dot(d) * slope

func _rotate_cell(c: Vector2i, k: int) -> Vector2i:
	return cell_at(rot(cell_centre(c), k))

func _rand_in_sector(r_min: float, r_max: float) -> Vector2:
	var angle: float = _angle0 + _rng.randf_range(-0.5, 0.5) * _step
	var reach: float = _edge_distance_along(angle)
	return Vector2.from_angle(angle) * _rng.randf_range(r_min, r_max) * reach

func _noise01(p: Vector2) -> float:
	return _noise.get_noise_2dv(p) * 0.5 + 0.5

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

## --- Objectives & plateaus (template frame) ---

## Width of the ledge a lower tier keeps around the tier above it: room for
## that tier's inset ramp, its landing, and a little walking space.
func _tier_ring() -> float:
	return ramp_length + 3.0

func _objective_plateau_half() -> float:
	return _gen.objective_clear_radius + ramp_length + 1.5 + (_gen.objective_plateau_tiers - 1) * _tier_ring()

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

func _plan_plateaus() -> void:
	if _gen.objectives_on_plateaus:
		var h: float = _objective_plateau_half()
		for site in _objective_sites:
			var plateau := {centre = site.pos, half = Vector2(h, h), radius = 3.0, symmetric = site.symmetric, tiers = _gen.objective_plateau_tiers}
			if site.symmetric:
				plateau.half = Vector2(h, h) * 1.05
				plateau.radius = plateau.half.x
			_plateaus.append(plateau)
	var min_half: float = maxf(_gen.plateau_half_size.x, ramp_length + 3.0 + (_gen.plateau_tiers - 1) * _tier_ring())
	var max_half: float = maxf(_gen.plateau_half_size.y, min_half)
	for n in _gen.plateaus_per_player:
		var placed: bool = false
		for attempt in 300:
			var extents := Vector2(_rng.randf_range(min_half, max_half), _rng.randf_range(min_half, max_half))
			var reach: float = extents.length()
			var p: Vector2 = _rand_in_sector(0.2, 0.95)
			if edge_distance(p) < reach + 6.0:
				continue
			if not _clear_of_bases(p, _gen.base_clear_radius + reach + 10.0):
				continue
			if not _clear_of_sites(p, reach + 5.0):
				continue
			if not _clear_of_plateaus(p, reach):
				continue
			if _self_copies_too_close(p, reach * 2.0 + 6.0):
				continue
			_plateaus.append({centre = p, half = extents, radius = minf(extents.x, extents.y) * _rng.randf_range(0.2, 0.6), symmetric = false, tiers = _gen.plateau_tiers})
			placed = true
			break
		if not placed:
			push_warning("MapGenerator: no room for extra plateau %d." % (n + 1))

func _clear_of_plateaus(p: Vector2, reach: float) -> bool:
	for plateau in _plateaus:
		var other: float = (plateau.half as Vector2).length()
		for k in players:
			if rot(p, k).distance_to(plateau.centre) < reach + other + 6.0:
				return false
	return true

## A copy's plateau sits at the exactly rotated position but keeps a
## quarter-turn orientation, so its cliffs stay straight enough for ramps.
func _grid_aligned_angle(k: int) -> float:
	return roundf(k * _step / (PI * 0.5)) * PI * 0.5

func _in_rounded_rect(q: Vector2, extents: Vector2, radius: float) -> bool:
	var r: float = minf(radius, minf(extents.x, extents.y))
	var d: Vector2 = q.abs() - (extents - Vector2(r, r))
	return Vector2(maxf(d.x, 0.0), maxf(d.y, 0.0)).length() + minf(maxf(d.x, d.y), 0.0) <= r

func _rasterize_plateaus() -> void:
	for plateau in _plateaus:
		var copies: int = 1 if plateau.symmetric else players
		var reach: float = (plateau.half as Vector2).length() + 1.0
		for k in copies:
			var centre: Vector2 = rot(plateau.centre, k)
			var lo: Vector2i = cell_at(centre - Vector2(reach, reach))
			var hi: Vector2i = cell_at(centre + Vector2(reach, reach))
			for z in range(maxi(lo.y, 0), mini(hi.y, size - 1) + 1):
				for x in range(maxi(lo.x, 0), mini(hi.x, size - 1) + 1):
					var c := Vector2i(x, z)
					if playable[index(c)] == 0:
						continue
					var q: Vector2 = (cell_centre(c) - centre).rotated(-_grid_aligned_angle(k))
					for t in range(plateau.tiers - 1, -1, -1):
						var extents: Vector2 = plateau.half - Vector2.ONE * _tier_ring() * t
						var radius: float = extents.x if plateau.symmetric else plateau.radius
						if extents.x > 0.0 and extents.y > 0.0 and _in_rounded_rect(q, extents, radius):
							level[index(c)] = maxi(level[index(c)], (t + 1) * height)
							break

## Each tier is smoothed on its own (closing then opening with a cross-shaped
## element removes one-tile slivers and notches, which make paper-thin
## cliffs), then kept at least a few cells inside the tier below.
func _clean_plateaus() -> void:
	var top_tier: int = 0
	for value in level:
		top_tier = maxi(top_tier, floori(float(value) / height))
	var masks: Array[PackedByteArray] = []
	for t in range(1, top_tier + 1):
		var mask := PackedByteArray()
		mask.resize(level.size())
		for i in level.size():
			mask[i] = 1 if level[i] >= t * height and playable[i] == 1 else 0
		mask = _morph(_morph(_morph(_morph(mask, true), false), false), true)
		if not masks.is_empty():
			var inside: PackedInt32Array = _distance_inside(masks[masks.size() - 1])
			for i in mask.size():
				if inside[i] < 3:
					mask[i] = 0
			mask = _morph(_morph(mask, false), true)
		masks.append(mask)
	for i in level.size():
		var tiers: int = 0
		for mask in masks:
			tiers += mask[i]
		level[i] = tiers * height

func _morph(source: PackedByteArray, dilate: bool) -> PackedByteArray:
	var result: PackedByteArray = source.duplicate()
	for z in size:
		for x in size:
			var c := Vector2i(x, z)
			var hits: int = 0
			for d in DIRS:
				var n: Vector2i = c + d
				if in_bounds(n) and source[index(n)] == 1:
					hits += 1
			var i: int = index(c)
			if dilate and source[i] == 0 and hits >= 3 and playable[i] == 1:
				result[i] = 1
			elif not dilate and source[i] == 1 and hits < 2:
				result[i] = 0
	return result

## Cells inside `mask`, measured in steps to the nearest cell outside it.
func _distance_inside(mask: PackedByteArray) -> PackedInt32Array:
	var distance := PackedInt32Array()
	distance.resize(mask.size())
	distance.fill(1 << 20)
	var frontier: Array[Vector2i] = []
	for z in size:
		for x in size:
			var c := Vector2i(x, z)
			if mask[index(c)] == 0:
				distance[index(c)] = 0
				frontier.append(c)
	var head: int = 0
	while head < frontier.size():
		var c: Vector2i = frontier[head]
		head += 1
		for d in DIRS:
			var n: Vector2i = c + d
			if in_bounds(n) and distance[index(n)] > distance[index(c)] + 1:
				distance[index(n)] = distance[index(c)] + 1
				frontier.append(n)
	return distance

## --- Ramps ---

func _snap_dir(v: Vector2) -> int:
	if absf(v.x) >= absf(v.y):
		return 1 if v.x > 0.0 else 3
	return 2 if v.y > 0.0 else 0

## Each tier's ramps turn a quarter (or, on the centre, half a slice) from
## the tier below, so climbing means walking round the ledge in between.
func _place_ramps() -> void:
	for plateau in _plateaus:
		var centre: Vector2 = plateau.centre
		var turn: float = _step * 0.5 if plateau.symmetric else PI * 0.5
		for t in plateau.tiers:
			var from: int = t * height
			for base_dir in _ramp_directions(plateau):
				var v: Vector2 = base_dir.rotated(turn * t)
				var ramp0: Dictionary = _find_ramp(centre, _snap_dir(v), from)
				for k in players:
					var ramp: Dictionary = {}
					if k == 0:
						ramp = ramp0
					elif _exact_grid_symmetry and not ramp0.is_empty():
						ramp = _rotated_ramp(ramp0, k)
					else:
						ramp = _find_ramp(centre if plateau.symmetric else rot(centre, k), _snap_dir(rot(v, k)), from)
					_commit_ramp(ramp, k, plateau.symmetric)

## Template-frame directions each plateau's ramps descend toward: the first
## faces the nearest base (or, for the centre, one ramp per player).
func _ramp_directions(plateau: Dictionary) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if plateau.symmetric:
		result.append(base_centres[0].normalized())
		return result
	var centre: Vector2 = plateau.centre
	var primary: Vector2 = (base_centres[0] - centre).normalized()
	var toward_middle: Vector2 = -centre.normalized()
	var candidates: Array[Vector2] = [primary, -primary, toward_middle, primary.orthogonal(), -primary.orthogonal()]
	for v in candidates:
		if result.size() >= _gen.ramps_per_plateau:
			break
		var taken: bool = false
		for existing in result:
			if _snap_dir(existing) == _snap_dir(v):
				taken = true
		if not taken:
			result.append(v)
	return result

func _find_ramp(centre: Vector2, d: int, from: int) -> Dictionary:
	var to: int = from + height
	var start: Vector2i = cell_at(centre)
	if not in_bounds(start) or level[index(start)] < to:
		return {}
	var step: Vector2i = DIRS[d]
	var boundary: Vector2i = start
	while in_bounds(boundary + step) and level[index(boundary + step)] >= to:
		boundary += step
	var perp: Vector2i = DIRS[(d + 1) % 4]
	for offset in [0, 1, -1, 2, -2, 3, -3, 4, -4, 5, -5, 6, -6]:
		var foot: Vector2i = boundary + perp * offset
		while in_bounds(foot) and level[index(foot)] >= to and in_bounds(foot + step) and level[index(foot + step)] >= to:
			foot += step
		var ramp := {foot = foot, dir = d, from = from}
		if _ramp_valid(ramp):
			return ramp
	return {}

func _rotated_ramp(ramp: Dictionary, k: int) -> Dictionary:
	var quarter: int = k * int(4.0 / players)
	return {foot = _rotate_cell(ramp.foot, k), dir = (int(ramp.dir) + quarter) % 4, from = ramp.from}

func _ramp_cells(ramp: Dictionary) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var step: Vector2i = DIRS[ramp.dir]
	var perp: Vector2i = DIRS[(int(ramp.dir) + 1) % 4]
	var hw: int = _gen.ramp_width >> 1
	for s in range(-hw, hw + 1):
		for i in ramp_length:
			cells.append(ramp.foot + perp * s - step * i)
	return cells

func _ramp_valid(ramp: Dictionary) -> bool:
	var step: Vector2i = DIRS[ramp.dir]
	var perp: Vector2i = DIRS[(int(ramp.dir) + 1) % 4]
	var hw: int = _gen.ramp_width >> 1
	for s in range(-hw - 1, hw + 2):
		var edge: bool = absi(s) == hw + 1
		for i in range(-2, ramp_length + 2):
			var c: Vector2i = ramp.foot + perp * s - step * i
			if not is_playable_cell(c):
				return false
			var inside_plateau: bool = level[index(c)] == int(ramp.from) + height and not is_ramp(c)
			if i < 0:
				if not edge and (level[index(c)] != ramp.from or is_ramp(c)):
					return false
			elif i < ramp_length:
				if not inside_plateau:
					return false
			elif not edge and not inside_plateau:
				return false
	return true

func _commit_ramp(ramp: Dictionary, copy: int, on_centre: bool) -> void:
	if ramp.is_empty() or not _ramp_valid(ramp):
		push_warning("MapGenerator: a plateau could not fit a ramp — it will be unreachable unless another ramp exists.")
		return
	var i: int = 0
	for c in _ramp_cells(ramp):
		ramp_dir[index(c)] = ramp.dir
		ramp_step[index(c)] = i % ramp_length
		ramp_base[index(c)] = ramp.from
		i += 1
	var step: Vector2 = Vector2(DIRS[ramp.dir])
	var foot: Vector2 = cell_centre(ramp.foot)
	ramp.entrance = foot + step * 2.0
	ramp.landing = foot - step * (ramp_length + 1.0)
	ramp.copy = copy
	ramp.on_centre = on_centre
	_ramps.append(ramp)
	_add_body(ramp.entrance, _gen.ramp_width * 0.5 + 2.5, 0.0, _new_group(), false)
	_add_body(ramp.landing, _gen.ramp_width * 0.5 + 1.5, 0.0, _new_group(), false)
	var mid: Vector2 = foot - step * (ramp_length - 1) * 0.5
	_add_body(mid, (ramp_length + _gen.ramp_width) * 0.5, 0.0, _new_group(), false)

## Multi-source BFS distance (in cells) from any cell that is not flat ground.
func _compute_cliff_distance() -> void:
	_cliff_distance.resize(size * size)
	_cliff_distance.fill(1 << 20)
	var frontier: Array[Vector2i] = []
	for z in size:
		for x in size:
			var c := Vector2i(x, z)
			if level[index(c)] > 0 or is_ramp(c):
				_cliff_distance[index(c)] = 0
				frontier.append(c)
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

## True if the disc at p sits on one flat, playable surface of the given level
## with the required clearance from cliffs and ramps.
func _footprint_ok(p: Vector2, radius: float, required_level: int, cliff_clearance: int) -> bool:
	var centre: Vector2i = cell_at(p)
	if not is_playable_cell(centre) or is_ramp(centre):
		return false
	if required_level >= 0 and level[index(centre)] != required_level:
		return false
	if edge_distance(p) < radius + 0.5:
		return false
	var surface: int = level[index(centre)]
	if surface == 0 and _cliff_distance[index(centre)] < cliff_clearance:
		return false
	var r: int = ceili(radius + 0.5)
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var c: Vector2i = centre + Vector2i(dx, dz)
			if cell_centre(c).distance_to(p) > radius + 0.75:
				continue
			if not is_playable_cell(c) or is_ramp(c) or level[index(c)] != surface:
				return false
	return true

func _near_path(p: Vector2, clearance: float) -> bool:
	for path in _paths:
		for k in players:
			var a: Vector2 = rot(path.a, k)
			var b: Vector2 = rot(path.b, k)
			if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) < path.width * 0.5 + clearance:
				return true
	return false

## Validates every rotated copy of the template points together; commits all
## or nothing. `spec`: {radius, gap, level, cliff, solid, avoid_paths}.
func _try_place_symmetric(points: Array[Vector2], spec: Dictionary) -> bool:
	var pending: Array = []
	var groups: Array[int] = []
	for k in players:
		groups.append(_new_group())
	for k in players:
		for p in points:
			var q: Vector2 = rot(p, k)
			if not _footprint_ok(q, spec.radius, spec.level, spec.cliff):
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
			if not _footprint_ok(q, spec.radius, spec.level, spec.cliff) \
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
## only need flat ground, not the usual body check.
func _place_objectives() -> void:
	for site in _objective_sites:
		var pos: Vector2 = site.pos
		var surface: int = level[index(cell_at(pos))]
		var copies: int = 1 if site.symmetric else players
		var ok: bool = true
		for k in copies:
			if not _footprint_ok(rot(pos, k), _gen.objective_clear_radius, surface, 0):
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
	var gold_spec := {radius = GOLD_RADIUS, gap = 1.5, level = 0, cliff = CLIFF_CLEARANCE_OBJECTS, solid = true, avoid_paths = true}
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
	var spec := {radius = spacing * 0.5, gap = _gen.forest_corridor, level = 0, cliff = CLIFF_CLEARANCE_TREES, solid = true, avoid_paths = true}
	var accepted: Array[Vector2] = _place_symmetric_each(points, spec)
	for p in accepted:
		_emit(&"tree", _gen.tree_scene, p, _rng.randf() * TAU)
	return accepted

func _place_neutral_resources() -> void:
	var keep_out: float = _gen.base_clear_radius + 16.0
	var gold_spec := {radius = GOLD_RADIUS, gap = 2.0, level = 0, cliff = CLIFF_CLEARANCE_OBJECTS, solid = true, avoid_paths = true}
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
	var spec := {radius = spacing * 0.5, gap = _gen.forest_corridor, level = 0, cliff = CLIFF_CLEARANCE_TREES, solid = true, avoid_paths = true}
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
			if not _footprint_ok(q, spec.radius, spec.level, spec.cliff) or _near_path(q, spec.radius + 1.0) \
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
	var spec := {radius = spacing * 0.5, gap = _gen.forest_corridor, level = 0, cliff = CLIFF_CLEARANCE_TREES, solid = true, avoid_paths = true, group = _new_group()}
	var candidates: Array[Vector2] = []
	var limit: float = half - _gen.border_width
	var pitch: float = spacing * 1.08
	var steps: int = ceili(limit * 2.0 / pitch)
	var grid_points: Array[Vector2] = []
	for gz in steps:
		for gx in steps:
			grid_points.append(Vector2(-limit + (gx + 0.5) * pitch, -limit + (gz + 0.5) * pitch) + Vector2(_rng.randf_range(-0.2, 0.2), _rng.randf_range(-0.2, 0.2)) * spacing)
	for p in grid_points:
		if absf(wrapf(p.angle() - _angle0, -PI, PI)) > _step * 0.5:
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
		if absf(wrapf(p.angle() - _angle0, -PI, PI)) > _step * 0.5 or edge_distance(p) > -0.6:
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
	var spec := {radius = PROP_RADIUS, gap = 0.4, level = -1, cliff = 1, solid = false}
	var placed: int = 0
	for attempt in _gen.props_per_player * 12:
		if placed >= _gen.props_per_player:
			break
		var points: Array[Vector2] = [_rand_in_sector(0.05, 1.0)]
		if _try_place_symmetric(points, spec):
			_emit(&"prop", scenes[_rng.randi() % scenes.size()], points[0], _rng.randf() * TAU, _rng.randf_range(0.8, 1.2))
			placed += 1

## --- Decals ---

## Paths run from each base to the nearest centre-plateau ramp (or the middle).
func _plan_paths() -> void:
	if not _gen.paths_to_centre:
		return
	var base0: Vector2 = base_centres[0]
	var target: Vector2 = Vector2.ZERO
	for ramp in _ramps:
		if ramp.on_centre and ramp.from == 0 and ramp.entrance.distance_to(base0) < target.distance_to(base0):
			target = ramp.entrance
	_paths.append({a = base0, b = target, width = _gen.path_width, symmetric = false})

func _plan_decals() -> void:
	var base0: Vector2 = base_centres[0]
	_dirt_shapes.append({a = base0, b = base0, width = _gen.base_clear_radius * 1.5, symmetric = false})
	_dirt_shapes.append_array(_paths)
	for ramp in _ramps:
		if ramp.copy == 0 and ramp.from == 0:
			_dirt_shapes.append({a = ramp.entrance, b = ramp.entrance, width = _gen.ramp_width + 2.0, symmetric = false})
	for site in _objective_sites:
		if level[index(cell_at(site.pos))] == 0:
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

## Samples shapes at cell corners (the decal tiles are picked from these by
## marching squares). Noise is read in the template frame so copies match.
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

func corner_mask(field: PackedByteArray, c: Vector2i) -> int:
	var corners: int = size + 1
	var top: int = c.y * corners + c.x
	var bottom: int = top + corners
	return field[top] * 8 + field[top + 1] * 4 + field[bottom] * 2 + field[bottom + 1]

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
			if not is_playable_cell(n) or seen[index(n)] == 1 or blocked[index(n)] == 1:
				continue
			if absf(edge_height(c, d) - edge_height(n, (d + 2) % 4)) > 0.3:
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
