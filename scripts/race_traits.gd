class_name RaceTraits
extends Node
## What makes each people fight like itself: a trait every unit of theirs is
## born with, and the upgrades their own military buildings research.
##
## A unit's people and kind (RealmRoster.Kind: infantry, ranged, cavalry,
## caster, beast) are read off its scene through RealmRoster, so a Gnoll
## Archer is ranged Gnolls whichever settlement trained it.
## An upgrade is a plain UPGRADE item whose unlock tag (UnitUnlocks) is its id:
## that makes it one purchase per player, broadcast to every peer, and hidden
## from every building once owned. Every peer writes its effects onto the
## units it has, the way Research writes its nodes; the host alone reads the
## combat ones.
##
## Traits:
##   Human           Drilled: military units in a block take 10% less damage.
##   Gnolls          Pack Courage and litters (see Unit.pack_member).
##   Dark Elves      Cruelty: +25% damage against enemies below half health.
##   Star Wanderers  Starlit: up to 2 armour as night falls.
##   Beastmen        Bloodrage: up to +40% attack speed as they lose health.

## An upgrade offered at every one of its people's military buildings and
## applying to all of their units.
const EVERY_KIND: int = -1
## A Human Blacksmith line (Unit.UnitCategory-wide, through UnitUpgrades).
const SMITHY: int = -2

const HUMAN_BLOCK_GUARD: float = 0.1
const DARK_ELF_CRUELTY: float = 0.25
## Below this fraction of its max health a target counts as wounded (Cruelty),
## and a Gnoll counts as frenzied (Blood Frenzy).
const WOUNDED_FRACTION: float = 0.5
const STAR_NIGHT_ARMOR: int = 2
const BEASTMEN_BLOODRAGE: float = 0.4

## How close an enemy's death has to be for Carrion Feast.
const CARRION_RADIUS: float = 7.0
## How far a Comet Arrow's burst reaches from the unit it hits.
const SPLASH_RADIUS: float = 2.5

const UnitGrid = preload("res://scripts/unit_grid.gd")
const WOOD: ResourceType = preload("res://resources/wood_resource_type.tres")
const GOLD: ResourceType = preload("res://resources/gold_resource_type.tres")

