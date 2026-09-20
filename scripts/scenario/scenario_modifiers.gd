class_name ScenarioModifiers
extends Resource
## What a scenario changes about the ordinary rules — for one slot, or (on the
## Scenario node itself) for everyone it doesn't name. Every field defaults to
## ordinary skirmish, so empty modifiers change nothing and a normal match
## never notices this exists.
##
## Everything here is asked through MatchRules, never read directly.

## What this player pays, as a fraction of the listed price, for buildings,
## units and upgrades alike. 1.0 = unchanged.
@export_range(0.0, 4.0, 0.05) var cost_multiplier: float = 1.0
## Buildings this player may put up, by BuildingType.building_name. Empty =
## the whole roster. (Names rather than resources so the list survives the
## roster being edited, and reads properly in the inspector.)
@export var allowed_buildings: Array[String] = []
## Units and upgrades this player may train, by ProducibleItem.item_name.
## Empty = everything the building offers.
@export var allowed_items: Array[String] = []
## Research unlocks this player starts the mission already holding, by tag
## (see the UnitUnlocks autoload) — "shields", "crossbows", "halberds",
## "lances", "ancient_texts". Empty = none, i.e. they have to be researched as usual.
@export var starting_unlocks: Array[StringName] = []
## Which monsters a Shrine may offer, by ProducibleItem.item_name. Empty = the
## usual roll. Read from the Scenario's own modifiers rather than a slot's: a
## Shrine is rolled once for the whole match, not per player.
@export var allowed_monsters: Array[String] = []
## Highest research tier this player may buy. -1 = no limit, 0 = no research
## at all.
@export var research_tier_cap: int = -1
## Flat population cap for this player; 0 = the usual houses-and-town-centre
## rules.
@export var population_cap: int = 0
## Parts of the HUD this player cannot use yet — how a tutorial introduces the
## game one piece at a time. Known names: "research", "build", "formations",
## "control_groups". Anything else here is ignored.
@export var locked_hud: Array[String] = []
