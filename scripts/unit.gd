extends CharacterBody3D
class_name Unit

const SpriteSheetFrames = preload("res://scripts/sprite_sheet_frames.gd")

const GRAVITY: float = 20.0
## The sheets in assets/art face right by default; flip_h mirrors them to face left.
const FLIP_DOT_THRESHOLD: float = 0.15
## Below this actual speed the unit is considered stopped (e.g. blocked by another unit).
const MOVING_SPEED_THRESHOLD: float = 0.15
const MOVE_ARRIVAL_DISTANCE: float = 0.5
## Base avoidance footprint (also the default NavigationAgent3D.radius) —
## see _update_formation_avoidance, which shrinks this and shifts
## avoidance_priority for units settling into a formation slot.
const FORMATION_BASE_RADIUS: float = 0.45
## _formation_progress() (0 = leg just started, 1 = arrived at slot) fraction
## beyond which a formation-moving unit starts "settling": shrinking its
## avoidance radius and regaining avoidance_priority as it nears its slot.
## Below this the unit is still mid-transit like any other formation-mate.
const FORMATION_SETTLE_PROGRESS_START: float = 0.75
## Floor for a fully-settled unit's shrunk avoidance radius. Must stay >= the
## physical CapsuleShape3D.radius on scenes/units/unit.tscn (0.4 there as of
## writing) — RVO only steers neighbors this far away, but move_and_slide()
## still enforces the real capsule regardless, so shrinking the avoidance
## radius below the physical body would let RVO permit neighbors closer than
## the capsule can actually tolerate, causing hard-collision pushback/jitter
## right during the settling window this feature exists to smooth out. Kept
## as an explicit floor (not a multiplier of FORMATION_BASE_RADIUS) so it
## can't silently drift under the physical capsule if that radius or
## FORMATION_BASE_RADIUS ever change independently. If unit.tscn's capsule
## radius ever changes, update this to match (plus the small margin).
const FORMATION_SETTLE_RADIUS_FLOOR: float = 0.42
## avoidance_priority (0..1) a formation-moving unit runs at while still
## mid-transit (below FORMATION_SETTLE_PROGRESS_START) — kept below the
## default 1.0 so it yields to groupmates that have already reached/are
## settling into their own slots, instead of every unit in the formation
## negotiating avoidance with equal priority all at once. Note: avoidance_priority
## is a single global NavigationAgent3D knob, not formation-scoped — while
## traveling, this also makes the unit yield priority to any other agent it
## encounters (unrelated units included), not just formation-mates. Judged
## harmless: everyone sharing the same team avoidance layer/mask already
## negotiates through this same system regardless of formation membership.
const FORMATION_TRAVELING_AVOIDANCE_PRIORITY: float = 0.4
## Chokepoint funnelling (see funnel_point / _update_funnel, armed host-side by
## main.gd's _find_funnel_point when a formation move's route has to thread a
## gap narrower than the formation is wide). How close to the funnel waypoint
## this unit has to get before it's considered through the gap and released to
## its real formation slot. Deliberately much larger than MOVE_ARRIVAL_DISTANCE:
## the waypoint is a shared convergence point for the whole group, so demanding
## everyone actually reach it would just build a traffic jam on top of it, and
## the point of the waypoint is only to make units commit to the gap rather
## than to be a destination in its own right. Also has to stay comfortably
## above MOVE_ARRIVAL_DISTANCE + 0.5 so the funnel leg can never be mistaken
## for the move order itself completing (see _physics_process's arrival check).
const FUNNEL_CLEAR_DISTANCE: float = 3.0
## Hard ceiling on how long a unit will keep heading for the funnel waypoint
## before giving up and going straight to its slot. Pure safety valve: a unit
## that can't reach the gap at all (blocked, or the gap got walled up mid-move)
## must never be left standing at a waypoint forever, which is the one way a
## two-stage move can be worse than no funnelling at all.
const FUNNEL_TIMEOUT: float = 12.0
## Drop-off points sit outside a building's avoidance-obstacle radius, so this
## needs more slack than a plain move order to reliably register as "arrived".
const DROPOFF_ARRIVAL_DISTANCE: float = 1.0
## How much further than attack_range a target can drift before we bother re-approaching.
const ATTACK_LEASH_SLACK: float = 1.2
## Building footprints push agents back via avoidance same as for melee attacks.
const BUILD_ARRIVAL_DISTANCE: float = 1.0
## Seconds a builder can spend heading to a build site without covering
## STUCK_MOVE_EPSILON of ground before it's treated as unreachable and
## abandoned — see _tick_build_approach(). Otherwise a queued run of many
## build orders (most notably a long wall) can leave a builder standing
## forever if a later piece ends up boxed in by earlier ones the same run
## already finished, since nothing else would ever make it give up.
const BUILD_STUCK_TIMEOUT: float = 4.0
const BUILD_STUCK_MOVE_EPSILON: float = 0.3
## How often an attack-moving/patrolling unit checks for nearby enemies to engage.
const ENEMY_SCAN_INTERVAL: float = 0.25
## Multiplier applied when an attacker's damage_type matches its target's
## weak_to — see take_damage().
const WEAKNESS_DAMAGE_MULTIPLIER: float = 1.5
## Radius around an attack-move's destination that counts as "the place the
## player pointed at". A unit under that order keeps picking new targets
## inside this circle — enemy buildings included — until the area is clear or
## it's given another order. See _find_assault_target().
const ASSAULT_AREA_RADIUS: float = 12.0

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
## Which Blacksmith upgrade line affects this unit (see UnitUpgrades
## autoload). Independent of DamageType above — that's the rock-paper-
## scissors bonus system, this is "what category of unit is this for
## upgrade purposes" — NONE for non-combat units like the Villager.
enum UnitCategory { NONE, INFANTRY, ARCHER, CAVALRY }

## main.gd (which owns a proven-reliable broadcast RPC channel) relays this to
## other peers; RPCs declared directly on this dynamically-spawned node were
## not reaching clients. Sprite flip is NOT networked this way — see _process().
signal animation_changed(anim_name: String)
## Relayed the same way (see main.gd), so every peer can spawn its own purely
## cosmetic projectile visual flying toward the target. Real damage timing is
## tracked independently on the host via _pending_projectile_hits, not this.
signal projectile_fired(target: Node3D)
## Relayed the same way (see main.gd) for a floating damage-number popup —
## take_damage() only ever runs on the host, so without relaying this every
## other peer would never see the number at all.
signal damaged(amount: int)
## Relayed the same way, for a floating "+N" resource popup. Carries the
## resource's display_color directly (rather than the ResourceType resource
## itself) since that's all the popup needs and it's trivially RPC-safe.
signal resource_deposited(amount: int, color: Color)
## Emitted on each harvest tick (host only, like the gathering itself) so
## main.gd can relay the node's squash animation out to every peer.
signal resource_harvested(node: Gatherable)
## Host-only, never relayed to other peers (order_queue itself isn't
## networked — only the host ever advances it, same as every other combat/
## movement decision). Fired the moment a command naturally runs its course
## (a move arrives, an attack runs out of enemies, a build finishes) so
## main.gd can pop and dispatch the next shift-queued order, if any. Not
## fired on an explicit stop or death — those are interruptions, not
## completions, and clear order_queue instead of advancing it.
signal order_completed

