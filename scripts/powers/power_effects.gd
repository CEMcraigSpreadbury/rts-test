class_name PowerEffects
extends Node
## The faction powers' set pieces (ResearchNode.set_piece). The host runs each
## cast's timeline — the warning on the ground, the strike, what it leaves
## behind — dealing its damage and telling every peer's PowerFx what to draw
## and when. Research.cast_as has already checked and paid for the cast.
##
## Each run is a Dictionary ticked by its set piece's _tick_<name>, which
## returns true once it is over. The numbers live here, by power; a node's own
## radius, line, telegraph, duration, buffs and colour are read where they fit.

## --- Royal Volley ---
const VOLLEY_SECONDS: float = 3.5
const VOLLEY_TICK: float = 0.35
const VOLLEY_DAMAGE: int = 3
const VOLLEY_BUILDING_DAMAGE: int = 2
## --- Charge of the Old Kings ---
const CHARGE_SECONDS: float = 3.8
const CHARGE_DAMAGE: int = 40
const CHARGE_BUILDING_DAMAGE: int = 80
const CHARGE_THROW: float = 5.0
const CHARGE_STUN: float = 1.0
## --- The Sword of Aldmere ---
const SWORD_FALL: float = 0.9
const SWORD_DAMAGE: int = 40
const SWORD_BUILDING_DAMAGE: int = 120
const SWORD_THROW: float = 5.0
const SWORD_STUN: float = 1.2
const SWORD_STAYS: float = 60.0
const SWORD_AURA_RADIUS: float = 12.0
const SWORD_AURA_TICK: float = 1.0
const SWORD_AURA_HEAL: int = 3
const SWORD_GOLD: Color = Color(1.0, 0.86, 0.4)
## --- Cursed Treasure ---
const TREASURE_LURE_SECONDS: float = 4.0
const TREASURE_LURE_RADIUS: float = 12.0
const TREASURE_LURE_TICK: float = 0.5
const TREASURE_BLAST_RADIUS: float = 6.5
const TREASURE_DAMAGE: int = 40
const TREASURE_BUILDING_DAMAGE: int = 90
const TREASURE_THROW: float = 6.0
const TREASURE_STUN: float = 1.5
## --- Ghost Crew ---
const GHOST_RISE_DELAY: float = 0.8
## --- The Dread Galleon ---
const GALLEON_SPEED: float = 14.0
## The ship comes in from this far behind the line's start and sails this far
## past its end.
const GALLEON_RUN_IN: float = 14.0
const GALLEON_HULL_HALF: float = 4.5
const GALLEON_BOW_AHEAD: float = 7.0
const GALLEON_BOW_DAMAGE: int = 30
const GALLEON_BOW_BUILDING_DAMAGE: int = 150
const GALLEON_BOW_THROW: float = 7.0
const GALLEON_BOW_STUN: float = 1.2
const GALLEON_VOLLEY_TICK: float = 0.45
const GALLEON_BALLS_PER_SIDE: int = 3
const GALLEON_BROADSIDE_NEAR: float = 6.0
const GALLEON_BROADSIDE_FAR: float = 17.0
const GALLEON_BALL_FLIGHT: float = 0.55
const GALLEON_BALL_RADIUS: float = 3.0
const GALLEON_BALL_DAMAGE: int = 22
const GALLEON_BALL_BUILDING_DAMAGE: int = 45
## --- Overclock ---
const OVERCLOCK_SECONDS: float = 12.0
const OVERCLOCK_SEIZE: float = 4.0
const OVERCLOCK_COLOR: Color = Color(1.0, 0.18, 0.1)
## Red-hot all over, not just a wash.
const OVERCLOCK_TINT_STRENGTH: float = 0.85
## --- Orbital Lance ---
const LANCE_SECONDS: float = 6.0
const LANCE_SPEED: float = 8.0
const LANCE_RADIUS: float = 2.8
const LANCE_TICK: float = 0.25
const LANCE_DAMAGE: int = 9
const LANCE_BUILDING_DAMAGE: int = 16
const LANCE_SYNC: float = 0.1
## --- Colossus Drop ---
const POD_FALL: float = 0.5
const POD_RADIUS: float = 6.0
const POD_DAMAGE: int = 50
const POD_BUILDING_DAMAGE: int = 100
const POD_THROW: float = 6.0
const COLOSSUS_OUT_AFTER: float = 1.1
const COLOSSUS_BLAST_RADIUS: float = 7.5
const COLOSSUS_BLAST_DAMAGE: int = 80
const COLOSSUS_BLAST_BUILDING_DAMAGE: int = 160

