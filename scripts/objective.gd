extends Node3D
class_name Objective

## Conquest-style capture: every point has a "flag" that belongs to one player
## (flag_peer_id) and stands at some height (flag_control, 0-1). Taking an
## owned point is two stages — lower the owner's flag to 0 (the point goes
## neutral), then raise your own to 1 (it becomes yours) — each taking
## stage_duration seconds for a lone unit. See _physics_process for the
## head-count tug-of-war that decides which way the flag moves.

## Seconds one combat unit needs to lower a flag from full to empty, or raise
## one from empty to full. Extra units speed this up (see _capture_speed).
@export var stage_duration: float = 15.0
## Each combat unit beyond the first adds this much to the capture speed
## multiplier, up to max_capture_speed — so 1 unit = 1x, 2 = 1.5x, 3+ = 2x.
@export var capture_speed_per_extra_unit: float = 0.5
@export var max_capture_speed: float = 2.0
## Seconds a neutral point must sit completely empty (no units of any player
## in the zone, every guard dead) before its guard roster respawns.
@export var guard_respawn_delay: float = 45.0
## Fraction of max health respawned guards come back with — a retaken-then-
## abandoned point is meant to be cheaper to retake than the opening fight.
@export var guard_respawn_health: float = 0.5
## Guards wander about within this radius of the objective's origin; they'll
## break off a chase and return once dragged past
## wander_radius * LEASH_MULTIPLIER (see Unit.leash_radius).
@export var wander_radius: float = 4.0
## Favour per second credited to whoever currently holds this objective.
## Favour is the Conquest score — first to the target wins — and is never
## spent. The map's centre point is set to pay double (see MapGenerator's
## centre_favour_per_second). Held means owned, not occupied: an empty point
## keeps paying until someone takes it — but not while it's contested or
## being drained (see _paying).
@export var favour_per_second: float = 1.0
## Gold per second credited to the holder on exactly the same terms as Favour
## (not while contested or draining, not to an eliminated or disconnected
## owner) — but in every game mode, since unlike Favour it's ordinary money.
## Keeps armies fed once the map's gold deposits have been mined out.
@export var gold_per_second: float = 1.0
## Wood per second, on exactly the same terms as gold. Wood is the scarcer
## resource (villagers and every building cost it), so a point pays both
## rather than all gold.
@export var wood_per_second: float = 1.0
## Which people live here, for a Realm settlement: decides what its hall can put
## in its slots (see _slot_options) and any race quirk (Star Wanderers pay more
## at night).
@export var race_name: String = ""

const LEASH_MULTIPLIER: float = 2.5

## --- Settlement (Realm) ---
## In a Realm match (MatchRules.realm) a point is a settlement: it grows from
## Village to Town to City while its owner holds it in peace, more cottages go
## up around it as it does, it pays more (and food) at each tier, and it keeps a
## garrison of its own race that regrows after a fight. A Shrine stays a
## Shrine. Outside Realm none of this runs and a point is a plain capture point.
enum Tier { VILLAGE, TOWN, CITY }
## Raising a settlement is bought at its hall (see _offer_slots): what Town and
## City cost, and how long the work takes.
const TIER_UPGRADE_WOOD: Array[int] = [0, 200, 400]
const TIER_UPGRADE_GOLD: Array[int] = [0, 150, 300]
const TIER_UPGRADE_SECONDS: Array[float] = [0.0, 45.0, 60.0]
const TIER_NAMES: Array[String] = ["Village", "Town", "City"]
## How often a settlement shows its owner what it has paid them.
const INCOME_POPUP_SECONDS: float = 5.0
const TIER_INCOME: Array[float] = [1.0, 1.5, 2.0]
const TIER_FOOD_PER_SECOND: Array[float] = [0.5, 0.8, 1.2]
const TIER_HOUSES: Array[int] = [3, 6, 10]
## The owner's garrison at each tier; a neutral settlement starts with
## NEUTRAL_GARRISON guards (the scene's own plus copies of them).
const TIER_GARRISON: Array[int] = [3, 6, 9]
const NEUTRAL_GARRISON: int = 6
const GARRISON_REGEN_SECONDS: float = 20.0
## Cottages stand in a ring outside the capture zone and inside the clearing
## the map generator levels for a settlement.
const HOUSE_RING := Vector2(8.5, 11.0)
const HOUSE_SLOTS: int = 10
const HOUSE_WALLS := Color(0.8, 0.72, 0.58)
const FOOD_RESOURCE: ResourceType = preload("res://resources/food_resource_type.tres")
## A settlement claims ground up to this far, nearest settlement or Town
## Centre first (see territory_owner).
const TERRITORY_REACH: float = 70.0

var tier: int = Tier.VILLAGE
## Host only: income paid since the last popup, by resource.
var _income_shown: Dictionary = {}
var _income_timer: float = 0.0
## Host only: the owner's garrison units (untyped, as _guards).
var _garrison: Array = []
var _garrison_timer: float = 0.0
var _houses: Array[Node3D] = []
var _house_owner_tint: Color = Color.TRANSPARENT
static var _house_mesh_body: BoxMesh = null
static var _house_mesh_roof: PrismMesh = null
static var _house_materials: Dictionary = {}
const NEUTRAL_TINT: Color = Color(0.5, 0.5, 0.5)
## Above the Favour "+N" popups (WorldFeedback.FAVOUR_POPUP_HEIGHT).
const LETTER_HEIGHT: float = 5.5
## ResourceStockpile totals are ints, so fractional income accumulates here
## and is banked a whole point at a time (see _tick_favour/_tick_gold).
const FAVOUR_RESOURCE: ResourceType = preload("res://resources/favour_resource_type.tres")
const GOLD_RESOURCE: ResourceType = preload("res://resources/gold_resource_type.tres")
const WOOD_RESOURCE: ResourceType = preload("res://resources/wood_resource_type.tres")

@onready var capture_zone: Area3D = $CaptureZone
@onready var guards: Node3D = $Guards
@onready var buildings: Node3D = $Buildings
@onready var progress_disc: MeshInstance3D = $ProgressDisc

