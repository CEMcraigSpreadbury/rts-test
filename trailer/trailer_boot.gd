extends Node

const MAP_PATH: String = "res://scenes/maps/four_kingdoms.tscn"

func _ready() -> void:
	Network.start_offline()
	for i in 3:
		Network.add_ai_player()
	Network.resolve_random_rulers()
	var script_path: String = "res://trailer/trailer_scout.gd" if OS.get_cmdline_user_args().has("--scout") \
			else "res://trailer/trailer_director.gd"
	var director: Node = load(script_path).new()
	get_tree().root.add_child.call_deferred(director)
	SceneLoader.change_scene(MAP_PATH)
