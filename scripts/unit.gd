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
## How much further than attack_range a target can drift before we bother re-approaching.
const ATTACK_LEASH_SLACK: float = 1.2

## The player's standing order. Move is one-shot; Gather/Attack loop
## (resource->dropoff->resource / target->next target) until interrupted or exhausted.
enum Command { NONE, MOVE, GATHER, ATTACK }
## The current step within a command, e.g. Gather cycles TO_RESOURCE -> GATHERING -> TO_DROPOFF.
enum Activity { IDLE, MOVING, TO_RESOURCE, GATHERING, TO_DROPOFF, TO_TARGET, ATTACKING, DEAD }

## main.gd (which owns a proven-reliable broadcast RPC channel) relays this to
## other peers; RPCs declared directly on this dynamically-spawned node were
## not reaching clients. Sprite flip is NOT networked this way — see _process().
signal animation_changed(anim_name: String)

@export var move_speed: float = 5.0
@export var rotation_speed: float = 10.0
@export var team_tint: Color = Color.WHITE
## Which player controls this unit. The host is always peer 1.
@export var owner_peer_id: int = 1
## How far this unit reveals fog of war around itself.
@export var vision_range: float = 8.0
## Set at spawn time from the ProducibleItem that produced this unit (see
## main.gd's _on_building_item_completed); released back to the owner's
## Population pool when this unit dies.
@export var population_cost: int = 1

@export_group("Sprite Sheet")
@export var sprite_sheet: Texture2D = preload("res://assets/art/MinifolksVillagers2/Blue/Outline/MiniGatherer.png")
@export var sprite_cell_size: Vector2i = Vector2i(32, 32)
@export var idle_row: int = 0
@export var idle_frame_count: int = 4
@export var walk_row: int = 1
@export var walk_frame_count: int = 5
@export var attack_row: int = 3
@export var attack_frame_count: int = 6
@export var death_row: int = 6
@export var death_frame_count: int = 4

@export_group("Gathering")
@export var can_gather: bool = true
## Higher levels gather faster and carry more; upgradable later.
@export var gather_level: int = 1
@export var carry_capacity: int = 10

@export_group("Combat")
@export var can_fight: bool = true
@export var max_health: int = 15
@export var attack_damage: int = 2
## Melee reach; how close a unit needs to be to land hits.
@export var attack_range: float = 1.2
@export var attack_cooldown: float = 1.0
## After a target dies, how far to look for another enemy before giving up and going idle.
@export var aggro_range: float = 6.0

@export_group("Status", "status_")
## Read/write here for debugging; normally driven by command_move / command_gather / command_attack.
@export var status_command: Command = Command.NONE
@export var status_activity: Activity = Activity.IDLE
@export var status_carried_amount: int = 0
@export var status_carried_type: ResourceType = null
## Was a plain (non-exported, non-networked) var, so it never showed a live
## value in the remote inspector and never updated on non-authoritative peers.
@export var status_current_health: int = 1

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var sprite: AnimatedSprite3D = $Sprite
@onready var selection_ring: MeshInstance3D = $SelectionRing
@onready var health_bar: Node3D = $HealthBar
@onready var health_bar_fill: Sprite3D = $HealthBar/Fill

var selected: bool = false:
	set(value):
		selected = value
		selection_ring.visible = value

## Captured from the scene's authored (full-health) scale so the fill's
## aspect-ratio/sizing lives in the scene file, not duplicated in script.
var _fill_base_scale_x: float = 1.0

var target_resource: Gatherable = null
var dropoff_point: Node3D = null
var gather_timer: float = 0.0
## Unit or ProductionBuilding — anything with owner_peer_id/current_health/take_damage().
var attack_target: Node3D = null
var attack_timer: float = 0.0
var _dying: bool = false

