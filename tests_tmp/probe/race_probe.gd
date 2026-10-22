extends Node
## Throwaway: a Realm match, the host Pirates, AIs Pirates / Robots / Aldmere;
## every 30 s, per side, villagers, army by unit and buildings by shown name,
## gold, and plundered/wound-up state.

const MINUTES: float = 4.0
var _main: Main
var _tick := 0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var map := 1
	for a in args:
		if a.begins_with("--map="):
			map = int(a.get_slice("=", 1))
	var info: MapInfo = MapInfo.list_all()[map]
	Network.start_offline()
	Network.map_index = map
	Network.set_match_settings(Network.GameMode.REALM, 0)
	Network.set_my_race(1)
	for race in [2, 0]:
		var id := Network.add_ai_player(Network.AiDifficulty.NORMAL)
		Network.set_ai_race(id, race)
	Network.resolve_random_rulers()
	(func():
		var m: Node = load(info.scene_path).instantiate()
		get_tree().root.add_child(m)
		get_tree().current_scene = m
		_main = m as Main
		## The host is a Pirate AI too, so it plays itself.
		_main._start_ai_player.call_deferred(1)).call_deferred()

func _physics_process(_d: float) -> void:
	if _main == null:
		return
	_tick += 1
	if _tick % (30 * 30) == 0:
		for peer in Network.players:
			var faction: Faction = _main.faction_by_peer.get(peer)
			var counts := {}
			var villagers := 0
			var windup := []
			for u in get_tree().get_nodes_in_group(&"units"):
				if not (u is Unit) or u.owner_peer_id != peer or u.status_activity == Unit.Activity.DEAD:
					continue
				if u.can_gather:
					villagers += 1
				else:
					counts[u.display_name] = counts.get(u.display_name, 0) + 1
					if u.race_clockwork:
						windup.append("%.2f" % u.race_windup)
			var names: Array[String] = []
			for b in get_tree().get_nodes_in_group(&"buildings"):
				if b is ProductionBuilding and b.owner_peer_id == peer:
					names.append(b.shown_name() + ("*" if b.is_under_construction else ""))
			names.sort()
			print("t=%3ds p%d %s vill %d gold %d army %s" % [_tick / 30, peer, faction.faction_name if faction else "?",
					villagers, ResourceStockpile.get_amount(peer, AiPlayer.GOLD), counts])
			print("      buildings: %s" % ", ".join(names))
			if not windup.is_empty():
				print("      windup: %s" % " ".join(windup.slice(0, 12)))
	if _tick >= int(MINUTES * 60.0 * 30.0):
		get_tree().root.remove_child(_main)
		get_tree().quit()
