extends SceneTree
func _init() -> void:
	for f in DirAccess.get_files_at("res://scenes/units/beasts"):
		if not f.ends_with(".tscn"): continue
		var u = load("res://scenes/units/beasts/" + f).instantiate()
		var model: PackedScene = u.get("figure_model")
		var root: Node = model.instantiate() if model else null
		var aabb := AABB()
		if root:
			for mi in root.find_children("*", "MeshInstance3D", true, false):
				aabb = mi.get_aabb() if aabb.size == Vector3.ZERO else aabb.merge(mi.get_aabb())
			root.free()
		print(f, " size ", aabb.size.snapped(Vector3.ONE * 0.01))
		u.free()
	quit()