## Effects an upgrade can carry (key -> amount):
##   health, speed, vision, damage, attack_speed, aura: fractions
##   range: metres (ranged units only)   armor: points
##   extra_bodies: one more body in each litter
##   carrion_heal: health per enemy death nearby   regen: health a second out of combat
##   frenzy: attack speed while below WOUNDED_FRACTION   bloodrage: more Bloodrage
##   lifesteal: of damage dealt   cruelty: more Cruelty   splash: of a shot's damage
##   bleed / slow / venom: an on-hit effect (for units with none of their own)
##   pack_radius / pack_max: Pack Courage reach (fraction) and peak (added)
##   night_always: Starlit by day too   charge_damage: fraction   charge_heal: health
##   fast_brace: spears counter charging cavalry harder
##   pierce_guard: less damage from arrows and bolts while in a block
##   grant_aura: a healing aura of this much for units without one
##   building_damage: added to the building damage multiplier
##   smith: [Unit.UnitCategory, weapon points, armour points] (host, UnitUpgrades)
const UPGRADES: Array[Dictionary] = [
	# --- Human ---
	{id = &"hum_shield_wall", race = "Human", at = RealmRoster.Kind.BARRACKS, name = "Shield Wall",
		text = "Infantry standing in a block take 25% less damage from arrows and bolts.",
		wood = 120, gold = 100, time = 35.0, effects = {pierce_guard = 0.25}},
	{id = &"hum_pike_drill", race = "Human", at = RealmRoster.Kind.BARRACKS, name = "Pike Drill",
		text = "Spearmen and Halberdiers hit charging cavalry harder.",
		wood = 80, gold = 120, time = 35.0, effects = {fast_brace = 1}},
	{id = &"hum_bodkin", race = "Human", at = RealmRoster.Kind.RANGE, name = "Bodkin Points",
		text = "Archers and Crossbowmen shoot 3 m further.",
		wood = 100, gold = 80, time = 30.0, effects = {range = 3.0}},
	{id = &"hum_volley", race = "Human", at = RealmRoster.Kind.RANGE, name = "Volley Drill",
		text = "Archers and Crossbowmen shoot 15% faster.",
		wood = 60, gold = 140, time = 35.0, effects = {attack_speed = 0.15}},
	{id = &"hum_barding", race = "Human", at = RealmRoster.Kind.STABLES, name = "Barding",
		text = "Horsemen and Cavaliers gain 20% health.",
		wood = 100, gold = 120, time = 35.0, effects = {health = 0.2}},
	{id = &"hum_couched_lances", race = "Human", at = RealmRoster.Kind.STABLES, name = "Couched Lances",
		text = "Cavalry charges hit 50% harder.",
		wood = 60, gold = 150, time = 40.0, effects = {charge_damage = 0.5}},
	{id = &"hum_battle_magic", race = "Human", at = RealmRoster.Kind.SANCTUM, name = "Battle Magic",
		text = "Wizards and Arch Mages deal 20% more damage.",
		wood = 80, gold = 160, time = 40.0, effects = {damage = 0.2}},
	{id = &"hum_royal_aerie", race = "Human", at = RealmRoster.Kind.BESTIARY, name = "Royal Aerie",
		text = "Griffins and Manticores gain 15% health and speed.",
		wood = 150, gold = 200, time = 50.0, effects = {health = 0.15, speed = 0.15}},
	{id = &"smith_archer_1", race = "Human", at = SMITHY, name = "Archer Gear I",
		text = "Archers gain 1 damage and 1 armour.",
		wood = 0, gold = 100, time = 20.0, effects = {smith = [Unit.UnitCategory.ARCHER, 1, 1]}},
	{id = &"smith_archer_2", race = "Human", at = SMITHY, name = "Archer Gear II", requires = &"smith_archer_1",
		text = "Archers gain another 1 damage and 1 armour.",
		wood = 0, gold = 200, time = 25.0, effects = {smith = [Unit.UnitCategory.ARCHER, 1, 1]}},
	{id = &"smith_archer_3", race = "Human", at = SMITHY, name = "Archer Gear III", requires = &"smith_archer_2",
		text = "Archers gain another 1 damage and 1 armour.",
		wood = 0, gold = 300, time = 30.0, effects = {smith = [Unit.UnitCategory.ARCHER, 1, 1]}},
	{id = &"smith_cavalry_1", race = "Human", at = SMITHY, name = "Cavalry Gear I",
		text = "Cavalry gain 1 damage and 1 armour.",
		wood = 0, gold = 120, time = 20.0, effects = {smith = [Unit.UnitCategory.CAVALRY, 1, 1]}},
	{id = &"smith_cavalry_2", race = "Human", at = SMITHY, name = "Cavalry Gear II", requires = &"smith_cavalry_1",
		text = "Cavalry gain another 1 damage and 1 armour.",
		wood = 0, gold = 220, time = 25.0, effects = {smith = [Unit.UnitCategory.CAVALRY, 1, 1]}},
	{id = &"smith_cavalry_3", race = "Human", at = SMITHY, name = "Cavalry Gear III", requires = &"smith_cavalry_2",
		text = "Cavalry gain another 1 damage and 1 armour.",
		wood = 0, gold = 320, time = 30.0, effects = {smith = [Unit.UnitCategory.CAVALRY, 1, 1]}},

	# --- Gnolls ---
	{id = &"gnl_carrion_feast", race = "Gnolls", at = EVERY_KIND, name = "Carrion Feast",
		text = "Gnolls heal 6 health whenever an enemy dies near them.",
		wood = 80, gold = 60, time = 30.0, effects = {carrion_heal = 6}},
	{id = &"gnl_bigger_litters", race = "Gnolls", at = RealmRoster.Kind.BARRACKS, name = "Bigger Litters",
		text = "Every litter trained here brings one more gnoll, if there is room for it.",
		wood = 150, gold = 100, time = 45.0, effects = {extra_bodies = 1}},
	{id = &"gnl_blood_frenzy", race = "Gnolls", at = RealmRoster.Kind.BARRACKS, name = "Blood Frenzy",
		text = "Gnoll infantry attack 30% faster below half health.",
		wood = 60, gold = 80, time = 30.0, effects = {frenzy = 0.3}},
	{id = &"gnl_barbed_arrows", race = "Gnolls", at = RealmRoster.Kind.RANGE, name = "Barbed Arrows",
		text = "Gnoll arrows make their target bleed for 2 damage a second.",
		wood = 70, gold = 70, time = 30.0, effects = {bleed = 1}},
	{id = &"gnl_hamstring", race = "Gnolls", at = RealmRoster.Kind.STABLES, name = "Hamstring",
		text = "Hyena bites slow their prey by 35% for 2 seconds.",
		wood = 60, gold = 80, time = 30.0, effects = {slow = 1}},
	{id = &"gnl_war_drums", race = "Gnolls", at = RealmRoster.Kind.SANCTUM, name = "War Drums",
		text = "Pack Courage reaches 50% further and peaks at +60% damage.",
		wood = 100, gold = 120, time = 40.0, effects = {pack_radius = 0.5, pack_max = 0.2}},
	{id = &"gnl_bone_plating", race = "Gnolls", at = RealmRoster.Kind.BESTIARY, name = "Bone Plating",
		text = "Sand Worms and Skeleton Dragons gain 2 armour.",
		wood = 150, gold = 180, time = 50.0, effects = {armor = 2}},

	# --- Dark Elves ---
	{id = &"de_blood_drinkers", race = "Dark Elves", at = EVERY_KIND, name = "Blood Drinkers",
		text = "Dark Elves heal for 20% of the damage they deal.",
		wood = 80, gold = 150, time = 40.0, effects = {lifesteal = 0.2}},
	{id = &"de_envenomed_blades", race = "Dark Elves", at = RealmRoster.Kind.BARRACKS, name = "Envenomed Blades",
		text = "Dark Elf Warriors and Guards poison whatever they strike.",
		wood = 60, gold = 110, time = 35.0, effects = {venom = 1}},
	{id = &"de_exquisite_cruelty", race = "Dark Elves", at = RealmRoster.Kind.BARRACKS, name = "Exquisite Cruelty",
		text = "Cruelty's bonus against wounded enemies rises to 50%.",
		wood = 50, gold = 140, time = 40.0, effects = {cruelty = 0.25}},
	{id = &"de_nightshade_bows", race = "Dark Elves", at = RealmRoster.Kind.RANGE, name = "Nightshade Bows",
		text = "Dark Elf Archers shoot 3 m further.",
		wood = 80, gold = 90, time = 30.0, effects = {range = 3.0}},
	{id = &"de_shadow_steeds", race = "Dark Elves", at = RealmRoster.Kind.STABLES, name = "Shadow Steeds",
		text = "Dark Elf Riders ride 15% faster and poison what they strike.",
		wood = 80, gold = 120, time = 35.0, effects = {speed = 0.15, venom = 1}},
	{id = &"de_soulfire", race = "Dark Elves", at = RealmRoster.Kind.SANCTUM, name = "Soulfire",
		text = "Sorceresses and Spellstealers deal 25% more damage.",
		wood = 60, gold = 170, time = 40.0, effects = {damage = 0.25}},
	{id = &"de_spirit_bond", race = "Dark Elves", at = RealmRoster.Kind.BESTIARY, name = "Spirit Bond",
		text = "Kitsune and Wind Tigers move 20% faster.",
		wood = 140, gold = 180, time = 45.0, effects = {speed = 0.2}},

	# --- Star Wanderers ---
	{id = &"sw_starlight_mending", race = "Star Wanderers", at = EVERY_KIND, name = "Starlight Mending",
		text = "Star Wanderers regenerate 2 health a second out of combat.",
		wood = 100, gold = 140, time = 40.0, effects = {regen = 2.0}},
	{id = &"sw_celestial_plate", race = "Star Wanderers", at = RealmRoster.Kind.BARRACKS, name = "Celestial Plate",
		text = "Star Wanderer infantry gain 2 armour.",
		wood = 100, gold = 150, time = 40.0, effects = {armor = 2}},
	{id = &"sw_eternal_vigil", race = "Star Wanderers", at = RealmRoster.Kind.BARRACKS, name = "Eternal Vigil",
		text = "Starlit armour holds at full strength by day as well as by night.",
		wood = 80, gold = 180, time = 45.0, effects = {night_always = 1}},
	{id = &"sw_comet_arrows", race = "Star Wanderers", at = RealmRoster.Kind.RANGE, name = "Comet Arrows",
		text = "Star Hunter shots burst on impact, hitting enemies around the target for half damage.",
		wood = 90, gold = 150, time = 40.0, effects = {splash = 0.5}},
	{id = &"sw_astral_charge", race = "Star Wanderers", at = RealmRoster.Kind.STABLES, name = "Astral Charge",
		text = "Star Wanderer cavalry heal 15 health each time they land a charge.",
		wood = 80, gold = 130, time = 35.0, effects = {charge_heal = 15}},
	{id = &"sw_radiance", race = "Star Wanderers", at = RealmRoster.Kind.SANCTUM, name = "Radiance",
		text = "The Priestess's healing aura is 50% stronger and reaches 50% further.",
		wood = 90, gold = 150, time = 40.0, effects = {aura = 0.5}},
	{id = &"sw_storm_scales", race = "Star Wanderers", at = RealmRoster.Kind.BESTIARY, name = "Storm Scales",
		text = "Dragons and Lightning Dragons gain 2 armour.",
		wood = 150, gold = 200, time = 50.0, effects = {armor = 2}},

	# --- Beastmen ---
	{id = &"bm_regrowth", race = "Beastmen", at = EVERY_KIND, name = "Regrowth",
		text = "Beastmen regenerate 1 health a second out of combat.",
		wood = 90, gold = 60, time = 30.0, effects = {regen = 1.0}},
	{id = &"bm_thick_hides", race = "Beastmen", at = RealmRoster.Kind.BARRACKS, name = "Thick Hides",
		text = "Beastman Warriors and Panda Warriors gain 20% health.",
		wood = 100, gold = 80, time = 35.0, effects = {health = 0.2}},
	{id = &"bm_primal_fury", race = "Beastmen", at = RealmRoster.Kind.BARRACKS, name = "Primal Fury",
		text = "Bloodrage climbs to +80% attack speed.",
		wood = 60, gold = 120, time = 40.0, effects = {bloodrage = 0.4}},
	{id = &"bm_trackers", race = "Beastmen", at = RealmRoster.Kind.RANGE, name = "Trackers",
		text = "Wolf Pathfinders see 25% further and shoot 3 m further.",
		wood = 80, gold = 70, time = 30.0, effects = {range = 3.0, vision = 0.25}},
	{id = &"bm_torch_riders", race = "Beastmen", at = RealmRoster.Kind.STABLES, name = "Torch Riders",
		text = "Beastman Raiders deal double damage to buildings.",
		wood = 70, gold = 90, time = 30.0, effects = {building_damage = 1.0}},
	{id = &"bm_wild_growth", race = "Beastmen", at = RealmRoster.Kind.SANCTUM, name = "Wild Growth",
		text = "Beastman Druids heal nearby allies for 3 health every 3 seconds.",
		wood = 80, gold = 110, time = 35.0, effects = {grant_aura = 3}},
]

