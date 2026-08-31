extends Node3D
class_name Objective

## How long the capture zone must be held uncontested (see _physics_process)
## before ownership changes.
@export var capture_duration: float = 30.0
## Guards patrol a square loop of this radius around the objective's origin;
## they'll break off a chase and return once dragged past
## patrol_radius * LEASH_MULTIPLIER (see Unit.leash_radius).
@export var patrol_radius: float = 4.0

const LEASH_MULTIPLIER: float = 2.5

@onready var capture_zone: Area3D = $CaptureZone
@onready var guards: Node3D = $Guards
@onready var buildings: Node3D = $Buildings
@onready var progress_disc: MeshInstance3D = $ProgressDisc

## 0 = neutral/AI-controlled, same convention as Gatherable.owner_peer_id.
var owner_peer_id: int = 0
var capture_progress: float = 0.0

func _ready() -> void:
	progress_disc.visible = false
	var main := get_tree().current_scene
	for building in buildings.get_children():
		if building is ProductionBuilding and main.has_method("register_objective_building"):
			main.register_objective_building(building)
	if not multiplayer.is_server():
		return
	for guard in guards.get_children():
		var unit: Unit = guard
		unit.owner_peer_id = 0
		unit.team_tint = Color(0.5, 0.5, 0.5)
		unit.leash_origin = self
		unit.leash_radius = patrol_radius * LEASH_MULTIPLIER
		unit.command_patrol(_patrol_loop())
	for building in buildings.get_children():
		building.owner_peer_id = 0

func _patrol_loop() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for i in 4:
		var angle := TAU * i / 4.0
		points.append(global_position + Vector3(cos(angle), 0.0, sin(angle)) * patrol_radius)
	return points

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
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
		Population.reserve(new_owner, unit.population_cost)
	for building in buildings.get_children():
		building.owner_peer_id = new_owner
		building.team_tint = tint
	owner_peer_id = new_owner
	capture_progress = 0.0
