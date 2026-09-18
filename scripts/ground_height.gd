class_name GroundHeight
extends RefCounted
## The current map's TerraBrush terrain, found once per map, for units to read
## the ground height from directly (see Unit._slide) instead of sweeping a
## collision shape against it. Null on a map without one, where units fall
## back to move_and_slide().

static var _terrain: TerraBrush = null
static var _scene: Node = null

static func terrain(tree: SceneTree) -> TerraBrush:
	var scene := tree.current_scene
	if scene != _scene:
		_scene = scene
		_terrain = null
		if scene != null:
			var found := scene.find_children("*", "TerraBrush", true, false)
			if not found.is_empty():
				_terrain = found[0]
	return _terrain
