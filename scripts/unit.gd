extends CharacterBody3D
class_name Unit

const SpriteSheetFrames = preload("res://scripts/sprite_sheet_frames.gd")

const GRAVITY: float = 20.0
## The sheets in assets/art face right by default; flip_h mirrors them to face left.
const FLIP_DOT_THRESHOLD: float = 0.15
## Below this actual speed the unit is considered stopped (e.g. blocked by another unit).
const MOVING_SPEED_THRESHOLD: float = 0.15
const MOVE_ARRIVAL_DISTANCE: float = 0.5
## Drop-off points sit outside a building's avoidance-obstacle radius, so this
## needs more slack than a plain move order to reliably register as "arrived".
const DROPOFF_ARRIVAL_DISTANCE: float = 1.0

## The player's standing order. Move is one-shot; Gather loops (resource -> dropoff -> resource...)
## until interrupted by a new command or the resource is depleted.
enum Command { NONE, MOVE, GATHER }
## The current step within a command, e.g. Gather cycles through TO_RESOURCE -> GATHERING -> TO_DROPOFF.
enum Activity { IDLE, MOVING, TO_RESOURCE, GATHERING, TO_DROPOFF }

@export var move_speed: float = 5.0
@export var rotation_speed: float = 10.0
@export var team_tint: Color = Color.WHITE
## Which player controls this unit. The host is always peer 1.
@export var owner_peer_id: int = 1

@export_group("Sprite Sheet")
@export var sprite_sheet: Texture2D = preload("res://assets/art/MinifolksVillagers2/Blue/Outline/MiniGatherer.png")
@export var sprite_cell_size: Vector2i = Vector2i(32, 32)
@export var idle_row: int = 0
@export var idle_frame_count: int = 4
@export var walk_row: int = 1
@export var walk_frame_count: int = 5

@export_group("Gathering")
@export var can_gather: bool = true
## Higher levels gather faster and carry more; upgradable later.
@export var gather_level: int = 1
@export var carry_capacity: int = 10

@export_group("Status", "status_")
## Read/write here for debugging; normally driven by command_move / command_gather.
@export var status_command: Command = Command.NONE
@export var status_activity: Activity = Activity.IDLE
@export var status_carried_amount: int = 0
@export var status_carried_type: ResourceType = null

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var sprite: AnimatedSprite3D = $Sprite
@onready var selection_ring: MeshInstance3D = $SelectionRing

var selected: bool = false:
	set(value):
		selected = value
		selection_ring.visible = value

var target_resource: Gatherable = null
var dropoff_point: Node3D = null
var gather_timer: float = 0.0

func _ready() -> void:
	if sprite_sheet:
		sprite.sprite_frames = SpriteSheetFrames.build(sprite_sheet, sprite_cell_size, {
			"idle": {"row": idle_row, "frames": idle_frame_count, "fps": 5.0, "loop": true},
			"walk": {"row": walk_row, "frames": walk_frame_count, "fps": 8.0, "loop": true},
		})
		sprite.play("idle")
	sprite.modulate = team_tint
	nav_agent.path_desired_distance = 0.5
	nav_agent.target_desired_distance = MOVE_ARRIVAL_DISTANCE
	nav_agent.avoidance_enabled = true
	nav_agent.radius = 0.45
	nav_agent.max_speed = move_speed
	nav_agent.velocity_computed.connect(_on_velocity_computed)

## Raw navigation command; prefer command_move / command_gather which also manage status.
func move_to(target_position: Vector3) -> void:
	nav_agent.target_position = target_position

func command_move(target_position: Vector3) -> void:
	status_command = Command.MOVE
	status_activity = Activity.MOVING
	target_resource = null
	nav_agent.target_desired_distance = MOVE_ARRIVAL_DISTANCE
	move_to(target_position)

func command_gather(resource_node: Gatherable, dropoff: Node3D) -> void:
	if not can_gather or resource_node == null:
		return
	status_command = Command.GATHER
	target_resource = resource_node
	dropoff_point = dropoff
	_head_to_resource()

func _physics_process(delta: float) -> void:
	## Only the host simulates movement/gathering; other peers just display the
	## position/animation replicated by this unit's MultiplayerSynchronizer.
	if not is_multiplayer_authority():
		return

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	if status_activity == Activity.GATHERING:
		velocity.x = 0.0
		velocity.z = 0.0
		_tick_gathering(delta)
		if sprite.sprite_frames and sprite.animation != "idle":
			sprite.play("idle")
		move_and_slide()
		return

	if status_activity == Activity.TO_RESOURCE and nav_agent.is_navigation_finished():
		_start_gathering()
	elif status_activity == Activity.TO_DROPOFF and nav_agent.is_navigation_finished():
		_deposit_and_continue()

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

	if status_command == Command.MOVE and nav_agent.is_navigation_finished():
		status_activity = Activity.IDLE

func _update_facing(direction: Vector3) -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return
	var cam_right: Vector3 = camera.global_transform.basis.x
	var screen_dot: float = direction.dot(cam_right)
	if absf(screen_dot) > FLIP_DOT_THRESHOLD:
		sprite.flip_h = screen_dot < 0.0

func _head_to_resource() -> void:
	if not is_instance_valid(target_resource):
		_end_gather_command()
		return
	status_activity = Activity.TO_RESOURCE
	nav_agent.target_desired_distance = target_resource.gather_range
	move_to(target_resource.global_position)

func _start_gathering() -> void:
	if not is_instance_valid(target_resource):
		_end_gather_command()
		return
	status_activity = Activity.GATHERING
	gather_timer = 0.0
	status_carried_type = target_resource.resource_type

func _tick_gathering(delta: float) -> void:
	if not is_instance_valid(target_resource):
		_head_to_dropoff()
		return

	gather_timer += delta
	var interval: float = target_resource.resource_type.gather_interval / maxf(gather_level, 1.0)
	if gather_timer >= interval:
		gather_timer = 0.0
		var amount: int = target_resource.resource_type.gather_amount_per_tick * gather_level
		status_carried_amount += target_resource.gather(amount)

	if status_carried_amount >= carry_capacity or not is_instance_valid(target_resource):
		_head_to_dropoff()

func _head_to_dropoff() -> void:
	if dropoff_point == null or status_carried_amount <= 0:
		_head_to_resource()
		return
	status_activity = Activity.TO_DROPOFF
	nav_agent.target_desired_distance = DROPOFF_ARRIVAL_DISTANCE
	move_to(dropoff_point.global_position)

func _deposit_and_continue() -> void:
	if status_carried_amount > 0 and status_carried_type != null:
		ResourceStockpile.add(status_carried_type, status_carried_amount)
	status_carried_amount = 0
	status_carried_type = null

	if status_command == Command.GATHER and is_instance_valid(target_resource) and target_resource.amount_remaining > 0:
		_head_to_resource()
	else:
		_end_gather_command()

func _end_gather_command() -> void:
	target_resource = null
	status_command = Command.NONE
	status_activity = Activity.IDLE
