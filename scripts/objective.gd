extends Node3D
class_name Objective

## How long the capture zone must be held uncontested (see _physics_process)
## before ownership changes.
@export var capture_duration: float = 30.0
## Guards wander about within this radius of the objective's origin; they'll
## break off a chase and return once dragged past
## wander_radius * LEASH_MULTIPLIER (see Unit.leash_radius).
@export var wander_radius: float = 4.0
## Favour per second credited to whoever currently holds this objective —
## the whole point of taking one, since Favour is what Shrines train monsters
## with and nothing else in the game produces it. 0 (the default) means an
## objective is worth only the buildings on it, so a map can mix paying and
## non-paying objectives without a separate scene/script per kind.
@export var favour_per_second: float = 0.0

const LEASH_MULTIPLIER: float = 2.5
## ResourceStockpile totals are ints, so fractional income accumulates here
## and is banked a whole point at a time (see _tick_favour).
const FAVOUR_RESOURCE: ResourceType = preload("res://resources/favour_resource_type.tres")

@onready var capture_zone: Area3D = $CaptureZone
@onready var guards: Node3D = $Guards
@onready var buildings: Node3D = $Buildings
@onready var progress_disc: MeshInstance3D = $ProgressDisc

## 0 = neutral/AI-controlled, same convention as Gatherable.owner_peer_id.
var owner_peer_id: int = 0
var capture_progress: float = 0.0
## Host-only remainder of Favour earned but not yet whole enough to bank.
var _favour_fraction: float = 0.0
## Guards already passed to main for signal wiring — see register_guard.
var _registered_guards: Array[Unit] = []

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
	progress_disc.visible = false
	var main := get_tree().current_scene
	for building in buildings.get_children():
		if building is ProductionBuilding and main.has_method("register_objective_building"):
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
		unit.owner_peer_id = 0
		unit.team_tint = Color(0.5, 0.5, 0.5)
		unit.leash_origin = self
		unit.leash_radius = wander_radius * LEASH_MULTIPLIER
		unit.command_wander(self, wander_radius)
	for building in buildings.get_children():
		building.owner_peer_id = 0

## Idempotent, because a ShrineObjective's guard does not exist at a fixed
## point in the lifecycle: the host adds it before _ready (so the loop above
## catches it), while a client adds it later from the host's reply (so
## _apply_monster has to call this itself). Whichever runs second is a no-op.
func register_guard(unit: Unit) -> void:
	if _registered_guards.has(unit):
		return
	_registered_guards.append(unit)
	var main := get_tree().current_scene
	if main.has_method("register_objective_unit"):
		main.register_objective_unit(unit)

## A destroyed building sticks around for its sink animation before freeing
## itself, so is_destroyed has to be checked rather than just the child count.
func _has_capturable_buildings() -> bool:
	for building in buildings.get_children():
		if building is ProductionBuilding and building.is_destroyed:
			continue
		return true
	return false

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	_tick_favour(delta)

	## Razing every building at an objective removes the thing ownership of it
	## would even transfer, so it stops being capturable at all rather than
	## flipping owner over an empty patch of ground.
	if not _has_capturable_buildings():
		capture_progress = 0.0
		return

	var defenders_present := false
	var attacker_peer := -1
	var contested := false
	for body in capture_zone.get_overlapping_bodies():
		if body is Unit and body.status_activity != Unit.Activity.DEAD:
			if body.owner_peer_id == owner_peer_id:
				defenders_present = true
			elif attacker_peer == -1:
				attacker_peer = body.owner_peer_id
			elif attacker_peer != body.owner_peer_id:
				contested = true

	if defenders_present or contested or attacker_peer == -1:
		capture_progress = maxf(capture_progress - delta, 0.0)
	else:
		capture_progress = minf(capture_progress + delta, capture_duration)
		if capture_progress >= capture_duration:
			_capture(attacker_peer)

## Runs on every peer (capture_progress arrives via MultiplayerSynchronizer,
## same pattern as ProductionBuilding.construction_progress driving its bar)
## so the disc animates identically for everyone, not just the host.
func _process(_delta: float) -> void:
	var fraction := capture_progress / capture_duration
	progress_disc.visible = fraction > 0.0
	var mat := progress_disc.get_active_material(0)
	if mat:
		mat.set_shader_parameter("fill", fraction)

## Income stops the moment the objective's buildings are all razed, matching
## the capture rule above — a salted objective pays nobody, which is what
## makes denial a real alternative to holding.
func _tick_favour(delta: float) -> void:
	if favour_per_second <= 0.0 or owner_peer_id <= 0 or not _has_capturable_buildings():
		return
	_favour_fraction += favour_per_second * delta
	var whole := int(_favour_fraction)
	if whole <= 0:
		return
	_favour_fraction -= float(whole)
	ResourceStockpile.add(owner_peer_id, FAVOUR_RESOURCE, whole)
	var main := get_tree().current_scene
	if main.has_method("show_favour_popup"):
		main.show_favour_popup(self, whole)


func _capture(new_owner: int) -> void:
	var main := get_tree().current_scene
	var tint: Color = main.get_team_tint(new_owner) if main.has_method("get_team_tint") else Color.WHITE
	for guard in guards.get_children():
		var unit: Unit = guard
		if unit.status_activity == Unit.Activity.DEAD:
			continue
		unit.owner_peer_id = new_owner
		unit.team_tint = tint
		unit.leash_origin = null
		unit.leash_radius = 0.0
		## Drops the guard order entirely (wander included) — otherwise a guard
		## caught mid-wander-pause would sit in Activity.IDLE under a
		## Command.PATROL that nothing advances any more, which also suppresses
		## the idle standing-guard scan (Command.NONE only).
		unit.command_stop()
		Population.reserve(new_owner, unit.population_cost)
	for building in buildings.get_children():
		building.owner_peer_id = new_owner
		building.team_tint = tint
	owner_peer_id = new_owner
	capture_progress = 0.0
	## Dropped rather than carried over, so a partial point earned under the
	## previous owner can't be banked by whoever takes the objective off them.
	_favour_fraction = 0.0