var main: Main

## Host only.
var _runs: Array = []
## Ghost Crew, host only: [{peer, pos, radius, until}] and the dead waiting to
## rise, [{scene_path, peer, pos, at, until}].
var _ghost_zones: Array = []
var _ghosts_rising: Array = []
## Host only: peer_id -> where that player's Orbital Lance is being steered.
var _steer: Dictionary = {}
## The local player's own Lance: when it stops listening to the cursor.
var _my_lance_until: float = -1.0
var _steer_send_timer: float = 0.0

## Host only, from Research.cast_as.
func start(peer_id: int, node: ResearchNode, pos: Vector3, end: Vector3) -> void:
	var run := {"kind": node.set_piece, "peer": peer_id, "node": node, "pos": pos, "end": end,
			"t": 0.0, "step": 0, "timer": 0.0, "hit": {}}
	var dir := end - pos
	dir.y = 0.0
	run["dir"] = dir.normalized() if dir.length_squared() > 0.0001 else Vector3.FORWARD
	run["length"] = dir.length()
	if node.telegraph > 0.0:
		if node.aim == ResearchNode.Aim.LINE:
			_fx(&"telegraph_line", {"pos": pos, "end": end, "width": _telegraph_width(node), "color": node.effect_color,
					"seconds": node.telegraph})
		else:
			_fx(&"telegraph_circle", {"pos": pos, "radius": node.radius, "color": node.effect_color, "seconds": node.telegraph})
	if has_method("_start_" + String(node.set_piece)):
		call("_start_" + String(node.set_piece), run)
	_runs.append(run)

func _telegraph_width(node: ResearchNode) -> float:
	if node.set_piece == &"galleon":
		return GALLEON_BROADSIDE_FAR * 2.0
	return node.line_width

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		_send_steer(delta)
		return
	_send_steer(delta)
	for i in range(_runs.size() - 1, -1, -1):
		var run: Dictionary = _runs[i]
		run["t"] += delta
		if call("_tick_" + String(run["kind"]), run, delta):
			_runs.remove_at(i)
	_tick_ghosts()

## --- Royal Volley: the sky goes dark, then arrows everywhere in the circle ---

func _tick_volley(run: Dictionary, delta: float) -> bool:
	var node: ResearchNode = run["node"]
	var t: float = run["t"] - node.telegraph
	if t < 0.0:
		return false
	if run["step"] == 0:
		run["step"] = 1
		_fx(&"volley", {"pos": run["pos"], "radius": node.radius, "seconds": VOLLEY_SECONDS})
	run["timer"] -= delta
	if run["timer"] <= 0.0:
		run["timer"] += VOLLEY_TICK
		for unit in _enemies_near(run["peer"], run["pos"], node.radius):
			_hurt(run["peer"], unit, VOLLEY_DAMAGE)
		for building in _enemy_buildings_near(run["peer"], run["pos"], node.radius):
			building.take_damage(VOLLEY_BUILDING_DAMAGE, null)
	return t >= VOLLEY_SECONDS

## --- Charge of the Old Kings: ghost knights ride the line down ---

