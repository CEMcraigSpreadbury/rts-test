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
## Building footprints push agents back via avoidance same as for melee attacks.
const BUILD_ARRIVAL_DISTANCE: float = 1.0
## How often an attack-moving/patrolling unit checks for nearby enemies to engage.
const ENEMY_SCAN_INTERVAL: float = 0.25
## Multiplier applied when an attacker's damage_type matches its target's
## weak_to — see take_damage().
const WEAKNESS_DAMAGE_MULTIPLIER: float = 1.5

## The player's standing order. Move is one-shot; Gather/Attack/Build loop or
## hold (resource->dropoff->resource / target->next target / stay building
## until done) until interrupted or exhausted.
enum Command { NONE, MOVE, GATHER, ATTACK, BUILD, ATTACK_MOVE, PATROL }
## The current step within a command, e.g. Gather cycles TO_RESOURCE -> GATHERING -> TO_DROPOFF.
enum Activity { IDLE, MOVING, TO_RESOURCE, GATHERING, TO_DROPOFF, TO_TARGET, ATTACKING, TO_BUILD_SITE, BUILDING, DEAD }
## Rock-paper-scissors combat: NONE means "no special type" (deals no bonus,
## takes no bonus). MAGIC has no attacker yet — reserved for future spellcasters.
enum DamageType { NONE, SPEAR, CAVALRY, PIERCE, MAGIC }
## Distinct from Command above — this exists purely to pick which On ***
## Sound Effects array to play from (see play_order_sound()), and needs its
## own STOP entry since command_stop() results in Command.NONE, which
## wouldn't otherwise distinguish "stopped" from "never given an order".
enum OrderSoundKind { MOVE, ATTACK, PATROL, BUILD, STOP, GATHER }

## main.gd (which owns a proven-reliable broadcast RPC channel) relays this to
## other peers; RPCs declared directly on this dynamically-spawned node were
## not reaching clients. Sprite flip is NOT networked this way — see _process().
signal animation_changed(anim_name: String)
## Relayed the same way (see main.gd), so every peer can spawn its own purely
## cosmetic projectile visual flying toward the target. Real damage timing is
## tracked independently on the host via _pending_projectile_hits, not this.
signal projectile_fired(target: Node3D)

## What this unit type is called in UI (info panel title, etc.) — unlike the
## scene node's own .name, this can't get an auto-incremented suffix (e.g.
## "Unit2") when several of the same unit are siblings under Units.
@export var display_name: String = "Villager"
@export var move_speed: float = 5.0
@export var rotation_speed: float = 10.0
@export var team_tint: Color = Color.WHITE
## Which player controls this unit. The host is always peer 1.
@export var owner_peer_id: int = 1
## How far this unit reveals fog of war around itself.
@export var vision_range: float = 8.0
## One is picked at random and played through select_audio_player whenever
## this unit becomes newly selected (see main.gd's selection code — never
## replayed for a selection refresh, only an actual new selection action).
@export var on_select_sound_effects: Array[AudioStream] = []

@export_group("Cost")
## The single source of truth for what this unit costs to produce — edit it
## right here rather than on the building's ProducibleItem, which just reads
## these back via get_costs()/get_population_cost() at enqueue time.
@export var costs: Array[ResourceCost] = []
## Released back to the owner's Population pool when this unit dies.
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
## Only played by units with can_gather; harmless (just unused) otherwise.
@export var gather_row: int = 2
@export var gather_frame_count: int = 10

@export_group("Gathering")
@export var can_gather: bool = true
## Higher levels gather faster and carry more; upgradable later.
@export var gather_level: int = 1
@export var carry_capacity: int = 10
## Whether this unit can be sent to help construct a building.
@export var can_build: bool = true

