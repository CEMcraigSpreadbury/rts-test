class_name UnitDiorama
extends SubViewportContainer
## One unit's figure stood on a little plastic display base, slowly turning:
## the Races screen's showcase. Its own world in its own SubViewport, so it
## needs no Main or FigureBatcher; the figure is drawn with
## FigureMaterials.standalone, as the Bestiary cage and the menu backdrop do.
## Drag across it to turn the figure by hand.

## Radians per second it turns on its own.
const SPIN_RATE: float = 0.45
## Radians per pixel of drag.
const DRAG_RATE: float = 0.012
## Seconds after a drag before it starts turning on its own again.
const SPIN_RESUME: float = 2.0
## The figure is scaled so its widest or tallest side is this, in metres, so a
## Villager and a Dragon both fill the stand.
const FIT_SIZE: float = 1.7
const BASE_RADIUS: float = 1.15
const BASE_HEIGHT: float = 0.16
const BASE_COLOUR := Color(0.36, 0.55, 0.27)
const RIM_COLOUR := Color(0.24, 0.27, 0.3)
const CAMERA_FOV: float = 30.0
const CAMERA_PITCH_DEGREES: float = 16.0
## Starts three-quarters on rather than square to the camera.
const START_YAW: float = 0.5

var _viewport: SubViewport
var _turntable: Node3D
var _figure_root: Node3D
var _camera: Camera3D
var _resume_in: float = 0.0

func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	add_child(_viewport)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.75, 0.78, 0.85)
	environment.ambient_light_energy = 0.6
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = environment
	_viewport.add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	_viewport.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20.0, -150.0, 0.0)
	fill.light_energy = 0.35
	_viewport.add_child(fill)

	_turntable = Node3D.new()
	_viewport.add_child(_turntable)
	_turntable.add_child(_base())
	_figure_root = Node3D.new()
	_figure_root.position.y = BASE_HEIGHT
	_turntable.add_child(_figure_root)

	_camera = Camera3D.new()
	_camera.fov = CAMERA_FOV
	_viewport.add_child(_camera)

## A round toy display stand: a grass-green top on a grey rim.
func _base() -> Node3D:
	var stand := Node3D.new()
	var rim := MeshInstance3D.new()
	var rim_mesh := CylinderMesh.new()
	rim_mesh.top_radius = BASE_RADIUS + 0.05
	rim_mesh.bottom_radius = BASE_RADIUS + 0.12
	rim_mesh.height = BASE_HEIGHT * 0.6
	rim_mesh.radial_segments = 48
	rim.mesh = rim_mesh
	rim.material_override = _plastic(RIM_COLOUR)
	rim.position.y = BASE_HEIGHT * 0.3
	stand.add_child(rim)
	var top := MeshInstance3D.new()
	var top_mesh := CylinderMesh.new()
	top_mesh.top_radius = BASE_RADIUS
	top_mesh.bottom_radius = BASE_RADIUS
	top_mesh.height = BASE_HEIGHT * 0.4
	top_mesh.radial_segments = 48
	top.mesh = top_mesh
	top.material_override = _plastic(BASE_COLOUR)
	top.position.y = BASE_HEIGHT * 0.8
	stand.add_child(top)
	return stand

static func _plastic(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.45
	return material

## Shows `unit` (a scene instance that never enters the tree; the caller
## frees it) in `tint`: its body, any wheels and its siege crew.
func show_unit(unit: Unit, tint: Color) -> void:
	for child in _figure_root.get_children():
		child.free()
	_turntable.rotation.y = START_YAW
	_resume_in = 0.0
	unit._take_villager_figure()
	var body: Mesh = Unit.figure_mesh(unit.figure_model)
	if body == null:
		return
	var parts: Array = [[body, unit.figure_palette, Transform3D.IDENTITY]]
	for i in unit.wheel_models.size():
		var wheel: Mesh = Unit.figure_mesh(unit.wheel_models[i])
		if wheel != null:
			parts.append([wheel, unit.figure_palette, Transform3D.IDENTITY])
	if unit.crew_figure_model != null:
		var crew: Mesh = Unit.figure_mesh(unit.crew_figure_model)
		if crew != null:
			parts.append([crew, unit.crew_figure_palette if unit.crew_figure_palette != null else unit.figure_palette,
					Transform3D(Basis(Vector3.UP, deg_to_rad(unit.crew_figure_yaw)), unit.crew_figure_offset)])

	var box := AABB()
	for i in parts.size():
		var part_box: AABB = (parts[i][2] as Transform3D) * (parts[i][0] as Mesh).get_aabb()
		box = part_box if i == 0 else box.merge(part_box)
	var fit: float = FIT_SIZE / maxf(maxf(box.size.x, box.size.z), maxf(box.size.y, 0.01))
	var holder := Node3D.new()
	holder.scale = Vector3.ONE * fit
	holder.position = Vector3(-box.get_center().x * fit, -box.position.y * fit, -box.get_center().z * fit)
	_figure_root.add_child(holder)
	for part in parts:
		holder.add_child(FigureMaterials.standalone(part[0], part[1], tint, part[2]))
	_frame(box.size.y * fit)

## Puts the camera where the stand and a figure `height` tall both fit.
func _frame(height: float) -> void:
	var look := Vector3(0.0, BASE_HEIGHT + height * 0.38, 0.0)
	var reach: float = maxf(height + BASE_HEIGHT, BASE_RADIUS * 2.0) * 0.72
	var distance: float = reach / tan(deg_to_rad(CAMERA_FOV * 0.5))
	var pitch: float = deg_to_rad(CAMERA_PITCH_DEGREES)
	_camera.position = look + Vector3(0.0, sin(pitch), cos(pitch)) * distance
	_camera.look_at(look)

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if _resume_in > 0.0:
		_resume_in -= delta
	else:
		_turntable.rotation.y += SPIN_RATE * delta

func _gui_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null and motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_turntable.rotation.y += motion.relative.x * DRAG_RATE
		_resume_in = SPIN_RESUME
		accept_event()
