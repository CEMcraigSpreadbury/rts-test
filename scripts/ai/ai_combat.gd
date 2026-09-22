class_name AiCombat
extends RefCounted
## AiPlayer's fighting: what it can see, defending the base, and attack waves.
##
## Sight: the AI only knows about enemy units currently inside the vision
## range of one of its own units or buildings, and about enemy buildings it
## has seen at some point (like explored fog). It also knows where the map's
## spawn points are, as a human does, and treats the ones it hasn't looked at
## yet as places an enemy base might be.
##
## Defence: enemies near any of our buildings pull every soldier at home
## onto them (after AiProfile.defend_reaction_seconds), call an attack wave
## back if home can't hold, and send villagers near the fight to the Town
## Center. Captured objectives' buildings don't count as the base — points
## are defended by sending a wave to them (see Conquest below).
##
## Attack: once enough soldiers are free, they leave as one wave with an
## attack-move on a target. Attack-move fights everything met on the way,
## then clears the target area — so a wave standing idle at its target has
## won there and moves on to the next target. New soldiers join it in
## batches; it retreats home once clearly outmatched.
##
## Capture points come before bases — they pay gold in every mode, and
## Favour (the score) in Conquest. A wave goes for, in order of preference:
## one of our own points under attack, a neutral point whose guards it
## clearly outguns, an enemy's point (more eagerly if that player is close to
## winning Conquest). At a point it clears the guards/defenders, steps inside
## the capture zone and holds until the flag is fully up, then moves on; no
## headway for POINT_HOLD_TIMEOUT means it gives up on that point for a
## while. Bases are the fallback once no point is worth taking.

## Enemies this close to any of our buildings are an attack on the base.
const DEFEND_RADIUS: float = 24.0
## Seconds with no enemy near the base before defenders stand down.
const THREAT_FORGET_SECONDS: float = 6.0
## Defenders are re-ordered once the fight has moved this far.
const DEFEND_REORDER_DISTANCE: float = 8.0
## Villagers this close to an attacker run when the base can't hold.
const FLEE_RADIUS: float = 9.0
## A wave within this of its target counts as arrived. Matches the radius an
## attack-move clears around its destination (Unit.ASSAULT_AREA_RADIUS).
const WAVE_ARRIVE_RADIUS: float = 12.0
## Enemy strength within this of a wave's middle counts as the fight it's in.
const LOCAL_FIGHT_RADIUS: float = 18.0
const RETREAT_COOLDOWN_SECONDS: float = 60.0
## A spawn point counts as looked at once one of our units gets this close,
## and as a known base once an enemy building is seen this close to it.
const SCOUTED_RADIUS: float = 16.0
const BASE_NEAR_SPAWN_RADIUS: float = 30.0
## How long a sighting of an enemy army is remembered for attack decisions.
const STRENGTH_MEMORY_SECONDS: float = 120.0
## Home soldiers further than this from the staging point walk back to it.
const STAGING_LEASH: float = 18.0
## Vision is checked through a grid of this cell size (and the cell around),
## so it must be at least the longest vision range in the game.
const VISION_CELL: float = 16.0
## Main bases are preferred targets by this much distance.
const MAIN_BASE_TARGET_BONUS: float = 20.0

## --- Conquest ---
## Each Favour/second a point pays counts as this much less distance.
const POINT_VALUE_WEIGHT: float = 15.0
## Gold/second counts as this much Favour/second when scoring a point — the
## score is what wins Conquest, gold only pays for the army that wins it.
const GOLD_VALUE_SHARE: float = 1.0 / 3.0
## One of our points under attack is preferred by this much distance...
const DEFEND_POINT_BONUS: float = 45.0
## ...and a point held by a player this close to the Favour target by this.
const LEADER_POINT_BONUS: float = 30.0
const LEADER_THRESHOLD: float = 0.7
## A neutral point is only attacked by a wave this many times stronger than
## its guards.
const GUARD_MARGIN: float = 1.5
## Enemies within this of a point of ours are an attack on it.
const POINT_THREAT_RADIUS: float = 9.0
## A wave's middle within this of its point counts as there, holding it.
const POINT_HOLD_RADIUS: float = 8.0
## Soldiers stand within this of the point's centre while holding — inside
## the capture zone (radius 5 on the stock objectives) with some margin.
const CAPTURE_STAND_RADIUS: float = 3.0
## Holding a point this long without the flag moving our way means it can't
## be taken right now (an equal enemy on it, guards out of reach).
const POINT_HOLD_TIMEOUT: float = 40.0
## A point counts as reachable if a path ends this close to its centre.
const POINT_REACH_TOLERANCE: float = 6.0

var ai: AiPlayer

## Refreshed every think: enemy units our side can currently see.
var visible_enemies: Array[Unit] = []
## Enemy building -> true, for every one ever seen and still standing.
var known_buildings: Dictionary = {}
var _unscouted_spawns: Array[Vector3] = []
var _spawns_initialised: bool = false
## peer -> [strength, game_time] of the biggest army of theirs seen lately.
var _seen_strength: Dictionary = {}

