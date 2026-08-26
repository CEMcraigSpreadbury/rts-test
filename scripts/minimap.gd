extends Control
## Self-contained minimap: draws the same fog-of-war grid used in the 3D
## world (so it never disagrees with what the ground itself is showing),
## colored dots for every unit/building currently allowed to be seen, a
## rough camera-frustum outline, and click/drag-to-pan.

const TERRAIN_COLOR: Color = Color(0.22, 0.32, 0.19, 1.0)
const BORDER_COLOR: Color = Color(0.9, 0.9, 0.9, 0.8)
const OWN_OUTLINE_COLOR: Color = Color(1, 1, 1, 0.9)
const UNIT_DOT_RADIUS: float = 2.5
const BUILDING_DOT_RADIUS: float = 4.0
const FRUSTUM_COLOR: Color = Color(1, 1, 1, 0.6)

@onready var fog: FogOfWar = get_node(^"../../FogOfWar")
@onready var camera_rig: Node3D = get_node(^"../../CameraRig")
@onready var camera: Camera3D = get_node(^"../../CameraRig/Yaw/Pitch/Camera3D")

var _dragging: bool = false

func _my_peer_id() -> int:
	return multiplayer.get_unique_id()

func _process(_delta: float) -> void:
	## Fog only updates a few times a second, but unit dots should move
	## smoothly, so just redraw every frame — this is a tiny Control.
	queue_redraw()

func _world_to_local(world_pos: Vector3) -> Vector2:
	var u := (world_pos.x - fog.map_origin.x) / fog.map_size.x
	var v := (world_pos.z - fog.map_origin.y) / fog.map_size.y
	return Vector2(u * size.x, v * size.y)

func _local_to_world(local_pos: Vector2) -> Vector3:
	var u := local_pos.x / size.x
	var v := local_pos.y / size.y
	return Vector3(fog.map_origin.x + u * fog.map_size.x, 0.0, fog.map_origin.y + v * fog.map_size.y)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), TERRAIN_COLOR)
	if fog and fog.fog_texture:
		draw_texture_rect(fog.fog_texture, Rect2(Vector2.ZERO, size), false)

	var my_peer := _my_peer_id()

	for node in get_tree().get_nodes_in_group("buildings"):
		var building := node as ProductionBuilding
		if not building or building.is_destroyed:
			continue
		var mine: bool = building.owner_peer_id == my_peer
		if not mine and not fog.is_explored_at(building.global_position):
			continue
		var p := _world_to_local(building.global_position)
		draw_circle(p, BUILDING_DOT_RADIUS, building.team_tint)
		if mine:
			draw_arc(p, BUILDING_DOT_RADIUS, 0.0, TAU, 12, OWN_OUTLINE_COLOR, 1.0)

	for node in get_tree().get_nodes_in_group("units"):
		var unit := node as Unit
		if not unit or unit.status_activity == Unit.Activity.DEAD:
			continue
		var mine: bool = unit.owner_peer_id == my_peer
		if not mine and not fog.is_visible_at(unit.global_position):
			continue
		var p := _world_to_local(unit.global_position)
		draw_circle(p, UNIT_DOT_RADIUS, unit.team_tint)
		if mine:
			draw_arc(p, UNIT_DOT_RADIUS, 0.0, TAU, 10, OWN_OUTLINE_COLOR, 1.0)

	_draw_camera_frustum()
	draw_rect(Rect2(Vector2.ZERO, size), BORDER_COLOR, false, 2.0)

## Approximates what the main camera currently frames by ray-casting its four
## viewport corners onto the ground plane — gives a properly perspective-skewed
## trapezoid rather than a fake rectangle.
func _draw_camera_frustum() -> void:
	var vp_size := get_viewport().get_visible_rect().size
	var corners := [Vector2.ZERO, Vector2(vp_size.x, 0), vp_size, Vector2(0, vp_size.y)]
	var ground := Plane(Vector3.UP, 0.0)
	var points: Array[Vector2] = []
	for corner in corners:
		var from: Vector3 = camera.project_ray_origin(corner)
		var dir: Vector3 = camera.project_ray_normal(corner)
		var hit = ground.intersects_ray(from, dir)
		if hit == null:
			return
		points.append(_world_to_local(hit))
	points.append(points[0])
	draw_polyline(points, FRUSTUM_COLOR, 1.5)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			_pan_to(event.position)
	elif event is InputEventMouseMotion and _dragging:
		_pan_to(event.position)

func _pan_to(local_pos: Vector2) -> void:
	var world_pos := _local_to_world(local_pos)
	camera_rig.global_position.x = world_pos.x
	camera_rig.global_position.z = world_pos.z