## What this unit type is called in UI (info panel title, etc.) — unlike the
## scene node's own .name, this can't get an auto-incremented suffix (e.g.
## "Unit2") when several of the same unit are siblings under Units.
@export var display_name: String = "Villager"
@export var move_speed: float = 5.0
@export var rotation_speed: float = 10.0
## Setter (guarded — sprite isn't ready yet the first time Godot applies this
## from the scene file during instantiation) so an Objective capture can
## re-tint a unit immediately instead of only ever applying once in _ready().
@export var team_tint: Color = Color.WHITE:
	set(value):
		team_tint = value
		_update_team_tint_visual()
## Which player controls this unit. The host is always peer 1.
## Setter keeps NavigationAgent3D avoidance layers in sync with ownership (see
## _update_avoidance_team below) so a captured Objective guard immediately
## stops being avoidance-blocked by its old enemies and starts being ignored
## by its new allies, instead of only applying once in _ready().
@export var owner_peer_id: int = 1:
	set(value):
		owner_peer_id = value
		if nav_agent:
			_update_avoidance_team()
		_update_team_tint_visual()

## How much an enemy's team_tint still shows through — kept well under 1.0 so
## it reads as a subtle recolor rather than a flat-painted sprite.
const _ENEMY_TINT_STRENGTH: float = 0.35

## Only enemy units (relative to this viewer's own peer id) get team-colored —
## own/ally units keep their sprite's natural colors, since team_tint's whole
## purpose is telling enemies apart from a glance, not decorating your own
## army.
func _resting_modulate() -> Color:
	if owner_peer_id == multiplayer.get_unique_id():
		return Color.WHITE
	return Color.WHITE.lerp(team_tint, _ENEMY_TINT_STRENGTH)

## Called from both team_tint's and owner_peer_id's setters (order of property
## application during scene instantiation isn't guaranteed) as well as
## _ready(), so whichever ends up set last still lands on the right result.
func _update_team_tint_visual() -> void:
	if sprite:
		sprite.modulate = _resting_modulate()
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
## Which Blacksmith weapon/armor upgrade line applies to this unit.
@export var unit_category: UnitCategory = UnitCategory.NONE
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
## Inspector-configurable (amount/color/spread/etc. all live on the node
## itself) — see _process() for when it's toggled on/off.
@onready var walk_dust: GPUParticles3D = get_node_or_null("WalkDust")
## Positional — the battlefield half of this unit's voice, which currently
## means just its attack bark. See _order_sound_player.
@onready var unit_audio_player: AudioStreamPlayer3D = $UnitAudioPlayer
## Non-positional — feedback on the local player's own click (selecting this
## unit, and acknowledging orders given to it). Same reasoning, and the same
## node name, as main.gd's own CommandAudioPlayer: this is interface feedback
## rather than something happening at a world location, so attenuating it by
## camera distance only makes your own units harder to hear.
@onready var command_audio_player: AudioStreamPlayer = $CommandAudioPlayer

## Always interface feedback: selection is only ever triggered locally, on the
## selecting player's own machine, and never relayed.
func play_select_sound() -> void:
	AudioUtils.play_random(command_audio_player, on_select_sound_effects)

func play_order_sound(kind: OrderSoundKind) -> void:
	var player = _order_sound_player(kind)
	match kind:
		OrderSoundKind.MOVE:
			AudioUtils.play_random(player, on_move_sound_effects)
		OrderSoundKind.ATTACK:
			AudioUtils.play_random(player, on_attack_sound_effects)
		OrderSoundKind.PATROL:
			AudioUtils.play_random(player, on_patrol_sound_effects)
		OrderSoundKind.BUILD:
			AudioUtils.play_random(player, on_build_sound_effects)
		OrderSoundKind.STOP:
			AudioUtils.play_random(player, on_stop_sound_effects)
		OrderSoundKind.GATHER:
			AudioUtils.play_random(player, on_gather_sound_effects)

## Attack keeps the positional player — it reads as a battlefield sound rather
## than an interface one. Every other acknowledgment is pure interface feedback.
## No owner check is needed either way: an order sound only ever reaches the
## peer that gave the order (see main.gd's _play_unit_order_sound), so this is
## always the local player's own unit. Untyped return for the same duck-typing
## reason as AudioUtils.play_random.
func _order_sound_player(kind: OrderSoundKind):
	return unit_audio_player if kind == OrderSoundKind.ATTACK else command_audio_player

var selected: bool = false:
	set(value):
		var was_selected := selected
		selected = value
		selection_ring.visible = value
		if value and not was_selected:
			_play_selection_punch()

## Quick scale bounce on newly becoming selected — purely a local visual, not
## networked, same as selected itself (selection is per-viewer, like sprite flip).
func _play_selection_punch() -> void:
	selection_ring.scale = Vector3.ONE * 0.5
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(selection_ring, "scale", Vector3.ONE, 0.25)

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

var _flash_tween: Tween

## Called by main.gd when relaying the damaged signal (see there — take_damage
## only ever runs on the host, so this needs relaying to show on every peer,
## same as the floating damage number it's paired with). Flashes to white and
## eases back to team_tint rather than just snapping back, so a rapid flurry
## of hits doesn't cut the flash short mid-fade.
func play_hit_flash() -> void:
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	sprite.modulate = Color.WHITE
	_flash_tween = create_tween()
	_flash_tween.tween_property(sprite, "modulate", _resting_modulate(), 0.15)

## -1 = no override, move at this unit's own move_speed. Set only by a
## multi-unit formation move (main.gd:_rpc_issue_command/_slowest_move_speed)
## so the whole group travels at its slowest member's pace instead of faster
## units outrunning slower ones and scrambling the formation shape mid-transit
## — the arrival slots were already correct, only the pacing during the move
## wasn't. Cleared back to -1 by every other command (see each command_*
## below) so a stale slowdown never outlives the move it was set for.
var formation_speed: float = -1.0

