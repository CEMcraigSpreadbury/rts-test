class_name AiBaseBuilder
extends RefCounted
## AiPlayer's base building: the build order (Mines, Barracks, Archery Range, Stables — see
## AiProfile's "Build Order" group), finding a sensible spot for anything that
## goes on open ground, and pointing every military building's rally at the
## base's staging point.
##
## Site rules, so the base doesn't wall itself in: nothing hugs the Town
## Center, every building keeps a gap around it for units to walk through,
## Houses go behind the base (away from the map's middle) and military
## buildings in front, and nothing is dropped on the path between the Town
## Center and its Mines.

## Buildings placed by a build-order step of their own rather than by what
## they train (see _type_named / _military_type).
const BLACKSMITH_NAME: String = "Blacksmith"
const ARCANE_SANCTUM_NAME: String = "Arcane Sanctum"
const NAMED_STEP_BUILDINGS: Array[String] = [BLACKSMITH_NAME, ARCANE_SANCTUM_NAME]

## Walking room kept around every AI building, on top of its footprint.
const SITE_CLEARANCE: float = 1.6
## Extra room kept clear right around the Town Center (villagers queue up to
## drop off there, and new units spawn there).
const TOWN_CENTER_CLEARANCE: float = 4.0
const SITE_RING_STEP: float = 2.5
const SITE_MAX_RADIUS: float = 32.0
## How strongly Houses prefer the back of the base and military buildings the
## front, against simply staying close to home.
const SITE_FACING_WEIGHT: float = 6.0
## Candidate spots actually tested per search (each costs a few physics
## queries). Generous, since the favoured side of a base is often forest; a
## search that still finds nothing isn't repeated for SITE_RETRY_SECONDS.
const SITE_TESTS_PER_SEARCH: int = 160
## Kept clear either side of the Town Center-to-Mine walk.
const MINE_LANE_HALF_WIDTH: float = 2.5
## Deposits further than this from home aren't claimed...
const MAX_DEPOSIT_DISTANCE: float = 60.0
## ...unless every Mine of ours has run dry.
const MAX_DEPOSIT_DISTANCE_WHEN_DRY: float = 100.0
const DANGER_RADIUS_SITE: float = 12.0
## How far in front of the Town Center new units gather.
const STAGING_DISTANCE: float = 12.0

## A construction site that makes no progress for this long (builders keep
## failing to reach it) is given up on — see is_abandoned.
const SITE_STALL_SECONDS: float = 75.0
## How near the end of a navmesh path must get to a deposit/site for it to
## count as reachable (both are carved out of the navmesh themselves).
const DEPOSIT_REACH_TOLERANCE: float = 4.0
const SITE_REACH_TOLERANCE: float = 1.5

var ai: AiPlayer
## BuildingType -> true for types whose last site search found nothing, so a
## cramped base doesn't pay for a full search every think. Cleared every
## SITE_RETRY_SECONDS.
var _no_site: Dictionary = {}
var _no_site_cleared_at: float = 0.0
const SITE_RETRY_SECONDS: float = 10.0
var _staging_point: Variant = null
## Construction site -> [last seen progress, game_time it last changed].
var _site_progress: Dictionary = {}
## Construction sites given up on. There's no way to cancel a construction,
## so they just stand there; the AI stops sending builders and doesn't count
## them as owned.
var _abandoned: Dictionary = {}

func _init(p_ai: AiPlayer) -> void:
	ai = p_ai

func think() -> void:
	if ai.game_time - _no_site_cleared_at > SITE_RETRY_SECONDS:
		_no_site.clear()
		_no_site_cleared_at = ai.game_time
	_watch_sites()
	_follow_build_order()
	_set_rally_points()

func is_abandoned(building: ProductionBuilding) -> bool:
	return _abandoned.has(building)

func _watch_sites() -> void:
	for building in ai.my_buildings:
		if not building.is_under_construction or _abandoned.has(building):
			continue
		var entry: Array = _site_progress.get(building, [-1.0, ai.game_time])
		if building.construction_progress > entry[0]:
			entry = [building.construction_progress, ai.game_time]
		elif ai.game_time - entry[1] > SITE_STALL_SECONDS:
			_abandoned[building] = true
		_site_progress[building] = entry
	## Forget finished/destroyed sites. Keys are checked with is_instance_valid
	## before any typed use — freed buildings stay in here until this runs.
	for key in _site_progress.keys():
		if not is_instance_valid(key) or not key.is_under_construction:
			_site_progress.erase(key)
	for key in _abandoned.keys():
		if not is_instance_valid(key):
			_abandoned.erase(key)

