@tool
class_name MapTerrainBuilder
extends RefCounted
## Turns a MapLayout into TileMapLayer3D tile data and a navigation mesh.
##
## Tile data is written straight into the columnar TileMapLayerData arrays
## (same format TileMapLayer3D.add_tile_direct produces) rather than one
## add_tile_direct call per tile, which copies every array on each call.
##
## Ramps, rims and decals use per-tile custom transforms. Decals sit a hair
## above the floor they cover, keyed 0.1 higher (the key precision) so they
## never collide with the floor tile's key.

const FLOOR: int = 0
## Wall orientation for a wall on the cell edge facing DIRS[i] (N, E, S, W).
const WALL_FOR_DIR: Array[int] = [3, 5, 2, 4]
const RIM_LIFT: float = 0.02
const GRASS_LIFT: float = 0.02
const DIRT_LIFT: float = 0.04

## Marching-squares mask (TL=8, TR=4, BL=2, BR=1) -> offset into a 5x5 blob
## template. The two diagonal cases have no tile of their own and use the
## full-cover centre tile.
const BLOB_TILES: Dictionary = {
	1: Vector2i(1, 0), 2: Vector2i(3, 0), 3: Vector2i(2, 0),
	4: Vector2i(1, 4), 5: Vector2i(0, 2), 6: Vector2i(2, 2), 7: Vector2i(1, 1),
	8: Vector2i(3, 4), 9: Vector2i(2, 2), 10: Vector2i(4, 2), 11: Vector2i(3, 1),
	12: Vector2i(2, 4), 13: Vector2i(1, 3), 14: Vector2i(3, 3), 15: Vector2i(2, 2),
}

static func atlas_texture(tileset: TileSet) -> Texture2D:
	if tileset == null or tileset.get_source_count() == 0:
		return null
	var source := tileset.get_source(tileset.get_source_id(0)) as TileSetAtlasSource
	return source.texture if source != null else null

static func build_tile_data(layout: MapLayout, gen: MapGenerator, terrain: TileMapLayer3D) -> TileMapLayerData:
	var writer := _TileWriter.new(terrain, gen.tileset)
	var rng := RandomNumberGenerator.new()
	rng.seed = gen.map_seed + 7919
	var size: int = layout.size
	var slope: float = float(layout.height) / layout.ramp_length
	for z in size:
		for x in size:
			var c := Vector2i(x, z)
			var i: int = layout.index(c)
			var centre: Vector2 = layout.cell_centre(c)
			if layout.ramp_dir[i] >= 0:
				var mid: float = (layout.ramp_step[i] + 0.5) * slope
				writer.add(Vector3(centre.x - 0.5, snappedf(mid, 0.1) - 0.5, centre.y - 0.5), FLOOR, _pick(gen.ramp_tiles, rng),
					_ramp_transform(centre, mid, layout.ramp_dir[i], slope))
			elif layout.level[i] > 0:
				var h: float = layout.level[i]
				writer.add(Vector3(centre.x - 0.5, h - 0.5, centre.y - 0.5), FLOOR, gen.plateau_template + Vector2i(2, 2))
				var rim: Vector2i = _rim_offset(layout, c, rng)
				if rim != Vector2i(2, 2):
					writer.add(Vector3(centre.x - 0.5, h - 0.4, centre.y - 0.5), FLOOR, gen.plateau_template + rim,
						Transform3D(Basis.IDENTITY, Vector3(centre.x, h + RIM_LIFT, centre.y)))
			else:
				writer.add(Vector3(centre.x - 0.5, -0.5, centre.y - 0.5), FLOOR, _pick(gen.ground_tiles, rng))
				var grass_mask: int = layout.corner_mask(layout.grass, c)
				if grass_mask != 0:
					writer.add(Vector3(centre.x - 0.5, -0.4, centre.y - 0.5), FLOOR, gen.grass_template + BLOB_TILES[grass_mask],
						Transform3D(Basis.IDENTITY, Vector3(centre.x, GRASS_LIFT, centre.y)))
				var dirt_mask: int = layout.corner_mask(layout.dirt, c)
				if dirt_mask != 0:
					writer.add(Vector3(centre.x - 0.5, -0.3, centre.y - 0.5), FLOOR, gen.dirt_template + BLOB_TILES[dirt_mask],
						Transform3D(Basis.IDENTITY, Vector3(centre.x, DIRT_LIFT, centre.y)))
			_add_walls(writer, layout, c, gen, rng)
	return writer.finish()

## Walls hang from this cell's edges down to whichever neighbour is lower. A
## wall beside a ramp runs the full height; the ramp surface hides the rest.
static func _add_walls(writer: _TileWriter, layout: MapLayout, c: Vector2i, gen: MapGenerator, rng: RandomNumberGenerator) -> void:
	var i: int = layout.index(c)
	if layout.level[i] == 0 or layout.ramp_dir[i] >= 0:
		return
	var top: int = layout.level[i]
	var centre: Vector2 = layout.cell_centre(c)
	for d in 4:
		var n: Vector2i = c + MapLayout.DIRS[d]
		if not layout.in_bounds(n):
			continue
		var neighbour_edge: float = layout.edge_height(n, (d + 2) % 4)
		if neighbour_edge >= top - 0.01:
			continue
		var bottom: int = 0 if layout.ramp_dir[layout.index(n)] >= 0 else floori(neighbour_edge)
		var offset := Vector2(MapLayout.DIRS[d]) * 0.5
		for k in range(bottom, top):
			writer.add(Vector3(centre.x + offset.x - 0.5, k, centre.y + offset.y - 0.5), WALL_FOR_DIR[d], _pick(gen.cliff_tiles, rng))

