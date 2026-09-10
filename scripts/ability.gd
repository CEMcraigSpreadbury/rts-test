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

func is_activated() -> bool:
	return kind != Kind.PASSIVE_AURA