func _tick_charge(run: Dictionary, _delta: float) -> bool:
	var node: ResearchNode = run["node"]
	var t: float = run["t"] - node.telegraph
	if t < 0.0:
		return false
	if run["step"] == 0:
		run["step"] = 1
		_fx(&"charge", {"pos": run["pos"], "end": run["end"], "width": node.line_width, "seconds": CHARGE_SECONDS})
	var front: float = minf(t / CHARGE_SECONDS, 1.0) * run["length"]
	var peer: int = run["peer"]
	var dir: Vector3 = run["dir"]
	var on_unit := func(unit: Unit, lateral: float) -> void:
		_hurt(peer, unit, CHARGE_DAMAGE)
		unit.power_knock(dir + _side(dir) * signf(lateral) * 0.6, CHARGE_THROW, CHARGE_STUN)
	var on_building := func(building: ProductionBuilding) -> void:
		building.take_damage(CHARGE_BUILDING_DAMAGE, null)
	_sweep_line(run, -1.0, front + 1.5, node.line_width * 0.5, on_unit, on_building)
	return t >= CHARGE_SECONDS

## --- The Sword of Aldmere: a giant sword falls, and stays as a beacon ---

func _tick_sword(run: Dictionary, delta: float) -> bool:
	var node: ResearchNode = run["node"]
	var t: float = run["t"] - node.telegraph
	if t < 0.0:
		return false
	if run["step"] == 0:
		run["step"] = 1
		_fx(&"sword", {"pos": run["pos"], "fall": SWORD_FALL, "seconds": SWORD_STAYS, "aura": SWORD_AURA_RADIUS})
	if t < SWORD_FALL:
		return false
	if run["step"] == 1:
		run["step"] = 2
		_blast(run["peer"], run["pos"], node.radius, SWORD_DAMAGE, SWORD_BUILDING_DAMAGE, SWORD_THROW, SWORD_STUN)
	run["timer"] -= delta
	if run["timer"] <= 0.0:
		run["timer"] += SWORD_AURA_TICK
		var blessed: Array = []
		for unit in _friends_near(run["peer"], run["pos"], SWORD_AURA_RADIUS):
			for buff in node.buffs:
				unit.buffs.add(buff, float(node.buffs[buff]), SWORD_AURA_TICK * 1.5)
			unit.heal(SWORD_AURA_HEAL)
			blessed.append(unit)
		if not blessed.is_empty():
			main.feedback.relay_buff_tints(blessed, SWORD_GOLD, SWORD_AURA_TICK * 1.5)
	return t >= SWORD_FALL + SWORD_STAYS

## --- Cursed Treasure: a chest no one can resist, then it goes up ---

func _tick_treasure(run: Dictionary, delta: float) -> bool:
	var pos: Vector3 = run["pos"]
	if run["step"] == 0:
		run["step"] = 1
		_fx(&"treasure", {"pos": pos, "seconds": TREASURE_LURE_SECONDS, "radius": TREASURE_LURE_RADIUS})
	if run["t"] < TREASURE_LURE_SECONDS:
		run["timer"] -= delta
		if run["timer"] <= 0.0:
			run["timer"] += TREASURE_LURE_TICK
			for unit in _enemies_near(run["peer"], pos, TREASURE_LURE_RADIUS):
				run["hit"][unit] = true
				if _flat(unit.global_position, pos) > 1.8:
					var jitter := Vector3(randf_range(-1.5, 1.5), 0.0, randf_range(-1.5, 1.5))
					unit.command_move(pos + jitter)
		return false
	_fx(&"treasure_blast", {"pos": pos, "radius": TREASURE_BLAST_RADIUS})
	_blast(run["peer"], pos, TREASURE_BLAST_RADIUS, TREASURE_DAMAGE, TREASURE_BUILDING_DAMAGE, TREASURE_THROW, TREASURE_STUN)
	## Whoever was dragged in and lived shakes it off where they stand.
	for unit in run["hit"]:
		if is_instance_valid(unit) and unit.status_activity != Unit.Activity.DEAD:
			unit.command_stop()
	return true

## --- Ghost Crew: your fallen in the circle come back to finish the fight ---

