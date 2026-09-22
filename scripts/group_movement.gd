class_name GroupMovement
extends Node
## Host-side group movement planning, split out of main.gd: formation slot
## solving, chokepoint funnelling and reformation (closing ranks when members
## drop out of a formation move). Owns no selection or UI state — only the
## in-flight formation records below — and only ever does work on the host.

const UnitGrid = preload("res://scripts/unit_grid.gd")

## The host's instance, for units handing it enemies met on a group
## attack-move (see formation_contact).
static var current: GroupMovement = null

func _enter_tree() -> void:
	current = self

func _exit_tree() -> void:
	if current == self:
		current = null

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
##
## `forward_override` supplies the group's facing instead of deriving it from
## (target - centroid) — an explicit re-form is centred on the group's own
## centroid, and a dragged formation (see Main's right-drag) was told its facing
## by the player, so neither has a direction of travel worth deriving one from.
## `front_width` is a dragged front-rank width, see Formation.front_width.
func formation_positions(units: Array[Unit], target_pos: Vector3, formation_type: Formation.Type = Formation.DEFAULT_TYPE, forward_override: Vector3 = Vector3.ZERO, front_width: float = -1.0) -> Array[Vector3]:
	if units.is_empty():
		return []
	if units.size() == 1:
		return [target_pos]

	var forward := order_facing(units, target_pos, forward_override)
	var right := Vector3(forward.z, 0.0, -forward.x)

	## A regiment holds its places. Its men keep the arrangement they were
	## raised in, so a block that turns, is re-targeted or closes up after
	## losses rotates as one body — where re-matching every man to his nearest
	## slot made the whole formation break apart and reassemble on every
	## order. Only whole, single regiments qualify; a mixed or partial
	## selection has no shared arrangement to keep and matches as before.
	if _sole_regiment_id(units) >= 0:
		return _regiment_places(units, target_pos, forward, right, formation_type, front_width)

	var formation := Formation.new(units, formation_type, front_width)
	var slots := formation.get_slot_positions(target_pos, forward, right)
	## A group that is going to march (see _start_march) keeps its current
	## arrangement: units are matched to slots by where they stand WITHIN the
	## group rather than by raw distance, so the block translates instead of
	## shuffling ranks on the way. A short hop still takes nearest slots.
	var relative := _flat_distance(group_centroid(units), target_pos) >= MARCH_MIN_DISTANCE
	return _assign_slots_to_units(units, slots, forward, relative)

## A regiment's front, taken from whichever of its men still carries one,
## rather than requiring all of them to agree as held_facing does for a loose
## group. Reinforcements, a newly assigned officer and men pulled back out of
## a fight all arrive carrying no front of their own, and a single one of
## those would otherwise leave the whole block with none — which is exactly
## when it stops noticing it has been ordered to turn about, and marches
## through itself to get there.
static func _regiment_front(units: Array[Unit]) -> Vector3:
	for unit in units:
		if unit.formation_facing != Vector3.ZERO:
			return unit.formation_facing
	return Vector3.ZERO

## How far behind the rear rank an officer rides.
const OFFICER_STANDOFF: float = 2.4

## A regiment's places, with the officer given his own ground behind the block
## rather than a slot among the men.
##
## Keeping him out of the grid is what lets the men lay out as whole ranks: a
## body of N men plus an officer was laid out as N+1, leaving a ragged back
## row that shuffled every time the block turned. It is also how he should
## read on the field — a commander behind his men, not one of them.
func _regiment_places(units: Array[Unit], target_pos: Vector3, forward: Vector3, right: Vector3, formation_type: Formation.Type, front_width: float) -> Array[Vector3]:
	var men: Array[Unit] = []
	var officers := 0
	for unit in units:
		if unit.is_officer:
			officers += 1
		else:
			men.append(unit)
	if men.is_empty():
		var lone: Array[Vector3] = []
		for i in units.size():
			lone.append(target_pos)
		return lone
	var formation := Formation.new(men, formation_type, front_width)
	var slots := formation.get_slot_positions(target_pos, forward, right)
	var places := _held_positions(men, slots)
	var out: Array[Vector3] = []
	var next_man := 0
	var next_officer := 0
	for unit in units:
		if unit.is_officer:
			out.append(officer_ground(target_pos, forward, slots, next_officer, officers))
			next_officer += 1
		else:
			out.append(places[next_man])
			next_man += 1
	return out

## Where an officer stands: behind the rearmost rank, on the block's centre
## line, spread sideways if a body somehow has more than one.
func officer_ground(front_centre: Vector3, forward: Vector3, slots: Array[Vector3], index: int, count: int) -> Vector3:
	var right := Vector3(forward.z, 0.0, -forward.x)
	var deepest := 0.0
	for slot in slots:
		deepest = maxf(deepest, (front_centre - slot).dot(forward))
	var across: float = (index - (count - 1) * 0.5) * Formation.SPACING
	return front_centre - forward * (deepest + OFFICER_STANDOFF) + right * across

## The regiment `units` all belong to, or -1 if they are not one body.
static func _sole_regiment_id(units: Array[Unit]) -> int:
	var id: int = units[0].regiment_id
	if id < 0:
		return -1
	for unit in units:
		if unit.regiment_id != id:
			return -1
	return id

## Slots handed out in the order the men hold their places: the front rank
## goes to the lowest ranks, the officer (highest of all) to the back, and a
## body that has taken losses closes up rather than re-solving.
static func _held_positions(units: Array[Unit], slots: Array[Vector3]) -> Array[Vector3]:
	## Officers are held out of the ordering and put behind the block either
	## way — turning about must not march the commander to the front rank.
	var order: Array[int] = []
	var officers: Array[int] = []
	for i in units.size():
		if units[i].regiment_rank >= Regiment.OFFICER_RANK:
			officers.append(i)
		else:
			order.append(i)
	order.sort_custom(func(a, b): return units[a].regiment_rank < units[b].regiment_rank)
	order.append_array(officers)
	var out: Array[Vector3] = []
	out.resize(units.size())
	for place in order.size():
		out[order[place]] = slots[mini(place, slots.size() - 1)]
	return out

## Which way a formation order faces. An explicit facing (a drag, a re-form)
## always wins. Otherwise a group already holding a front keeps it for anything
## ahead of or beside it and about-faces for anything behind it — the rear rank
## becomes the front and everyone just turns round, rather than the whole block
## pivoting to point at the click. A group with no shared front (fresh from
## training, or pulled together from different places) faces its way of travel.
func order_facing(units: Array[Unit], target_pos: Vector3, forward_override: Vector3 = Vector3.ZERO) -> Vector3:
	if forward_override != Vector3.ZERO:
		return forward_override
	var travel := _group_forward(group_centroid(units), target_pos)
	var held := held_facing(units)
	if held == Vector3.ZERO:
		return travel
	return held if travel.dot(held) >= 0.0 else -held

## The front every member of `units` is holding from its last formation order
## (see Unit.formation_facing), or ZERO if they don't all share one.
func held_facing(units: Array[Unit]) -> Vector3:
	if units.is_empty():
		return Vector3.ZERO
	var shared: Vector3 = units[0].formation_facing
	if shared == Vector3.ZERO:
		return Vector3.ZERO
	for unit in units:
		if unit.formation_facing.dot(shared) < 0.99:
			return Vector3.ZERO
	return shared

## The facing a dragged formation takes: square to the drag line, on the left
## of the drag direction as seen from above (Total War / Cossacks: drag left to
## right and the block faces up the screen), so the player picks which way it
## faces — including back toward where it stands now — by which end they start
## from. The front rank lands on the line itself. Client-side (it drives the
## preview) and sent with the order, so the host builds exactly the shape the
## player saw instead of re-deriving it from its own unit positions.
func drag_facing(units: Array[Unit], line_start: Vector3, line_end: Vector3) -> Vector3:
	var along := line_end - line_start
	along.y = 0.0
	if along.length_squared() < 0.0001:
		return _group_forward(group_centroid(units), line_start)
	along = along.normalized()
	return Vector3(along.z, 0.0, -along.x)

