extends Node

const MAP_PATH: String = "res://scenes/maps/aethermoor_creek.tscn"

func _ready() -> void:
	Network.start_offline()
	Network.add_ai_player()
	Network.resolve_random_rulers()
	var script_path: String = "res://trailer/showcase_director.gd"
	if OS.get_cmdline_user_args().has("--scout"):
		script_path = "res://trailer/showcase_scout.gd"
	var director: Node = load(script_path).new()
	get_tree().root.add_child.call_deferred(director)
	SceneLoader.change_scene(MAP_PATH)
