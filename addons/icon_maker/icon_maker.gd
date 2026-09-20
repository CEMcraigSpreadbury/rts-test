@tool
class_name IconMaker
extends RefCounted
## Turns a 3D model or a sprite into a small pixel-art command-card icon.
## Shared by the Icon Maker dock (select a file, tweak, save) and
## scenes/tools/generate_command_icons.tscn (regenerates every building and
## unit icon in one go).

## The command button is 40px with a 4px content margin, so 32 fills it 1:1.
const DEFAULT_SIZE: int = 32
## Models render this many times larger than the icon, then get averaged
## down — coverage, not a single sample, decides each final pixel.
const SUPERSAMPLE: int = 8
const OUTLINE_COLOR: Color = Color(0.07, 0.05, 0.04)
## Below this averaged coverage a pixel is left empty; icons have hard edges.
const ALPHA_CUTOFF: float = 0.45

class Options:
	var size: int = DEFAULT_SIZE
	## Camera orbit around the model, degrees. 0 yaw looks down -Z.
	var yaw: float = 35.0
	var pitch: float = 35.0
	## > 1 crops in tighter, < 1 leaves more room around the model.
	var zoom: float = 1.0
	var outline: bool = true
	## Sprites only: one frame of a sheet. A zero size uses the whole image.
	var frame_size: Vector2i = Vector2i.ZERO
	var frame_row: int = 0
	var frame_column: int = 0
	## Sprites only: how much to blow the figure up. Zero fits it to the icon
	## on its own; a set value is how a whole roster is given one zoom (see
	## unit_scale) so buttons sitting side by side match.
	var scale: float = 0.0

## What a file can be turned into: "model", "unit" (a scene with a sprite
## sheet), "sprite", or "" for anything else.
static func source_kind(path: String) -> String:
	if not ResourceLoader.exists(path):
		return ""
	var resource: Resource = load(path)
	if resource is Texture2D:
		return "sprite"
	if resource is PackedScene:
		var node: Node = (resource as PackedScene).instantiate()
		var kind := "unit" if node.get("sprite_sheet") is Texture2D else "model"
		node.free()
		return kind
	return ""

## Icon for any supported file; null if it isn't one. Awaitable — models take
## a couple of rendered frames.
static func make(host: Node, path: String, options: Options) -> Image:
	match source_kind(path):
		"model":
			return await render_model(host, load(path), options)
		"unit":
			return unit_icon(load(path), options)
		"sprite":
			return sprite_icon(load(path), options)
	return null

## A unit scene's first idle frame, read off its exported sprite settings.
static func unit_icon(scene: PackedScene, options: Options) -> Image:
	return sprite_icon(_unit_sheet(scene), _unit_options(scene, options))

## The zoom this unit's figure would get on its own. A roster takes the
## smallest of these and passes it back in as Options.scale, so no one unit
## ends up twice the size of the one beside it on the command card.
static func unit_scale(scene: PackedScene, size: int) -> float:
	var options := Options.new()
	options.size = size
	var frame: Image = _frame_image(_unit_sheet(scene), _unit_options(scene, options))
	if frame == null:
		return 1.0
	return _auto_scale(frame.get_size(), size)

static func _unit_sheet(scene: PackedScene) -> Texture2D:
	var unit: Node = scene.instantiate()
	var sheet: Texture2D = unit.get("sprite_sheet")
	unit.free()
	return sheet

static func _unit_options(scene: PackedScene, options: Options) -> Options:
	var unit: Node = scene.instantiate()
	var cell: Vector2i = unit.get("sprite_cell_size")
	var row: int = unit.get("idle_row")
	unit.free()
	var sprite_options := Options.new()
	sprite_options.size = options.size
	sprite_options.outline = options.outline
	sprite_options.scale = options.scale
	sprite_options.frame_size = cell
	sprite_options.frame_row = row
	return sprite_options

## Crops the figure out of its frame and scales it by whole pixels, so its
## pixels stay square and even.
static func sprite_icon(texture: Texture2D, options: Options) -> Image:
	if texture == null:
		return null
	var image: Image = _frame_image(texture, options)
	if image == null:
		return null
	var used: Vector2i = image.get_size()
	var scale: float = options.scale if options.scale > 0.0 else _auto_scale(used, options.size)
	var scaled := Vector2i(maxi(1, roundi(used.x * scale)), maxi(1, roundi(used.y * scale)))
	scaled = scaled.min(Vector2i(options.size, options.size))
	image.resize(scaled.x, scaled.y, Image.INTERPOLATE_NEAREST)
	var icon := Image.create_empty(options.size, options.size, false, Image.FORMAT_RGBA8)
	icon.blit_rect(image, Rect2i(Vector2i.ZERO, scaled), (Vector2i(options.size, options.size) - scaled) / 2)
	if options.outline:
		_outline(icon)
	return icon

## One frame of a sheet, trimmed to the figure — a frame is mostly empty
## space, and where in the cell the figure sits varies from sheet to sheet.
static func _frame_image(texture: Texture2D, options: Options) -> Image:
	if texture == null:
		return null
	var image: Image = texture.get_image()
	if image == null:
		return null
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	if options.frame_size.x > 0 and options.frame_size.y > 0:
		var frame := Rect2i(options.frame_column * options.frame_size.x, options.frame_row * options.frame_size.y,
				options.frame_size.x, options.frame_size.y)
		image = image.get_region(frame.intersection(Rect2i(Vector2i.ZERO, image.get_size())))
	var used: Rect2i = image.get_used_rect()
	if not used.has_area():
		return null
	return image.get_region(used)

