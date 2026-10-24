extends Node
## Throwaway: two linked Robot Telepads, a few Troopers ordered onto one; where
## do they end up, and what state are they in on the way.

var _main: Main
var _tick := 0
var _pads: Array = []
var _units: Array = []

func _ready() -> void:
	var info: MapInfo = MapInfo.list_all()[1]
	Network.start_offline()
	Network.map_index = 1
	Network.set_match_settings(Network.GameMode.REALM, 0)
	Network.set_my_race(2)
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
	var tc: Node3D = _main.town_centers.get(1)
	if tc == null:
		return
	var base: Vector3 = tc.global_position
	if _tick == 60:
		for off in [Vector3(14, 0, 0), Vector3(-14, 0, 30)]:
			_pads.append(_main.building_spawner.spawn({"scene_path": "res://scenes/buildings/robots/robot_telepad_building.tscn",
					"peer_id": 1, "position": _main.power_effects.ground_point(base + off), "tint": Color.BLUE}))
		for i in 4:
			_units.append(_main.unit_spawner.spawn({"scene_path": "res://scenes/units/robots/robot_trooper_unit.tscn",
					"peer_id": 1, "tint": Color.BLUE, "position": _main.power_effects.ground_point(base + Vector3(4 + i, 0, 8))}))
	if _tick == 70:
		print("pads under construction ", _pads[0].is_under_construction, " ", _pads[1].is_under_construction,
				" partner ", _pads[0].partner(), " can_send ", _pads[0].can_send(1))
		if _pads[0].partner() == null:
			_pads[0].link_to(_pads[1])
			print("linked by hand: can_send ", _pads[0].can_send(1))
	if _tick == 80:
		var paths: Array[NodePath] = []
		for u in _units:
			paths.append(u.get_path())
		var target := _main._resolve_order_target_path({"collider": _pads[0], "position": _pads[0].global_position})
		print("right-click target ", target)
		_main.issue_command_as(1, paths, target, _pads[0].global_position, false, false)
	if _tick > 80 and _tick % 30 == 0:
		var line := "t=%d travellers %d |" % [_tick, _pads[0]._travellers.size()]
		for u in _units:
			line += " cmd%d d%.1f" % [u.status_command, Vector2(u.global_position.x - _pads[0].global_position.x, u.global_position.z - _pads[0].global_position.z).length()]
		print(line)
	if _tick > 80 + 30 * 20:
		get_tree().root.remove_child(_main)
		get_tree().quit()