func _start_ghost_crew(run: Dictionary) -> void:
	var node: ResearchNode = run["node"]
	_ghost_zones.append({"peer": run["peer"], "pos": run["pos"], "radius": node.radius,
			"until": Research.now() + node.duration})
	_fx(&"ghost_zone", {"pos": run["pos"], "radius": node.radius, "seconds": node.duration})

func _tick_ghost_crew(_run: Dictionary, _delta: float) -> bool:
	return true

## Host only, from Unit._die.
func on_unit_died(unit: Unit) -> void:
	if unit.summoned or unit.can_gather or not unit.can_fight or unit.scene_file_path.is_empty():
		return
	var now := Research.now()
	for zone in _ghost_zones:
		if zone["peer"] == unit.owner_peer_id and now < zone["until"] \
				and _flat(unit.global_position, zone["pos"]) <= zone["radius"]:
			_ghosts_rising.append({"scene_path": unit.scene_file_path, "peer": unit.owner_peer_id,
					"pos": unit.global_position, "at": now + GHOST_RISE_DELAY, "until": zone["until"]})
			return

func _tick_ghosts() -> void:
	var now := Research.now()
	for i in range(_ghost_zones.size() - 1, -1, -1):
		if now >= _ghost_zones[i]["until"]:
			_ghost_zones.remove_at(i)
	for i in range(_ghosts_rising.size() - 1, -1, -1):
		var ghost: Dictionary = _ghosts_rising[i]
		if now < ghost["at"]:
			continue
		_ghosts_rising.remove_at(i)
		if not main.is_peer_active(ghost["peer"]) or now >= ghost["until"]:
			continue
		var unit: Unit = main.unit_spawner.spawn({
			"scene_path": ghost["scene_path"],
			"peer_id": ghost["peer"],
			"tint": main.get_team_tint(ghost["peer"]),
			"position": ghost["pos"],
		})
		unit.summoned = true
		main.research.track_summon(unit, ghost["until"])
		var seconds: float = ghost["until"] - now
		## After the spawner has made it on every peer.
		get_tree().create_timer(0.4).timeout.connect(func() -> void:
			if is_instance_valid(unit) and unit.is_inside_tree():
				_fx(&"ghost_rise", {"path": unit.get_path(), "seconds": seconds - 0.4}))

## --- The Dread Galleon: a ship on a wave, broadsides either side ---

func _galleon_seconds(run: Dictionary) -> float:
	return (run["length"] + GALLEON_RUN_IN * 2.0) / GALLEON_SPEED

func _tick_galleon(run: Dictionary, delta: float) -> bool:
	var node: ResearchNode = run["node"]
	var t: float = run["t"] - node.telegraph
	if t < 0.0:
		return false
	if run["step"] == 0:
		run["step"] = 1
		run["balls"] = []
		_fx(&"galleon", {"pos": run["pos"], "end": run["end"], "run_in": GALLEON_RUN_IN, "speed": GALLEON_SPEED,
				"tint": main.get_team_tint(run["peer"])})
	var dir: Vector3 = run["dir"]
	var side := _side(dir)
	var centre_along: float = -GALLEON_RUN_IN + t * GALLEON_SPEED
	var centre: Vector3 = run["pos"] + dir * centre_along
	## The bow wave throws aside whatever is in the ship's way.
	var peer: int = run["peer"]
	var on_unit := func(unit: Unit, lateral: float) -> void:
		_hurt(peer, unit, GALLEON_BOW_DAMAGE)
		unit.power_knock(dir * 0.5 + side * (1.0 if lateral >= 0.0 else -1.0), GALLEON_BOW_THROW, GALLEON_BOW_STUN)
	var on_building := func(building: ProductionBuilding) -> void:
		building.take_damage(GALLEON_BOW_BUILDING_DAMAGE, null)
	_sweep_line(run, -GALLEON_RUN_IN, centre_along + GALLEON_BOW_AHEAD, GALLEON_HULL_HALF, on_unit, on_building)
	## Broadsides while it is over the line.
	run["timer"] -= delta
	if run["timer"] <= 0.0 and centre_along >= 0.0 and centre_along <= run["length"]:
		run["timer"] += GALLEON_VOLLEY_TICK
		var from: Array = []
		var to: Array = []
		for s in [-1.0, 1.0]:
			for i in GALLEON_BALLS_PER_SIDE:
				var muzzle: Vector3 = centre + dir * randf_range(-4.0, 4.0) + side * s * 2.2
				var landing: Vector3 = centre + dir * randf_range(-3.0, 6.0) \
						+ side * s * randf_range(GALLEON_BROADSIDE_NEAR, GALLEON_BROADSIDE_FAR)
				landing = ground_point(landing)
				from.append(muzzle)
				to.append(landing)
				run["balls"].append([t + GALLEON_BALL_FLIGHT, landing])
		_fx(&"cannon_volley", {"from": from, "to": to, "flight": GALLEON_BALL_FLIGHT})
	for i in range(run["balls"].size() - 1, -1, -1):
		var ball: Array = run["balls"][i]
		if t >= ball[0]:
			run["balls"].remove_at(i)
			_blast(run["peer"], ball[1], GALLEON_BALL_RADIUS, GALLEON_BALL_DAMAGE, GALLEON_BALL_BUILDING_DAMAGE, 2.5, 0.3)
	return t >= _galleon_seconds(run) and run["balls"].is_empty()

