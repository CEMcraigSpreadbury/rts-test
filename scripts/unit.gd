extends CharacterBody3D
class_name Unit

const SpriteSheetFrames = preload("res://scripts/sprite_sheet_frames.gd")
const UnitSilhouetteMaterial = preload("res://scripts/unit_silhouette_material.gd")
const UnitGrid = preload("res://scripts/unit_grid.gd")

const GRAVITY: float = 20.0
## The sheets in assets/art face right by default; flip_h mirrors them to face left.
const FLIP_DOT_THRESHOLD: float = 0.15
## Nudges the crew sprite (see crew_sprite_sheet) slightly away from the
## camera so the machine it's pushing draws over it where they overlap.
const CREW_DEPTH_OFFSET: float = 0.05
## Below this actual speed the unit is considered stopped (e.g. blocked by another unit).
const MOVING_SPEED_THRESHOLD: float = 0.15
const MOVE_ARRIVAL_DISTANCE: float = 0.5
## A unit's footprint radius for group planning — the physical capsule on
## scenes/units/unit.tscn is 0.4, plus a little room. Used by GroupMovement to
## decide which openings a unit can fit through.
const FORMATION_BASE_RADIUS: float = 0.45
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
## Drop-off points sit outside a building's footprint, so this
## needs more slack than a plain move order to reliably register as "arrived".
const DROPOFF_ARRIVAL_DISTANCE: float = 1.0
## How much further than attack_range a target can drift before we bother re-approaching.
const ATTACK_LEASH_SLACK: float = 1.2
## Building footprints keep units back, same as for melee attacks.
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
## How often a unit closing on a live target re-paths to where that target
## actually is now. Without this the nav destination is only ever the spot the
## target occupied when the chase started, so a unit walks to a stale position,
## finishes navigation, and only then notices the target has moved on — most
## visible on Objective guards, which chase in that stop-start way while the
## unit that aggro'd them keeps walking.
const CHASE_REPATH_INTERVAL: float = 0.2
## How far a target has to have drifted from the point we last pathed to before
## a repath is worth the cost — a target shuffling inside avoidance shouldn't
## reset the path every interval.
const CHASE_REPATH_EPSILON: float = 0.5
## How long a wandering unit pauses at the end of each leg, randomised per
## leg so a group of guards doesn't move in lockstep.
const WANDER_PAUSE_MIN: float = 1.0
const WANDER_PAUSE_MAX: float = 3.0
## Fraction of wander_radius a wander leg must at least cover, so legs are
## actual walks rather than a shuffle in place.
const WANDER_MIN_LEG_FRACTION: float = 0.35
## Multiplier applied when an attacker's damage_type matches its target's
## weak_to — see take_damage().
const WEAKNESS_DAMAGE_MULTIPLIER: float = 1.5
## Radius around an attack-move's destination that counts as "the place the
## player pointed at". A unit under that order keeps picking new targets
## inside this circle — enemy buildings included — until the area is clear or
## it's given another order. See _find_assault_target().
const ASSAULT_AREA_RADIUS: float = 12.0

## Separation: units have no avoidance and don't physically collide with other
## units, so this is the only thing keeping two units from standing in exactly
## the same spot — marching blocks, crowds and melee scrums alike. Any two
## living units closer than SEPARATION_DISTANCE (a little over two 0.4 body
## capsules) get nudged apart — except that a unit is never pushed by an enemy
## that is attacking it (see _update_separation).
## Only overlapping bodies are pushed, so formation slots (Formation.SPACING
## apart) and melee contact (attack_range apart) are never disturbed by it.
const SEPARATION_DISTANCE: float = 0.85
## Push speed at full overlap, scaled down linearly as bodies part.
const SEPARATION_SPEED: float = 3.0
const SEPARATION_MAX_SPEED: float = 2.5
## Recomputed on a short timer rather than every frame — cheap, and the push
## only has to be roughly current to read as bodies jostling apart.
const SEPARATION_INTERVAL: float = 0.1

## Melee crowding: each melee attacker already on a target makes it read this
## many meters further away to the target scans, so a line of melee units
## spreads across the enemy line instead of all picking the one nearest enemy.
const MELEE_CROWD_PENALTY: float = 1.2
## How many melee attackers can already be closer to a target than this unit
## before it looks for a less crowded enemy beside it (see _tick_melee_overflow).
const MELEE_CROWD_LIMIT: int = 3
## How far from the crowded target that replacement may stand — close enough
## that it's still "the same fight" the player sent them into.
const MELEE_OVERFLOW_RADIUS: float = 4.0
const MELEE_OVERFLOW_SCAN_INTERVAL: float = 0.3

## Melee reach: a melee unit can't swing through another body. Any living unit
## standing between it and its target — at least MELEE_BLOCK_MARGIN nearer the
## target and within MELEE_BLOCK_WIDTH of the line to it — blocks the swing, so
## only the front rank around a target fights and the ranks behind hold back
## instead of cramming in (see _melee_reach_blocked). Ring neighbours at the
## same distance sit well outside the corridor, so they never block each other.
const MELEE_BLOCK_WIDTH: float = 0.4
const MELEE_BLOCK_MARGIN: float = 0.25
## Only checked this close to the target (past its reach): further out a body
## in line is just someone in the way of the march, not a rank in front.
const MELEE_BLOCK_QUEUE_DEPTH: float = 3.0
const MELEE_BLOCK_CHECK_INTERVAL: float = 0.15

## The player's standing order. Move is one-shot; Gather/Attack/Build loop or
## hold (resource->dropoff->resource / target->next target / stay building
## until done) until interrupted or exhausted.
## CAST is one-shot like Move: walk into an ability's range, cast, go idle.
enum Command { NONE, MOVE, GATHER, ATTACK, BUILD, ATTACK_MOVE, PATROL, CAST }
## The current step within a command, e.g. Gather cycles TO_RESOURCE -> GATHERING -> TO_DROPOFF.
## CASTING holds the unit still while its cast animation plays out (see _perform_cast).
enum Activity { IDLE, MOVING, TO_RESOURCE, GATHERING, TO_DROPOFF, TO_TARGET, ATTACKING, TO_BUILD_SITE, BUILDING, DEAD, TO_CAST, CASTING }
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
## `attacker_path` is empty when nothing identifiable landed the hit, and
## `fatal` says whether this is the blow that kills — see take_damage, and
## main.gd, which relays both to drive the recoil direction and the attacker's
## kill hitstop on every peer.
signal damaged(amount: int, attacker_path: NodePath, fatal: bool)
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
## Host-only, fired the moment an activated ability actually goes off (after
## any walk into range). main.gd relays the cooldown to the owner's HUD and the
## impact visual to every peer. `ability_index` indexes get_abilities().
signal ability_cast(ability_index: int, target_pos: Vector3)
## Host-only, fired cast_windup seconds after ability_cast, when the ability
## actually leaves the caster. main.gd relays it so every peer flies the same
## projectile/wave and plays the impact when it lands; real damage is timed
## independently on the host by _pending_ability_hits.
signal ability_launched(ability_index: int, from_pos: Vector3, target_pos: Vector3)
## Host-only, relayed by main.gd so every peer shows burning/slowed/stunned
## on a unit hit by an area ability (the effects themselves are host-side).
signal status_applied(dot_seconds: float, slow_seconds: float, stun_seconds: float, color: Color)

## What this unit type is called in UI (info panel title, etc.) — unlike the
## scene node's own .name, this can't get an auto-incremented suffix (e.g.
## "Unit2") when several of the same unit are siblings under Units.
@export var display_name: String = "Villager"
@export var move_speed: float = 3.75
@export var rotation_speed: float = 10.0
## Setter (guarded — sprite isn't ready yet the first time Godot applies this
## from the scene file during instantiation) so an Objective capture can
## re-tint a unit immediately instead of only ever applying once in _ready().
@export var team_tint: Color = Color.WHITE:
	set(value):
		team_tint = value
		_update_team_tint_visual()
## Which player controls this unit. The host is always peer 1.
@export var owner_peer_id: int = 1:
	set(value):
		owner_peer_id = value
		_update_team_tint_visual()

## How much an enemy's team_tint still shows through — kept well under 1.0 so
## it reads as a subtle recolor rather than a flat-painted sprite.
const _ENEMY_TINT_STRENGTH: float = 0.35

## Only enemy units (relative to this viewer's own peer id) get team-colored —
## own/ally units keep their sprite's natural colors, since team_tint's whole
## purpose is telling enemies apart from a glance, not decorating your own
## army.
func _resting_modulate() -> Color:
	var base := Color.WHITE
	if owner_peer_id != multiplayer.get_unique_id():
		base = Color.WHITE.lerp(team_tint, _ENEMY_TINT_STRENGTH)
	if _status_tint_until_ms > Time.get_ticks_msec():
		base *= Color.WHITE.lerp(_status_tint, _STATUS_TINT_STRENGTH)
	if _buff_tint_until_ms > Time.get_ticks_msec():
		base *= Color.WHITE.lerp(_buff_tint, _BUFF_TINT_STRENGTH)
	return base

## Called from both team_tint's and owner_peer_id's setters (order of property
## application during scene instantiation isn't guaranteed) as well as
## _ready(), so whichever ends up set last still lands on the right result.
func _update_team_tint_visual() -> void:
	if sprite:
		sprite.modulate = _resting_modulate()
		## Rebuilt here too so an Objective capture recolors the silhouette.
		if sprite_sheet and not _death_playing:
			sprite.material_overlay = UnitSilhouetteMaterial.build(sprite_sheet, team_tint)
	if crew_sprite:
		crew_sprite.modulate = sprite.modulate
		if not _death_playing:
			crew_sprite.material_overlay = UnitSilhouetteMaterial.build(crew_sprite_sheet, team_tint)
## How far this unit reveals fog of war around itself.
@export var vision_range: float = 11.0
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
## Monarchs currently in the tree, any owner — lets CombatUtils skip its aura
## lookups (run on every attack and every hit) when there are none.
static var monarch_count: int = 0

@export_group("Sprite Sheet")
@export var sprite_sheet: Texture2D = preload("res://assets/art/MinifolksVillagers2/Blue/Outline/MiniGatherer.png")
@export var sprite_cell_size: Vector2i = Vector2i(32, 32)
@export var idle_row: int = 0
@export var idle_frame_count: int = 4
## The HUD and dialogue portrait: a rectangle of the first idle frame, in
## pixels within the cell. Left empty it is worked out from the art (see
## UnitPortrait) — set it for a unit whose face that gets wrong.
@export var portrait_region: Rect2i = Rect2i()
@export var walk_row: int = 1
@export var walk_frame_count: int = 5
@export var attack_row: int = 3
@export var attack_frame_count: int = 6
@export var death_row: int = 6
@export var death_frame_count: int = 4
## Only played by units with can_gather; harmless (just unused) otherwise.
@export var gather_row: int = 2
@export var gather_frame_count: int = 10
## Played when this unit uses an activated ability — the monsters' special-
## attack row. 0 frames = no cast clip; the ordinary attack swing stands in.
@export var cast_row: int = 4
@export var cast_frame_count: int = 0
@export var cast_fps: float = 12.0
## Optional second sprite drawn behind this one on screen, animated alongside
## it — e.g. the soldier pushing a siege weapon. Purely visual: it has no
## health of its own and plays its death clip when this unit dies.
@export var crew_sprite_sheet: Texture2D
@export var crew_idle_row: int = 0
@export var crew_idle_frame_count: int = 4
@export var crew_walk_row: int = 1
@export var crew_walk_frame_count: int = 6
@export var crew_death_row: int = 5
@export var crew_death_frame_count: int = 4
## How far behind the main sprite, along the screen's horizontal, the crew stands.
@export var crew_offset: float = 0.7

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
## Scales this unit's damage against buildings — siege weapons (Ballista,
## Magic Cannon) set it well above 1.
@export var building_damage_multiplier: float = 1.0
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

@export_group("Command Lines")
## What this unit type shouts back when the local player gives it an order —
## the words and the clip together, one list per command kind (keys match
## main.gd's _spawn_command_popup `kind`). Per unit type rather than one
## global pool on Main, because a villager, a knight and a hydra issuing the
## identical human "Moving!" was the single most obviously wrong thing about
## the order feedback.
##
## Empty means SILENT, not "fall back to a default": the monsters have no
## lines yet, and a fallback would put human speech back in their mouths,
## which is the exact bug this replaced. Authoring a "GRRR" line with a
## matching clip is what gives one a voice. Beastmen are commandable once
## their barracks is captured, so they inherit unit.tscn's human lines for
## now rather than being silenced.
@export var move_command_lines: Array[CommandLine] = []
@export var attack_command_lines: Array[CommandLine] = []
@export var patrol_command_lines: Array[CommandLine] = []
@export var build_command_lines: Array[CommandLine] = []

@export_group("Abilities")
## Abilities this unit type always has, promoted or not — e.g. each Shrine
## monster's area attack. Listed ahead of monarch_abilities on the command
## card and in ability indices (see get_abilities).
@export var abilities: Array[Ability] = []

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
## Built in _ready when crew_sprite_sheet is set; a child of `sprite` so it
## rides along with every recoil, squash and death-knockback tween.
var crew_sprite: AnimatedSprite3D = null
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

## This unit type's authored lines for `kind`, or an empty list if it has
## none (see the Command Lines group — empty means silent). A match rather
## than a Dictionary because the arrays are @export vars, which can't be
## referenced from a const.
func command_lines_for(kind: String) -> Array[CommandLine]:
	match kind:
		"move": return move_command_lines
		"attack": return attack_command_lines
		"patrol": return patrol_command_lines
		"build": return build_command_lines
	return []

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
		if value != is_monarch:
			monarch_count += 1 if value else -1
		is_monarch = value
		if crown_icon:
			crown_icon.visible = value

## Captured from the scene's authored (full-health) scale so the fill's
## aspect-ratio/sizing lives in the scene file, not duplicated in script.
var _fill_base_scale_x: float = 1.0

var _flash_tween: Tween

## Three separate tweens, one per sprite property, deliberately: a unit being
## hit mid-swing has to be able to flash, recoil and squash all at once. They
## only ever conflict within a property — a hit recoil cancelling an in-flight
## attack lunge, say — and there the newest event simply wins, since all of
## them ease back to the same authored base.
var _sprite_move_tween: Tween
var _sprite_scale_tween: Tween

## Captured from the scene rather than assumed, same reasoning as
## _fill_base_scale_x: the authored offset (the sprite sits above the unit's
## feet) lives in the scene file, and every motion below is an offset from it.
var _sprite_base_position: Vector3 = Vector3.ZERO
var _sprite_base_scale: Vector3 = Vector3.ONE

## Attack lunge. The windup pulls back away from the target before the sprite
## drives forward through it — melee at RTS camera height is only a few dozen
## pixels tall, and without the anticipation beat the swing reads as the sprite
## flickering rather than as a blow being thrown.
const ATTACK_WINDUP_DISTANCE: float = 0.09
const ATTACK_WINDUP_DURATION: float = 0.06
const ATTACK_LUNGE_DISTANCE: float = 0.16
const ATTACK_LUNGE_DURATION: float = 0.07
const ATTACK_RECOVER_DURATION: float = 0.18

