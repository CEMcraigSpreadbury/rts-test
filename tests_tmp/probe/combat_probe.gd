extends Node
## Throwaway: reproduces "attack-move onto ground near enemies doesn't fight"
## and "enemies don't react when you get close". Args: -- --case=A|B --map=N

const SOLDIER := "res://scenes/units/soldier_unit.tscn"
const PER_SIDE := 12
var case_name := "A"
var map_index := 1
var _main: Main
var _ai := 0
var _tick := 0
var _mine: Array[Unit] = []
var _theirs: Array[Unit] = []
var _a := Vector3.ZERO
var _b := Vector3.ZERO
var _fwd := Vector3.FORWARD

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="): case_name = arg.get_slice("=", 1)
		if arg.begins_with("--map="): map_index = int(arg.get_slice("=", 1))
	seed(7)
	var info: MapInfo = MapInfo.list_all()[map_index]
	Network.start_offline()
	Network.map_index = map_index
	Network.set_match_settings(Network.GameMode.ANNIHILATION, 0)
	_ai = Network.add_ai_player(Network.AiDifficulty.NORMAL)
	_start.call_deferred(load(info.scene_path))

func _start(scene: PackedScene) -> void:
	var m: Node = scene.instantiate()
	get_tree().root.add_child(m)
	get_tree().current_scene = m
	_main = m as Main

func _spawn(peer: int, centre: Vector3, facing: Vector3) -> Array[Unit]:
	var right := Vector3(facing.z, 0, -facing.x)
	var out: Array[Unit] = []
	for i in PER_SIDE:
		var u: Unit = _main.unit_spawner.spawn({"scene_path": SOLDIER, "peer_id": peer,
			"tint": _main.get_team_tint(peer), "position": centre + right * ((i % 6) - 2.5) * 1.6 - facing * (i / 6) * 1.6})
		Population.reserve(peer, u.population_cost)
		out.append(u)
	return out

func _paths(units: Array[Unit]) -> Array[NodePath]:
	var p: Array[NodePath] = []
	for u in units:
		if is_instance_valid(u) and u.status_activity != Unit.Activity.DEAD:
			p.append(u.get_path())
	return p

func _centroid(units: Array[Unit]) -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for u in units:
		if is_instance_valid(u) and u.status_activity != Unit.Activity.DEAD:
			c += u.global_position
			n += 1
	return c / maxf(n, 1)

func _physics_process(_d: float) -> void:
	if _main == null:
		return
	_tick += 1
	if case_name == "V":
		_cast_tick()
		return
	if case_name == "R":
		_archer_tick()
		return
	if case_name == "H":
		_hunt_tick()
		return
	if _tick == 90:
		## Silence the AI so it never orders the probe's units.
		for n in get_tree().root.find_children("*", "", true, false):
			if n is AiPlayer:
				n.process_mode = Node.PROCESS_MODE_DISABLED
		var s: Node3D = _main.player_spawn_points
		var p0: Vector3 = (s.get_child(0) as Node3D).global_position
		var p1: Vector3 = (s.get_child(1) as Node3D).global_position
		var mid := (p0 + p1) * 0.5
		_fwd = (p1 - p0); _fwd.y = 0; _fwd = _fwd.normalized()
		_a = mid - _fwd * 15.0
		_b = mid + _fwd * 6.0
		if case_name in ["C", "D", "E"]:
			## Nearest settlement's guards instead of a spawned enemy.
			var best: Unit = null
			for u in get_tree().get_nodes_in_group(&"units"):
				if u is Unit and u.owner_peer_id == 0 and u.leash_origin is Objective and u.can_fight:
					if best == null or u.global_position.distance_to(p0) < best.global_position.distance_to(p0):
						best = u
			for u in get_tree().get_nodes_in_group(&"units"):
				if u is Unit and u.owner_peer_id == 0 and u.leash_radius > 0.0 and u.leash_origin == best.leash_origin:
					_theirs.append(u)
			var gc := _centroid(_theirs)
			_fwd = (gc - p0); _fwd.y = 0; _fwd = _fwd.normalized()
			_a = gc - _fwd * 22.0
			print("GUARDS ", _theirs.size(), " leash ", best.leash_radius, " aggro ", best.aggro_range, " origin ", best.leash_origin.name)
			_mine = _spawn(1, _a, _fwd)
		else:
			_mine = _spawn(1, _a, _fwd)
			_theirs = _spawn(_ai, _b, -_fwd)
		_main.fog_of_war.reveal_all = true
	if _tick == 150:
		## Both sides formed into blocks where they stand, as an army would be.
		_main.issue_command_as(1, _paths(_mine), NodePath(), _a + _fwd * 1.0, false, false)
		if case_name in ["A", "B"]:
			_main.issue_command_as(_ai, _paths(_theirs), NodePath(), _b - _fwd * 1.0, false, false)
	if _tick == 400:
		var near := _centroid(_theirs) - _fwd * 4.0
		if case_name == "E":
			var side := Vector3(_fwd.z, 0, -_fwd.x)
			print("ORDER attack-move to ground 5 m beside the guards")
			_main.issue_command_as(1, _paths(_mine), NodePath(), _centroid(_theirs) + side * 5.0, true, false)
		elif case_name in ["A", "C"]:
			print("ORDER attack-move to ground 4 m in front of the enemy block")
			_main.issue_command_as(1, _paths(_mine), NodePath(), near, true, false)
		else:
			print("ORDER plain move to 3 m in front of the enemy block")
			_main.issue_command_as(1, _paths(_mine), NodePath(), _centroid(_theirs) - _fwd * 3.0, false, false)
	if _tick >= 400 and _tick % 60 == 0:
		print("t=%2d  mine: %s   theirs: %s" % [(_tick - 400) / 60, _summary(_mine), _summary(_theirs)])
	if _tick >= 400 + 60 * 25:
		get_tree().quit()