func _ready() -> void:
	status_current_health = max_health
	if health_bar_fill:
		_fill_base_scale_x = health_bar_fill.scale.x
	if sprite_sheet:
		sprite.sprite_frames = SpriteSheetFrames.build(sprite_sheet, sprite_cell_size, {
			"idle": {"row": idle_row, "frames": idle_frame_count, "fps": 5.0, "loop": true},
			"walk": {"row": walk_row, "frames": walk_frame_count, "fps": 8.0, "loop": true},
			"attack": {"row": attack_row, "frames": attack_frame_count, "fps": 10.0, "loop": false},
			"death": {"row": death_row, "frames": death_frame_count, "fps": 8.0, "loop": false},
		})
		sprite.play("idle")
	sprite.animation_finished.connect(_on_attack_animation_finished)
	sprite.modulate = team_tint
	nav_agent.path_desired_distance = 0.5
	nav_agent.target_desired_distance = MOVE_ARRIVAL_DISTANCE
	nav_agent.radius = 0.45
	nav_agent.max_speed = move_speed

	## Puppets (non-authority peers) never call set_velocity(), but avoidance
	## keeps emitting velocity_computed on its own once enabled regardless of
	## authority. status_activity isn't replicated, so a puppet's copy always
	## reads as IDLE and this callback would otherwise force the animation back
	## to idle every frame, fighting the animation RPCs from the real owner.
	if is_multiplayer_authority():
		nav_agent.avoidance_enabled = true
		nav_agent.velocity_computed.connect(_on_velocity_computed)

## Raw navigation command; prefer command_move / command_gather / command_attack which also manage status.
func move_to(target_position: Vector3) -> void:
	nav_agent.target_position = target_position

func command_move(target_position: Vector3) -> void:
	if status_activity == Activity.DEAD:
		return
	status_command = Command.MOVE
	status_activity = Activity.MOVING
	target_resource = null
	attack_target = null
	nav_agent.target_desired_distance = MOVE_ARRIVAL_DISTANCE
	move_to(target_position)

func command_gather(resource_node: Gatherable, dropoff: Node3D) -> void:
	if status_activity == Activity.DEAD or not can_gather or resource_node == null:
		return
	status_command = Command.GATHER
	attack_target = null
	target_resource = resource_node
	dropoff_point = dropoff
	_head_to_resource()

func command_attack(target: Node3D) -> void:
	if status_activity == Activity.DEAD or not can_fight or target == null or not is_instance_valid(target):
		return
	status_command = Command.ATTACK
	target_resource = null
	attack_target = target
	_head_to_target()

func take_damage(amount: int, attacker: Node3D = null) -> void:
	if not is_multiplayer_authority() or status_activity == Activity.DEAD:
		return
	status_current_health = maxi(status_current_health - amount, 0)
	if status_current_health <= 0:
		_die()
		return

	if can_fight and attacker != null and is_instance_valid(attacker):
		if status_command != Command.ATTACK:
			command_attack(attacker)
		CombatUtils.alert_nearby_allies(get_tree(), global_position, owner_peer_id, attacker)

