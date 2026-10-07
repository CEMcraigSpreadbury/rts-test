class_name GroundScatter
extends Node3D
## Small things on the grass that make it read as a meadow: grey rocks, white
## and yellow flowers, and pebbles on the dirt. Purely
## visual and local to each peer, placed once at load from the terrain's own
## splatmap (grass only, never on dirt, rock or sand) with a fixed seed so a
## map always looks the same.
##
## Batched as one MultiMesh per kind per CHUNK square, each with a draw
## distance, so a big map costs only what is near the camera. Anything that
## ends up under a building or field later is hidden by the shader (it reads
## the same ground stamps that put dirt there). Colours here are sRGB and
## converted for the shader, which takes vertex colour as linear.

const ROCK_SHADER: Shader = preload("res://shaders/terrain/ground_scatter_rock.gdshader")
const PEBBLE_SHADER: Shader = preload("res://shaders/terrain/ground_scatter_pebble.gdshader")
const FLOWER_SHADER: Shader = preload("res://shaders/terrain/ground_scatter_flower.gdshader")

const CHUNK: float = 48.0
const DRAW_DISTANCE: float = 150.0
## Grass weight in the splatmap needed to put anything down.
const GRASS_MIN: float = 0.75
## Per square metre, before the patch noise thins them out.
const ROCK_DENSITY: float = 1.0 / 80.0
const FLOWER_DENSITY: float = 1.0 / 12.0
## Small stones: on painted paths, and on the dirt stamped under buildings.
const PEBBLE_DENSITY: float = 1.0 / 30.0
const SEED: int = 7151
## Instance custom alpha: how a piece treats dirt stamped under a building or
## field (ground_scatter.gdshaderinc).
const HIDE_ON_DIRT: float = 0.0
const ALWAYS: float = 0.5
const ONLY_ON_DIRT: float = 1.0

## Warm sandy greys, as the buildings' stone; warmer than they look, since the
## glossy finish picks up the blue sky.
const ROCK_COLOURS: Array[Color] = [Color(0.6, 0.53, 0.45), Color(0.52, 0.47, 0.41), Color(0.66, 0.6, 0.51)]
const FLOWER_COLOURS: Array[Color] = [Color(0.88, 0.88, 0.86), Color(0.88, 0.88, 0.84), Color(0.92, 0.82, 0.45)]

var _rng := RandomNumberGenerator.new()

## Builds the scatter for the map's TerraBrush terrain, or does nothing if
## the map has none (or its data can't be read).
static func build(main: Node) -> GroundScatter:
	var terrain: Node = _find_terrain(main)
	if terrain == null:
		return null
	var data_path: String = terrain.get("dataPath")
	var size: int = terrain.get("zonesSize")
	var splat := load(data_path.path_join("Splatmap_0_0_0.res")) as Image
	var heights := load(data_path.path_join("Heightmap_0_0.res")) as Image
	if splat == null or heights == null or size <= 1:
		return null
	if splat.is_compressed():
		splat = splat.duplicate()
		splat.decompress()
	var scatter := GroundScatter.new()
	scatter.name = "GroundScatter"
	main.add_child(scatter)
	scatter._populate(splat, heights, size, (terrain as Node3D).global_position)
	return scatter

static func _find_terrain(node: Node) -> Node:
	## TerraBrush is a C# node, so it is found by the property it carries.
	var data_path: Variant = node.get("dataPath")
	if data_path is String and data_path != "" and node.get("zonesSize") != null:
		return node
	for child in node.get_children():
		var found: Node = _find_terrain(child)
		if found != null:
			return found
	return null