## --- Overclock: red-hot robots, then they seize up ---

func _tick_overclock(run: Dictionary, _delta: float) -> bool:
	var node: ResearchNode = run["node"]
	if run["step"] == 0:
		run["step"] = 1
		var units := _friends_near(run["peer"], run["pos"], node.radius)
		run["units"] = units
		var paths: Array = []
		for unit in units:
			for buff in node.buffs:
				unit.buffs.add(buff, float(node.buffs[buff]), OVERCLOCK_SECONDS)
			paths.append(unit.get_path())
		main.feedback.relay_buff_tints(units, OVERCLOCK_COLOR, OVERCLOCK_SECONDS, OVERCLOCK_TINT_STRENGTH)
		_fx(&"overclock", {"pos": run["pos"], "radius": node.radius, "paths": paths, "seconds": OVERCLOCK_SECONDS})
		return false
	if run["t"] < OVERCLOCK_SECONDS:
		return false
	var paths: Array = []
	for unit in run["units"]:
		if is_instance_valid(unit) and unit.status_activity != Unit.Activity.DEAD:
			unit.power_knock(Vector3.ZERO, 0.0, OVERCLOCK_SEIZE)
			paths.append(unit.get_path())
	_fx(&"overclock_seize", {"paths": paths, "seconds": OVERCLOCK_SEIZE})
	return true

## --- Orbital Lance: a beam from orbit that follows the caster's cursor ---

func _start_lance(run: Dictionary) -> void:
	run["beam"] = run["pos"]
	_steer[run["peer"]] = run["pos"]

func _tick_lance(run: Dictionary, delta: float) -> bool:
	var node: ResearchNode = run["node"]
	var t: float = run["t"] - node.telegraph
	if t < 0.0:
		return false
	if run["step"] == 0:
		run["step"] = 1
		run["sync"] = 0.0
		_fx(&"lance", {"pos": run["beam"], "seconds": LANCE_SECONDS, "peer": run["peer"], "radius": LANCE_RADIUS})
	var beam: Vector3 = run["beam"]
	var aim: Vector3 = _steer.get(run["peer"], beam)
	var to := aim - beam
	to.y = 0.0
	var step := LANCE_SPEED * delta
	beam = beam + to.normalized() * step if to.length() > step else Vector3(aim.x, beam.y, aim.z)
	beam = ground_point(beam)
	run["beam"] = beam
	run["sync"] -= delta
	if run["sync"] <= 0.0:
		run["sync"] += LANCE_SYNC
		main.power_fx.relay_lance_position(run["peer"], beam)
	run["timer"] -= delta
	if run["timer"] <= 0.0:
		run["timer"] += LANCE_TICK
		for unit in _enemies_near(run["peer"], beam, LANCE_RADIUS):
			_hurt(run["peer"], unit, LANCE_DAMAGE)
		for building in _enemy_buildings_near(run["peer"], beam, LANCE_RADIUS):
			building.take_damage(LANCE_BUILDING_DAMAGE, null)
	if t >= LANCE_SECONDS:
		_steer.erase(run["peer"])
		_fx(&"lance_end", {"peer": run["peer"]})
		return true
	return false

