class_name ToyProjectile
extends Node3D
## A shot in flight as a chunky plastic toy: an arrow, a ballista bolt, a
## glowing magic orb or a burning torch thrown at a building. Built from primitive meshes pointing along -Z, so
## WorldFeedback._fly_projectile_visual only has to turn it along its arc.
## Purely visual; the damage is the host's (Unit._tick_pending_projectiles).

enum Kind { ARROW, BOLT, ORB, TORCH }
@export var kind: Kind = Kind.ARROW
## The orb's colour, set by the shooter before it is added (Unit.projectile_tint).
var tint: Color = Color(0.75, 0.5, 1.0)

const ORB_RADIUS: float = 0.16
const TRAIL_LIFETIME: float = 0.4

static var _materials: Dictionary = {}
var _trail: GPUParticles3D = null

func _ready() -> void:
	match kind:
		Kind.ARROW:
			_build_arrow(1.0, Color(0.72, 0.52, 0.3))
		Kind.BOLT:
			_build_arrow(2.2, Color(0.45, 0.3, 0.18))
		Kind.ORB:
			_build_orb()
		Kind.TORCH:
			_build_torch()

## Shaft, head and two crossed fletchings, `size` times an arrow.
func _build_arrow(size: float, wood: Color) -> void:
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.028 * size
	shaft.bottom_radius = 0.028 * size
	shaft.height = 0.62 * size
	shaft.radial_segments = 6
	shaft.rings = 1
	shaft.material = _plastic(wood)
	_add_part(shaft, Vector3.ZERO, Vector3(-PI * 0.5, 0.0, 0.0))
	var head := CylinderMesh.new()
	head.top_radius = 0.0
	head.bottom_radius = 0.065 * size
	head.height = 0.14 * size
	head.radial_segments = 6
	head.rings = 1
	head.material = _plastic(Color(0.72, 0.74, 0.78))
	_add_part(head, Vector3(0.0, 0.0, -0.36 * size), Vector3(-PI * 0.5, 0.0, 0.0))
	for i in 2:
		var fletch := BoxMesh.new()
		fletch.size = Vector3(0.012 * size, 0.1 * size, 0.16 * size)
		fletch.material = _plastic(Color(0.85, 0.22, 0.18) if i == 0 else Color(0.95, 0.93, 0.88))
		_add_part(fletch, Vector3(0.0, 0.0, 0.24 * size), Vector3(0.0, 0.0, PI * 0.5 * i))

func _build_orb() -> void:
	var core := SphereMesh.new()
	core.radius = ORB_RADIUS
	core.height = ORB_RADIUS * 2.0
	core.radial_segments = 14
	core.rings = 7
	core.material = _plastic(tint, 1.6)
	_add_part(core, Vector3.ZERO, Vector3.ZERO)
	_trail = _puffs(tint, 24, TRAIL_LIFETIME, false)
	_trail.local_coords = false
	add_child(_trail)

## A wooden handle with a flame at its head (the end that leads), trailing
## and bursting in fire colours.
func _build_torch() -> void:
	tint = TORCH_FIRE
	var handle := CylinderMesh.new()
	handle.top_radius = 0.035
	handle.bottom_radius = 0.045
	handle.height = 0.5
	handle.radial_segments = 6
	handle.rings = 1
	handle.material = _plastic(Color(0.45, 0.3, 0.17))
	_add_part(handle, Vector3(0.0, 0.0, 0.1), Vector3(-PI * 0.5, 0.0, 0.0))
	for layer in [[0.11, 0.3, TORCH_FIRE], [0.06, 0.2, Color(1.0, 0.85, 0.4)]]:
		var flame := CylinderMesh.new()
		flame.top_radius = 0.0
		flame.bottom_radius = layer[0]
		flame.height = layer[1]
		flame.radial_segments = 6
		flame.rings = 1
		flame.material = _plastic(layer[2], 2.0)
		_add_part(flame, Vector3(0.0, 0.0, -0.15 - layer[1] * 0.5), Vector3(-PI * 0.5, 0.0, 0.0))
	_trail = _puffs(TORCH_FIRE, 20, TRAIL_LIFETIME, false)
	_trail.local_coords = false
	add_child(_trail)

const TORCH_FIRE: Color = Color(1.0, 0.45, 0.1)

func _add_part(mesh: Mesh, at: Vector3, rotation_euler: Vector3) -> void:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = at
	part.rotation = rotation_euler
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(part)

## Arrived: an orb leaves its trail to fade and bursts into a few sparkles;
## an arrow or bolt simply goes.
func land() -> void:
	if _trail != null and get_parent() != null:
		var parent := get_parent()
		var at := _trail.global_position
		remove_child(_trail)
		parent.add_child(_trail)
		_trail.global_position = at
		_trail.emitting = false
		get_tree().create_timer(TRAIL_LIFETIME + 0.1).timeout.connect(_trail.queue_free)
		var burst := _puffs(tint, 12, 0.35, true)
		parent.add_child(burst)
		burst.global_position = global_position
		burst.finished.connect(burst.queue_free)
	queue_free()

## Round glowing puffs in `colour`: a drifting trail, or a one-shot burst.
func _puffs(colour: Color, amount: int, lifetime: float, burst: bool) -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.08
	process.direction = Vector3.UP
	process.spread = 180.0
	process.initial_velocity_min = 1.5 if burst else 0.1
	process.initial_velocity_max = 3.0 if burst else 0.4
	process.gravity = Vector3(0, -3.0 if burst else 0.0, 0)
	process.scale_min = 0.6
	process.scale_max = 1.2
	var fade := Gradient.new()
	fade.set_color(0, colour.lightened(0.4))
	fade.set_color(1, Color(colour, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.billboard_keep_scale = true
	material.albedo_texture = RoundParticle.texture()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.2, 0.2)
	quad.material = material
	var particles := GPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = lifetime
	particles.process_material = process
	particles.draw_pass_1 = quad
	if burst:
		particles.one_shot = true
		particles.explosiveness = 1.0
	particles.emitting = true
	return particles

## One glossy plastic material per colour and glow, shared by every shot.
static func _plastic(colour: Color, glow: float = 0.0) -> StandardMaterial3D:
	var key := "%s/%s" % [colour.to_html(), glow]
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.3
	material.clearcoat_enabled = true
	material.clearcoat = 0.5
	if glow > 0.0:
		material.emission_enabled = true
		material.emission = colour
		material.emission_energy_multiplier = glow
	_materials[key] = material
	return material
