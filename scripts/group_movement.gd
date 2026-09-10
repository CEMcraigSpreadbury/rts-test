class_name GroupMovement
extends Node
## Host-side group movement planning, split out of main.gd: formation slot
## solving, chokepoint funnelling and reformation (closing ranks when members
## drop out of a formation move). Owns no selection or UI state — only the
## in-flight formation records below — and only ever does work on the host.

## Host-only reformation bookkeeping — one record per in-flight multi-unit
## formation move (see register_formation/update_reformation). Records are
## created when a move is dispatched, polled once a frame to notice members
## dropping out (death, or being pulled into a fight), and dropped as soon as
## fewer than two members are still walking this order. Never networked and
## never touched on a client: only the host ever solves or issues slots.
var _active_formations: Array[Dictionary] = []
## Arranges units into the given Formation.Type shape, oriented to face the
## direction of travel — front rank/slot arrives exactly at target_pos,
## further ranks trail behind it — instead of a fixed screen-space block
## that never rotated with the order. Only matters for the plain-move/
## attack-move fallback in _dispatch_smart_command; a gather/attack/build
## target ignores its assigned position entirely and paths to the target
## node itself. Actual per-shape geometry lives in Formation
## (scripts/formation.gd) — this just builds the facing and hands off to it.
##
## Returned positions are aligned to `units` by index (result[i] is where
## units[i] should go), but which unit gets which shape slot is decided by
## nearest-available-slot assignment (see _assign_slots_to_units), not by
## raw selection order — assigning slot i to units[i] directly would send
## units to whichever slot their index happened to land on regardless of
## where they actually are, causing them to needlessly cross paths to swap
## places with each other.
func formation_positions(units: Array[Unit], target_pos: Vector3, formation_type: Formation.Type = Formation.DEFAULT_TYPE) -> Array[Vector3]:
	if units.is_empty():
		return []
	if units.size() == 1:
		return [target_pos]

	var forward := _group_forward(group_centroid(units), target_pos)
	var right := Vector3(forward.z, 0.0, -forward.x)

	var formation := Formation.new(units, formation_type)
	var slots := formation.get_slot_positions(target_pos, forward, right)

	return _assign_slots_to_units(units, slots)

func group_centroid(units: Array[Unit]) -> Vector3:
	var centroid := Vector3.ZERO
	if units.is_empty():
		return centroid
	for unit in units:
		centroid += unit.global_position
	centroid /= units.size()
	return centroid

## The group's direction of travel, flattened to XZ. Degenerate case (target
## basically on top of the group's own centroid) still needs a facing to build
## `right` from — arbitrary is fine, it only affects which way a
## near-zero-distance formation fans out.
func _group_forward(centroid: Vector3, target_pos: Vector3) -> Vector3:
	var to_target := target_pos - centroid
	to_target.y = 0.0
	return to_target.normalized() if to_target.length_squared() > 0.0001 else Vector3.FORWARD

## Greedy nearest-pair assignment: repeatedly claims the closest remaining
## (unit, slot) pair until every unit has one. Not globally optimal (that's
## the Hungarian algorithm), but for RTS-sized selections this is more than
## good enough and avoids the crossing-paths problem a fixed index mapping has.
func _assign_slots_to_units(units: Array[Unit], slots: Array[Vector3]) -> Array[Vector3]:
	var pairs: Array = []
	for ui in units.size():
		for si in slots.size():
			pairs.append([units[ui].global_position.distance_squared_to(slots[si]), ui, si])
	pairs.sort_custom(func(a, b): return a[0] < b[0])

	var result: Array[Vector3] = []
	result.resize(units.size())
	var unit_taken: Array[bool] = []
	unit_taken.resize(units.size())
	var slot_taken: Array[bool] = []
	slot_taken.resize(slots.size())

	var assigned := 0
	for pair in pairs:
		if assigned >= units.size():
			break
		var ui: int = pair[1]
		var si: int = pair[2]
		if unit_taken[ui] or slot_taken[si]:
			continue
		unit_taken[ui] = true
		slot_taken[si] = true
		result[ui] = slots[si]
		assigned += 1
	return result