## Slot layout for a dragged formation, in shape order rather than assigned to
## units — only for drawing the preview; the order itself goes through
## formation_positions on the host with the same inputs.
func drag_preview_slots(units: Array[Unit], line_start: Vector3, line_end: Vector3, facing: Vector3) -> Array[Vector3]:
	var midpoint := (line_start + line_end) * 0.5
	var right := Vector3(facing.z, 0.0, -facing.x)
	var front_width := _flat_distance(line_start, line_end)
	## Officers are kept out of the ranks and shown behind the block, so the
	## preview is the shape the order will actually make. Appended last, which
	## is what lets the preview mark them out (see drag_preview_officers).
	var men: Array[Unit] = []
	var officers := 0
	for unit in units:
		if unit.is_officer:
			officers += 1
		else:
			men.append(unit)
	if men.is_empty():
		men = units
		officers = 0
	var formation := Formation.new(men, Formation.DEFAULT_TYPE, front_width)
	var slots := formation.get_slot_positions(midpoint, facing, right)
	for i in officers:
		slots.append(officer_ground(midpoint, facing, slots, i, officers))
	return slots

## How many of drag_preview_slots' places belong to officers — the trailing
## ones, drawn apart from the ranks.
func drag_preview_officers(units: Array[Unit]) -> int:
	var officers := 0
	var men := 0
	for unit in units:
		if unit.is_officer:
			officers += 1
		else:
			men += 1
	return officers if men > 0 else 0

## Host-side memory of right-drag formations (see Unit.dragged_formation).
## A dragged order (front_width >= 0) stamps its units with a fresh shared id,
## its width and the formation type selected at the time. A later order without
## a width reuses the remembered one only while every unit still carries the
## same id — the selection is that dragged group, or what's left of it — and
## the player hasn't picked a different formation type since; anything else
## forms up in the selected type and forgets the dragged shape.
var _next_dragged_formation_id: int = 1

func resolve_dragged_width(units: Array[Unit], formation_type: Formation.Type, front_width: float) -> float:
	if units.is_empty():
		return front_width
	if front_width >= 0.0:
		var memory := {"id": _next_dragged_formation_id, "width": front_width, "type": formation_type}
		_next_dragged_formation_id += 1
		for unit in units:
			unit.dragged_formation = memory
		return front_width
	var shared: Dictionary = units[0].dragged_formation
	var keep: bool = not shared.is_empty() and shared["type"] == formation_type
	if keep:
		for unit in units:
			if unit.dragged_formation.get("id", -1) != shared["id"]:
				keep = false
				break
	if keep:
		return shared["width"]
	for unit in units:
		unit.dragged_formation = {}
	return front_width

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

## Past this many units the all-pairs greedy match below (n² pairs, sorted)
## gives way to the rank sweep — on 250 units the greedy match alone was most
## of a 200 ms hitch on the order.
const GREEDY_ASSIGN_MAX_UNITS: int = 48
## Slots whose depth behind the front differs by less than this share a rank.
const RANK_DEPTH_TOLERANCE: float = 0.25

func _assign_slots_to_units(units: Array[Unit], slots: Array[Vector3], forward: Vector3, relative: bool = false) -> Array[Vector3]:
	if units.size() <= GREEDY_ASSIGN_MAX_UNITS:
		return _assign_slots_greedy(units, slots, relative)
	return _assign_slots_by_rank(units, slots, forward)

## Rank sweep, O(n log n): the frontmost units (by depth along `forward`) take
## the front rank's slots, the next ones the rank behind, and so on; within a
## rank they pair up left to right. Nobody crosses anybody else's path, and a
## block that's already formed up keeps its arrangement. Only orderings along
## `forward` and `right` matter, so it needs no centring for a relative match.
## Keys are Vector2(projection, index) so the built-in sort orders them
## without a per-comparison script callback.
func _assign_slots_by_rank(units: Array[Unit], slots: Array[Vector3], forward: Vector3) -> Array[Vector3]:
	var right := Vector3(forward.z, 0.0, -forward.x)
	var count: int = mini(units.size(), slots.size())
	var slot_keys: Array[Vector2] = []
	var unit_keys: Array[Vector2] = []
	for i in count:
		slot_keys.append(Vector2(-slots[i].dot(forward), i))
		unit_keys.append(Vector2(-units[i].global_position.dot(forward), i))
	slot_keys.sort()
	unit_keys.sort()

	var result: Array[Vector3] = []
	result.resize(units.size())
	var start := 0
	while start < count:
		var end := start + 1
		while end < count and slot_keys[end].x - slot_keys[start].x < RANK_DEPTH_TOLERANCE:
			end += 1
		var rank_slots: Array[Vector2] = []
		var rank_units: Array[Vector2] = []
		for k in range(start, end):
			var slot_index := int(slot_keys[k].y)
			var unit_index := int(unit_keys[k].y)
			rank_slots.append(Vector2(slots[slot_index].dot(right), slot_index))
			rank_units.append(Vector2(units[unit_index].global_position.dot(right), unit_index))
		rank_slots.sort()
		rank_units.sort()
		for k in rank_slots.size():
			result[int(rank_units[k].y)] = slots[int(rank_slots[k].y)]
		start = end
	return result

