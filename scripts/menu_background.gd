extends Node3D
## The live diorama behind the main menu (see MenuBackdrop, which renders it
## small and blurs it): a town centre with villagers chopping at the treelines
## and mining a gold pile, seen from the RTS camera's angle as it slowly
## circles the town.
##
## None of it is the real game — no Main, no Units, no Network — just the same
## models and figures, walked about by this script. So it can't leave
## match state behind for the game the player then starts.
##
## Wind normally comes from FogOfWar, which walks the tree for grass materials
## and drives their `wind_velocity` / `wind_offset` every frame. There is no
## FogOfWar out here, so this does the same job for the backdrop's foliage.

const TOWN_CENTRE: PackedScene = preload("res://assets/art/Models/TownBuildings/TownCentre.glb")
const GRASS_SHADER: Shader = preload("res://shaders/terrain/binbun_foliage.gdshader")
const GOLD_DEPOSIT: PackedScene = preload("res://assets/art/Models/TownBuildings/GoldDeposit.glb")
const PINES: Array[PackedScene] = [
	preload("res://assets/art/Trees/tree_pine_low.glb"),
	preload("res://assets/art/Trees/tree_pine_low_2.glb"),
]
## The villager figures the game draws, by job: tool in hand going out and
## working, the load on his back coming home.
const VILLAGER_FIGURE: String = "res://assets/art/Models/Units/Villager_%s.glb"
## The blue the old backdrop sheets were drawn in, as a team colour.
const VILLAGER_TINT: Color = Color(0.25, 0.45, 0.9)

## Radians per second the wind direction wanders, so the field never looks looped.
const DRIFT_RATE: float = 0.08
const STRENGTH: float = 0.35
## Matches FogOfWar's scroll rate so the backdrop and the game look alike.
const OFFSET_SCALE: float = 0.01

## Where the town sits on this terrain; the layout below is relative to it.
const CENTRE_XZ := Vector2(40.0, -70.0)
## The RTS camera's look at its default zoom (RtsCamera.DEFAULT_ZOOM), a
## little steeper so the terrain's edge stays out of shot.
const CAMERA_PITCH_DEGREES: float = 40.0
const CAMERA_DISTANCE: float = 18.0
const CAMERA_FOV: float = 45.0
## The point the camera circles, relative to the centre: between the town
## centre and the gold pile, so both stay in shot all the way round.
const CAMERA_FOCUS := Vector3(-2.0, 0.0, -3.0)
## Radians per second; about four minutes a turn.
const ORBIT_RATE: float = TAU / 240.0

const TOWN_CENTRE_RADIUS: float = 3.0
## [centre offset, tree count, spread] per grove.
const GROVES: Array = [
	[Vector2(-10.0, -1.0), 6, 2.4],
	[Vector2(-3.0, -11.0), 8, 2.8],
	[Vector2(9.0, -10.0), 9, 3.0],
	[Vector2(9.0, 6.0), 7, 2.6],
	[Vector2(-7.0, 10.0), 8, 2.8],
]
const GOLD_OFFSET := Vector2(-5.0, -5.5)
## [grove index, villager count]; -1 is the gold pile.
const CREWS: Array = [[2, 4], [1, 3], [0, 2], [3, 3], [4, 2], [-1, 5]]

const WALK_SPEED: float = 2.4
const WORK_SECONDS := Vector2(5.0, 9.0)
const DROP_SECONDS: float = 0.8
## The toy hop of a walking figure and the rock of one at work.
const HOP_HEIGHT: float = 0.1
const HOP_RATE: float = 11.0
const WORK_RATE: float = 6.0
const WORK_TILT: float = 0.22

enum Job { WALK_OUT, WORK, WALK_BACK, DROP }

var _materials: Array[ShaderMaterial] = []
## The Binbun grass, shown or hidden with the Grass setting as FogOfWar does
## in a match.
var _grass_nodes: Array[GeometryInstance3D] = []
var _direction: float = 0.7
var _offset: Vector2 = Vector2.ZERO
var _rng := RandomNumberGenerator.new()
var _centre: Vector3
var _camera: Camera3D
var _orbit: float = 0.0
## Each villager: {node, tool, carry, job, timer, pos, work, drop, face, t}.
var _villagers: Array[Dictionary] = []

