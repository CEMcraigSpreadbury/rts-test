class_name ResearchNode
extends Resource
## One unlock in a Ruler's research tree (see Ruler). Bought once per match
## with research points; its index in Ruler.nodes is what goes over the wire.

enum Kind { PASSIVE, POWER }

## What an owned node changes, read through Research.bonus(peer_id, stat).
## Fractions unless noted (0.15 = +15%). Stats that change a unit or
## building's own numbers (health, speed, vision, tower damage/range) are
## written onto it once — see Research.apply_node_to.
enum Stat {
	NONE,
	MILITARY_TRAIN_SPEED,
	COMBAT_MOVE_SPEED,
	BUILDING_DAMAGE,
	KILL_HEAL, ## HP per killing blow
	LOW_HEALTH_DAMAGE, ## below Research.LOW_HEALTH_FRACTION of max health
	INFANTRY_CAVALRY_HEALTH,
	POPULATION_CAP, ## flat
	GATHER_SPEED,
	BUILDING_HEALTH,
	BUILD_SPEED,
	POINT_GOLD,
	COST_REDUCTION,
	RESEARCH_TRICKLE,
	PERIODIC_INCOME, ## gold and wood each Research.PERIODIC_INCOME_INTERVAL
	TOWER_DAMAGE,
	TOWER_RANGE,
	WALL_HEALTH,
	REGENERATION, ## HP per second out of combat
	ABILITY_DAMAGE_REDUCTION,
	VISION,
	MONSTER_COST_REDUCTION,
	MONSTER_TRAIN_SPEED,
	MONSTER_COOLDOWN_REDUCTION,
	MONSTER_HEALTH,
	HEALING_LIGHT_UPGRADE, ## read by the Healing Light power
	POWER_COOLDOWN_REDUCTION,
}

@export var node_name: String = "Research"
@export_multiline var description: String = ""
@export var icon: Texture2D
## PASSIVE applies everywhere the moment it's bought. POWER is cast at a spot
## the player can see, then goes on cooldown.
@export var kind: Kind = Kind.PASSIVE
## Row in the Research panel, 1 at the top.
@export_range(1, 4) var tier: int = 1
## Horizontal slot in the Research panel, 0-3 across. Fractional values sit a
## node between its parents.
@export var column: float = 0.0
@export var cost: int = 5
## Every one of these must already be owned before this can be bought.
@export var requires: Array[ResearchNode] = []
## Stat -> amount. A POWER can carry these too, for anything it changes
## permanently on top of being castable.
@export var effects: Dictionary = {}

## Short-lived effects a POWER puts on what it hits, for `duration` seconds
## (see TimedBuffs). Fractions unless noted.
enum Buff {
	NONE,
	ATTACK_SPEED,
	ARMOR, ## flat
	MOVE_SPEED,
	DAMAGE,
	GATHER_SPEED,
	DAMAGE_TAKEN_REDUCTION,
	PRODUCTION_SPEED,
	INVULNERABLE, ## any amount
}

@export_group("Power")
@export var cooldown: float = 60.0
@export var radius: float = 6.0
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
## A later node in the tree that improves this power (Renewal -> Healing
## Light): while its owner has any of this stat, the cooldown is scaled by
## upgraded_cooldown_multiplier, and buildings can be hit too if
## upgraded_affects_own_buildings.
@export var upgraded_by: Stat = Stat.NONE
@export var upgraded_cooldown_multiplier: float = 1.0
@export var upgraded_affects_own_buildings: bool = false
## Hits every enemy unit in the radius with this, as if a monster's area
## ability had landed there — damage, stun, burning ground, and its look.
@export var hit_ability: Ability
## Muster: this many of summon_scene appear at the target and last `duration`
## seconds. They reserve no population and are worth nothing to their killer.
@export var summon_scene: PackedScene
@export var summon_count: int = 0
