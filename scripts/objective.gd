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

const LEASH_MULTIPLIER: float = 2.5
const NEUTRAL_TINT: Color = Color(0.5, 0.5, 0.5)
## Above the Favour "+N" popups (WorldFeedback.FAVOUR_POPUP_HEIGHT).
const LETTER_HEIGHT: float = 5.5
## ResourceStockpile totals are ints, so fractional income accumulates here
## and is banked a whole point at a time (see _tick_favour).
const FAVOUR_RESOURCE: ResourceType = preload("res://resources/favour_resource_type.tres")

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
	if not multiplayer.is_server():
		return
	for guard in guards.get_children():
		var unit: Unit = guard
		_guard_roster.append({scene_path = unit.scene_file_path, position = unit.position})
		_setup_guard(unit)
	for building in buildings.get_children():
		building.owner_peer_id = 0

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

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	## Combat-unit head count per player standing in the zone. Neutral guards
	## (peer 0) aren't a player; they block capture outright instead.
	var counts: Dictionary = {}
	var anyone_present := false
	for body in capture_zone.get_overlapping_bodies():
		if not (body is Unit) or body.status_activity == Unit.Activity.DEAD or body.owner_peer_id <= 0:
			continue
		anyone_present = true
		if _counts_for_capture(body):
			counts[body.owner_peer_id] = counts.get(body.owner_peer_id, 0) + 1

	_tick_guard_respawn(delta, anyone_present)

	contested = false
	_paying = true
	if owner_peer_id == 0 and _any_guard_alive():
		flag_peer_id = 0
		flag_control = 0.0
		return

	var step := delta / stage_duration
	var holder_count: int = counts.get(flag_peer_id, 0) if flag_peer_id > 0 else 0
	var challengers: Array = counts.keys().filter(func(p): return p != flag_peer_id)

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
		flag_peer_id = challengers[0] if a > b else challengers[1]
		_raise(step * _capture_speed(absi(a - b)))
	elif challengers.size() > 1:
		contested = true
		_paying = false
	elif flag_peer_id == 0:
		## A bare pole: the lone player present starts raising their flag.
		flag_peer_id = challengers[0]
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

func _raise(amount: float) -> void:
	flag_control = minf(flag_control + amount, 1.0)
	if flag_control >= 1.0 and owner_peer_id != flag_peer_id:
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
	_favour_fraction += favour_per_second * delta
	var whole := int(_favour_fraction)
	if whole <= 0:
		return
	_favour_fraction -= float(whole)
	ResourceStockpile.add(owner_peer_id, FAVOUR_RESOURCE, whole)
	if main.has_method("show_favour_popup"):
		main.show_favour_popup(self, whole)

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
		building.owner_peer_id = new_owner
		building.team_tint = tint
	owner_peer_id = new_owner
	## Dropped rather than carried over, so a partial point earned under the
	## previous owner can't be banked by whoever takes the objective off them.
	_favour_fraction = 0.0
	if new_owner > 0 and main.has_method("announce_point_captured"):
		main.announce_point_captured(new_owner, letter)