func _summary(units: Array[Unit]) -> String:
	var hp := 0.0
	var alive := 0
	var states := {}
	for u in units:
		if not is_instance_valid(u) or u.status_activity == Unit.Activity.DEAD:
			continue
		alive += 1
		hp += u.status_current_health
		var key: String = "%s/%s%s" % [Unit.Command.keys()[u.status_command], Unit.Activity.keys()[u.status_activity], "*" if u.attack_target != null else ""]
		states[key] = states.get(key, 0) + 1
	var near := INF
	for m in _mine:
		if not is_instance_valid(m) or m.status_activity == Unit.Activity.DEAD: continue
		for t in _theirs:
			if not is_instance_valid(t) or t.status_activity == Unit.Activity.DEAD: continue
			near = minf(near, m.global_position.distance_to(t.global_position))
	var extra := ""
	if units == _mine and not units.is_empty() and is_instance_valid(units[0]):
		var u0: Unit = units[0]
		extra = " u0[follow=%s assault=%s idleblock=%s aggro=%.0f]" % [u0.sim_follow, u0.assault_active, u0.in_idle_block(), u0.aggro_range]
	return "alive %d hp %d %s closest %.1f%s" % [alive, hp, states, near, extra]

var _cast_done := {}
var _deer: Unit = null
var _hunters: Array[Unit] = []
func _hunt_tick() -> void:
	if _tick == 90:
		for n in get_tree().root.find_children("*", "", true, false):
			if n is AiPlayer:
				n.process_mode = Node.PROCESS_MODE_DISABLED
		var p0: Vector3 = (_main.player_spawn_points.get_child(0) as Node3D).global_position
		for u in get_tree().get_nodes_in_group(&"units"):
			if u is Unit and u.hunt_meat > 0 and not u.can_fight and u.display_name == "Deer" and _safe(u) 					and (_deer == null or u.global_position.distance_to(p0) < _deer.global_position.distance_to(p0)):
				_deer = u
		print("DEER ", _deer.display_name, " hp ", _deer.status_current_health, " meat ", _deer.hunt_meat)
		for i in 2:
			var v: Unit = _main.unit_spawner.spawn({"scene_path": "res://scenes/units/unit.tscn", "peer_id": 1,
				"tint": _main.get_team_tint(1), "position": _deer.global_position + Vector3(4 + i, 0, 3)})
			_hunters.append(v)
		_main.fog_of_war.reveal_all = true
	if _tick == 150:
		_main.issue_command_as(1, _paths(_hunters), _deer.get_path(), _deer.global_position, false, false)
	if _tick >= 150 and _tick % 120 == 0:
		var carcasses := get_tree().get_nodes_in_group(&"carcasses")
		var c := ""
		for k in carcasses:
			c += "%s(%d food, %d gatherers, shown %s) " % [k.name, k.amount_remaining, k.gatherers.size(), k._figure.visible if k._figure else false]
		var hs := ""
		for h in _hunters:
			if not is_instance_valid(h):
				hs += "gone; "
				continue
			hs += "%s/%s carry %d; " % [Unit.Command.keys()[h.status_command], Unit.Activity.keys()[h.status_activity], h.status_carried_amount]
		print("t=%2d deer %s | carcasses %s| hunters %s| food %d" % [(_tick - 150) / 60,
			str(_deer.status_current_health) if is_instance_valid(_deer) else "gone", c, hs, ResourceStockpile.get_amount(1, Carcass.FOOD)])
	if _tick >= 150 + 60 * 60:
		get_tree().quit()

func _safe(deer: Unit) -> bool:
	for o in get_tree().get_nodes_in_group(&"objectives"):
		if (o as Node3D).global_position.distance_to(deer.global_position) < 35.0:
			return false
	for u in get_tree().get_nodes_in_group(&"units"):
		if u is Unit and u.can_fight and u.owner_peer_id == 0 and u.global_position.distance_to(deer.global_position) < 25.0:
			return false
	return true