@export_group("Combat")
@export var can_fight: bool = true
@export var max_health: int = 15
@export var attack_damage: int = 2
## Melee reach; how close a unit needs to be to land hits.
@export var attack_range: float = 1.2
@export var attack_cooldown: float = 1.0
## After a target dies, how far to look for another enemy before giving up and going idle.
@export var aggro_range: float = 6.0
## What kind of damage this unit's attacks count as, for the weak_to rock-
## paper-scissors check below. NONE if this unit has no special damage type.
@export var damage_type: DamageType = DamageType.NONE
## Attacks whose damage_type matches this deal WEAKNESS_DAMAGE_MULTIPLIER
## bonus damage to this unit. NONE means immune to the whole system.
@export var weak_to: DamageType = DamageType.NONE
## Null = melee (instant damage on cooldown, like today). Set = ranged: each
## cooldown tick fires a projectile that travels at projectile_speed and only
## applies damage once it actually arrives (see _tick_pending_projectiles) —
## the target can die or leave range before it lands. The scene is spawned as
## a purely local visual by main.gd (see projectile_fired below); this array
## just tracks the real, authoritative delayed-damage timers on the host.
@export var projectile_scene: PackedScene = null
@export var projectile_speed: float = 14.0

@export_group("Order Sounds")
## One is picked at random and played through unit_audio_player whenever this
## unit is actually given the matching player order (see main.gd's
## _play_unit_order_sound) — not for automatic behavior like auto-retaliation
## or idle standing-guard engaging an enemy on its own, only real orders.
@export var on_move_sound_effects: Array[AudioStream] = []
## Shared by a plain Attack order and an Attack-Move that engages a target —
## same voice line either way.
@export var on_attack_sound_effects: Array[AudioStream] = []
@export var on_patrol_sound_effects: Array[AudioStream] = []
@export var on_build_sound_effects: Array[AudioStream] = []
@export var on_stop_sound_effects: Array[AudioStream] = []
@export var on_gather_sound_effects: Array[AudioStream] = []

@export_group("Monarch")
## Empty means this unit type can never be promoted. Non-empty defines what a
## promoted unit of this type can do — set directly on the unit scene, same
## convention as costs/population_cost, so "skills depend on which unit was
## promoted" needs no separate lookup table.
@export var monarch_abilities: Array[Ability] = []
@export var monarch_promotion_costs: Array[ResourceCost] = []

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
@onready var crown_icon: Sprite3D = $CrownIcon
## Shared by selection and order-acknowledgment sounds — both are short,
## non-overlapping-in-practice one-shots, so a second dedicated player isn't
## worth another node per unit scene.
@onready var unit_audio_player: AudioStreamPlayer3D = $UnitAudioPlayer

func play_select_sound() -> void:
	AudioUtils.play_random(unit_audio_player, on_select_sound_effects)

func play_order_sound(kind: OrderSoundKind) -> void:
	match kind:
		OrderSoundKind.MOVE:
			AudioUtils.play_random(unit_audio_player, on_move_sound_effects)
		OrderSoundKind.ATTACK:
			AudioUtils.play_random(unit_audio_player, on_attack_sound_effects)
		OrderSoundKind.PATROL:
			AudioUtils.play_random(unit_audio_player, on_patrol_sound_effects)
		OrderSoundKind.BUILD:
			AudioUtils.play_random(unit_audio_player, on_build_sound_effects)
		OrderSoundKind.STOP:
			AudioUtils.play_random(unit_audio_player, on_stop_sound_effects)
		OrderSoundKind.GATHER:
			AudioUtils.play_random(unit_audio_player, on_gather_sound_effects)

var selected: bool = false:
	set(value):
		selected = value
		selection_ring.visible = value

## Setter (not just a plain bool) so the crown reacts immediately whether set
## locally (host, on promotion) or received over the wire on other peers via
## replication — same reasoning as the `selected` setter above.
var is_monarch: bool = false:
	set(value):
		is_monarch = value
		if crown_icon:
			crown_icon.visible = value

## Captured from the scene's authored (full-health) scale so the fill's
## aspect-ratio/sizing lives in the scene file, not duplicated in script.
var _fill_base_scale_x: float = 1.0

