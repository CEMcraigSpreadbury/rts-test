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

## Where a dragged formation's men will stand, from the same block plan the
## order uses (ArmyBridge.plan_blocks) — one block per unit type or regiment,
## side by side — so the preview is the shape the order will actually make.
## Returns [slots, officers]: the officers' and Lords' places come last, the
## trailing `officers` of them, so the preview can mark them out.
func drag_preview(units: Array[Unit], line_start: Vector3, facing: Vector3, formation_type: Formation.Type = Formation.DEFAULT_TYPE) -> Array:
	var slots: Array[Vector3] = []
	var officer_slots: Array[Vector3] = []
	for entry: Dictionary in ArmyBridge.plan_blocks(units, line_start, formation_type, facing, false):
		var block: Array[Unit] = entry.block
		if block.size() == 1 and block[0].is_lord:
			officer_slots.append(entry.dest)
			continue
		var places: Array = ArmyBridge.block_slots(block, entry.dest, entry.forward, formation_type)
		slots.append_array(places[0])
		officer_slots.append_array(places[1])
	if slots.is_empty():
		return [officer_slots, 0]
	slots.append_array(officer_slots)
	return [slots, officer_slots.size()]

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
