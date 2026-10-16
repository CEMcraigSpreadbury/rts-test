extends Node
## Throwaway: a finished Library by the player's Town Centre, three villagers
## sent to read, research logged every 10 s for a minute.

var _main: Main
var _tick := 0
var _library: ProductionBuilding
var _readers: Array[Unit] = []

func _ready() -> void:
	var info: MapInfo = MapInfo.list_all()[1]
	Network.start_offline()
	Network.map_index = 1
	Network.set_match_settings(Network.GameMode.REALM, 0)
	Network.add_ai_player(Network.AiDifficulty.NORMAL)
	(func():
		var m: Node = load(info.scene_path).instantiate()
		get_tree().root.add_child(m)
		get_tree().current_scene = m
		_main = m as Main).call_deferred()

func _physics_process(_d: float) -> void:
	if _main == null:
		return
	_tick += 1
	if _tick == 90:
		for n in get_tree().root.find_children("*", "", true, false):
			if n is AiPlayer:
				n.process_mode = Node.PROCESS_MODE_DISABLED
		var p0: Vector3 = (_main.player_spawn_points.get_child(0) as Node3D).global_position
		var at := p0 + Vector3(-9, 0, 6)
		_library = _main.building_spawner.spawn({"scene_path": "res://scenes/buildings/library_building.tscn",
			"peer_id": 1, "tint": _main.get_team_tint(1), "position": at})
		for i in 3:
			_readers.append(_main.unit_spawner.spawn({"scene_path": "res://scenes/units/unit.tscn", "peer_id": 1,
				"tint": _main.get_team_tint(1), "position": at + Vector3(4 + i, 0, 4)}))
		print("LIBRARY built=", not _library.is_under_construction, " books=", _library.linked_deposit)
	if _tick == 150:
		print("BOOKS open=", _library.linked_deposit.can_be_gathered())
		var paths: Array[NodePath] = []
		for r in _readers:
			paths.append(r.get_path())
		_main.issue_command_as(1, paths, _library.get_path(), _library.global_position, false, false)
	if _tick >= 150 and _tick % 600 == 0:
		var s := ""
		for r in _readers:
			s += "%s/%s hidden=%s; " % [Unit.Command.keys()[r.status_command], Unit.Activity.keys()[r.status_activity], not r.visible]
		print("t=%2d research %d | %s" % [(_tick - 150) / 60, ResourceStockpile.get_amount(1, Research.RESOURCE), s])
	if _tick == 150 + 30 * 20:
		print("READERS ", _main.readers_of(_library).size())
		_main.release_reader(_library, 0)
	if _tick == 150 + 30 * 23:
		var r: Unit = _readers[0]
		print("RELEASED %s/%s visible=%s sheltered=%s selected=%s readers_left=%d" % [Unit.Command.keys()[r.status_command],
			Unit.Activity.keys()[r.status_activity], r.visible, r.sheltered, _main.selected_units.has(r), _main.readers_of(_library).size()])
		print("TARGET ", r.attack_target.display_name if is_instance_valid(r.attack_target) and "display_name" in r.attack_target else str(r.attack_target), " owner ", r.attack_target.owner_peer_id if is_instance_valid(r.attack_target) else -9)
		get_tree().quit()
	if _tick >= 150 + 60 * 65:
		get_tree().quit()