## Host: where `peer_id`'s Lance should head (an AI's own pick, or a player's
## cursor relayed from their machine).
func set_steer(peer_id: int, pos: Vector3) -> void:
	if _steer.has(peer_id):
		_steer[peer_id] = pos

## Is anything of `peer_id`'s being steered right now (AiResearch asks).
func is_steering(peer_id: int) -> bool:
	return _steer.has(peer_id)

## Every peer, from PowerFx when its own Lance comes down.
func listen_for_steer(seconds: float) -> void:
	_my_lance_until = Research.now() + seconds

func _send_steer(delta: float) -> void:
	if Research.now() >= _my_lance_until:
		return
	_steer_send_timer -= delta
	if _steer_send_timer > 0.0:
		return
	_steer_send_timer = LANCE_SYNC
	var hit := main.raycast(get_viewport().get_mouse_position())
	if hit.is_empty():
		return
	if multiplayer.is_server():
		set_steer(main.my_peer_id(), hit.position)
	else:
		_rpc_steer.rpc_id(1, hit.position)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_steer(pos: Vector3) -> void:
	if multiplayer.is_server():
		set_steer(multiplayer.get_remote_sender_id(), pos)

## --- Colossus Drop: a pod from orbit, a war mech out of it ---

func _tick_colossus(run: Dictionary, _delta: float) -> bool:
	var node: ResearchNode = run["node"]
	var t: float = run["t"] - node.telegraph
	if t < 0.0:
		return false
	var pos: Vector3 = run["pos"]
	match run["step"]:
		0:
			run["step"] = 1
			_fx(&"pod", {"pos": pos, "fall": POD_FALL, "tint": main.get_team_tint(run["peer"])})
		1:
			if t >= POD_FALL:
				run["step"] = 2
				_blast(run["peer"], pos, POD_RADIUS, POD_DAMAGE, POD_BUILDING_DAMAGE, POD_THROW, 1.0)
		2:
			if t >= POD_FALL + COLOSSUS_OUT_AFTER:
				run["step"] = 3
				if node.summon_scene == null or not main.is_peer_active(run["peer"]):
					return true
				var unit: Unit = main.unit_spawner.spawn({
					"scene_path": node.summon_scene.resource_path,
					"peer_id": run["peer"],
					"tint": main.get_team_tint(run["peer"]),
					"position": pos,
				})
				unit.summoned = true
				run["unit"] = unit
				run["until"] = run["t"] + node.duration
		3:
			var unit = run["unit"]
			if not is_instance_valid(unit) or unit.status_activity == Unit.Activity.DEAD:
				return true
			if run["t"] >= run["until"]:
				var at: Vector3 = unit.global_position
				_fx(&"colossus_blast", {"pos": at, "radius": COLOSSUS_BLAST_RADIUS})
				_blast(run["peer"], at, COLOSSUS_BLAST_RADIUS, COLOSSUS_BLAST_DAMAGE, COLOSSUS_BLAST_BUILDING_DAMAGE, 7.0, 1.5)
				unit.expire()
				return true
	return false

## --- Shared ---

## Everything hostile within `radius` of `pos` takes `damage` and is thrown
## outward; hostile buildings take `building_damage`.
func _blast(peer_id: int, pos: Vector3, radius: float, damage: int, building_damage: int, throw: float, stun: float) -> void:
	for unit in _enemies_near(peer_id, pos, radius):
		_hurt(peer_id, unit, damage)
		var away := unit.global_position - pos
		unit.power_knock(away if away.length_squared() > 0.01 else Vector3(randf() - 0.5, 0.0, randf() - 0.5), throw, stun)
	for building in _enemy_buildings_near(peer_id, pos, radius):
		building.take_damage(building_damage, null)