## 0 = neutral/AI-controlled, same convention as Gatherable.owner_peer_id.
var owner_peer_id: int = 0
## Whose flag is on the pole (0 = nobody's) and how high it stands. Always
## the owner's while owned; on a neutral point, whoever last started raising.
var flag_peer_id: int = 0
var flag_control: float = 0.0
## True while opposing players' units cancel each other out on the point —
## the flag is frozen and nobody is paid. Synced for the HUD.
var contested: bool = false
## "A", "B", ... — see set_letter.
var letter: String = ""
var _letter_label: Label3D = null
## Host-only remainder of Favour earned but not yet whole enough to bank.
var _favour_fraction: float = 0.0
## Host-only: false while the point is contested or being drained.
var _paying: bool = true
## Guards already passed to main for signal wiring — see register_guard.
var _registered_guards: Array[Unit] = []
## Host-only: every guard currently belonging to this point, hand-placed or
## respawned. A neutral point can't be taken while any of them lives.
## Untyped on purpose: dead guards are freed, and reading a freed entry out of
## a typed Array[Unit] errors before is_instance_valid() can reject it.
var _guards: Array = []
## Host-only: {scene_path, position (local)} per guard at match start — what
## a respawn recreates.
var _guard_roster: Array[Dictionary] = []
var _empty_neutral_time: float = 0.0

## owner_peer_id/team_tint are set here AND baked directly into every Guard/
## Building instance in the .tscn itself (not just here) — Godot readies a
## scene bottom-up in sibling declaration order, so if FogOfWar happens to be
## declared before this Objective under Main, FogOfWar._ready() computes its
## one-time initial "explored" stamp before this function ever runs, seeing
## each guard's still-uncorrected scene-file default (owner_peer_id 1, same
## as the real host) and permanently marking the objective as explored on
## sight. Setting it here alone only fixes every frame AFTER that first one —
## the .tscn defaults are what actually prevent the bad stamp from ever
## happening. Keep both in sync if this ever changes.
func _ready() -> void:
	## Main sizes the Conquest Favour target off how many of these there are.
	add_to_group(&"objectives")
	progress_disc.visible = false
	## Only its shape is read (see _units_in_zone): it has nothing to overlap.
	capture_zone.monitoring = false
	## Every instance of an objective scene shares the one ShaderMaterial
	## sub-resource, so without a private copy two points being captured at
	## once would fight over a single fill/colour.
	var mat := progress_disc.get_active_material(0)
	if mat:
		progress_disc.set_surface_override_material(0, mat.duplicate())
	var main := get_tree().current_scene
	for building in buildings.get_children():
		if building is ProductionBuilding:
			## On every peer, not just the host — see ProductionBuilding.is_invulnerable.
			building.is_invulnerable = true
			if main.has_method("register_objective_building"):
				main.register_objective_building(building)
	## Before the is_server() gate, same as the buildings above: the damage
	## numbers this wires up are spawned on every peer, not just the host.
	for guard in $Guards.get_children():
		if guard is Unit:
			register_guard(guard)
	for building in buildings.get_children():
		if building is ProductionBuilding:
			building.settlement = self
			if hall == null:
				hall = building
	if is_settlement():
		_show_houses()
		_offer_slots()
	if not multiplayer.is_server():
		return
	for guard in guards.get_children():
		var unit: Unit = guard
		_guard_roster.append({scene_path = unit.scene_file_path, position = unit.position})
		_setup_guard(unit)
	for building in buildings.get_children():
		building.owner_peer_id = 0
	if is_settlement():
		_grow_neutral_garrison.call_deferred()

## Idempotent, because a ShrineObjective's guard does not exist at a fixed
## point in the lifecycle: the host adds it before _ready (so the loop above
## catches it), while a client adds it later from the host's reply (so
## _apply_monsters has to call this itself). Whichever runs second is a no-op.
## Only for guards that live in the scene itself — respawned guards come
## through main's UnitSpawner, which already wires their signals.
func register_guard(unit: Unit) -> void:
	if _registered_guards.has(unit):
		return
	_registered_guards.append(unit)
	var main := get_tree().current_scene
	if main.has_method("register_objective_unit"):
		main.register_objective_unit(unit)

## Host only.
func _setup_guard(unit: Unit) -> void:
	unit.owner_peer_id = 0
	unit.team_tint = NEUTRAL_TINT
	unit.leash_origin = self
	unit.leash_radius = wander_radius * LEASH_MULTIPLIER
	unit.command_wander(self, wander_radius)
	_guards.append(unit)

func _any_guard_alive() -> bool:
	for unit in _guards:
		if is_instance_valid(unit) and unit.status_activity != Unit.Activity.DEAD:
			return true
	return false

## Workers don't take ground — only units that can't gather count.
static func _counts_for_capture(unit: Unit) -> bool:
	return unit.can_fight and not unit.can_gather

func _capture_speed(unit_count: int) -> float:
	return minf(1.0 + (unit_count - 1) * capture_speed_per_extra_unit, max_capture_speed)