## Group cohesion (on top of formation_speed): the OTHER units this unit was
## dispatched together with in the same formation move (this unit itself is
## deliberately excluded — see _set_formation_cohesion — so it never counts
## its own progress toward its own "group average"), and this unit's
## straight-line distance to its own assigned slot, recomputed at the moment
## this leg of the move actually starts (see _set_formation_cohesion) rather
## than only once back at original order-issue time — a shift-queued order
## only starts later, after the unit has moved for a prior leg, so a baseline
## frozen at issue time would be stale from tick one of this leg. Both empty/
## 0.0 outside an active formation move. formation_speed alone only stops a
## fast unit from *finishing* early; it does nothing about a unit whose
## particular path happens to be longer/blocked and falls behind, so
## _update_cohesion below compares each unit's progress fraction toward its
## own slot against the group's average and further throttles effective_speed
## for anyone running ahead of the pack.
var formation_group: Array[Unit] = []
var formation_initial_distance: float = 0.0
var _cohesion_recheck_timer: float = 0.0
var _cohesion_target_speed_scale: float = 1.0
var _cohesion_speed_scale: float = 1.0
## Stall tracking so a permanently-blocked groupmate doesn't drag the whole
## group's average (and therefore everyone else's throttle) down forever —
## same idea as _build_stuck_timer/_tick_build_approach's give-up-after-
## timeout pattern below, applied to formation progress instead of build
## approach. Tracked as raw remaining path distance (meters), not a fraction
## of formation_initial_distance — a fraction-of-total epsilon would demand a
## fixed number of meters of progress per recheck regardless of how long the
## leg is, so on any sufficiently long leg even a fully healthy, unthrottled
## unit would structurally fail to clear it every single tick (see
## _update_cohesion). Comparing raw meters-per-recheck against what this
## unit's own current pace should cover scales correctly with leg length.
var _cohesion_last_remaining_distance: float = -1.0
var _cohesion_stall_timer: float = 0.0
## Separate, shorter-fused timer for "literally not moving at all" (as
## opposed to just slower than expected) — see COHESION_HARD_STALL_*.
var _cohesion_hard_stall_timer: float = 0.0
var _cohesion_stalled: bool = false

## Chokepoint funnelling state — host-only, same as everything else that
## actually simulates movement. While _funnel_active, nav_agent is steered at
## funnel_point (a spot just past a narrow gap the group has to thread) instead
## of at this unit's real formation slot, which is parked in _funnel_final_target
## until the unit is through. _funnel_forward is the group's direction of travel
## through the gap, used to release a unit that has passed the waypoint off to
## one side rather than driving it back to a point it has already overshot.
var _funnel_active: bool = false
var funnel_point: Vector3 = Vector3.ZERO
var _funnel_forward: Vector3 = Vector3.FORWARD
var _funnel_final_target: Vector3 = Vector3.ZERO
var _funnel_timer: float = 0.0

const COHESION_RECHECK_INTERVAL: float = 0.2
## Progress-fraction lead (0-1) over the group average tolerated before any
## throttling kicks in — small formation-keeping wobble/noise shouldn't cause
## constant micro-braking.
const COHESION_AHEAD_DEADBAND: float = 0.08
## Lead fraction at which throttling bottoms out at COHESION_MIN_SPEED_SCALE.
const COHESION_MAX_THROTTLE_RANGE: float = 0.35
## Never fully halts a unit that's ahead — just slows it — so it keeps
## drifting forward instead of visibly stopping and starting.
const COHESION_MIN_SPEED_SCALE: float = 0.35
## How fast _cohesion_speed_scale eases toward its newly-recomputed target
## per second — smooths the throttle instead of it snapping frame to frame.
const COHESION_SCALE_LERP_RATE: float = 1.5
## A unit must cover at least this fraction of (its own current commanded
## pace x the recheck interval) in raw meters each recheck to count as
## "still making progress". Deliberately not tiny (e.g. 0.25) — a unit only
## has to dodge below near-total-standstill to keep resetting the timer at
## that level, so a genuinely struggling unit (bumping an obstacle, weaving,
## covering 30-40% of its expected pace) never crosses the bar and drags the
## whole group down indefinitely, which is exactly what stall-exclusion is
## supposed to prevent. 0.55 catches that "still crawling but clearly
## struggling" case while the sustained COHESION_STUCK_TIMEOUT window below
## (see its own comment) — not a loose per-tick tolerance — is what absorbs
## normal one-off RVO jostling: a unit briefly slowing to negotiate around a
## groupmate loses at most one or two ticks below 0.55x pace before resuming,
## nowhere near the consecutive resets-that-don't-happen needed to accumulate
## the full timeout, so transient avoidance noise still can't false-flag it.
const COHESION_STALL_TOLERANCE: float = 0.55
## 3.5s (not 2.0s) gives real margin for legitimate single-file chokepoint
## queuing — this project has wall gate/segment/corner pieces
## (scenes/buildings/wall_gate.tscn etc.) a formation can plausibly funnel
## through, where several units waiting their turn via normal RVO negotiation
## could sustain sub-0.55x pace for longer than a brief one-off jostle. A
## genuinely stuck unit (boxed in, pathing failure) still gets excluded well
## within a few seconds — an acceptable tradeoff for an RTS — while normal
## queuing at a gate has room to clear before that happens.
const COHESION_STUCK_TIMEOUT: float = 3.5
## Raw meters progressed within one recheck window below which a unit counts
## as making literally no progress at all, not merely slower progress than
## expected — this can't legitimately happen from throttled pacing under any
## circumstance, so it's excluded from the group average on a much shorter
## fuse than the general stall timeout above, capping how long a dead-stopped
## groupmate can drag down the pace-setter's own throttle.
const COHESION_HARD_STALL_DISTANCE_EPS: float = 0.05
const COHESION_HARD_STUCK_TIMEOUT: float = 0.6

var target_resource: Gatherable = null
var dropoff_point: Node3D = null
var gather_timer: float = 0.0
## Unit or ProductionBuilding — anything with owner_peer_id/current_health/take_damage().
var attack_target: Node3D = null
var attack_timer: float = 0.0
var build_target: ProductionBuilding = null
## Progress-stall tracking for _tick_build_approach() while heading to
## build_target — reset whenever a new build site is targeted.
var _build_stuck_timer: float = 0.0
var _build_stuck_check_pos: Vector3 = Vector3.ZERO
var _dying: bool = false
var patrol_points: Array[Vector3] = []
var patrol_index: int = 0
## Shift-queued follow-on orders — see main.gd's _rpc_issue_command/
## _rpc_request_build (append param) and _on_unit_order_completed. Each
## entry is a plain Dictionary (target_path/world_pos/attack_move_fallback/
## speed_override) rather than a class since it's just a few RPC parameters
## held onto until this unit's current order finishes, same style as
## rally_target_path/rally_point on ProductionBuilding. Host-only; never
## networked, since only the host ever dispatches from it.
var order_queue: Array[Dictionary] = []

func queue_order(target_path: NodePath, world_pos: Vector3, attack_move_fallback: bool, speed_override: float = -1.0, group: Array[Unit] = []) -> void:
	order_queue.append({
		"target_path": target_path,
		"world_pos": world_pos,
		"attack_move_fallback": attack_move_fallback,
		"speed_override": speed_override,
		"formation_group": group,
	})

