extends Node
func _ready() -> void:
	var bad := 0
	for f in DirAccess.get_files_at("res://scenes/buildings"):
		if f.ends_with(".tscn"):
			var s = load("res://scenes/buildings/" + f)
			if s == null:
				bad += 1
				print("FAILED ", f)
	print("buildings checked, failures: ", bad, " lord item ", load("res://resources/lord_item.tres") != null)
	get_tree().quit()