## Everyone standing in the capture zone: its sphere, flat, asked of the sim
## (units have no physics body for the Area3D to overlap).
func _units_in_zone() -> Array[Unit]:
	if ArmyBridge.current == null:
		return []
	var shape := capture_zone.get_child(0) as CollisionShape3D
	var sphere := shape.shape as SphereShape3D if shape != null else null
	if sphere == null:
		return []
	return ArmyBridge.current.units_in_circle(shape.global_position, sphere.radius)

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	## Combat-unit head count per TEAM standing in the zone — allies push the
	## same flag together instead of cancelling each other out as two rival
	## challengers. Neutral guards (peer 0) aren't a player; they block capture
	## outright instead. A point is still owned by a player (whose colour it
	## flies), so team_rep remembers which one raised each team's flag.
	var counts: Dictionary = {}
	var team_rep: Dictionary = {}
	var anyone_present := false
	for body in _units_in_zone():
		if not (body is Unit) or body.status_activity == Unit.Activity.DEAD or body.owner_peer_id <= 0:
			continue
		anyone_present = true
		if _counts_for_capture(body):
			var team: int = Teams.team_of(body.owner_peer_id)
			counts[team] = counts.get(team, 0) + 1
			if not team_rep.has(team):
				team_rep[team] = body.owner_peer_id

	## Freshly razed ruins: nobody can raise a flag on them until the ruin time
	## is up and the old garrison has come back (see RUIN_SECONDS).
	if _ruin_left > 0.0:
		_ruin_left -= delta
		flag_peer_id = 0
		flag_control = 0.0
		contested = false
		if _ruin_left <= 0.0:
			_respawn_guards()
		return

	_tick_guard_respawn(delta, anyone_present)

	contested = false
	_paying = true
	if owner_peer_id == 0 and _any_guard_alive():
		flag_peer_id = 0
		flag_control = 0.0
		return

	var step := delta / stage_duration
	## Everything below works in teams; only the flag itself names a player.
	var flag_team: int = Teams.team_of(flag_peer_id)
	var holder_count: int = counts.get(flag_team, 0) if flag_peer_id > 0 else 0
	var challengers: Array = counts.keys().filter(func(t): return t != flag_team)

	if challengers.is_empty():
		if holder_count > 0:
			_raise(step * _capture_speed(holder_count))
		elif owner_peer_id > 0:
			## Nobody here: an owner's half-lowered flag creeps back up.
			_raise(step)
		else:
			## ...and a half-raised flag on a neutral point sinks back down.
			_lower(step)
	elif challengers.size() == 2 and flag_peer_id == 0 and counts[challengers[0]] != counts[challengers[1]]:
		## Two players meeting at a bare pole: the bigger side starts raising,
		## after which the ordinary holder-vs-challenger tug-of-war takes over.
		var a: int = counts[challengers[0]]
		var b: int = counts[challengers[1]]
		flag_peer_id = team_rep[challengers[0] if a > b else challengers[1]]
		_raise(step * _capture_speed(absi(a - b)))
	elif challengers.size() > 1:
		contested = true
		_paying = false
	elif flag_peer_id == 0:
		## A bare pole: the lone team present starts raising its flag.
		flag_peer_id = team_rep[challengers[0]]
		_raise(step * _capture_speed(counts[challengers[0]]))
	else:
		var net: int = counts[challengers[0]] - holder_count
		if net > 0:
			_paying = false
			_lower(step * _capture_speed(net))
		elif net == 0:
			contested = true
			_paying = false
		else:
			_raise(step * _capture_speed(-net))

	_tick_favour(delta)
	if is_settlement():
		_tick_settlement(delta)

func _raise(amount: float) -> void:
	flag_control = minf(flag_control + amount, 1.0)
	## An ally standing on a teammate's point helps hold it; it never changes
	## hands within a team (is_friendly is false for a neutral point, so those
	## are still taken normally).
	if flag_control >= 1.0 and owner_peer_id != flag_peer_id \
			and not Teams.is_friendly(owner_peer_id, flag_peer_id):
		_set_owner(flag_peer_id)

func _lower(amount: float) -> void:
	flag_control = maxf(flag_control - amount, 0.0)
	if flag_control > 0.0:
		return
	flag_peer_id = 0
	if owner_peer_id != 0:
		_set_owner(0)

## Counts toward the respawn timer only while the point is neutral, every
## guard is dead, and nobody at all (workers included) is standing on it.
func _tick_guard_respawn(delta: float, anyone_present: bool) -> void:
	if owner_peer_id != 0 or anyone_present or _guard_roster.is_empty() or _any_guard_alive():
		_empty_neutral_time = 0.0
		return
	_empty_neutral_time += delta
	if _empty_neutral_time >= guard_respawn_delay:
		_empty_neutral_time = 0.0
		_respawn_guards()

## Host only. Through main's UnitSpawner so every client gets the unit too —
## unlike the originals, these don't exist in the scene file.
func _respawn_guards() -> void:
	var main := get_tree().current_scene
	if not ("unit_spawner" in main):
		return
	_guards = _guards.filter(func(u): return is_instance_valid(u) and u.status_activity != Unit.Activity.DEAD)
	flag_peer_id = 0
	flag_control = 0.0
	for entry in _guard_roster:
		var unit: Unit = main.unit_spawner.spawn({
			"scene_path": entry.scene_path,
			"peer_id": 0,
			"tint": NEUTRAL_TINT,
			"position": to_global(entry.position),
		})
		unit.status_current_health = maxi(1, int(unit.max_health * guard_respawn_health))
		_setup_guard(unit)

## At rest: a fully-raised flag on an owned point, or a bare pole on a
## neutral one — nothing in progress worth drawing.
func is_flag_at_rest() -> bool:
	return flag_control <= 0.0 or (owner_peer_id > 0 and flag_control >= 1.0)

## The owner's colour, read off the point's own (synced) buildings rather than
## Main.get_team_tint, which only knows a disconnected player's colour on the
## host.
func owner_tint() -> Color:
	if owner_peer_id <= 0:
		return NEUTRAL_TINT
	for building in buildings.get_children():
		if building is ProductionBuilding:
			return building.team_tint
	return NEUTRAL_TINT

func flag_tint() -> Color:
	if flag_peer_id <= 0:
		return NEUTRAL_TINT
	if flag_peer_id == owner_peer_id:
		return owner_tint()
	var main := get_tree().current_scene
	return main.get_team_tint(flag_peer_id) if main.has_method("get_team_tint") else NEUTRAL_TINT

## Set once by Main (see Main._assign_objective_letters) — the same letter on
## every peer. Floats above the point in its owner's colour.
func set_letter(value: String) -> void:
	letter = value
	if _letter_label == null:
		_letter_label = Label3D.new()
		_letter_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		## Label3D isn't a Control, so it doesn't pick up the project theme's
		## font by itself — same medieval face as the rest of the UI.
		var theme := ThemeDB.get_project_theme()
		if theme != null and theme.default_font != null:
			_letter_label.font = theme.default_font
		_letter_label.font_size = 128
		_letter_label.outline_size = 32
		_letter_label.pixel_size = 0.012
		_letter_label.position = Vector3(0.0, LETTER_HEIGHT, 0.0)
		## Hidden until explored, like the point's buildings.
		_letter_label.add_to_group(&"fog_static_props")
		add_child(_letter_label)
	_letter_label.text = value