func _archer_tick() -> void:
	if _tick == 90:
		for n in get_tree().root.find_children("*", "", true, false):
			if n is AiPlayer:
				n.process_mode = Node.PROCESS_MODE_DISABLED
		var s: Node3D = _main.player_spawn_points
		var p0: Vector3 = (s.get_child(0) as Node3D).global_position
		var p1: Vector3 = (s.get_child(1) as Node3D).global_position
		var mid := (p0 + p1) * 0.5
		_fwd = (p1 - p0); _fwd.y = 0; _fwd = _fwd.normalized()
		_a = mid - _fwd * 6.0
		_b = mid + _fwd * 6.0
		for i in PER_SIDE:
			var right := Vector3(_fwd.z, 0, -_fwd.x)
			var u: Unit = _main.unit_spawner.spawn({"scene_path": "res://scenes/units/archer_unit.tscn", "peer_id": 1,
				"tint": _main.get_team_tint(1), "position": _a + right * ((i % 6) - 2.5) * 1.6 - _fwd * (i / 6) * 1.6})
			_mine.append(u)
		_theirs = _spawn(_ai, _b, -_fwd)
		_main.fog_of_war.reveal_all = true
	if _tick == 150:
		_main.issue_command_as(1, _paths(_mine), NodePath(), _a + _fwd * 0.5, false, false)
		_main.issue_command_as(_ai, _paths(_theirs), NodePath(), _b, false, false)
		## Hold the enemy still so only the archers' choice is measured.
	if _tick == 330:
		var target: Unit = _theirs[0]
		print("ORDER archers attack ", target.name)
		_main.issue_command_as(1, _paths(_mine), target.get_path(), target.global_position, false, false)
	if _tick > 330 and _tick % 30 == 0 and _tick < 330 + 30 * 8:
		var picks := {}
		for m in _mine:
			if not is_instance_valid(m): continue
			var t = m.sim_target if is_instance_valid(m.sim_target) else m.attack_target
			if is_instance_valid(t):
				picks[t.name] = picks.get(t.name, 0) + 1
		print("t=%d distinct targets %d %s" % [(_tick - 330) / 30, picks.size(), picks.values()])
	if _tick >= 330 + 30 * 8:
		get_tree().quit()

func _cast_tick() -> void:
	if _tick == 90:
		for n in get_tree().root.find_children("*", "", true, false):
			if n is AiPlayer:
				n.process_mode = Node.PROCESS_MODE_DISABLED
		var s: Node3D = _main.player_spawn_points
		var p0: Vector3 = (s.get_child(0) as Node3D).global_position
		var p1: Vector3 = (s.get_child(1) as Node3D).global_position
		var mid := (p0 + p1) * 0.5
		_fwd = (p1 - p0); _fwd.y = 0; _fwd = _fwd.normalized()
		for res in [Carcass.FOOD, AiPlayer.GOLD, AiPlayer.WOOD, Research.RESOURCE, load("res://resources/favour_resource_type.tres")]:
			ResourceStockpile.add(1, res, 5000)
		for path in ["res://scenes/units/monsters/black_dragon_unit.tscn", "res://scenes/units/monsters/hydra_unit.tscn",
				"res://scenes/units/monsters/giant_bear_unit.tscn", "res://scenes/units/monsters/yeti_unit.tscn",
				"res://scenes/units/monsters/dark_lord_unit.tscn", "res://scenes/units/monsters/phoenix_unit.tscn",
				"res://scenes/units/beasts/dragon_unit.tscn", "res://scenes/units/beasts/lightning_dragon_unit.tscn",
				"res://scenes/units/beasts/wind_tiger_unit.tscn", "res://scenes/units/beasts/skeleton_dragon_unit.tscn"]:
			_mine.append(_main.unit_spawner.spawn({"scene_path": path, "peer_id": 1, "tint": _main.get_team_tint(1), "position": mid - _fwd * 6.0}))
		_theirs = _spawn(_ai, mid + _fwd * 2.0, -_fwd)
		_main.fog_of_war.reveal_all = true
	if _tick >= 150 and _tick % 30 == 0:
		for m in _mine:
			if not is_instance_valid(m) or _cast_done.has(m.display_name):
				continue
			var spawned: Array = []
			for t in _theirs:
				if is_instance_valid(t) and t.status_activity != Unit.Activity.DEAD:
					spawned.append(t)
			if spawned.is_empty():
				_theirs = _spawn(_ai, m.global_position + _fwd * 6.0, -_fwd)
			if _main.request_ability_as(1, m.get_path(), 0, _centroid(_theirs)):
				_cast_done[m.display_name] = true
				print("CAST ", m.display_name, " ", m.get_ability(0).ability_name, " style ", m.get_ability(0).effect_style, " at t=", (_tick - 150) / 30)
	if _tick == 150 + 30 * 30:
		print("CAST DONE ", _cast_done.size(), " of ", _mine.size())
		get_tree().quit()