## Untyped on purpose: soldiers die and are freed, and reading a freed entry
## out of a typed Array[Unit] errors before is_instance_valid() can reject it
## (same as Objective._guards). Pruned at the top of every think.
var wave: Array = []
var wave_target: Vector3 = Vector3.ZERO
## Untyped: the building being attacked may be freed.
var _wave_target_node = null
## The capture point the wave is taking or holding, or null.
var _wave_target_objective = null
var _last_retreat_time: float = -INF
## Where the wave's middle was when it last made headway, and when.
var _wave_progress_pos: Vector3 = Vector3.ZERO
var _wave_progress_time: float = 0.0
const WAVE_STALL_SECONDS: float = 20.0
const WAVE_STALL_DISTANCE: float = 3.0
## The spawn point the wave was sent to look at, or null for a building.
var _wave_target_spawn: Variant = null
## Whether the wave has already been re-sent unit-by-unit at this target.
var _wave_resent: bool = false
## Holding a point: the best flag progress seen (our flag's height, or minus
## an enemy flag's height while draining it) and when it last improved.
var _hold_best: float = -INF
var _hold_progress_time: float = 0.0

## Middle of the enemies attacking the base right now, or null.
var threat_pos: Variant = null
var threat_strength: float = 0.0
var _threat_first_seen: float = -1.0
var _last_threat_time: float = -INF
var _defending: bool = false
var _last_defend_pos: Vector3 = Vector3.ZERO

## Fighting the battle once it's joined: re-facing, cavalry (see AiTactics).
var tactics: AiTactics

func _init(p_ai: AiPlayer) -> void:
	ai = p_ai
	tactics = AiTactics.new(p_ai, self)

func think() -> void:
	_prune(wave)
	ai.phase(&"combat: perceive", _perceive)
	ai.phase(&"combat: defence", _update_defence)
	ai.phase(&"combat: wave", _update_wave)
	ai.phase(&"combat: tactics", tactics.think)
	ai.phase(&"combat: home units", _manage_home_units)
	ai.phase(&"combat: unstick", _unstick_units)
	ai.phase(&"combat: abilities", _use_abilities)

## --- Abilities ---

## Hostiles further than this past an ability's reach aren't considered —
## the caster would have to walk out of its fight to get them in range.
const CAST_REACH_SLACK: float = 2.0
## Area abilities cast this match (for tests/tuning).
var abilities_cast: int = 0

## Every ready area ability goes off on the spot that catches the most
## enemies — neutral guards included — as long as that's at least
## AiProfile.ability_min_targets of them. A caster casts where it stands, or
## walks a short way into range (see Unit.command_cast_ability).
func _use_abilities() -> void:
	var min_targets: int = ai.profile.ability_min_targets
	if min_targets <= 0:
		return
	for unit in ai.army:
		var abilities: Array[Ability] = unit.get_abilities()
		for i in abilities.size():
			var ability: Ability = abilities[i]
			if ability == null or ability.kind != Ability.Kind.ACTIVATED_AREA or not unit.is_ability_ready(i):
				continue
			if not ResourceStockpile.can_afford(ai.peer_id, ability.costs):
				continue
			var hostiles := _hostiles_near(unit.global_position, ability.activation_range + CAST_REACH_SLACK)
			if hostiles.size() < min_targets:
				continue
			var best_pos := Vector3.ZERO
			var best_count := 0
			for candidate in hostiles:
				var count := 0
				for other in hostiles:
					if other.global_position.distance_to(candidate.global_position) <= ability.area_radius:
						count += 1
				if count > best_count:
					best_count = count
					best_pos = candidate.global_position
			if best_count >= min_targets and ai.main.request_ability_as(ai.peer_id, unit.get_path(), i, best_pos):
				abilities_cast += 1
				break

## Living units of anyone hostile (enemy players and neutral guards — never an
## ally's) within `radius` of `pos`.
func _hostiles_near(pos: Vector3, radius: float) -> Array[Unit]:
	var out: Array[Unit] = []
	for child in ai.main.units_root.get_children():
		var other := child as Unit
		if other == null or not Teams.is_enemy(ai.peer_id, other.owner_peer_id) or other.status_activity == Unit.Activity.DEAD:
			continue
		if other.global_position.distance_to(pos) <= radius:
			out.append(other)
	return out

## Soldiers that are trying to walk but haven't moved for UNIT_STUCK_SECONDS
## — typically two that ended up exactly on top of each other, which leaves
## their separation push with no direction to part them in. A short step to a
## nearby spot pulls them apart; the wave/home logic re-sends them from there
## once they're idle.
const UNIT_STUCK_SECONDS: float = 8.0
const UNIT_STUCK_DISTANCE: float = 0.4
const UNSTICK_STEP: float = 2.0
## Unit instance id -> [position, game_time it was last seen moving].
var _unit_progress: Dictionary = {}