func clear_order_queue() -> void:
	order_queue.clear()

## Arms group-cohesion tracking for a fresh formation-move leg — see
## formation_group/formation_initial_distance declaration above. Called only
## from command_move/command_attack_move, i.e. exactly when this leg actually
## starts (whether dispatched immediately or popped later off order_queue for
## a shift-queued order), so the distance baseline is always taken from this
## unit's real starting position for THIS leg rather than a stale position
## from whenever the original order was issued. `group` deliberately should
## NOT include this unit itself (see main.gd:_rpc_issue_command) — kept as-is
## here rather than filtered, since _update_cohesion is what actually skips
## self when averaging; an empty group (single-unit selection, or any
## non-formation dispatch) leaves cohesion inert since _update_cohesion bails
## out on an empty formation_group.
func _set_formation_cohesion(group: Array[Unit], target_position: Vector3) -> void:
	formation_group = group
	formation_initial_distance = global_position.distance_to(target_position) if not group.is_empty() else 0.0
	_cohesion_recheck_timer = 0.0
	_cohesion_target_speed_scale = 1.0
	_cohesion_speed_scale = 1.0
	_cohesion_last_remaining_distance = -1.0
	_cohesion_stall_timer = 0.0
	_cohesion_hard_stall_timer = 0.0
	_cohesion_stalled = false
	## Any fresh move leg starts un-funnelled by definition; main.gd re-arms it
	## immediately afterwards (via set_funnel_waypoint) if this particular leg's
	## route actually needs one. Clearing here rather than only in command_move
	## means every path that (re)baselines cohesion also drops a stale funnel,
	## including the re-baseline _update_funnel itself does on release.
	_funnel_active = false

func _clear_formation_cohesion() -> void:
	_funnel_active = false
	formation_group = []
	formation_initial_distance = 0.0
	_cohesion_target_speed_scale = 1.0
	_cohesion_speed_scale = 1.0
	_cohesion_last_remaining_distance = -1.0
	_cohesion_stall_timer = 0.0
	_cohesion_hard_stall_timer = 0.0
	_cohesion_stalled = false
## Set directly by Objective for its guards; 0.0 = no leash (every normal
## player unit) — a leashed unit breaks off a chase and resumes patrol
## instead of following a fleeing/kiting target indefinitely.
var leash_origin: Node3D = null
var leash_radius: float = 0.0
## Counts down while attack-moving/patrolling; scanning for enemies every frame
## would be an unthrottled O(units x units) group scan, so this paces it instead.
var _enemy_scan_timer: float = 0.0
## Ranged units only: {"time_remaining": float, "target": Node3D, "damage": int}
## per shot currently in flight — see _tick_attacking's projectile_scene branch.
var _pending_projectile_hits: Array[Dictionary] = []
## Damage already committed to this unit by shots currently in the air. Read by
## every target scan via CombatUtils.is_worth_attacking, which is what stops a
## whole volley landing on someone the first three arrows already killed.
var incoming_damage: int = 0
## Set by command_attack_move: where the player pointed, and whether that
## standing "clear this area" order is still live. Deliberately survives the
## individual fights it spawns (command_attack keeps it, see keep_assault), so
## killing one target leads to the next one in the area rather than ending the
## order — only Stop or another command calls it off.
var assault_center: Vector3 = Vector3.ZERO
var assault_active: bool = false
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
	_update_team_tint_visual()
	nav_agent.path_desired_distance = 0.5
	nav_agent.target_desired_distance = MOVE_ARRIVAL_DISTANCE
	nav_agent.radius = FORMATION_BASE_RADIUS
	nav_agent.avoidance_priority = 1.0
	nav_agent.max_speed = move_speed
	_update_avoidance_team()

	## Puppets (non-authority peers) never call set_velocity(), but avoidance
	## keeps emitting velocity_computed on its own once enabled regardless of
	## authority. status_activity isn't replicated, so a puppet's copy always
	## reads as IDLE and this callback would otherwise force the animation back
	## to idle every frame, fighting the animation RPCs from the real owner.
	if is_multiplayer_authority():
		nav_agent.avoidance_enabled = true
		nav_agent.velocity_computed.connect(_on_velocity_computed)

## Same-team units broadcast on (and only avoid) their own owner_peer_id's
## avoidance layer, so allies can freely overlap/squeeze past each other in a
## tight chokepoint (e.g. a narrow ramp) instead of RVO treating every nearby
## unit, ally or not, as something to steer around and deadlocking. Enemies
## still avoid each other normally since they're never on the same layer.
func _update_avoidance_team() -> void:
	## +1 so peer 0 (neutral units, e.g. Objective guards) doesn't land on bit
	## 1 — the default avoidance layer every building's NavigationObstacle3D
	## uses (never explicitly set). Clearing only this unit's own bit from its
	## mask leaves that shared obstacle layer untouched for every team, so
	## units of any owner still avoid buildings/terrain normally.
	var team_bit: int = 1 << (owner_peer_id + 1)
	nav_agent.avoidance_layers = team_bit
	nav_agent.avoidance_mask = ~team_bit

## Raw navigation command; prefer command_move / command_gather / command_attack which also manage status.
func move_to(target_position: Vector3) -> void:
	nav_agent.target_position = target_position

func command_move(target_position: Vector3, speed_override: float = -1.0, group: Array[Unit] = []) -> void:
	if status_activity == Activity.DEAD:
		return
	_leave_build_site()
	_leave_gather_site()
	status_command = Command.MOVE
	status_activity = Activity.MOVING
	attack_target = null
	assault_active = false
	formation_speed = speed_override
	_set_formation_cohesion(group, target_position)
	nav_agent.target_desired_distance = MOVE_ARRIVAL_DISTANCE
	move_to(target_position)

## Two-stage formation move: steer at `point` (a spot just past a narrow gap the
## group's route has to thread) first, and only head for the slot this unit was
## actually given once it's through. Host-only, and armed by main.gd right after
## command_move/command_attack_move — so the caller has already set the real
## slot as nav_agent.target_position, which is what gets parked here.
## `forward` is the group's direction of travel through the gap.
func set_funnel_waypoint(point: Vector3, forward: Vector3) -> void:
	if not _funnel_can_arm():
		return
	var final_target: Vector3 = nav_agent.target_position
	## Re-baselines cohesion onto the leg this unit is actually walking now
	## (here -> gap) rather than leaving it pointed at the far-side slot. Both
	## _update_cohesion and _update_formation_avoidance read progress as
	## 1 — nav_agent.distance_to_target() / formation_initial_distance, so a
	## baseline measured to the distant slot while nav_agent steers at the much
	## nearer gap would read as "nearly arrived" from the first frame. Giving
	## each leg its own baseline is exactly what _set_formation_cohesion already
	## does for shift-queued orders. It also clears any stale funnel, hence the
	## ordering here — arm afterwards, never before.
	_set_formation_cohesion(formation_group, point)
	_funnel_final_target = final_target
	funnel_point = point
	_funnel_forward = forward
	_funnel_timer = 0.0
	_funnel_active = true
	nav_agent.target_position = point

