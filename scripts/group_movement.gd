class_name GroupMovement
extends Node
## What is left of group movement planning now that the native sim marches
## every block (see ArmyBridge): the shared geometry the order code, the drag
## preview and the bridge still ask for — a group's centre and facing, where a
## dragged formation faces and lays out, and whether a group can take on an
## enemy as a block.

## The match's instance.
static var current: GroupMovement = null

func _enter_tree() -> void:
	current = self

func _exit_tree() -> void:
	if current == self:
		current = null

## How far behind the rear rank an officer rides.
const OFFICER_STANDOFF: float = 2.4
## Which way a group faces when nothing gives it a direction.
const DEFAULT_FORWARD: Vector3 = Vector3.FORWARD
## How far inside the group's shortest range the front rank stops, so a target
## shuffling back a little doesn't step straight out of reach.
const ENGAGE_RANGE_FRACTION: float = 0.9

## Where an officer stands: behind the rearmost rank, on the block's centre
## line, spread sideways if a body somehow has more than one.
func officer_ground(front_centre: Vector3, forward: Vector3, slots: Array[Vector3], index: int, count: int) -> Vector3:
	var right := Vector3(forward.z, 0.0, -forward.x)
	var deepest := 0.0
	for slot in slots:
		deepest = maxf(deepest, (front_centre - slot).dot(forward))
	var across: float = (index - (count - 1) * 0.5) * Formation.SPACING
	return front_centre - forward * (deepest + OFFICER_STANDOFF) + right * across

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

## The facing a dragged formation takes: from the right-click point toward the
## cursor, so the block stays where the player clicked and the drag only turns
## it. Client-side (it drives the preview) and sent with the order, so the host
## builds exactly the shape the player saw instead of re-deriving it from its
## own unit positions.
func drag_facing(units: Array[Unit], line_start: Vector3, line_end: Vector3) -> Vector3:
	var along := line_end - line_start
	along.y = 0.0
	if along.length_squared() < 0.0001:
		return _group_forward(group_centroid(units), line_start)
	return along.normalized()

## Slot layout for a dragged formation, in shape order rather than assigned to
## units — only for drawing the preview.
func drag_preview_slots(units: Array[Unit], line_start: Vector3, line_end: Vector3, facing: Vector3, formation_type: Formation.Type = Formation.DEFAULT_TYPE) -> Array[Vector3]:
	var midpoint := line_start
	var right := Vector3(facing.z, 0.0, -facing.x)
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
	## The drag only aims the block: its width comes from the shape.
	var formation := Formation.new(men, formation_type, -1.0)
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

## group_centroid for an untyped array, callable without an instance.
static func group_centroid_of(units: Array) -> Vector3:
	var sum := Vector3.ZERO
	for unit in units:
		sum += (unit as Unit).global_position
	return sum / maxi(units.size(), 1)

func group_centroid(units: Array[Unit]) -> Vector3:
	return group_centroid_of(units)

## The direction from `centroid` to `target_pos`, flattened to XZ; arbitrary
## (but still a direction) when the two are on top of each other.
func _group_forward(centroid: Vector3, target_pos: Vector3) -> Vector3:
	var to_target := target_pos - centroid
	to_target.y = 0.0
	return to_target.normalized() if to_target.length_squared() > 0.0001 else DEFAULT_FORWARD

## The group's front: the one its members hold together, else the average of
## the ways they are facing. Averaged as vectors rather than angles so opposing
## headings cancel instead of averaging into a meaningless midpoint — a group
## facing every which way after a brawl falls back to the default instead of
## inheriting one member's spin.
func group_facing(units: Array[Unit]) -> Vector3:
	var held := held_facing(units)
	if held != Vector3.ZERO:
		return held
	var facing := Vector3.ZERO
	for unit in units:
		facing += Vector3(sin(unit.rotation.y), 0.0, cos(unit.rotation.y))
	facing.y = 0.0
	return facing.normalized() if facing.length_squared() > 0.0001 else DEFAULT_FORWARD

## Whether `units` attacking `target` fights as a block (ArmyBridge.attack_blocks):
## a group of fighting units ordered onto an enemy it can attack. A selection
## with non-fighters in it (villagers) still closes in man by man.
func can_formation_attack(units: Array[Unit], target: Node) -> bool:
	if units.size() < 2 or not (target is Node3D) or not is_instance_valid(target):
		return false
	if not (target is Unit or (target is ProductionBuilding and target.can_be_attacked())):
		return false
	for unit in units:
		if not unit.can_fight or not Teams.is_enemy(unit.owner_peer_id, target.owner_peer_id):
			return false
	return true