## Greedy nearest-pair assignment: repeatedly claims the closest remaining
## (unit, slot) pair until every unit has one. Not globally optimal (that's
## the Hungarian algorithm), but for small selections this is more than
## good enough and avoids the crossing-paths problem a fixed index mapping has.
func _assign_slots_greedy(units: Array[Unit], slots: Array[Vector3], relative: bool = false) -> Array[Vector3]:
	var unit_origin := Vector3.ZERO
	var slot_origin := Vector3.ZERO
	if relative:
		unit_origin = group_centroid(units)
		for slot in slots:
			slot_origin += slot
		slot_origin /= slots.size()
	var pairs: Array = []
	for ui in units.size():
		var from := units[ui].global_position - unit_origin
		from.y = 0.0
		for si in slots.size():
			var to := slots[si] - slot_origin
			to.y = 0.0
			pairs.append([from.distance_squared_to(to), ui, si])
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
	var last := route.size() - 2
	if last < 0:
		return {"position": route[0] if not route.is_empty() else Vector3.ZERO, "forward": Vector3.FORWARD}
	## The segment `arc` falls on, found by binary search over the cumulative
	## lengths — a march looks this up several times per member per re-steer.
	var i: int = clampi(cumulative.bsearch(arc) - 1, 0, last)
	while i < last and cumulative[i + 1] - cumulative[i] < 0.0001:
		i += 1
	var segment_length: float = cumulative[i + 1] - cumulative[i]
	if segment_length < 0.0001:
		return {"position": route[0], "forward": Vector3.FORWARD}
	var t: float = clampf((arc - cumulative[i]) / segment_length, 0.0, 1.0)
	var direction: Vector3 = route[i + 1] - route[i]
	direction.y = 0.0
	return {
		"position": route[i].lerp(route[i + 1], t),
		"forward": direction.normalized() if direction.length_squared() > 0.0001 else Vector3.FORWARD,
	}

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
## `forward` is the order's resolved facing (see order_facing): kept so closing
## ranks keeps the block's front, and stamped on every member as the front it
## now holds. `front_width` is kept for a dragged formation so closing ranks
## keeps the shape the player laid out rather than falling back to the default.
## `speed_cap` holds the march to at most that pace (see formation_attack).
## `start_march` false records the formation without planning a march for it —
## for an order whose block is going to stop and fight before it has walked
## anywhere, where the route would be planned and thrown away in the same
## breath (see Main.issue_command_as).
func register_formation(group: Array[Unit], target_pos: Vector3, formation_type: Formation.Type, attack_move: bool, forward: Vector3 = Vector3.ZERO, front_width: float = -1.0, speed_cap: float = INF, start_march: bool = true) -> Dictionary:
	if not multiplayer.is_server() or group.size() < 2:
		return {}
	var members := _formation_record_members(group)
	if members.size() < 2:
		return {}
	for unit in members:
		unit.formation_facing = forward
	## A group attack-move is remembered on its members, so the group can stop
	## to fight as a block and pick the march back up afterwards.
	if attack_move:
		var order := {
			"units": members.duplicate(),
			"target": target_pos,
			"type": formation_type,
			"forward": forward,
			"front_width": front_width,
		}
		for unit in members:
			unit.attack_move_order = order
	## No need to hunt down an older record these units were in: they are
	## carrying this new group array now, so they no longer read as live
	## members of it and the next poll retires it on its own.
	var record := {
		"group": group,
		"slots": _slot_map(members),
		"target": target_pos,
		"type": formation_type,
		"attack_move": attack_move,
		"forward": forward,
		"front_width": front_width,
		"count": members.size(),
		"timer": 0.0,
		"dirty": false,
		"march": false,
		"attack_target": null,
		"fight_id": -1,
		"speed_cap": speed_cap,
	}
	if start_march:
		_start_march(record, members)
	_active_formations.append(record)
	return record

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
	if not multiplayer.is_server():
		return
	var engagements_start := Time.get_ticks_usec() if PerfStats.enabled else 0
	_update_engagements(delta)
	if PerfStats.enabled:
		PerfStats.add_section(&"march: engagements", Time.get_ticks_usec() - engagements_start)
	if _active_formations.is_empty():
		return
	for i in range(_active_formations.size() - 1, -1, -1):
		var record: Dictionary = _active_formations[i]
		var holding_start := Time.get_ticks_usec() if PerfStats.enabled else 0
		var members := _record_holding(record)
		if PerfStats.enabled:
			PerfStats.add_section(&"march: holding", Time.get_ticks_usec() - holding_start)
		## Nothing left to hold a shape (everyone died or moved on), or nothing
		## left to close ranks on the way to (everyone still here has arrived).
		if members.size() < 2 or not _any_walking(record, members):
			_active_formations.remove_at(i)
			continue
		if members.size() < int(record["count"]):
			record["count"] = members.size()
			record["dirty"] = true
			record["timer"] = REFORM_DEBOUNCE
		var advance_start := Time.get_ticks_usec() if PerfStats.enabled else 0
		_advance_march(record, members, delta)
		if PerfStats.enabled:
			PerfStats.add_section(&"march: advance", Time.get_ticks_usec() - advance_start)
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
		var reform_start := Time.get_ticks_usec() if PerfStats.enabled else 0
		record["dirty"] = false
		reform_group(members, record["target"], record["type"], record["attack_move"], record["forward"], record["front_width"])
		## Re-issuing the move ended any formation fight; the block is still
		## on its way to fight, so pick it back up.
		## Keyed on the engagement, not the target: by now the target may well
		## be dead and freed, and the block is still fighting.
		if int(record["fight_id"]) >= 0:
			var fight_target = record["attack_target"] if is_instance_valid(record["attack_target"]) else null
			for unit in members:
				unit.begin_formation_fight(fight_target, unit.formation_slot(), record["fight_id"])
		## The re-issue hands the survivors a new group array as their cohesion
		## group, so the record has to follow it or every member would read as
		## "moved on" on the very next poll.
		record["group"] = members
		record["slots"] = _slot_map(members)
		## The re-issue dropped everyone off the march; pick it back up from
		## where the anchor already is, with offsets for the re-solved slots.
		if record["march"]:
			for march in record["marches"]:
				march["slots"] = record["slots"]
				_set_march_offsets(march, _march_members(march, members))
				_set_route_offsets(march)
		if PerfStats.enabled:
			PerfStats.add_section(&"march: reform", Time.get_ticks_usec() - reform_start)

## How far an idle member that finished this order (Unit.arrived_group) may
## have been nudged off its slot — by separation in a crowd, or by settling
## short of a slot it couldn't reach — and still count as holding it.
const HOLD_SLOT_DISTANCE: float = 4.0

## unit -> the slot its current formation order is taking it to.
func _slot_map(units: Array[Unit]) -> Dictionary:
	var slots: Dictionary = {}
	for unit in units:
		slots[unit] = unit.formation_slot()
	return slots

## A record's members still holding its formation: alive, and either still
## walking this order or standing idle on the slot it gave them. Arriving
## clears a unit's formation_group (see Unit._apply_velocity), so going
## by the group alone read every arrival as a loss and re-solved the
## stragglers into slots the arrivals were already standing in.
func _record_holding(record: Dictionary) -> Array[Unit]:
	var slots: Dictionary = record["slots"]
	var holding: Array[Unit] = []
	for unit in slots:
		if not is_instance_valid(unit) or unit.status_activity == Unit.Activity.DEAD:
			continue
		var arrived: bool = unit.holds_place() \
				and is_same(unit.arrived_group, record["group"]) \
				and _flat_distance(unit.global_position, slots[unit]) <= HOLD_SLOT_DISTANCE
		if arrived or _is_walking(record, unit):
			holding.append(unit)
	return holding

func _is_walking(record: Dictionary, unit: Unit) -> bool:
	return (unit.status_command == Unit.Command.MOVE or unit.status_command == Unit.Command.ATTACK_MOVE) \
			and is_same(unit.formation_group, record["group"])

func _any_walking(record: Dictionary, units: Array[Unit]) -> bool:
	for unit in units:
		if _is_walking(record, unit):
			return true
	return false

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
func reform_group(units: Array[Unit], target_pos: Vector3, formation_type: Formation.Type, attack_move: bool, forward_override: Vector3 = Vector3.ZERO, front_width: float = -1.0) -> void:
	_issue_slots(units, formation_positions(units, target_pos, formation_type, forward_override, front_width), attack_move)

## `slots` aligned to `units`; `units` itself becomes their cohesion group.
func _issue_slots(units: Array[Unit], slots: Array[Vector3], attack_move: bool) -> void:
	var speed := slowest_move_speed(units)
	for i in units.size():
		if attack_move:
			units[i].command_attack_move(slots[i], speed, units)
		else:
			units[i].command_move(slots[i], speed, units)

## The group's average heading, taken from the direction each unit is actually
## facing (units rotate toward their movement direction, so after a move or a
## fight this is where they were last heading/looking). Averaged as vectors
## rather than angles so opposing headings cancel instead of averaging into a
## meaningless midpoint — a group facing every which way after a brawl falls
## back to the default instead of inheriting one member's spin.
func group_facing(units: Array[Unit]) -> Vector3:
	var held := held_facing(units)
	if held != Vector3.ZERO:
		return held
	var facing := Vector3.ZERO
	for unit in units:
		facing += Vector3(sin(unit.rotation.y), 0.0, cos(unit.rotation.y))
	facing.y = 0.0
	return facing.normalized() if facing.length_squared() > 0.0001 else REFORM_DEFAULT_FORWARD

## ---------------------------------------------------------------------------
## Formation attack
##
## An attack order given to a ranged group, rather than each man being sent at
## the target on his own (which left the block as a ring round it): the block
## marches as a formation to where its front rank is just inside range, facing
## the target, and every member then fights from its slot (see
## Unit.in_formation_fight) — only what's within its own reach, the ordered
## target first, never chasing.
## ---------------------------------------------------------------------------

## How far inside the group's shortest range the front rank stops, so a target
## shuffling back a little doesn't step straight out of reach.
const ENGAGE_RANGE_FRACTION: float = 0.9

## Whether `units` attacking `target` fights as a formation: a group of
## fighting units ordered onto an enemy it can attack. A selection with
## non-fighters in it (villagers) still closes in man by man.
func can_formation_attack(units: Array[Unit], target: Node) -> bool:
	if units.size() < 2 or not (target is Node3D) or not is_instance_valid(target):
		return false
	if not (target is Unit or (target is ProductionBuilding and target.can_be_attacked())):
		return false
	for unit in units:
		if not unit.can_fight or not Teams.is_enemy(unit.owner_peer_id, target.owner_peer_id):
			return false
	return true