## Hit recoil. Deliberately smaller than the lunge: the unit taking the blow
## should look shoved, not launched, and an over-large nudge on a tightly
## packed battle line reads as the whole formation jittering.
const HIT_RECOIL_DISTANCE: float = 0.11
const HIT_RECOIL_DURATION: float = 0.05
const HIT_RECOVER_DURATION: float = 0.2
const HIT_SQUASH_SCALE: Vector3 = Vector3(1.16, 0.84, 1.16)
const HIT_SQUASH_DURATION: float = 0.28

## Hitstop on the killing blow — the attacker's own animation freezes for a
## beat so a kill lands harder than an ordinary hit. Per-sprite rather than
## Engine.time_scale, which would desync every other peer's simulation.
const HITSTOP_DURATION: float = 0.07

var _hitstop_tween: Tween

## Death knockback: the corpse is launched away from the killing blow and
## bounces to a stop before the death clip plays. Bounce durations follow
## real projectile time for each height under DEATH_BOUNCE_GRAVITY, and the
## horizontal speed bleeds off each bounce so it skids to a halt rather than
## stopping dead at the end of the last hop.
const DEATH_KNOCKBACK_DISTANCE: float = 1.4
const DEATH_BOUNCE_HEIGHTS := [0.75, 0.32, 0.13, 0.05]
const DEATH_BOUNCE_GRAVITY: float = 22.0
const DEATH_BOUNCE_SPEED_DECAY: float = 0.6
const DEATH_LAUNCH_STRETCH_SCALE: Vector3 = Vector3(0.8, 1.25, 0.8)
const DEATH_LAND_SQUASH_SCALE: Vector3 = Vector3(1.35, 0.65, 1.35)
const DEATH_LAND_SQUASH_DURATION: float = 0.25

## Set locally on every peer by the death RPC. Hit reactions and lunges can
## still arrive over the wire after it, and both drive the same sprite
## properties the knockback does.
var _death_playing: bool = false

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

## The full reaction to taking a hit: flash, a shove directly away from
## whatever landed it, and a squash that settles elastically. `from_position`
## is the attacker's position; passing this unit's own position (what main.gd
## does when the attacker is gone or unknown) means "no direction", and the
## recoil is skipped so the unit doesn't lurch off in an arbitrary direction.
func play_hit_reaction(from_position: Vector3) -> void:
	if _death_playing:
		return
	play_hit_flash()
	_play_hit_squash()
	var away := global_position - from_position
	away.y = 0.0
	if away.length_squared() <= 0.0001:
		return
	## The sprite is a child of a unit that rotates to face its own target, so a
	## world-space direction has to come back into the sprite's local space or
	## the recoil would point somewhere different depending on which way the
	## unit happens to be turned. Y rotation only, so the basis inverse is exact.
	var local_away: Vector3 = global_transform.basis.inverse() * away.normalized()
	var base := _sprite_base_position
	_restart_sprite_move_tween()
	_sprite_move_tween.tween_property(
			sprite, "position", base + local_away * HIT_RECOIL_DISTANCE, HIT_RECOIL_DURATION
	) 			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_sprite_move_tween.tween_property(sprite, "position", base, HIT_RECOVER_DURATION) 			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _play_hit_squash() -> void:
	if _sprite_scale_tween and _sprite_scale_tween.is_valid():
		_sprite_scale_tween.kill()
	sprite.scale = _sprite_base_scale * HIT_SQUASH_SCALE
	_sprite_scale_tween = create_tween()
	_sprite_scale_tween.tween_property(sprite, "scale", _sprite_base_scale, HIT_SQUASH_DURATION) 			.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

## Windup-then-drive-forward on the sprite, along the unit's own facing (local
## +Z — see _process, which reads the same forward vector off rotation.y to
## decide sprite flipping). Public because remote peers never run
## _play_attack_swing: they're handed the bare animation name over the wire and
## main.gd calls this alongside it. Facing is replicated, so every peer derives
## the same direction without anything extra going over the network.
func play_attack_lunge() -> void:
	if _death_playing:
		return
	var base := _sprite_base_position
	_restart_sprite_move_tween()
	_sprite_move_tween.tween_property(
			sprite, "position", base - Vector3(0.0, 0.0, ATTACK_WINDUP_DISTANCE), ATTACK_WINDUP_DURATION
	) 			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	## Eased IN so the sprite accelerates through the contact point rather than
	## arriving already slowing down.
	_sprite_move_tween.tween_property(
			sprite, "position", base + Vector3(0.0, 0.0, ATTACK_LUNGE_DISTANCE), ATTACK_LUNGE_DURATION
	) 			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_sprite_move_tween.tween_property(sprite, "position", base, ATTACK_RECOVER_DURATION) 			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Freezes this unit's animation for a beat after it lands a killing blow.
## speed_scale rather than pause() so the clip resumes from where it stopped,
## and the restore is a tween callback so it dies with the node if this unit is
## freed mid-hitstop instead of leaving a frozen sprite behind.
func play_hitstop() -> void:
	if _hitstop_tween and _hitstop_tween.is_valid():
		_hitstop_tween.kill()
	sprite.speed_scale = 0.0
	_hitstop_tween = create_tween()
	_hitstop_tween.tween_interval(HITSTOP_DURATION)
	_hitstop_tween.tween_callback(func() -> void: sprite.speed_scale = 1.0)

## --- Status effect visuals ---
## Purely local, on every peer (main.gd relays status_applied), mirroring the
## host-only _dots/_slow_remaining/_stun_remaining that actually do the work.
## Each is timed off its own expiry rather than reading those back, since they
## only exist on the host.

## How far a slowed unit's sprite is tinted toward the ability's colour.
const _STATUS_TINT_STRENGTH: float = 0.55
const STUN_STAR_COUNT: int = 3
const STUN_STAR_HEIGHT: float = 1.9
const STUN_STAR_RADIUS: float = 0.32
const STUN_STAR_SPIN_SPEED: float = 5.0

var _status_tint: Color = Color.WHITE
var _status_tint_until_ms: int = 0
## A Ruler power's buff (or Curse) on this unit — lighter than the status
## tint, so it reads as a wash of colour rather than a burn or chill.
const _BUFF_TINT_STRENGTH: float = 0.3
var _buff_tint: Color = Color.WHITE
var _buff_tint_until_ms: int = 0
var _dot_until_ms: int = 0
var _stun_until_ms: int = 0
var _dot_particles: GPUParticles3D = null
var _stun_stars: Node3D = null

static var _status_particle_mesh: QuadMesh = null
static var _stun_star_mesh: QuadMesh = null

func show_status_effects(dot_seconds: float, slow_seconds: float, stun_seconds: float, color: Color) -> void:
	if _death_playing:
		return
	var now := Time.get_ticks_msec()
	if slow_seconds > 0.0:
		_status_tint = color
		_status_tint_until_ms = maxi(_status_tint_until_ms, now + int(slow_seconds * 1000.0))
		_update_team_tint_visual()
	if dot_seconds > 0.0:
		_dot_until_ms = maxi(_dot_until_ms, now + int(dot_seconds * 1000.0))
		_ensure_dot_particles()
		(_dot_particles.process_material as ParticleProcessMaterial).color = color
		_dot_particles.emitting = true
	if stun_seconds > 0.0:
		_stun_until_ms = maxi(_stun_until_ms, now + int(stun_seconds * 1000.0))
		_ensure_stun_stars()
		_stun_stars.visible = true

## Every peer, relayed by WorldFeedback.relay_buff_tints.
func show_buff_tint(color: Color, seconds: float) -> void:
	if _death_playing:
		return
	_buff_tint = color
	_buff_tint_until_ms = maxi(_buff_tint_until_ms, Time.get_ticks_msec() + int(seconds * 1000.0))
	_update_team_tint_visual()

## Called every frame from _process; cheap when nothing is active.
func _update_status_visuals(delta: float) -> void:
	if _buff_tint_until_ms == 0 and _status_tint_until_ms == 0 and _dot_particles == null and _stun_stars == null:
		return
	var now := Time.get_ticks_msec()
	if _buff_tint_until_ms != 0 and now >= _buff_tint_until_ms:
		_buff_tint_until_ms = 0
		_update_team_tint_visual()
	if _status_tint_until_ms != 0 and now >= _status_tint_until_ms:
		_status_tint_until_ms = 0
		_update_team_tint_visual()
	if _dot_particles and _dot_particles.emitting and (now >= _dot_until_ms or _death_playing):
		_dot_particles.emitting = false
	if _stun_stars and _stun_stars.visible:
		if now >= _stun_until_ms or _death_playing:
			_stun_stars.visible = false
		else:
			_stun_stars.rotation.y += STUN_STAR_SPIN_SPEED * delta