## Starts at most one build-order building per think, earliest step first.
func _follow_build_order() -> void:
	var p: AiProfile = ai.profile
	var villagers: int = ai.villagers.size()
	var mines: Array[BuildingType] = ai.types_with_role(AiPlayer.BuildingRole.MINE)
	var barracks: BuildingType = _military_type(AiPlayer.UnitRole.INFANTRY)
	var archery_range: BuildingType = _military_type(AiPlayer.UnitRole.RANGED)
	var stables: BuildingType = _military_type(AiPlayer.UnitRole.CAVALRY)
	var steps: Array = []
	if not mines.is_empty():
		steps.append([mines[0], p.first_mine_at_villagers, 1])
		steps.append([mines[0], p.second_mine_at_villagers, 2])
	if barracks != null:
		steps.append([barracks, p.barracks_at_villagers, 1])
		steps.append([barracks, p.second_barracks_at_villagers, 2])
	if archery_range != null:
		steps.append([archery_range, p.archery_range_at_villagers, 1])
	if stables != null:
		steps.append([stables, p.stables_at_villagers, 1])
	var blacksmith: BuildingType = _type_named(BLACKSMITH_NAME)
	if blacksmith != null:
		steps.append([blacksmith, p.blacksmith_at_villagers, 1])
	var sanctum: BuildingType = _type_named(ARCANE_SANCTUM_NAME)
	if sanctum != null:
		steps.append([sanctum, p.arcane_sanctum_at_villagers, 1])
	steps.sort_custom(func(a, b): return a[1] < b[1])
	for step in steps:
		var type: BuildingType = step[0]
		var at_villagers: int = step[1]
		var wanted: int = step[2]
		if at_villagers < 0 or villagers < at_villagers:
			continue
		var owned: int = _working_mines() if ai.building_roles[type] == AiPlayer.BuildingRole.MINE else ai.count_owned(type)
		if owned >= wanted:
			continue
		## Nowhere to put this one right now: let the next step have a go
		## rather than stalling the whole order on it.
		if try_construct(type) or not _no_site.has(type):
			return

## Mines still sitting on a deposit with gold left (a Mine outlives its
## deposit, and then only a new one helps).
func _working_mines() -> int:
	var count := 0
	for building in ai.my_buildings:
		if ai.building_role(building) != AiPlayer.BuildingRole.MINE or _abandoned.has(building):
			continue
		var deposit = building.linked_deposit
		if is_instance_valid(deposit) and deposit.amount_remaining > 0:
			count += 1
	return count

## The military building type that trains `role` (infantry -> barracks,
## ranged -> archery range, cavalry -> stables); of several, the one that
## trains the most kinds. Only the cavalry lookup may return a cavalry trainer.
## Types with a build-order step of their own are left out, or the Arcane
## Sanctum (whose Wizards are ranged) could be mistaken for the Archery Range.
func _military_type(role: AiPlayer.UnitRole) -> BuildingType:
	var best: BuildingType = null
	var best_count := -1
	for type in ai.types_with_role(AiPlayer.BuildingRole.MILITARY):
		if NAMED_STEP_BUILDINGS.has(type.building_name):
			continue
		var roles: Array = ai.roles_trained_by_type(type)
		if not roles.has(role):
			continue
		if roles.has(AiPlayer.UnitRole.CAVALRY) != (role == AiPlayer.UnitRole.CAVALRY):
			continue
		if roles.size() > best_count:
			best_count = roles.size()
			best = type
	return best

## One of this player's own buildable types by name, for the build-order
## steps that can't be found by what the building trains.
func _type_named(building_name: String) -> BuildingType:
	for type in ai.building_roles:
		if type.building_name == building_name:
			return type
	return null

## Places `type` and sends builders, if it can be paid for now. Can't pay:
## its cost is set aside (see AiPlayer.reserved) so cheaper things wait.
func try_construct(type: BuildingType) -> bool:
	var costs: Array[ResourceCost] = ai.building_costs.get(type, [] as Array[ResourceCost])
	if not ai.can_afford(costs):
		ai.reserve(costs)
		return false
	if _no_site.has(type):
		return false
	var pos := Vector3.ZERO
	var target_path := NodePath()
	if type.requires_deposit:
		var deposit := _pick_deposit(type)
		if deposit == null:
			_no_site[type] = true
			return false
		pos = deposit.global_position
		target_path = deposit.get_path()
	else:
		var site = find_site(type)
		if site == null:
			_no_site[type] = true
			return false
		pos = site
	var builders: Array[Unit] = ai.economy.pick_builders(pos, maxi(ai.profile.builders_per_site, 1))
	if builders.is_empty():
		return false
	var paths: Array[NodePath] = []
	for unit in builders:
		paths.append(unit.get_path())
	return ai.main.placement.request_build_as(ai.peer_id, ai.building_type_index[type], pos, target_path, paths, false) != null

