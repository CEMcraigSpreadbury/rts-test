class_name DustPool
extends MultiMeshInstance3D
## Every walking unit's dust, drawn together: a unit emits a puff at its feet a
## few times a second (Unit._process_visuals) into a ring buffer of instances
## in one MultiMesh, which shaders/dust_puff.gdshader animates from each
## puff's age — instead of each unit carrying a particle emitter of its own
## (one draw and one particle update per unit, every frame, which was most of
## an army's cost on screen once its sprites were batched, see SpriteBatcher).

## The match's pool, for units to emit into (every peer has one).
static var current: DustPool = null

const PUFF_SHADER: Shader = preload("res://shaders/dust_puff.gdshader")
## Puffs a walking unit emits per second, and how far from its feet, as its own
## emitter had them (8 particles over a 0.5 s lifetime, a 0.5 m sphere).
const PUFFS_PER_SECOND: float = 16.0
const SPREAD: float = 0.5
const QUAD_SIZE: float = 0.12
## Puffs alive at once: 8 per walking unit, for 512 walking in view.
const CAPACITY: int = 4096

var _next: int = 0
var _clock: float = 0.0
## Its own, so drawing dust never shifts the game's random numbers.
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(QUAD_SIZE, QUAD_SIZE)
	var material := ShaderMaterial.new()
	material.shader = PUFF_SHADER
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = quad
	multimesh.instance_count = CAPACITY
	## Nothing spawned yet: every slot long dead.
	for i in CAPACITY:
		multimesh.set_instance_custom_data(i, Color(-100.0, 0.0, 0.0, 0.0))
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-2048, -64, -2048), Vector3(4096, 256, 4096))

func _enter_tree() -> void:
	current = self

func _exit_tree() -> void:
	if current == self:
		current = null

func _process(delta: float) -> void:
	_clock += delta
	set_instance_shader_parameter(&"now", _clock)

func puff(at: Vector3) -> void:
	var offset := Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)).limit_length(1.0) * SPREAD
	multimesh.set_instance_transform(_next, Transform3D(Basis(), at + offset))
	multimesh.set_instance_custom_data(_next, Color(_clock, _rng.randf(), _rng.randf(), _rng.randf()))
	_next = (_next + 1) % CAPACITY