func _unstick_units() -> void:
	var seen: Dictionary = {}
	for unit in ai.army:
		var id: int = unit.get_instance_id()
		seen[id] = true
		var walking: bool = unit.status_activity == Unit.Activity.MOVING or unit.status_activity == Unit.Activity.TO_TARGET
		var entry: Array = _unit_progress.get(id, [unit.global_position, ai.game_time])
		if not walking or unit.global_position.distance_to(entry[0]) > UNIT_STUCK_DISTANCE:
			_unit_progress[id] = [unit.global_position, ai.game_time]
			continue
		if ai.game_time - entry[1] > UNIT_STUCK_SECONDS:
			var angle: float = randf() * TAU
			var step: Vector3 = unit.global_position + Vector3(cos(angle), 0.0, sin(angle)) * UNSTICK_STEP
			ai.order_move([unit], ai.nearest_navmesh_point(step))
			_unit_progress[id] = [unit.global_position, ai.game_time]
		else:
			_unit_progress[id] = entry
	for id in _unit_progress.keys():
		if not seen.has(id):
			_unit_progress.erase(id)

## Whether `pos` is somewhere villagers should keep away from right now.
func is_threatened(pos: Vector3) -> bool:
	return threat_pos != null and pos.distance_to(threat_pos) < DEFEND_RADIUS

## --- Sight ---

func _perceive() -> void:
	if not _spawns_initialised:
		_init_spawns()
	var grid: Dictionary = {}
	for unit in ai.villagers:
		_add_eye(grid, unit.global_position, unit.vision_range)
	for unit in ai.army:
		_add_eye(grid, unit.global_position, unit.vision_range)
	for building in ai.my_buildings:
		_add_eye(grid, building.global_position, building.vision_range)

	visible_enemies.clear()
	var strength_by_peer: Dictionary = {}
	for child in ai.main.units_root.get_children():
		var unit := child as Unit
		if unit == null or unit.owner_peer_id <= 0 or not Teams.is_enemy(ai.peer_id, unit.owner_peer_id):
			continue
		if unit.status_activity == Unit.Activity.DEAD or not _is_seen(grid, unit.global_position):
			continue
		visible_enemies.append(unit)
		if not unit.can_gather:
			strength_by_peer[unit.owner_peer_id] = float(strength_by_peer.get(unit.owner_peer_id, 0.0)) + unit_strength(unit)
	for peer in strength_by_peer:
		var remembered: Array = _seen_strength.get(peer, [0.0, -INF])
		if strength_by_peer[peer] >= remembered[0] or ai.game_time - remembered[1] > STRENGTH_MEMORY_SECONDS:
			_seen_strength[peer] = [strength_by_peer[peer], ai.game_time]

	for node in ai.get_tree().get_nodes_in_group("buildings"):
		var building := node as ProductionBuilding
		if building == null or building.owner_peer_id <= 0 or not Teams.is_enemy(ai.peer_id, building.owner_peer_id):
			continue
		if not building.can_be_attacked() or known_buildings.has(building):
			continue
		if _is_seen(grid, building.global_position):
			known_buildings[building] = true
	for key in known_buildings.keys():
		if not is_instance_valid(key) or key.is_destroyed or key.owner_peer_id <= 0 or not Teams.is_enemy(ai.peer_id, key.owner_peer_id):
			known_buildings.erase(key)

	## Looked at once any of ours gets within SCOUTED_RADIUS — a spawn marker
	## sits inside where that player's Town Center stands (or stood), so a unit
	## often can't walk right up to it.
	for i in range(_unscouted_spawns.size() - 1, -1, -1):
		var spawn: Vector3 = _unscouted_spawns[i]
		if _any_known_building_near(spawn, BASE_NEAR_SPAWN_RADIUS):
			_unscouted_spawns.remove_at(i)
		elif _any_unit_near(spawn, SCOUTED_RADIUS):
			## Arriving at a spawn is looking at the base there — the Town
			## Center can stand just past one soldier's own vision range from
			## where the army stops, and treating the spot as empty would turn
			## the whole wave round at the gates.
			_reveal_buildings_near(spawn, BASE_NEAR_SPAWN_RADIUS)
			_unscouted_spawns.remove_at(i)

## Every spawn point but our own.
func _init_spawns() -> void:
	_spawns_initialised = true
	for spawn in ai.main.player_spawn_points.get_children():
		var pos: Vector3 = (spawn as Node3D).global_position
		if pos.distance_to(ai.home) > BASE_NEAR_SPAWN_RADIUS:
			_unscouted_spawns.append(pos)

func _add_eye(grid: Dictionary, pos: Vector3, vision: float) -> void:
	var cell := Vector2i(floori(pos.x / VISION_CELL), floori(pos.z / VISION_CELL))
	if not grid.has(cell):
		grid[cell] = []
	grid[cell].append([pos, vision])