## Chokepoint funnelling (see find_funnel_point). How far to either side of the
## route we bother looking for something that constricts it — anything further
## out than this isn't shaping the corridor the group walks down, and treating
## it as "the corridor edge" would make wide-open ground read as a gap.
const CHOKE_PROBE_HALF_WIDTH: float = 12.0
## Granularity of the corridor-width scan along the route, in meters. The gap
## we care about (a gate, a slot between two buildings) is a couple of meters
## across, so anything much finer than this only costs cycles.
const CHOKE_BIN_SIZE: float = 2.0
## Gaps narrower than this aren't a chokepoint to thread, they're a wall. Herding
## the whole group at a waypoint they physically can't squeeze through would be
## strictly worse than letting them path individually, so we leave those alone.
const CHOKE_MIN_GAP: float = 1.0
## How much narrower than the formation a gap has to be before it's worth
## funnelling. Without a margin, a formation that fits with centimeters to spare
## would still trigger the whole two-stage detour for no visible gain.
const CHOKE_WIDTH_MARGIN: float = 1.5
## Funnelling is a group behavior; a pair of units negotiates a gate fine on its
## own and the waypoint detour would just be overhead.
const CHOKE_MIN_UNITS: int = 3
## How far past the gap the funnel waypoint is placed. Has to clear the gap
## itself (so "reached the waypoint" genuinely means "through"), but staying
## modest keeps units fanning out to their slots promptly on the far side.
const CHOKE_EXIT_AHEAD: float = 3.5
## Ignore constrictions this close to either end of the route: one right on top
## of the group is something they're already inside (funnelling backwards into
## it helps nobody), and one at the destination is just the destination being
## tight, which the formation shape itself has to deal with.
const CHOKE_MIN_DISTANCE_FROM_GROUP: float = 5.0
const CHOKE_MIN_DISTANCE_FROM_TARGET: float = 4.0
## Radius of the NavigationObstacle3D a passage's flanking structure carries per
## side (0.2 per post on wall_gate.tscn). It isn't the physical geometry that
## decides whether a unit fits through an opening — RVO steers off obstacle
## centres, so each side effectively reaches this far in on top of its own
## agent-radius standoff.
const CHOKE_PASSAGE_SIDE_RADIUS: float = 0.2
## Narrowest opening worth funnelling a group at. An agent needs its own radius
## plus the flanking obstacle's on BOTH sides before any of it is walkable, so a
## bare agent diameter is nominal rather than protective — a 1.0m opening would
## clear that and still be impassable. Conservative by a little: the obstacles
## sit at the post CENTRES, slightly outside the clear span passage_width
## measures, so real clearance is marginally better than this assumes. A
## passage below it isn't skipped, it stops counting as a doorway and falls
## through to the footprint scan as the blocker it effectively is.
const CHOKE_MIN_PASSAGE_WIDTH: float = (Unit.FORMATION_BASE_RADIUS + CHOKE_PASSAGE_SIDE_RADIUS) * 2.0
## How closely a passage's own axis has to agree with the group's direction of
## travel (|dot|, so either facing counts) before it's accepted. A gate set in a
## wall running alongside the route isn't on the way to anywhere — without this,
## one up to CHOKE_PROBE_HALF_WIDTH off-route would short-circuit the scan and
## drag the formation sideways through a doorway nobody needed. 0.5 is a 60
## degree cone, so an angled but sensible approach still qualifies while a
## near-parallel one (where the through-direction's sign is arbitrary anyway,
## and the waypoint could land on the wrong side of the wall) is rejected.
const CHOKE_PASSAGE_AXIS_DOT: float = 0.5
## Slack added to the formation's raw slot spread to get the width it actually
## needs to pass somewhere — roughly one unit's body diameter (the physical
## CapsuleShape3D radius on scenes/units/unit.tscn is 0.4), since the spread is
## measured between slot centers.
const CHOKE_UNIT_WIDTH: float = 1.0