## Embers/bubbles rising off the body for as long as a burn or poison lasts.
## Local coords off so they trail behind a unit that walks out of the cloud.
func _ensure_dot_particles() -> void:
	if _dot_particles:
		return
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.35
	process.direction = Vector3.UP
	process.spread = 20.0
	process.initial_velocity_min = 0.6
	process.initial_velocity_max = 1.3
	process.gravity = Vector3(0, 0.6, 0)
	process.scale_min = 0.6
	process.scale_max = 1.2
	var fade := Gradient.new()
	fade.set_color(0, Color.WHITE)
	fade.set_color(1, Color(1, 1, 1, 0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	_dot_particles = GPUParticles3D.new()
	_dot_particles.amount = 12
	_dot_particles.lifetime = 0.7
	_dot_particles.process_material = process
	_dot_particles.draw_pass_1 = _status_quad_mesh()
	_dot_particles.position = Vector3(0, 0.7, 0)
	_dot_particles.emitting = false
	add_child(_dot_particles)

func _ensure_stun_stars() -> void:
	if _stun_stars:
		return
	if _stun_star_mesh == null:
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.albedo_color = Color(1.0, 0.92, 0.35)
		_stun_star_mesh = QuadMesh.new()
		_stun_star_mesh.size = Vector2(0.13, 0.13)
		_stun_star_mesh.material = material
	_stun_stars = Node3D.new()
	_stun_stars.position = Vector3(0, STUN_STAR_HEIGHT, 0)
	for i in STUN_STAR_COUNT:
		var star := MeshInstance3D.new()
		star.mesh = _stun_star_mesh
		star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var angle := TAU * i / STUN_STAR_COUNT
		star.position = Vector3(cos(angle), 0.0, sin(angle)) * STUN_STAR_RADIUS
		_stun_stars.add_child(star)
	add_child(_stun_stars)

static func _status_quad_mesh() -> QuadMesh:
	if _status_particle_mesh == null:
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.vertex_color_use_as_albedo = true
		material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		material.billboard_keep_scale = true
		_status_particle_mesh = QuadMesh.new()
		_status_particle_mesh.size = Vector2(0.12, 0.12)
		_status_particle_mesh.material = material
	return _status_particle_mesh

## Both sprite motions (attack lunge and hit recoil) drive the same property,
## so they share one tween — whichever fires last takes over, from wherever the
## sprite currently is, and still ends at the authored base.
func _restart_sprite_move_tween() -> void:
	if _sprite_move_tween and _sprite_move_tween.is_valid():
		_sprite_move_tween.kill()
	_sprite_move_tween = create_tween()

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

## Host-only: the right-drag formation this unit was last laid out in, if its
## group is still using it — see GroupMovement.resolve_dragged_width.
var dragged_formation: Dictionary = {}

## Host-only: the way this unit's last formation order faced (see
## GroupMovement.order_facing), or ZERO once it has had a solo move or a
## non-formation order. An idle unit turns back to it, so a block stands facing
## its front however it walked there and the next order reads that front.
var formation_facing: Vector3 = Vector3.ZERO
## Host-only. The formation group (see formation_group) whose move this unit
## finished — at its slot, or settled short of one it couldn't reach — so
## GroupMovement's ranks-closing knows it's standing in its place even after
## separation has nudged it about. Cleared by the next move leg.
var arrived_group: Array[Unit] = []

## Formation marching state (see GroupMovement's Marching section) — host-only.
## While _march_active the unit holds its place relative to the group's moving
## anchor, steering at _march_point and matching _march_velocity, rather than
## walking straight to its slot; the slot itself is parked in
## _march_final_target until end_march hands it back to the nav agent.
var _march_active: bool = false
var _march_point: Vector3 = Vector3.ZERO
var _march_velocity: Vector3 = Vector3.ZERO
var _march_final_target: Vector3 = Vector3.ZERO
## Within this distance of its marching point a unit steers straight at it;
## further out (knocked aside, or held up behind something) it paths there.
const MARCH_DIRECT_DISTANCE: float = 2.0
## How hard a marching unit is pulled back onto its point, per meter off it.
const MARCH_CORRECTION_GAIN: float = 2.0
## A marching unit more than MARCH_CATCH_UP_DISTANCE off its point hurries at
## this multiple of its speed — the anchor walks at nearly full pace, so at
## normal speed a straggler that went round an obstacle would barely gain on it.
const MARCH_CATCH_UP_SPEED: float = 1.3
const MARCH_CATCH_UP_DISTANCE: float = 1.0
## How far the marching point may drift from the nav target before re-pathing.
## The path only has to get the unit round whatever it's stuck behind — once
## it's finished the unit closes the rest straight — so it can go a while stale.
const MARCH_REPATH_DISTANCE: float = 2.0
## Fewest seconds between those re-paths — each is a full navmesh query, and
## a block flowing round a wood has a hundred members pathing at once. Game
## time, so it holds at any frame rate or game speed.
const MARCH_REPATH_INTERVAL: float = 1.0
var _march_recheck_in: float = 0.0
## Pathing to its marching point rather than steering straight at it (see
## _march_desired_velocity).
var _march_pathing: bool = false

## Path-query gating (see PathBudget). The agent only searches for a path when
## asked for its next waypoint, so the two places that ask go through
## _path_ready() first: a target the agent hasn't pathed to yet waits for its
## turn in the budget, and meanwhile the unit steers straight at it.
## The target the agent last computed a path to.
var _path_target: Vector3 = Vector3.INF
## repath() re-issues the same target on purpose, which the comparison above
## can't see.
var _path_stale: bool = false
## Waiting in PathBudget's queue / cleared to query on this or the next tick.
var _path_queued: bool = false
## Physics frame PathBudget gave this unit its turn on, or -1.
var _path_granted_frame: int = -1
## The navigation map iteration the agent's path was computed on (see
## PathBudget.map_iteration).
var _path_iteration: int = -1

const COHESION_RECHECK_INTERVAL: float = 0.2
## Most groupmates a unit averages over per recheck (see _update_cohesion).
const COHESION_SAMPLE_SIZE: int = 24
## This unit's _formation_progress() as of its last cohesion recheck — what
## groupmates read instead of recomputing it.
var _cohesion_progress: float = 0.0
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
## What to look for, and where to look from, once target_resource runs out.
## Null type = the node doesn't seek_replacement_when_depleted, so just stop.
var _replacement_resource_type: ResourceType = null
var _last_resource_position: Vector3 = Vector3.ZERO
## How far from the felled node a replacement may be — past this the unit
## idles rather than trekking off across the map on its own.
const RESOURCE_RETARGET_RADIUS: float = 15.0
## Unit or ProductionBuilding — anything with owner_peer_id/current_health/take_damage().
## Setter keeps the target's melee_attackers count in step, whichever of the
## many code paths below retargets this unit.
var attack_target: Node3D = null:
	set(value):
		if value == attack_target:
			return
		var melee := _counts_as_melee()
		if melee and is_instance_valid(attack_target) and attack_target is Unit:
			attack_target.melee_attackers = maxi(attack_target.melee_attackers - 1, 0)
		attack_target = value
		if melee and is_instance_valid(value) and value is Unit:
			value.melee_attackers += 1
## Host only: how many melee units currently have this unit as attack_target.
var melee_attackers: int = 0
var _separation_timer: float = randf() * SEPARATION_INTERVAL
var _separation_velocity: Vector3 = Vector3.ZERO
var _overflow_scan_timer: float = 0.0
var _reach_check_timer: float = randf() * MELEE_BLOCK_CHECK_INTERVAL
var _reach_blocked: bool = false
## Earliest Time.get_ticks_msec() this unit may call allies in again (see take_damage).
var _next_alert_ms: int = 0
## How long this unit's move path has been over without reaching its target
## (see _apply_velocity), and how long that's allowed before it gives up.
var _path_end_timer: float = 0.0
const PATH_END_GIVE_UP: float = 1.0
var attack_timer: float = 0.0
var build_target: ProductionBuilding = null
## Progress-stall tracking for _tick_build_approach() while heading to
## build_target — reset whenever a new build site is targeted.
var _build_stuck_timer: float = 0.0
var _build_stuck_check_pos: Vector3 = Vector3.ZERO
var _dying: bool = false
var patrol_points: Array[Vector3] = []
var patrol_index: int = 0
## Wander mode (see command_wander) — objective guards mill about near their
## building instead of walking a fixed loop. Runs as Command.PATROL so all the
## engage/resume handling applies unchanged; the only difference is that each
## leg picks a fresh random point near wander_origin rather than stepping
## through patrol_points. 0.0 = normal patrol.
var wander_origin: Node3D = null
var wander_radius: float = 0.0
## Counts down while a wandering unit is standing still between legs.
var _wander_pause_timer: float = 0.0
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
	arrived_group = []
	if group.is_empty():
		formation_facing = Vector3.ZERO
	formation_initial_distance = global_position.distance_to(target_position) if not group.is_empty() else 0.0
	_cohesion_recheck_timer = 0.0
	_cohesion_progress = 0.0
	_cohesion_target_speed_scale = 1.0
	_cohesion_speed_scale = 1.0
	_cohesion_last_remaining_distance = -1.0
	_cohesion_stall_timer = 0.0
	_cohesion_hard_stall_timer = 0.0
	_cohesion_stalled = false
	_march_active = false
	## Any fresh move leg starts un-funnelled by definition; main.gd re-arms it
	## immediately afterwards (via set_funnel_waypoint) if this particular leg's
	## route actually needs one. Clearing here rather than only in command_move
	## means every path that (re)baselines cohesion also drops a stale funnel,
	## including the re-baseline _update_funnel itself does on release.
	_funnel_active = false

func _clear_formation_cohesion() -> void:
	_funnel_active = false
	_march_active = false
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
## Player-toggled stance (see Main.toggle_hold_position): while standing idle
## the unit only takes on enemies already within attack_range and never walks
## out to meet them. Replicated so every peer's command card shows the state.
## Explicit orders (move, attack, attack-move, patrol) still behave as normal.
var hold_position: bool = false
## Host-only. Set when this unit's group was ordered to attack as a formation
## (see GroupMovement.formation_attack): it marches to its slot in the block,
## then fights from there like a holding unit — only what's within reach, the
## ordered target first — instead of each man chasing the target down on his
## own and the block ending up as a ring round it. Any other order ends it.
var in_formation_fight: bool = false
var formation_attack_target: Node3D = null
## Host-only. The group attack-move this unit is on, shared by the whole group
## (see GroupMovement.register_formation): what lets the group stop and fight
## an enemy as a block and then carry on (GroupMovement.formation_contact).
## Empty for a lone unit, and forgotten on any other order.
var attack_move_order: Dictionary = {}
## Which of GroupMovement's engagements this unit fights in.
var formation_fight_id: int = -1
## Where this unit stands in the fighting block — its slot, or wherever its
## move actually ended if the slot couldn't be reached — which it walks back
## to when shoved out of place (see _tick_formation_place).
var formation_fight_place: Vector3 = Vector3.ZERO
## Idle and this far out of place: walk back. Stops once within
## FORMATION_PLACE_SETTLED, so it doesn't twitch at the edge.
const FORMATION_PLACE_RETURN: float = 0.8
const FORMATION_PLACE_SETTLED: float = 0.25
## Shooting and shoved this far out of place: break off and go back first.
## A melee member may be out by its step as well (see MELEE_FORMATION_STEP).
const FORMATION_PLACE_DRIFT_MAX: float = 2.0
## How far a melee member of a fighting block steps out of line to strike an
## enemy — its reach is counted from its place, not from wherever it stands.
## Ranged members shoot from where they stand.
const MELEE_FORMATION_STEP: float = 2.0
var _returning_to_place: bool = false
## Set when a holding unit picked its current fight up by itself rather than
## being ordered into it, so it lets the target go instead of chasing it.
var _hold_engagement: bool = false
## Counts down while attack-moving/patrolling; scanning for enemies every frame
## would be an unthrottled O(units x units) group scan, so this paces it instead.
var _enemy_scan_timer: float = 0.0
## Paces the chase repath in _tick_chase, and the target position that repath
## last pathed to (compared against CHASE_REPATH_EPSILON).
var _chase_repath_timer: float = 0.0
var _chase_target_position: Vector3 = Vector3.ZERO
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
## Host-only: ability index (within get_abilities()) -> Time.get_ticks_msec()
## when it's usable again. Not synced — only the host ever enforces cooldowns.
var _ability_ready_at_ms: Dictionary = {}
## The owner's local copy of the same thing, on the owner's own clock — set
## by main.gd's cooldown relay (via start_local_cooldown) and read only by the
## HUD button. The duration is kept alongside so the button's sweep knows how
## far through the cooldown it is.
var local_ability_ready_at_ms: Dictionary = {}
var _local_ability_cooldown_ms: Dictionary = {}
## Host-only Command.CAST state: which ability, aimed where, and how long the
## walk into range has been going (see _tick_cast_approach).
var _cast_ability_index: int = -1
var _cast_target: Vector3 = Vector3.ZERO
var _cast_approach_time: float = 0.0
## A freshly issued move_to() can read as navigation-finished for a frame or
## two before its path exists (see _apply_velocity), so a cast approach
## doesn't give up on an unreachable target until this long has passed.
const CAST_GIVE_UP_GRACE: float = 0.3
## Host-only. Abilities whose cast animation has started but that haven't
## gone off yet: {"index": int, "ability": Ability, "target": Vector3,
## "time_remaining": float}. Ticked independently of status_activity, so an
## order given mid-windup walks the caster away without cancelling the
## ability it has already paid for — see _tick_pending_casts.
var _pending_casts: Array[Dictionary] = []
## Host-only. Area abilities in flight: {"ability": Ability, "target": Vector3,
## "time_remaining": float}. Like _pending_projectile_hits, keeps ticking after
## the caster dies so a fireball already in the air still lands.
var _pending_ability_hits: Array[Dictionary] = []
## How long this unit stays in Activity.CASTING — the cast animation's length,
## but never shorter than the windup, so it's still standing there facing the
## target at the moment the ability actually goes off.
var _casting_time_remaining: float = 0.0

## Host-only status effects applied by area abilities (see apply_ability_hit).
## Each DoT entry is {"dps": int, "ticks_left": int, "tick_timer": float,
## "source": Node3D}; overlapping DoTs stack, slow and stun just extend.
var _dots: Array[Dictionary] = []
var _slow_fraction: float = 0.0
var _slow_remaining: float = 0.0
var _stun_remaining: float = 0.0

func _ready() -> void:
	status_current_health = max_health
	if health_bar_fill:
		_fill_base_scale_x = health_bar_fill.scale.x
	_sprite_base_position = sprite.position
	_sprite_base_scale = sprite.scale
	if sprite_sheet:
		var animations := {
			"idle": {"row": idle_row, "frames": idle_frame_count, "fps": 5.0, "loop": true},
			"walk": {"row": walk_row, "frames": walk_frame_count, "fps": 8.0, "loop": true},
			"attack": {"row": attack_row, "frames": attack_frame_count, "fps": 10.0, "loop": false},
			"death": {"row": death_row, "frames": death_frame_count, "fps": 8.0, "loop": false},
			"gather": {"row": gather_row, "frames": gather_frame_count, "fps": 8.0, "loop": true},
		}
		if cast_frame_count > 0:
			animations["cast"] = {"row": cast_row, "frames": cast_frame_count, "fps": cast_fps, "loop": false}
		sprite.sprite_frames = SpriteSheetFrames.build(sprite_sheet, sprite_cell_size, animations)
		sprite.play("idle")
	if crew_sprite_sheet:
		_build_crew_sprite()
	sprite.animation_finished.connect(_on_attack_animation_finished)
	_update_team_tint_visual()
	## Waypoints sit on the navmesh, which on hilly terrain can be a few tenths
	## of a metre off the ground the unit stands on, and the agent measures this
	## in 3D: too tight and a unit can fail to "reach" a waypoint it has walked
	## past, turning back to it and sticking on the slope.
	nav_agent.path_desired_distance = 1.0
	## Keeps a unit on the ground walking down hills instead of briefly
	## leaving it (and falling) each time the slope steepens.
	floor_snap_length = 0.4
	nav_agent.target_desired_distance = MOVE_ARRIVAL_DISTANCE
	## The agent re-runs its path query by itself once the unit is this far off
	## its path, which goes round PathBudget — a marching unit that followed its
	## anchor away from an old catch-up path set off hundreds at once. Wedged
	## units re-path through the budget instead (see _track_blocked).
	nav_agent.path_max_distance = 1000.0
	## No RVO avoidance: it ran every agent (and every tree's obstacle) through
	## the avoidance solver each physics frame and answered through a callback,
	## which didn't scale to armies. The agent only plans paths now; units keep
	## apart with _update_separation and steer in _physics_tick directly.
	nav_agent.avoidance_enabled = false
	## The agent's target defaults to the world origin, which repath() would
	## otherwise re-issue after the first navmesh rebake — sending every idle
	## unit walking to the middle of the map.
	nav_agent.target_position = global_position
	if is_multiplayer_authority() and OS.is_debug_build():
		nav_agent.path_changed.connect(_on_path_changed)

func _on_path_changed() -> void:
	if PerfStats.enabled:
		PerfStats.count_path()

func _exit_tree() -> void:
	if is_monarch:
		monarch_count -= 1
		is_monarch = false

## Raw navigation command; prefer command_move / command_gather / command_attack which also manage status.
func move_to(target_position: Vector3) -> void:
	nav_agent.target_position = target_position

## Re-runs the path query against whatever the navmesh looks like right now,
## without disturbing where this unit was already heading. Called by
## NavigationBlockers after it rebakes the region around a building that was
## just placed or destroyed, so a unit mid-walk stops following a route that
## no longer exists. Assigning target_position is the hook for this:
## NavigationAgent3D deliberately never early-outs on an unchanged value.
func repath() -> void:
	## nav_agent is @onready, and group membership starts one notification
	## earlier than _ready — a bake landing in that window would otherwise
	## reach a unit that hasn't resolved it yet.
	if nav_agent == null or status_activity == Activity.DEAD:
		return
	var target: Vector3 = nav_agent.target_position
	nav_agent.target_position = target
	_path_stale = true

## True when the agent may be asked about its path this tick — its path is
## already for the current target, or PathBudget has just given this unit its
## turn to compute one. Otherwise queues the unit (once) and returns false.
## Gates is_navigation_finished() as well as get_next_path_position(): both
## run the path query themselves whenever the target has changed. An empty
## path counts as not ready too, since the agent re-queries an empty path on
## every call (a unit stuck off the navmesh would otherwise search each frame).
func _path_ready() -> bool:
	var target: Vector3 = nav_agent.target_position
	var iteration := PathBudget.map_iteration(nav_agent.get_navigation_map())
	if not _path_stale and target == _path_target and iteration == _path_iteration \
			and not nav_agent.get_current_navigation_path().is_empty():
		return true
	PathBudget.serve()
	if _path_granted_frame >= 0:
		var fresh: bool = _path_granted_frame >= Engine.get_physics_frames() - 1
		_path_granted_frame = -1
		_path_queued = false
		## A turn only counts on the tick it's given or the next. An unused one
		## (a marching unit that stopped needing its path) would otherwise sit
		## there until the next retarget, and a whole army spending theirs on
		## the same tick — every member released at the end of a march — is
		## exactly the burst the budget exists to prevent.
		if fresh:
			_path_stale = false
			_path_target = target
			_path_iteration = iteration
			return true
	if not _path_queued:
		_path_queued = true
		PathBudget.enqueue(self)
	return false

## is_navigation_finished() through the path budget: a target that's still
## waiting for its path isn't finished.
func _nav_finished() -> bool:
	return _path_ready() and nav_agent.is_navigation_finished()

## Flat direction to the nav target, for steering while a path is still queued.
func _straight_direction() -> Vector3:
	var direction := nav_agent.target_position - global_position
	direction.y = 0.0
	return direction.normalized() if direction.length_squared() > 0.0001 else Vector3.ZERO

func command_move(target_position: Vector3, speed_override: float = -1.0, group: Array[Unit] = []) -> void:
	if status_activity == Activity.DEAD:
		return
	_end_formation_fight()
	attack_move_order = {}
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
	## _update_cohesion and _formation_progress read progress as
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

## Read-only view of the funnel state for the host-side reformation pass
## (main.gd:_update_reformation): a group that is currently threading a
## chokepoint must not have its slots re-solved underneath it, or units
## mid-gap get sent straight at a far-side slot through the wall they were
## being funnelled around. Reformation defers until nobody is funnelling.
func is_funnelling() -> bool:
	return _funnel_active

## Where this unit's current formation order is taking it, even while a
## funnel waypoint is steering it somewhere nearer first.
func formation_slot() -> Vector3:
	if _march_active:
		return _march_final_target
	return _funnel_final_target if _funnel_active else nav_agent.target_position

## Arms (or updates) marching for this move leg — see _march_active. A no-op
## once the unit has left the move, e.g. peeled off into a fight.
func set_march_target(point: Vector3, anchor_velocity: Vector3) -> void:
	if not _funnel_can_arm():
		return
	if not _march_active:
		_march_final_target = nav_agent.target_position
		_march_active = true
		## A fresh march may re-path to its point straight away, rather than
		## wait out a timer left over from an earlier one and meanwhile ask
		## the agent about the far-off slot it's still targeting.
		_march_recheck_in = 0.0
		_march_pathing = false
	_march_point = point
	_march_velocity = anchor_velocity

## The group's anchor has arrived: walk the rest of the way to the real slot.
func end_march() -> void:
	if not _march_active:
		return
	_march_active = false
	_path_end_timer = 0.0
	nav_agent.target_position = _march_final_target

## Desired velocity while marching: keep pace with the anchor and close on this
## unit's own point, or path to that point when too far off to walk straight.
func _march_desired_velocity(max_speed: float) -> Vector3:
	var to_point := _march_point - global_position
	to_point.y = 0.0
	if to_point.length() > MARCH_CATCH_UP_DISTANCE:
		max_speed *= MARCH_CATCH_UP_SPEED
	if to_point.length() <= MARCH_DIRECT_DISTANCE:
		_march_pathing = false
		_march_recheck_in = 0.0
	else:
		## Every MARCH_REPATH_INTERVAL: walk straight back if nothing's in the
		## way (most stragglers), and only path — a full navmesh query — when
		## something is. Starting to path afresh always re-targets: the agent
		## may still hold a path to wherever the point was the last time.
		_march_recheck_in -= get_physics_process_delta_time()
		if _march_recheck_in <= 0.0:
			_march_recheck_in = MARCH_REPATH_INTERVAL
			var was_pathing := _march_pathing
			_march_pathing = not _line_walkable(_march_point)
			if _march_pathing and (not was_pathing \
					or nav_agent.target_position.distance_to(_march_point) > MARCH_REPATH_DISTANCE):
				nav_agent.target_position = _march_point
		if _march_pathing and _path_ready() and not nav_agent.is_navigation_finished():
			_path_waypoint = nav_agent.get_next_path_position()
			var next := _path_waypoint - global_position
			next.y = 0.0
			if next.length_squared() > 0.0001:
				return next.normalized() * max_speed
	return (_march_velocity + to_point * MARCH_CORRECTION_GAIN).limit_length(max_speed)

## Whether the straight line from here to `to` stays on walkable ground,
## sampled along the navmesh index (each sample hinted with the last one's
## polygon, so it's mostly one polygon test apiece). Lines longer than
## LINE_CHECK_MAX count as blocked — past that a path is worth its cost anyway.
const LINE_CHECK_MAX: float = 12.0
const LINE_CHECK_STEP: float = 0.5
func _line_walkable(to: Vector3) -> bool:
	var walkability := NavWalkability.current
	if walkability == null:
		return false
	var distance := _flat_distance(global_position, to)
	if distance > LINE_CHECK_MAX:
		return false
	var steps: int = maxi(1, ceili(distance / LINE_CHECK_STEP))
	var poly := _walk_poly
	for step in range(1, steps + 1):
		poly = walkability.polygon_at(global_position.lerp(to, float(step) / steps), poly)
		if poly < 0:
			return false
	return true

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
	_end_formation_fight()
	attack_move_order = {}
	## Skip the capacity check when re-issued at a resource this unit is
	## already assigned to — otherwise it would be blocked by its own reservation.
	if resource_node != target_resource and not resource_node.can_accept_gatherer():
		return
	_leave_build_site()
	_leave_gather_site()
	formation_facing = Vector3.ZERO
	status_command = Command.GATHER
	attack_target = null
	assault_active = false
	formation_speed = -1.0
	_clear_formation_cohesion()
	target_resource = resource_node
	dropoff_point = dropoff
	resource_node.add_gatherer(self)
	_replacement_resource_type = resource_node.resource_type if resource_node.seek_replacement_when_depleted else null
	_last_resource_position = resource_node.global_position
	_head_to_resource()

## keep_assault: true when this fight was picked *by* a standing attack-move
## order, or is self-defense during one, rather than being a fresh player order
## at a specific target. The assault then survives the fight, so
## _find_new_target_or_idle can move on to the next thing in the area once this
## target dies instead of the unit stopping there.
func command_attack(target: Node3D, keep_assault: bool = false) -> void:
	if status_activity == Activity.DEAD or not can_fight or target == null or not is_instance_valid(target):
		return
	_end_formation_fight()
	if not keep_assault:
		attack_move_order = {}
	_leave_build_site()
	_leave_gather_site()
	if not keep_assault:
		assault_active = false
	_hold_engagement = false
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
	_end_formation_fight()
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
	_end_formation_fight()
	attack_move_order = {}
	_leave_build_site()
	_leave_gather_site()
	formation_facing = Vector3.ZERO
	status_command = Command.PATROL
	attack_target = null
	assault_active = false
	formation_speed = -1.0
	_clear_formation_cohesion()
	patrol_points = points
	patrol_index = 0
	wander_origin = null
	wander_radius = 0.0
	status_activity = Activity.MOVING
	nav_agent.target_desired_distance = MOVE_ARRIVAL_DISTANCE
	move_to(patrol_points[0])

## Extends an already-active patrol loop with another waypoint (e.g. a
## shift-click while patrol-targeting). No-ops if the order changed before
## this arrived.
func command_patrol_add_waypoint(point: Vector3) -> void:
	if status_command == Command.PATROL:
		patrol_points.append(point)

## Mills about within radius of origin, engaging anything that comes near and
## drifting back to another random nearby point once the fight ends. Used by
## Objective for its guards (see Objective._ready).
func command_wander(origin: Node3D, radius: float) -> void:
	if status_activity == Activity.DEAD or not can_fight or origin == null or radius <= 0.0:
		return
	_end_formation_fight()
	attack_move_order = {}
	_leave_build_site()
	_leave_gather_site()
	formation_facing = Vector3.ZERO
	status_command = Command.PATROL
	attack_target = null
	assault_active = false
	formation_speed = -1.0
	_clear_formation_cohesion()
	patrol_points.clear()
	patrol_index = 0
	wander_origin = origin
	wander_radius = radius
	_begin_wander_leg()

## Takes on an enemy already within reach without leaving the spot — the
## holding-unit counterpart to the idle scan's command_attack.
func _engage_from_hold(target: Node3D) -> void:
	## command_attack ends a formation fight, like any order — but this is the
	## formation fighting, not a new order, so it carries on afterwards.
	var fighting := in_formation_fight
	var ordered := formation_attack_target
	var fight_id := formation_fight_id
	command_attack(target, true)
	in_formation_fight = fighting
	formation_attack_target = ordered
	formation_fight_id = fight_id
	_hold_engagement = true

## Hands an enemy met on a group attack-move to the group, which fights it as
## a block (GroupMovement.formation_contact). False for a lone unit.
func _group_contact(enemy: Node3D) -> bool:
	if attack_move_order.is_empty() or GroupMovement.current == null:
		return false
	return GroupMovement.current.formation_contact(self, enemy)

## Joins a formation attack on `target` (see in_formation_fight). Called by
## GroupMovement right after the move to this unit's slot is issued.
func begin_formation_fight(target: Node3D, place: Vector3, fight_id: int) -> void:
	in_formation_fight = true
	formation_attack_target = target
	formation_fight_id = fight_id
	formation_fight_place = place
	_returning_to_place = false

func _end_formation_fight() -> void:
	in_formation_fight = false
	formation_attack_target = null
	formation_fight_id = -1

## The block has lost its target and found nothing to go after: members hold
## their places and fight whatever comes within reach.
func hold_formation_fight() -> void:
	formation_attack_target = null

## Walks an idle member of a fighting block back to its place once it's been
## pushed out of it — by separation, or an enemy shoving through — straight
## there, since it's never far. True while it's doing so (the rest of the
## tick's steering is skipped).
func _tick_formation_place(delta: float) -> bool:
	if not in_formation_fight or status_activity != Activity.IDLE or status_command != Command.NONE:
		_returning_to_place = false
		return false
	var to_place := formation_fight_place - global_position
	to_place.y = 0.0
	var distance := to_place.length()
	if distance > FORMATION_PLACE_RETURN:
		_returning_to_place = true
	elif distance <= FORMATION_PLACE_SETTLED:
		_returning_to_place = false
	if not _returning_to_place:
		return false
	_update_separation(delta)
	## Slows over the last stretch so it settles instead of overshooting.
	var speed: float = minf(move_speed, distance * 4.0)
	_apply_velocity(to_place / distance * speed)
	return true

## The formation's ordered target, if it's alive and within this unit's reach
## from where it stands.
func _formation_target_in_reach() -> Node3D:
	if not in_formation_fight or not _is_target_alive(formation_attack_target):
		return null
	if not _formation_can_reach(formation_attack_target):
		return null
	return formation_attack_target

## How far a member of a fighting block reaches, counted from its place.
func _formation_reach(target: Node3D) -> float:
	return _reach_to(target) + (MELEE_FORMATION_STEP if _counts_as_melee() else 0.0)

func _formation_can_reach(target: Node3D) -> bool:
	return _flat_distance(formation_fight_place, target.global_position) <= _formation_reach(target)

## Whether a unit fighting from where it stands (hold_position, or its place in
## a fighting block) may go on with a fight against `target`.
func _hold_can_reach(target: Node3D) -> bool:
	return _formation_can_reach(target) if in_formation_fight else _target_in_reach()

## Nearest enemy a holding unit may take on: within attack_range, or for a
## member of a fighting block, within its reach from its place.
func _nearest_in_place_reach() -> Node3D:
	if not in_formation_fight:
		var near := _find_nearest_enemy_in_range(attack_range)
		if near and _flat_distance(global_position, near.global_position) <= attack_range:
			return near
		return null
	var step: float = MELEE_FORMATION_STEP if _counts_as_melee() else 0.0
	var enemy := _find_nearest_enemy_in_range(attack_range + step)
	return enemy if enemy and _formation_can_reach(enemy) else null

## Idle in its place in a formation — or fighting from it (see
## in_formation_fight, hold_position) — as opposed to off on an errand of its
## own. What GroupMovement's ranks-closing counts as still holding the shape.
func holds_place() -> bool:
	return (status_command == Command.NONE and attack_target == null) or _in_hold_fight()

## Only while that self-picked fight is still the unit's order — any other
## command either replaces Command.ATTACK or comes back through command_attack.
func _in_hold_fight() -> bool:
	return _hold_engagement and status_command == Command.ATTACK

func command_stop() -> void:
	if status_activity == Activity.DEAD:
		return
	_end_formation_fight()
	attack_move_order = {}
	_leave_build_site()
	_leave_gather_site()
	status_command = Command.NONE
	status_activity = Activity.IDLE
	attack_target = null
	assault_active = false
	formation_speed = -1.0
	_clear_formation_cohesion()
	patrol_points.clear()
	wander_origin = null
	wander_radius = 0.0
	nav_agent.target_position = global_position

## --- Building ---

func command_build(building: ProductionBuilding) -> void:
	if status_activity == Activity.DEAD or not can_build or building == null:
		return
	_end_formation_fight()
	attack_move_order = {}
	if not is_instance_valid(building) or not building.is_under_construction:
		return
	_leave_build_site()
	_leave_gather_site()
	formation_facing = Vector3.ZERO
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
		ally._grounded = false
		## Clears any in-flight path the same way command_stop() does, so a
		## teleported unit doesn't immediately try to walk back to where it
		## was heading from its old position.
		ally.nav_agent.target_position = ally.global_position

## --- Abilities ---

## Everything this unit can currently use, in command-card order: its own
## abilities first, then its Monarch ones once promoted. Indices into this list
## are what the HUD, hotkeys, cooldowns and the activation RPC all refer to —
## innate abilities come first so promotion never shifts their indices.
func get_abilities() -> Array[Ability]:
	if not is_monarch or monarch_abilities.is_empty():
		return abilities
	var all: Array[Ability] = abilities.duplicate()
	all.append_array(monarch_abilities)
	return all

func get_ability(index: int) -> Ability:
	var list := get_abilities()
	return list[index] if index >= 0 and index < list.size() else null

## Host-side authority.
func is_ability_ready(index: int) -> bool:
	return Time.get_ticks_msec() >= int(_ability_ready_at_ms.get(index, 0))

## Owner-side estimate, for the HUD only.
func is_ability_ready_locally(index: int) -> bool:
	return Time.get_ticks_msec() >= int(local_ability_ready_at_ms.get(index, 0))

func start_local_cooldown(index: int, cooldown: float) -> void:
	_local_ability_cooldown_ms[index] = int(cooldown * 1000.0)
	local_ability_ready_at_ms[index] = Time.get_ticks_msec() + _local_ability_cooldown_ms[index]

## 1.0 the moment the ability is cast, falling to 0.0 as it comes back.
func local_cooldown_remaining_fraction(index: int) -> float:
	var duration: int = _local_ability_cooldown_ms.get(index, 0)
	if duration <= 0:
		return 0.0
	var left: int = int(local_ability_ready_at_ms.get(index, 0)) - Time.get_ticks_msec()
	return clampf(float(left) / float(duration), 0.0, 1.0)

## Host-only, called from main.gd's validated activation RPC. Walks until
## target_pos is within the ability's activation_range, then casts (see
## _tick_cast_approach / _perform_cast).
func command_cast_ability(ability_index: int, target_pos: Vector3) -> void:
	var ability := get_ability(ability_index)
	if status_activity == Activity.DEAD or ability == null or not ability.is_activated():
		return
	_end_formation_fight()
	attack_move_order = {}
	_leave_build_site()
	_leave_gather_site()
	status_command = Command.CAST
	status_activity = Activity.TO_CAST
	attack_target = null
	assault_active = false
	formation_speed = -1.0
	_clear_formation_cohesion()
	_cast_ability_index = ability_index
	_cast_target = target_pos
	_cast_approach_time = 0.0
	if _flat_distance(global_position, target_pos) <= ability.activation_range:
		_perform_cast()
		return
	## Aim a little short of the range edge so arriving always lands inside it.
	nav_agent.target_desired_distance = maxf(ability.activation_range * 0.9, MOVE_ARRIVAL_DISTANCE)
	move_to(target_pos)

func _tick_cast_approach(delta: float) -> void:
	var ability := get_ability(_cast_ability_index)
	if ability == null:
		_end_cast_command()
		return
	if _flat_distance(global_position, _cast_target) <= ability.activation_range:
		_perform_cast()
		return
	_cast_approach_time += delta
	## Navigation ended short of range: the target point can't be reached
	## (a cliff, the far side of a wall), so give up rather than stand forever.
	if _nav_finished() and _cast_approach_time > CAST_GIVE_UP_GRACE:
		_end_cast_command()

func _perform_cast() -> void:
	var index := _cast_ability_index
	var ability := get_ability(index)
	var target := _cast_target
	nav_agent.target_position = global_position
	## Rechecked here rather than trusted from request time — the walk into
	## range can take a while, and resources can be spent meanwhile.
	if ability == null or not is_ability_ready(index) or not ResourceStockpile.can_afford(owner_peer_id, ability.costs):
		_end_cast_command()
		return
	ResourceStockpile.spend(owner_peer_id, ability.costs)
	_ability_ready_at_ms[index] = Time.get_ticks_msec() + int(ability_cooldown(ability) * 1000.0)

	var to_target := target - global_position
	to_target.y = 0.0
	if to_target.length_squared() > 0.0001:
		rotation.y = atan2(to_target.x, to_target.z)
	var cast_length := 0.0
	if sprite.sprite_frames:
		cast_length = _play_cast_animation()
	ability_cast.emit(index, target)

	## Teleport stays instant — its windup is meaningless (the caster is the
	## thing that moves) and it has no projectile or impact to line up.
	if ability.kind != Ability.Kind.ACTIVATED_AREA:
		execute_teleport_ability(ability, target)
		_end_cast_command()
		return
	_pending_casts.append({"index": index, "ability": ability, "target": target, "time_remaining": ability.cast_windup})
	status_activity = Activity.CASTING
	_casting_time_remaining = maxf(cast_length, ability.cast_windup)
	velocity.x = 0.0
	velocity.z = 0.0

## Plays the special-attack clip if this unit has one, else the ordinary
## swing. Returns how long it runs, which is how long CASTING holds the unit.
func _play_cast_animation() -> float:
	if not sprite.sprite_frames.has_animation("cast"):
		_play_attack_swing()
		return attack_frame_count / 10.0
	sprite.play("cast")
	animation_changed.emit("cast")
	return cast_frame_count / maxf(cast_fps, 0.01)

func _tick_casting(delta: float) -> void:
	_casting_time_remaining -= delta
	if _casting_time_remaining <= 0.0:
		_end_cast_command()

func _end_cast_command() -> void:
	_cast_ability_index = -1
	status_command = Command.NONE
	status_activity = Activity.IDLE
	order_completed.emit()

## Goes off whether or not the caster is still in CASTING (see _pending_casts),
## but not once it's dead.
func _tick_pending_casts(delta: float) -> void:
	for i in range(_pending_casts.size() - 1, -1, -1):
		var cast: Dictionary = _pending_casts[i]
		cast["time_remaining"] -= delta
		if cast["time_remaining"] > 0.0:
			continue
		_pending_casts.remove_at(i)
		_launch_ability(cast["index"], cast["ability"], cast["target"])

func _launch_ability(index: int, ability: Ability, target: Vector3) -> void:
	var from := get_ability_launch_position(ability)
	var travel := ability_travel_time(ability, from, target)
	ability_launched.emit(index, from, target)
	if travel <= 0.0:
		_execute_area_ability(ability, target)
		return
	_pending_ability_hits.append({"ability": ability, "target": target, "time_remaining": travel})

## Where an ability's cast effect and projectile start: launch_offset out
## along this unit's current facing. Public so every peer derives the same
## point from replicated position/rotation.
func get_ability_launch_position(ability: Ability) -> Vector3:
	var forward := Vector3(sin(rotation.y), 0.0, cos(rotation.y))
	return global_position + forward * ability.launch_offset.x + Vector3.UP * ability.launch_offset.y

## Shared by the host's damage timer and every peer's visual, so the impact
## effect lands on the same beat as the damage.
static func ability_travel_time(ability: Ability, from: Vector3, target: Vector3) -> float:
	if ability.projectile_style == Ability.ProjectileStyle.NONE:
		return 0.0
	var distance := Vector2(from.x, from.z).distance_to(Vector2(target.x, target.z))
	return distance / maxf(ability.projectile_speed, 0.01)

func _tick_pending_ability_hits(delta: float) -> void:
	for i in range(_pending_ability_hits.size() - 1, -1, -1):
		var hit: Dictionary = _pending_ability_hits[i]
		hit["time_remaining"] -= delta
		if hit["time_remaining"] > 0.0:
			continue
		_pending_ability_hits.remove_at(i)
		_execute_area_ability(hit["ability"], hit["target"])

## Hits every living enemy unit inside the area — buildings and allies are
## never affected. Targets are gathered before any damage is applied, since a
## kill frees nodes out of the "units" group mid-iteration.
func _execute_area_ability(ability: Ability, target: Vector3) -> void:
	var victims: Array[Unit] = []
	for node in get_tree().get_nodes_in_group("units"):
		var other := node as Unit
		if other == null or other == self or not Teams.is_enemy(owner_peer_id, other.owner_peer_id) or not _is_target_alive(other):
			continue
		if _flat_distance(target, other.global_position) <= ability.area_radius:
			victims.append(other)
	for victim in victims:
		if is_instance_valid(victim):
			victim.apply_ability_hit(ability, self)
	if ability.linger_duration > 0.0:
		AbilityZone.spawn(get_tree().current_scene, ability, target, owner_peer_id, self)

## How long a zone's slow and burning visual outlast the tick that applied
## them. A little over one tick (AbilityZone.TICK_INTERVAL), so they hold
## steady while a unit stands in the zone and wear off shortly after it walks out.
const ZONE_EFFECT_SECONDS: float = 1.25

## Host-only, once per AbilityZone.TICK_INTERVAL while this unit stands in a
## lingering zone. Deliberately not apply_ability_hit: re-running that every
## tick would re-stack the DoT and chain the stun forever. The zone's own
## damage stands in for the DoT, and only the slow is refreshed.
func apply_zone_tick(ability: Ability, source) -> void:
	if not is_multiplayer_authority() or status_activity == Activity.DEAD:
		return
	if ability.linger_damage_per_second > 0:
		take_damage(_warded(ability.linger_damage_per_second), source if is_instance_valid(source) else null)
	if status_activity == Activity.DEAD:
		return
	var slow_seconds := 0.0
	if ability.slow_fraction > 0.0:
		slow_seconds = ZONE_EFFECT_SECONDS
		_slow_fraction = maxf(_slow_fraction if _slow_remaining > 0.0 else 0.0, ability.slow_fraction)
		_slow_remaining = maxf(_slow_remaining, slow_seconds)
	var burn_seconds: float = ZONE_EFFECT_SECONDS if ability.linger_damage_per_second > 0 else 0.0
	if burn_seconds > 0.0 or slow_seconds > 0.0:
		status_applied.emit(burn_seconds, slow_seconds, 0.0, ability.effect_color)

## Host-only. The upfront hit, then whatever lingering effects the ability
## carries. `source` is who to credit for the damage — untyped for the same
## freed-object reason as _is_target_alive, since a DoT can outlive its caster.
func apply_ability_hit(ability: Ability, source) -> void:
	if not is_multiplayer_authority() or status_activity == Activity.DEAD:
		return
	if ability.area_damage > 0:
		take_damage(_warded(ability.area_damage), source if is_instance_valid(source) else null)
	if status_activity == Activity.DEAD:
		return
	if ability.dot_damage_per_second > 0 and ability.dot_duration > 0.0:
		_dots.append({
			"dps": ability.dot_damage_per_second,
			"ticks_left": maxi(roundi(ability.dot_duration), 1),
			"tick_timer": 1.0,
			"source": source,
		})
	if ability.slow_fraction > 0.0 and ability.slow_duration > 0.0:
		_slow_fraction = maxf(_slow_fraction if _slow_remaining > 0.0 else 0.0, ability.slow_fraction)
		_slow_remaining = maxf(_slow_remaining, ability.slow_duration)
	if ability.stun_duration > 0.0:
		_stun_remaining = maxf(_stun_remaining, ability.stun_duration)
	var dot_seconds: float = ability.dot_duration if ability.dot_damage_per_second > 0 else 0.0
	var slow_seconds: float = ability.slow_duration if ability.slow_fraction > 0.0 else 0.0
	if dot_seconds > 0.0 or slow_seconds > 0.0 or ability.stun_duration > 0.0:
		status_applied.emit(dot_seconds, slow_seconds, ability.stun_duration, ability.effect_color)

func _tick_status_effects(delta: float) -> void:
	_stun_remaining = maxf(_stun_remaining - delta, 0.0)
	_slow_remaining = maxf(_slow_remaining - delta, 0.0)
	for i in range(_dots.size() - 1, -1, -1):
		var dot: Dictionary = _dots[i]
		dot["tick_timer"] -= delta
		if dot["tick_timer"] > 0.0:
			continue
		dot["tick_timer"] += 1.0
		dot["ticks_left"] -= 1
		if dot["ticks_left"] <= 0:
			_dots.remove_at(i)
		var source = dot["source"]
		take_damage(_warded(dot["dps"]), source if is_instance_valid(source) else null)
		if status_activity == Activity.DEAD:
			_dots.clear()
			return

## Host-only: when this unit last took damage — Research's out-of-combat
## regeneration waits on it.
var last_damaged_msec: int = -100000
## Host-only Ruler power effects currently on this unit.
var buffs := TimedBuffs.new()
## Host-only: spawned by a power (Muster) rather than trained — reserves no
## population and is worth nothing to its killer.
var summoned: bool = false
## Host-only: the player whose power last hit this unit, and when. A power
## has no attacking unit, so this is who a power kill is credited to.
var power_credit_peer: int = 0
var power_credit_time: float = -1000.0

## Host only: a summon's time is up.
func expire() -> void:
	if is_multiplayer_authority() and status_activity != Activity.DEAD:
		_die(null)

func _buff_speed_multiplier() -> float:
	return maxf(1.0 + buffs.amount(ResearchNode.Buff.MOVE_SPEED), 0.1)

## Host only. Never past max health.
func heal(amount: int) -> void:
	if not is_multiplayer_authority() or status_activity == Activity.DEAD:
		return
	status_current_health = mini(status_current_health + amount, max_health)

## Only the Shrine monsters carry abilities of their own (a Monarch's live in
## monarch_abilities instead).
func is_monster() -> bool:
	return not abilities.is_empty()

## A monster's cooldown shortened by its owner's research (Spirit Link).
func ability_cooldown(ability: Ability) -> float:
	if not is_monster():
		return ability.cooldown
	return ability.cooldown * (1.0 - Research.bonus(owner_peer_id, ResearchNode.Stat.MONSTER_COOLDOWN_REDUCTION))

## Ability damage taken, after this unit's owner's Warding.
func _warded(amount: int) -> int:
	var reduction := Research.bonus(owner_peer_id, ResearchNode.Stat.ABILITY_DAMAGE_REDUCTION)
	return maxi(roundi(amount * (1.0 - reduction)), 1) if reduction > 0.0 else amount

func _slow_multiplier() -> float:
	return 1.0 - _slow_fraction if _slow_remaining > 0.0 else 1.0

func take_damage(amount: int, attacker: Node3D = null) -> void:
	if not is_multiplayer_authority() or status_activity == Activity.DEAD:
		return
	## Sanctuary: nothing gets through while it lasts.
	if buffs.amount(ResearchNode.Buff.INVULNERABLE) > 0.0:
		return
	last_damaged_msec = Time.get_ticks_msec()
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
			+ UnitUpgrades.get_armor_bonus(owner_peer_id, unit_category) 			+ roundi(buffs.amount(ResearchNode.Buff.ARMOR))
	amount = maxi(amount - armor, 1)
	## Fatality is decided here, before the health subtraction below, purely so
	## it can ride along with the signal: main.gd relays this to every peer and
	## uses it to hitstop the attacker on a killing blow, and by the time the
	## relay lands there is nothing left to ask.
	var fatal: bool = status_current_health - amount <= 0
	var attacker_path: NodePath = NodePath()
	if attacker != null and is_instance_valid(attacker) and attacker.is_inside_tree():
		attacker_path = attacker.get_path()
	damaged.emit(amount, attacker_path, fatal)
	status_current_health = maxi(status_current_health - amount, 0)
	if status_current_health <= 0:
		_die(attacker)
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
		## Command.CAST is the same kind of deliberate order: a monster walking
		## in to cast shouldn't be talked out of it by the first thing to hit it.
		elif (hold_position or in_formation_fight) and status_command == Command.NONE:
			if _flat_distance(global_position, attacker.global_position) <= _reach_to(attacker):
				_engage_from_hold(attacker)
		elif status_command != Command.ATTACK and status_command != Command.MOVE and status_command != Command.CAST:
			## keep_assault: being shot at while marching on an assault target
			## makes this unit fight back, but must not quietly cancel the
			## standing order to take the place it was sent to.
			if not _group_contact(attacker):
				command_attack(attacker, true)
		var now := Time.get_ticks_msec()
		if now >= _next_alert_ms:
			_next_alert_ms = now + CombatUtils.ALERT_INTERVAL_MS
			CombatUtils.alert_nearby_allies(get_tree(), global_position, owner_peer_id, attacker)

## Timed wrapper for PerfStats ("cmd perf"); the real tick is _physics_tick.
func _physics_process(delta: float) -> void:
	if not PerfStats.enabled:
		_physics_tick(delta)
		return
	var start := Time.get_ticks_usec()
	_physics_tick(delta)
	PerfStats.add_unit_time(Time.get_ticks_usec() - start)

func _physics_tick(delta: float) -> void:
	## Only the host simulates movement/gathering/combat; other peers just display
	## the position/animation replicated by this unit's MultiplayerSynchronizer.
	if not is_multiplayer_authority():
		return
	_path_waypoint = Vector3.INF

	## Runs even if this unit just died — an arrow already in the air should
	## still land rather than vanish because its shooter is gone.
	_tick_pending_projectiles(delta)
	_tick_pending_ability_hits(delta)

	if status_activity == Activity.DEAD:
		velocity = Vector3.ZERO
		_slide()
		return

	## Following the terrain directly (see _slide) keeps a unit on the ground
	## by construction; only the move_and_slide() fallback needs gravity.
	if GroundHeight.terrain(get_tree()) != null or is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta

	_tick_status_effects(delta)
	if status_activity == Activity.DEAD:
		return
	## Before the stun check, deliberately: a monster stunned mid-windup has
	## already paid for and committed to the ability, and freezing the windup
	## would let a stun silently swallow it if the order changed meanwhile.
	_tick_pending_casts(delta)

	## Stunned: frozen in place, every timer (attack, gather, cast approach)
	## paused, but the current order survives and resumes once it wears off.
	if _stun_remaining > 0.0:
		velocity.x = 0.0
		velocity.z = 0.0
		## Those activities manage their own animation and slide; everything
		## else goes through the normal movement step, standing still.
		if status_activity == Activity.GATHERING or status_activity == Activity.ATTACKING or status_activity == Activity.BUILDING or status_activity == Activity.CASTING:
			_slide()
		else:
			_apply_velocity(Vector3.ZERO)
		return

	if status_activity == Activity.CASTING:
		velocity.x = 0.0
		velocity.z = 0.0
		_tick_casting(delta)
		_slide()
		return

	if status_activity == Activity.GATHERING:
		velocity.x = 0.0
		velocity.z = 0.0
		_tick_gathering(delta)
		if sprite.sprite_frames:
			_set_animation("gather")
		_slide()
		return

	if status_activity == Activity.ATTACKING:
		var push := _update_separation(delta)
		velocity.x = push.x
		velocity.z = push.z
		_face_attack_target(delta)
		_tick_attacking(delta)
		_slide()
		return

	if status_activity == Activity.BUILDING:
		velocity.x = 0.0
		velocity.z = 0.0
		_tick_building()
		if sprite.sprite_frames:
			_set_animation("idle")
		_slide()
		return

	if status_activity == Activity.TO_RESOURCE and _nav_finished():
		_start_gathering()
	elif status_activity == Activity.TO_DROPOFF and _nav_finished():
		_deposit_and_continue()
	elif status_activity == Activity.TO_TARGET:
		## Straight-line reach counts as arrived too: in a scrum the path can't
		## finish (bodies in the way keep the agent short of its nav target)
		## even though the target is already within swing. A rank behind the
		## front one waits instead (see _melee_reach_blocked).
		if not _update_reach_blocked(delta) and (_nav_finished() or _target_in_reach()):
			_start_attacking()
		else:
			_tick_chase(delta)
			_tick_approach_threats(delta)
			_tick_melee_overflow(delta)
	elif status_activity == Activity.TO_BUILD_SITE:
		if _nav_finished():
			_start_building()
		else:
			_tick_build_approach(delta)
	elif status_activity == Activity.TO_CAST:
		_tick_cast_approach(delta)
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
				## A group attack-move stops and fights it as a block; a lone
				## unit hands off to the normal ATTACK flow for this one fight,
				## but keeps the assault so the destination isn't lost.
				if target and not _group_contact(target):
					command_attack(target, true)
			else:
				## Patrol stays Command.PATROL through the fight so
				## _find_new_target_or_idle() resumes the loop after.
				var enemy := _find_nearest_enemy_in_range(aggro_range)
				if enemy:
					attack_target = enemy
					_head_to_target()
	elif status_activity == Activity.IDLE and status_command == Command.PATROL and wander_radius > 0.0:
		_tick_wander_pause(delta)
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
			if hold_position or in_formation_fight:
				var in_reach: Node3D = _formation_target_in_reach()
				if in_reach == null:
					in_reach = _nearest_in_place_reach()
				if in_reach:
					_engage_from_hold(in_reach)
			else:
				var enemy: Node3D = _find_assault_target() if assault_active \
						else _find_nearest_enemy_in_range(aggro_range)
				if enemy and not (assault_active and _group_contact(enemy)):
					command_attack(enemy, true)

	if _tick_formation_place(delta):
		return

	## Standing idle with no order and nothing shoving it — most of an army,
	## most of the time — there's no steering, path or arrival work to do. It
	## still turns to hold its formation's front, and still gets pushed apart.
	if status_activity == Activity.IDLE and status_command == Command.NONE:
		_update_separation(delta)
		if _separation_velocity == Vector3.ZERO:
			velocity.x = 0.0
			velocity.z = 0.0
			if formation_facing != Vector3.ZERO:
				var front_angle: float = atan2(formation_facing.x, formation_facing.z)
				if absf(angle_difference(rotation.y, front_angle)) > 0.01:
					rotation.y = lerp_angle(rotation.y, front_angle, rotation_speed * delta)
			if sprite.sprite_frames:
				_set_animation("idle")
			_slide()
			return

	## Before the steering read below, so a unit released from its funnel
	## waypoint this frame immediately starts steering at its real slot instead
	## of spending one more frame closing on a waypoint it's already through.
	_update_funnel(delta)

	## A marching unit steers off its anchor (see _march_desired_velocity), so
	## it never asks for the path to its far-off slot — that query is a full
	## cross-map search per unit, for a result the march would throw away.
	var direction := Vector3.ZERO
	if not _march_active:
		if not _path_ready():
			direction = _straight_direction()
		elif not nav_agent.is_navigation_finished():
			var next_pos: Vector3 = nav_agent.get_next_path_position()
			_path_waypoint = next_pos
			direction = next_pos - global_position
			direction.y = 0.0
			if direction.length_squared() > 0.0001:
				direction = direction.normalized()

	## Units always travel at their own full speed, even in a mixed group —
	## no slowest-member cap (formation_speed) and no cohesion throttle.
	var effective_speed: float = move_speed
	var buff_speed := _buff_speed_multiplier()
	effective_speed *= _slow_multiplier() * buff_speed
	var desired_velocity := Vector3(direction.x * effective_speed, 0.0, direction.z * effective_speed)
	if _march_active:
		desired_velocity = _march_desired_velocity(effective_speed)
	## Held behind the front rank: stand and wait for a gap rather than walk
	## into the backs of the units already fighting.
	if status_activity == Activity.TO_TARGET and _reach_blocked:
		desired_velocity = Vector3.ZERO
	_update_separation(delta)
	_apply_velocity(desired_velocity)

## Push away from any living unit overlapping this one (see SEPARATION_DISTANCE).
## Units sitting on exactly the same point part along a per-unit fixed angle so
## a stacked pair splits instead of both computing a zero-length direction.
func _update_separation(delta: float) -> Vector3:
	_separation_timer -= delta
	if _separation_timer > 0.0:
		return _separation_velocity
	_separation_timer = SEPARATION_INTERVAL
	var push := Vector3.ZERO
	for other in UnitGrid.units_near(get_tree(), global_position, SEPARATION_DISTANCE):
		if other == self:
			continue
		## Enemies shove each other like anyone else, except that an enemy
		## attacking this unit doesn't push it: every attacker crowding a target
		## would otherwise sum into one big shove and bulldoze a mobbed unit
		## across the field. The attacker still yields to its target, and a
		## pair fighting each other push both ways.
		if Teams.is_enemy(owner_peer_id, other.owner_peer_id) and other.attack_target == self and other != attack_target:
			continue
		var away := global_position - other.global_position
		away.y = 0.0
		var distance := away.length()
		if distance < 0.01:
			var angle := float(get_instance_id() % 6283) * 0.001
			away = Vector3(cos(angle), 0.0, sin(angle))
		else:
			away /= distance
		push += away * (1.0 - distance / SEPARATION_DISTANCE) * SEPARATION_SPEED
	_separation_velocity = push.limit_length(SEPARATION_MAX_SPEED)
	return _separation_velocity

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
		_cohesion_progress = self_progress

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
		## A big group is averaged over an evenly spaced sample rather than every
		## member (offset per unit, so different units sample different members)
		## — the whole-group loop is O(n^2) across the group, which a large army
		## selection turns into most of the frame.
		var group_size: int = formation_group.size()
		var stride: int = maxi(1, ceili(float(group_size) / COHESION_SAMPLE_SIZE))
		for i in range(get_instance_id() % stride, group_size, stride):
			var other: Unit = formation_group[i]
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
			## Only compare against groupmates walking the SAME leg. Progress is
			## a fraction of whatever leg a unit is currently on, and a funnel
			## splits the group across two of them (see set_funnel_waypoint): a
			## unit still heading for the gap is 90% through its leg while one
			## just released onto its final slot is at 0% of a brand new one.
			## Mixing the two collapses the average for everyone still queueing
			## at the gap, which reads as a huge lead and throttles the back of
			## the column to COHESION_MIN_SPEED_SCALE at exactly the moment it
			## should be streaming through. Each side of the funnel therefore
			## paces itself against its own half.
			if other._funnel_active != _funnel_active:
				continue
			## Each member's own progress as of its last recheck, rather than a
			## fresh _formation_progress() (a full remaining-path walk) per
			## groupmate per recheck.
			total_progress += other._cohesion_progress
			count += 1

		_cohesion_target_speed_scale = 1.0
		if count > 0:
			var avg_progress: float = total_progress / count
			var ahead: float = self_progress - avg_progress
			if ahead > COHESION_AHEAD_DEADBAND:
				var t: float = clampf((ahead - COHESION_AHEAD_DEADBAND) / (COHESION_MAX_THROTTLE_RANGE - COHESION_AHEAD_DEADBAND), 0.0, 1.0)
				_cohesion_target_speed_scale = lerpf(1.0, COHESION_MIN_SPEED_SCALE, t)

	_cohesion_speed_scale = move_toward(_cohesion_speed_scale, _cohesion_target_speed_scale, COHESION_SCALE_LERP_RATE * delta)

## 0 (just started) to 1 (arrived) fraction of this unit's straight-line
## distance-to-slot at the start of this leg (see _set_formation_cohesion)
## that its actual remaining nav path distance now represents — used instead
## of raw move_speed comparisons so a unit taking a longer/curved path around
## an obstacle reads as "behind" even if its speed stat matches everyone else's.
func _formation_progress() -> float:
	if formation_initial_distance <= 0.0:
		return 1.0
	return clampf(1.0 - nav_agent.distance_to_target() / formation_initial_distance, 0.0, 1.0)

## The movement step for every activity that walks: applies `desired` plus the
## separation push, turns and animates the unit, slides it, and notices a
## finished move/patrol leg. Activities that manage their own animation and
## slide (and one that switched into them earlier this tick, e.g. a chase that
## just started attacking) are left alone.
func _apply_velocity(desired: Vector3) -> void:
	if status_activity == Activity.GATHERING or status_activity == Activity.ATTACKING or status_activity == Activity.BUILDING or status_activity == Activity.DEAD or status_activity == Activity.CASTING:
		return

	velocity.x = desired.x + _separation_velocity.x
	velocity.z = desired.z + _separation_velocity.z

	var flat_speed := Vector2(velocity.x, velocity.z).length()
	var is_moving := flat_speed > MOVING_SPEED_THRESHOLD
	if is_moving:
		var move_dir := Vector3(velocity.x, 0.0, velocity.z) / flat_speed
		var target_angle: float = atan2(move_dir.x, move_dir.z)
		rotation.y = lerp_angle(rotation.y, target_angle, rotation_speed * get_physics_process_delta_time())
	elif status_activity == Activity.IDLE and formation_facing != Vector3.ZERO:
		var front_angle: float = atan2(formation_facing.x, formation_facing.z)
		rotation.y = lerp_angle(rotation.y, front_angle, rotation_speed * get_physics_process_delta_time())

	if sprite.sprite_frames:
		_set_animation("walk" if is_moving else "idle")

	_slide()

	## Gated on Activity.MOVING specifically (not just nav-finished) because
	## PATROL stays Command.PATROL while chasing/fighting (Activity.TO_TARGET/
	## ATTACKING) too — this runs every physics frame regardless of
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
	##
	## A path can also end short of its target for good — a destination the
	## navmesh can't reach, where the path stops at the nearest point it can.
	## Without a way out the unit would stand there on its move order forever
	## (never idle, so never re-formed, never scanning), so a path that has
	## been over for PATH_END_GIVE_UP counts as arrived wherever it left the unit.
	## A marching unit's nav target is only its marching point, not the order's
	## destination — reaching it isn't arriving (see end_march).
	var path_over := status_activity == Activity.MOVING and not _march_active and _nav_finished()
	var at_target := path_over and global_position.distance_to(nav_agent.target_position) <= nav_agent.target_desired_distance + 0.5
	## Standing on the spot counts whatever the agent says: slots carry the
	## clicked point's height, so on uneven ground a unit exactly on its slot
	## can be further than target_desired_distance from it in 3D and the agent
	## never reports the path finished.
	if status_activity == Activity.MOVING and not _march_active \
			and _flat_distance(global_position, nav_agent.target_position) <= nav_agent.target_desired_distance:
		at_target = true
	## Wedged against whatever its slot is in or against (see BLOCKED_GIVE_UP_TIME).
	var wedged := status_activity == Activity.MOVING and not _march_active and _blocked_time >= BLOCKED_GIVE_UP_TIME \
			and _flat_distance(global_position, nav_agent.target_position) <= BLOCKED_ARRIVAL_RADIUS
	_path_end_timer = _path_end_timer + get_physics_process_delta_time() if path_over and not at_target else 0.0
	var gave_up := wedged or _path_end_timer >= PATH_END_GIVE_UP
	if at_target or gave_up:
		_path_end_timer = 0.0
		if status_command == Command.MOVE or status_command == Command.ATTACK_MOVE:
			## Where it stopped is its place in the formation now — without this
			## GroupMovement's ranks-closing reads a unit that settled short of
			## an unreachable slot, or was shoved off its slot by a crowding
			## neighbour, as lost and re-orders the whole group, over and over.
			arrived_group = formation_group
			if in_formation_fight:
				formation_fight_place = global_position
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
## Timed wrapper for PerfStats ("cmd perf"); the real per-frame visuals are
## _process_visuals.
func _process(delta: float) -> void:
	if not PerfStats.enabled:
		_process_visuals(delta)
		return
	var start := Time.get_ticks_usec()
	_process_visuals(delta)
	PerfStats.add_section(&"unit visuals", Time.get_ticks_usec() - start)

func _process_visuals(delta: float) -> void:
	_update_health_bar_visual()
	_update_status_visuals(delta)
	## Driven off the sprite's own already-cross-peer-correct animation state
	## (see _set_animation/animation_changed) rather than status_activity or
	## raw velocity directly — those are only reliable on the authoritative
	## peer, while every peer already shows the right walk/idle animation.
	var in_view := visible and _in_camera_view()
	## Only where someone can see it: every unit carries its own particle
	## system, each a GPU dispatch and a draw every frame it runs, and a whole
	## army starts walking on the same click.
	if walk_dust:
		var walking: bool = sprite.animation == &"walk" and in_view 				and (not is_instance_valid(_view_camera) 				or _view_camera.global_position.distance_squared_to(global_position) <= WALK_DUST_MAX_DISTANCE * WALK_DUST_MAX_DISTANCE)
		if walk_dust.emitting != walking:
			walk_dust.emitting = walking

	## Hidden by fog or off screen: nobody can see which way it's flipped, and
	## it's worked out again the frame it shows.
	if not in_view:
		return
	var cam_right := _camera_right_vector()
	if cam_right == Vector3.ZERO:
		return
	var forward := Vector3(sin(rotation.y), 0.0, cos(rotation.y))
	var screen_dot: float = forward.dot(cam_right)
	if absf(screen_dot) > FLIP_DOT_THRESHOLD:
		sprite.flip_h = screen_dot < 0.0
	if crew_sprite:
		_update_crew_sprite(cam_right)

func _build_crew_sprite() -> void:
	crew_sprite = AnimatedSprite3D.new()
	crew_sprite.name = "CrewSprite"
	crew_sprite.pixel_size = sprite.pixel_size
	crew_sprite.billboard = sprite.billboard
	crew_sprite.shaded = sprite.shaded
	crew_sprite.alpha_cut = sprite.alpha_cut
	crew_sprite.texture_filter = sprite.texture_filter
	crew_sprite.sprite_frames = SpriteSheetFrames.build(crew_sprite_sheet, sprite_cell_size, {
		"idle": {"row": crew_idle_row, "frames": crew_idle_frame_count, "fps": 5.0, "loop": true},
		"walk": {"row": crew_walk_row, "frames": crew_walk_frame_count, "fps": 8.0, "loop": true},
		"death": {"row": crew_death_row, "frames": crew_death_frame_count, "fps": 8.0, "loop": false},
	})
	sprite.add_child(crew_sprite)
	crew_sprite.play("idle")

## Keeps the crew behind the machine from this peer's own camera (so, like the
## flip itself, worked out locally every frame), mirroring its facing, hit
## flash and walk/idle state.
func _update_crew_sprite(cam_right: Vector3) -> void:
	crew_sprite.flip_h = sprite.flip_h
	crew_sprite.modulate = sprite.modulate
	if not _death_playing:
		var anim: StringName = &"walk" if sprite.animation == &"walk" else &"idle"
		if crew_sprite.animation != anim:
			crew_sprite.play(anim)
	var behind: Vector3 = cam_right * (crew_offset if sprite.flip_h else -crew_offset)
	var camera := get_viewport().get_camera_3d()
	if camera:
		behind -= camera.global_transform.basis.z * CREW_DEPTH_OFFSET
	## Y rotation only, so the basis inverse is exact (same as play_hit_reaction).
	crew_sprite.position = global_transform.basis.inverse() * behind

## Every unit needs the camera's right vector each frame for its sprite flip,
## and it's the same answer for all of them — so the first unit to ask in a
## frame looks it up and the rest reuse it.
static var _camera_right_frame: int = -1
static var _camera_right: Vector3 = Vector3.ZERO

## Walk dust only kicks up this close to the camera (see _process_visuals).
const WALK_DUST_MAX_DISTANCE: float = 45.0
## Slightly past the frustum, so a sprite half over the screen edge still counts.
const VIEW_MARGIN: float = 2.0
static var _view_camera_frame: int = -1
static var _view_camera: Camera3D = null

## Whether this unit is on screen for the local camera — looked up once per
## frame and shared, like _camera_right_vector. True with no camera at all.
func _in_camera_view() -> bool:
	var frame := Engine.get_process_frames()
	if frame != _view_camera_frame:
		_view_camera_frame = frame
		_view_camera = get_viewport().get_camera_3d()
	if not is_instance_valid(_view_camera):
		return true
	if _view_camera.is_position_in_frustum(global_position):
		return true
	return _view_camera.is_position_in_frustum(global_position + Vector3.UP * VIEW_MARGIN)

func _camera_right_vector() -> Vector3:
	var frame := Engine.get_process_frames()
	if frame != _camera_right_frame:
		_camera_right_frame = frame
		var camera := get_viewport().get_camera_3d()
		_camera_right = camera.global_transform.basis.x if camera else Vector3.ZERO
	return _camera_right

## Last fill fraction written to the bar, so the Fill's transform (which
## re-propagates on every write) is only touched when health actually changes.
var _shown_health_fraction: float = -1.0

## Reads from status_current_health, which is now a real synced property, so
## this displays correctly on every peer, not just the authoritative one.
func _update_health_bar_visual() -> void:
	if not health_bar:
		return
	var fraction: float = clampf(float(status_current_health) / float(maxi(max_health, 1)), 0.0, 1.0)
	health_bar.visible = fraction < 0.999 and status_activity != Activity.DEAD
	if fraction == _shown_health_fraction:
		return
	_shown_health_fraction = fraction
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
	play_attack_lunge()

## "attack" is non-looping; once a swing finishes, settle back to idle until
## the next hit fires. This runs on every peer (not just the authority) since
## it just reacts to that peer's own local sprite finishing its own playback.
func _on_attack_animation_finished() -> void:
	if sprite.animation == "attack" or sprite.animation == "cast":
		_set_animation("idle")

## --- Gathering ---

func _head_to_resource() -> void:
	if not _has_live_resource() and not _retarget_resource():
		_end_gather_command()
		return
	status_activity = Activity.TO_RESOURCE
	nav_agent.target_desired_distance = target_resource.gather_range
	move_to(target_resource.global_position)

func _start_gathering() -> void:
	## Felled while this unit was still walking to it.
	if not _has_live_resource():
		_head_to_resource()
		return
	status_activity = Activity.GATHERING
	gather_timer = 0.0
	status_carried_type = target_resource.resource_type

func _tick_gathering(delta: float) -> void:
	if not _has_live_resource():
		## Not full yet: carry on at the next tree rather than walking a
		## part-load home.
		if status_carried_amount < carry_capacity and _retarget_resource():
			_head_to_resource()
		else:
			_head_to_dropoff()
		return

	gather_timer += delta
	var interval: float = target_resource.resource_type.gather_interval / maxf(gather_level, 1.0) \
			/ (1.0 + Research.bonus(owner_peer_id, ResearchNode.Stat.GATHER_SPEED) + buffs.amount(ResearchNode.Buff.GATHER_SPEED))
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

	## _head_to_resource finds a replacement if this one ran out meanwhile,
	## and ends the command itself if there's none.
	if status_command == Command.GATHER:
		_head_to_resource()
	else:
		_end_gather_command()

func _has_live_resource() -> bool:
	return is_instance_valid(target_resource) and not target_resource.is_queued_for_deletion() \
			and target_resource.amount_remaining > 0

## Swaps a spent target_resource for the nearest usable node of the same kind.
## Measured from where the spent one stood rather than from this unit, so a
## woodcutter works its way through the same forest instead of drifting toward
## whichever tree is nearest its drop-off trip. Returns false (target left
## untouched) when the node type doesn't seek, or nothing is in range.
func _retarget_resource() -> bool:
	if _replacement_resource_type == null:
		return false
	var best: Gatherable = null
	var best_distance: float = RESOURCE_RETARGET_RADIUS
	for node in get_tree().get_nodes_in_group(&"gatherables"):
		var candidate := node as Gatherable
		if candidate == null or candidate.is_queued_for_deletion() or candidate.amount_remaining <= 0:
			continue
		if not candidate.seek_replacement_when_depleted or candidate.resource_type != _replacement_resource_type:
			continue
		if candidate.owner_peer_id != 0 and candidate.owner_peer_id != owner_peer_id:
			continue
		if not candidate.can_be_gathered() or not candidate.can_accept_gatherer():
			continue
		var distance: float = _last_resource_position.distance_to(candidate.global_position)
		if distance < best_distance:
			best_distance = distance
			best = candidate
	if best == null:
		return false
	_leave_gather_site()
	target_resource = best
	best.add_gatherer(self)
	_last_resource_position = best.global_position
	return true

func _end_gather_command() -> void:
	_leave_gather_site()
	status_command = Command.NONE
	status_activity = Activity.IDLE

## --- Combat ---

## Buildings are carved out of the navmesh with their footprint, so paths end
## well beyond a typical melee attack_range; units must count that footprint
## as part of "close enough" or they'd approach, stop at the carved edge short
## of attack_range, and never actually start attacking.
func _effective_attack_range() -> float:
	if attack_target is ProductionBuilding:
		return attack_range + attack_target.get_footprint_radius()
	return attack_range

## Live Blacksmith weapon-upgrade bonus on top of the exported stat, same
## "computed live, not baked into the field itself" approach as the Monarch
## aura attack-speed bonus — then the owner's research: more against buildings
## (Siegebreakers), more while badly hurt (Relentless).
func _effective_attack_damage(target: Node3D = null) -> int:
	var damage := attack_damage + UnitUpgrades.get_weapon_bonus(owner_peer_id, unit_category)
	var extra := 0.0
	if target is ProductionBuilding:
		extra += Research.bonus(owner_peer_id, ResearchNode.Stat.BUILDING_DAMAGE)
	if status_current_health < max_health * Research.LOW_HEALTH_FRACTION:
		extra += Research.bonus(owner_peer_id, ResearchNode.Stat.LOW_HEALTH_DAMAGE)
	extra += buffs.amount(ResearchNode.Buff.DAMAGE)
	var result: int = roundi(damage * (1.0 + extra)) if extra > 0.0 else damage
	if target is ProductionBuilding and building_damage_multiplier != 1.0:
		result = roundi(result * building_damage_multiplier)
	return result

func _head_to_target() -> void:
	if not _is_target_alive(attack_target) or (_in_hold_fight() and not _hold_can_reach(attack_target)):
		_find_new_target_or_idle()
		return
	status_activity = Activity.TO_TARGET
	nav_agent.target_desired_distance = _effective_attack_range()
	_chase_repath_timer = CHASE_REPATH_INTERVAL
	_chase_target_position = attack_target.global_position
	move_to(_chase_target_position)

## Keeps the nav destination on the target while closing, so a chase follows
## the target's current position rather than the one it held when the chase
## started. Buildings never move, so this only runs for unit targets.
func _tick_chase(delta: float) -> void:
	if not _is_target_alive(attack_target) or attack_target is ProductionBuilding:
		return
	_chase_repath_timer -= delta
	if _chase_repath_timer > 0.0:
		return
	_chase_repath_timer = CHASE_REPATH_INTERVAL
	## Same leash as _tick_attacking: now that a chase actually follows a moving
	## target, a leashed guard would otherwise be dragged off its post for good
	## by anything that keeps running, since it never gets into attack range for
	## the check there to fire.
	if leash_radius > 0.0 and global_position.distance_to(leash_origin.global_position) > leash_radius:
		attack_target = null
		_advance_patrol()
		return
	var current: Vector3 = attack_target.global_position
	if _chase_target_position.distance_to(current) < CHASE_REPATH_EPSILON:
		return
	_chase_target_position = current
	move_to(current)

func _target_in_reach() -> bool:
	return _is_target_alive(attack_target) \
			and _flat_distance(global_position, attack_target.global_position) <= _effective_attack_range()

## attack_range, plus a building's footprint (see _effective_attack_range).
func _reach_to(target: Node3D) -> float:
	if target is ProductionBuilding:
		return attack_range + target.get_footprint_radius()
	return attack_range

func _counts_as_melee() -> bool:
	return can_fight and projectile_scene == null

## A melee unit still closing on a target that MELEE_CROWD_LIMIT other melee
## units will reach first switches to the least crowded enemy standing right
## beside it, so the overflow spreads along the enemy line rather than queueing
## up behind one man. Applies to hand-picked targets too, but only ever swaps
## within MELEE_OVERFLOW_RADIUS of them, so the unit still joins the fight it
## was sent into.
func _tick_melee_overflow(delta: float) -> void:
	if not _counts_as_melee() or not _is_target_alive(attack_target) or not (attack_target is Unit):
		return
	_overflow_scan_timer -= delta
	if _overflow_scan_timer > 0.0:
		return
	_overflow_scan_timer = MELEE_OVERFLOW_SCAN_INTERVAL
	var target_pos: Vector3 = attack_target.global_position
	var my_distance := _flat_distance(global_position, target_pos)
	if my_distance <= _effective_attack_range() * ATTACK_LEASH_SLACK:
		return
	var ahead := 0
	for other in UnitGrid.units_near(get_tree(), target_pos, my_distance):
		if other != self and other.attack_target == attack_target and other._counts_as_melee():
			ahead += 1
	if ahead < MELEE_CROWD_LIMIT:
		return
	var best: Unit = null
	var best_crowd: int = attack_target.melee_attackers - 1
	for other in UnitGrid.units_near(get_tree(), target_pos, MELEE_OVERFLOW_RADIUS):
		if other == attack_target or not Teams.is_enemy(owner_peer_id, other.owner_peer_id) or not CombatUtils.is_worth_attacking(other):
			continue
		if leash_radius > 0.0 and leash_origin.global_position.distance_to(other.global_position) > leash_radius:
			continue
		if other.melee_attackers < best_crowd:
			best = other
			best_crowd = other.melee_attackers
	if best != null:
		attack_target = best
		_head_to_target()

## Cached _melee_reach_blocked(), refreshed on a short timer.
func _update_reach_blocked(delta: float) -> bool:
	_reach_check_timer -= delta
	if _reach_check_timer <= 0.0:
		_reach_check_timer = MELEE_BLOCK_CHECK_INTERVAL
		_reach_blocked = _melee_reach_blocked()
	return _reach_blocked

## Whether another body stands between this melee unit and its (unit) target
## — see MELEE_BLOCK_WIDTH. Ranged units, and attacks on buildings (whose wide
## footprint has room all round), are never blocked.
func _melee_reach_blocked() -> bool:
	if not _counts_as_melee() or not _is_target_alive(attack_target) or not (attack_target is Unit):
		return false
	var to_target: Vector3 = attack_target.global_position - global_position
	to_target.y = 0.0
	var dist := to_target.length()
	if dist < 0.01 or dist > _effective_attack_range() + MELEE_BLOCK_QUEUE_DEPTH:
		return false
	var dir := to_target / dist
	for other in UnitGrid.units_near(get_tree(), global_position, dist):
		if other == self or other == attack_target:
			continue
		var rel := other.global_position - global_position
		rel.y = 0.0
		var along := rel.dot(dir)
		if along < MELEE_BLOCK_MARGIN or along >= dist:
			continue
		if (rel - dir * along).length() < MELEE_BLOCK_WIDTH:
			return true
	return false

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
	## Shoved well out of its place in a fighting block: back into line before
	## shooting on (see _tick_formation_place).
	if in_formation_fight and _in_hold_fight() \
			and _flat_distance(global_position, formation_fight_place) > FORMATION_PLACE_DRIFT_MAX \
					+ (MELEE_FORMATION_STEP if _counts_as_melee() else 0.0):
		_hold_engagement = false
		attack_target = null
		status_command = Command.NONE
		status_activity = Activity.IDLE
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

	## Someone got between this unit and its target (pushed in, or the target
	## stepped back behind another body): no swinging through them.
	if _update_reach_blocked(delta):
		return

	attack_timer += delta
	## A nearby allied Monarch's passive aura can shrink the effective cooldown
	## (not the exported stat itself — this is computed live each tick).
	var effective_cooldown := attack_cooldown * (1.0 - CombatUtils.nearby_aura_attack_speed_bonus(get_tree(), self)) \
			/ (1.0 + buffs.amount(ResearchNode.Buff.ATTACK_SPEED))
	if attack_timer >= effective_cooldown:
		attack_timer = 0.0
		_play_attack_swing()
		if projectile_scene != null:
			## Damage lands later, when the shot actually arrives (see
			## _tick_pending_projectiles) — the shooter can keep re-nocking on
			## its own cooldown in the meantime rather than waiting for it.
			_fire_projectile(attack_target)
		else:
			attack_target.take_damage(_effective_attack_damage(attack_target), self)
			if not _is_target_alive(attack_target):
				_find_new_target_or_idle()

func _fire_projectile(target: Node3D) -> void:
	var dist := global_position.distance_to(target.global_position)
	var travel_time := dist / maxf(projectile_speed, 0.01)
	var damage := _effective_attack_damage(target)
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
		return target.can_be_attacked()
	return false

func _find_new_target_or_idle() -> void:
	## A holding unit's own fight: switch to anything else already in reach,
	## otherwise settle back into its stance where it stands.
	if _in_hold_fight():
		var in_reach: Node3D = _formation_target_in_reach()
		if in_reach == null:
			in_reach = _nearest_in_place_reach()
		if in_reach:
			attack_target = in_reach
			_start_attacking()
			return
		_hold_engagement = false
		attack_target = null
		status_command = Command.NONE
		status_activity = Activity.IDLE
		nav_agent.target_position = global_position
		return
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
	if wander_radius > 0.0 and is_instance_valid(wander_origin):
		## Straight back to a new leg when this came from a fight that dragged
		## the unit off its post (see the leash check in _tick_attacking) —
		## pausing here would leave it loitering wherever the chase ended.
		if global_position.distance_to(wander_origin.global_position) > wander_radius:
			_begin_wander_leg()
			return
		## Otherwise stand still for a beat before drifting off again; the
		## pause is ticked (and scanned through) by _tick_wander_pause.
		status_activity = Activity.IDLE
		_wander_pause_timer = randf_range(WANDER_PAUSE_MIN, WANDER_PAUSE_MAX)
		return
	if patrol_points.is_empty():
		status_command = Command.NONE
		status_activity = Activity.IDLE
		return
	patrol_index = (patrol_index + 1) % patrol_points.size()
	status_activity = Activity.MOVING
	nav_agent.target_desired_distance = MOVE_ARRIVAL_DISTANCE
	move_to(patrol_points[patrol_index])

## Walks to a fresh random point within wander_radius of wander_origin.
func _begin_wander_leg() -> void:
	status_activity = Activity.MOVING
	var angle := randf() * TAU
	var distance := randf_range(wander_radius * WANDER_MIN_LEG_FRACTION, wander_radius)
	var point := wander_origin.global_position + Vector3(cos(angle), 0.0, sin(angle)) * distance
	nav_agent.target_desired_distance = MOVE_ARRIVAL_DISTANCE
	move_to(point)

## Standing between wander legs: still Command.PATROL, so the idle
## standing-guard scan in _physics_process (which only covers Command.NONE)
## doesn't apply — this keeps watching for enemies the same way the moving
## half of a patrol does.
func _tick_wander_pause(delta: float) -> void:
	_enemy_scan_timer -= delta
	if _enemy_scan_timer <= 0.0:
		_enemy_scan_timer = ENEMY_SCAN_INTERVAL
		var enemy := _find_nearest_enemy_in_range(aggro_range)
		if enemy:
			attack_target = enemy
			_head_to_target()
			return
	_wander_pause_timer -= delta
	if _wander_pause_timer <= 0.0:
		if is_instance_valid(wander_origin):
			_begin_wander_leg()
		else:
			status_command = Command.NONE

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
		if not Teams.is_enemy(owner_peer_id, candidate.owner_peer_id) or not _is_target_alive(candidate):
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

## Melee units score each candidate by distance plus MELEE_CROWD_PENALTY per
## melee attacker already on it (this unit itself not counted), so they spread
## across nearby enemies; `search_range` still limits the raw distance.
func _find_nearest_enemy_in_range(search_range: float) -> Unit:
	var nearest: Unit = null
	var nearest_score := INF
	var melee := _counts_as_melee()
	for node in UnitGrid.enemies_near(get_tree(), global_position, search_range, owner_peer_id):
		var other: Unit = node
		if not _is_target_alive(other):
			continue
		## Overkill guard: a target that already has enough arrows in the air to
		## kill it isn't worth another shot. Skipping it here is what spreads a
		## volley across the enemy line instead of stacking it on one dying unit.
		if not CombatUtils.is_worth_attacking(other):
			continue
		if leash_radius > 0.0 and leash_origin.global_position.distance_to(other.global_position) > leash_radius:
			continue
		var dist := global_position.distance_to(other.global_position)
		if dist > search_range:
			continue
		var score := dist
		if melee:
			var crowd: int = other.melee_attackers - (1 if other == attack_target else 0)
			score += maxi(crowd, 0) * MELEE_CROWD_PENALTY
		if score <= nearest_score:
			nearest = other
			nearest_score = score
	return nearest

func _die(attacker: Node3D = null) -> void:
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
	## A summon never reserved any population (see Research._summon).
	if not summoned:
		Population.release(owner_peer_id, population_cost)
	var main := get_tree().current_scene
	if main is Main and main.research != null:
		var credit: int = power_credit_peer if Research.now() - power_credit_time <= Research.POWER_CREDIT_SECONDS else 0
		main.research.award_kill(self, attacker, credit)
		## Quest steps count kills too, on looser terms than research does
		## (which skips summons and anything without a living killer).
		if main.quests != null:
			var killer: int = credit
			if attacker != null and is_instance_valid(attacker) and "owner_peer_id" in attacker:
				killer = attacker.owner_peer_id
			main.quests.notify(&"unit_killed", {
				killer_peer = killer, victim_peer = owner_peer_id, victim_name = display_name,
			})

	## Decided here on the host and sent as a world-space direction, so every
	## peer launches the corpse the same way even if the attacker has already
	## been freed by the time the RPC lands. With no known attacker it flies
	## backward off its own facing, which is usually toward whatever hit it.
	var away := Vector3.ZERO
	if attacker != null and is_instance_valid(attacker):
		away = global_position - attacker.global_position
		away.y = 0.0
	if away.length_squared() <= 0.0001:
		away = -Vector3(sin(rotation.y), 0.0, cos(rotation.y))

	## A unit spawned at runtime through UnitSpawner is auto-despawned on
	## every client the moment the host frees it — but a hand-placed unit
	## (e.g. an Objective's guards, present in the scene file itself rather
	## than spawned) has no spawner tracking it, so nothing ever tells
	## clients to remove it. This RPC covers both cases identically: it plays
	## the death animation and frees the node on every peer, not just here.
	_play_death_and_remove.rpc(away.normalized())

@rpc("authority", "call_local", "reliable")
func _play_death_and_remove(away: Vector3) -> void:
	_death_playing = true
	## Corpses don't need picking out behind buildings.
	sprite.material_overlay = null
	if crew_sprite:
		crew_sprite.material_overlay = null
		crew_sprite.play("death")
		crew_sprite.pause()
	var has_death_anim: bool = sprite.sprite_frames and sprite.sprite_frames.has_animation("death")
	## Held on the clip's first frame through the flight; played directly
	## rather than via _set_animation, since every peer runs this RPC itself
	## and doesn't need the host relaying it.
	if has_death_anim:
		sprite.play("death")
		sprite.pause()
	await _play_death_knockback(away).finished
	if crew_sprite:
		crew_sprite.play()
	if has_death_anim:
		sprite.play()
		var frame_count: int = sprite.sprite_frames.get_frame_count("death")
		var fps: float = sprite.sprite_frames.get_animation_speed("death")
		await get_tree().create_timer(frame_count / maxf(fps, 1.0)).timeout
	queue_free()

## Runs on the sprite only, like the hit recoil — the body itself stays put, so
## there's nothing to fight the MultiplayerSynchronizer and every peer can play
## it locally from the direction the RPC handed over.
func _play_death_knockback(away: Vector3) -> Tween:
	if _sprite_move_tween and _sprite_move_tween.is_valid():
		_sprite_move_tween.kill()
	## Same Y-rotation-only reasoning as play_hit_reaction.
	var local_away: Vector3 = global_transform.basis.inverse() * away
	var base := _sprite_base_position

	var durations: Array[float] = []
	var weights: Array[float] = []
	var total_weight := 0.0
	for i in DEATH_BOUNCE_HEIGHTS.size():
		var t := 2.0 * sqrt(2.0 * DEATH_BOUNCE_HEIGHTS[i] / DEATH_BOUNCE_GRAVITY)
		var w := t * pow(DEATH_BOUNCE_SPEED_DECAY, i)
		durations.append(t)
		weights.append(w)
		total_weight += w

	_death_squash(DEATH_LAUNCH_STRETCH_SCALE, 1.0)
	var tween := create_tween()
	var travelled := 0.0
	for i in durations.size():
		var height: float = DEATH_BOUNCE_HEIGHTS[i]
		var from_offset := local_away * travelled
		travelled += DEATH_KNOCKBACK_DISTANCE * weights[i] / total_weight
		var to_offset := local_away * travelled
		tween.tween_method(func(p: float) -> void:
			sprite.position = base + from_offset.lerp(to_offset, p) \
					+ Vector3.UP * height * 4.0 * p * (1.0 - p)
		, 0.0, 1.0, durations[i])
		tween.tween_callback(_death_squash.bind(DEATH_LAND_SQUASH_SCALE, height / DEATH_BOUNCE_HEIGHTS[0]))
	return tween

## Snaps toward `target_scale` by `strength` (0 = none, 1 = full) and wobbles
## back elastically, so later, smaller bounces land softer than the first.
func _death_squash(target_scale: Vector3, strength: float) -> void:
	if _sprite_scale_tween and _sprite_scale_tween.is_valid():
		_sprite_scale_tween.kill()
	sprite.scale = _sprite_base_scale * Vector3.ONE.lerp(target_scale, strength)
	_sprite_scale_tween = create_tween()
	_sprite_scale_tween.tween_property(sprite, "scale", _sprite_base_scale, DEATH_LAND_SQUASH_DURATION) \
			.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

## Ground-following state (see _slide). _grounded: standing at the terrain's
## height since the last move — cleared when the unit is placed somewhere by
## hand (teleport). _walk_poly: the navmesh polygon (in _walk_index, the
## NavWalkability it indexes into) the unit was last standing in, or -1.
var _grounded: bool = false
var _walk_poly: int = -1
var _walk_index: NavWalkability = null

## How far a blocked step is turned, either side, looking for walkable ground
## to slide along (see _ground_step).
const EDGE_SLIDE_ANGLES: Array[float] = [PI / 6.0, PI / 3.0, PI * 0.47]
## A unit whose step keeps getting stopped or turned hard aside is wedged —
## typically a separation shove left the straight line to its next waypoint
## cutting through a tree's carved-out corner. After this long it re-paths from
## where it actually is (a fresh path is always walkable from its start), and
## again every BLOCKED_REPATH_INTERVAL while still wedged.
const BLOCKED_REPATH_TIME: float = 0.4
const BLOCKED_REPATH_INTERVAL: float = 1.5
## A move order still wedged this long within BLOCKED_ARRIVAL_RADIUS of its
## target counts as arrived — its slot is in or against something it can't
## stand in, the same as a path that ends short (see PATH_END_GIVE_UP).
const BLOCKED_GIVE_UP_TIME: float = 1.5
const BLOCKED_ARRIVAL_RADIUS: float = 2.5
## Still wedged this long and the unit is somewhere no path gets it out of —
## a pocket of ground walled in by trees. It is let through unclamped for
## BLOCKED_ESCAPE_DURATION, squeezing between the trunks the way a collision
## capsule could.
const BLOCKED_ESCAPE_TIME: float = 3.0
const BLOCKED_ESCAPE_DURATION: float = 1.0
## The path waypoint this tick's steering heads for, or INF when the unit isn't
## following a path this tick (see _ground_step).
var _path_waypoint: Vector3 = Vector3.INF
## The navigation server joins navmesh polygons across small gaps (its edge
## merging), and a path can run straight over one. A path-following unit may
## cross an unwalkable stretch up to this long on the way to its waypoint.
const PATH_GAP_MAX: float = 1.0
const PATH_GAP_SAMPLE: float = 0.25
var _blocked_time: float = 0.0
var _next_blocked_repath: float = BLOCKED_REPATH_TIME
var _unclamped_time: float = 0.0

## Moves the unit by its velocity for this tick. On a TerraBrush map that's a
## step across the ground: height read straight off the terrain, and kept to
## the walkable navmesh (which already has buildings, trees, cliffs and deep
## water carved out around it) instead of sweeping a collision shape — the
## sweep was the most expensive thing a unit did each tick. Anywhere else it's
## move_and_slide(). A unit standing still doesn't move at all.
func _slide() -> void:
	var terrain := GroundHeight.terrain(get_tree())
	var still: bool = absf(velocity.x) < 0.01 and absf(velocity.z) < 0.01
	if terrain == null:
		## is_on_floor() is as of the last real slide, which is still true for a
		## unit that hasn't moved since.
		if still and is_on_floor():
			return
		if not PerfStats.enabled:
			move_and_slide()
			return
		var slide_start := Time.get_ticks_usec()
		move_and_slide()
		PerfStats.add_slide(Time.get_ticks_usec() - slide_start)
		return
	if still and _grounded:
		_track_blocked(false, 0.0)
		return
	if not PerfStats.enabled:
		_ground_step(terrain, get_physics_process_delta_time())
		return
	var start := Time.get_ticks_usec()
	_ground_step(terrain, get_physics_process_delta_time())
	PerfStats.add_slide(Time.get_ticks_usec() - start)

func _ground_step(terrain: TerraBrush, delta: float) -> void:
	var step := Vector3(velocity.x, 0.0, velocity.z) * delta
	var next := global_position + step
	var wedged := false
	var walkability := NavWalkability.current
	if _unclamped_time > 0.0:
		_unclamped_time -= delta
		walkability = null
		_walk_poly = -1
	if walkability != null:
		if walkability != _walk_index:
			_walk_index = walkability
			_walk_poly = walkability.polygon_at(global_position)
		var poly := walkability.polygon_at(next, _walk_poly)
		## Only a unit already on walkable ground is held to it — one that
		## isn't (spawned or shoved off the edge) is free to walk back on.
		## Let through along the path, but still held to the walkable ground
		## for anything else (a separation shove, steering off the path).
		if poly < 0 and _walk_poly >= 0 and _path_crosses_gap(walkability, _path_waypoint):
			poly = _walk_poly
		if poly < 0 and _walk_poly >= 0:
			## Turn the step progressively further from straight ahead, either
			## side, until it lands on walkable ground — shortened to how much
			## of it still goes the intended way — so a unit slides along an
			## edge or round a tree's corner instead of stopping dead at it.
			for angle in EDGE_SLIDE_ANGLES:
				for side in [1.0, -1.0]:
					var turned: Vector3 = step.rotated(Vector3.UP, angle * side) * cos(angle)
					poly = walkability.polygon_at(global_position + turned, _walk_poly)
					if poly >= 0:
						next = global_position + turned
						wedged = angle > PI / 4.0
						break
				if poly >= 0:
					break
			if poly < 0:
				next = global_position
				poly = _walk_poly
				wedged = true
		_walk_poly = poly
	_track_blocked(wedged, delta)
	next.y = terrain.getHeightAtPosition(next.x, next.z, true)
	global_position = next
	_grounded = true

## Whether the unit is at a gap the path itself runs across: heading for
## `waypoint`, walkable ground resumes within PATH_GAP_MAX (or the waypoint is
## reached first). Only looks that far ahead — this runs for every blocked step.
func _path_crosses_gap(walkability: NavWalkability, waypoint: Vector3) -> bool:
	if not waypoint.is_finite():
		return false
	var distance := _flat_distance(global_position, waypoint)
	if distance < 0.01:
		return false
	var reach: float = minf(distance, PATH_GAP_MAX + PATH_GAP_SAMPLE)
	var steps: int = ceili(reach / PATH_GAP_SAMPLE)
	for step in range(1, steps + 1):
		var along: float = reach * step / steps
		if walkability.polygon_at(global_position.lerp(waypoint, along / distance)) >= 0:
			return along - PATH_GAP_SAMPLE <= PATH_GAP_MAX
	return distance <= PATH_GAP_MAX

func _track_blocked(wedged: bool, delta: float) -> void:
	if not wedged:
		_blocked_time = 0.0
		_next_blocked_repath = BLOCKED_REPATH_TIME
		return
	_blocked_time += delta
	if _blocked_time >= BLOCKED_ESCAPE_TIME:
		_unclamped_time = BLOCKED_ESCAPE_DURATION
		_blocked_time = 0.0
		_next_blocked_repath = BLOCKED_REPATH_TIME
		return
	if _blocked_time >= _next_blocked_repath:
		_next_blocked_repath += BLOCKED_REPATH_INTERVAL
		repath()
