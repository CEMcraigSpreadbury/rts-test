extends Node
## Throwaway: a Realm match with 2 AIs; every 30 s, per AI, how many villagers,
## whether it has a (finished) Library, its readers and its research total.

const MINUTES: float = 5.0
var _main: Main
var _ais: Array[int] = []
var _tick := 0

func _ready() -> void:
	var info: MapInfo = MapInfo.list_all()[1]
	Network.start_offline()
	Network.map_index = 1
	Network.set_match_settings(Network.GameMode.REALM, 0)
	for i in 2:
		_ais.append(Network.add_ai_player(Network.AiDifficulty.NORMAL))
	(func():
		var m: Node = load(info.scene_path).instantiate()
		get_tree().root.add_child(m)
		get_tree().current_scene = m
		_main = m as Main).call_deferred()

func _physics_process(_d: float) -> void:
	if _main == null:
		return
	_tick += 1
	if _tick % (30 * 30) == 0:
		for peer in _ais:
			var villagers := 0
			for u in get_tree().get_nodes_in_group(&"units"):
				if u is Unit and u.owner_peer_id == peer and u.can_gather and u.status_activity != Unit.Activity.DEAD:
					villagers += 1
			var library := "none"
			var readers := 0
			for b in get_tree().get_nodes_in_group(&"buildings"):
				if b is ProductionBuilding and b.owner_peer_id == peer and b.building_name == "Library":
					library = "building" if b.is_under_construction else "built"
					readers = _main.readers_of(b).size()
			var names: Array[String] = []
			for b in get_tree().get_nodes_in_group(&"buildings"):
				if b is ProductionBuilding and b.owner_peer_id == peer:
					names.append(b.building_name + ("*" if b.is_under_construction else ""))
			names.sort()
			print("   ai%d wood %d gold %d food %d: %s" % [peer, ResourceStockpile.get_amount(peer, AiPlayer.WOOD), ResourceStockpile.get_amount(peer, AiPlayer.GOLD), ResourceStockpile.get_amount(peer, RealmEconomy.FOOD), ", ".join(names)])
			print("t=%3ds ai%d villagers %2d library %s readers %d research %d" % [_tick / 30, peer, villagers,
					library, readers, ResourceStockpile.get_amount(peer, Research.RESOURCE)])
	if _tick >= int(MINUTES * 60.0 * 30.0):
		get_tree().quit()
