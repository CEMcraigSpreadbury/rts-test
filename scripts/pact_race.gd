class_name PactRace
extends Resource
## One allied race a player can make a Pact with at a Pact Hall (Gnolls, Dark
## Elves, Star Wanderers). A Pact unlocks this race's buildings in the
## villager build menu, where they train units that spend the separate PACT
## population pool instead of the player's Human one.
##
## The race's own currency (Meat / Souls / Starlight) and its rosters are
## filled in by later steps; what lives here is only what a Pact itself needs.

## Identifies the race everywhere — the pact a hall granted is replicated to
## clients by name (ProductionBuilding.synced_pact_name), so this has to be
## unique across the three and stable once a save/scenario references it.
@export var race_name: String = "Race"
## Tints this race's build-menu category button (step 2) so the three pages
## read apart at a glance.
@export var display_color: Color = Color.WHITE
@export var icon: Texture2D
## What this race's units and buildings are paid for in (Meat / Souls /
## Starlight). Private per player like every other resource, and only shown
## in the resource bar once the player has this Pact.
@export var currency: ResourceType
## Paid to every player holding this Pact regardless of what they have built
## — the last-resort floor under a race whose buildings have all been razed.
## Per second, accumulated as a fraction by Pacts.
@export var passive_income_per_second: float = 0.0
## Scales passive_income_per_second at night, the same way PactGenerator's
## night_multiplier scales a building's income.
@export var passive_night_multiplier: float = 1.0

## Offered in the villager build menu once this race's Pact is made. Empty
## until each race's buildings exist (build-order steps 5-7).
@export var building_types: Array[BuildingType] = []