## Every hostile unit and building the run's line has reached by `front`
## (metres along it from its start, counting from `behind`) within
## `half_width` of it, once each: on_unit(unit, signed lateral offset),
## on_building(building).
func _sweep_line(run: Dictionary, behind: float, front: float, half_width: float, on_unit: Callable, on_building: Callable) -> void:
	var start: Vector3 = run["pos"]
	var dir: Vector3 = run["dir"]
	var side := _side(dir)
	var hit: Dictionary = run["hit"]
	for child in get_tree().get_nodes_in_group(&"units"):
		var unit := child as Unit
		if unit == null or hit.has(unit) or unit.status_activity == Unit.Activity.DEAD \
				or not Teams.is_enemy(run["peer"], unit.owner_peer_id):
			continue
		var d := unit.global_position - start
		var along := d.dot(dir)
		var lateral := d.dot(side)
		if along < behind or along > front or absf(lateral) > half_width + unit.get_body_bulk():
			continue
		hit[unit] = true
		on_unit.call(unit, lateral)
	for child in main.buildings_root.get_children():
		var building := child as ProductionBuilding
		if building == null or hit.has(building) or building.is_destroyed or not Teams.is_enemy(run["peer"], building.owner_peer_id):
			continue
		var d := building.global_position - start
		var along := d.dot(dir)
		if along < behind or along > front or absf(d.dot(side)) > half_width + building.get_footprint_radius():
			continue
		hit[building] = true
		on_building.call(building)

static func _side(dir: Vector3) -> Vector3:
	return Vector3(-dir.z, 0.0, dir.x)

static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _hurt(peer_id: int, unit: Unit, amount: int) -> void:
	unit.power_credit_peer = peer_id
	unit.power_credit_time = Research.now()
	unit.take_damage(amount, null, false)

func _enemies_near(peer_id: int, pos: Vector3, radius: float) -> Array[Unit]:
	var out: Array[Unit] = []
	for child in get_tree().get_nodes_in_group(&"units"):
		var unit := child as Unit
		if unit == null or unit.status_activity == Unit.Activity.DEAD or not Teams.is_enemy(peer_id, unit.owner_peer_id):
			continue
		if _flat(unit.global_position, pos) <= radius + unit.get_body_bulk():
			out.append(unit)
	return out

## Your own units and your allies' (never neutral ones).
func _friends_near(peer_id: int, pos: Vector3, radius: float) -> Array[Unit]:
	var out: Array[Unit] = []
	for child in get_tree().get_nodes_in_group(&"units"):
		var unit := child as Unit
		if unit == null or unit.status_activity == Unit.Activity.DEAD or Teams.is_enemy(peer_id, unit.owner_peer_id):
			continue
		if _flat(unit.global_position, pos) <= radius + unit.get_body_bulk():
			out.append(unit)
	return out

func _enemy_buildings_near(peer_id: int, pos: Vector3, radius: float) -> Array[ProductionBuilding]:
	var out: Array[ProductionBuilding] = []
	for child in main.buildings_root.get_children():
		var building := child as ProductionBuilding
		if building == null or building.is_destroyed or not Teams.is_enemy(peer_id, building.owner_peer_id):
			continue
		if _flat(building.global_position, pos) <= radius + building.get_footprint_radius():
			out.append(building)
	return out

## The terrain under `pos` (buildings and resources don't count), or `pos`
## itself off the map.
func ground_point(pos: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(Vector3(pos.x, 200.0, pos.z), Vector3(pos.x, -100.0, pos.z), 1)
	var hit := main.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.collider is ProductionBuilding or hit.collider is Gatherable:
		return pos
	return hit.position

func _fx(kind: StringName, data: Dictionary) -> void:
	main.power_fx.relay(kind, data)
