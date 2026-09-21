extends Node3D
## The live scene behind the main menu: a fixed camera over a corner of the
## terrain, with the grass moving.
##
## The camera never moves -- this is a backdrop, not a fly-through, so nothing
## competes with the menu for attention.
##
## Wind normally comes from FogOfWar, which walks the tree for grass materials
## and drives their `wind_velocity` / `wind_offset` every frame. There is no
## FogOfWar out here, so this does the same job for the backdrop's foliage and
## nothing else. Kept deliberately small: one direction, one strength, no gusts.

## Radians per second the direction wanders, so the field never looks looped.
const DRIFT_RATE: float = 0.08
const STRENGTH: float = 0.35
## Matches FogOfWar's scroll rate so the backdrop and the game look alike.
const OFFSET_SCALE: float = 0.01

var _materials: Array[ShaderMaterial] = []
var _direction: float = 0.7
var _offset: Vector2 = Vector2.ZERO

## The still camera, in world units. These XZ coordinates come from the running
## game (the RTS camera's position after focusing the town centre on this map),
## because this terrain sits at NEGATIVE X and guessing coordinates does not
## work. The height is queried from the terrain and LIFT added, so the camera
## cannot end up underground or staring at the sky if the heightmap changes.
const CAMERA_XZ := Vector2(-84.0, 92.0)
const TARGET_XZ := Vector2(-77.0, 82.0)
## Two constraints pull against each other. The horizon shows whenever the pitch
## is shallower than half the fov (so with fov 55, anything under ~28 degrees),
## and the grass quads are small, so they only read as blades when the camera is
## within a few units of the ground. This is low AND pitched ~36 degrees: no sky,
## and real grass in the foreground rather than painted terrain texture.
const LIFT: float = 10.0

func _ready() -> void:
	_place_camera()
	## TerraBrush builds its foliage around the active camera over the first few
	## frames, so the sweep is deferred rather than run against an empty tree.
	await get_tree().process_frame
	await get_tree().process_frame
	_collect(self)

func _place_camera() -> void:
	var camera: Camera3D = get_node_or_null("Camera3D")
	if camera == null:
		return
	var camera_ground := _ground_at(CAMERA_XZ)
	var target_ground := _ground_at(TARGET_XZ)
	camera.position = Vector3(CAMERA_XZ.x, camera_ground + LIFT, CAMERA_XZ.y)
	camera.look_at(Vector3(TARGET_XZ.x, target_ground + 1.0, TARGET_XZ.y), Vector3.UP)

func _ground_at(xz: Vector2) -> float:
	var terrain: Node = get_node_or_null("Terrain")
	if terrain == null or not terrain.has_method("getHeightAtPosition"):
		return 0.0
	return float(terrain.call("getHeightAtPosition", xz.x, xz.y, true))

func _collect(node: Node) -> void:
	if node is GeometryInstance3D:
		var material := (node as GeometryInstance3D).material_override as ShaderMaterial
		if material != null and material.shader != null \
				and material.shader.code.contains("wind_velocity"):
			_materials.append(material)
	for child in node.get_children():
		_collect(child)

func _process(delta: float) -> void:
	if _materials.is_empty():
		return
	var strength: float = STRENGTH if Settings.get_value(&"wind") else 0.0
	_direction += DRIFT_RATE * delta
	var velocity := Vector2(cos(_direction), sin(_direction)) * strength
	_offset += velocity * OFFSET_SCALE * delta
	for material in _materials:
		material.set_shader_parameter("wind_velocity", velocity)
		material.set_shader_parameter("wind_offset", _offset)