## On-hit effects an upgrade can hand a unit with none of its own.
static var _on_hits: Dictionary = {}

static func _on_hit(effect: StringName) -> Ability:
	if _on_hits.has(effect):
		return _on_hits[effect]
	var ability := Ability.new()
	ability.kind = Ability.Kind.ACTIVATED_AREA
	match effect:
		&"bleed":
			ability.ability_name = "Bleed"
			ability.dot_damage_per_second = 2
			ability.dot_duration = 3.0
			ability.effect_color = Color(0.85, 0.2, 0.2)
		&"slow":
			ability.ability_name = "Hamstring"
			ability.slow_fraction = 0.35
			ability.slow_duration = 2.0
			ability.effect_color = Color(0.75, 0.6, 0.35)
		_:
			ability.ability_name = "Venom"
			ability.dot_damage_per_second = 2
			ability.dot_duration = 4.0
			ability.effect_color = Color(0.45, 0.85, 0.35)
	ability.icon = UiStyle.icon_art("abilities", ability.ability_name.to_lower())
	_on_hits[effect] = ability
	return ability

## --- Lookups ---

static var _by_id: Dictionary = {}

static func upgrade(id: StringName) -> Dictionary:
	if _by_id.is_empty():
		for entry in UPGRADES:
			_by_id[entry.id] = entry
	return _by_id.get(id, {})

