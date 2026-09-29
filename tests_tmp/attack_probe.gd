extends "res://scripts/tools/benchmark.gd"
## p1 vs neutral (peer 0) block, like "cmd spawn soldier 12e". Only p1 is ordered.
var _pushes := 0
var _enemy: Array[Unit] = []
func _spawn_armies() -> void:
	var spawns: Node3D = _main.player_spawn_points
	var a: Vector3 = (spawns.get_child(0) as Node3D).global_position
	var b: Vector3 = (spawns.get_child(1) as Node3D).global_position
	var mid: Vector3 = (a + b) * 0.5
	var fwd: Vector3 = (b - a) * Vector3(1, 0, 1)
	fwd = fwd.normalized()
	_armies[1] = _spawn_army(1, mid - fwd * ARMY_SEPARATION, fwd)
	for i in units_per_side:
		var u: Unit = _main.unit_spawner.spawn({"scene_path": "res://scenes/units/soldier_unit.tscn", "peer_id": 0,
			"tint": Objective.NEUTRAL_TINT, "position": mid + fwd * ARMY_SEPARATION + Vector3(fwd.z, 0, -fwd.x) * (i - units_per_side / 2) * 1.6})
		_enemy.append(u)
func _push() -> void:
	var mine: Array[Unit] = _living(1)
	var theirs: Array[Unit] = _enemy.filter(func(u): return is_instance_valid(u) and u.status_activity != Unit.Activity.DEAD)
	if mine.is_empty() or theirs.is_empty():
		print("probe %d: mine %d theirs %d" % [_pushes, mine.size(), theirs.size()])
		_pushes += 1
		return
	var c := Vector3.ZERO
	for u in theirs:
		c += u.global_position
	c /= theirs.size()
	var m := Vector3.ZERO
	for u in mine:
		m += u.global_position
	m /= mine.size()
	var hp := 0
	for u in theirs:
		hp += u.status_current_health
	var s := ""
	for u in mine.slice(0, 2):
		s += " [cmd %d act %d as %s fol %s blk %s tgt %s]" % [u.status_command, u.status_activity, u.assault_active, u.sim_follow, u.in_idle_block(), u.attack_target]
	print("probe %d: enemy n %d hp %d gap %.1f%s" % [_pushes, theirs.size(), hp, m.distance_to(c), s])
	if _pushes == 0:
		var paths: Array[NodePath] = []
		for u in mine:
			paths.append(u.get_path())
		var args := OS.get_cmdline_user_args()
		if args.has("--targeted"):
			_main.issue_command_as(1, paths, theirs[0].get_path(), theirs[0].global_position, true, false)
		else:
			var short := 15.0 if args.has("--far") else 7.0
			_main.issue_command_as(1, paths, NodePath(), c + (m - c).normalized() * short, true, false)
	_pushes += 1