func _is_seen(grid: Dictionary, pos: Vector3) -> bool:
	var cx: int = floori(pos.x / VISION_CELL)
	var cz: int = floori(pos.z / VISION_CELL)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for eye in grid.get(Vector2i(cx + dx, cz + dz), []):
				var eye_pos: Vector3 = eye[0]
				if Vector2(eye_pos.x - pos.x, eye_pos.z - pos.z).length() <= eye[1]:
					return true
	return false

func _reveal_buildings_near(pos: Vector3, radius: float) -> void:
	for node in ai.get_tree().get_nodes_in_group("buildings"):
		var building := node as ProductionBuilding
		if building == null or building.owner_peer_id <= 0 or not Teams.is_enemy(ai.peer_id, building.owner_peer_id):
			continue
		if building.can_be_attacked() and building.global_position.distance_to(pos) < radius:
			known_buildings[building] = true

func _any_unit_near(pos: Vector3, radius: float) -> bool:
	for unit in ai.army:
		if unit.global_position.distance_to(pos) < radius:
			return true
	for unit in ai.villagers:
		if unit.global_position.distance_to(pos) < radius:
			return true
	return false

func _any_known_building_near(pos: Vector3, radius: float) -> bool:
	for building in known_buildings:
		if is_instance_valid(building) and building.global_position.distance_to(pos) < radius:
			return true
	return false

## Rough fighting worth: health times damage per second.
static func unit_strength(unit: Unit) -> float:
	return float(maxi(unit.status_current_health, 0)) * float(unit.attack_damage) / maxf(unit.attack_cooldown, 0.2)

static func building_strength(building: ProductionBuilding) -> float:
	if building.attack_range <= 0.0:
		return 0.0
	return float(maxi(building.current_health, 0)) * float(building.attack_damage) / maxf(building.attack_cooldown, 0.2)

func _strength_of(units: Array) -> float:
	var total := 0.0
	for unit in units:
		if is_instance_valid(unit):
			total += unit_strength(unit)
	return total

## Enemy units we can see near `pos`, plus any known enemy tower that can
## reach there.
func _enemy_strength_near(pos: Vector3, radius: float) -> float:
	var total := 0.0
	for enemy in visible_enemies:
		if is_instance_valid(enemy) and not enemy.can_gather and enemy.global_position.distance_to(pos) < radius:
			total += unit_strength(enemy)
	for building in known_buildings:
		if is_instance_valid(building) and building.global_position.distance_to(pos) < radius + building.attack_range:
			total += building_strength(building)
	return total

## --- Defence ---

func _update_defence() -> void:
	var attackers: Array[Unit] = []
	for enemy in visible_enemies:
		for building in ai.my_buildings:
			## A captured objective's building isn't the base — see the class notes.
			if building.is_invulnerable:
				continue
			if enemy.global_position.distance_to(building.global_position) < DEFEND_RADIUS + building.get_footprint_radius():
				attackers.append(enemy)
				break
	if attackers.is_empty():
		threat_pos = null
		threat_strength = 0.0
		_threat_first_seen = -1.0
		if _defending and ai.game_time - _last_threat_time > THREAT_FORGET_SECONDS:
			_defending = false
			ai.order_move(_home_army(), ai.builder.staging_point())
		return
	_last_threat_time = ai.game_time
	if _threat_first_seen < 0.0:
		_threat_first_seen = ai.game_time
	threat_pos = ai.group_centroid(attackers)
	threat_strength = _strength_of(attackers)
	if ai.game_time - _threat_first_seen < ai.profile.defend_reaction_seconds:
		return

	var responders := _home_army()
	var home_strength := _strength_of(responders)
	if ai.profile.recall_army_to_defend and not wave.is_empty() and home_strength < threat_strength * 1.2:
		responders.append_array(wave)
		home_strength += _strength_of(wave)
		_clear_wave()
	if not responders.is_empty():
		var anyone_idle := false
		for unit in responders:
			if unit.status_command == Unit.Command.NONE:
				anyone_idle = true
				break
		if not _defending or anyone_idle or _last_defend_pos.distance_to(threat_pos) > DEFEND_REORDER_DISTANCE:
			ai.order_move(responders, threat_pos, true)
			_defending = true
			_last_defend_pos = threat_pos
	if ai.profile.villagers_flee and home_strength < threat_strength:
		_flee_villagers(attackers)

func _flee_villagers(attackers: Array[Unit]) -> void:
	if ai.town_center == null:
		return
	var runners: Array[Unit] = []
	for villager in ai.villagers:
		if villager.status_command == Unit.Command.MOVE:
			continue
		for enemy in attackers:
			if villager.global_position.distance_to(enemy.global_position) < FLEE_RADIUS:
				runners.append(villager)
				break
	var dropoff: Node3D = ai.town_center.get_node_or_null("DropoffPoint")
	ai.order_move(runners, dropoff.global_position if dropoff != null else ai.home)

## --- Attack waves ---