func _ready() -> void:
	_rng.seed = 20260930
	var world_env := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env and CompatLighting.is_active():
		world_env.environment = world_env.environment.duplicate()
		CompatLighting.apply(world_env.environment)
	_centre = _ground(CENTRE_XZ)
	_camera = get_node_or_null("Camera3D")
	if _camera != null:
		_camera.fov = CAMERA_FOV
	_place_camera()
	var town_centre := _place(TOWN_CENTRE.instantiate(), CENTRE_XZ, 0.0)
	GroundStamps.stamp_building(town_centre, TOWN_CENTRE_RADIUS)
	var groves: Array[Array] = []
	for grove in GROVES:
		groves.append(_plant_grove(CENTRE_XZ + grove[0], grove[1], grove[2]))
	var gold := CENTRE_XZ + GOLD_OFFSET
	_place(GOLD_DEPOSIT.instantiate(), gold, _rng.randf() * TAU)
	GroundStamps.stamp_building(_place(Node3D.new(), gold, 0.0), 1.5)
	for crew in CREWS:
		for i in crew[1]:
			if crew[0] < 0:
				var around := Vector2.from_angle(PI * 0.5 + _rng.randf_range(-1.3, 1.3)) * 1.6
				_add_villager("gold", gold + around, gold)
			else:
				var trees: Array = groves[crew[0]]
				var tree: Vector2 = trees[_rng.randi() % trees.size()]
				## Stand on the town's side of the tree, so he's in view.
				var toward_town := (CENTRE_XZ - tree).normalized()
				_add_villager("wood", tree + toward_town * 1.2, tree)
	## TerraBrush builds its foliage around the active camera over the first few
	## frames, so the sweep is deferred rather than run against an empty tree.
	await get_tree().process_frame
	await get_tree().process_frame
	_collect(self)
	_apply_grass_visibility()
	Settings.changed.connect(_on_setting_changed)

func _place_camera() -> void:
	if _camera == null:
		return
	var focus := _centre + CAMERA_FOCUS
	var pitch := deg_to_rad(CAMERA_PITCH_DEGREES)
	var boom := Vector3(0.0, sin(pitch), cos(pitch)).rotated(Vector3.UP, _orbit)
	_camera.position = focus + boom * CAMERA_DISTANCE
	_camera.look_at(focus, Vector3.UP)

func _ground(xz: Vector2) -> Vector3:
	var terrain: Node = get_node_or_null("Terrain")
	var height: float = 0.0
	if terrain != null and terrain.has_method("getHeightAtPosition"):
		height = float(terrain.call("getHeightAtPosition", xz.x, xz.y, true))
	return Vector3(xz.x, height, xz.y)

func _place(node: Node3D, xz: Vector2, yaw: float) -> Node3D:
	add_child(node)
	node.position = _ground(xz)
	node.rotation.y = yaw
	return node

## Returns where the trees stand, for the lumberjacks.
func _plant_grove(centre: Vector2, count: int, spread: float) -> Array:
	var spots: Array = []
	for i in count:
		var spot := centre + Vector2.from_angle(_rng.randf() * TAU) * sqrt(_rng.randf()) * spread
		var tree := _place(PINES[_rng.randi() % PINES.size()].instantiate(), spot, _rng.randf() * TAU)
		tree.scale = Vector3.ONE * _rng.randf_range(0.85, 1.2)
		spots.append(spot)
	return spots

func _add_villager(job: String, work: Vector2, target: Vector2) -> void:
	var node := Node3D.new()
	add_child(node)
	var tool := _figure(job)
	var carry := _figure("carry_" + job)
	node.add_child(tool)
	node.add_child(carry)
	## Each one drops off at his own spot round the town centre's edge.
	var drop := CENTRE_XZ + (work - CENTRE_XZ).normalized().rotated(_rng.randf_range(-0.35, 0.35)) \
			* (TOWN_CENTRE_RADIUS + 0.8)
	var villager := {
		"node": node,
		"tool": tool,
		"carry": carry,
		"t": _rng.randf() * TAU,
		"work": work,
		"drop": drop,
		"face": target,
		"pos": work.lerp(drop, _rng.randf()),
		"job": Job.WALK_OUT if _rng.randf() < 0.5 else Job.WALK_BACK,
		"timer": 0.0,
	}
	## Start some at their work so the scene is busy from the first frame.
	if _rng.randf() < 0.4:
		villager.pos = work
		villager.job = Job.WORK
		villager.timer = _rng.randf_range(0.5, WORK_SECONDS.y)
	_villagers.append(villager)
	_face(villager, (target - work) * (1.0 if villager.job == Job.WALK_OUT else -1.0))
	_show(villager)

