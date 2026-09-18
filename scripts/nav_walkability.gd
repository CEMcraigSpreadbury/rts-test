class_name NavWalkability
extends RefCounted
## Answers "is this spot on the navmesh?" without NavigationServer3D.
## map_get_closest_point checks every polygon on the map (0.25-0.4 ms a call on
## the shipped maps), which a march's room probing (see GroupMovement's
## Marching section) calls dozens of times at once. This buckets the navmesh's
## polygons into a coarse XZ grid once per bake, so a lookup only tests the
## handful of convex polygons in one cell. Heightmap maps have no overlapping
## floors, so XZ alone decides it.

## Small enough that a bucket in a wood — where the navmesh is cut into many
## little polygons round every trunk — still only holds a handful to test.
const BUCKET_SIZE: float = 1.0

## The index for the navmesh currently in play, or null before the first one is
## built (callers fall back to the NavigationServer). Kept up to date by
## NavigationBlockers, which rebuilds it off the main thread after each bake —
## so for the few frames a rebuild takes it can lag one bake behind.
static var current: NavWalkability = null

## The mesh this was built from — lets callers tell when a rebake replaced it.
var mesh: NavigationMesh
var _to_local: Transform3D
var _origin: Vector2
var _width: int = 0
var _height: int = 0
## Per bucket, the polygons whose XZ bounds touch it.
var _buckets: Array[PackedInt32Array] = []
## Polygon p's XZ corners are _points[_starts[p] .. _starts[p + 1]).
var _starts := PackedInt32Array()
var _points := PackedVector2Array()

func _init(navigation_mesh: NavigationMesh, region_transform: Transform3D) -> void:
	mesh = navigation_mesh
	_to_local = region_transform.affine_inverse()
	var vertices := navigation_mesh.get_vertices()
	if vertices.is_empty():
		return
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for v in vertices:
		low = low.min(Vector2(v.x, v.z))
		high = high.max(Vector2(v.x, v.z))
	_origin = low
	_width = int(ceil((high.x - low.x) / BUCKET_SIZE)) + 1
	_height = int(ceil((high.y - low.y) / BUCKET_SIZE)) + 1
	_buckets.resize(_width * _height)
	for i in _buckets.size():
		_buckets[i] = PackedInt32Array()
	var count := navigation_mesh.get_polygon_count()
	_starts.resize(count + 1)
	for p in count:
		_starts[p] = _points.size()
		var polygon := navigation_mesh.get_polygon(p)
		var poly_low := Vector2(INF, INF)
		var poly_high := Vector2(-INF, -INF)
		for index in polygon:
			var corner := Vector2(vertices[index].x, vertices[index].z)
			_points.append(corner)
			poly_low = poly_low.min(corner)
			poly_high = poly_high.max(corner)
		var first := _bucket_of(poly_low)
		var last := _bucket_of(poly_high)
		for bz in range(first.y, last.y + 1):
			for bx in range(first.x, last.x + 1):
				_buckets[bz * _width + bx].append(p)
	_starts[count] = _points.size()

func is_walkable(world_position: Vector3) -> bool:
	return polygon_at(world_position) >= 0

## Index of the navmesh polygon under `world_position` (XZ only), or -1 off the
## mesh. `hint` is tested first: a walking unit passes the polygon it was last
## in, which a single step almost always stays inside, skipping the bucket scan.
func polygon_at(world_position: Vector3, hint: int = -1) -> int:
	if _width == 0:
		return -1
	var local := _to_local * world_position
	var point := Vector2(local.x, local.z)
	if hint >= 0 and hint < _starts.size() - 1 and _inside(hint, point):
		return hint
	var bucket := _bucket_of(point)
	if bucket.x < 0 or bucket.y < 0 or bucket.x >= _width or bucket.y >= _height:
		return -1
	for p in _buckets[bucket.y * _width + bucket.x]:
		if _inside(p, point):
			return p
	return -1

func _bucket_of(point: Vector2) -> Vector2i:
	return Vector2i(floori((point.x - _origin.x) / BUCKET_SIZE), floori((point.y - _origin.y) / BUCKET_SIZE))

## Navmesh polygons are convex, so the point is inside when it sits on the same
## side of every edge (either winding).
func _inside(p: int, point: Vector2) -> bool:
	var start := _starts[p]
	var end := _starts[p + 1]
	var sign := 0.0
	for i in range(start, end):
		var a := _points[i]
		var b := _points[start if i + 1 == end else i + 1]
		var cross := (b - a).cross(point - a)
		if absf(cross) < 0.000001:
			continue
		if sign == 0.0:
			sign = cross
		elif sign * cross < 0.0:
			return false
	return true
