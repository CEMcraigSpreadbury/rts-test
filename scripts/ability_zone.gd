class_name AbilityZone
extends Node
## Host-only lingering ground left behind by an area ability with a
## linger_duration (burning ground, acid pools, frost). Hurts every enemy unit
## standing in it once per TICK_INTERVAL, so units that walk in after the
## impact are caught too. Owns no visuals — every peer draws its own copy of
## the pool off the same impact (see WorldFeedback._play_lingering_zone).
##
## A separate node rather than state on the caster, so the ground keeps
## burning after the monster that made it has died.

const TICK_INTERVAL: float = 1.0

var ability: Ability
var center: Vector3
var owner_peer_id: int = 0
## Who gets credit for the damage. Untyped, same freed-object reasoning as
## Unit._is_target_alive — the caster can be freed while the ground burns.
var source = null

var _time_left: float = 0.0
## Starts a full interval out: the impact itself already hit everything
## inside, so the first zone tick shouldn't double it up on the same frame.
var _tick_timer: float = TICK_INTERVAL

static func spawn(parent: Node, ability_: Ability, center_: Vector3, owner_peer_id_: int, source_) -> void:
	var zone := AbilityZone.new()
	zone.ability = ability_
	zone.center = center_
	zone.owner_peer_id = owner_peer_id_
	zone.source = source_
	zone._time_left = ability_.linger_duration
	parent.add_child(zone)

func _physics_process(delta: float) -> void:
	_time_left -= delta
	_tick_timer -= delta
	if _tick_timer <= 0.0:
		_tick_timer += TICK_INTERVAL
		_tick()
	if _time_left <= 0.0:
		queue_free()

## Victims are collected before any damage lands, same as
## Unit._execute_area_ability — a kill pulls a node out of the group mid-loop.
func _tick() -> void:
	var victims: Array[Unit] = []
	var flat_center := Vector2(center.x, center.z)
	for node in get_tree().get_nodes_in_group("units"):
		var unit := node as Unit
		if unit == null or unit.owner_peer_id == owner_peer_id or unit.status_activity == Unit.Activity.DEAD:
			continue
		if flat_center.distance_to(Vector2(unit.global_position.x, unit.global_position.z)) <= ability.area_radius:
			victims.append(unit)
	for victim in victims:
		if is_instance_valid(victim):
			victim.apply_zone_tick(ability, source if is_instance_valid(source) else null)