func _funnel_can_arm() -> bool:
	return status_activity == Activity.MOVING \
			and (status_command == Command.MOVE or status_command == Command.ATTACK_MOVE)

## Releases the unit from the funnel waypoint onto its real slot once it's
## through the gap. Three exits, any of which is enough:
##   — it got within FUNNEL_CLEAR_DISTANCE of the waypoint (the normal case —
##     the waypoint sits past the gap, so being near it means being through it);
##   — it's already past the waypoint's plane, which catches a unit that
##     squeezed through wide of the point and would otherwise be dragged
##     backwards to reach it;
##   — FUNNEL_TIMEOUT expired, the safety valve for a gap that turned out to be
##     unreachable (blocked, or walled up mid-move) — without it a funnelled
##     unit could stand at a waypoint indefinitely.
func _update_funnel(delta: float) -> void:
	if not _funnel_active:
		return
	_funnel_timer += delta
	var offset: Vector3 = funnel_point - global_position
	offset.y = 0.0
	if offset.length() > FUNNEL_CLEAR_DISTANCE \
			and offset.dot(_funnel_forward) > 0.0 \
			and _funnel_timer < FUNNEL_TIMEOUT:
		return
	var final_target: Vector3 = _funnel_final_target
	_set_formation_cohesion(formation_group, final_target)
	nav_agent.target_position = final_target

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
	assault_active = false
	formation_speed = -1.0
	_clear_formation_cohesion()
	target_resource = resource_node
	dropoff_point = dropoff
	resource_node.add_gatherer(self)
	_head_to_resource()

## keep_assault: true when this fight was picked *by* a standing attack-move
## order, or is self-defense during one, rather than being a fresh player order
## at a specific target. The assault then survives the fight, so
## _find_new_target_or_idle can move on to the next thing in the area once this
## target dies instead of the unit stopping there.
func command_attack(target: Node3D, keep_assault: bool = false) -> void:
	if status_activity == Activity.DEAD or not can_fight or target == null or not is_instance_valid(target):
		return
	_leave_build_site()
	_leave_gather_site()
	if not keep_assault:
		assault_active = false
	status_command = Command.ATTACK
	attack_target = target
	formation_speed = -1.0
	_clear_formation_cohesion()
	_head_to_target()

## Standing "assault this place" order: moves toward target_position, engaging
## enemies met on the way, and once at the destination keeps taking new targets
## within ASSAULT_AREA_RADIUS of it — enemy buildings included — as each one
## dies. Individual fights convert to Command.ATTACK (see the scan in
## _physics_process) but leave assault_active set, so unlike a plain move the
## order isn't spent by the first engagement: it ends when the area is clear or
## another command replaces it.
func command_attack_move(target_position: Vector3, speed_override: float = -1.0, group: Array[Unit] = []) -> void:
	if status_activity == Activity.DEAD or not can_fight:
		return
	_leave_build_site()
	_leave_gather_site()
	assault_center = target_position
	assault_active = true
	status_command = Command.ATTACK_MOVE
	attack_target = null
	formation_speed = speed_override
	_set_formation_cohesion(group, target_position)
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
	assault_active = false
	formation_speed = -1.0
	_clear_formation_cohesion()
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
	assault_active = false
	formation_speed = -1.0
	_clear_formation_cohesion()
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
	assault_active = false
	formation_speed = -1.0
	_clear_formation_cohesion()
	build_target = building
	_head_to_build_site()

func _head_to_build_site() -> void:
	if not is_instance_valid(build_target) or not build_target.is_under_construction:
		end_build_command()
		return
	status_activity = Activity.TO_BUILD_SITE
	nav_agent.target_desired_distance = build_target.get_footprint_radius() + BUILD_ARRIVAL_DISTANCE
	move_to(build_target.global_position)
	_build_stuck_timer = 0.0
	_build_stuck_check_pos = global_position

## Gives up on the current build site if this unit hasn't actually gotten any
## closer to it for BUILD_STUCK_TIMEOUT seconds — most commonly a later piece
## in a long wall run that's become boxed in by the earlier pieces this same
## builder already finished, with no path left to reach it. Ending the build
## command (rather than just sitting in TO_BUILD_SITE forever) fires
## order_completed, which — for a queued run like the wall dispatch — moves
## the builder on to whatever's queued next instead of freezing the whole run.
func _tick_build_approach(delta: float) -> void:
	_build_stuck_timer += delta
	if _build_stuck_timer < BUILD_STUCK_TIMEOUT:
		return
	_build_stuck_timer = 0.0
	if global_position.distance_to(_build_stuck_check_pos) < BUILD_STUCK_MOVE_EPSILON:
		end_build_command()
	else:
		_build_stuck_check_pos = global_position

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
	order_completed.emit()

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
	## A nearby allied Monarch's passive aura and this player's Blacksmith
	## armor upgrades both reduce this further; never reduces below 1 so
	## neither can make a unit fully immune.
	var armor: int = CombatUtils.nearby_aura_armor_bonus(get_tree(), self) \
			+ UnitUpgrades.get_armor_bonus(owner_peer_id, unit_category)
	amount = maxi(amount - armor, 1)
	damaged.emit(amount)
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
			## keep_assault: being shot at while marching on an assault target
			## makes this unit fight back, but must not quietly cancel the
			## standing order to take the place it was sent to.
			command_attack(attacker, true)
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
	elif status_activity == Activity.TO_TARGET:
		if nav_agent.is_navigation_finished():
			_start_attacking()
		else:
			_tick_approach_threats(delta)
	elif status_activity == Activity.TO_BUILD_SITE:
		if nav_agent.is_navigation_finished():
			_start_building()
		else:
			_tick_build_approach(delta)
	elif status_activity == Activity.MOVING and (status_command == Command.ATTACK_MOVE or status_command == Command.PATROL):
		_enemy_scan_timer -= delta
		if _enemy_scan_timer <= 0.0:
			_enemy_scan_timer = ENEMY_SCAN_INTERVAL
			if status_command == Command.ATTACK_MOVE:
				## Deliberately the plain aggro scan rather than
				## _find_assault_target(): while still marching, only something
				## the unit has actually walked into should break it out of the
				## formation move. Scanning the whole assault area from here
				## made the group abandon formation on the very first tick and
				## charge whatever happened to be nearest the destination, one
				## unit at a time. Targets further into the area — and enemy
				## buildings — are picked up on arrival instead, by the idle
				## scan below, and after each kill by _find_new_target_or_idle.
				var target := _find_nearest_enemy_in_range(aggro_range)
				if target:
					## Hands off to the normal ATTACK flow for this one fight,
					## but keeps the assault so the destination isn't lost.
					command_attack(target, true)
			else:
				## Patrol stays Command.PATROL through the fight so
				## _find_new_target_or_idle() resumes the loop after.
				var enemy := _find_nearest_enemy_in_range(aggro_range)
				if enemy:
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
			## A unit holding a cleared assault area watches that whole area
			## (buildings included), not just its own aggro bubble — it was told
			## to take the place, and only Stop or another order calls it off.
			var enemy: Node3D = _find_assault_target() if assault_active \
					else _find_nearest_enemy_in_range(aggro_range)
			if enemy:
				command_attack(enemy, true)

	## Before the steering read below, so a unit released from its funnel
	## waypoint this frame immediately starts steering at its real slot instead
	## of spending one more frame closing on a waypoint it's already through.
	_update_funnel(delta)

	var direction := Vector3.ZERO
	if not nav_agent.is_navigation_finished():
		var next_pos: Vector3 = nav_agent.get_next_path_position()
		direction = next_pos - global_position
		direction.y = 0.0
		if direction.length_squared() > 0.0001:
			direction = direction.normalized()

	## formation_speed (see its declaration) caps a formation move to the
	## group's slowest member — minf guards against it ever exceeding this
	## unit's own move_speed even if it somehow got set wrong.
	var effective_speed: float = minf(formation_speed, move_speed) if formation_speed > 0.0 else move_speed
	_update_cohesion(delta, effective_speed)
	effective_speed *= _cohesion_speed_scale
	_update_formation_avoidance()
	var desired_velocity := Vector3(direction.x * effective_speed, 0.0, direction.z * effective_speed)
	nav_agent.set_velocity(desired_velocity)