## A wave worn down below this goes home to be folded into the next one,
## rather than one or two soldiers wandering from point to point alone.
const MIN_WAVE_SIZE: int = 3

func _update_wave() -> void:
	if wave.is_empty():
		_clear_wave()
		if not _defending:
			_maybe_launch_wave()
		return
	if wave.size() < MIN_WAVE_SIZE:
		_send_wave_home()
		return
	var centre: Vector3 = ai.group_centroid(wave)
	var own := _strength_of(wave)
	var enemy := _enemy_strength_near(centre, LOCAL_FIGHT_RADIUS)
	if ai.profile.retreat_threshold > 0.0 and enemy > 0.0 and own < enemy * ai.profile.retreat_threshold:
		_retreat()
		return
	if is_instance_valid(_wave_target_objective) and _update_point_hold(centre):
		return
	if ai.mode == AiPlayer.Mode.ATTACK:
		_update_attack_hold()
		return
	var target_gone: bool = _wave_target_node != null and (not is_instance_valid(_wave_target_node) or _wave_target_node.is_destroyed \
			or _wave_target_node.owner_peer_id <= 0 or not Teams.is_enemy(ai.peer_id, _wave_target_node.owner_peer_id))
	## Sent to look at a spawn point, and it's been looked at.
	if _wave_target_spawn != null and not _unscouted_spawns.has(_wave_target_spawn):
		target_gone = true
	## Out scouting a spawn, but an enemy building has turned up since — go
	## for that instead of an empty corner.
	if _wave_target_spawn != null and not known_buildings.is_empty():
		target_gone = true
	var all_idle := true
	for unit in wave:
		if unit.status_command != Unit.Command.NONE:
			all_idle = false
			break
	var arrived: bool = Vector2(centre.x - wave_target.x, centre.z - wave_target.z).length() < WAVE_ARRIVE_RADIUS
	if target_gone or (all_idle and arrived and _wave_target_objective == null):
		if not _send_wave_to_next_target(centre):
			_send_wave_home()
		return
	## A wave that stops getting anywhere without being in a fight has
	## wedged itself (a group pacing to a stuck member, a jammed chokepoint):
	## re-order everyone on their own, which drops the group pacing and the
	## funnel, and lets each unit find its own way.
	var fighting := false
	for unit in wave:
		if unit.status_activity == Unit.Activity.ATTACKING or unit.status_activity == Unit.Activity.TO_TARGET:
			fighting = true
			break
	if fighting or centre.distance_to(_wave_progress_pos) > WAVE_STALL_DISTANCE:
		_wave_progress_pos = centre
		_wave_progress_time = ai.game_time
	elif ai.game_time - _wave_progress_time > WAVE_STALL_SECONDS:
		if _breach(wave):
			_wave_progress_pos = centre
			_wave_progress_time = ai.game_time
			return
		## Already re-sent everyone once and still wedged: this target can't be
		## got at from here — take the next one.
		if _wave_resent:
			if not _send_wave_to_next_target(centre, true):
				_send_wave_home()
			return
		for unit in wave:
			ai.order_move([unit], wave_target, true)
		_wave_resent = true
		_wave_progress_pos = centre
		_wave_progress_time = ai.game_time
		return
	_send_stragglers_on()

## ATTACK mode: the wave goes where it was sent and stays there. Neither the
## scouting rules nor "arrived, find something else" apply — an ally sent to
## guard a village stands in it and fights whatever comes, rather than
## wandering off after capture points once it gets there. Home troops keep
## joining it (see _manage_home_units). A new attack_position (SetAiModeAction
## mid-mission: "now march on the camp") moves the wave that is already out.
func _update_attack_hold() -> void:
	var aim: Vector3 = ai.nearest_navmesh_point(ai.attack_position)
	if Vector2(aim.x - wave_target.x, aim.z - wave_target.z).length() > 3.0:
		_set_wave_target({pos = ai.attack_position, node = null, objective = null, peer = 0})
		return
	_send_stragglers_on()

## Soldiers standing idle short of the target (a fight finished, or the path
## ran out against a wall) walk on — or break through what's in the way.
func _send_stragglers_on() -> void:
	var stragglers: Array[Unit] = []
	for unit in wave:
		if unit.status_command == Unit.Command.NONE and unit.global_position.distance_to(wave_target) > WAVE_ARRIVE_RADIUS \
				and not tactics.is_detached(unit):
			stragglers.append(unit)
	if stragglers.is_empty() or _breach(stragglers):
		return
	ai.order_move(stragglers, wave_target, true)

## --- Breaching ---

## An enemy building within this of where a path runs out (past its own
## footprint) counts as what's blocking it.
const BREACH_SEARCH_RADIUS: float = 5.0
## A path ending this close to a spawn/position target isn't blocked.
const BREACH_REACH_TOLERANCE: float = 4.0