func _figure(role: String) -> MultiMeshInstance3D:
	var model: PackedScene = load(VILLAGER_FIGURE % role)
	return FigureMaterials.standalone(Unit.figure_mesh(model), null, VILLAGER_TINT)

func _process(delta: float) -> void:
	_orbit = wrapf(_orbit + ORBIT_RATE * delta, 0.0, TAU)
	_place_camera()
	for villager in _villagers:
		_step(villager, delta)
	_blow_wind(delta)

func _step(villager: Dictionary, delta: float) -> void:
	villager.t += delta
	match villager.job:
		Job.WALK_OUT, Job.WALK_BACK:
			var goal: Vector2 = villager.work if villager.job == Job.WALK_OUT else villager.drop
			var pos: Vector2 = villager.pos
			var gap := goal - pos
			if gap.length() <= WALK_SPEED * delta:
				villager.pos = goal
				if villager.job == Job.WALK_OUT:
					villager.job = Job.WORK
					villager.timer = _rng.randf_range(WORK_SECONDS.x, WORK_SECONDS.y)
				else:
					villager.job = Job.DROP
					villager.timer = DROP_SECONDS
			else:
				villager.pos = pos + gap.normalized() * WALK_SPEED * delta
				_face(villager, gap)
		Job.WORK, Job.DROP:
			villager.timer -= delta
			if villager.timer <= 0.0:
				villager.job = Job.WALK_BACK if villager.job == Job.WORK else Job.WALK_OUT
	_show(villager)

func _show(villager: Dictionary) -> void:
	var node: Node3D = villager.node
	var t: float = villager.t
	var lift := 0.0
	var tilt := 0.0
	match villager.job:
		Job.WORK:
			_face(villager, (villager.face as Vector2) - (villager.pos as Vector2))
			## Leaning into each stroke of the axe or pick.
			tilt = maxf(sin(t * WORK_RATE), 0.0) * WORK_TILT
		Job.WALK_OUT, Job.WALK_BACK:
			lift = absf(sin(t * HOP_RATE)) * HOP_HEIGHT
	node.position = _ground(villager.pos) + Vector3.UP * lift
	node.rotation.x = tilt
	## Tools out and at work; the load on his back coming home and dropping it.
	var carrying: bool = villager.job == Job.WALK_BACK or villager.job == Job.DROP
	(villager.carry as Node3D).visible = carrying
	(villager.tool as Node3D).visible = not carrying

## Turns the figure to face along `direction` (in XZ).
func _face(villager: Dictionary, direction: Vector2) -> void:
	if direction.is_zero_approx():
		return
	(villager.node as Node3D).rotation.y = atan2(direction.x, direction.y)

func _collect(node: Node) -> void:
	if node is GeometryInstance3D:
		var material := (node as GeometryInstance3D).material_override as ShaderMaterial
		if material != null and material.shader != null \
				and material.shader.code.contains("wind_velocity"):
			_materials.append(material)
			if material.shader == GRASS_SHADER:
				_grass_nodes.append(node)
	for child in node.get_children():
		_collect(child)

func _on_setting_changed(key: StringName) -> void:
	if key == &"grass":
		_apply_grass_visibility()

func _apply_grass_visibility() -> void:
	var show_grass: bool = Settings.get_value(&"grass")
	for node in _grass_nodes:
		node.visible = show_grass

func _blow_wind(delta: float) -> void:
	if _materials.is_empty():
		return
	var strength: float = STRENGTH if Settings.get_value(&"wind") else 0.0
	_direction += DRIFT_RATE * delta
	var velocity := Vector2(cos(_direction), sin(_direction)) * strength
	_offset += velocity * OFFSET_SCALE * delta
	for material in _materials:
		material.set_shader_parameter("wind_velocity", velocity)
		material.set_shader_parameter("wind_offset", _offset)