## Host-side, one-shot-per-order chokepoint analysis: does the route from this
## group's centroid to its destination pass through somewhere narrower than the
## formation is wide? If so, returns the waypoint every unit should thread
## before dispersing to its own slot (see Unit.set_funnel_waypoint), otherwise
## an empty Dictionary and the order dispatches exactly as it always has.
##
## Why geometry and not the navmesh: NavigationBlockers does carve buildings
## out of the region, so the route below already goes *around* them — but a
## navmesh path is a corridor of arbitrary width reduced to a center line, and
## nothing in it says whether the gap it threads is a wide street or a gate
## barely wider than one unit. The navmesh path is used as the route's *shape*
## (so terrain and building detours are both followed), while the corridor
## width along it is measured against the actual building footprints.
##
## Cost: one path query plus one pass over the building list, and only on an
## order that could actually use the answer. No per-frame work and no raycasts.
func find_funnel_point(units: Array[Unit], centroid: Vector3, target_pos: Vector3, slots: Array[Vector3]) -> Dictionary:
	if units.size() < CHOKE_MIN_UNITS:
		return {}
	## Cheap rejections first — everything past this point costs a navmesh path
	## query and a pass over every building on the map, so a formation narrow
	## enough to fit through any gap worth funnelling toward, or a map with
	## nothing built on it, bails before paying for either.
	var required_width := _formation_required_width(slots, centroid, target_pos)
	if required_width < CHOKE_MIN_GAP + CHOKE_WIDTH_MARGIN:
		return {}
	var buildings := get_tree().get_nodes_in_group("buildings")
	if buildings.is_empty():
		return {}

	var route := _route_polyline(units[0], centroid, target_pos)
	if route.size() < 2:
		return {}

	## Cumulative arclength at each route vertex, so a building's projection onto
	## the polyline can be expressed as a single distance-along-route.
	var cumulative: Array[float] = [0.0]
	for i in route.size() - 1:
		cumulative.append(cumulative[i] + _flat_distance(route[i], route[i + 1]))
	var total_length: float = cumulative[cumulative.size() - 1]
	if total_length < CHOKE_MIN_DISTANCE_FROM_GROUP + CHOKE_MIN_DISTANCE_FROM_TARGET:
		return {}

	var bin_count: int = maxi(1, ceili(total_length / CHOKE_BIN_SIZE))
	## Free space remaining on each side of the route center line, per bin, named
	## for the side of the direction of travel they actually describe (`right` is
	## Vector3(forward.z, 0, -forward.x), the same axis the formation shape is
	## built against). Starts "unconstrained" and is whittled down by each
	## building that reaches into the corridor.
	var right_free: Array[float] = []
	var left_free: Array[float] = []
	for i in bin_count:
		right_free.append(CHOKE_PROBE_HALF_WIDTH)
		left_free.append(CHOKE_PROBE_HALF_WIDTH)

	## Nearest walkable opening found on the route, if any — see
	## ProductionBuilding.passage_width and _passage_funnel.
	var best_passage: Dictionary = {}

	for node in buildings:
		var building := node as Node3D
		if building == null or not is_instance_valid(building):
			continue
		var production := building as ProductionBuilding
		if production != null and production.is_destroyed:
			continue
		var hit := _project_onto_route(route, cumulative, building.global_position)
		var arc: float = hit["arc"]
		var lateral: float = hit["lateral_distance"]

		## A gate is a HOLE in a wall, not a blocker, and its footprint describes
		## the structure to either side of that hole rather than the hole itself
		## (wall_gate carries one small obstacle per post, at x = +/-0.85). Run
		## through the obstacle branch below it would read as a solid lump across
		## the very spot units are meant to walk through. Gates are therefore
		## their own kind of candidate: an opening of known width, centred on the
		## node origin.
		##
		## Two things demote one back to an ordinary obstacle rather than skipping
		## it — in both cases it really is blocking the corridor, and the scan
		## should see it as such:
		##   - still under construction (sunk into the ground by
		##     construction_sink_depth, so there's no doorway there yet);
		##   - too narrow for anything to fit through (see
		##     CHOKE_MIN_PASSAGE_WIDTH).
		var passage_width: float = production.passage_width if production != null else 0.0
		if production != null and production.is_under_construction:
			passage_width = 0.0
		if passage_width < CHOKE_MIN_PASSAGE_WIDTH:
			passage_width = 0.0
		if passage_width > 0.0:
			## Wide enough that the formation doesn't have to change shape for
			## it: not a chokepoint at all, and not a blocker either, so it
			## contributes nothing either way.
			if passage_width + CHOKE_WIDTH_MARGIN > required_width:
				continue
			if lateral > CHOKE_PROBE_HALF_WIDTH:
				continue
			if arc < CHOKE_MIN_DISTANCE_FROM_GROUP or arc > total_length - CHOKE_MIN_DISTANCE_FROM_TARGET:
				continue
			## The opening has to actually point the way the group is going. Its
			## axis is the gate's local Z (the structure sits either side of it on
			## local X), flipped where needed so it runs with the route rather
			## than against it.
			var route_forward: Vector3 = _route_point_at(route, cumulative, arc)["forward"]
			var through: Vector3 = building.global_transform.basis.z
			through.y = 0.0
			if through.length_squared() < 0.0001:
				continue
			through = through.normalized()
			var alignment: float = through.dot(route_forward)
			if absf(alignment) < CHOKE_PASSAGE_AXIS_DOT:
				continue
			if alignment < 0.0:
				through = -through
			## Nearest to the route line wins: with several gates in one wall, the
			## one the group is already walking at is the one it should use.
			if best_passage.is_empty() or lateral < float(best_passage["lateral_distance"]):
				best_passage = {"node": building, "lateral_distance": lateral, "through": through}
			continue

		var radius: float = building.get_footprint_radius() if building.has_method("get_footprint_radius") else 0.0
		if radius <= 0.0:
			continue
		var free: float = lateral - radius
		if free > CHOKE_PROBE_HALF_WIDTH:
			continue
		free = maxf(free, 0.0)
		## A building of radius r constricts the corridor over the whole stretch
		## of route it sits alongside, not just the single point it projects to.
		var first_bin: int = clampi(int(floor((arc - radius) / CHOKE_BIN_SIZE)), 0, bin_count - 1)
		var last_bin: int = clampi(int(floor((arc + radius) / CHOKE_BIN_SIZE)), 0, bin_count - 1)
		for b in range(first_bin, last_bin + 1):
			if hit["lateral_sign"] >= 0.0:
				right_free[b] = minf(right_free[b], free)
			else:
				left_free[b] = minf(left_free[b], free)

	## An actual gate on the route beats anything the footprint scan could infer
	## from the wall around it: its width and centre are known exactly rather
	## than measured off neighbouring pieces, and that wall would otherwise
	## register as an impassable stretch and be thrown away below.
	if not best_passage.is_empty():
		return _passage_funnel(best_passage)

	var best_bin: int = -1
	var best_gap: float = INF
	for b in bin_count:
		## Constricted on BOTH sides or it isn't a chokepoint — a single building
		## beside the route is something to walk around, not something to funnel
		## through, and treating it as one edge of a "gap" whose other edge is
		## open ground would fire on any building the group happens to pass.
		if right_free[b] >= CHOKE_PROBE_HALF_WIDTH or left_free[b] >= CHOKE_PROBE_HALF_WIDTH:
			continue
		var arc: float = (b + 0.5) * CHOKE_BIN_SIZE
		if arc < CHOKE_MIN_DISTANCE_FROM_GROUP or arc > total_length - CHOKE_MIN_DISTANCE_FROM_TARGET:
			continue
		var gap: float = right_free[b] + left_free[b]
		if gap < best_gap:
			best_gap = gap
			best_bin = b
	if best_bin < 0 or best_gap < CHOKE_MIN_GAP or best_gap + CHOKE_WIDTH_MARGIN > required_width:
		return {}

	var arc_at_gap: float = (best_bin + 0.5) * CHOKE_BIN_SIZE
	var at := _route_point_at(route, cumulative, arc_at_gap)
	var forward: Vector3 = at["forward"]
	var right := Vector3(forward.z, 0.0, -forward.x)
	## The route center line isn't necessarily the gap's center (the gap can sit
	## off to one side of it) — recenter on the free span actually measured,
	## which runs from -left_free to +right_free along `right`.
	var gap_center: Vector3 = at["position"] + right * ((right_free[best_bin] - left_free[best_bin]) * 0.5)
	return {
		"gap": gap_center,
		"point": gap_center + forward * CHOKE_EXIT_AHEAD,
		"forward": forward,
	}