## When the walk from `units` to the wave target runs out short of it, orders
## them to attack the enemy building (a wall, a gate) standing in the way.
## Returns whether it did. Once it falls they go idle and are sent on again,
## which re-checks the path.
func _breach(units: Array) -> bool:
	var blocker := find_blocker(units[0].global_position, wave_target, _wave_reach_tolerance())
	if blocker == null:
		return false
	ai.order_target(units, blocker)
	return true

func _wave_reach_tolerance() -> float:
	if is_instance_valid(_wave_target_objective):
		return POINT_REACH_TOLERANCE
	if is_instance_valid(_wave_target_node):
		return _wave_target_node.get_footprint_radius() + TARGET_REACH_SLACK
	return BREACH_REACH_TOLERANCE

## The attackable enemy building blocking the way from `from` to `to`, or
## null when a path gets within `tolerance` of `to` or nothing hostile is in
## the way (a cliff, our own or an ally's wall). Picks the building nearest
## where the path runs out, leaning towards the target side.
func find_blocker(from: Vector3, to: Vector3, tolerance: float) -> ProductionBuilding:
	if not ai.nav_ready():
		return null
	var nav_map: RID = ai.main.get_world_3d().navigation_map
	var path: PackedVector3Array = NavigationServer3D.map_get_path(nav_map, ai.nearest_navmesh_point(from), to, true)
	if path.is_empty():
		return null
	var end: Vector3 = path[path.size() - 1]
	if Vector2(end.x - to.x, end.z - to.z).length() <= tolerance:
		return null
	var best: ProductionBuilding = null
	var best_score := INF
	for node in ai.get_tree().get_nodes_in_group("buildings"):
		var building := node as ProductionBuilding
		if building == null or not building.can_be_attacked() or building.owner_peer_id <= 0 \
				or not Teams.is_enemy(ai.peer_id, building.owner_peer_id):
			continue
		var pos: Vector3 = building.global_position
		var gap: float = Vector2(pos.x - end.x, pos.z - end.z).length() - building.get_footprint_radius()
		if gap > BREACH_SEARCH_RADIUS:
			continue
		var score: float = gap + Vector2(pos.x - to.x, pos.z - to.z).length() * 0.25
		if score < best_score:
			best_score = score
			best = building
	return best

## The wave's point is taken (or can't be): move on. At the point: keep
## everyone inside the capture zone and watch the flag. Returns whether it
## handled the wave this think — false while the wave is still on its way,
## which leaves it to the ordinary walking/stall logic.
func _update_point_hold(centre: Vector3) -> bool:
	var point = _wave_target_objective
	var point_pos: Vector3 = point.global_position
	if _point_secured(point):
		if not _send_wave_to_next_target(centre):
			_send_wave_home()
		return true
	if Vector2(centre.x - point_pos.x, centre.z - point_pos.z).length() > POINT_HOLD_RADIUS:
		return false
	## Headway: our flag rising, or the owner's flag coming down.
	var progress: float = point.flag_control if point.flag_peer_id == ai.peer_id else -point.flag_control
	if _hold_best == -INF or progress > _hold_best + 0.01:
		_hold_best = progress
		_hold_progress_time = ai.game_time
	elif ai.game_time - _hold_progress_time > POINT_HOLD_TIMEOUT:
		if not _send_wave_to_next_target(centre, true):
			_send_wave_home()
		return true
	## Only soldiers inside the zone count, and a formation spreads wider than
	## it — anyone standing about outside is walked in, one by one so they
	## don't just reform the same shape.
	for unit in wave:
		if unit.status_command == Unit.Command.NONE and unit.global_position.distance_to(point_pos) > CAPTURE_STAND_RADIUS + 1.0:
			var angle: float = randf() * TAU
			var spot: Vector3 = point_pos + Vector3(cos(angle), 0.0, sin(angle)) * randf() * CAPTURE_STAND_RADIUS
			ai.order_move([unit], ai.nearest_navmesh_point(spot), true)
	return true

## Our side's (an ally's counts), flag fully up, and nobody fighting over it.
func _point_secured(point) -> bool:
	return point.owner_peer_id > 0 and Teams.is_friendly(ai.peer_id, point.owner_peer_id) \
			and point.flag_control >= 1.0 and not point.contested \
			and not _enemies_near(point.global_position, POINT_THREAT_RADIUS)

func _enemies_near(pos: Vector3, radius: float) -> bool:
	for enemy in visible_enemies:
		if is_instance_valid(enemy) and not enemy.can_gather and enemy.global_position.distance_to(pos) < radius:
			return true
	return false