## Runs on every peer (flag_* arrive via MultiplayerSynchronizer, same pattern
## as ProductionBuilding.construction_progress driving its bar) so the disc
## animates identically for everyone, not just the host.
func _process(_delta: float) -> void:
	if _letter_label != null:
		_letter_label.modulate = owner_tint().lightened(0.25) if owner_peer_id > 0 else Color(0.85, 0.85, 0.85)
	var at_rest := is_flag_at_rest()
	progress_disc.visible = not at_rest
	if at_rest:
		return
	var mat := progress_disc.get_active_material(0)
	if mat:
		mat.set_shader_parameter("fill", flag_control)
		## Well under opaque: full-strength team colours are loud across a
		## whole capture zone.
		mat.set_shader_parameter("fill_color", Color(flag_tint(), 0.45))

func _tick_favour(delta: float) -> void:
	## First, so none of the Favour-only early-outs below (Annihilation) skip them.
	_tick_gold(delta)
	_tick_research(delta)
	if favour_per_second <= 0.0 or owner_peer_id <= 0 or not _paying:
		return
	## An eliminated or disconnected owner keeps the point until someone takes
	## it, but it earns them nothing.
	var main := get_tree().current_scene
	if main.has_method("is_peer_active") and not main.is_peer_active(owner_peer_id):
		return
	## Favour only exists as the Conquest score.
	if "conquest_enabled" in main and not main.conquest_enabled:
		return
	_favour_fraction += favour_per_second * _tier_income() * delta
	var whole := int(_favour_fraction)
	if whole <= 0:
		return
	_favour_fraction -= float(whole)
	ResourceStockpile.add(owner_peer_id, FAVOUR_RESOURCE, whole)
	if main.has_method("show_favour_popup"):
		main.show_favour_popup(self, whole)

## Host-only remainders of gold/wood earned but not yet whole enough to bank.
var _gold_fraction: float = 0.0
var _wood_fraction: float = 0.0
var _food_fraction: float = 0.0

## Same terms as Favour (see _tick_favour) apart from the game mode. Pays
## wood alongside gold; the POINT_GOLD research bonus scales both.
func _tick_gold(delta: float) -> void:
	if (gold_per_second <= 0.0 and wood_per_second <= 0.0) or owner_peer_id <= 0 or not _paying:
		return
	var main := get_tree().current_scene
	if main.has_method("is_peer_active") and not main.is_peer_active(owner_peer_id):
		return
	var mult := (1.0 + Research.bonus(owner_peer_id, ResearchNode.Stat.POINT_GOLD)) * _tier_income() * _night_bonus() * delta
	_gold_fraction += gold_per_second * mult
	_wood_fraction += wood_per_second * mult
	if is_settlement():
		_food_fraction += TIER_FOOD_PER_SECOND[tier] * _night_bonus() * delta
		var whole_food := int(_food_fraction)
		if whole_food > 0:
			_food_fraction -= float(whole_food)
			ResourceStockpile.add(owner_peer_id, FOOD_RESOURCE, whole_food)
			_count_income(FOOD_RESOURCE, whole_food)
	var whole_gold := int(_gold_fraction)
	if whole_gold > 0:
		_gold_fraction -= float(whole_gold)
		ResourceStockpile.add(owner_peer_id, GOLD_RESOURCE, whole_gold)
		_count_income(GOLD_RESOURCE, whole_gold)
	var whole_wood := int(_wood_fraction)
	if whole_wood > 0:
		_wood_fraction -= float(whole_wood)
		ResourceStockpile.add(owner_peer_id, WOOD_RESOURCE, whole_wood)
		_count_income(WOOD_RESOURCE, whole_wood)

## Research points per point of favour_per_second — so the centre point,
## which pays double Favour, pays double research too.
const RESEARCH_PER_FAVOUR: float = 1.0 / 20.0
## Host-only remainder of research earned but not yet whole enough to bank.
var _research_fraction: float = 0.0

## Same terms as gold (see _tick_gold): every game mode.
func _tick_research(delta: float) -> void:
	if favour_per_second <= 0.0 or owner_peer_id <= 0 or not _paying:
		return
	var main := get_tree().current_scene
	if main.has_method("is_peer_active") and not main.is_peer_active(owner_peer_id):
		return
	_research_fraction += favour_per_second * RESEARCH_PER_FAVOUR * _tier_income() * delta
	var whole := int(_research_fraction)
	if whole <= 0:
		return
	_research_fraction -= float(whole)
	Research.earn(owner_peer_id, whole, &"points")

## Host only. Both halves of a capture come through here: lowering the old
## owner's flag hands the point to 0 (neutral), raising a new one hands it to
## that player. Anything queued on the buildings is cancelled first so the
## refund goes back to whoever paid for it.
func _set_owner(new_owner: int) -> void:
	var main := get_tree().current_scene
	var tint: Color = NEUTRAL_TINT
	if new_owner > 0 and main.has_method("get_team_tint"):
		tint = main.get_team_tint(new_owner)
	for building in buildings.get_children():
		if not (building is ProductionBuilding):
			continue
		while not building.queue.is_empty():
			building.cancel_at(building.queue.size() - 1)
		building.has_rally_point = false
		building.toggle_repeat(null)
		building.owner_peer_id = new_owner
		building.team_tint = tint
	var previous_owner: int = owner_peer_id
	owner_peer_id = new_owner
	if previous_owner > 0 and previous_owner != new_owner and main.has_method("check_out"):
		main.check_out.call_deferred(previous_owner)
	## Dropped rather than carried over, so a partial point earned under the
	## previous owner can't be banked by whoever takes the objective off them.
	_favour_fraction = 0.0
	_gold_fraction = 0.0
	_wood_fraction = 0.0
	_food_fraction = 0.0
	_income_shown.clear()
	_income_timer = 0.0
	_garrison.clear()
	_garrison_timer = 0.0
	for building in _slot_buildings:
		if not is_instance_valid(building) or building.is_destroyed:
			continue
		while not building.queue.is_empty():
			building.cancel_at(building.queue.size() - 1)
		building.has_rally_point = false
		building.toggle_repeat(null)
		building.owner_peer_id = new_owner
		building.team_tint = tint
	if is_settlement():
		razed = false
		_set_choice(new_owner)
		if multiplayer.multiplayer_peer != null:
			_rpc_houses.rpc(tier)
		_show_houses()
	if new_owner > 0 and "lords" in main and main.lords != null:
		main.lords.on_capture(global_position, new_owner)
	if new_owner > 0 and main.has_method("announce_point_captured"):
		main.announce_point_captured(new_owner, letter)

