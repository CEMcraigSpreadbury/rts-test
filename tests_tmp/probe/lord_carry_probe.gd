extends Node
## Throwaway: m1 with a Lord, then the Next-mission scene change to m2; how
## many Lords are there once m2 has settled?
var _t := 0
func _ready() -> void:
	if get_parent() != get_tree().root or get_tree().current_scene == self:
		## The scene root: hand off to a copy parked on the root, which the
		## scene changes below don't free.
		var watcher: Node = load("res://tests_tmp/probe/lord_carry_probe.gd").new()
		watcher.name = "Watcher"
		get_tree().root.add_child.call_deferred(watcher)
		set_physics_process(false)
		return
	Network.start_offline()
	SceneLoader.change_scene("res://scenes/scenarios/m1_a_holding_in_the_march.tscn")
func _physics_process(_d: float) -> void:
	_t += 1
	var main := get_tree().current_scene as Main
	if _t == 30 * 8 and main != null:
		var lord: Unit = main.unit_spawner.spawn({"scene_path": "res://scenes/units/lord_unit.tscn", "peer_id": 1,
			"tint": main.get_team_tint(1), "position": (main.player_spawn_points.get_child(0) as Node3D).global_position + Vector3(5, 0, 5)})
		print("M1 lords: ", _lords())
	if _t == 30 * 12:
		Network.current_scenario_id = "m2"
		SceneLoader.change_scene("res://scenes/scenarios/m2_smoke_over_the_vale.tscn")
	if _t > 30 * 14 and _t % 60 == 0:
		var tc := Vector3.INF
		for b in get_tree().get_nodes_in_group(&"buildings"):
			if b is ProductionBuilding and b.is_main_base and b.owner_peer_id == 1:
				tc = b.global_position.round()
		print("t=", _t / 30, " tc ", tc, " lords: ", _lords())
	if _t == 30 * 34:
		get_tree().quit()
func _lords() -> Array:
	var out := []
	for u in get_tree().get_nodes_in_group(&"units"):
		if u is Unit and u.is_lord:
			out.append("%s at %s %s/%s" % [u.display_name, u.global_position.round(), Unit.Command.keys()[u.status_command], Unit.Activity.keys()[u.status_activity]])
	return out
