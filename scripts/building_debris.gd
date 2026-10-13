class_name BuildingDebris
extends Node3D
## A building breaking like a toy: chunky plastic blocks in its own colours
## burst out of it, tumble, bounce on the ground and shrink away. Purely
## visual, so every peer plays it locally (ProductionBuilding._play_break).
## Added to the building's parent, not the building, which is freed while
## the pieces are still in the air.

const GRAVITY: float = 18.0
const BOUNCE: float = 0.35
const GROUND_FRICTION: float = 0.55
const LIFE_MIN: float = 1.5
const LIFE_MAX: float = 2.2
const SHRINK_TIME: float = 0.3
## Share of the pieces in the owner's colour, so a fallen building still
## says whose it was.
const TEAM_SHARE: float = 0.3

static var _materials: Dictionary = {}

var _pieces: Array[MeshInstance3D] = []
var _velocity: Array[Vector3] = []
var _spin: Array[Vector3] = []
var _life: Array[float] = []
var _base_scale: Array[Vector3] = []
var _half_height: Array[float] = []
var _ground_y: float = 0.0
var _age: float = 0.0
var _end: float = 0.0

## `box`: the building's world bounds. `colours`: what its surfaces are
## painted, `team`: its owner's colour.
static func burst(parent: Node, box: AABB, colours: Array[Color], team: Color, count: int) -> BuildingDebris:
	var debris := BuildingDebris.new()
	parent.add_child(debris)
	debris._spawn(box, colours, team, count)
	return debris

func _spawn(box: AABB, colours: Array[Color], team: Color, count: int) -> void:
	_ground_y = box.position.y
	var centre := box.get_center()
	var reach := maxf(box.size.x, box.size.z) * 0.5
	var size_scale := clampf(reach * 0.32, 0.18, 0.55)
	for i in count:
		var piece := MeshInstance3D.new()
		var dims := Vector3(randf_range(0.6, 1.2), randf_range(0.4, 0.9), randf_range(0.6, 1.2)) * size_scale
		if randf() < 0.25:
			var wedge := PrismMesh.new()
			wedge.size = dims
			piece.mesh = wedge
		else:
			var block := BoxMesh.new()
			block.size = dims
			piece.mesh = block
		var colour: Color = team if (colours.is_empty() or randf() < TEAM_SHARE) else colours[randi() % colours.size()]
		piece.material_override = _material_for(colour)
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(piece)
		piece.global_position = Vector3(
				centre.x + randf_range(-0.5, 0.5) * box.size.x * 0.7,
				lerpf(box.position.y, box.end.y, randf_range(0.3, 0.9)),
				centre.z + randf_range(-0.5, 0.5) * box.size.z * 0.7)
		piece.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		var out := Vector3(piece.global_position.x - centre.x, 0.0, piece.global_position.z - centre.z)
		if out.length_squared() < 0.01:
			out = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
		out = out.normalized() * randf_range(2.0, 5.0) * clampf(reach / 1.5, 0.7, 1.6)
		_pieces.append(piece)
		_velocity.append(out + Vector3.UP * randf_range(4.0, 7.5))
		_spin.append(Vector3(randf_range(-9.0, 9.0), randf_range(-6.0, 6.0), randf_range(-9.0, 9.0)))
		var life := randf_range(LIFE_MIN, LIFE_MAX)
		_life.append(life)
		_end = maxf(_end, life)
		_base_scale.append(Vector3.ONE)
		_half_height.append(dims.y * 0.5)

func _process(delta: float) -> void:
	_age += delta
	if _age >= _end:
		queue_free()
		return
	for i in _pieces.size():
		var piece := _pieces[i]
		var v := _velocity[i]
		v.y -= GRAVITY * delta
		var p := piece.global_position + v * delta
		var floor_y := _ground_y + _half_height[i]
		if p.y < floor_y:
			p.y = floor_y
			if v.y < -1.0:
				v.y = -v.y * BOUNCE
				v.x *= GROUND_FRICTION
				v.z *= GROUND_FRICTION
				_spin[i] *= 0.5
			else:
				v = Vector3(v.x * 0.9, 0.0, v.z * 0.9)
				_spin[i] *= 0.9
		_velocity[i] = v
		piece.global_position = p
		piece.rotation += _spin[i] * delta
		var left := _life[i] - _age
		piece.scale = _base_scale[i] * clampf(left / SHRINK_TIME, 0.0, 1.0)
		piece.visible = left > 0.0

## One shared glossy plastic material per colour.
static func _material_for(colour: Color) -> StandardMaterial3D:
	var key := colour.to_html(false)
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.35
	material.clearcoat_enabled = true
	material.clearcoat = 0.45
	material.clearcoat_roughness = 0.3
	_materials[key] = material
	return material