static func is_upgrade(tag: StringName) -> bool:
	return not upgrade(tag).is_empty()

## Scene path -> [race, RealmRoster.Kind] for every unit a people trains.
static var _unit_info: Dictionary = {}
## Scene path -> race for each people's own buildings.
static var _building_race: Dictionary = {}

static func _index() -> void:
	if not _unit_info.is_empty():
		return
	for race in RealmRoster.RACES:
		var entry: Dictionary = RealmRoster.RACES[race]
		for kind in (entry.units as Array).size():
			for unit in entry.units[kind]:
				_unit_info[unit[0]] = [race, kind]
		for scene in entry.scenes:
			if not (scene as String).is_empty():
				_building_race[scene] = race

## [race, kind] for a unit scene. A Human unit no settlement trains (the
## Shieldman, the Officer) goes by its category; anything not of a people
## (monsters, animals, siege) is ["", -1].
static func unit_info(scene_path: String, category: int = Unit.UnitCategory.NONE) -> Array:
	_index()
	if _unit_info.has(scene_path):
		return _unit_info[scene_path]
	if scene_path.get_base_dir() != "res://scenes/units" or scene_path.get_file().begins_with("beastman_"):
		return ["", -1]
	match category:
		Unit.UnitCategory.INFANTRY:
			return ["Human", RealmRoster.Kind.BARRACKS]
		Unit.UnitCategory.ARCHER:
			return ["Human", RealmRoster.Kind.RANGE]
		Unit.UnitCategory.CAVALRY:
			return ["Human", RealmRoster.Kind.STABLES]
	return ["Human", -1]