func _maybe_launch_wave() -> void:
	var p: AiProfile = ai.profile
	## A side told to hold its ground keeps its army home; defending itself
	## (see _defend) carries on as normal.
	if ai.mode == AiPlayer.Mode.DEFEND:
		return
	if ai.game_time - _last_retreat_time < RETREAT_COOLDOWN_SECONDS:
		return
	var pool := _home_army()
	var keep: int = int(pool.size() * p.home_guard_share)
	var free: int = mini(pool.size() - keep, p.attack_max_wave)
	## Points pay gold in every mode (Favour too in Conquest), so they're
	## worth taking in Annihilation as well.
	var can_capture: bool = ai.game_time >= p.first_capture_seconds and free >= p.capture_min_army
	var can_attack: bool = ai.game_time >= p.first_attack_seconds and free >= p.attack_min_army
	if not can_capture and not can_attack:
		return
	## The soldiers furthest forward go; those nearest home stay as the guard.
	pool.sort_custom(func(a: Unit, b: Unit) -> bool:
		return a.global_position.distance_squared_to(ai.map_centre) < b.global_position.distance_squared_to(ai.map_centre))
	var attackers: Array[Unit] = pool.slice(0, free)
	var target: Dictionary = {}
	if ai.mode == AiPlayer.Mode.ATTACK:
		## Sent somewhere specific: go there and keep going there, rather than
		## weighing up the map. Whatever is standing on the spot gets fought on
		## the way in, the same as any other wave.
		target = {pos = ai.attack_position, node = null, objective = null, peer = 0}
	else:
		target = _choose_target(ai.home, _strength_of(attackers), can_capture, can_attack)
	if target.is_empty():
		return
	if target.objective == null and p.attack_advantage > 0.0:
		var seen: float = _remembered_strength(target.peer)
		if seen > 0.0 and _strength_of(attackers) < seen * p.attack_advantage:
			return
	wave = attackers
	_set_wave_target(target)

## {pos: Vector3, node: building or null, objective: point or null, peer: int},
## or {} when there's nowhere worth going. Capture points first (Conquest
## only, and only if `points`), then — if `bases` — the nearest known enemy
## building (main bases preferred) of a player still in the match, then the
## nearest spawn not yet looked at. `strength` is the wave's, for deciding
## which guarded points it can take. Anything no path from `from` leads to is
## skipped, and put on the same cooldown as a target a wave gave up on.
func _choose_target(from: Vector3, strength: float, points: bool = true, bases: bool = true) -> Dictionary:
	var groups: Array = []
	if points:
		groups.append(_point_candidates(from, strength))
	if bases:
		var buildings: Array = []
		for building in known_buildings:
			if not is_instance_valid(building) or not ai.main.is_peer_active(building.owner_peer_id) or _on_cooldown(building):
				continue
			var score: float = building.global_position.distance_to(from)
			if building.is_main_base:
				score -= MAIN_BASE_TARGET_BONUS
			buildings.append([score, {pos = building.global_position, node = building, objective = null, peer = building.owner_peer_id},
					building.get_footprint_radius() + TARGET_REACH_SLACK])
		groups.append(buildings)
		var spawns: Array = []
		for spawn in _unscouted_spawns:
			if not _on_cooldown(spawn):
				spawns.append([spawn.distance_to(from), {pos = spawn, node = null, objective = null, peer = 0}, SCOUTED_RADIUS])
		groups.append(spawns)
	for candidates in groups:
		candidates.sort_custom(func(a, b): return a[0] < b[0])
		for i in mini(candidates.size(), TARGET_REACH_CHECKS):
			var target: Dictionary = candidates[i][1]
			if ai.is_reachable(target.pos, candidates[i][2], from) or find_blocker(from, target.pos, candidates[i][2]) != null:
				return target
			_unreachable_until[_target_key(target)] = ai.game_time + UNREACHABLE_RETRY_SECONDS
	return {}

## [score, target, reach tolerance] for every capture point worth a wave of
## `strength` right now — see the class notes for the order of preference.
func _point_candidates(from: Vector3, strength: float) -> Array:
	var out: Array = []
	for point in ai.objectives:
		if not is_instance_valid(point) or _on_cooldown(point):
			continue
		var pos: Vector3 = point.global_position
		var income: float = (point.gold_per_second + point.wood_per_second) * GOLD_VALUE_SHARE
		if ai.main.conquest_enabled:
			income += point.favour_per_second
		var score: float = pos.distance_to(from) - income * POINT_VALUE_WEIGHT
		if point.owner_peer_id > 0 and Teams.is_friendly(ai.peer_id, point.owner_peer_id):
			if _point_secured(point):
				continue
			score -= DEFEND_POINT_BONUS
		elif point.owner_peer_id == 0:
			if strength < _guard_strength(point) * GUARD_MARGIN:
				continue
		elif _near_victory(point.owner_peer_id):
			score -= LEADER_POINT_BONUS
		out.append([score, {pos = pos, node = null, objective = point, peer = point.owner_peer_id}, POINT_REACH_TOLERANCE])
	return out

## Everything still standing guard on a neutral point.
func _guard_strength(point) -> float:
	var total := 0.0
	for guard in point._guards:
		if is_instance_valid(guard) and guard.status_activity != Unit.Activity.DEAD:
			total += unit_strength(guard)
	return total