## Funnel data for a walkable opening (see ProductionBuilding.passage_width).
## Both the gap centre and the direction through it come from the gate's own
## transform rather than from the route: the doorway is centred on the node
## origin and runs along its local Z (already resolved and direction-checked by
## the caller), so a gate approached at an angle still gets a waypoint squarely
## in front of its opening instead of one nudged toward a post.
func _passage_funnel(passage: Dictionary) -> Dictionary:
	var gate: Node3D = passage["node"]
	var through: Vector3 = passage["through"]
	return {
		"gap": gate.global_position,
		"point": gate.global_position + through * CHOKE_EXIT_AHEAD,
		"forward": through,
	}

## Navmesh path when there is one (so the route follows terrain and built-up
## ground rather than cutting through them), straight line otherwise. Only
## ever the *shape* of the route — see find_funnel_point on why the corridor
## width can't come from the navmesh.
func _route_polyline(unit: Unit, from: Vector3, to: Vector3) -> PackedVector3Array:
	var map: RID = unit.nav_agent.get_navigation_map()
	if map.is_valid():
		var path := NavigationServer3D.map_get_path(map, from, to, true)
		if path.size() >= 2:
			return path
	return PackedVector3Array([from, to])

## Closest point on the route polyline to `point`, as distance-along-route
## ("arc"), perpendicular distance, and which side of the route it's on
## (positive = the route's right-hand side, matching the formation's `right`).
func _project_onto_route(route: PackedVector3Array, cumulative: Array[float], point: Vector3) -> Dictionary:
	var best := {"arc": 0.0, "lateral_distance": INF, "lateral_sign": 1.0}
	var flat_point := Vector3(point.x, 0.0, point.z)
	for i in route.size() - 1:
		var a := Vector3(route[i].x, 0.0, route[i].z)
		var b := Vector3(route[i + 1].x, 0.0, route[i + 1].z)
		var segment := b - a
		var length_squared: float = segment.length_squared()
		if length_squared < 0.0001:
			continue
		var t: float = clampf((flat_point - a).dot(segment) / length_squared, 0.0, 1.0)
		var projected: Vector3 = a + segment * t
		var offset: Vector3 = flat_point - projected
		var distance: float = offset.length()
		if distance >= best["lateral_distance"]:
			continue
		var direction: Vector3 = segment.normalized()
		var right := Vector3(direction.z, 0.0, -direction.x)
		best = {
			"arc": cumulative[i] + sqrt(length_squared) * t,
			"lateral_distance": distance,
			"lateral_sign": 1.0 if offset.dot(right) >= 0.0 else -1.0,
		}
	return best