func _physics_process(delta: float) -> void:
	## Only the host simulates movement/gathering/combat; other peers just display
	## the position/animation replicated by this unit's MultiplayerSynchronizer.
	if not is_multiplayer_authority():
		return

	if status_activity == Activity.DEAD:
		velocity = Vector3.ZERO
		move_and_slide()
		return

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	if status_activity == Activity.GATHERING:
		velocity.x = 0.0
		velocity.z = 0.0
		_tick_gathering(delta)
		if sprite.sprite_frames:
			_set_animation("idle")
		move_and_slide()
		return

	if status_activity == Activity.ATTACKING:
		velocity.x = 0.0
		velocity.z = 0.0
		_face_attack_target(delta)
		_tick_attacking(delta)
		move_and_slide()
		return

	if status_activity == Activity.TO_RESOURCE and nav_agent.is_navigation_finished():
		_start_gathering()
	elif status_activity == Activity.TO_DROPOFF and nav_agent.is_navigation_finished():
		_deposit_and_continue()
	elif status_activity == Activity.TO_TARGET and nav_agent.is_navigation_finished():
		_start_attacking()

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
	## NavigationAgent3D's avoidance keeps emitting this every physics frame once
	## armed, even after we stop calling set_velocity() — so states that manage
	## their own animation/velocity (and already call move_and_slide() themselves)
	## must ignore these stale callbacks rather than have them stomp the animation.
	if status_activity == Activity.GATHERING or status_activity == Activity.ATTACKING or status_activity == Activity.DEAD:
		return

	velocity.x = safe_velocity.x
	velocity.z = safe_velocity.z

	var flat_speed := Vector2(velocity.x, velocity.z).length()
	var is_moving := flat_speed > MOVING_SPEED_THRESHOLD
	if is_moving:
		var move_dir := Vector3(velocity.x, 0.0, velocity.z) / flat_speed
		var target_angle: float = atan2(move_dir.x, move_dir.z)
		rotation.y = lerp_angle(rotation.y, target_angle, rotation_speed * get_physics_process_delta_time())

	if sprite.sprite_frames:
		_set_animation("walk" if is_moving else "idle")

	move_and_slide()

	if status_command == Command.MOVE and nav_agent.is_navigation_finished():
		status_activity = Activity.IDLE

## Sprite flip is inherently viewer-dependent: whether a unit facing world
## direction X should mirror left/right on screen depends on which side of
## that direction YOUR OWN camera is looking from. Two players can be looking
## from opposite sides of the map at once, so this can never be a single
## networked value decided by whoever owns the unit — every peer (including
## the host) must derive it locally, every frame, from the unit's already-synced
## world rotation plus that peer's own current camera.
func _process(_delta: float) -> void:
	_update_health_bar_visual()

	var camera := get_viewport().get_camera_3d()
	if not camera:
		return
	var forward := Vector3(sin(rotation.y), 0.0, cos(rotation.y))
	var cam_right: Vector3 = camera.global_transform.basis.x
	var screen_dot: float = forward.dot(cam_right)
	if absf(screen_dot) > FLIP_DOT_THRESHOLD:
		sprite.flip_h = screen_dot < 0.0

## Reads from status_current_health, which is now a real synced property, so
## this displays correctly on every peer, not just the authoritative one.
func _update_health_bar_visual() -> void:
	if not health_bar:
		return
	var fraction: float = clampf(float(status_current_health) / float(maxi(max_health, 1)), 0.0, 1.0)
	health_bar.visible = fraction < 0.999 and status_activity != Activity.DEAD
	## Scale from center only (no position offset) so Fill can't visually drift
	## away from Background as the unit/camera rotates.
	health_bar_fill.scale.x = _fill_base_scale_x * maxf(fraction, 0.001)

## Applied locally immediately; main.gd relays the change to other peers via
## its own broadcast RPC (see note on the signal above). AnimatedSprite3D.animation
## resets playback to frame 0 whenever it's set (even to the same value), so this
## must only fire on an actual change, not continuously.
func _set_animation(anim_name: String) -> void:
	if sprite.animation == anim_name:
		return
	sprite.play(anim_name)
	animation_changed.emit(anim_name)

## Called exactly when a hit actually lands, so the swing is synced to
## attack_cooldown instead of looping on its own independent timer. Unlike
## _set_animation(), this always restarts the clip even if "attack" is
## already playing (e.g. a very short cooldown re-triggering mid-swing).
func _play_attack_swing() -> void:
	sprite.play("attack")
	animation_changed.emit("attack")

## "attack" is non-looping; once a swing finishes, settle back to idle until
## the next hit fires. This runs on every peer (not just the authority) since
## it just reacts to that peer's own local sprite finishing its own playback.
func _on_attack_animation_finished() -> void:
	if sprite.animation == "attack":
		_set_animation("idle")

