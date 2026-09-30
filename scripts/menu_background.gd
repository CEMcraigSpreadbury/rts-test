extends Node3D
## The live diorama behind the main menu (see MenuBackdrop, which renders it
## small and blurs it): a town centre with villagers chopping at the treelines
## and mining a gold pile, seen from the RTS camera's angle as it slowly
## circles the town.
##
## None of it is the real game — no Main, no Units, no Network — just the same
## models and sprite sheets, walked about by this script. So it can't leave
## match state behind for the game the player then starts.
##
## Wind normally comes from FogOfWar, which walks the tree for grass materials
## and drives their `wind_velocity` / `wind_offset` every frame. There is no
## FogOfWar out here, so this does the same job for the backdrop's foliage.

const TOWN_CENTRE: PackedScene = preload("res://assets/art/Models/TownBuildings/TownCentre.glb")
const GOLD_DEPOSIT: PackedScene = preload("res://assets/art/Models/TownBuildings/GoldDeposit.glb")
const PINES: Array[PackedScene] = [
	preload("res://assets/art/AmiPolyGon_Forest_Free_Pack/AmiPolyGon_Forest_Free_Pack/GLB/tree_pine_1.glb"),
	preload("res://assets/art/AmiPolyGon_Forest_Free_Pack/AmiPolyGon_Forest_Free_Pack/GLB/tree_pine_2.glb"),
]
const LUMBERJACK_SHEET: Texture2D = preload("res://assets/art/MinifolksVillagers2/Blue/Outline/MiniLumberjack.png")
const MINER_SHEET: Texture2D = preload("res://assets/art/MinifolksVillagers2/Blue/Outline/MiniMiner.png")
## Rows of the Minifolks work sheets, as Unit.WORK_ROLE_CLIPS has them.
const LUMBERJACK_CLIPS: Dictionary = {
	"idle": {"row": 0, "frames": 4, "fps": 5.0},
	"walk": {"row": 3, "frames": 6, "fps": 8.0},
	"work": {"row": 2, "frames": 6, "fps": 8.0},
}
const MINER_CLIPS: Dictionary = {
	"idle": {"row": 0, "frames": 4, "fps": 5.0},
	"walk": {"row": 3, "frames": 6, "fps": 8.0},
	"work": {"row": 5, "frames": 5, "fps": 8.0},
}

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
## As a Unit's sprite.
const SPRITE_PIXEL_SIZE: float = 0.05
const SPRITE_LIFT: float = 0.628

enum Job { WALK_OUT, WORK, WALK_BACK, DROP }

var _materials: Array[ShaderMaterial] = []
var _direction: float = 0.7
var _offset: Vector2 = Vector2.ZERO
var _rng := RandomNumberGenerator.new()
var _centre: Vector3
var _camera: Camera3D
var _orbit: float = 0.0
## Each villager: {sprite, job, timer, pos, work, drop, face}.
var _villagers: Array[Dictionary] = []

func _ready() -> void:
	_rng.seed = 20260930
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
				_add_villager(MINER_SHEET, MINER_CLIPS, gold + around, gold)
			else:
				var trees: Array = groves[crew[0]]
				var tree: Vector2 = trees[_rng.randi() % trees.size()]
				## Stand on the town's side of the tree, so he's in view.
				var toward_town := (CENTRE_XZ - tree).normalized()
				_add_villager(LUMBERJACK_SHEET, LUMBERJACK_CLIPS, tree + toward_town * 1.2, tree)
	## TerraBrush builds its foliage around the active camera over the first few
	## frames, so the sweep is deferred rather than run against an empty tree.
	await get_tree().process_frame
	await get_tree().process_frame
	_collect(self)

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

func _add_villager(sheet: Texture2D, clips: Dictionary, work: Vector2, target: Vector2) -> void:
	var animations := {}
	for clip in clips:
		animations[clip] = clips[clip].merged({"loop": true})
	var sprite := AnimatedSprite3D.new()
	sprite.sprite_frames = SpriteSheetFrames.build(sheet, Vector2i(32, 32), animations)
	sprite.pixel_size = SPRITE_PIXEL_SIZE
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded = true
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	## Each one drops off at his own spot round the town centre's edge.
	var drop := CENTRE_XZ + (work - CENTRE_XZ).normalized().rotated(_rng.randf_range(-0.35, 0.35)) \
			* (TOWN_CENTRE_RADIUS + 0.8)
	var villager := {
		"sprite": sprite,
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
	sprite.frame = _rng.randi() % 4
	_show(villager)

func _process(delta: float) -> void:
	_orbit = wrapf(_orbit + ORBIT_RATE * delta, 0.0, TAU)
	_place_camera()
	for villager in _villagers:
		_step(villager, delta)
	_blow_wind(delta)

func _step(villager: Dictionary, delta: float) -> void:
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
	var sprite: AnimatedSprite3D = villager.sprite
	sprite.position = _ground(villager.pos) + Vector3.UP * SPRITE_LIFT
	var anim: StringName
	match villager.job:
		Job.WORK:
			anim = &"work"
			_face(villager, (villager.face as Vector2) - (villager.pos as Vector2))
		Job.DROP:
			anim = &"idle"
		_:
			anim = &"walk"
	if sprite.animation != anim:
		sprite.play(anim)

## The sheets face right; mirror them when heading screen-left.
func _face(villager: Dictionary, direction: Vector2) -> void:
	if _camera == null or direction.is_zero_approx():
		return
	var right := _camera.global_transform.basis.x
	(villager.sprite as AnimatedSprite3D).flip_h = right.x * direction.x + right.z * direction.y < 0.0

func _collect(node: Node) -> void:
	if node is GeometryInstance3D:
		var material := (node as GeometryInstance3D).material_override as ShaderMaterial
		if material != null and material.shader != null \
				and material.shader.code.contains("wind_velocity"):
			_materials.append(material)
	for child in node.get_children():
		_collect(child)

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