## Group cohesion on top of formation_speed's flat pacing cap: throttles this
## unit further, proportionally, when it's running ahead of the formation
## group's average progress toward their slots — a unit with a short/clear
## path would otherwise still reach its slot early and sit there drifting
## while a unit stuck going around an obstacle catches up, even though both
## have the same raw move_speed. Recomputed on a short timer (not every
## frame, both for cost — O(group size) — and to avoid the target scale
## flickering frame to frame) and then eased toward smoothly so the unit's
## speed ramps rather than snaps.
func _update_cohesion(delta: float, base_speed: float) -> void:
	if formation_speed <= 0.0 or formation_group.is_empty() or formation_initial_distance <= 0.0:
		_cohesion_speed_scale = 1.0
		_cohesion_last_remaining_distance = -1.0
		_cohesion_stall_timer = 0.0
		_cohesion_hard_stall_timer = 0.0
		_cohesion_stalled = false
		return

	_cohesion_recheck_timer -= delta
	if _cohesion_recheck_timer <= 0.0:
		_cohesion_recheck_timer = COHESION_RECHECK_INTERVAL
		var self_progress := _formation_progress()

		## Stall detection compares RAW meters progressed this recheck window
		## against what this unit's own current commanded pace should cover —
		## not a flat fraction of formation_initial_distance. A fixed fraction
		## (e.g. "must gain 3% progress per tick") demands more raw meters on a
		## longer leg, since progress is normalized by the whole leg length; a
		## 50m leg needs 10x the ground-speed a 5m leg does just to clear the
		## same fractional bar, so a fully healthy unit on a long enough leg
		## would fail it every tick and never be able to reset the timer. Raw
		## distance against this unit's own pace scales correctly regardless
		## of leg length.
		var remaining := nav_agent.distance_to_target()
		var progressed_distance: float = (_cohesion_last_remaining_distance - remaining) if _cohesion_last_remaining_distance >= 0.0 else INF
		## Reference pace is base_speed x this unit's own current throttle
		## scale — i.e. what it was actually just commanded to do — so a
		## unit that's legitimately pacing itself down (formation_speed cap,
		## or its own cohesion throttle) is judged against its own reduced
		## target, not against an unthrottled top speed it was never asked
		## to hit.
		var expected_min_distance: float = base_speed * _cohesion_speed_scale * COHESION_RECHECK_INTERVAL * COHESION_STALL_TOLERANCE
		if progressed_distance >= expected_min_distance:
			_cohesion_stall_timer = 0.0
		else:
			_cohesion_stall_timer += COHESION_RECHECK_INTERVAL
		## Faster-fused "literally zero movement" check — this can't happen
		## from any legitimate throttled pacing, so it doesn't need to wait
		## out the full grace window above before this groupmate stops
		## counting toward everyone else's average (see the critic's
		## compounding-throttle concern: while a stuck unit is still counted,
		## it can drag even the pace-setter below its own formation_speed
		## floor).
		if progressed_distance < COHESION_HARD_STALL_DISTANCE_EPS:
			_cohesion_hard_stall_timer += COHESION_RECHECK_INTERVAL
		else:
			_cohesion_hard_stall_timer = 0.0
		_cohesion_last_remaining_distance = remaining
		_cohesion_stalled = _cohesion_stall_timer >= COHESION_STUCK_TIMEOUT or _cohesion_hard_stall_timer >= COHESION_HARD_STUCK_TIMEOUT

		var total_progress := 0.0
		var count := 0
		for other in formation_group:
			## formation_group is built by main.gd as "the units dispatched
			## together" and deliberately does NOT exclude this unit itself
			## (it's a single shared array reference across the whole group,
			## cheaper than building a per-unit copy) — skip self here so a
			## unit's own progress never counts toward its own "group average"
			## (that would shrink the ahead-signal, worse for smaller groups).
			if other == self or other == null or not is_instance_valid(other) or other.status_activity == Activity.DEAD:
				continue
			if other.formation_speed <= 0.0 or other.formation_initial_distance <= 0.0:
				continue
			## Excludes a stalled groupmate from the average rather than letting
			## it drag every other unit's throttle down (and compounding, since
			## effective_speed already stacks formation_speed x cohesion scale)
			## indefinitely while it's stuck.
			if other._cohesion_stalled:
				continue
			total_progress += other._formation_progress()
			count += 1

		_cohesion_target_speed_scale = 1.0
		if count > 0:
			var avg_progress: float = total_progress / count
			var ahead: float = self_progress - avg_progress
			if ahead > COHESION_AHEAD_DEADBAND:
				var t: float = clampf((ahead - COHESION_AHEAD_DEADBAND) / (COHESION_MAX_THROTTLE_RANGE - COHESION_AHEAD_DEADBAND), 0.0, 1.0)
				_cohesion_target_speed_scale = lerpf(1.0, COHESION_MIN_SPEED_SCALE, t)

	_cohesion_speed_scale = move_toward(_cohesion_speed_scale, _cohesion_target_speed_scale, COHESION_SCALE_LERP_RATE * delta)

