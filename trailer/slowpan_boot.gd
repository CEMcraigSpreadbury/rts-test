extends Node

const MAP_PATH: String = "res://scenes/maps/aethermoor_creek.tscn"

func _ready() -> void:
	Network.start_offline()
	Network.add_ai_player()
	Network.resolve_random_rulers()
	var director: Node = load("res://trailer/slowpan_director.gd").new()
	get_tree().root.add_child.call_deferred(director)
	SceneLoader.change_scene(MAP_PATH)