var target_resource: Gatherable = null
var dropoff_point: Node3D = null
var gather_timer: float = 0.0
## Unit or ProductionBuilding — anything with owner_peer_id/current_health/take_damage().
var attack_target: Node3D = null
var attack_timer: float = 0.0
var build_target: ProductionBuilding = null
var _dying: bool = false
var patrol_points: Array[Vector3] = []
var patrol_index: int = 0
## Counts down while attack-moving/patrolling; scanning for enemies every frame
## would be an unthrottled O(units x units) group scan, so this paces it instead.
var _enemy_scan_timer: float = 0.0
## Ranged units only: {"time_remaining": float, "target": Node3D, "damage": int}
## per shot currently in flight — see _tick_attacking's projectile_scene branch.
var _pending_projectile_hits: Array[Dictionary] = []
## Host-only: ability index (within monarch_abilities) -> Time.get_ticks_msec()
## when it's usable again. Not synced — only the host ever checks cooldowns,
## in the RPC handler that validates an activation request.
var _ability_ready_at_ms: Dictionary = {}

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
			"gather": {"row": gather_row, "frames": gather_frame_count, "fps": 8.0, "loop": true},
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
	_leave_build_site()
	_leave_gather_site()
	status_command = Command.MOVE
	status_activity = Activity.MOVING
	attack_target = null
	nav_agent.target_desired_distance = MOVE_ARRIVAL_DISTANCE
	move_to(target_position)

func command_gather(resource_node: Gatherable, dropoff: Node3D) -> void:
	if status_activity == Activity.DEAD or not can_gather or resource_node == null:
		return
	## Skip the capacity check when re-issued at a resource this unit is
	## already assigned to — otherwise it would be blocked by its own reservation.
	if resource_node != target_resource and not resource_node.can_accept_gatherer():
		return
	_leave_build_site()
	_leave_gather_site()
	status_command = Command.GATHER
	attack_target = null
	target_resource = resource_node
	dropoff_point = dropoff
	resource_node.add_gatherer(self)
	_head_to_resource()

func command_attack(target: Node3D) -> void:
	if status_activity == Activity.DEAD or not can_fight or target == null or not is_instance_valid(target):
		return
	_leave_build_site()
	_leave_gather_site()
	status_command = Command.ATTACK
	attack_target = target
	_head_to_target()

## One-shot: moves toward target_position, engaging (and fully converting to
## Command.ATTACK — see the scan in _physics_process) the first enemy found
## along the way. Once it engages, this order is gone for good; it does not
## resume toward target_position afterward.
func command_attack_move(target_position: Vector3) -> void:
	if status_activity == Activity.DEAD or not can_fight:
		return
	_leave_build_site()
	_leave_gather_site()
	status_command = Command.ATTACK_MOVE
	attack_target = null
	status_activity = Activity.MOVING
	nav_agent.target_desired_distance = MOVE_ARRIVAL_DISTANCE
	move_to(target_position)

## Loops through points, engaging anything encountered along the way and
## resuming the loop once each fight ends (see _find_new_target_or_idle).
func command_patrol(points: Array[Vector3]) -> void:
	if status_activity == Activity.DEAD or not can_fight or points.is_empty():
		return
	_leave_build_site()
	_leave_gather_site()
	status_command = Command.PATROL
	attack_target = null
	patrol_points = points
	patrol_index = 0
	status_activity = Activity.MOVING
	nav_agent.target_desired_distance = MOVE_ARRIVAL_DISTANCE
	move_to(patrol_points[0])

## Extends an already-active patrol loop with another waypoint (e.g. a
## shift-click while patrol-targeting). No-ops if the order changed before
## this arrived.
func command_patrol_add_waypoint(point: Vector3) -> void:
	if status_command == Command.PATROL:
		patrol_points.append(point)

func command_stop() -> void:
	if status_activity == Activity.DEAD:
		return
	_leave_build_site()
	_leave_gather_site()
	status_command = Command.NONE
	status_activity = Activity.IDLE
	attack_target = null
	patrol_points.clear()
	nav_agent.target_position = global_position

## --- Building ---

func command_build(building: ProductionBuilding) -> void:
	if status_activity == Activity.DEAD or not can_build or building == null:
		return
	if not is_instance_valid(building) or not building.is_under_construction:
		return
	_leave_build_site()
	_leave_gather_site()
	status_command = Command.BUILD
	attack_target = null
	build_target = building
	_head_to_build_site()