## Whose people a building belongs to: a settlement's slot building says so
## itself; a people's own scene (a Gnoll Den, a Dark Spire) is theirs wherever
## it stands; anything else is Human.
static func building_race(building: ProductionBuilding) -> String:
	if not building.slot_race.is_empty():
		return building.slot_race
	_index()
	return _building_race.get(building.scene_file_path, "Human")

## --- Building menus ---

## Every peer: `building`'s menu with its people's upgrades for the kinds of
## unit it trains, placed before any level-ups. Idempotent — the upgrades from
## an earlier call are dropped first — so it can run again whenever the menu
## is rebuilt (a slot building's level-up).
static func offer_upgrades(building: ProductionBuilding) -> void:
	var kept: Array[ProducibleItem] = []
	var levels: Array[ProducibleItem] = []
	for item in building.producibles:
		if item.has_meta(&"race_upgrade"):
			continue
		if item.kind == ProducibleItem.Kind.LEVEL:
			levels.append(item)
		else:
			kept.append(item)
	var race := building_race(building)
	var kinds: Array[int] = []
	if building.slot_kind >= 0:
		kinds.append(building.slot_kind)
	else:
		for item in kept:
			if item.kind != ProducibleItem.Kind.UNIT or item.unit_scene == null:
				continue
			var info := unit_info(item.unit_scene.resource_path, _probe_category(item.unit_scene))
			if info[0] == race and info[1] >= 0 and not kinds.has(info[1]):
				kinds.append(info[1])
	var smithy: bool = building.building_name == "Blacksmith" and race == "Human"
	var offered: Array[ProducibleItem] = kept.duplicate()
	for entry in UPGRADES:
		if entry.race != race:
			continue
		var at: int = entry.at
		if (at == SMITHY and smithy) or (at == EVERY_KIND and not kinds.is_empty()) or (at >= 0 and kinds.has(at)):
			offered.append(_item(entry))
	offered.append_array(levels)
	building.producibles = offered

static var _categories: Dictionary = {}

