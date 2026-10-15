class_name BuildingTorches
extends Node3D

## Torches on posts beside an Aldmere building's front corners (either side of
## a gateway), each with a real light that comes up as night falls and
## flickers. Purely cosmetic and local to each peer. Added to every building
## by ProductionBuilding; it only lights up for one whose model is Aldmere's
## own (TownBuildings) and not a wall, field or banner, and only once the
## building is finished. Torches are unlit by day: the flame and light come up
## together as night falls, and the light fades out at a distance.

const ALDMERE_MODELS: String = "res://assets/art/Models/TownBuildings/"
## Models that get no torches.
const UNLIT: Array[String] = ["WallSegment", "WallCorner", "Field", "GoldDeposit", "RallyBanner"]
const POST_HEIGHT: float = 1.0
## How far out from the model's sides, and how far towards its front (0 the
## middle, 1 the front face) the posts stand.
const SIDE_GAP: float = 0.35
const FRONT_SHARE: float = 0.55
## A gateway's posts stand just in front of its own.
const GATE_POST_X: float = 0.95
const GATE_FRONT: float = 0.45

const LIGHT_COLOUR := Color(1.0, 0.62, 0.3)
const LIGHT_ENERGY: float = 1.8
const LIGHT_RANGE: float = 7.0
const LIGHT_FADE_FROM: float = 45.0
const LIGHT_FADE_OVER: float = 15.0
const FLAME_GLOW: float = 4.0
const FLICKER: float = 0.18
## Below this night amount the torch is unlit.
const LIT_FROM: float = 0.02
## The flame: an orange cone with a yellow core, standing in the cup.
const FLAME_HEIGHT: float = 0.32
const FLAME_RADIUS: float = 0.09
const CORE_SHARE: float = 0.55

static var _post_mesh: CylinderMesh = null
static var _cup_mesh: CylinderMesh = null
static var _flame_mesh: CylinderMesh = null
static var _core_mesh: CylinderMesh = null

var _building: ProductionBuilding
## null until the building is finished and known to want torches; false once
## it is known not to.
var _placed: Variant = null
var _flames: Array[Node3D] = []
var _lights: Array[OmniLight3D] = []
var _phase: float = 0.0

func _init(building: ProductionBuilding) -> void:
	_building = building
	name = "Torches"

func _ready() -> void:
	_phase = float(hash(get_instance_id()) % 1000) * 0.01

func _process(_delta: float) -> void:
	if _placed == false:
		set_process(false)
		return
	if _building.is_under_construction or _building.is_destroyed:
		visible = false
		return
	if _placed == null:
		_placed = _place()
		if _placed == false:
			return
	visible = true
	var night: float = _night()
	var lit: bool = night > LIT_FROM
	## The flame grows to full size over the first part of dusk.
	var size: float = smoothstep(LIT_FROM, 0.3, night)
	var t: float = GameClock.msec() * 0.001 + _phase
	for i in _lights.size():
		var light := _lights[i]
		light.visible = lit
		_flames[i].visible = lit
		if not lit:
			continue
		var flicker: float = 1.0 - FLICKER * (0.5 + 0.5 * sin(t * 11.0 + i * 2.3) * sin(t * 7.3 + i))
		light.light_energy = LIGHT_ENERGY * night * flicker
		var sway: float = 0.08 * sin(t * 5.1 + i * 1.7)
		_flames[i].scale = Vector3(size * (1.05 - 0.1 * flicker), size * (0.8 + 0.4 * flicker), size * (1.05 - 0.1 * flicker))
		_flames[i].rotation = Vector3(sway, t * 1.3 + i, sway * 0.6)

func _night() -> float:
	var main := get_tree().current_scene
	var day_night: DayNight = main.get(&"day_night") if main != null and &"day_night" in main else null
	return day_night.night_amount if day_night != null else 0.0