## Inverse of _project_onto_route: the world position `arc` meters along the
## route, plus the direction of travel there.
func _route_point_at(route: PackedVector3Array, cumulative: Array[float], arc: float) -> Dictionary:
	for i in route.size() - 1:
		var segment_length: float = cumulative[i + 1] - cumulative[i]
		if segment_length < 0.0001:
			continue
		if arc > cumulative[i + 1] and i < route.size() - 2:
			continue
		var t: float = clampf((arc - cumulative[i]) / segment_length, 0.0, 1.0)
		var direction: Vector3 = route[i + 1] - route[i]
		direction.y = 0.0
		return {
			"position": route[i].lerp(route[i + 1], t),
			"forward": direction.normalized() if direction.length_squared() > 0.0001 else Vector3.FORWARD,
		}
	return {"position": route[0], "forward": Vector3.FORWARD}

## How wide a corridor this formation actually needs: the lateral spread of its
## slots (measured on the same left/right axis the shape was built against, so
## trailing ranks don't inflate it) plus one unit's body width, since the spread
## is between slot centers.
func _formation_required_width(slots: Array[Vector3], centroid: Vector3, target_pos: Vector3) -> float:
	if slots.size() < 2:
		return 0.0
	var forward := _group_forward(centroid, target_pos)
	var right := Vector3(forward.z, 0.0, -forward.x)
	var smallest: float = INF
	var largest: float = -INF
	for slot in slots:
		var lateral: float = (slot - target_pos).dot(right)
		smallest = minf(smallest, lateral)
		largest = maxf(largest, lateral)
	return (largest - smallest) + CHOKE_UNIT_WIDTH

## Arms the funnel waypoint on one unit, unless it's already past the gap — a
## unit on the far side would otherwise be sent backwards through the
## chokepoint just to come back out again.
func apply_funnel(unit: Unit, funnel: Dictionary) -> void:
	var forward: Vector3 = funnel["forward"]
	var offset: Vector3 = unit.global_position - funnel["gap"]
	offset.y = 0.0
	if offset.dot(forward) > 0.0:
		return
	unit.set_funnel_waypoint(funnel["point"], forward)

func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(b.x - a.x, b.z - a.z).length()

