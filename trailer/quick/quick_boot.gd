extends Node
## Boots a quick trailer: `-- --director=<name>` picks trailer/quick/<name>_director.gd
## (default quick).

const MAP_PATH: String = "res://scenes/maps/aldmere_vale_realm.tscn"

func _ready() -> void:
	Network.start_offline()
	Network.add_ai_player()
	Network.resolve_random_rulers()
	var director_name: String = "quick"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--director="):
			director_name = arg.trim_prefix("--director=")
	var director: Node = load("res://trailer/quick/%s_director.gd" % director_name).new()
	get_tree().root.add_child.call_deferred(director)
	SceneLoader.change_scene(MAP_PATH)
