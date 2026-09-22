class_name AiProfile
extends Resource
## One AI difficulty's tuning. The brain (AiPlayer and its parts) is the same
## at every difficulty; these numbers are the only thing that changes. One
## .tres per difficulty in resources/ai/, indexed by Network.AiDifficulty.

@export_group("Pace")
## Seconds between decisions. Lower reacts faster.
@export var think_interval: float = 1.0
## Most unit orders (gather/build assignments) given per decision — caps how
## much gets fixed at once, so an easier AI leaves villagers idle longer.
@export var max_orders_per_think: int = 4

@export_group("Economy")
@export var target_villagers: int = 18
## Villagers are trained ahead of soldiers until this share of
## target_villagers is reached — lower gets an army (and the first capture
## waves) out sooner at the cost of a slower economy.
@export_range(0.0, 1.0, 0.05) var economy_first_share: float = 0.6
## Villagers kept queued at each Town Center at once.
@export var villager_queue: int = 1
## Fraction of villagers on gold once a Mine is working.
@export_range(0.0, 1.0, 0.05) var gold_worker_share: float = 0.4
## Build a House once free population drops to this (plus one per working
## production building).
@export var house_headroom: int = 2
## Stop building Houses past this population cap.
@export var max_population: int = 80
## Villagers sent to each new construction.
@export var builders_per_site: int = 2

@export_group("Build Order")
## Villager count at which each is started; -1 never.
@export var first_mine_at_villagers: int = 4
@export var second_mine_at_villagers: int = 14
@export var barracks_at_villagers: int = 7
@export var archery_range_at_villagers: int = 9
@export var stables_at_villagers: int = 12
@export var second_barracks_at_villagers: int = -1
## The two tier-2 buildings, matched by name rather than by what they train:
## a Blacksmith trains nothing at all, and an Arcane Sanctum trains ranged
## units like the Archery Range does, so neither can be found the way
## AiBaseBuilder._military_type finds the others.
@export var blacksmith_at_villagers: int = 14
@export var arcane_sanctum_at_villagers: int = 18

@export_group("Military")
## Units kept queued at each military building at once.
@export var military_queue: int = 2
## Soldiers (living plus queued) past which no more are trained.
@export var max_army: int = 70
## How many men this AI raises a regiment with — any multiple of
## Regiment.STEP. 0 leaves its army loose, which is how it fought before
## regiments existed and the fallback if they ever cost it a match.
##
## Deliberately small. The AI trains a weighted mix across four roles under
## max_army, so it rarely holds more than a dozen of any single kind at once —
## and a regiment is one kind of soldier. Measured over a five-minute match on
## a four-player map, three AIs reached armies of 20-48 and raised no
## regiments at all at 12; six is comfortably inside what its mix produces.
## Bigger AI bodies would need its production biased toward finishing one
## regiment's worth of a type before starting the next.
@export var regiment_size: int = 6
## Whether a monster's cost is set aside at an owned Shrine until it can be
## afforded (otherwise one's only bought when the money happens to be there).
@export var save_for_monsters: bool = true
## Whether upgrades that unlock a better unit (Crossbows, Halberds, Lances,
## Ancient Texts — see the UnitUnlocks autoload) are bought when affordable.
## Plain weapon/armor upgrades are never bought either way.
@export var buys_unit_unlocks: bool = true
## Fewest hostiles an area ability must catch before it's cast. 0 = never.
@export var ability_min_targets: int = 3
## While the army is smaller than this many soldiers per villager, soldiers
## are trained ahead of more villagers (wood is the bottleneck for both).
@export var army_per_villager: float = 0.5
## Target army make-up, by unit role. Normalised at use, so only the ratios
## matter.
@export_group("Combat")
## Conquest only: match time before the first wave may go for a capture
## point, and the soldiers it needs — points are the early game, so both are
## well below the base-attack numbers.
@export var first_capture_seconds: float = 150.0
@export var capture_min_army: int = 6
## Match time before the first attack wave may leave for an enemy base.
@export var first_attack_seconds: float = 480.0
## Soldiers that must be free to go (beyond the home guard) before a wave
## leaves.
@export var attack_min_army: int = 14
## Most soldiers one wave takes; the rest stay home.
@export var attack_max_wave: int = 999
## A wave only leaves once it's this many times stronger than the biggest
## army seen from its target recently. 0 = doesn't check.
@export var attack_advantage: float = 1.0
## Fraction of the army that stays home when a wave leaves.
@export_range(0.0, 1.0, 0.05) var home_guard_share: float = 0.2
## Soldiers gathered at home before they're sent on to join a wave.
@export var reinforce_batch: int = 5
## A wave pulls back once it's weaker than this fraction of the enemy
## fighting it. 0 = fights to the last.
@export var retreat_threshold: float = 0.5
## Seconds between enemies turning up at the base and the army reacting.
@export var defend_reaction_seconds: float = 3.0
## Whether an attack wave is called home when the base can't hold alone.
@export var recall_army_to_defend: bool = true
## Whether villagers run for the Town Center when the base can't hold.
@export var villagers_flee: bool = true
## Seconds a block is caught in the flank or rear before it turns to meet the
## attacker (see AiTactics). -1 = never.
@export var reface_reaction_seconds: float = 3.0
## Whether cavalry leaves the block to ride round and charge flanks, archers
## and siege (see AiTactics), rather than just marching with the wave.
@export var cavalry_tactics: bool = true
## Whether cavalry wheels away once its charge is spent, to charge again.
@export var cavalry_recharge: bool = false

@export_group("Army Mix")
@export var infantry_weight: float = 0.45
@export var spear_weight: float = 0.2
@export var ranged_weight: float = 0.35
@export var cavalry_weight: float = 0.3