## --- Gathering ---

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
		ResourceStockpile.add(owner_peer_id, status_carried_type, status_carried_amount)
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

## --- Combat ---

## Buildings have a large NavigationObstacle3D footprint that keeps agents
## pushed back well beyond a typical melee attack_range, so units must count
## that footprint as part of "close enough" or they'd approach, get stopped
## by avoidance short of attack_range, and never actually start attacking.
func _effective_attack_range() -> float:
	if attack_target is ProductionBuilding:
		return attack_range + attack_target.get_footprint_radius()
	return attack_range

func _head_to_target() -> void:
	if not _is_target_alive(attack_target):
		_find_new_target_or_idle()
		return
	status_activity = Activity.TO_TARGET
	nav_agent.target_desired_distance = _effective_attack_range()
	move_to(attack_target.global_position)

func _start_attacking() -> void:
	if not _is_target_alive(attack_target):
		_find_new_target_or_idle()
		return
	status_activity = Activity.ATTACKING
	attack_timer = attack_cooldown

func _face_attack_target(delta: float) -> void:
	if not is_instance_valid(attack_target):
		return
	var to_target := attack_target.global_position - global_position
	to_target.y = 0.0
	if to_target.length_squared() <= 0.0001:
		return
	var dir := to_target.normalized()
	rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), rotation_speed * delta)

func _tick_attacking(delta: float) -> void:
	if not _is_target_alive(attack_target):
		_find_new_target_or_idle()
		return

	var dist := global_position.distance_to(attack_target.global_position)
	if dist > _effective_attack_range() * ATTACK_LEASH_SLACK:
		_head_to_target()
		return

	attack_timer += delta
	if attack_timer >= attack_cooldown:
		attack_timer = 0.0
		_play_attack_swing()
		attack_target.take_damage(attack_damage, self)
		if not _is_target_alive(attack_target):
			_find_new_target_or_idle()

## Untyped parameter is deliberate: a statically-typed Node3D parameter makes
## GDScript type-check the argument before the function body even runs, and
## that check throws on an already-freed object instead of letting
## is_instance_valid() safely catch it below.
func _is_target_alive(target) -> bool:
	if not is_instance_valid(target):
		return false
	if target is Unit:
		return target.status_activity != Activity.DEAD
	if target is ProductionBuilding:
		return not target.is_destroyed
	return false

func _find_new_target_or_idle() -> void:
	if status_command != Command.ATTACK:
		return
	var nearest: Unit = _find_nearest_enemy_in_range(aggro_range)
	if nearest:
		attack_target = nearest
		_head_to_target()
	else:
		attack_target = null
		status_command = Command.NONE
		status_activity = Activity.IDLE

func _find_nearest_enemy_in_range(search_range: float) -> Unit:
	var nearest: Unit = null
	var nearest_dist := search_range
	for node in get_tree().get_nodes_in_group("units"):
		if node == self or not (node is Unit):
			continue
		var other: Unit = node
		if other.owner_peer_id == owner_peer_id or not _is_target_alive(other):
			continue
		var dist := global_position.distance_to(other.global_position)
		if dist <= nearest_dist:
			nearest = other
			nearest_dist = dist
	return nearest

func _die() -> void:
	if _dying:
		return
	_dying = true
	status_activity = Activity.DEAD
	status_command = Command.NONE
	attack_target = null
	target_resource = null
	## take_damage() (the only caller of _die()) already gates on
	## is_multiplayer_authority(), so this only ever runs once, on the host.
	Population.release(owner_peer_id, population_cost)

	if sprite.sprite_frames and sprite.sprite_frames.has_animation("death"):
		_set_animation("death")
		var frame_count: int = sprite.sprite_frames.get_frame_count("death")
		var fps: float = sprite.sprite_frames.get_animation_speed("death")
		await get_tree().create_timer(frame_count / maxf(fps, 1.0)).timeout
	queue_free()