## --- Settlement (Realm), continued ---

func is_settlement() -> bool:
	return MatchRules.realm() and not (self is ShrineObjective)

func _tier_income() -> float:
	return TIER_INCOME[tier] if is_settlement() else 1.0

## Host only.
func _tick_settlement(delta: float) -> void:
	if choice_peer > 0:
		_choice_timer += delta
		if _choice_timer >= CHOICE_SECONDS:
			resolve_choice(Choice.OCCUPY)
	_tick_doors(delta)
	if owner_peer_id <= 0 or not _paying or contested:
		return
	_income_timer += delta
	if _income_timer >= INCOME_POPUP_SECONDS:
		_income_timer = 0.0
		_show_income()
	_garrison = _garrison.filter(func(u): return is_instance_valid(u) and u.status_activity != Unit.Activity.DEAD \
			and u.owner_peer_id == owner_peer_id)
	if _garrison.size() >= _garrison_cap() or _guard_roster.is_empty():
		_garrison_timer = 0.0
		return
	_garrison_timer += delta
	if _garrison_timer >= GARRISON_REGEN_SECONDS:
		_garrison_timer = 0.0
		_raise_garrison_man()

## One more of this settlement's own people, for its owner: an ordinary unit
## of theirs, standing at the settlement to be ordered like any other. Kept
## free of upkeep (RealmEconomy), and counted against the settlement's cap
## wherever he goes, so a settlement can't be milked for an army.
func _raise_garrison_man() -> void:
	var main := get_tree().current_scene
	if not ("unit_spawner" in main):
		return
	var entry: Dictionary = _guard_roster[_garrison.size() % _guard_roster.size()]
	var unit: Unit = main.unit_spawner.spawn({
		"scene_path": entry.scene_path,
		"peer_id": owner_peer_id,
		"tint": main.get_team_tint(owner_peer_id),
		"position": to_global(entry.position),
	})
	unit.set_meta(&"garrison", true)
	_garrison.append(unit)

## A neutral settlement is held by a small regiment, not the scene's handful:
## copies of its guards in a ring, remembered so a respawn brings them all back.
func _grow_neutral_garrison() -> void:
	var main := get_tree().current_scene
	if not ("unit_spawner" in main) or _guard_roster.is_empty():
		return
	var start: int = _guard_roster.size()
	for i in range(start, NEUTRAL_GARRISON):
		var template: Dictionary = _guard_roster[i % start]
		var angle: float = TAU * float(i) / float(NEUTRAL_GARRISON)
		var local := Vector3(cos(angle), 0.0, sin(angle)) * (wander_radius * 0.6)
		_guard_roster.append({scene_path = template.scene_path, position = local})
		var unit: Unit = main.unit_spawner.spawn({
			"scene_path": template.scene_path,
			"peer_id": 0,
			"tint": NEUTRAL_TINT,
			"position": to_global(local),
		})
		_setup_guard(unit)

@rpc("authority", "call_remote", "reliable")
func _rpc_houses(new_tier: int) -> void:
	tier = new_tier
	_show_houses()

## Cottages for the current tier, roofed in the owner's colour. Every peer lays
## them out from the settlement's own position, so they agree without being
## sent anywhere.
func _show_houses() -> void:
	var wanted: int = 0 if razed else TIER_HOUSES[tier]
	var tint: Color = owner_tint()
	if _houses.size() == wanted and tint == _house_owner_tint:
		return
	for house in _houses:
		house.queue_free()
	_houses.clear()
	_house_owner_tint = tint
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(roundi(global_position.x), roundi(global_position.z)))
	var start: float = rng.randf() * TAU
	for i in HOUSE_SLOTS:
		var angle: float = start + TAU * float(i) / float(HOUSE_SLOTS) + rng.randf_range(-0.2, 0.2)
		var radius: float = rng.randf_range(HOUSE_RING.x, HOUSE_RING.y)
		var yaw: float = rng.randf() * TAU
		if i >= wanted:
			continue
		var house := _make_house(tint)
		house.position = Vector3(cos(angle), 0.0, sin(angle)) * radius
		house.rotation.y = yaw
		add_child(house)
		_houses.append(house)
func _make_house(roof_tint: Color) -> Node3D:
	if _house_mesh_body == null:
		_house_mesh_body = BoxMesh.new()
		_house_mesh_body.size = Vector3(1.6, 1.1, 1.3)
		_house_mesh_roof = PrismMesh.new()
		_house_mesh_roof.size = Vector3(1.9, 0.8, 1.5)
	var house := Node3D.new()
	var body := MeshInstance3D.new()
	body.mesh = _house_mesh_body
	body.position.y = 0.55
	body.material_override = _house_material(HOUSE_WALLS)
	house.add_child(body)
	var roof := MeshInstance3D.new()
	roof.mesh = _house_mesh_roof
	roof.position.y = 1.5
	roof.material_override = _house_material(roof_tint.darkened(0.15))
	house.add_child(roof)
	## Hidden until explored, like the point's own buildings.
	house.add_to_group(&"fog_static_props")
	return house

