class_name TreeBillboard
extends RefCounted
## Test swap of the 3D tree models for 2D billboards cut from the tree sheet.
## The sprite goes inside the model root (so fog hiding and the harvest squash
## still reach it) and the model's meshes are only hidden, so TOGGLE_KEY can
## flip every tree back and forth for comparison.

const SHEET: Texture2D = preload("res://assets/art/Trees/flat shaded trees.png")
const TOGGLE_KEY: Key = KEY_F10
## The tallest sheet pines (~385 px) come out the height of tree_pine_1 (6.2 m).
const PIXEL_SIZE: float = 0.016
## The trunk's bottom edge sits a little into the ground so slopes don't show a gap.
const SINK: float = 0.15
const REGIONS: Array[Rect2] = [
	Rect2(13, 17, 208, 384),
	Rect2(261, 42, 216, 359),
	Rect2(516, 17, 210, 386),
	Rect2(777, 17, 222, 386),
	Rect2(1069, 53, 254, 352),
	Rect2(1431, 29, 228, 376),
	Rect2(18, 431, 184, 259),
	Rect2(249, 440, 158, 251),
	Rect2(451, 436, 169, 257),
	Rect2(656, 441, 183, 249),
	Rect2(883, 437, 189, 252),
	Rect2(1099, 448, 145, 242),
	Rect2(1276, 441, 174, 249),
	Rect2(1477, 441, 180, 251),
	Rect2(14, 715, 187, 199),
	Rect2(240, 715, 198, 200),
	Rect2(485, 715, 190, 202),
	Rect2(710, 720, 201, 196),
	Rect2(948, 719, 220, 197),
	Rect2(1209, 717, 169, 200),
	Rect2(1411, 708, 241, 212),
]

static var enabled: bool = true
static var _sprites: Array[Sprite3D] = []

## Walks `node`, adding a billboard to every tree model found (same tree*.glb
## test TreeWind uses). Safe to call twice on the same nodes.
static func apply_to_trees_in(node: Node) -> void:
	if node is Node3D and node.scene_file_path.get_file().to_lower().begins_with("tree"):
		_apply(node)
		return
	for child in node.get_children():
		apply_to_trees_in(child)

static func toggle() -> void:
	enabled = not enabled
	var i := _sprites.size() - 1
	while i >= 0:
		var sprite := _sprites[i]
		if is_instance_valid(sprite):
			_show(sprite)
		else:
			_sprites.remove_at(i)
		i -= 1

static func _apply(model: Node3D) -> void:
	if model.has_node(^"TreeBillboard"):
		return
	## Seeded from position, so every peer (and every run) picks the same tree.
	var pos := model.global_position
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(roundi(pos.x * 10.0), roundi(pos.z * 10.0)))
	var region: Rect2 = REGIONS[rng.randi() % REGIONS.size()]
	var sprite := Sprite3D.new()
	sprite.name = &"TreeBillboard"
	sprite.texture = SHEET
	sprite.region_enabled = true
	sprite.region_rect = region
	sprite.pixel_size = PIXEL_SIZE
	sprite.flip_h = rng.randi() % 2 == 0
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.shaded = true
	sprite.offset = Vector2(0.0, region.size.y * 0.5 - SINK / PIXEL_SIZE)
	model.add_child(sprite)
	_sprites.append(sprite)
	_show(sprite)

static func _show(sprite: Sprite3D) -> void:
	sprite.visible = enabled
	for child in sprite.get_parent().get_children():
		if child != sprite and child is VisualInstance3D:
			child.visible = not enabled