## Host-side. Issues the formation attack (see can_formation_attack), or, with
## `fight_id`, sends an engagement already under way at a new target. `refill`
## re-solves a fighting block's slots in place after losses: members already
## close to their new slot carry on fighting from it, and only the ones with
## somewhere to go (the rank behind stepping into a hole) walk there.
func formation_attack(units: Array[Unit], target: Node3D, formation_type: Formation.Type, front_width: float = -1.0, fight_id: int = -1, refill: bool = false) -> void:
	if fight_id < 0:
		fight_id = _next_fight_id
		_next_fight_id += 1
		_engagements.append({
			"id": fight_id,
			"units": units.duplicate(),
			"owner": units[0].owner_peer_id,
			"target": target,
			"type": formation_type,
			"front_width": front_width,
			"check_in": ENGAGEMENT_CHECK_INTERVAL,
			"advance_in": 0.0,
			"count": units.size(),
			"refill_in": -1.0,
		})
	var facing := _group_forward(group_centroid(units), target.global_position)
	var melee := _melee_members(units, true)
	var ranged := _melee_members(units, false)
	## A mixed group goes in as one block — melee ranks in front, ranged
	## behind — and the melee ranks charge on from there (see
	## _check_engagement). Once fighting, each part refills on its own: the
	## melee in contact, the ranged at its own range behind.
	if not refill and not melee.is_empty() and not ranged.is_empty():
		_formation_attack_mixed(melee, ranged, target, facing, formation_type, front_width, fight_id)
		return
	if not melee.is_empty():
		_formation_attack_block(melee, target, facing, formation_type, front_width, fight_id, refill, INF)
	if not ranged.is_empty():
		_formation_attack_block(ranged, target, facing, formation_type, front_width, fight_id, refill, INF)

func _melee_members(units: Array[Unit], melee: bool) -> Array[Unit]:
	var result: Array[Unit] = []
	for unit in units:
		if unit._counts_as_melee() == melee:
			result.append(unit)
	return result

## A mixed group's way in: one formation with the melee in its front ranks and
## the ranged behind, halted where the first ranged rank is in range — so the
## melee is in front of the archers, short of the enemy, and marching at the
## slowest member's pace so neither part runs ahead of the other.
func _formation_attack_mixed(melee: Array[Unit], ranged: Array[Unit], target: Node3D, facing: Vector3, formation_type: Formation.Type, front_width: float, fight_id: int) -> void:
	var units: Array[Unit] = []
	units.append_array(melee)
	units.append_array(ranged)
	var target_pos := target.global_position
	var ranged_engage := _engage_distance(ranged, target)
	if _flat_distance(group_centroid(units), target_pos) <= ranged_engage:
		for unit in units:
			unit.command_stop()
			unit.formation_facing = facing
			unit.begin_formation_fight(target, unit.global_position, fight_id)
		return
	var right := Vector3(facing.z, 0.0, -facing.x)
	var shape := Formation.new(units, formation_type, front_width).get_slot_positions(Vector3.ZERO, facing, right)
	## Slots front to back, as (depth behind the front rank, index).
	var order: Array[Vector2] = []
	for i in shape.size():
		order.append(Vector2(-shape[i].dot(facing), i))
	order.sort()
	## The first ranged rank is where range is measured from.
	var ranged_depth: float = order[mini(melee.size(), order.size() - 1)].x
	var front: float = maxf(ranged_engage - ranged_depth, _engage_distance(melee, target))
	var point := target_pos - facing * front
	var map: RID = units[0].nav_agent.get_navigation_map()
	if map.is_valid() and NavigationServer3D.map_get_iteration_id(map) > 0:
		point = NavigationServer3D.map_get_closest_point(map, point)
	var melee_slots: Array[Vector3] = []
	var ranged_slots: Array[Vector3] = []
	for k in order.size():
		var slot: Vector3 = shape[int(order[k].y)] + point
		if k < melee.size():
			melee_slots.append(slot)
		else:
			ranged_slots.append(slot)
	var speed := slowest_move_speed(units)
	for part in [[melee, _assign_slots_to_units(melee, melee_slots, facing, true)],
			[ranged, _assign_slots_to_units(ranged, ranged_slots, facing, true)]]:
		var members: Array[Unit] = part[0]
		var slots: Array[Vector3] = part[1]
		for i in members.size():
			members[i].command_move(slots[i], speed, units)
			members[i].begin_formation_fight(target, slots[i], fight_id)
	var record := register_formation(units, point, formation_type, false, facing, front_width, speed)
	if not record.is_empty():
		record["attack_target"] = target
		record["fight_id"] = fight_id

## One block of a formation attack (see formation_attack): all melee or all
## ranged, facing `facing`.
func _formation_attack_block(units: Array[Unit], target: Node3D, facing: Vector3, formation_type: Formation.Type, front_width: float, fight_id: int, refill: bool, speed_cap: float) -> void:
	var centroid := group_centroid(units)
	var target_pos := target.global_position
	var engage := _engage_distance(units, target)
	## Already close enough: fight from where they stand rather than walk
	## backwards to a line further out.
	if not refill and _flat_distance(centroid, target_pos) <= engage:
		for unit in units:
			unit.command_stop()
			unit.formation_facing = facing
			unit.begin_formation_fight(target, unit.global_position, fight_id)
		return
	var point := target_pos - facing * engage
	var map: RID = units[0].nav_agent.get_navigation_map()
	if map.is_valid() and NavigationServer3D.map_get_iteration_id(map) > 0:
		point = NavigationServer3D.map_get_closest_point(map, point)
	var slots := formation_positions(units, point, formation_type, facing, front_width)
	var speed := slowest_move_speed(units)
	for i in units.size():
		var unit := units[i]
		## Measured from its place, not where it stands: a melee man stepped
		## out to strike is still in the same spot in the line.
		if refill and unit.status_command != Unit.Command.MOVE \
				and _flat_distance(unit.formation_fight_place, slots[i]) <= REFILL_KEEP_DISTANCE:
			unit.formation_fight_place = slots[i]
			unit.formation_attack_target = target
			continue
		unit.command_move(slots[i], speed, units)
		unit.begin_formation_fight(target, slots[i], fight_id)
	var record := register_formation(units, point, formation_type, false, facing, front_width, speed_cap)
	if not record.is_empty():
		record["attack_target"] = target
		record["fight_id"] = fight_id

## Where the front rank stands off from `target`: just inside the group's
## shortest reach.
func _engage_distance(units: Array[Unit], target: Node3D) -> float:
	var reach := INF
	for unit in units:
		reach = minf(reach, unit.attack_range)
	if target is ProductionBuilding:
		reach += target.get_footprint_radius()
	return reach * ENGAGE_RANGE_FRACTION

## ---------------------------------------------------------------------------
## Engagements
##
## A formation attack doesn't end when the block arrives. Each one is watched
## here for as long as any member is still fighting in it (any other order
## takes a unit out): a target that moves out of reach is followed as a block,
## and one that dies is replaced by the nearest enemy near the block — or, with
## nothing near, the block holds and fights whatever comes within reach.
## ---------------------------------------------------------------------------

var _engagements: Array[Dictionary] = []
var _next_fight_id: int = 1
## How often each engagement is looked at.
const ENGAGEMENT_CHECK_INTERVAL: float = 0.25
## Fewest seconds between re-advances on a target that keeps moving off —
## each re-solves and re-issues the whole block's slots.
const ENGAGEMENT_ADVANCE_INTERVAL: float = 1.5
## A fighting block that loses members waits this long — deaths come in
## bursts — then re-solves its slots so the rank behind steps into the holes.
const ENGAGEMENT_REFILL_DELAY: float = 1.0
## On a refill, a member already this close to its new slot carries on
## fighting rather than walking the last bit (see formation_attack).
const REFILL_KEEP_DISTANCE: float = 1.2
## How far beyond the block's edge a new target is looked for once the last
## one is dead — from the edge rather than the centre, so a deep block of
## hundreds looks as far past its front rank as a small one does.
const ENGAGEMENT_RETARGET_REACH: float = 10.0