static func _house_material(colour: Color) -> StandardMaterial3D:
	var key := colour.to_html()
	if not _house_materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = colour
		material.roughness = 0.9
		_house_materials[key] = material
	return _house_materials[key]

## Who holds the ground at `pos` in a Realm match: the owner of the nearest
## settlement or Town Centre within TERRITORY_REACH, or 0 for nobody's land.
static func territory_owner(tree: SceneTree, pos: Vector3) -> int:
	var best_owner: int = 0
	var best: float = TERRITORY_REACH * TERRITORY_REACH
	for node in tree.get_nodes_in_group(&"objectives"):
		var objective := node as Objective
		if objective == null or objective is ShrineObjective:
			continue
		var d: float = _flat_distance_squared(objective.global_position, pos)
		if d < best:
			best = d
			best_owner = objective.owner_peer_id
	for node in tree.get_nodes_in_group(&"buildings"):
		var building := node as ProductionBuilding
		if building == null or not building.is_main_base or building.is_destroyed:
			continue
		var d: float = _flat_distance_squared(building.global_position, pos)
		if d < best:
			best = d
			best_owner = building.owner_peer_id
	return best_owner

static func _flat_distance_squared(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length_squared()

## --- Slots (Realm) ---
## A settlement's hall (its central building) offers buildings for its slots
## as items in its own queue: one slot as a Village, two as a Town, three as a
## City. Each option can be built once; the building goes up finished when the
## item completes, in the next free place around the square.
const TIER_SLOTS: Array[int] = [1, 2, 3]
const SLOT_RADIUS: float = 6.0
const GRANARY: String = "Granary"
const MARKET: String = "Market"
const WATCHTOWER: String = "Watchtower"
const SLOT_BUILD_SECONDS: float = 30.0
## Race name -> [item name, building scene, wood, gold]: each people's own
## second building, which trains the rest of their roster.
const RACE_SLOTS: Dictionary = {
	"Gnolls": ["Gnoll Totem", "res://scenes/buildings/gnoll_totem_building.tscn", 120, 60],
	"Dark Elves": ["Dark Elf Coven", "res://scenes/buildings/dark_elf_coven_building.tscn", 120, 60],
	"Star Wanderers": ["Star Sanctum", "res://scenes/buildings/star_sanctum_building.tscn", 120, 60],
}
const WOOD_COST: ResourceType = preload("res://resources/wood_resource_type.tres")
const GOLD_COST: ResourceType = preload("res://resources/gold_resource_type.tres")

var hall: ProductionBuilding = null
## Item names already built here, in slot order. Replicated (_rpc_slots) so every
## peer's menu agrees on what is left.
var slot_built: PackedStringArray = PackedStringArray()
## Host only: the buildings standing in the slots.
var _slot_buildings: Array = []

func _slot_options() -> Array[ProducibleItem]:
	var items: Array[ProducibleItem] = []
	if RACE_SLOTS.has(race_name):
		var entry: Array = RACE_SLOTS[race_name]
		items.append(_slot_item(entry[0], entry[1], entry[2], entry[3]))
	items.append(_slot_item(GRANARY, "res://scenes/settlements/granary_building.tscn", 80, 0))
	if race_name == "Human":
		items.append(_slot_item(MARKET, "res://scenes/settlements/market_building.tscn", 60, 40))
	items.append(_slot_item(WATCHTOWER, "res://scenes/buildings/watchtower_building.tscn", 100, 20))
	items.append(_slot_item(WALLS, "res://scenes/buildings/wall_gate.tscn", 300, 100))
	return items

## The same items on every peer and in the same order: the hall's menu is
## indexed by position (Main.enqueue_as).
static func _slot_item(item_name: String, scene_path: String, wood: int, gold: int) -> ProducibleItem:
	var item := ProducibleItem.new()
	item.item_name = item_name
	item.kind = ProducibleItem.Kind.SLOT
	item.build_time = SLOT_BUILD_SECONDS
	item.slot_scene = load(scene_path)
	var costs: Array[ResourceCost] = []
	for pair in [[WOOD_COST, wood], [GOLD_COST, gold]]:
		if int(pair[1]) > 0:
			var cost := ResourceCost.new()
			cost.resource_type = pair[0]
			cost.amount = int(pair[1])
			costs.append(cost)
	item.costs = costs
	return item

func _offer_slots() -> void:
	if hall == null:
		return
	## A copy: the scene's list is shared by every building of that kind.
	var offered: Array[ProducibleItem] = hall.producibles.duplicate()
	offered.append_array(_slot_options())
	for next in [Tier.TOWN, Tier.CITY]:
		var raise := ProducibleItem.new()
		raise.item_name = "Upgrade to " + TIER_NAMES[next]
		raise.kind = ProducibleItem.Kind.TIER
		raise.tier_to = next
		raise.build_time = TIER_UPGRADE_SECONDS[next]
		var raise_costs: Array[ResourceCost] = []
		for pair in [[WOOD_COST, TIER_UPGRADE_WOOD[next]], [GOLD_COST, TIER_UPGRADE_GOLD[next]]]:
			var cost := ResourceCost.new()
			cost.resource_type = pair[0]
			cost.amount = pair[1]
			raise_costs.append(cost)
		raise.costs = raise_costs
		offered.append(raise)
	for choice in [Choice.OCCUPY, Choice.SACK, Choice.RAZE]:
		var item := ProducibleItem.new()
		item.item_name = CHOICE_NAMES[choice]
		item.kind = ProducibleItem.Kind.CHOICE
		item.choice = choice
		item.build_time = 0.0
		offered.append(item)
	hall.producibles = offered

## Whether `item` can go into the queue of this settlement's hall now.
func can_build_slot(item: ProducibleItem, queue: Array) -> bool:
	if not is_settlement() or slot_built.has(item.item_name):
		return false
	var queued := 0
	for entry in queue:
		if entry.kind == ProducibleItem.Kind.SLOT:
			if entry.item_name == item.item_name:
				return false
			queued += 1
	return slot_built.size() + queued < TIER_SLOTS[tier]

## For the HUD, on any peer: still to build, with a slot free for it.
func slot_open(item: ProducibleItem) -> bool:
	return is_settlement() and not slot_built.has(item.item_name) and slot_built.size() < TIER_SLOTS[tier]

## Host only, when a SLOT item finishes in the hall.
func place_slot(item: ProducibleItem) -> void:
	var main := get_tree().current_scene
	if item.slot_scene == null or not ("building_spawner" in main) or slot_built.size() >= TIER_SLOTS.back():
		return
	if item.item_name == WALLS:
		_build_walls()
		return
	var index: int = slot_built.size()
	var angle: float = PI * 0.5 + TAU * float(index) / float(TIER_SLOTS.back())
	var at: Vector3 = global_position + Vector3(cos(angle), 0.0, sin(angle)) * SLOT_RADIUS
	var building: ProductionBuilding = main.building_spawner.spawn({
		"scene_path": item.slot_scene.resource_path,
		"peer_id": owner_peer_id,
		"position": at,
		"tint": main.get_team_tint(owner_peer_id),
	})
	building.settlement = self
	_slot_buildings.append(building)
	slot_built.append(item.item_name)
	var built_name: String = item.item_name
	building.destroyed.connect(func():
		var i := slot_built.find(built_name)
		if i >= 0:
			slot_built.remove_at(i)
			_send_slots()
	, CONNECT_ONE_SHOT)
	_send_slots()

func _send_slots() -> void:
	if multiplayer.multiplayer_peer != null:
		_rpc_slots.rpc(slot_built)

@rpc("authority", "call_remote", "reliable")
func _rpc_slots(built: PackedStringArray) -> void:
	slot_built = built

## Star Wanderers' settlements pay up to half as much again by night.
const STAR_NIGHT_BONUS: float = 0.5

func _night_bonus() -> float:
	if not is_settlement() or race_name != "Star Wanderers":
		return 1.0
	var main := get_tree().current_scene
	if main == null or not ("day_night" in main) or main.day_night == null:
		return 1.0
	return 1.0 + STAR_NIGHT_BONUS * main.day_night.night_amount

## --- Occupy, Sack or Raze (Realm) ---
## Whoever takes a settlement decides, once, what becomes of it: keep it as it
## is, strip it for gold at the cost of a tier, or burn it to the ground for a
## little gold and leave nobody's ruins behind. The three sit on its hall's
## menu until chosen; left alone, it is occupied.
enum Choice { OCCUPY, SACK, RAZE }
const CHOICE_NAMES: Array[String] = ["Occupy", "Sack", "Raze"]
const CHOICE_SECONDS: float = 30.0
const SACK_GOLD: Array[int] = [100, 200, 350]
const RAZE_GOLD: int = 50

## The player whose decision is pending, 0 when none. Replicated for the menu.
var choice_peer: int = 0
var _choice_timer: float = 0.0
## Burnt out: no cottages until someone takes it again.
var razed: bool = false
## Razed ruins stay nobody's for this long before their garrison returns and
## they can be fought for again — or the same troops could raze, retake and
## raze again for gold for ever.
const RUIN_SECONDS: float = 120.0
## Host only: ruin time still to run.
var _ruin_left: float = 0.0

func _set_choice(peer_id: int) -> void:
	choice_peer = peer_id
	_choice_timer = 0.0
	if multiplayer.is_server() and multiplayer.multiplayer_peer != null:
		_rpc_choice.rpc(peer_id, razed)

@rpc("authority", "call_remote", "reliable")
func _rpc_choice(peer_id: int, is_razed: bool) -> void:
	choice_peer = peer_id
	razed = is_razed
	_show_houses()

func can_choose(peer_id: int, queue: Array) -> bool:
	if not is_settlement() or choice_peer <= 0 or choice_peer != peer_id:
		return false
	for entry in queue:
		if entry.kind == ProducibleItem.Kind.CHOICE:
			return false
	return true

## Host only.
func resolve_choice(choice: int) -> void:
	if choice_peer <= 0:
		return
	var chooser: int = choice_peer
	_set_choice(0)
	match choice:
		Choice.SACK:
			ResourceStockpile.add(chooser, GOLD_RESOURCE, SACK_GOLD[tier])
			tier = maxi(tier - 1, Tier.VILLAGE)
			if multiplayer.multiplayer_peer != null:
				_rpc_houses.rpc(tier)
			_show_houses()
		Choice.RAZE:
			ResourceStockpile.add(chooser, GOLD_RESOURCE, RAZE_GOLD)
			for building in _slot_buildings:
				if is_instance_valid(building) and not building.is_destroyed:
					building.take_damage(building.max_health * 10, null)
			_slot_buildings.clear()
			_gates.clear()
			_doors_shut = false
			slot_built = PackedStringArray()
			_send_slots()
			tier = Tier.VILLAGE
			flag_peer_id = 0
			flag_control = 0.0
			_set_owner(0)
			razed = true
			_ruin_left = RUIN_SECONDS
			_set_choice(0)
			if multiplayer.multiplayer_peer != null:
				_rpc_houses.rpc(tier)
			_show_houses()

## --- Raising a settlement (Realm) ---

## Whether `item` (a TIER item) can go into the hall's queue now: the next tier
## up, nothing else being raised, and no Occupy/Sack/Raze still to decide.
func can_raise(item: ProducibleItem, queue: Array) -> bool:
	if not is_settlement() or owner_peer_id <= 0 or choice_peer > 0 or tier != item.tier_to - 1:
		return false
	for entry in queue:
		if entry.kind == ProducibleItem.Kind.TIER:
			return false
	return true

## Host only, when an upgrade finishes in the hall.
func raise_tier(to: int) -> void:
	if to != tier + 1 or to > Tier.CITY:
		return
	tier = to
	if multiplayer.multiplayer_peer != null:
		_rpc_houses.rpc(tier)
	_show_houses()

## --- Income feedback (Realm) ---

func _count_income(type: ResourceType, amount: int) -> void:
	if is_settlement():
		_income_shown[type] = int(_income_shown.get(type, 0)) + amount

func _show_income() -> void:
	if _income_shown.is_empty():
		return
	var main := get_tree().current_scene
	if not ("feedback" in main):
		return
	var lines: Array = []
	for type in [FOOD_RESOURCE, GOLD_RESOURCE, WOOD_RESOURCE]:
		if int(_income_shown.get(type, 0)) > 0:
			lines.append([int(_income_shown[type]), type.display_color])
	_income_shown.clear()
	main.feedback.show_income_popup(self, owner_peer_id, lines)

## --- Walls (Realm) ---
## Walls are one of a settlement's slot buildings: a ring of wall around the
## cottages with WALL_GATES gates in it, raised in one go when the item
## finishes. A walled settlement keeps a bigger garrison. Its gates stand open
## until an enemy comes within DOOR_ALARM_RADIUS of the walls, then shut to
## everyone until the danger has gone — attackers have to batter a gate down
## (the AI's own breaching does this, see AiCombat._breach) or break the wall.
const WALLS: String = "Walls"
const WALL_RADIUS: float = 13.5
const WALL_SEGMENT: float = 2.0
const WALL_GATES: int = 3
const WALL_GARRISON_BONUS: int = 3
const DOOR_ALARM_RADIUS: float = 15.0
const DOOR_CHECK_SECONDS: float = 0.5
const WALL_SEGMENT_SCENE: String = "res://scenes/buildings/wall_segment.tscn"
const WALL_GATE_SCENE: String = "res://scenes/buildings/wall_gate.tscn"
const DOOR_COLOUR := Color(0.36, 0.25, 0.16)
const UnitGrid = preload("res://scripts/unit_grid.gd")

## Host only.
var _gates: Array = []
var _doors_shut: bool = false
var _door_timer: float = 0.0

func has_walls() -> bool:
	return slot_built.has(WALLS)

func _garrison_cap() -> int:
	return TIER_GARRISON[tier] + (WALL_GARRISON_BONUS if has_walls() else 0)

## Host only. Gates sit between the slot buildings' places, walls everywhere
## else round the ring that isn't already taken by something solid (a tree
## there blocks the way just as well). Slopes are fine: a gap left on a hillside
## would let an army walk round the walls.
func _build_walls() -> void:
	var main := get_tree().current_scene
	var count: int = ceili(TAU * WALL_RADIUS / WALL_SEGMENT)
	var gate_every: int = maxi(count / WALL_GATES, 1)
	var gate_offset: int = int(round(float(count) / (WALL_GATES * 2.0)))
	for i in count:
		var angle: float = PI * 0.5 + TAU * float(i) / float(count)
		var at: Vector3 = global_position + Vector3(cos(angle), 0.0, sin(angle)) * WALL_RADIUS
		at = main.placement.grounded_position(at, 0.8)
		var is_gate: bool = (i + gate_offset) % gate_every == 0 and _gates.size() < WALL_GATES
		if not is_gate and not main.placement._is_placement_valid(at, WALL_CLEARANCE):
			continue
		var piece: ProductionBuilding = main.building_spawner.spawn({
			"scene_path": WALL_GATE_SCENE if is_gate else WALL_SEGMENT_SCENE,
			"peer_id": owner_peer_id,
			"position": at,
			"rotation": Vector3(0.0, -(angle + PI * 0.5), 0.0),
			"tint": main.get_team_tint(owner_peer_id),
		})
		piece.settlement = self
		_slot_buildings.append(piece)
		if is_gate:
			_gates.append(piece)
	slot_built.append(WALLS)
	_send_slots()

## How much room a wall piece needs clear of other solid things.
const WALL_CLEARANCE: float = 0.6

## Host only.
func _tick_doors(delta: float) -> void:
	if _gates.is_empty():
		return
	_door_timer -= delta
	if _door_timer > 0.0:
		return
	_door_timer = DOOR_CHECK_SECONDS
	_gates = _gates.filter(func(gate): return is_instance_valid(gate) and not gate.is_destroyed)
	var danger: bool = owner_peer_id > 0 and not UnitGrid.enemies_near(get_tree(), global_position,
			WALL_RADIUS + DOOR_ALARM_RADIUS, owner_peer_id).is_empty()
	if danger == _doors_shut:
		return
	_doors_shut = danger
	var paths: Array[NodePath] = []
	for gate in _gates:
		paths.append(gate.get_path())
	_apply_doors(paths, danger)
	if multiplayer.multiplayer_peer != null:
		_rpc_doors.rpc(paths, danger)

@rpc("authority", "call_remote", "reliable")
func _rpc_doors(paths: Array[NodePath], shut: bool) -> void:
	_apply_doors(paths, shut)

## A door is a plank wall between a gate's posts: seen and solid while shut,
## gone while open. Built the first time it is needed, on every peer.
func _apply_doors(paths: Array[NodePath], shut: bool) -> void:
	for path in paths:
		var gate := get_node_or_null(path) as Node3D
		if gate == null:
			continue
		var door := gate.get_node_or_null(^"Door") as StaticBody3D
		if door == null:
			door = _make_door(gate)
		door.visible = shut
		(door.get_child(0) as CollisionShape3D).disabled = not shut
		if shut:
			door.add_to_group(&"nav_blockers")
		elif door.is_in_group(&"nav_blockers"):
			door.remove_from_group(&"nav_blockers")

func _make_door(gate: Node3D) -> StaticBody3D:
	var door := StaticBody3D.new()
	door.name = "Door"
	if gate is CollisionObject3D:
		door.collision_layer = (gate as CollisionObject3D).collision_layer
	door.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.7, 1.6, 0.3)
	shape.shape = box
	shape.position.y = 0.8
	door.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = box.size
	mesh.mesh = box_mesh
	mesh.position.y = 0.8
	mesh.material_override = _house_material(DOOR_COLOUR)
	door.add_child(mesh)
	gate.add_child(door)
	return door