## Formation-mates settling into their slots get avoidance priority back over
## ones still mid-transit, and shrink their own avoidance radius, so a tight
## formation (e.g. a Box at SPACING) settles slot-by-slot instead of every
## unit negotiating RVO avoidance with every other at equal footing all at
## once (the visible jostling/stutter this exists to fix). Deliberately reuses
## _formation_progress() (already computed for cohesion) rather than adding
## new per-unit state or touching formation shape/rank data — "close to my
## own slot" is a good enough proxy for "front rank / about to settle"
## without needing main.gd to hand down explicit rank info. Resets to the
## base footprint/priority the instant formation_group is cleared (order
## completion, retarget, or a non-formation command), so it never lingers
## once a unit is done treating this as a formation leg.
func _update_formation_avoidance() -> void:
	if formation_group.is_empty():
		nav_agent.radius = FORMATION_BASE_RADIUS
		nav_agent.avoidance_priority = 1.0
		return
	var progress: float = _formation_progress()
	if progress < FORMATION_SETTLE_PROGRESS_START:
		nav_agent.radius = FORMATION_BASE_RADIUS
		nav_agent.avoidance_priority = FORMATION_TRAVELING_AVOIDANCE_PRIORITY
		return
	var t: float = clampf((progress - FORMATION_SETTLE_PROGRESS_START) / (1.0 - FORMATION_SETTLE_PROGRESS_START), 0.0, 1.0)
	nav_agent.radius = lerpf(FORMATION_BASE_RADIUS, FORMATION_SETTLE_RADIUS_FLOOR, t)
	nav_agent.avoidance_priority = lerpf(FORMATION_TRAVELING_AVOIDANCE_PRIORITY, 1.0, t)

## 0 (just started) to 1 (arrived) fraction of this unit's straight-line
## distance-to-slot at the start of this leg (see _set_formation_cohesion)
## that its actual remaining nav path distance now represents — used instead
## of raw move_speed comparisons so a unit taking a longer/curved path around
## an obstacle reads as "behind" even if its speed stat matches everyone else's.
func _formation_progress() -> float:
	if formation_initial_distance <= 0.0:
		return 1.0
	return clampf(1.0 - nav_agent.distance_to_target() / formation_initial_distance, 0.0, 1.0)

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
	##
	## The extra distance check guards against a NavigationAgent3D quirk: right
	## after move_to() sets a brand new target_position from a cold/idle start,
	## is_navigation_finished() can read true for a frame or two before the
	## async path is actually computed (no path yet reads as "nothing left to
	## do"). That was always harmless before this flag existed — resetting
	## status_command a frame early didn't stop the unit's real navigation —
	## but with a shift-queued order waiting, this false completion would
	## immediately pop and dispatch it, making the unit skip straight to the
	## next waypoint instead of ever visiting the first one.
	if status_activity == Activity.MOVING and nav_agent.is_navigation_finished() \
			and global_position.distance_to(nav_agent.target_position) <= nav_agent.target_desired_distance + 0.5:
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
			_clear_formation_cohesion()
			order_completed.emit()
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
	## Driven off the sprite's own already-cross-peer-correct animation state
	## (see _set_animation/animation_changed) rather than status_activity or
	## raw velocity directly — those are only reliable on the authoritative
	## peer, while every peer already shows the right walk/idle animation.
	if walk_dust:
		walk_dust.emitting = sprite.animation == "walk"

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
		var node := target_resource
		status_carried_amount += node.gather(amount)
		if is_instance_valid(node):
			resource_harvested.emit(node)

	if status_carried_amount >= carry_capacity or not is_instance_valid(target_resource):
		_head_to_dropoff()

func _head_to_dropoff() -> void:
	if status_carried_amount <= 0:
		_head_to_resource()
		return
	## Re-resolved on every trip rather than staying fixed to whatever
	## command_gather was handed, so a farmer walks to whichever Mill is
	## actually nearest right now — and so a drop-off built or destroyed
	## mid-gather is accounted for instead of stranding this unit.
	var nearest := _nearest_dropoff()
	if nearest != null:
		dropoff_point = nearest
	if not is_instance_valid(dropoff_point):
		dropoff_point = null
		_head_to_resource()
		return
	status_activity = Activity.TO_DROPOFF
	nav_agent.target_desired_distance = DROPOFF_ARRIVAL_DISTANCE
	move_to(dropoff_point.global_position)

## Closest DropoffPoint marker on a finished building this player owns that
## accepts what's currently being carried — a Mill only takes Food, so wood
## and gold keep going back to the Town Center. Host-only, like everything
## else driven from _physics_process.
func _nearest_dropoff() -> Node3D:
	var best: Node3D = null
	var best_distance: float = INF
	for node in get_tree().get_nodes_in_group("dropoff_points"):
		var building := node as ProductionBuilding
		if building == null or building.owner_peer_id != owner_peer_id or building.is_under_construction:
			continue
		if not building.accepts_dropoff(status_carried_type):
			continue
		var point: Node3D = building.get_node_or_null("DropoffPoint")
		if point == null:
			continue
		var distance: float = global_position.distance_to(point.global_position)
		if distance < best_distance:
			best_distance = distance
			best = point
	return best

func _deposit_and_continue() -> void:
	if status_carried_amount > 0 and status_carried_type != null:
		ResourceStockpile.add(owner_peer_id, status_carried_type, status_carried_amount)
		resource_deposited.emit(status_carried_amount, status_carried_type.display_color)
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

## Live Blacksmith weapon-upgrade bonus on top of the exported stat, same
## "computed live, not baked into the field itself" approach as the Monarch
## aura attack-speed bonus.
func _effective_attack_damage() -> int:
	return attack_damage + UnitUpgrades.get_weapon_bonus(owner_peer_id, unit_category)

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