func _update_engagements(delta: float) -> void:
	for i in range(_engagements.size() - 1, -1, -1):
		var engagement: Dictionary = _engagements[i]
		var members := _engagement_members(engagement)
		if members.is_empty():
			_engagements.remove_at(i)
			continue
		engagement["advance_in"] = float(engagement["advance_in"]) - delta
		if members.size() < int(engagement["count"]):
			engagement["count"] = members.size()
			engagement["refill_in"] = ENGAGEMENT_REFILL_DELAY
		elif float(engagement["refill_in"]) >= 0.0:
			engagement["refill_in"] = maxf(float(engagement["refill_in"]) - delta, 0.0)
		engagement["check_in"] = float(engagement["check_in"]) - delta
		if engagement["check_in"] > 0.0:
			continue
		engagement["check_in"] = ENGAGEMENT_CHECK_INTERVAL
		## Still walking into place: let the block get there first — though
		## whoever's already standing idle beside a fight goes on into it.
		var walking := false
		for unit in members:
			if unit.status_command == Unit.Command.MOVE:
				walking = true
				break
		if walking:
			_bring_up_wings(engagement, members)
			continue
		_check_engagement(engagement, members)

## Members still fighting in `engagement`: alive, and not given another order.
func _engagement_members(engagement: Dictionary) -> Array[Unit]:
	var members: Array[Unit] = []
	for unit in engagement["units"]:
		if is_instance_valid(unit) and unit.status_activity != Unit.Activity.DEAD \
				and unit.in_formation_fight and unit.formation_fight_id == engagement["id"]:
			members.append(unit)
	return members

func _check_engagement(engagement: Dictionary, members: Array[Unit]) -> void:
	var target = engagement["target"]
	var alive: bool = target != null and is_instance_valid(target) and not _is_dead(target)
	## Lost men a moment ago: close the holes before anything else.
	if alive and members.size() >= 2 and float(engagement["refill_in"]) == 0.0:
		engagement["refill_in"] = -1.0
		## Wings that moved up and are still fighting stay out of it rather
		## than being pulled back into line (see _bring_up_wings).
		var wings: Array = engagement.get("wings", [])
		var line: Array[Unit] = []
		for unit in members:
			if not (wings.has(unit) and unit.attack_target != null):
				line.append(unit)
		engagement["wings"] = wings.filter(func(unit): return not line.has(unit))
		if line.size() >= 2:
			formation_attack(line, target, engagement["type"], engagement["front_width"], engagement["id"], true)
			return
	if alive:
		## A mixed block in place with its archers shooting and its melee
		## ranks still short of the enemy: the melee charges on into contact.
		var melee := _melee_members(members, true)
		if not melee.is_empty() and melee.size() < members.size() and engagement["advance_in"] <= 0.0:
			var melee_engaged := false
			for unit in melee:
				if unit.attack_target != null or unit._formation_can_reach(target):
					melee_engaged = true
					break
			if not melee_engaged:
				engagement["advance_in"] = ENGAGEMENT_ADVANCE_INTERVAL
				var charge_facing := _group_forward(group_centroid(melee), target.global_position)
				_formation_attack_block(melee, target, charge_facing, engagement["type"], engagement["front_width"], engagement["id"], false, INF)
				return
		## Someone can still reach it: the block is doing its job.
		for unit in members:
			if unit._formation_can_reach(target):
				_bring_up_wings(engagement, members)
				return
		## Moved off out of everyone's reach — follow it as a block.
		if engagement["advance_in"] > 0.0:
			_bring_up_wings(engagement, members)
			return
		_advance_engagement(engagement, members, target)
		return
	var next := _nearest_enemy_near(members, int(engagement["owner"]))
	## Nothing left near a group that met this fight on an attack-move: carry
	## on to where it was going.
	if next == null and engagement.has("resume"):
		_resume_attack_move(members, engagement["resume"])
		return
	if next == null:
		if target != null:
			engagement["target"] = null
			for unit in members:
				unit.hold_formation_fight()
		return
	_advance_engagement(engagement, members, next)

## Host-side. `unit`, on a group attack-move, has met `enemy` (seen it, been
## hit by it, or been called in by a neighbour it hit): the whole group still on
## that attack-move stops and fights it as a formation, and resumes the march
## once the area's clear (see _check_engagement). False if there's no group to
## bring round, so the unit fights it on its own as before.
func formation_contact(unit: Unit, enemy: Node3D) -> bool:
	if not multiplayer.is_server():
		return false
	var order: Dictionary = unit.attack_move_order
	var members := _attack_move_members(order)
	if not members.has(unit):
		return false
	return _order_contact(members, order, enemy)

## Whether the block behind `order` came round onto `enemy`. Takes the order
## rather than one of its members, for a caller that already has the whole
## group in hand: every member carries the same order and would build the same
## member list, so asking once per member repeated the same O(group) scan as
## many times as the group is strong — an n-squared that only shows itself at
## army size (see Main._engage_at_attack_move_destination).
func order_contact(order: Dictionary, enemy: Node3D) -> bool:
	if not multiplayer.is_server():
		return false
	return _order_contact(_attack_move_members(order), order, enemy)

## The members of `order` still free to be pulled into a block fight: alive,
## able to fight, still carrying this exact order, and not already in one.
func _attack_move_members(order: Dictionary) -> Array[Unit]:
	var members: Array[Unit] = []
	for other in order.get("units", []):
		if is_instance_valid(other) and other.status_activity != Unit.Activity.DEAD and other.can_fight \
				and is_same(other.attack_move_order, order) and not other.in_formation_fight \
				and (other.status_command == Unit.Command.ATTACK_MOVE or other.status_command == Unit.Command.NONE):
			members.append(other)
	return members

func _order_contact(members: Array[Unit], order: Dictionary, enemy: Node3D) -> bool:
	if members.size() < 2 or not can_formation_attack(members, enemy):
		return false
	formation_attack(members, enemy, order["type"], order["front_width"])
	_engagements[_engagements.size() - 1]["resume"] = order
	return true

## An idle block (see Unit.in_idle_block) met from the front goes in as one:
## every member still standing idle in it joins a formation attack on `enemy`,
## in the shape it was last dragged into, if any.
func idle_block_contact(unit: Unit, enemy: Node3D) -> bool:
	if not multiplayer.is_server():
		return false
	var group: Array[Unit] = unit.arrived_group
	var members: Array[Unit] = []
	for other in group:
		if is_instance_valid(other) and other.status_activity != Unit.Activity.DEAD \
				and is_same(other.arrived_group, group) and other.in_idle_block():
			members.append(other)
	if members.size() < 2 or not members.has(unit) or not can_formation_attack(members, enemy):
		return false
	var memory: Dictionary = unit.dragged_formation
	formation_attack(members, enemy, memory.get("type", Formation.DEFAULT_TYPE), memory.get("width", -1.0))
	return true

## Puts `members` back on the group attack-move `order` after a fight.
func _resume_attack_move(members: Array[Unit], order: Dictionary) -> void:
	var target: Vector3 = order["target"]
	var slots := formation_positions(members, target, order["type"], order["forward"], order["front_width"])
	var speed := slowest_move_speed(members)
	for i in members.size():
		members[i].command_attack_move(slots[i], speed, members)
	register_formation(members, target, order["type"], true, order["forward"], order["front_width"])

## Width of the lanes _bring_up_wings sorts a block into: about one file.
const WING_LANE_WIDTH: float = Formation.SPACING
## A melee member with a comrade at least this far ahead of it in its lane (or
## the next one over) is a rear rank, and holds for its turn to step up.
const WING_COVER_DEPTH: float = 0.5

