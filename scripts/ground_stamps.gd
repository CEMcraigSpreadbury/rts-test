class_name GroundStamps
extends RefCounted
## Dirt worn into the ground around finished buildings, like the cleared area
## the map generator paints around each town center. One R8 texture covers
## STAMP_EXTENT metres centred on the origin; binbun_terrain.gdshader reads it
## as extra dirt and binbun_foliage.gdshader grows no blades on it, both
## through the ground_stamp_* shader globals.

const STAMP_EXTENT: float = 512.0
const PIXELS_PER_METRE: float = 2.0
## How far past the footprint the dirt reaches, and over how many metres its
## edge fades (the terrain shader turns the fade into its noisy path edge).
const MARGIN: float = 1.5
const FALLOFF: float = 1.5
## How much the radius wobbles around the building, as a fraction of it.
const WOBBLE: float = 0.25

static var _image: Image
static var _texture: ImageTexture
static var _scene_id: int = 0
static var _noise: FastNoiseLite

static func stamp_building(building: Node3D, footprint_radius: float) -> void:
	if footprint_radius <= 0.0:
		return
	_ensure_texture(building)
	var centre := Vector2(building.global_position.x, building.global_position.z)
	var radius: float = footprint_radius + MARGIN
	var reach: float = radius * (1.0 + WOBBLE) + FALLOFF
	var size: int = _image.get_width()
	var lo: Vector2i = _to_pixel(centre - Vector2(reach, reach))
	var hi: Vector2i = _to_pixel(centre + Vector2(reach, reach))
	for py in range(maxi(lo.y, 0), mini(hi.y, size - 1) + 1):
		for px in range(maxi(lo.x, 0), mini(hi.x, size - 1) + 1):
			var p: Vector2 = _to_world(Vector2i(px, py))
			var offset: Vector2 = p - centre
			var wobble: float = _noise.get_noise_2d(centre.x + offset.normalized().x * 40.0, centre.y + offset.normalized().y * 40.0)
			var edge: float = radius * (1.0 + wobble * WOBBLE)
			var value: float = clampf((edge - offset.length()) / FALLOFF * 0.5 + 0.5, 0.0, 1.0)
			if value > _image.get_pixel(px, py).r:
				_image.set_pixel(px, py, Color(value, 0.0, 0.0))
	_texture.update(_image)

## A fresh, empty texture for each map, so stamps don't carry between matches.
static func _ensure_texture(node: Node) -> void:
	var scene: Node = node.get_tree().current_scene
	var scene_id: int = scene.get_instance_id() if scene else 0
	if _image != null and _scene_id == scene_id:
		return
	_scene_id = scene_id
	var size: int = int(STAMP_EXTENT * PIXELS_PER_METRE)
	_image = Image.create_empty(size, size, false, Image.FORMAT_R8)
	_texture = ImageTexture.create_from_image(_image)
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.frequency = 0.05
	RenderingServer.global_shader_parameter_set(&"ground_stamp_tex", _texture)
	RenderingServer.global_shader_parameter_set(&"ground_stamp_rect",
			Vector4(-STAMP_EXTENT * 0.5, -STAMP_EXTENT * 0.5, STAMP_EXTENT, STAMP_EXTENT))

static func _to_pixel(world: Vector2) -> Vector2i:
	return Vector2i(((world + Vector2.ONE * STAMP_EXTENT * 0.5) * PIXELS_PER_METRE).floor())

static func _to_world(pixel: Vector2i) -> Vector2:
	return (Vector2(pixel) + Vector2(0.5, 0.5)) / PIXELS_PER_METRE - Vector2.ONE * STAMP_EXTENT * 0.5
