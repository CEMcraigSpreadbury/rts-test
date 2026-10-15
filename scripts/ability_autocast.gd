class_name AbilityAutocast
extends Node
## Casts the human players' monsters' area abilities for them, when the
## "Monsters Auto-Cast Abilities" option is on: every ready one goes off on the
## spot that catches the most hostiles, as the AI casts its own (AiCombat uses
## best_spot too). Only a monster standing or fighting is cast for; one walking
## where it was sent, or already casting, is left alone. Host-only, made by
## Main._add_components.

const THINK_INTERVAL: float = 0.5
## Never wasted on a lone straggler.
const MIN_TARGETS: int = 2
## How far beyond its activation range a caster looks, since it walks a short
## way in to cast (Unit.command_cast_ability).
const CAST_REACH_SLACK: float = 3.0

var main: Main
var _timer: float = THINK_INTERVAL

func _ready() -> void:
	name = "AbilityAutocast"
	set_physics_process(multiplayer.is_server())

func _physics_process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = THINK_INTERVAL
	if not Settings.get_value(&"auto_cast_abilities") or main.game_over:
		return
	for child in main.units_root.get_children():
		var unit := child as Unit
		if unit == null or not unit.is_monster() or unit.status_activity == Unit.Activity.DEAD:
			continue
		if Network.is_ai(unit.owner_peer_id) or unit.owner_peer_id <= 0:
			continue
		if unit.status_command != Unit.Command.NONE and unit.status_command != Unit.Command.ATTACK \
				and unit.status_command != Unit.Command.ATTACK_MOVE:
			continue
		_cast_for(unit)

func _cast_for(unit: Unit) -> void:
	var abilities: Array[Ability] = unit.get_abilities()
	for i in abilities.size():
		var ability: Ability = abilities[i]
		if ability == null or ability.kind != Ability.Kind.ACTIVATED_AREA or not unit.is_ability_ready(i):
			continue
		if not ResourceStockpile.can_afford(unit.owner_peer_id, ability.costs):
			continue
		var hostiles := hostiles_near(main, unit.owner_peer_id, unit.global_position, ability.activation_range + CAST_REACH_SLACK)
		if hostiles.size() < MIN_TARGETS:
			continue
		var spot: Dictionary = best_spot(unit, ability, hostiles)
		if spot.count >= MIN_TARGETS and main.request_ability_as(unit.owner_peer_id, unit.get_path(), i, spot.pos):
			return

## Living units hostile to `peer_id` (enemy players and neutral guards, never
## an ally's, never harmless game) within `radius` of `pos`.
static func hostiles_near(main: Main, peer_id: int, pos: Vector3, radius: float) -> Array[Unit]:
	var out: Array[Unit] = []
	for child in main.units_root.get_children():
		var other := child as Unit
		if other == null or not Teams.is_enemy(peer_id, other.owner_peer_id) or other.status_activity == Unit.Activity.DEAD:
			continue
		if other.is_harmless_game():
			continue
		if other.global_position.distance_to(pos) <= radius:
			out.append(other)
	return out

## Where `caster` should aim `ability` to catch the most of `hostiles`:
## {pos, count}. A nova or slam (Shape.SELF) only ever goes off where it stands.
static func best_spot(caster: Unit, ability: Ability, hostiles: Array[Unit]) -> Dictionary:
	if ability.shape == Ability.Shape.SELF:
		var around := 0
		for other in hostiles:
			if other.global_position.distance_to(caster.global_position) <= ability.area_radius + caster.get_body_bulk():
				around += 1
		return {pos = caster.global_position, count = around}
	var best_pos := Vector3.ZERO
	var best_count := 0
	for candidate in hostiles:
		var count := 0
		for other in hostiles:
			if ability.shape == Ability.Shape.CONE:
				if in_cone(caster, ability, candidate.global_position, other.global_position):
					count += 1
			elif other.global_position.distance_to(candidate.global_position) <= ability.area_radius:
				count += 1
		if count > best_count:
			best_count = count
			best_pos = candidate.global_position
	return {pos = best_pos, count = best_count}

## Whether `point` falls in `caster`'s breath aimed at `aim_at`.
static func in_cone(caster: Unit, ability: Ability, aim_at: Vector3, point: Vector3) -> bool:
	var aim := Vector2(aim_at.x - caster.global_position.x, aim_at.z - caster.global_position.z)
	var to := Vector2(point.x - caster.global_position.x, point.z - caster.global_position.z)
	if to.length() > ability.activation_range or aim.length_squared() < 0.0001:
		return false
	return absf(aim.angle_to(to)) <= deg_to_rad(ability.cone_angle) * 0.5