func _head_to_build_site() -> void:
	if not is_instance_valid(build_target) or not build_target.is_under_construction:
		end_build_command()
		return
	status_activity = Activity.TO_BUILD_SITE
	nav_agent.target_desired_distance = build_target.get_footprint_radius() + BUILD_ARRIVAL_DISTANCE
	move_to(build_target.global_position)

func _start_building() -> void:
	if not is_instance_valid(build_target) or not build_target.is_under_construction:
		end_build_command()
		return
	status_activity = Activity.BUILDING
	build_target.add_builder(self)

func _tick_building() -> void:
	if not is_instance_valid(build_target) or build_target.is_destroyed or not build_target.is_under_construction:
		end_build_command()

## Leaves whatever construction site this unit was contributing to, if any,
## without otherwise touching status_command/status_activity — called both
## when a new command interrupts building and when the build naturally ends.
func _leave_build_site() -> void:
	if build_target != null and is_instance_valid(build_target):
		build_target.remove_builder(self)
	build_target = null

## Releases this unit's gatherer-cap reservation on whatever resource it was
## assigned to, if any — mirrors _leave_build_site(), called at the top of
## every command_* function plus wherever gathering naturally ends.
func _leave_gather_site() -> void:
	if target_resource != null and is_instance_valid(target_resource):
		target_resource.remove_gatherer(self)
	target_resource = null

## Public: ProductionBuilding calls this directly on each of its builders
## when construction finishes, to send them back to idle.
func end_build_command() -> void:
	_leave_build_site()
	status_command = Command.NONE
	status_activity = Activity.IDLE

## --- Monarch ---

## Called only from main.gd's validated promotion RPC handler. No sprite/scene
## change — this unit keeps its existing model/animations; the crown icon is
## the only visual difference (see is_monarch's setter above).
func promote_to_monarch() -> void:
	is_monarch = true

## Called only from main.gd's validated ability-activation RPC handler.
## Teleports self to target_pos, then applies the same offset to every ally
## (same owner, self excluded) that was within ability.affected_ally_radius
## of this unit's position *before* the jump, so relative formation is kept.
func execute_teleport_ability(ability: Ability, target_pos: Vector3) -> void:
	var old_position := global_position
	var delta := target_pos - old_position
	for node in get_tree().get_nodes_in_group("units"):
		if not (node is Unit):
			continue
		var ally: Unit = node
		if ally != self and (ally.owner_peer_id != owner_peer_id \
				or ally.global_position.distance_to(old_position) > ability.affected_ally_radius):
			continue
		ally.global_position += delta
		## Clears any in-flight path the same way command_stop() does, so a
		## teleported unit doesn't immediately try to walk back to where it
		## was heading from its old position.
		ally.nav_agent.target_position = ally.global_position

func take_damage(amount: int, attacker: Node3D = null) -> void:
	if not is_multiplayer_authority() or status_activity == Activity.DEAD:
		return
	## Rock-paper-scissors bonus: an attacker whose damage_type matches what
	## this unit is weak_to hits harder. NONE never matches NONE, so units
	## with no assigned weakness (or attackers with no assigned type, e.g.
	## Villager) are simply never affected by this either way.
	if weak_to != DamageType.NONE and attacker is Unit and attacker.damage_type == weak_to:
		amount = int(amount * WEAKNESS_DAMAGE_MULTIPLIER)
	## A nearby allied Monarch's passive aura can reduce this further; never
	## reduces below 1 so an aura can't make a unit fully immune.
	amount = maxi(amount - CombatUtils.nearby_aura_armor_bonus(get_tree(), self), 1)
	status_current_health = maxi(status_current_health - amount, 0)
	if status_current_health <= 0:
		_die()
		return

	if can_fight and attacker != null and is_instance_valid(attacker):
		## Patrol deliberately stays Command.PATROL through a fight (see
		## _physics_process) so it can resume afterward, so status_command
		## can't be used as the "already engaged" check the way it is for
		## every other command below — attack_target is the reliable signal.
		if status_command == Command.PATROL:
			if attack_target == null:
				attack_target = attacker
				_head_to_target()
		## A plain Command.MOVE is a deliberate player order (e.g. retreating a
		## unit out of a losing fight) — auto-retaliating here would silently
		## override that order the moment the attacker lands one more hit
		## before the unit escapes range, undoing the retreat entirely.
		elif status_command != Command.ATTACK and status_command != Command.MOVE:
			command_attack(attacker)
		CombatUtils.alert_nearby_allies(get_tree(), global_position, owner_peer_id, attacker)

