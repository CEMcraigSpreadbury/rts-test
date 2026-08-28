class_name Ability
extends Resource
## One Monarch ability. A flat resource (matching BuildingType/ProducibleItem
## style) rather than subclasses per kind — irrelevant fields for a given
## kind are just left at default, and both the command panel and a future AI
## can iterate an Array[Ability] generically by switching on `kind` instead
## of needing bespoke per-named-ability code.

enum Kind { PASSIVE_AURA, ACTIVATED_TARGET_POINT }

@export var ability_name: String = "Ability"
## Shown in the command-card tooltip alongside ability_name; the button
## itself just shows a hotkey letter (see MONARCH_ABILITY_HOTKEYS in main.gd).
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

@export_group("Activated (target point)")
## How far from the Monarch's current position a target point may be.
@export var activation_range: float = 12.0
## Allies within this radius of the Monarch (at the moment of activation) are affected too.
@export var affected_ally_radius: float = 4.0
@export var cooldown: float = 20.0
## Optional per-use cost; empty means free (still gated by cooldown/range).
@export var costs: Array[ResourceCost] = []