## -1 (no override) for a single-unit selection — see Unit.formation_speed.
func slowest_move_speed(units: Array[Unit]) -> float:
	if units.size() <= 1:
		return -1.0
	var slowest: float = units[0].move_speed
	for unit in units:
		slowest = minf(slowest, unit.move_speed)
	return slowest

## ---------------------------------------------------------------------------
## Reformation
##
## A formation is solved once, at order time (formation_positions). Without
## anything else that layout is frozen for the whole journey: if four of a
## twelve-unit box die on the way, the eight survivors keep walking to their
## original twelve-slot layout and arrive as a block with four holes in it,
## and a group scattered by a fight or an obstacle never pulls itself back
## together. The two entry points below fix exactly that and nothing else —
## they re-solve and re-issue slots, and never change how a shape is generated
## (Formation), how cohesion paces it (Unit._update_cohesion) or how the
## funnel threads it (find_funnel_point):
##   — automatic: update_reformation polls each live formation record for
##     members dropping out and closes ranks around the survivors;
##   — explicit: _issue_reform_order (FORMATION_REFORM_KEY) re-tightens the
##     current selection around its own centroid.
## Both are host-side. The explicit one is a plain RPC to the server exactly
## like a move order; no formation state is ever predicted or solved client-side.
## ---------------------------------------------------------------------------

## How long a record waits after noticing it lost members before re-solving.
## Deaths cluster — a volley of arrows or an area ability takes several units
## out of one group in the same frame or across a handful of frames — and
## re-solving per death would issue a full re-path per casualty for what the
## player reads as a single event. Waiting a beat batches the whole burst into
## one re-solve, and re-arming the timer on each further loss means a group
## being steadily ground down re-forms once when the bleeding stops rather
## than continuously mid-fight.
const REFORM_DEBOUNCE: float = 0.4
## Retry delay when a re-solve is due but the group is mid-chokepoint. Slots
## must not move while units are threading a gap (see Unit.is_funnelling), so
## the re-solve waits for the last member through — Unit's own FUNNEL_TIMEOUT
## guarantees that always eventually happens.
const REFORM_FUNNEL_RETRY: float = 0.3
## Facing an explicit re-form falls back to when the group has no usable
## average heading (see group_facing).
const REFORM_DEFAULT_FORWARD: Vector3 = Vector3.FORWARD

## Starts tracking a dispatched multi-unit formation move. `group` is the exact
## array instance handed to those units as their cohesion group — it doubles as
## this order's identity token, since a unit later given any other order gets a
## different (or empty) formation_group, which is what _formation_record_members
## uses to tell "still walking this order" from "has moved on". Single-unit and
## non-formation dispatches carry an empty group and are never tracked.
func register_formation(group: Array[Unit], target_pos: Vector3, formation_type: Formation.Type, attack_move: bool) -> void:
	if not multiplayer.is_server() or group.size() < 2:
		return
	var members := _formation_record_members(group)
	if members.size() < 2:
		return
	## No need to hunt down an older record these units were in: they are
	## carrying this new group array now, so they no longer read as live
	## members of it and the next poll retires it on its own.
	_active_formations.append({
		"group": group,
		"target": target_pos,
		"type": formation_type,
		"attack_move": attack_move,
		"count": members.size(),
		"timer": 0.0,
		"dirty": false,
	})

## The members of `group` still actually walking this order: alive, still on a
## move/attack-move command, and still carrying this exact group array. A unit
## that died, was given a new order, or peeled off into a fight drops out here
## — which is both how ranks-closing notices a loss and how a record eventually
## retires itself.
func _formation_record_members(group: Array[Unit]) -> Array[Unit]:
	var members: Array[Unit] = []
	for unit in group:
		if unit == null or not is_instance_valid(unit) or unit.status_activity == Unit.Activity.DEAD:
			continue
		if unit.status_command != Unit.Command.MOVE and unit.status_command != Unit.Command.ATTACK_MOVE:
			continue
		if not is_same(unit.formation_group, group):
			continue
		members.append(unit)
	return members