func _physics_process(delta: float) -> void:
	## Only the host simulates movement/gathering/combat; other peers just display
	## the position/animation replicated by this unit's MultiplayerSynchronizer.
	if not is_multiplayer_authority():
		return

	## Runs even if this unit just died — an arrow already in the air should
	## still land rather than vanish because its shooter is gone.
	_tick_pending_projectiles(delta)

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
			_set_animation("gather")
		move_and_slide()
		return

	if status_activity == Activity.ATTACKING:
		velocity.x = 0.0
		velocity.z = 0.0
		_face_attack_target(delta)
		_tick_attacking(delta)
		move_and_slide()
		return

	if status_activity == Activity.BUILDING:
		velocity.x = 0.0
		velocity.z = 0.0
		_tick_building()
		if sprite.sprite_frames:
			_set_animation("idle")
		move_and_slide()
		return

	if status_activity == Activity.TO_RESOURCE and nav_agent.is_navigation_finished():
		_start_gathering()
	elif status_activity == Activity.TO_DROPOFF and nav_agent.is_navigation_finished():
		_deposit_and_continue()
	elif status_activity == Activity.TO_TARGET and nav_agent.is_navigation_finished():
		_start_attacking()
	elif status_activity == Activity.TO_BUILD_SITE and nav_agent.is_navigation_finished():
		_start_building()
	elif status_activity == Activity.MOVING and (status_command == Command.ATTACK_MOVE or status_command == Command.PATROL):
		_enemy_scan_timer -= delta
		if _enemy_scan_timer <= 0.0:
			_enemy_scan_timer = ENEMY_SCAN_INTERVAL
			var enemy := _find_nearest_enemy_in_range(aggro_range)
			if enemy:
				if status_command == Command.ATTACK_MOVE:
					## "Engage and stop": fully hands off to the normal ATTACK
					## flow, so the original destination is gone for good.
					command_attack(enemy)
				else:
					## Patrol stays Command.PATROL through the fight so
					## _find_new_target_or_idle() resumes the loop after.
					attack_target = enemy
					_head_to_target()
	## Standing guard: a unit with nothing else to do still watches for enemies
	## wandering into range, instead of only ever reacting once it's actually
	## hit. Without this, an idle unit (e.g. a ranged Archer) just stands there
	## while an enemy walks right up to and past it.
	elif status_activity == Activity.IDLE and can_fight and status_command == Command.NONE:
		_enemy_scan_timer -= delta
		if _enemy_scan_timer <= 0.0:
			_enemy_scan_timer = ENEMY_SCAN_INTERVAL
			var enemy := _find_nearest_enemy_in_range(aggro_range)
			if enemy:
				command_attack(enemy)

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
	if status_activity == Activity.GATHERING or status_activity == Activity.ATTACKING or status_activity == Activity.BUILDING or status_activity == Activity.DEAD:
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

	## Gated on Activity.MOVING specifically (not just nav-finished) because
	## PATROL stays Command.PATROL while chasing/fighting (Activity.TO_TARGET/
	## ATTACKING) too — this callback fires every physics frame regardless of
	## activity, and without this gate, a patrolling unit closing to within
	## attack range of its target would look "finished navigating" while still
	## mid-chase and get yanked into _advance_patrol() before _start_attacking()
	## ever got a chance to run, causing it to circle the enemy instead of fighting.
	if status_activity == Activity.MOVING and nav_agent.is_navigation_finished():
		if status_command == Command.MOVE or status_command == Command.ATTACK_MOVE:
			## Reset status_command too, not just status_activity — otherwise
			## a unit that has ever finished a move order (including every
			## unit that walks to a rally point right after spawning) stays
			## "stuck" in Command.MOVE forever, which now also permanently
			## blocks auto-retaliation and idle standing-guard scanning (both
			## deliberately treat Command.MOVE as "still following a player
			## order, don't interrupt it").
			status_activity = Activity.IDLE
			status_command = Command.NONE
		elif status_command == Command.PATROL:
			_advance_patrol()

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
	_leave_gather_site()
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
	## A nearby allied Monarch's passive aura can shrink the effective cooldown
	## (not the exported stat itself — this is computed live each tick).
	var effective_cooldown := attack_cooldown * (1.0 - CombatUtils.nearby_aura_attack_speed_bonus(get_tree(), self))
	if attack_timer >= effective_cooldown:
		attack_timer = 0.0
		_play_attack_swing()
		if projectile_scene != null:
			## Damage lands later, when the shot actually arrives (see
			## _tick_pending_projectiles) — the shooter can keep re-nocking on
			## its own cooldown in the meantime rather than waiting for it.
			_fire_projectile(attack_target)
		else:
			attack_target.take_damage(attack_damage, self)
			if not _is_target_alive(attack_target):
				_find_new_target_or_idle()