## Whatever gets in front of a unit while it's closing on a target that's
## still a long way off is the more urgent problem. An assault produces exactly
## that situation every time it clears one spot and moves on to the next thing
## in the area, and without this the unit tunnel-visions on its distant target
## and walks straight through an enemy line — and, being Command.ATTACK
## already, doesn't even fight back when shot in the back, since take_damage
## reads an attacking unit as already engaged.
##
## Only applies under a live assault: a target the player picked out by hand is
## the one they want dead, and should not be second-guessed on the way there.
func _tick_approach_threats(delta: float) -> void:
	if not assault_active or not _is_target_alive(attack_target):
		return
	## Already closing on something within arm's reach — there's nothing
	## "nearer" left for a scan to find, so don't pay for one.
	if _flat_distance(global_position, attack_target.global_position) <= aggro_range:
		return
	_enemy_scan_timer -= delta
	if _enemy_scan_timer > 0.0:
		return
	_enemy_scan_timer = ENEMY_SCAN_INTERVAL
	var closer := _find_nearest_enemy_in_range(aggro_range)
	if closer != null and closer != attack_target:
		attack_target = closer
		_head_to_target()

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

	if leash_radius > 0.0 and global_position.distance_to(leash_origin.global_position) > leash_radius:
		attack_target = null
		_advance_patrol()
		return

	var dist := global_position.distance_to(attack_target.global_position)
	if dist > _effective_attack_range() * ATTACK_LEASH_SLACK:
		_head_to_target()
		return

	## Overkill guard: if enough shots are already in the air to finish this
	## target, go look for another one now instead of adding to the pile. The
	## target scans skip already-doomed targets too, so this can't just re-pick
	## the same one and spin.
	if not CombatUtils.is_worth_attacking(attack_target):
		_find_new_target_or_idle()
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
			attack_target.take_damage(_effective_attack_damage(), self)
			if not _is_target_alive(attack_target):
				_find_new_target_or_idle()

func _fire_projectile(target: Node3D) -> void:
	var dist := global_position.distance_to(target.global_position)
	var travel_time := dist / maxf(projectile_speed, 0.01)
	var damage := _effective_attack_damage()
	_pending_projectile_hits.append({
		"time_remaining": travel_time,
		"target": target,
		"damage": damage,
	})
	## Held against the target for exactly as long as this shot is airborne, and
	## released below however the shot ends — see CombatUtils.reserve_damage.
	CombatUtils.reserve_damage(target, damage)
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
		## Released whether the shot lands or the target died first — the
		## reservation only ever covers time in the air.
		CombatUtils.reserve_damage(target, -int(hit["damage"]))
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
		var nearest: Node3D = _find_assault_target() if assault_active \
				else _find_nearest_enemy_in_range(aggro_range)
		if nearest:
			attack_target = nearest
			_head_to_target()
		## Assault area is clear but the unit never actually got there — a fight
		## that started en route can end a long way short of the destination.
		## Walk the rest of the way, still scanning, rather than stopping
		## wherever the last kill happened to leave it.
		elif assault_active and _flat_distance(global_position, assault_center) > ASSAULT_AREA_RADIUS:
			attack_target = null
			status_command = Command.ATTACK_MOVE
			status_activity = Activity.MOVING
			## The group this unit marched out with has scattered into its own
			## fights by now, so this last leg is walked solo at full speed.
			formation_speed = -1.0
			_clear_formation_cohesion()
			nav_agent.target_desired_distance = MOVE_ARRIVAL_DISTANCE
			move_to(assault_center)
		else:
			## assault_active is deliberately left set here: the unit holds the
			## ground it took, and the idle scan in _physics_process keeps
			## watching the whole area for anything that wanders back into it.
			attack_target = null
			status_command = Command.NONE
			status_activity = Activity.IDLE
			order_completed.emit()
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

## Target priority for a unit under a standing attack-move order:
##   1. anything already inside its own aggro bubble (self-defense, and what it
##      runs into on the way there),
##   2. then enemy units inside the assault area,
##   3. then enemy buildings inside the assault area.
## Units before buildings deliberately — an army that stops to chew a farm while
## archers shoot it in the back is the classic attack-ground failure. Returns
## null once the area holds nothing worth attacking, which is what ends the
## order (see _find_new_target_or_idle).
func _find_assault_target() -> Node3D:
	var nearest: Node3D = _find_nearest_enemy_in_range(aggro_range)
	if nearest != null or not assault_active:
		return nearest
	nearest = _nearest_in_assault_area(&"units")
	if nearest != null:
		return nearest
	return _nearest_in_assault_area(&"buildings")

## Nearest living, not-already-doomed enemy of the given group whose own
## position is inside the assault area. Membership is measured from
## assault_center rather than from this unit, so every member of an assaulting
## group agrees on which targets are in scope instead of each peeling off after
## whatever happens to be nearest to it personally; distance from this unit is
## only the tie-break between those in-scope targets.
func _nearest_in_assault_area(group: StringName) -> Node3D:
	var nearest: Node3D = null
	var nearest_dist := INF
	for node in get_tree().get_nodes_in_group(group):
		var candidate := node as Node3D
		if candidate == null or candidate == self:
			continue
		if not (candidate is Unit or candidate is ProductionBuilding):
			continue
		if candidate.owner_peer_id == owner_peer_id or not _is_target_alive(candidate):
			continue
		if not CombatUtils.is_worth_attacking(candidate):
			continue
		if _flat_distance(assault_center, candidate.global_position) > ASSAULT_AREA_RADIUS:
			continue
		var dist := _flat_distance(global_position, candidate.global_position)
		if dist < nearest_dist:
			nearest = candidate
			nearest_dist = dist
	return nearest

## XZ-plane distance: vertical separation on sloped terrain shouldn't count
## toward whether something is inside the area the player clicked.
func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))

func _find_nearest_enemy_in_range(search_range: float) -> Unit:
	var nearest: Unit = null
	var nearest_dist := search_range
	for node in get_tree().get_nodes_in_group("units"):
		if node == self or not (node is Unit):
			continue
		var other: Unit = node
		if other.owner_peer_id == owner_peer_id or not _is_target_alive(other):
			continue
		## Overkill guard: a target that already has enough arrows in the air to
		## kill it isn't worth another shot. Skipping it here is what spreads a
		## volley across the enemy line instead of stacking it on one dying unit.
		if not CombatUtils.is_worth_attacking(other):
			continue
		if leash_radius > 0.0 and leash_origin.global_position.distance_to(other.global_position) > leash_radius:
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
	assault_active = false
	_leave_build_site()
	_leave_gather_site()
	## take_damage() (the only caller of _die()) already gates on
	## is_multiplayer_authority(), so this only ever runs once, on the host.
	Population.release(owner_peer_id, population_cost)

	## A unit spawned at runtime through UnitSpawner is auto-despawned on
	## every client the moment the host frees it — but a hand-placed unit
	## (e.g. an Objective's guards, present in the scene file itself rather
	## than spawned) has no spawner tracking it, so nothing ever tells
	## clients to remove it. This RPC covers both cases identically: it plays
	## the death animation and frees the node on every peer, not just here.
	_play_death_and_remove.rpc()

@rpc("authority", "call_local", "reliable")
func _play_death_and_remove() -> void:
	if sprite.sprite_frames and sprite.sprite_frames.has_animation("death"):
		_set_animation("death")
		var frame_count: int = sprite.sprite_frames.get_frame_count("death")
		var fps: float = sprite.sprite_frames.get_animation_speed("death")
		await get_tree().create_timer(frame_count / maxf(fps, 1.0)).timeout
	queue_free()
