class_name RoadNet
extends RefCounted
## A map's roads (the generator's settlement roads, saved on its "Roads" node)
## as a coarse grid, so "is this on a road?" is one lookup. On a road a unit,
## or a block marching as one, goes ROAD_SPEED times as fast — which is what
## makes the roads between settlements the way armies travel.

const ROAD_SPEED: float = 1.25
const CELL: float = 2.0
const NODE_NAME: String = "Roads"

## The roads of the map being played; empty on a map without any.
static var _cells: Dictionary = {}

## Every peer, as the match starts: reads the roads under `map_root`.
static func build(map_root: Node) -> void:
	_cells.clear()
	var node := map_root.get_node_or_null(NODE_NAME)
	if node == null or not node.has_meta(&"segments"):
		return
	var ends: PackedVector2Array = node.get_meta(&"segments")
	var widths: PackedFloat32Array = node.get_meta(&"widths")
	for s in widths.size():
		var a: Vector2 = ends[s * 2]
		var b: Vector2 = ends[s * 2 + 1]
		var half: float = widths[s] * 0.5
		var low := Vector2i(floori((minf(a.x, b.x) - half) / CELL), floori((minf(a.y, b.y) - half) / CELL))
		var high := Vector2i(floori((maxf(a.x, b.x) + half) / CELL), floori((maxf(a.y, b.y) + half) / CELL))
		for z in range(low.y, high.y + 1):
			for x in range(low.x, high.x + 1):
				var centre := Vector2((x + 0.5) * CELL, (z + 0.5) * CELL)
				if Geometry2D.get_closest_point_to_segment(centre, a, b).distance_to(centre) <= half:
					_cells[Vector2i(x, z)] = true

static func has_roads() -> bool:
	return not _cells.is_empty()

## ROAD_SPEED on a road, 1.0 anywhere else.
static func speed_at(pos: Vector3) -> float:
	if _cells.is_empty():
		return 1.0
	return ROAD_SPEED if _cells.has(Vector2i(floori(pos.x / CELL), floori(pos.z / CELL))) else 1.0