## Whole-number zoom while the figure still fits; anything already bigger
## than the icon is shrunk to fit instead.
static func _auto_scale(figure: Vector2i, size: int) -> float:
	var fit: float = minf(float(size) / figure.x, float(size) / figure.y)
	return maxf(1.0, floorf(fit)) if fit >= 1.0 else fit

## Renders the scene in its own world from a three-quarter view, framed to
## its meshes, then pixelates it. Scripts are stripped first so nothing in the
## scene runs, and effects, health bars, rings and sounds are left out.
static func render_model(host: Node, scene: PackedScene, options: Options) -> Image:
	var render_size: int = options.size * SUPERSAMPLE
	var viewport := SubViewport.new()
	viewport.size = Vector2i(render_size, render_size)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.55
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	viewport.add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, options.yaw - 40.0, 0.0)
	sun.light_energy = 1.1
	viewport.add_child(sun)

	var model: Node = scene.instantiate()
	_strip(model)
	viewport.add_child(model)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	viewport.add_child(camera)
	host.add_child(viewport)

	var bounds: AABB = _visual_bounds(model)
	if not bounds.has_volume():
		viewport.queue_free()
		return null
	var basis := Basis.from_euler(Vector3(deg_to_rad(-options.pitch), deg_to_rad(options.yaw), 0.0))
	var distance: float = bounds.size.length() * 2.0 + 1.0
	camera.global_transform = Transform3D(basis, bounds.get_center() + basis.z * distance)
	camera.near = 0.05
	camera.far = distance * 3.0
	## Frame the model's projected outline, not its box: a tall tower seen
	## from above is much narrower on screen than its bounding box suggests.
	var to_camera: Transform3D = camera.global_transform.affine_inverse()
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for corner in _points_of(model):
		var local: Vector3 = to_camera * corner
		low = low.min(Vector2(local.x, local.y))
		high = high.max(Vector2(local.x, local.y))
	var middle: Vector2 = (low + high) * 0.5
	camera.global_position += basis.x * middle.x + basis.y * middle.y
	var margin: float = float(options.size) / float(options.size - 2)
	camera.size = maxf(high.x - low.x, high.y - low.y) * margin / options.zoom

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var render: Image = viewport.get_texture().get_image()
	viewport.queue_free()
	var icon := _downsample(render, options.size)
	if options.outline:
		_outline(icon)
	return icon

static func _strip(node: Node) -> void:
	for child in node.get_children():
		if _is_extra(child):
			node.remove_child(child)
			child.free()
		else:
			_strip(child)
	node.set_script(null)

static func _is_extra(node: Node) -> bool:
	return node is GPUParticles3D or node is CPUParticles3D or node is SpriteBase3D or node is Label3D \
			or node is Decal or node is Light3D or node is AudioStreamPlayer or node is AudioStreamPlayer3D \
			or node is AudioStreamPlayer2D or node is CanvasItem or node.name.to_lower().contains("selection")

static func _geometry(node: Node, found: Array[GeometryInstance3D]) -> void:
	if node is GeometryInstance3D and (node as GeometryInstance3D).is_visible_in_tree():
		found.append(node)
	for child in node.get_children():
		_geometry(child, found)

static func _visual_bounds(model: Node) -> AABB:
	var bounds := AABB()
	var first := true
	var found: Array[GeometryInstance3D] = []
	_geometry(model, found)
	for geometry in found:
		var box: AABB = geometry.global_transform * geometry.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	return bounds

## Every mesh's box corners, in world space — framing from these is much
## tighter than from one box around the whole model.
static func _points_of(model: Node) -> PackedVector3Array:
	var points := PackedVector3Array()
	var found: Array[GeometryInstance3D] = []
	_geometry(model, found)
	for geometry in found:
		var box: AABB = geometry.get_aabb()
		for i in 8:
			points.append(geometry.global_transform * box.get_endpoint(i))
	return points

## Averages each block of the render into one pixel, weighting colour by
## coverage so the transparent background doesn't darken the edges.
static func _downsample(render: Image, size: int) -> Image:
	render.convert(Image.FORMAT_RGBA8)
	var block: int = render.get_width() / size
	var icon := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var sum := Vector3.ZERO
			var coverage := 0.0
			for by in block:
				for bx in block:
					var c: Color = render.get_pixel(x * block + bx, y * block + by)
					sum += Vector3(c.r, c.g, c.b) * c.a
					coverage += c.a
			var alpha: float = coverage / float(block * block)
			if alpha >= ALPHA_CUTOFF:
				var average: Vector3 = sum / coverage
				icon.set_pixel(x, y, Color(average.x, average.y, average.z, 1.0))
	return icon

## A one-pixel dark edge round the shape, like the unit sprites have.
static func _outline(icon: Image) -> void:
	var size: Vector2i = icon.get_size()
	var edge: Array[Vector2i] = []
	for y in size.y:
		for x in size.x:
			if icon.get_pixel(x, y).a > 0.0:
				continue
			for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = Vector2i(x, y) + offset
				if n.x >= 0 and n.y >= 0 and n.x < size.x and n.y < size.y and icon.get_pixelv(n).a > 0.0:
					edge.append(Vector2i(x, y))
					break
	for pixel in edge:
		icon.set_pixelv(pixel, OUTLINE_COLOR)