## While the block is fighting, members with nothing in reach from their place
## — the ends of a line that overlaps the enemy's, most often — move up to
## the nearest enemy near them and fight from there instead of standing idle.
## A melee rear rank, with a comrade in front of it, only goes if that enemy
## has nobody on it yet; otherwise it holds to step into the gaps as before.
func _bring_up_wings(engagement: Dictionary, members: Array[Unit]) -> void:
	var fighting := false
	for unit in members:
		if unit.attack_target != null:
			fighting = true
			break
	if not fighting:
		return
	var facing := group_facing(members)
	var right := Vector3(facing.z, 0.0, -facing.x)
	## Furthest-forward place in each lane.
	var lane_front := {}
	for unit in members:
		var lane := floori(unit.formation_fight_place.dot(right) / WING_LANE_WIDTH)
		var depth: float = unit.formation_fight_place.dot(facing)
		lane_front[lane] = maxf(float(lane_front.get(lane, -INF)), depth)
	for unit in members:
		if unit.status_command != Unit.Command.NONE or unit.attack_target != null:
			continue
		if unit._nearest_in_place_reach() != null:
			continue
		## A ranged unit only picks what it can see (see Unit._nearest_in_place_reach).
		var search: float = maxf(unit.aggro_range, unit.attack_range + ENGAGEMENT_RETARGET_REACH) \
				if unit._counts_as_melee() else unit.aggro_range
		var enemy := unit._find_nearest_enemy_in_range(search)
		if enemy == null:
			continue
		if unit._counts_as_melee() and enemy.melee_attackers > 0:
			var lane := floori(unit.formation_fight_place.dot(right) / WING_LANE_WIDTH)
			var depth: float = unit.formation_fight_place.dot(facing) + WING_COVER_DEPTH
			if float(lane_front.get(lane - 1, -INF)) > depth or float(lane_front.get(lane, -INF)) > depth \
					or float(lane_front.get(lane + 1, -INF)) > depth:
				continue
		var away := unit.global_position - enemy.global_position
		away.y = 0.0
		if away.length_squared() < 0.0001:
			continue
		var alone: Array[Unit] = [unit]
		var place := enemy.global_position + away.normalized() * _engage_distance(alone, enemy)
		var map: RID = unit.nav_agent.get_navigation_map()
		if map.is_valid() and NavigationServer3D.map_get_iteration_id(map) > 0:
			place = NavigationServer3D.map_get_closest_point(map, place)
		var fight_id := unit.formation_fight_id
		unit.command_move(place)
		unit.begin_formation_fight(enemy, place, fight_id)
		var wings: Array = engagement.get("wings", [])
		if not wings.has(unit):
			wings.append(unit)
		engagement["wings"] = wings

func _advance_engagement(engagement: Dictionary, members: Array[Unit], target: Node3D) -> void:
	engagement["target"] = target
	engagement["advance_in"] = ENGAGEMENT_ADVANCE_INTERVAL
	engagement["wings"] = []
	formation_attack(members, target, engagement["type"], engagement["front_width"], engagement["id"])

func _is_dead(target: Node) -> bool:
	if target is Unit:
		return target.status_activity == Unit.Activity.DEAD
	if target is ProductionBuilding:
		return target.is_destroyed or not target.can_be_attacked()
	return false

## Nearest enemy of `owner` within ENGAGEMENT_RETARGET_REACH of the block's
## edge (nearest to its centre): a unit if there is one, otherwise an
## attackable building.
func _nearest_enemy_near(members: Array[Unit], owner: int) -> Node3D:
	var centre := group_centroid(members)
	var block_radius := 0.0
	for unit in members:
		block_radius = maxf(block_radius, _flat_distance(centre, unit.global_position))
	var search := block_radius + ENGAGEMENT_RETARGET_REACH
	var best: Node3D = null
	var best_distance := search
	for unit in UnitGrid.enemies_near(get_tree(), centre, search, owner):
		if not CombatUtils.is_worth_attacking(unit):
			continue
		var distance := _flat_distance(centre, unit.global_position)
		if distance <= best_distance:
			best = unit
			best_distance = distance
	if best != null:
		return best
	for node in get_tree().get_nodes_in_group(&"buildings"):
		var building := node as ProductionBuilding
		if building == null or building.is_destroyed or not building.can_be_attacked() \
				or not Teams.is_enemy(owner, building.owner_peer_id):
			continue
		var distance := _flat_distance(centre, building.global_position) - building.get_footprint_radius()
		if distance <= best_distance:
			best = building
			best_distance = distance
	return best

## ---------------------------------------------------------------------------
## Marching
##
## Without this every unit paths to its own slot independently, so the shape
## only exists at the two ends of a move and smears out in between. A marching
## record instead walks one virtual anchor (the front-centre of the formation)
## along a single navmesh route, and every member steers at its own offset from
## that anchor. The block holds the order's facing the whole way rather than
## wheeling with every bend in the path: each steer re-expresses a member's
## fixed offset as (across, behind) the current direction of travel, and places
## it `behind` meters back ALONG the route and `across` it. On a straight stretch
## that is an exact rigid slide; at a bend the part of the block still short of
## it follows the route round instead of cutting the corner.
## Where the navmesh narrows, a rank first slides sideways into whatever room
## there is and only then squeezes its flanks inward, and squeezed units drop
## back behind their rank — so a gate or a gap between buildings turns the
## block into a column and it opens back out on the far side. The anchor paces
## itself to how far behind the members are, so a scattered group forms up
## before it marches off and a jam at a gap holds the front back instead of
## the front running away from it. Once the anchor reaches the destination the
## members are released onto their real slots (Unit.end_march).
## ---------------------------------------------------------------------------

## Moves shorter than this just walk to their slots — marching needs some route
## to march along, and a short hop keeps its shape well enough on its own.
const MARCH_MIN_DISTANCE: float = 6.0
## Anchor pace as a fraction of the slowest member's speed, leaving the members
## a little slack to catch up to their offsets while moving.
const MARCH_SPEED_FACTOR: float = 0.9
## Median member lag (meters from their steering point) the anchor ignores,
## and the lag at which it slows to MARCH_MIN_SCALE. The median, not the
## average: in a big block some members are always off round a tree clump or a
## bank, and pacing on them held the whole army to half speed — they hurry to
## catch up instead (see Unit.MARCH_CATCH_UP_SPEED).
const MARCH_LAG_FREE: float = 1.0
const MARCH_LAG_STOP: float = 4.0
## Never fully halted, so one unit that can't keep up can't freeze the group.
const MARCH_MIN_SCALE: float = 0.15
## How often each member's steering point is re-solved — a slice of the block
## per frame, so the work is spread evenly rather than landing on one frame
## (see _steer_march). The anchor itself moves
## every frame and members extrapolate with its velocity in between.
const MARCH_UPDATE_INTERVAL: float = 0.1
## Route heading is read across this many meters either side of a point so a
## sharp path corner re-lays the block smoothly instead of snapping it.
const MARCH_HEADING_SPAN: float = 1.5
## Extra heading span per meter of the block's reach (see _new_march).
const MARCH_HEADING_SPAN_PER_REACH: float = 0.3
## Spacing of the navmesh samples used to measure room across the route.
const MARCH_PROBE_STEP: float = 0.5
## Extra room probed past a rank's own width, for sliding it sideways.
const MARCH_PROBE_EXTRA: float = 3.0
## Length of route one cached room measurement covers (see _route_room).
const MARCH_ROOM_BIN: float = 1.0## A sample whose nearest navmesh point is further than this is off the mesh.
const MARCH_BLOCKED_DISTANCE: float = 0.3
## How far behind its rank a squeezed unit falls, per meter squeezed inward.
const MARCH_SQUEEZE_TRAIL: float = 0.8

## One march per speed class: an anchor can only walk at one pace, and holding
## every member to the slowest one's would break the rule that units travel at
## their own full speed. So a mixed selection splits into a block per speed,
## each marching its own members' slots of the order's shape along its own
## route and arriving when it arrives. Only the marching splits — closing
## ranks still re-solves the whole selection as one formation.
func _start_march(record: Dictionary, members: Array[Unit]) -> void:
	record["marches"] = []
	var target: Vector3 = record["target"]
	var map: RID = members[0].nav_agent.get_navigation_map()
	if not map.is_valid():
		return
	var forward: Vector3 = record["forward"]
	if forward == Vector3.ZERO:
		forward = _group_forward(group_centroid(members), target)
	for speed_class in _speed_classes(members):
		var march := _new_march(record, speed_class, forward, map)
		if not march.is_empty():
			record["marches"].append(march)
	record["march"] = not (record["marches"] as Array).is_empty()

