extends CharacterBody3D
class_name Unit

const SpriteSheetFrames = preload("res://scripts/sprite_sheet_frames.gd")

const GRAVITY: float = 20.0
## The sheets in assets/art face right by default; flip_h mirrors them to face left.
const FLIP_DOT_THRESHOLD: float = 0.15
## Below this actual speed the unit is considered stopped (e.g. blocked by another unit).
const MOVING_SPEED_THRESHOLD: float = 0.15

@export var move_speed: float = 5.0
@export var rotation_speed: float = 10.0
@export var team_tint: Color = Color.WHITE

@export_group("Sprite Sheet")
@export var sprite_sheet: Texture2D = preload("res://assets/art/MinifolksVillagers2/Blue/Outline/MiniGatherer.png")
@export var sprite_cell_size: Vector2i = Vector2i(32, 32)
@export var idle_row: int = 0
@export var idle_frame_count: int = 4
@export var walk_row: int = 1
@export var walk_frame_count: int = 5

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var sprite: AnimatedSprite3D = $Sprite
@onready var selection_ring: MeshInstance3D = $SelectionRing

var selected: bool = false:
	set(value):
		selected = value
		selection_ring.visible = value

func _ready() -> void:
	if sprite_sheet:
		sprite.sprite_frames = SpriteSheetFrames.build(sprite_sheet, sprite_cell_size, {
			"idle": {"row": idle_row, "frames": idle_frame_count, "fps": 5.0, "loop": true},
			"walk": {"row": walk_row, "frames": walk_frame_count, "fps": 8.0, "loop": true},
		})
		sprite.play("idle")
	sprite.modulate = team_tint
	nav_agent.path_desired_distance = 0.5
	nav_agent.target_desired_distance = 0.5
	nav_agent.avoidance_enabled = true
	nav_agent.radius = 0.45
	nav_agent.max_speed = move_speed
	nav_agent.velocity_computed.connect(_on_velocity_computed)

func move_to(target_position: Vector3) -> void:
	nav_agent.target_position = target_position

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	var direction := Vector3.ZERO
	if not nav_agent.is_navigation_finished():
		var next_pos: Vector3 = nav_agent.get_next_path_position()
		direction = next_pos - global_position
		direction.y = 0.0
		if direction.length_squared() > 0.0001:
			direction = direction.normalized()

	var desired_velocity := Vector3(direction.x * move_speed, 0.0, direction.z * move_speed)
	nav_agent.set_velocity(desired_velocity)

func _on_velocity_computed(safe_velocity: Vector3) -> void:
	velocity.x = safe_velocity.x
	velocity.z = safe_velocity.z

	var flat_speed := Vector2(velocity.x, velocity.z).length()
	var is_moving := flat_speed > MOVING_SPEED_THRESHOLD
	if is_moving:
		var move_dir := Vector3(velocity.x, 0.0, velocity.z) / flat_speed
		var target_angle: float = atan2(move_dir.x, move_dir.z)
		rotation.y = lerp_angle(rotation.y, target_angle, rotation_speed * get_physics_process_delta_time())
		_update_facing(move_dir)

	if sprite.sprite_frames:
		var desired_anim := "walk" if is_moving else "idle"
		if sprite.animation != desired_anim:
			sprite.play(desired_anim)

	move_and_slide()

func _update_facing(direction: Vector3) -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return
	var cam_right: Vector3 = camera.global_transform.basis.x
	var screen_dot: float = direction.dot(cam_right)
	if absf(screen_dot) > FLIP_DOT_THRESHOLD:
		sprite.flip_h = screen_dot < 0.0