## Which piece of the 5x5 plateau template (rim edges and corners around a
## solid centre) this plateau cell needs, from which sides drop away.
static func _rim_offset(layout: MapLayout, c: Vector2i, rng: RandomNumberGenerator) -> Vector2i:
	var top: float = layout.level[layout.index(c)]
	var low: Array[bool] = []
	for d in 4:
		var n: Vector2i = c + MapLayout.DIRS[d]
		low.append(layout.in_bounds(n) and layout.edge_height(n, (d + 2) % 4) < top - 0.01)
	var col: int = rng.randi_range(1, 3)
	var row: int = rng.randi_range(1, 3)
	if low[0] and not low[2]:
		row = 0
	elif low[2] and not low[0]:
		row = 4
	if low[3] and not low[1]:
		col = 0
	elif low[1] and not low[3]:
		col = 4
	if row in [1, 2, 3] and col in [1, 2, 3]:
		return Vector2i(2, 2)
	return Vector2i(col, row)

static func _ramp_transform(centre: Vector2, mid_height: float, dir_index: int, slope: float) -> Transform3D:
	var d: Vector2i = MapLayout.DIRS[dir_index]
	var x_axis := Vector3(1.0, -slope * d.x, 0.0)
	var z_axis := Vector3(0.0, -slope * d.y, 1.0)
	var y_axis: Vector3 = z_axis.cross(x_axis).normalized()
	return Transform3D(Basis(x_axis, y_axis, z_axis), Vector3(centre.x, mid_height, centre.y))

static func _pick(tiles: Array[Vector2i], rng: RandomNumberGenerator) -> Vector2i:
	return tiles[rng.randi() % tiles.size()] if not tiles.is_empty() else Vector2i.ZERO

## Navigation is baked from the layout itself rather than the rendered mesh,
## so only playable, walkable surfaces are included: nothing under plateaus,
## nothing in the decorative border.
static func bake_navigation_mesh(layout: MapLayout) -> NavigationMesh:
	var faces := PackedVector3Array()
	for z in layout.size:
		for x in layout.size:
			var c := Vector2i(x, z)
			if not layout.is_playable_cell(c):
				continue
			var centre: Vector2 = layout.cell_centre(c)
			var corners: Array[Vector3] = []
			for offset in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]:
				var p: Vector2 = centre + offset * 0.999
				corners.append(Vector3(centre.x + offset.x, layout.surface_height(p), centre.y + offset.y))
			_append_down_facing(faces, corners[0], corners[1], corners[2])
			_append_down_facing(faces, corners[0], corners[2], corners[3])
	var geometry := NavigationMeshSourceGeometryData3D.new()
	geometry.add_faces(faces, Transform3D.IDENTITY)
	var nav_mesh := NavigationMesh.new()
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.01
	nav_mesh.agent_radius = 0.3
	NavigationServer3D.bake_from_source_geometry_data(nav_mesh, geometry)
	return nav_mesh

## add_faces() flips winding, and Recast drops downward faces — so hand it
## triangles facing down (same trick as NavigationBlockers).
static func _append_down_facing(faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3) -> void:
	if (b - a).cross(c - a).y <= 0.0:
		faces.append_array(PackedVector3Array([a, b, c]))
	else:
		faces.append_array(PackedVector3Array([a, c, b]))

class _TileWriter:
	var _terrain: TileMapLayer3D
	var _tileset: TileSet
	var _tile_px: Vector2
	var _seen: Dictionary = {}
	var positions := PackedVector3Array()
	var uv_rects := PackedFloat32Array()
	var source_ids := PackedInt32Array()
	var atlas_coords := PackedInt32Array()
	var flags := PackedInt32Array()
	var transform_indices := PackedInt32Array()
	var anim_indices := PackedInt32Array()
	var custom_transforms: Dictionary = {}

	func _init(terrain: TileMapLayer3D, tileset: TileSet) -> void:
		_terrain = terrain
		_tileset = tileset
		_tile_px = Vector2(tileset.tile_size)

	func add(grid_pos: Vector3, orientation: int, coords: Vector2i, custom: Transform3D = Transform3D()) -> void:
		var key: int = GlobalUtil.make_tile_key(grid_pos, orientation)
		if _seen.has(key):
			return
		_seen[key] = true
		positions.append(grid_pos)
		uv_rects.append_array(PackedFloat32Array([coords.x * _tile_px.x, coords.y * _tile_px.y, _tile_px.x, _tile_px.y]))
		source_ids.append(0)
		atlas_coords.append_array(PackedInt32Array([coords.x, coords.y]))
		flags.append(_terrain._pack_flags_direct(orientation, 0, GlobalConstants.MeshMode.FLAT_SQUARE, false, -1))
		transform_indices.append(-1)
		anim_indices.append(-1)
		if custom != Transform3D():
			custom_transforms[key] = custom

	func finish() -> TileMapLayerData:
		var data := TileMapLayerData.new()
		data.tileset = _tileset
		data._tile_positions = positions
		data._tile_uv_rects = uv_rects
		data._tile_atlas_source_ids = source_ids
		data._tile_atlas_coords = atlas_coords
		data._tile_flags = flags
		data._flags_format_version = 2
		data._tile_transform_indices = transform_indices
		data._tile_transform_data = PackedFloat32Array()
		data._tile_custom_transforms = custom_transforms
		data._tile_anim_indices = anim_indices
		data._tile_anim_data = PackedFloat32Array()
		return data