static func _probe_category(scene: PackedScene) -> int:
	var path := scene.resource_path
	if not _categories.has(path):
		var probe := scene.instantiate()
		_categories[path] = probe.get(&"unit_category") if probe.get(&"unit_category") != null else Unit.UnitCategory.NONE
		probe.free()
	return _categories[path]

static func _item(entry: Dictionary) -> ProducibleItem:
	var item := ProducibleItem.new()
	item.item_name = entry.name
	item.description = entry.text
	item.kind = ProducibleItem.Kind.UPGRADE
	## The blacksmith's Gear I/II/III share one icon.
	var icon_name := String(entry.id)
	if icon_name.begins_with("smith_"):
		icon_name = icon_name.left(icon_name.rfind("_"))
	item.icon = UiStyle.icon_art("upgrades", icon_name)
	item.build_time = entry.time
	item.grants_unlock = entry.id
	item.requires_unlock = entry.get("requires", &"")
	var costs: Array[ResourceCost] = []
	for pair in [[WOOD, entry.wood], [GOLD, entry.gold]]:
		if int(pair[1]) > 0:
			var cost := ResourceCost.new()
			cost.resource_type = pair[0]
			cost.amount = int(pair[1])
			costs.append(cost)
	item.costs = costs
	item.set_meta(&"race_upgrade", true)
	return item

## Host: how many more bodies a litter of `item` brings for `peer_id`.
static func extra_bodies(peer_id: int, item: ProducibleItem) -> int:
	if item.spawn_count <= 1 or item.unit_scene == null:
		return 0
	var info := unit_info(item.unit_scene.resource_path)
	var extra := 0
	for entry in UPGRADES:
		if entry.race == info[0] and (entry.at == EVERY_KIND or entry.at == info[1]) \
				and entry.effects.has("extra_bodies") and UnitUnlocks.has(peer_id, entry.id):
			extra += int(entry.effects.extra_bodies)
	return extra

## --- Units ---

var main: Main

## 0 by day, 1 at full night — Starlit armour reads it on every blow, so it is
## kept here rather than looked up through the scene each time.
static var night: float = 0.0

const TICK_SECONDS: float = 1.0
var _tick: float = 0.0

func _ready() -> void:
	UnitUnlocks.granted.connect(_on_granted)

func _physics_process(delta: float) -> void:
	if main == null or main.day_night == null:
		return
	night = clampf(main.day_night.night_amount, 0.0, 1.0)
	if not multiplayer.is_server():
		return
	_tick += delta
	if _tick < TICK_SECONDS:
		return
	_tick -= TICK_SECONDS
	_tick_regeneration()

## Host: out of combat for Research's cooldown, and not swinging.
func _tick_regeneration() -> void:
	var now := GameClock.msec()
	for node in main.units_root.get_children():
		var unit := node as Unit
		if unit == null or unit.race_regen <= 0.0 or unit.status_activity == Unit.Activity.DEAD:
			continue
		if unit.status_current_health >= unit.max_health or unit.status_activity == Unit.Activity.ATTACKING \
				or now - unit.last_damaged_msec < Research.REGEN_COMBAT_COOLDOWN_MS:
			continue
		unit.heal(maxi(roundi(unit.race_regen * TICK_SECONDS), 1))

## Host: Carrion Feast — the victim's enemies close by feed on it.
func on_death(victim: Unit) -> void:
	for other in UnitGrid.enemies_near(get_tree(), victim.global_position, CARRION_RADIUS, victim.owner_peer_id):
		if other.race_carrion_heal > 0 and other.status_activity != Unit.Activity.DEAD \
				and other.global_position.distance_to(victim.global_position) <= CARRION_RADIUS:
			other.heal(other.race_carrion_heal)

## Every peer, as a unit spawns (after Unit._ready): its people's trait and
## every upgrade its owner already holds.
func apply_all_to(unit: Unit) -> void:
	var info := unit_info(unit.scene_file_path, unit.unit_category)
	unit.race_name = info[0]
	unit.race_kind = info[1]
	match unit.race_name:
		"Human":
			if unit.can_fight and not unit.can_gather:
				unit.race_block_guard = HUMAN_BLOCK_GUARD
		"Dark Elves":
			unit.race_wounded_bonus = DARK_ELF_CRUELTY
		"Star Wanderers":
			unit.race_night_armor = STAR_NIGHT_ARMOR
		"Beastmen":
			unit.race_bloodrage = BEASTMEN_BLOODRAGE
	for entry in UPGRADES:
		if UnitUnlocks.has(unit.owner_peer_id, entry.id):
			_apply_to(unit, entry)

