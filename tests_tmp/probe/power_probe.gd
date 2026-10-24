extends Node
## Throwaway: host Knights, AIs Pirates and Robots, all AI-played. At 40 s every
## side gets 200 research points; reports what each bought and cast.

const MINUTES: float = 6.0
var _main: Main
var _tick := 0

func _ready() -> void:
	Engine.time_scale = 4.0
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
		_main = m as Main
		_main._start_ai_player.call_deferred(1)).call_deferred()

func _physics_process(_d: float) -> void:
	if _main == null:
		return
	_tick += 1
	if _tick == 40 * 30:
		for peer in Network.players:
			Research.earn(peer, 200, &"probe")
			var names := []
			for p in Research.powers_for(peer):
				names.append(p.node_name)
			print("p%d %s powers %s" % [peer, _main.faction_by_peer[peer].faction_name, names])
	if _tick % (30 * 30) == 0 and _tick > 40 * 30:
		_report()
	if _tick >= int(MINUTES * 60.0 * 30.0):
		get_tree().root.remove_child(_main)
		get_tree().quit()

func _report() -> void:
	for peer in Network.players:
		var ai: AiPlayer = _main.ai_players.get(peer) if "ai_players" in _main else null
		var cast = ai.research.powers_cast if ai != null else "?"
		print("t=%3ds p%d owned %s points %d cast %s" % [_tick / 30, peer, _main.research.owned_by(peer),
				ResourceStockpile.get_amount(peer, Research.RESOURCE), cast])