func _fire_projectile(target: Node3D) -> void:
	var dist := global_position.distance_to(target.global_position)
	var travel_time := dist / maxf(projectile_speed, 0.01)
	_pending_projectile_hits.append({
		"time_remaining": travel_time,
		"target": target,
		"damage": attack_damage,
	})
	projectile_fired.emit(target)

## Real, authoritative delayed damage for ranged attacks — the projectile_fired
## signal/visual is purely cosmetic and never applies damage itself. Keeps
## ticking (see _physics_process) even after this unit dies, so a shot already
## in the air still lands.
func _tick_pending_projectiles(delta: float) -> void:
	for i in range(_pending_projectile_hits.size() - 1, -1, -1):
		var hit: Dictionary = _pending_projectile_hits[i]
		hit["time_remaining"] -= delta
		if hit["time_remaining"] > 0.0:
			continue
		_pending_projectile_hits.remove_at(i)
		var target = hit["target"]
		if not _is_target_alive(target):
			continue
		target.take_damage(hit["damage"], self)
		if attack_target == target and not _is_target_alive(target):
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
	if status_command == Command.ATTACK:
		var nearest: Unit = _find_nearest_enemy_in_range(aggro_range)
		if nearest:
			attack_target = nearest
			_head_to_target()
		else:
			attack_target = null
			status_command = Command.NONE
			status_activity = Activity.IDLE
	elif status_command == Command.PATROL:
		var nearest: Unit = _find_nearest_enemy_in_range(aggro_range)
		if nearest:
			attack_target = nearest
			_head_to_target()
		else:
			attack_target = null
			_advance_patrol()

## Advances to the next patrol waypoint, looping back to the start. Waypoints
## can be appended mid-loop (command_patrol_add_waypoint), which this picks up
## naturally since patrol_points.size() is read fresh each call.
func _advance_patrol() -> void:
	if patrol_points.is_empty():
		status_command = Command.NONE
		status_activity = Activity.IDLE
		return
	patrol_index = (patrol_index + 1) % patrol_points.size()
	status_activity = Activity.MOVING
	nav_agent.target_desired_distance = MOVE_ARRIVAL_DISTANCE
	move_to(patrol_points[patrol_index])

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
	_leave_build_site()
	_leave_gather_site()
	## take_damage() (the only caller of _die()) already gates on
	## is_multiplayer_authority(), so this only ever runs once, on the host.
	Population.release(owner_peer_id, population_cost)

	if sprite.sprite_frames and sprite.sprite_frames.has_animation("death"):
		_set_animation("death")
		var frame_count: int = sprite.sprite_frames.get_frame_count("death")
		var fps: float = sprite.sprite_frames.get_animation_speed("death")
		await get_tree().create_timer(frame_count / maxf(fps, 1.0)).timeout
	queue_free()
