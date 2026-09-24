class_name Regiment
extends RefCounted
## A persistent body of men under one Officer — the thing the player actually
## commands, Cossacks-style. The men are still individual Units, trained one
## at a time, each with its own body and its own health; a regiment is the
## identity that survives *between* orders.
##
## The codebase already had all of this, transiently: Unit.formation_group,
## dragged_formation, arrived_group and attack_move_order are the same idea
## rebuilt from scratch on every order and cleared by the next one. A regiment
## is that group identity made persistent and given an owner. Nothing here
## replaces the formation machinery — GroupMovement still solves the shapes
## and runs the marches; this only says who is in the block and what shape it
## was last holding.
##
## Host-side only, like every other authoritative record (see Main.regiments).

## A regiment is raised in whole ranks: any multiple of STEP, from a six-man
## company up to MAX_SIZE. Whole ranks are what keep a block a clean rectangle
## rather than a formation with a half-empty back row, and fixing the size at
## forming is what makes its shape and the cost of ordering it predictable —
## instead of both depending on however many men were box-selected.
const STEP: int = 6
const MIN_SIZE: int = 6
const MAX_SIZE: int = 120

## What being led is worth: a proportion added to damage, and armour points on
## top of whatever the Blacksmith has given. Bigger bodies are worth more,
## because holding one together under a single officer is the harder thing —
## SIZE_BANDS is the size each step up asks for. Applied while the officer
## lives and dropped the moment he falls.
const SIZE_BANDS: Array[int] = [0, 72, 120]
const DAMAGE_BONUS: Array[float] = [0.10, 0.15, 0.20]
const ARMOR_BONUS: Array[int] = [1, 2, 3]

## The largest whole-rank body `count` men can fill, or -1 if they cannot even
## make the smallest.
static func size_for(count: int) -> int:
	if count < MIN_SIZE:
		return -1
	return mini(count - count % STEP, MAX_SIZE)

## The officer's place: always behind his men, whatever the block's size.
const OFFICER_RANK: int = 1 << 20

static var _next_id: int = 1

var id: int = 0
var owner_peer_id: int = 0
## How many men this body was raised to hold. A multiple of STEP.
var size: int = MIN_SIZE
## The officer leading it. A regiment outlives its officer — the men hold
## together and still take orders — but loses its buffs until another one
## takes over (see has_officer).
var officer: Unit = null
## The men, officer excluded.
var members: Array[Unit] = []

## The shape this regiment holds between orders, so it re-forms into the block
## it was last put in rather than whatever type happens to be selected. Starts
## as the default and is overwritten by an order that says otherwise.
var formation_type: Formation.Type = Formation.DEFAULT_TYPE
var front_width: float = -1.0
var facing: Vector3 = Vector3.ZERO

static func create(peer_id: int, established_size: int) -> Regiment:
	var regiment := Regiment.new()
	regiment.id = _next_id
	_next_id += 1
	regiment.owner_peer_id = peer_id
	regiment.size = clampi(established_size - established_size % STEP, MIN_SIZE, MAX_SIZE)
	return regiment

## How many men this regiment is established to hold.
func capacity() -> int:
	return size

## Which step of the bonuses this body has earned by its size.
func bonus_band() -> int:
	var band := 0
	for i in SIZE_BANDS.size():
		if size >= SIZE_BANDS[i]:
			band = i
	return band

## Men still in it. prune() first if the answer has to be exact after a fight.
func strength() -> int:
	return members.size()

func is_under_strength() -> bool:
	return members.size() < capacity()

## Whether the buffs apply. A regiment whose officer is dead keeps its shape,
## keeps its selection and keeps taking orders — it just stops being better
## at fighting until a new officer is assigned.
func has_officer() -> bool:
	return is_instance_valid(officer) and officer.status_activity != Unit.Activity.DEAD

## Everyone who answers this regiment's orders, the officer included.
func all_units() -> Array[Unit]:
	var out: Array[Unit] = members.duplicate()
	if has_officer():
		out.append(officer)
	return out

## Drops the dead and the freed. Membership is only ever lost by dying or by
## disbanding — giving an order to part of a regiment does not split it.
func prune() -> void:
	for i in range(members.size() - 1, -1, -1):
		var unit: Unit = members[i]
		if not is_instance_valid(unit) or unit.status_activity == Unit.Activity.DEAD:
			members.remove_at(i)

## Nothing left to command: every man down and no officer standing.
func is_spent() -> bool:
	return members.is_empty() and not has_officer()

## Takes `unit` in if there is room. Officers are set with set_officer, not
## added as men.
func add(unit: Unit) -> bool:
	if unit == null or unit.is_officer or members.size() >= capacity() or members.has(unit):
		return false
	members.append(unit)
	unit.regiment_id = id
	unit.regiment_rank = _free_rank()
	return true

## The lowest place nobody is holding. Reused rather than always counting up,
## so men who join to replace losses fill the holes in the block instead of
## forming a new rank behind it.
func _free_rank() -> int:
	var taken: Dictionary = {}
	for unit in members:
		if is_instance_valid(unit):
			taken[unit.regiment_rank] = true
	var rank := 0
	while taken.has(rank):
		rank += 1
	return rank

## What kind of soldier this body is made of. A regiment is always one type
## (see Main.largest_same_type), so any member answers for all of them. Empty
## for a regiment worn down to nothing but its officer.
func unit_type() -> String:
	for unit in members:
		if is_instance_valid(unit):
			return unit.display_name
	return ""

## Room left before it is back up to its established size.
func room() -> int:
	return maxi(capacity() - members.size(), 0)

func set_officer(unit: Unit) -> bool:
	if unit == null or not unit.is_officer:
		return false
	if is_instance_valid(officer):
		officer.regiment_id = -1
	officer = unit
	unit.regiment_id = id
	unit.regiment_rank = OFFICER_RANK
	return true

## Lets everyone go, so they can be selected and ordered as loose units again.
func release() -> void:
	for unit in members:
		if is_instance_valid(unit):
			unit.regiment_id = -1
			unit.regiment_rank = -1
			unit.regiment_damage_bonus = 0.0
			unit.regiment_armor_bonus = 0
	if is_instance_valid(officer):
		officer.regiment_id = -1
		officer.regiment_rank = -1
		officer.regiment_damage_bonus = 0.0
		officer.regiment_armor_bonus = 0
	members.clear()
	officer = null