## `units` split into groups sharing one move_speed.
func _speed_classes(units: Array[Unit]) -> Array[Array]:
	var by_speed: Dictionary = {}
	for unit in units:
		var key: float = snappedf(unit.move_speed, 0.01)
		if not by_speed.has(key):
			var bucket: Array[Unit] = []
			by_speed[key] = bucket
		by_speed[key].append(unit)
	var classes: Array[Array] = []
	for bucket in by_speed.values():
		classes.append(bucket)
	return classes

## The march state for one speed class of `record`, or empty if that class is
## better off walking straight to its slots (too short a hop, or no route).
func _new_march(record: Dictionary, units: Array[Unit], forward: Vector3, map: RID) -> Dictionary:
	var target: Vector3 = record["target"]
	var centroid := group_centroid(units)
	if _flat_distance(centroid, target) < MARCH_MIN_DISTANCE:
		return {}
	var march := {
		"target": target,
		"march_forward": forward,
		"map": map,
		"slots": record["slots"],
	}
	_set_march_offsets(march, units)

	## The anchor starts where the front-centre of a formation centred on the
	## class's current position would be.
	var offsets: Dictionary = march["offsets"]
	var average_back := 0.0
	for unit in offsets:
		average_back += (offsets[unit] as Vector2).y
	average_back /= maxi(offsets.size(), 1)
	var start := NavigationServer3D.map_get_closest_point(map, centroid + forward * average_back)
	var route := _straighten_route(NavigationServer3D.map_get_path(map, start, target, true))
	if PerfStats.enabled:
		PerfStats.count_path()
	if route.size() < 2:
		return {}
	var cumulative: Array[float] = [0.0]
	for i in route.size() - 1:
		cumulative.append(cumulative[i] + _flat_distance(route[i], route[i + 1]))
	var length: float = cumulative[cumulative.size() - 1]
	if length < MARCH_MIN_DISTANCE:
		return {}

	march["route"] = route
	march["cumulative"] = cumulative
	march["length"] = length
	march["arc"] = 0.0
	## A wide block reads its heading over more route, so the small zigzags of
	## a navmesh path don't swing its flanks back and forth.
	march["heading_span"] = maxf(MARCH_HEADING_SPAN, float(march["probe_reach"]) * MARCH_HEADING_SPAN_PER_REACH)
	_set_route_offsets(march)
	march["speed"] = minf(units[0].move_speed, float(record["speed_cap"])) * MARCH_SPEED_FACTOR
	march["march_scale"] = MARCH_MIN_SCALE
	_steer_march(march, units, 0.0)
	return march

## `route` with every stretch that can be walked in a straight line replaced by
## that line. Over rolling terrain the navmesh path wanders meters either side
## of a straight line across open ground (the funnel works on the 3D polygons),
## and the anchor following it snaked the whole block from side to side.
## Splits in half until each piece either walks straight or is a single leg of
## the original path, so open ground costs one check.
func _straighten_route(route: PackedVector3Array) -> PackedVector3Array:
	if route.size() <= 2 or NavWalkability.current == null:
		return route
	var result := PackedVector3Array([route[0]])
	result.append_array(_straighten_span(route, 0, route.size() - 1))
	return result

## The straightened points of route[from..to] that follow route[from].
func _straighten_span(route: PackedVector3Array, from: int, to: int) -> PackedVector3Array:
	if to - from <= 1 or _segment_walkable(route[from], route[to]):
		return PackedVector3Array([route[to]])
	var middle: int = floori((from + to) * 0.5)
	var points := _straighten_span(route, from, middle)
	points.append_array(_straighten_span(route, middle, to))
	return points

func _segment_walkable(from: Vector3, to: Vector3) -> bool:
	var walkability := NavWalkability.current
	var steps: int = maxi(1, ceili(_flat_distance(from, to) / MARCH_PROBE_STEP))
	var poly := -1
	for step in range(1, steps):
		poly = walkability.polygon_at(from.lerp(to, float(step) / steps), poly)
		if poly < 0:
			return false
	return true

## The members of `members` that belong to `march` (its speed class).
func _march_members(march: Dictionary, members: Array[Unit]) -> Array[Unit]:
	var offsets: Dictionary = march["offsets"]
	var result: Array[Unit] = []
	for unit in members:
		if offsets.has(unit):
			result.append(unit)
	return result

## Each member's slot as (lateral, back) against the order's final facing —
## lateral along `right`, back measured behind the front rank.
func _set_march_offsets(march: Dictionary, members: Array[Unit]) -> void:
	var target: Vector3 = march["target"]
	var forward: Vector3 = march["march_forward"]
	var right := Vector3(forward.z, 0.0, -forward.x)
	var slots: Dictionary = march["slots"]
	var offsets: Dictionary = {}
	var widest := 0.0
	for unit in members:
		if not slots.has(unit):
			continue
		var offset: Vector3 = slots[unit] - target
		var lateral: float = offset.dot(right)
		var back: float = maxf(-offset.dot(forward), 0.0)
		offsets[unit] = Vector2(lateral, back)
		## Any member can end up furthest across the route once the travel
		## direction stops matching the facing, so probe as far as the
		## furthest slot from the anchor in any direction.
		widest = maxf(widest, Vector2(lateral, back).length())
	march["offsets"] = offsets
	march["probe_reach"] = widest + MARCH_PROBE_EXTRA

## A block of chargers marching on an attack breaks into a charge over the last
## stretch (see Unit.CHARGE_SPRINT_DISTANCE): the anchor speeds up with them, or
## it would hold them to marching pace. Only when every walker can charge and
## has its charge ready, so a mixed or spent block keeps its step.
func _charge_factor(record: Dictionary, walking: Array[Unit], remaining: float) -> float:
	if walking.is_empty() or remaining > Unit.CHARGE_SPRINT_DISTANCE:
		return 1.0
	if record["attack_target"] == null or not is_instance_valid(record["attack_target"]):
		return 1.0
	for unit in walking:
		if not unit.is_charge_ready():
			return 1.0
	return Unit.CHARGE_SPEED_MULTIPLIER

func _advance_march(record: Dictionary, members: Array[Unit], delta: float) -> void:
	if not record["march"]:
		return
	var marches: Array = record["marches"]
	for i in range(marches.size() - 1, -1, -1):
		var march: Dictionary = marches[i]
		var walking: Array[Unit] = []
		for unit in _march_members(march, members):
			if _is_walking(record, unit):
				walking.append(unit)
		var length: float = march["length"]
		march["charge_scale"] = _charge_factor(record, walking, length - float(march["arc"]))
		var speed: float = float(march["speed"]) * float(march["charge_scale"])
		var arc: float = minf(float(march["arc"]) + speed * float(march["march_scale"]) * delta, length)
		march["arc"] = arc
		if arc >= length:
			for unit in walking:
				unit.end_march()
			marches.remove_at(i)
			continue
		_steer_march(march, walking, delta)
	record["march"] = not marches.is_empty()

## Each member's place against the route, as (across, behind the anchor along
## it), fixed from the direction of travel where the block is now — so the
## block keeps the arrangement it's standing in and bends round the route's
## corners like a column, rather than swinging the whole block round to keep
## its world orientation at every bend (which sent the flanks tens of meters
## to their new points, and held the anchor back until they got there). It
## turns into the order's facing at the end, when members walk onto their
## real slots (Unit.end_march).
func _set_route_offsets(march: Dictionary) -> void:
	var forward: Vector3 = march["march_forward"]
	var facing_right := Vector3(forward.z, 0.0, -forward.x)
	var travel: Vector3 = _march_frame(march, float(march["arc"]))["forward"]
	var travel_right := Vector3(travel.z, 0.0, -travel.x)
	var offsets: Dictionary = march["offsets"]
	var route_offsets: Dictionary = {}
	for unit in offsets:
		var slot: Vector2 = offsets[unit]
		var world := facing_right * slot.x - forward * slot.y
		route_offsets[unit] = Vector2(world.dot(travel_right), -world.dot(travel))
	march["route_offsets"] = route_offsets
	## A "rank" is everyone at the same distance behind the anchor ALONG the
	## route — the facing rank when the block walks straight ahead, a column's
	## cross-section when it walks sideways — with its reach either side, so
	## the whole thing can slide. Fixed along with the offsets.
	var ranks: Dictionary = {}
	for unit in route_offsets:
		var offset: Vector2 = route_offsets[unit]
		var key := _rank_key(offset)
		var reach: Vector2 = ranks.get(key, Vector2.ZERO)
		ranks[key] = Vector2(maxf(reach.x, -offset.x), maxf(reach.y, offset.x))
	march["ranks"] = ranks
	march["lags"] = {}
	march["steer_cursor"] = 0