## Puts the torches up, or says this building gets none.
func _place() -> bool:
	var model: Node3D = null
	for child in _building.get_children():
		if child is Node3D and String(child.scene_file_path).begins_with(ALDMERE_MODELS):
			model = child
			break
	if model == null or UNLIT.has(model.scene_file_path.get_file().get_basename()):
		return false
	var spots: Array[Vector3] = []
	if _building.passage_width > 0.0:
		for side in [-1.0, 1.0]:
			spots.append(Vector3(GATE_POST_X * side, 0.0, GATE_FRONT))
	else:
		var box := _model_box(model)
		if box.size == Vector3.ZERO:
			return false
		var centre: Vector3 = box.get_center()
		for side in [-1.0, 1.0]:
			spots.append(Vector3(centre.x + side * (box.size.x * 0.5 + SIDE_GAP), 0.0,
					centre.z + box.size.z * 0.5 * FRONT_SHARE))
	for spot in spots:
		_add_torch(spot)
	return true

## The model's extent in the building's space, as it stands when settled (not
## mid-bounce): its meshes relative to the model, under the model's resting
## transform.
func _model_box(model: Node3D) -> AABB:
	var rest: Transform3D = model.transform
	var index: int = _building._model_roots.find(model)
	if index >= 0:
		rest = Transform3D(Basis(Vector3.UP, _building._model_base_yaws[index]).scaled(_building._model_base_scales[index]),
				_building._model_base_positions[index])
	var box := AABB()
	var first: bool = true
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var local: Transform3D = model.global_transform.affine_inverse() * mi.global_transform
		var part: AABB = rest * local * mi.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box

func _add_torch(at: Vector3) -> void:
	_build_meshes()
	var torch := Node3D.new()
	torch.position = at
	var post := MeshInstance3D.new()
	post.mesh = _post_mesh
	post.position.y = POST_HEIGHT * 0.5
	torch.add_child(post)
	var cup := MeshInstance3D.new()
	cup.mesh = _cup_mesh
	cup.position.y = POST_HEIGHT + 0.07
	torch.add_child(cup)
	## Pivots at the cup's rim so the flame grows and sways from its base.
	var flame := Node3D.new()
	flame.position.y = POST_HEIGHT + 0.14
	flame.visible = false
	for mesh in [_flame_mesh, _core_mesh]:
		var part := MeshInstance3D.new()
		part.mesh = mesh
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		part.position.y = (mesh as CylinderMesh).height * 0.5
		flame.add_child(part)
	torch.add_child(flame)
	var light := OmniLight3D.new()
	light.light_color = LIGHT_COLOUR
	light.omni_range = LIGHT_RANGE
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = LIGHT_FADE_FROM
	light.distance_fade_length = LIGHT_FADE_OVER
	light.position.y = POST_HEIGHT + 0.45
	light.visible = false
	torch.add_child(light)
	add_child(torch)
	_flames.append(flame)
	_lights.append(light)

static func _build_meshes() -> void:
	if _post_mesh != null:
		return
	_post_mesh = CylinderMesh.new()
	_post_mesh.top_radius = 0.05
	_post_mesh.bottom_radius = 0.07
	_post_mesh.height = POST_HEIGHT
	_post_mesh.radial_segments = 8
	_post_mesh.rings = 1
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.42, 0.28, 0.17)
	wood.roughness = 0.6
	_post_mesh.material = wood
	_cup_mesh = CylinderMesh.new()
	_cup_mesh.top_radius = 0.13
	_cup_mesh.bottom_radius = 0.07
	_cup_mesh.height = 0.14
	_cup_mesh.radial_segments = 8
	_cup_mesh.rings = 1
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.25, 0.23, 0.22)
	iron.roughness = 0.4
	iron.metallic = 0.4
	_cup_mesh.material = iron
	## The outer cone is part see-through so the core glows inside it.
	_flame_mesh = _cone(FLAME_RADIUS, FLAME_HEIGHT, Color(1.0, 0.42, 0.08, 0.7))
	_core_mesh = _cone(FLAME_RADIUS * CORE_SHARE, FLAME_HEIGHT * CORE_SHARE, Color(1.0, 0.86, 0.4))

static func _cone(radius: float, height: float, colour: Color) -> CylinderMesh:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = radius
	cone.height = height
	cone.radial_segments = 6
	cone.rings = 1
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = colour
	if colour.a < 1.0:
		glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.emission_enabled = true
	glow.emission = Color(colour, 1.0)
	glow.emission_energy_multiplier = FLAME_GLOW
	cone.material = glow
	return cone