func _populate(splat: Image, heights: Image, size: int, origin: Vector3) -> void:
	_rng.seed = SEED
	var patches := FastNoiseLite.new()
	patches.seed = SEED
	patches.frequency = 0.045
	var half: float = (size - 1) * 0.5
	var rock_meshes: Array[Mesh] = [_rock_mesh(0), _rock_mesh(1), _rock_mesh(2)]
	var flower_mesh: Mesh = _flower_mesh()
	var rock_material := ShaderMaterial.new()
	rock_material.shader = ROCK_SHADER
	var pebble_material := ShaderMaterial.new()
	pebble_material.shader = PEBBLE_SHADER
	var flower_material := ShaderMaterial.new()
	flower_material.shader = FLOWER_SHADER

	## chunk key -> {kind: Array[[Transform3D, Color]]}
	var chunks: Dictionary = {}
	var total_area: float = float(size - 1) * float(size - 1)
	for spec in [["rock", ROCK_DENSITY], ["flower", FLOWER_DENSITY], ["pebble", PEBBLE_DENSITY]]:
		var kind: String = spec[0]
		for _i in int(total_area * float(spec[1])):
			var px: float = _rng.randf() * (size - 1)
			var pz: float = _rng.randf() * (size - 1)
			var texel: Color = splat.get_pixelv(Vector2i(int(px), int(pz)))
			var grass: float = texel.r
			var on_path: bool = texel.g > 0.6
			match kind:
				"pebble":
					if grass < GRASS_MIN and not on_path:
						continue
				_:
					if grass < GRASS_MIN:
						continue
			var world := Vector2(px - half + origin.x, pz - half + origin.z)
			## Patches: flowers gather in tight drifts, the rest in looser scatters.
			var patch: float = patches.get_noise_2d(world.x, world.y) * 0.5 + 0.5
			var keep: float = 0.35 + patch
			if kind == "flower":
				keep = pow(patch, 5.0) * 4.0
			elif kind == "pebble":
				## Pebbles lie in little scatters, not evenly sprinkled.
				keep = pow(patch, 3.0) * 3.0
			if _rng.randf() > keep:
				continue
			var at := Vector3(world.x, _height_at(heights, px, pz) + origin.y, world.y)
			var basis := Basis(Vector3.UP, _rng.randf() * TAU)
			match kind:
				"rock":
					var s: float = _rng.randf_range(0.75, 1.25)
					basis = basis.scaled(Vector3(s, s * _rng.randf_range(0.7, 1.1), s))
					_put(chunks, "rock%d" % (_rng.randi() % rock_meshes.size()), Transform3D(basis, at),
							_rock_tint(), HIDE_ON_DIRT)
				"flower":
					basis = basis.scaled(Vector3.ONE * _rng.randf_range(1.7, 2.1))
					_put(chunks, "flower", Transform3D(basis, at), FLOWER_COLOURS[_rng.randi() % FLOWER_COLOURS.size()], HIDE_ON_DIRT)
				"pebble":
					var p: float = _rng.randf_range(0.28, 0.45)
					basis = basis.scaled(Vector3(p, p * 0.7, p))
					## On a painted path, always; on grass, only once a building
					## or field has stamped dirt there.
					_put(chunks, "pebble%d" % (_rng.randi() % rock_meshes.size()), Transform3D(basis, at),
							_rock_tint(), ALWAYS if on_path else ONLY_ON_DIRT)

	for key in chunks:
		var lists: Dictionary = chunks[key]
		for kind in lists:
			var mesh: Mesh
			var material: ShaderMaterial
			if String(kind).begins_with("rock"):
				mesh = rock_meshes[int(String(kind).substr(4))]
				material = rock_material
			elif String(kind).begins_with("pebble"):
				mesh = rock_meshes[int(String(kind).substr(6))]
				material = pebble_material
			else:
				mesh = flower_mesh
				material = flower_material
			_add_chunk(lists[kind], mesh, material)

## Files one instance under its chunk. `tint`'s alpha is replaced by `mode`,
## which tells the shader how to treat stamped dirt.
static func _put(chunks: Dictionary, kind: String, xform: Transform3D, tint: Color, mode: float) -> void:
	var key := Vector2i(floori(xform.origin.x / CHUNK), floori(xform.origin.z / CHUNK))
	if not chunks.has(key):
		chunks[key] = {}
	var lists: Dictionary = chunks[key]
	if not lists.has(kind):
		lists[kind] = []
	tint.a = mode
	lists[kind].append([xform, tint])

func _rock_tint() -> Color:
	return ROCK_COLOURS[_rng.randi() % ROCK_COLOURS.size()].srgb_to_linear()

func _add_chunk(items: Array, mesh: Mesh, material: ShaderMaterial) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = items.size()
	for i in items.size():
		multimesh.set_instance_transform(i, items[i][0])
		multimesh.set_instance_custom_data(i, items[i][1])
	var node := MultiMeshInstance3D.new()
	node.multimesh = multimesh
	node.material_override = material
	node.visibility_range_end = DRAW_DISTANCE
	node.visibility_range_end_margin = 10.0
	node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	if material.shader == FLOWER_SHADER:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)