## Polled once a frame on the host. Notices a record losing members (the common
## cause being death mid-move, but a unit yanked into a fight or given a fresh
## order counts the same way), waits out REFORM_DEBOUNCE so a burst of losses
## collapses into a single re-solve, then re-solves the shape for whoever is
## left — closing the holes the dead units' slots would otherwise leave.
## Polling membership rather than hooking each individual death is what keeps
## this one batched check no matter how many units die at once, and it also
## covers hand-placed units that never went through the spawner's signal wiring.
func update_reformation(delta: float) -> void:
	if not multiplayer.is_server() or _active_formations.is_empty():
		return
	for i in range(_active_formations.size() - 1, -1, -1):
		var record: Dictionary = _active_formations[i]
		var group: Array[Unit] = record["group"]
		var members := _formation_record_members(group)
		## Nothing left to hold a shape: everyone arrived, died, or moved on.
		if members.size() < 2:
			_active_formations.remove_at(i)
			continue
		if members.size() < int(record["count"]):
			record["count"] = members.size()
			record["dirty"] = true
			record["timer"] = REFORM_DEBOUNCE
		if not record["dirty"]:
			continue
		record["timer"] = float(record["timer"]) - delta
		if record["timer"] > 0.0:
			continue
		## Never re-solve slots out from under a group that is mid-gap: a
		## funnelled unit is deliberately steered at a shared waypoint with its
		## real slot parked away until it's through, and re-issuing here would
		## send it straight at a far-side slot through whatever it was being
		## funnelled around. Retried, not dropped — the group re-forms as soon
		## as the last member clears the gap.
		if any_funnelling(members):
			record["timer"] = REFORM_FUNNEL_RETRY
			continue
		record["dirty"] = false
		reform_group(members, record["target"], record["type"], record["attack_move"])
		## The re-issue hands the survivors a new group array as their cohesion
		## group, so the record has to follow it or every member would read as
		## "moved on" on the very next poll.
		record["group"] = members

func any_funnelling(units: Array[Unit]) -> bool:
	for unit in units:
		if unit.is_funnelling():
			return true
	return false

## Re-issues a formation move for `units`, re-solved for their current count.
## Goes through command_move/command_attack_move directly rather than
## _dispatch_smart_command: there is no target node to re-resolve (a gather/
## attack/build order never had formation slots to begin with), and this is a
## continuation of an order the player already gave, so it deliberately plays
## no order sound and never touches order_queue — anything shift-queued behind
## this leg still runs when this leg completes. command_move re-baselines
## cohesion for the new leg on its own (Unit._set_formation_cohesion), which is
## exactly what a re-solved slot needs, and clears any stale funnel with it.
func reform_group(units: Array[Unit], target_pos: Vector3, formation_type: Formation.Type, attack_move: bool, forward_override: Vector3 = Vector3.ZERO) -> void:
	var slots: Array[Vector3] = formation_positions(units, target_pos, formation_type) if forward_override == Vector3.ZERO \
			else _reform_positions(units, target_pos, formation_type, forward_override)
	var speed := slowest_move_speed(units)
	for i in units.size():
		if attack_move:
			units[i].command_attack_move(slots[i], speed, units)
		else:
			units[i].command_move(slots[i], speed, units)

## Same slot solve as formation_positions, but with the group's facing supplied
## rather than derived from (target - centroid): an explicit re-form is centered
## on the group's own centroid, so there is no direction of travel to derive a
## facing from and every re-form would otherwise come out pointing the same
## arbitrary way (see _group_forward's degenerate case).
func _reform_positions(units: Array[Unit], target_pos: Vector3, formation_type: Formation.Type, forward: Vector3) -> Array[Vector3]:
	if units.is_empty():
		return []
	if units.size() == 1:
		return [target_pos]
	var right := Vector3(forward.z, 0.0, -forward.x)
	var formation := Formation.new(units, formation_type)
	return _assign_slots_to_units(units, formation.get_slot_positions(target_pos, forward, right))

## The group's average heading, taken from the direction each unit is actually
## facing (units rotate toward their movement direction, so after a move or a
## fight this is where they were last heading/looking). Averaged as vectors
## rather than angles so opposing headings cancel instead of averaging into a
## meaningless midpoint — a group facing every which way after a brawl falls
## back to the default instead of inheriting one member's spin.
func group_facing(units: Array[Unit]) -> Vector3:
	var facing := Vector3.ZERO
	for unit in units:
		facing += Vector3(sin(unit.rotation.y), 0.0, cos(unit.rotation.y))
	facing.y = 0.0
	return facing.normalized() if facing.length_squared() > 0.0001 else REFORM_DEFAULT_FORWARD
