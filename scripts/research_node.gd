class_name ResearchNode
extends Resource
## One of a faction's three powers (see Faction.powers): bought once per match
## with research points, in order (the first, then the second, then the
## ultimate), then cast for free at a spot the player can see and put on
## cooldown. Its index in Faction.powers is what goes over the wire.

@export var node_name: String = "Power"
@export_multiline var description: String = ""
@export var icon: Texture2D
## Its UiGlyphs icon in the research panel and on the power bar. Takes the place
## of `icon` when set; clear it to go back to the pixel art.
@export var glyph: StringName = &""
## 1 early, 2 mid, 3 the ultimate — its card in the Research panel, and what a
## scenario's research_tier_cap counts.
@export_range(1, 3) var tier: int = 1
@export var cost: int = 15

## Short-lived effects a power puts on what it hits, for `duration` seconds
## (see TimedBuffs). Fractions unless noted.
enum Buff {
	NONE,
	ATTACK_SPEED,
	ARMOR, ## armour points (see Unit.ARMOR_REDUCTION_PER_POINT)
	MOVE_SPEED,
	DAMAGE,
	GATHER_SPEED,
	DAMAGE_TAKEN_REDUCTION,
	PRODUCTION_SPEED,
	INVULNERABLE, ## any amount
}

## POINT is cast at a spot. LINE is dragged out from where the button goes
## down: line_length along the drag, line_width across.
enum Aim { POINT, LINE }

@export_group("Power")
@export var cooldown: float = 90.0
@export var radius: float = 6.0
@export var aim: Aim = Aim.POINT
@export var line_length: float = 40.0
@export var line_width: float = 6.0
## Seconds of warning on the ground, seen by everyone, before it lands.
@export var telegraph: float = 0.0
## The caster's cursor drags it about while it lasts (Orbital Lance).
@export var steerable: bool = false
## A scripted spectacle run by PowerEffects (see its START table) in place of
## the plain effects below.
@export var set_piece: StringName = &""
@export var affects_own_units: bool = false
@export var affects_own_buildings: bool = false
@export var affects_enemy_units: bool = false
## How long `buffs` last, and what `heal_fraction` is spread over (0 = healed
## at once).
@export var duration: float = 0.0
## Of each target's max health.
@export var heal_fraction: float = 0.0
## Buff -> amount.
@export var buffs: Dictionary = {}
## Tints the targeting ring and the flash where it lands.
@export var effect_color: Color = Color(1.0, 1.0, 1.0)
## Hits every enemy unit in the radius with this, as if a monster's area
## ability had landed there — damage, stun, burning ground, and its look.
@export var hit_ability: Ability
## This many of summon_scene appear at the target and last `duration`
## seconds. They reserve no population and are worth nothing to their killer.
@export var summon_scene: PackedScene
@export var summon_count: int = 0