## Bilinear, so a rock never floats over a slope between two pixels.
static func _height_at(heights: Image, px: float, pz: float) -> float:
	var x0: int = clampi(int(px), 0, heights.get_width() - 1)
	var z0: int = clampi(int(pz), 0, heights.get_height() - 1)
	var x1: int = mini(x0 + 1, heights.get_width() - 1)
	var z1: int = mini(z0 + 1, heights.get_height() - 1)
	var fx: float = px - x0
	var fz: float = pz - z0
	var top: float = lerpf(heights.get_pixel(x0, z0).r, heights.get_pixel(x1, z0).r, fx)
	var bottom: float = lerpf(heights.get_pixel(x0, z1).r, heights.get_pixel(x1, z1).r, fx)
	return lerpf(top, bottom, fz)

## A chunky toy stone: a rounded block with broad, nearly flat faces (as the
## gold deposit's boulders), a little lumpy, smooth shaded so it takes the
## plastic shine, and a little sunk into the ground.
func _rock_mesh(variant: int) -> Mesh:
	var sphere := SphereMesh.new()
	## Enough rings and segments for the rounded corners to read.
	sphere.radial_segments = 12
	sphere.rings = 8
	sphere.radius = 1.0
	sphere.height = 2.0
	var arrays: Array = sphere.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var noise := FastNoiseLite.new()
	noise.seed = SEED + variant * 31
	## Broad lumps rather than fine facets.
	noise.frequency = 1.4
	## Half-extents per variant (x, y, z): chunky enough to stand clear of the
	## grass blades, and each a different shape.
	var extents: Vector3 = [Vector3(0.5, 0.36, 0.42), Vector3(0.44, 0.4, 0.5), Vector3(0.56, 0.3, 0.46)][variant % 3]
	var twist: float = variant * 0.7
	for i in vertices.size():
		var u: Vector3 = vertices[i].normalized()
		## A superellipsoid: |x|^4 + |y|^4 + |z|^4 = 1 is a cube with rounded
		## edges, so the faces come out broad and nearly flat.
		var s: float = pow(pow(absf(u.x), 4.0) + pow(absf(u.y), 4.0) + pow(absf(u.z), 4.0), -0.25)
		var v: Vector3 = (u * s * extents).rotated(Vector3.UP, twist)
		## Keyed on position, so the seam vertices a sphere duplicates move together.
		var bump: float = 1.0 + noise.get_noise_3dv(vertices[i]) * 0.12
		v *= bump
		## Flat-bottomed and only just sunk, so it stands clear of the grass blades.
		v.y = maxf(v.y, -0.02) - 0.02
		vertices[i] = v
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for index in indices:
		var v: Vector3 = vertices[index]
		## Lighter on top, as if sunlit and weathered.
		var light: float = clampf(0.62 + v.y * 2.2, 0.5, 1.12)
		tool.set_color(Color(light, light, light).srgb_to_linear())
		## One smooth group: normals average across the shared positions.
		tool.set_smooth_group(0)
		tool.add_vertex(v)
	tool.generate_normals()
	return tool.commit()

## Two daisies, upright and facing +z: the flower shader turns them to the
## camera. Round-tipped petals, so they read as flowers, not stars.
func _flower_mesh() -> Mesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var centre := Color(1.0, 0.8, 0.18)
	var petal := Color(0.95, 0.95, 0.92)
	for f in 2:
		var at := Vector3([-0.06, 0.07][f], [0.15, 0.19][f], 0.0)
		for p in 5:
			var a: float = p * TAU / 5.0 + 0.3
			var dir := Vector3(cos(a), sin(a), 0.0)
			var side := Vector3(-sin(a), cos(a), 0.0)
			## A rounded petal: a fan from the eye out to a blunt tip.
			var steps: int = 4
			for k in steps:
				var t0: float = (float(k) / steps - 0.5) * PI
				var t1: float = (float(k + 1) / steps - 0.5) * PI
				var c := at + dir * 0.045
				_tri(tool, petal, at, c + dir * cos(t0) * 0.03 + side * sin(t0) * 0.022,
						c + dir * cos(t1) * 0.03 + side * sin(t1) * 0.022)
		for c in 6:
			var ca: float = c * TAU / 6.0
			var eye := Vector3(0.0, 0.0, 0.004)
			_tri(tool, centre, at + eye, at + eye + Vector3(cos(ca), sin(ca), 0.0) * 0.036,
					at + eye + Vector3(cos(ca + TAU / 6.0), sin(ca + TAU / 6.0), 0.0) * 0.036)
	return tool.commit()

static func _tri(tool: SurfaceTool, colour: Color, a: Vector3, b: Vector3, c: Vector3) -> void:
	for v in [a, b, c]:
		tool.set_color(colour.srgb_to_linear())
		tool.add_vertex(v)
