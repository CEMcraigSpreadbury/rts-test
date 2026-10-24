extends Node
## Throwaway: fires every faction power at a fresh block of 16 enemy Soldiers
## (with 6 of the caster's own Soldiers beside it, for vision and for the
## friendly powers) and reports what it did.

const SOLDIER := "res://scenes/units/soldier_unit.tscn"
var _main: Main
var _tick := 0
var _queue: Array = []
var _current: Dictionary = {}

func _ready() -> void:
	Engine.time_scale = 2.0
	var info: MapInfo = MapInfo.list_all()[1]
	Network.start_offline()
	Network.map_index = 1
	Network.set_match_settings(Network.GameMode.REALM, 0)
	Network.set_my_race(0)
	for race in [1, 2]:
		var id := Network.add_ai_player(Network.AiDifficulty.NORMAL)
		Network.set_ai_race(id, race)
	Network.resolve_random_races()
	(func():
		var m: Node = load(info.scene_path).instantiate()
		get_tree().root.add_child(m)
		get_tree().current_scene = m
		_main = m as Main).call_deferred()

func _physics_process(_d: float) -> void:
	if _main == null:
		return
	_tick += 1
	if _tick == 30 * 8:
		var peers := Network.players.keys()
		for peer in peers:
			Research.earn(peer, 300, &"probe")
			for i in 3:
				_main.research.buy_as(peer, i)
			for i in 3:
				_queue.append([peer, i])
	if _tick > 30 * 8 and (_current.is_empty() or _tick >= _current["until"]):
		if not _current.is_empty() and not _current.has("pending"):
			_report()
		if _queue.is_empty():
			if not _current.is_empty() or _tick > 30 * 9:
				get_tree().root.remove_child(_main)
				get_tree().quit()
			return
		_fire(_queue.pop_front())

func _fire(job: Array) -> void:
	_current = {"pending": true, "until": 1 << 30}
	var peer: int = job[0]
	var index: int = job[1]
	var node: ResearchNode = Research.powers_for(peer)[index]
	var victim: int = 2 if peer != 2 else 3
	var centre: Vector3 = _main.power_effects.ground_point(Vector3(0.0, 0.0, -60.0 + 0.0 * index))
	var enemies: Array = []
	var friends: Array = []
	for i in 16:
		enemies.append(_spawn(victim, centre + Vector3((i % 4) * 1.6 - 2.4, 0.0, (i / 4) * 1.6 - 2.4)))
	for i in 6:
		friends.append(_spawn(peer, centre + Vector3(i * 1.6 - 4.0, 0.0, 6.0)))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var target := centre
	var end := centre
	if node.aim == ResearchNode.Aim.LINE:
		target = centre - Vector3.FORWARD * node.line_length * 0.5
		end = centre + Vector3.FORWARD * node.line_length * 0.5
	if node.set_piece == &"ghost_crew" or node.set_piece == &"overclock":
		target = centre + Vector3(0.0, 0.0, 4.0)
	for u in enemies + friends:
		u.aggro_range = 0.0
		u.can_fight = node.set_piece == &"ghost_crew" and u in friends
	_main.research._power_ready_at.clear()
	var hp := _hp(enemies)
	var ok := _main.research.cast_as(peer, index, target, end)
	var seconds := 10.0
	if node.set_piece == &"colossus":
		seconds = 52.0
	elif node.set_piece == &"sword":
		seconds = 8.0
	elif node.set_piece == &"ghost_crew":
		seconds = 20.0
	## Ghost Crew needs some of the caster's men to fall in the circle.
	if node.set_piece == &"ghost_crew":
		for f in friends.slice(0, 3):
			f.take_damage(9999, null, false)
	if node.set_piece == &"overclock" or node.set_piece == &"ghost_crew":
		get_tree().create_timer(2.0).timeout.connect(func():
			var amounts := []
			for f in friends:
				amounts.append([is_instance_valid(f) and f.status_activity != Unit.Activity.DEAD, f.buffs.amount(ResearchNode.Buff.ATTACK_SPEED) if is_instance_valid(f) else -1])
			var sums := []
			for u in get_tree().get_nodes_in_group(&"units"):
				if u is Unit and u.summoned:
					sums.append([u.display_name, u.owner_peer_id])
			print("DBG ", node.node_name, " friends ", amounts, " summons ", sums, " zones ", _main.power_effects._ghost_zones.size(), " rising ", _main.power_effects._ghosts_rising.size()))
	_current = {"node": node, "peer": peer, "enemies": enemies, "friends": friends, "hp": hp, "ok": ok,
			"until": _tick + int(seconds * 30.0), "mid": _tick + 30 * 3}

func _report() -> void:
	var node: ResearchNode = _current["node"]
	var alive := 0
	for e in _current["enemies"]:
		if is_instance_valid(e) and e.status_activity != Unit.Activity.DEAD:
			alive += 1
	var extra := ""
	var buffed := 0
	for f in _current["friends"]:
		if is_instance_valid(f) and f.status_activity != Unit.Activity.DEAD and (f.buffs.amount(ResearchNode.Buff.ATTACK_SPEED) > 0.0 or f.buffs.amount(ResearchNode.Buff.DAMAGE) > 0.0):
			buffed += 1
	var summons := 0
	for u in get_tree().get_nodes_in_group(&"units"):
		if u is Unit and u.summoned and u.owner_peer_id == _current["peer"] and u.status_activity != Unit.Activity.DEAD:
			summons += 1
			extra += " " + u.display_name
	print("%-26s cast=%s enemy hp %d -> %d, alive %d/16, friends buffed now %d, summons %d%s" % [node.node_name, _current["ok"],
			_current["hp"], _hp(_current["enemies"]), alive, buffed, summons, extra])
	for e in _current["enemies"] + _current["friends"]:
		if is_instance_valid(e) and e.status_activity != Unit.Activity.DEAD:
			e.queue_free()

func _hp(units: Array) -> int:
	var total := 0
	for u in units:
		if is_instance_valid(u) and u.status_activity != Unit.Activity.DEAD:
			total += u.status_current_health
	return total

func _spawn(peer: int, at: Vector3) -> Unit:
	return _main.unit_spawner.spawn({"scene_path": SOLDIER, "peer_id": peer, "tint": _main.get_team_tint(peer),
			"position": _main.power_effects.ground_point(at)})