func _on_granted(peer_id: int, tag: StringName) -> void:
	var entry := upgrade(tag)
	if entry.is_empty():
		return
	if entry.effects.has("smith") and multiplayer.is_server():
		var smith: Array = entry.effects.smith
		UnitUpgrades.add_bonus(peer_id, smith[0], UnitUpgrades.Stat.WEAPON, smith[1])
		UnitUpgrades.add_bonus(peer_id, smith[0], UnitUpgrades.Stat.ARMOR, smith[2])
	if main == null:
		return
	for node in main.units_root.get_children():
		if node is Unit and node.owner_peer_id == peer_id and node.status_activity != Unit.Activity.DEAD:
			_apply_to(node, entry)

const APPLIED_META: StringName = &"race_upgrades"

## Once per unit per upgrade, and only to the units it is for.
func _apply_to(unit: Unit, entry: Dictionary) -> void:
	if unit.race_name.is_empty() or entry.race != unit.race_name:
		return
	if entry.at != EVERY_KIND and entry.at != unit.race_kind:
		return
	var applied: Array = unit.get_meta(APPLIED_META, [])
	if applied.has(entry.id):
		return
	applied.append(entry.id)
	unit.set_meta(APPLIED_META, applied)
	var ranged: bool = unit.projectile_scene != null
	for key in entry.effects:
		var amount = entry.effects[key]
		match key:
			"health":
				var extra := roundi(unit.max_health * float(amount))
				unit.max_health += extra
				if multiplayer.is_server():
					unit.status_current_health += extra
			"speed":
				unit.move_speed *= 1.0 + float(amount)
			"vision":
				unit.vision_range *= 1.0 + float(amount)
			"range":
				if ranged:
					unit.attack_range += float(amount)
			"damage":
				unit.attack_damage = roundi(unit.attack_damage * (1.0 + float(amount)))
			"attack_speed":
				unit.attack_cooldown /= 1.0 + float(amount)
			"armor":
				unit.race_armor += int(amount)
			"carrion_heal":
				unit.race_carrion_heal += int(amount)
			"regen":
				unit.race_regen += float(amount)
			"frenzy":
				unit.race_frenzy += float(amount)
			"bloodrage":
				unit.race_bloodrage += float(amount)
			"lifesteal":
				unit.race_lifesteal += float(amount)
			"cruelty":
				unit.race_wounded_bonus += float(amount)
			"splash":
				if ranged:
					unit.race_splash += float(amount)
			"bleed", "slow", "venom":
				if unit.on_hit_ability == null:
					unit.race_on_hit = _on_hit(StringName(key))
			"pack_radius":
				unit.race_pack_radius += float(amount)
			"pack_max":
				unit.race_pack_max += float(amount)
			"night_always":
				unit.race_night_always = true
			"charge_damage":
				unit.race_charge_bonus += float(amount)
			"charge_heal":
				unit.race_charge_heal += int(amount)
			"fast_brace":
				unit.race_fast_brace = true
			"pierce_guard":
				unit.race_pierce_guard += float(amount)
			"aura":
				if unit.heal_aura_amount > 0:
					unit.heal_aura_amount = roundi(unit.heal_aura_amount * (1.0 + float(amount)))
					unit.heal_aura_radius *= 1.0 + float(amount)
			"grant_aura":
				if unit.heal_aura_amount <= 0:
					unit.heal_aura_amount = int(amount)
			"building_damage":
				unit.building_damage_multiplier += float(amount)
	## A sleeping unit (see Unit._maybe_sleep) has to be up to heal around it,
	## and the sim holds its own copy of range, vision and speed.
	unit.wake()
	if unit.sim_id >= 0 and ArmyBridge.current != null:
		ArmyBridge.current.refresh_unit_stats(unit)
