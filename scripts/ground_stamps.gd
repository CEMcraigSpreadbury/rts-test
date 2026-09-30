class_name GroundStamps
extends RefCounted
## Dirt worn into the ground under and round buildings and fields, like the cleared area
## the map generator paints around each town center. One R8 texture covers the
## map's terrain (see _ensure_texture); binbun_terrain.gdshader reads it
## as extra dirt and binbun_foliage.gdshader grows no blades on it, both
## through the ground_stamp_* shader globals.

## Used when there is no terrain to size to.
const STAMP_EXTENT: float = 512.0
const PIXELS_PER_METRE: float = 2.0
## Past this the texture gets coarser rather than bigger (a Realm map is 2 km).
const MAX_PIXELS: int = 4096
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
## The world XZ of the texture's corner, the metres it spans, and its pixels
## per metre.
static var _origin: Vector2 = Vector2.ZERO
static var _extent: float = STAMP_EXTENT
static var _ppm: float = PIXELS_PER_METRE
## A whole map's buildings stamp in the same frame as it loads: one upload
## for all of them rather than a full texture each.
static var _upload_queued: bool = false

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
	if not _upload_queued:
		_upload_queued = true
		_upload.call_deferred()

static func _upload() -> void:
	_upload_queued = false
	if _texture != null:
		_texture.update(_image)

## A fresh, empty texture for each map, so stamps don't carry between matches.
static func _ensure_texture(node: Node) -> void:
	var scene: Node = node.get_tree().current_scene
	var scene_id: int = scene.get_instance_id() if scene else 0
	if _image != null and _scene_id == scene_id:
		return
	_scene_id = scene_id
	_extent = STAMP_EXTENT
	_origin = -Vector2.ONE * STAMP_EXTENT * 0.5
	## Fitted to the terrain, laid out as ArmyBridge reads it: one zone of
	## heightmap pixels a metre apart, centred on the node. A fixed square round
	## the origin missed every building out past it on the bigger maps.
	var found: Array[Node] = []
	if scene != null:
		found = scene.find_children("*", "TerraBrush", true, false)
	if not found.is_empty():
		var terrain: Node3D = found[0]
		var zones: Variant = terrain.get(&"terrainZones")
		var heights: Image = zones.zones[0].heightMapImage if zones != null and not zones.zones.is_empty() else null
		if heights != null:
			_extent = float(heights.get_width() - 1)
			_origin = Vector2(terrain.global_position.x, terrain.global_position.z) - Vector2.ONE * _extent * 0.5
	_ppm = minf(PIXELS_PER_METRE, MAX_PIXELS / _extent)
	var size: int = ceili(_extent * _ppm)
	_image = Image.create_empty(size, size, false, Image.FORMAT_R8)
	_texture = ImageTexture.create_from_image(_image)
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.frequency = 0.05
	RenderingServer.global_shader_parameter_set(&"ground_stamp_tex", _texture)
	RenderingServer.global_shader_parameter_set(&"ground_stamp_rect",
			Vector4(_origin.x, _origin.y, _extent, _extent))

static func _to_pixel(world: Vector2) -> Vector2i:
	return Vector2i(((world - _origin) * _ppm).floor())

static func _to_world(pixel: Vector2i) -> Vector2:
	return (Vector2(pixel) + Vector2(0.5, 0.5)) / _ppm + _origin
