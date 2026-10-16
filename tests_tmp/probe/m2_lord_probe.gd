extends Node
var _t := 0
func _ready() -> void:
	if get_tree().current_scene == self:
		var w: Node = load("res://tests_tmp/probe/m2_lord_probe.gd").new()
		get_tree().root.add_child.call_deferred(w)
		set_physics_process(false)
		return
	Network.start_offline()
	SceneLoader.change_scene("res://scenes/scenarios/m2_smoke_over_the_vale.tscn")
func _physics_process(_d: float) -> void:
	_t += 1
	if _t % 60 != 0: return
	var main := get_tree().current_scene as Main
	if main == null: return
	var tc := Vector3.INF
	for b in get_tree().get_nodes_in_group(&"buildings"):
		if b is ProductionBuilding and b.is_main_base and b.owner_peer_id == 1:
			tc = b.global_position
	for u in get_tree().get_nodes_in_group(&"units"):
		if u is Unit and u.is_lord:
			print("t=%ds lord %s cmd %s act %s tc %s" % [_t / 30, u.global_position.round(), Unit.Command.keys()[u.status_command], Unit.Activity.keys()[u.status_activity], tc.round()])
	if _t >= 30 * 30: get_tree().quit()