static func _rank_key(offset: Vector2) -> int:
	return roundi(offset.y * 10.0)

## Re-solves members' steering points off the anchor's current position: the
## next slice of `units` this frame, sized so everyone is refreshed every
## MARCH_UPDATE_INTERVAL (all of them when `delta` is 0, as on the first call).
## Doing the whole block on one frame was a ~50 ms hitch ten times a second
## for a few hundred units. The anchor is paced off the median lag once per
## full pass.
func _steer_march(march: Dictionary, units: Array[Unit], delta: float) -> void:
	var count := units.size()
	if count == 0:
		return
	var slice: int = count if delta <= 0.0 else mini(count, ceili(count * delta / MARCH_UPDATE_INTERVAL))
	var start: int = int(march["steer_cursor"]) % count
	var arc: float = march["arc"]
	var probe_reach: float = march["probe_reach"]
	var anchor_speed: float = float(march["speed"]) * float(march["march_scale"]) * float(march.get("charge_scale", 1.0))
	var route_offsets: Dictionary = march["route_offsets"]
	var ranks: Dictionary = march["ranks"]
	var lags: Dictionary = march["lags"]

	## Per rank, shared by everyone in it this call: the route frame at the
	## rank's arc, and [left room, right room, sideways shift].
	var rank_frames: Dictionary = {}
	var rank_room: Dictionary = {}
	for i in slice:
		var unit: Unit = units[(start + i) % count]
		if not route_offsets.has(unit):
			continue
		var offset: Vector2 = route_offsets[unit]
		var rank := _rank_key(offset)
		if not rank_frames.has(rank):
			rank_frames[rank] = _march_frame(march, arc - offset.y)
			var reach: Vector2 = ranks.get(rank, Vector2.ZERO)
			var measured := _route_room(march, arc - offset.y, probe_reach)
			var left_room: float = measured.x
			var right_room: float = measured.y
			## Slide the whole rank toward the open side before squeezing anyone.
			var shift := 0.0
			if right_room < reach.y:
				shift = -minf(reach.y - right_room, maxf(left_room - reach.x, 0.0))
			elif left_room < reach.x:
				shift = minf(reach.x - left_room, maxf(right_room - reach.y, 0.0))
			rank_room[rank] = Vector3(left_room, right_room, shift)
		var frame: Dictionary = rank_frames[rank]
		var room: Vector3 = rank_room[rank]
		var base: Vector3 = frame["position"]
		var heading: Vector3 = frame["forward"]
		var right := Vector3(heading.z, 0.0, -heading.x)

		var wanted: float = offset.x + room.z
		var lateral: float = clampf(wanted, -room.x, room.y)
		var trail: float = absf(wanted - lateral) * MARCH_SQUEEZE_TRAIL
		## Only a squeezed unit can be steered at somewhere off the navmesh; one
		## within its rank's measured room is already on walkable ground.
		var point := base + right * lateral
		if trail > 0.05:
			var trailed := _march_frame(march, arc - offset.y - trail)
			base = trailed["position"]
			heading = trailed["forward"]
			right = Vector3(heading.z, 0.0, -heading.x)
			point = _walkable_toward(base + right * lateral, base, march["map"])
		unit.set_march_target(point, heading * anchor_speed)
		lags[unit] = _flat_distance(unit.global_position, point)

	march["steer_cursor"] = start + slice
	if start + slice < count:
		return
	var current := PackedFloat32Array()
	for unit in units:
		if lags.has(unit):
			current.append(lags[unit])
	if not current.is_empty():
		current.sort()
		var lag: float = current[current.size() / 2]
		march["march_scale"] = clampf(1.0 - (lag - MARCH_LAG_FREE) / (MARCH_LAG_STOP - MARCH_LAG_FREE), MARCH_MIN_SCALE, 1.0)

## The walkable point nearest `point` on the way back toward `toward` (a point
## on the route, so walkable itself), stepping along the navmesh index — a
## squeezed unit's point pulled back inside the corridor. Only without the index
## does it fall back on the NavigationServer, whose closest-point query checks
## every polygon on the map.
func _walkable_toward(point: Vector3, toward: Vector3, map: RID) -> Vector3:
	var walkability := NavWalkability.current
	if walkability == null:
		return NavigationServer3D.map_get_closest_point(map, point)
	var distance := _flat_distance(point, toward)
	var steps: int = ceili(distance / MARCH_PROBE_STEP)
	for step in steps:
		var candidate := point.lerp(toward, float(step) / steps)
		if walkability.is_walkable(candidate):
			return candidate
	return toward

## Position `arc` meters along the march route and the direction of travel
## there. Arcs off either end (members still behind the route's start, or ahead
## of the anchor when the block walks sideways) extend straight out from it.
func _march_frame(march: Dictionary, arc: float) -> Dictionary:
	var route: PackedVector3Array = march["route"]
	var cumulative: Array[float] = march["cumulative"]
	var position := _march_position(route, cumulative, arc)
	var span: float = march.get("heading_span", MARCH_HEADING_SPAN)
	var heading := _march_position(route, cumulative, arc + span) \
			- _march_position(route, cumulative, arc - span)
	heading.y = 0.0
	heading = heading.normalized() if heading.length_squared() > 0.0001 else march["march_forward"]
	return {"position": position, "forward": heading}

func _march_position(route: PackedVector3Array, cumulative: Array[float], arc: float) -> Vector3:
	var length: float = cumulative[cumulative.size() - 1]
	if arc > length:
		var end_forward: Vector3 = _route_point_at(route, cumulative, length)["forward"]
		return route[route.size() - 1] + end_forward * (arc - length)
	if arc >= 0.0:
		return _route_point_at(route, cumulative, arc)["position"]
	var start_forward: Vector3 = _route_point_at(route, cumulative, 0.0)["forward"]
	return route[0] + start_forward * arc

## Room either side of the route (left, right) at `arc`, measured once per
## MARCH_ROOM_BIN of route and cached on the march. Every rank walks the same
## route, so trailing ranks reuse what the front rank already measured, and a
## re-steer only probes the ground the anchor has newly reached — probing
## per rank per re-steer was hundreds of navmesh queries a second.
func _route_room(march: Dictionary, arc: float, reach: float) -> Vector2:
	if not march.has("room_cache"):
		march["room_cache"] = {}
	var cache: Dictionary = march["room_cache"]
	var bin := floori(arc / MARCH_ROOM_BIN)
	if cache.has(bin):
		return cache[bin]
	var frame := _march_frame(march, (bin + 0.5) * MARCH_ROOM_BIN)
	var base: Vector3 = frame["position"]
	var heading: Vector3 = frame["forward"]
	var right := Vector3(heading.z, 0.0, -heading.x)
	var map: RID = march["map"]
	var room := Vector2(_probe_room(map, base, -right, reach), _probe_room(map, base, right, reach))
	cache[bin] = room
	return room

## Walkable distance from `base` along `direction`, up to `reach`, sampled
## against the navmesh (which buildings are already carved out of).
## Uses NavWalkability's polygon index when it's built: a closest-point query
## scans every polygon on the map, and this runs many of them per rank.
func _probe_room(map: RID, base: Vector3, direction: Vector3, reach: float) -> float:
	var walkability := NavWalkability.current
	var room := 0.0
	var distance := MARCH_PROBE_STEP
	while room < reach:
		var sample := base + direction * minf(distance, reach)
		if walkability != null:
			if not walkability.is_walkable(sample):
				return room
		elif _flat_distance(NavigationServer3D.map_get_closest_point(map, sample), sample) > MARCH_BLOCKED_DISTANCE:
			return room
		room = minf(distance, reach)
		distance += MARCH_PROBE_STEP
	return reach