## Nearest unclaimed deposit to home that's out of harm's way and can be
## walked to. Our own side of the map while there's a choice — a mine out by
## the middle is a gift to whoever passes — but once no Mine of ours has gold
## left, anywhere safe beats an army with nothing to buy it with.
func _pick_deposit(type: BuildingType) -> Gatherable:
	var own_side_only: bool = _working_mines() > 0
	var max_distance: float = MAX_DEPOSIT_DISTANCE if own_side_only else MAX_DEPOSIT_DISTANCE_WHEN_DRY
	var candidates: Array = []
	for node in ai.get_tree().get_nodes_in_group("gatherables"):
		var deposit := node as Gatherable
		if deposit == null or deposit.is_claimed or not ai.main.placement.is_matching_deposit(deposit, type):
			continue
		var distance: float = deposit.global_position.distance_to(ai.home)
		if own_side_only and distance > deposit.global_position.distance_to(ai.map_centre):
			continue
		if distance <= max_distance and not ai.is_dangerous(deposit.global_position):
			candidates.append([distance, deposit])
	candidates.sort_custom(func(a, b): return a[0] < b[0])
	for candidate in candidates:
		var deposit: Gatherable = candidate[1]
		if ai.is_reachable(deposit.global_position, DEPOSIT_REACH_TOLERANCE):
			return deposit
	return null

## A valid open-ground spot for `type` near home, or null. Rings of
## candidates around the Town Center, best-scored first (see the class notes).
func find_site(type: BuildingType) -> Variant:
	var radius: float = type.footprint_radius
	var is_house: bool = ai.building_roles.get(type) == AiPlayer.BuildingRole.HOUSE
	var away: Vector3 = ai.away_from_centre()
	var tc_radius: float = ai.town_center.get_footprint_radius() if ai.town_center != null else 2.5
	var lanes := _mine_lanes()
	var candidates: Array = []
	var r: float = tc_radius + radius + TOWN_CENTER_CLEARANCE
	while r <= SITE_MAX_RADIUS:
		var steps: int = maxi(8, int(TAU * r / 3.0))
		for i in steps:
			var angle: float = TAU * i / steps
			var offset := Vector3(cos(angle), 0.0, sin(angle))
			var pos: Vector3 = ai.home + offset * r
			if _blocks_lane(pos, radius, lanes):
				continue
			var facing: float = offset.dot(away)
			var score: float = r - facing * SITE_FACING_WEIGHT if is_house else r + facing * SITE_FACING_WEIGHT
			candidates.append([score, pos])
		r += SITE_RING_STEP
	candidates.sort_custom(func(a, b): return a[0] < b[0])
	var tests := 0
	for candidate in candidates:
		if tests >= SITE_TESTS_PER_SEARCH:
			break
		var pos: Vector3 = candidate[1]
		if _near_objective(pos):
			continue
		tests += 1
		var ground = ai.ground_at(pos)
		if ground == null or not ai.on_navmesh(ground):
			continue
		if not ai.main.placement.is_area_clear(ground, radius + SITE_CLEARANCE):
			continue
		if ai.main.placement.can_place_at(ground, type, ai.peer_id) and ai.is_reachable(ground, SITE_REACH_TOLERANCE):
			return ground
	return null

func _near_objective(pos: Vector3) -> bool:
	for objective in ai.objectives:
		if is_instance_valid(objective) and objective.global_position.distance_to(pos) < DANGER_RADIUS_SITE:
			return true
	return false

## [from, to] for each of our Mines — the villagers' walk to and fro.
func _mine_lanes() -> Array:
	var lanes: Array = []
	for building in ai.my_buildings:
		if ai.building_role(building) == AiPlayer.BuildingRole.MINE and not _abandoned.has(building):
			lanes.append([ai.home, building.global_position])
	return lanes

func _blocks_lane(pos: Vector3, radius: float, lanes: Array) -> bool:
	for lane in lanes:
		var closest := Geometry3D.get_closest_point_to_segment(pos, lane[0], lane[1])
		if Vector2(closest.x - pos.x, closest.z - pos.z).length() < radius + MINE_LANE_HALF_WIDTH:
			return true
	return false

## --- Rally ---

## In front of the Town Center, towards the map's middle, on walkable ground.
func staging_point() -> Vector3:
	if _staging_point != null:
		return _staging_point
	var wanted: Vector3 = ai.home - ai.away_from_centre() * STAGING_DISTANCE
	## Not remembered until it can be snapped onto walkable ground.
	if not ai.nav_ready():
		return wanted
	_staging_point = ai.nearest_navmesh_point(wanted)
	return _staging_point

func _set_rally_points() -> void:
	for building in ai.my_buildings:
		if building.is_under_construction or building.has_rally_point or not building.can_rally:
			continue
		if ai.building_role(building) != AiPlayer.BuildingRole.MILITARY:
			continue
		ai.main.set_rally_point_as(ai.peer_id, building.get_path(), staging_point(), NodePath())
