class_name MatchRules
extends RefCounted
## The one place every system asks what this match's rules are: prices, what a
## side may build or train, how far its research goes, its population cap.
## An ordinary skirmish uses the defaults, which change nothing.
##
## Reached statically (MatchRules.active()) the way Research.bonus and Teams
## are, because the things that ask — a Shrine rolling its monsters, a
## building pricing an item — run during _ready, before Main has finished
## setting itself up. Main clears `current` as each match loads and a
## Scenario, if there is one, installs its own in _enter_tree.

static var current: MatchRules = null

## What the campaign difficulty does to the opposition, on top of shifting
## each enemy AI's level: how many of them a wave spawns, and what they start
## with. Indexed by Network.campaign_difficulty (Easy/Normal/Hard).
const DIFFICULTY_SCALE: Array[float] = [0.7, 1.0, 1.4]

static func enemy_scale() -> float:
	return DIFFICULTY_SCALE[clampi(Network.campaign_difficulty, 0, DIFFICULTY_SCALE.size() - 1)]

## --- Realm ---
## The Realm economy (Network.GameMode.REALM): Food comes back, farmed at a
## Mill, and every soldier eats it; Houses and the population cap go, leaving
## only a ceiling high enough that nobody meets it in play; soldiers are bought
## with gold alone, and a villager costs a little food on top of its wood.
## Missions keep their own authored rules, so a scenario is never Realm.
const REALM_POPULATION_CEILING: int = 800
const REALM_VILLAGER_FOOD: int = 8
const FOOD: ResourceType = preload("res://resources/food_resource_type.tres")
const GOLD: ResourceType = preload("res://resources/gold_resource_type.tres")
const WOOD: ResourceType = preload("res://resources/wood_resource_type.tres")
## Only built in a Realm match, and never in one.
const REALM_ONLY_BUILDINGS: Array[String] = ["Mill"]
const NOT_IN_REALM_BUILDINGS: Array[String] = ["House", "Pact Hall"]

static func realm() -> bool:
	return active().scenario == null and Network.game_mode == Network.GameMode.REALM

## A unit's listed price as a Realm match charges it: a soldier's wood, and any
## allied-race currency (Meat, Souls, Starlight — there are no Pacts in Realm),
## is folded into its gold; a worker keeps its wood and adds
## REALM_VILLAGER_FOOD. Outside Realm, `costs` comes back unchanged.
static func realm_unit_costs(costs: Array[ResourceCost], is_worker: bool) -> Array[ResourceCost]:
	if not realm():
		return costs
	var out: Array[ResourceCost] = []
	if is_worker:
		out.assign(costs)
		var food := ResourceCost.new()
		food.resource_type = FOOD
		food.amount = REALM_VILLAGER_FOOD
		out.append(food)
		return out
	var gold := 0
	for cost in costs:
		if cost.resource_type == FOOD:
			out.append(cost)
		else:
			gold += cost.amount
	if gold > 0:
		var entry := ResourceCost.new()
		entry.resource_type = GOLD
		entry.amount = gold
		out.push_front(entry)
	return out

## Never null: no scenario means ordinary rules.
static func active() -> MatchRules:
	if current == null:
		current = MatchRules.new(null)
	return current

var scenario: Scenario = null
## Used by any side the scenario doesn't give its own, and the source of the
## map-wide Shrine monster pool.
var _default: ScenarioModifiers
## peer_id -> ScenarioModifiers, filled as each side is set up.
var _by_peer: Dictionary = {}

func _init(p_scenario: Scenario = null) -> void:
	scenario = p_scenario
	if p_scenario != null and p_scenario.modifiers != null:
		_default = p_scenario.modifiers
	else:
		_default = ScenarioModifiers.new()

## Copied, never referenced: a quest unlocking something mid-mission edits this
## side's rules, and that must not write back into the scenario's authored
## resource — an external .tres is shared and cached, so the change would
## survive into the next attempt at the mission.
func assign(peer_id: int, modifiers: ScenarioModifiers) -> void:
	if modifiers != null:
		_by_peer[peer_id] = modifiers.duplicate()

func modifiers_for(peer_id: int) -> ScenarioModifiers:
	return _by_peer.get(peer_id, _default)

## Modifiers this peer can have changed mid-mission (a quest unlocking a
## building). Copied on first write, so editing one side's rules never reaches
## through a shared resource into everyone else's.
func editable_modifiers_for(peer_id: int) -> ScenarioModifiers:
	if not _by_peer.has(peer_id):
		_by_peer[peer_id] = _default.duplicate()
	return _by_peer[peer_id]

## `costs` unchanged (the same array) when this side pays the listed price, so
## an ordinary match allocates nothing here.
func scaled_costs(peer_id: int, costs: Array[ResourceCost]) -> Array[ResourceCost]:
	var multiplier := modifiers_for(peer_id).cost_multiplier
	if is_equal_approx(multiplier, 1.0):
		return costs
	var out: Array[ResourceCost] = []
	for cost in costs:
		var scaled := ResourceCost.new()
		scaled.resource_type = cost.resource_type
		scaled.amount = maxi(roundi(cost.amount * multiplier), 0)
		out.append(scaled)
	return out

func building_allowed(peer_id: int, building_name: String) -> bool:
	if (REALM_ONLY_BUILDINGS if not realm() else NOT_IN_REALM_BUILDINGS).has(building_name):
		return false
	var allowed := modifiers_for(peer_id).allowed_buildings
	return allowed.is_empty() or allowed.has(building_name)

func item_allowed(peer_id: int, item_name: String) -> bool:
	var allowed := modifiers_for(peer_id).allowed_items
	return allowed.is_empty() or allowed.has(item_name)

## Map-wide rather than per player: a Shrine rolls its offer once for the whole
## match, before anyone owns it.
func monster_allowed(item_name: String) -> bool:
	var allowed := _default.allowed_monsters
	return allowed.is_empty() or allowed.has(item_name)

func research_allowed(peer_id: int, node: ResearchNode) -> bool:
	var cap := modifiers_for(peer_id).research_tier_cap
	return cap < 0 or (cap > 0 and node.tier <= cap)

## 0 = the ordinary houses-and-town-centre rules. Realm has no cap to build
## towards, only a ceiling that keeps a runaway economy playable.
func population_cap(peer_id: int) -> int:
	var fixed: int = modifiers_for(peer_id).population_cap
	if fixed == 0 and realm():
		return REALM_POPULATION_CEILING
	return fixed

## Whether a part of the HUD is available to this player — "research", "build",
## "formations", "control_groups". A tutorial locks them and unlocks them as it
## teaches them; everywhere else they are always available.
func hud_allowed(peer_id: int, feature: String) -> bool:
	return not modifiers_for(peer_id).locked_hud.has(feature)

## Whether Favour is scored at all. Outside a scenario this follows the lobby's
## game mode, which Main asks about separately.
func favour_enabled() -> bool:
	return scenario == null or scenario.favour_enabled
