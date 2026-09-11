class_name Ability
extends Resource
## One unit ability — a Monarch's (Unit.monarch_abilities) or one a unit type
## always has (Unit.abilities, e.g. the Shrine monsters). A flat resource
## (matching BuildingType/ProducibleItem style) rather than subclasses per
## kind — irrelevant fields for a given kind are just left at default, and
## both the command panel and a future AI can iterate an Array[Ability]
## generically by switching on `kind` instead of needing bespoke
## per-named-ability code.

enum Kind { PASSIVE_AURA, ACTIVATED_TARGET_POINT, ACTIVATED_AREA }

@export var ability_name: String = "Ability"
## Shown in the command-card tooltip alongside ability_name; the button
## itself just shows a hotkey letter (see ABILITY_HOTKEYS in main.gd).
@export_multiline var description: String = ""
@export var icon: Texture2D
@export var kind: Kind = Kind.PASSIVE_AURA

@export_group("Passive Aura")
## Continuously affects nearby allies owned by the same player as the Monarch.
@export var aura_radius: float = 6.0
## Fractional cooldown reduction applied to allies' attacks, e.g. 0.2 = 20% faster.
@export var aura_attack_speed_bonus: float = 0.0
## Flat damage reduction applied to hits allies take.
@export var aura_armor_bonus: int = 0

@export_group("Activated")
## How far from the caster a target point may be. A target further away than
## this makes the caster walk until it's in range, then cast.
@export var activation_range: float = 12.0
@export var cooldown: float = 20.0
## Optional per-use cost; empty means free (still gated by cooldown).
@export var costs: Array[ResourceCost] = []

@export_group("Teleport (target point)")
## Allies within this radius of the Monarch (at the moment of activation) are affected too.
@export var affected_ally_radius: float = 4.0

@export_group("Area Effect")
## Every enemy unit within this radius of the target point is hit.
@export var area_radius: float = 3.0
## Dealt once, the instant the ability lands.
@export var area_damage: int = 0
## Burn/poison: this much damage again every second for dot_duration seconds.
@export var dot_damage_per_second: int = 0
@export var dot_duration: float = 0.0
## Fraction of move speed taken away, e.g. 0.5 = half speed.
@export_range(0.0, 0.95) var slow_fraction: float = 0.0
@export var slow_duration: float = 0.0
## Stunned units can't move, attack, gather or build.
@export var stun_duration: float = 0.0
## Tints both the targeting decal and the impact effect.
@export var effect_color: Color = Color(1.0, 0.5, 0.15)
## How long the impact's ground flash stays up, in seconds — it holds at full
## strength for the first half, then fades out over the second.
@export_range(0.2, 10.0, 0.1, "or_greater") var effect_duration: float = 1.8
## How long each impact spark lives, in seconds.
@export_range(0.1, 5.0, 0.1, "or_greater") var effect_particle_lifetime: float = 1.2
@export var impact_shake: float = 0.35

@export_group("Cast")
## Seconds into the caster's "cast" animation (see Unit.cast_row) before the
## ability actually goes off — lines the launch up with the frame where the
## monster breathes, throws or slams. Committed once the animation starts:
## a new order can walk the caster away, but the ability still fires.
@export_range(0.0, 3.0, 0.05, "or_greater") var cast_windup: float = 0.4
## Played at the caster's mouth/hands the moment the ability goes off, turned
## toward the target if the effect is set to orient.
@export var cast_effect: SpriteEffect
## Where cast_effect and the projectile start, relative to the caster: x is
## forward along its facing, y is up.
@export var launch_offset: Vector2 = Vector2(0.6, 0.9)

@export_group("Projectile")
enum ProjectileStyle { NONE, FLYING, GROUND_WAVE }
## NONE lands the impact at the target the instant the ability goes off.
## FLYING sends projectile_effect through the air to the target. GROUND_WAVE
## erupts projectile_effect along the ground from caster to target instead.
@export var projectile_style: ProjectileStyle = ProjectileStyle.NONE
@export var projectile_effect: SpriteEffect
@export var projectile_speed: float = 12.0
@export var projectile_arc_height: float = 0.0
## GROUND_WAVE only: distance between eruptions along the path.
@export var wave_spacing: float = 1.0
## FLYING only: sparks shed behind the projectile, in effect_color.
@export var projectile_trail: bool = true

@export_group("Impact")
## Played at the target when the ability lands, on top of the ground flash
## and sparks every area ability gets.
@export var impact_effect: SpriteEffect
## One full-size burst at the centre plus this many smaller ones scattered
## across area_radius, staggered slightly, so a big area reads as covered
## rather than as a single explosion in the middle.
@export var impact_scatter_count: int = 0

@export_group("Lingering Zone")
## Seconds the area stays on the ground after landing. 0 = gone on impact.
## While it lasts, every enemy unit standing in it — including ones that walk
## in afterwards — is hurt once a second (see AbilityZone).
@export var linger_duration: float = 0.0
@export var linger_damage_per_second: int = 0
## Looped at scattered points across the zone for as long as it lasts, on
## top of the ground disc and rising particles every zone gets.
@export var linger_effect: SpriteEffect
@export var linger_effect_count: int = 5

func is_activated() -> bool:
	return kind != Kind.PASSIVE_AURA