## Main.scores is per team, so this asks about the owner's whole side.
func _near_victory(peer: int) -> bool:
	var target: int = ai.main.favour_target
	var team: int = Teams.team_of(peer)
	if target <= 0 or not ai.main.scores.has(team):
		return false
	return float(ai.main.scores[team].score) >= target * LEADER_THRESHOLD

func _target_key(target: Dictionary):
	if target.objective != null:
		return target.objective
	return target.node if target.node != null else target.pos

func _on_cooldown(key) -> bool:
	return ai.game_time < float(_unreachable_until.get(key, -INF))

## Targets a wave gave up on, or no path led to: building, point or spawn
## position -> game_time before which they're not picked again.
var _unreachable_until: Dictionary = {}
const UNREACHABLE_RETRY_SECONDS: float = 120.0
## Path queries spent per target search (nearest candidates first).
const TARGET_REACH_CHECKS: int = 4
## A building counts as reachable if a path ends this far past its footprint.
const TARGET_REACH_SLACK: float = 4.0

func _remembered_strength(peer: int) -> float:
	if peer <= 0 or not _seen_strength.has(peer):
		return 0.0
	var entry: Array = _seen_strength[peer]
	return entry[0] if ai.game_time - entry[1] <= STRENGTH_MEMORY_SECONDS else 0.0

func _set_wave_target(target: Dictionary) -> void:
	var is_spawn: bool = target.node == null and target.objective == null
	wave_target = ai.nearest_navmesh_point(target.pos) if is_spawn else target.pos
	_wave_target_node = target.node
	_wave_target_objective = target.objective
	_wave_target_spawn = target.pos if is_spawn else null
	_wave_resent = false
	_hold_best = -INF
	_hold_progress_time = ai.game_time
	_wave_progress_pos = ai.group_centroid(wave)
	_wave_progress_time = ai.game_time
	ai.order_move(wave, wave_target, true)
	tactics.reset()

## `give_up_current`: the current target proved unreachable (or untakeable) —
## it's left alone for UNREACHABLE_RETRY_SECONDS (see _choose_target).
func _send_wave_to_next_target(from: Vector3, give_up_current: bool = false) -> bool:
	if give_up_current:
		if is_instance_valid(_wave_target_objective):
			_unreachable_until[_wave_target_objective] = ai.game_time + UNREACHABLE_RETRY_SECONDS
		if is_instance_valid(_wave_target_node):
			_unreachable_until[_wave_target_node] = ai.game_time + UNREACHABLE_RETRY_SECONDS
		if _wave_target_spawn != null:
			_unreachable_until[_wave_target_spawn] = ai.game_time + UNREACHABLE_RETRY_SECONDS
	## A small capture party doesn't go on to storm a base.
	var bases: bool = wave.size() >= ai.profile.attack_min_army and ai.game_time >= ai.profile.first_attack_seconds
	var target := _choose_target(from, _strength_of(wave), true, bases)
	if target.is_empty():
		return false
	_set_wave_target(target)
	return true

func _send_wave_home() -> void:
	ai.order_move(wave, ai.builder.staging_point())
	_clear_wave()

func _clear_wave() -> void:
	wave.clear()
	tactics.reset()
	_wave_target_node = null
	_wave_target_objective = null
	_wave_target_spawn = null

## A plain move, not an attack-move — it has to break off, not fight its way
## home.
func _retreat() -> void:
	_last_retreat_time = ai.game_time
	_send_wave_home()

## --- Home army ---

func _home_army() -> Array[Unit]:
	var home: Array[Unit] = []
	for unit in ai.army:
		if not wave.has(unit):
			home.append(unit)
	return home

func _manage_home_units() -> void:
	if _defending:
		return
	var home := _home_army()
	var staging: Vector3 = ai.builder.staging_point()
	## Reinforce the wave with whoever is waiting at home beyond the guard.
	if not wave.is_empty():
		var keep: int = int(ai.army.size() * ai.profile.home_guard_share)
		var waiting: Array[Unit] = []
		for unit in home:
			if unit.status_command == Unit.Command.NONE and unit.global_position.distance_to(staging) < STAGING_LEASH:
				waiting.append(unit)
		var spare: int = home.size() - keep
		if spare >= ai.profile.reinforce_batch and waiting.size() >= ai.profile.reinforce_batch:
			var batch: Array[Unit] = waiting.slice(0, mini(spare, waiting.size()))
			wave.append_array(batch)
			ai.order_move(batch, wave_target, true)
			return
	## Anyone left wandering after a fight walks back.
	var strays: Array[Unit] = []
	for unit in home:
		if unit.status_command == Unit.Command.NONE and unit.global_position.distance_to(staging) > STAGING_LEASH:
			strays.append(unit)
	ai.order_move(strays, staging)

static func _prune(units: Array) -> void:
	for i in range(units.size() - 1, -1, -1):
		var unit = units[i]
		if not is_instance_valid(unit) or unit.status_activity == Unit.Activity.DEAD:
			units.remove_at(i)
