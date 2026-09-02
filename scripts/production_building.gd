class_name ProductionBuilding
extends StaticBody3D
## Generic producing building. One reusable scene/script pair: what a specific
## building "is" (Town Center, Barracks, ...) is entirely defined by the
## `building_name` and `producibles` configured on the instance in the inspector.
## The build menu UI reads `producibles` to know what buttons to show.
##
## Only the host ever actually runs the queue/construction/combat simulation
## (see the is_multiplayer_authority() guard in _process); everyone else just
## displays the handful of fields below that are kept in sync for the UI.

signal queue_changed
signal item_completed(item: ProducibleItem)
signal construction_finished
signal destroyed
## Relayed by main.gd for a floating damage-number popup, same reasoning as
## Unit.damaged — take_damage() only ever runs on the host.
signal damaged(amount: int)

const DESTROY_SINK_DURATION: float = 1.5

@export var building_name: String = "Production Building"
## The single source of truth for what this building costs to construct —
## edit it right here rather than on BuildingType, which just reads it back
## via BuildingType.get_costs() when placement is requested.
@export var costs: Array[ResourceCost] = []
@export var producibles: Array[ProducibleItem] = []
## Which player owns this building; only they may queue production on it.
@export var owner_peer_id: int = 1
## Where completed units appear in the world.
@export var spawn_point_path: NodePath = ^"SpawnPoint"
## Whether this building type supports a rally point at all (Town Center,
## Barracks, etc). When off, right-clicking it while selected does nothing.
@export var can_rally: bool = true
## How far this building reveals fog of war around itself.
@export var vision_range: float = 10.0
## One is picked at random and played through select_audio_player whenever
## this building becomes newly selected (see main.gd's selection code).
@export var on_select_sound_effects: Array[AudioStream] = []
## Added to the owner's population cap once construction finishes (or
## immediately for buildings placed pre-built, e.g. the starting Town
## Center), and removed again if this building is destroyed. 0 for buildings
## that don't grant population room (Barracks, Farm).
@export var population_capacity: int = 0
## Set alongside owner_peer_id at spawn time; used only for the minimap dot
## color (buildings have no sprite to modulate the way units do).
@export var team_tint: Color = Color.WHITE
## Set once a ProducibleItem with kind == UPGRADE and unlocks_monarch_promotion
## completes on this building (see main.gd:_on_building_item_completed).
## Mirrored to non-authoritative peers so their own command panel can tell
## whether promotion is available.
@export var can_promote_monarch: bool = false
## How far the model sinks into the ground as it's destroyed.
@export var construction_sink_depth: float = 3.0
## Set (via spawn data, resolved per-peer from a NodePath since Gatherables
## aren't networked nodes) when this building was placed via requires_deposit
## (e.g. a Mine on a Gold Deposit). Its collision commonly overlaps the
## deposit's own, and either way "right-click the building itself" should
## still gather from the resource it sits on rather than just moving there.
var linked_deposit: Gatherable = null

@export_group("Combat")
@export var max_health: int = 100
## True only for Town Center-type buildings: a player loses when all of theirs are destroyed.
@export var is_main_base: bool = false

## Mirrored to non-authoritative peers purely so their UI/health bar reads correctly.
@export var is_under_construction: bool = false
@export var construction_progress: float = 1.0
@export var synced_queue_size: int = 0
@export var synced_time_remaining: float = 0.0
@export var synced_current_item_name: String = ""
## 0-1 fraction of synced_current_item_name's build_time elapsed, for the
## command panel's queue progress bar.
@export var synced_current_item_progress: float = 0.0
@export var health_fraction: float = 1.0
## Mirrored purely for the "N building" UI display.
@export var synced_builder_count: int = 0
## item_name -> how many of that item are currently in queue (including the
## one in progress) — drives the small count badge on each producible button.
@export var synced_queue_counts: Dictionary = {}

var queue: Array[ProducibleItem] = []
var build_timer: float = 0.0
## Host-only: UPGRADE items already bought, so a one-time upgrade can't be
## queued twice — see the guard in enqueue().
var _purchased_upgrades: Array[ProducibleItem] = []

## How long a SINGLE builder takes to finish this from 0%; each additional
## villager assigned via add_builder() scales progress proportionally, so N
## builders finish in construction_time / N seconds. No progress is made at
## all with zero builders — see _process().
var construction_time: float = 0.0
var builders: Array[Unit] = []

## mesh_instance -> Array of its original per-surface material overrides
## (null entries mean "no override", i.e. use the mesh's own material),
## captured so the translucent under-construction look can be reverted
## exactly. Applied/removed on every peer (see _update_construction_visual),
## not just the host, since materials aren't a networked property.
var _construction_visual_applied: bool = false
var _original_materials: Dictionary = {}

## Not networked: only the host's copy is ever read (when spawning units), and
## the one peer allowed to set it (the owner) writes their own local copy
## directly at the same time as sending the RPC that updates the host's copy.
var rally_point: Vector3 = Vector3.ZERO
var has_rally_point: bool = false
## Set alongside rally_point when the rally click landed on a Gatherable/enemy/
## under-construction-building target, so newly spawned units can be given the
## matching smart command (gather/attack/build) instead of just moving there.
var rally_target_path: NodePath = NodePath()

var current_health: int = 1
var is_destroyed: bool = false
var _destroy_timer: float = 0.0
var _destroy_start_y: float = 0.0

@onready var health_bar: Node3D = $HealthBar
@onready var health_bar_fill: Sprite3D = $HealthBar/Fill
@onready var select_audio_player: AudioStreamPlayer = $SelectAudioPlayer
## Both purely cosmetic and Inspector-configurable per building type (particle
## count/color/spread/etc. are all edited directly on these nodes, not the
## script) — see _update_construction_visual() for when each one fires.
@onready var placement_particles: GPUParticles3D = get_node_or_null("PlacementBurst")
@onready var construction_particles: GPUParticles3D = get_node_or_null("ConstructionDust")

func play_select_sound() -> void:
	AudioUtils.play_random(select_audio_player, on_select_sound_effects)

## Captured from the scene's authored (full-health) scale so the fill's
## aspect-ratio/sizing lives in the scene file, not duplicated in script.
var _fill_base_scale_x: float = 1.0

func _ready() -> void:
	current_health = max_health
	if health_bar_fill:
		_fill_base_scale_x = health_bar_fill.scale.x

## Called by whatever places this building (e.g. the placement system) once
## it's positioned in the world. Buildings placed directly in a scene file
## (like a level's starting Town Center) simply never call this, so they
## start fully built. The building appears immediately at its real position
## (never sunk below the ground) so it's clickable right away — a builder has
## to be assigned to make any progress at all, so a buried-and-unclickable
## building would be a permanent soft-lock. See _update_construction_visual()
## for the translucent "not finished yet" look instead.
func begin_construction(duration: float) -> void:
	if duration <= 0.0:
		return
	construction_time = duration
	is_under_construction = true
	construction_progress = 0.0

## Called by Unit when a builder arrives at (or leaves) this site.
func add_builder(unit: Unit) -> void:
	if not is_under_construction or is_destroyed or builders.has(unit):
		return
	builders.append(unit)
	synced_builder_count = builders.size()

func remove_builder(unit: Unit) -> void:
	builders.erase(unit)
	synced_builder_count = builders.size()

func enqueue(item: ProducibleItem) -> bool:
	if is_destroyed or is_under_construction or item == null or not ResourceStockpile.can_afford(owner_peer_id, item.get_costs()):
		return false
	if item.kind == ProducibleItem.Kind.UPGRADE:
		if _purchased_upgrades.has(item) or queue.has(item):
			return false
		if item.requires_upgrade != null and not _purchased_upgrades.has(item.requires_upgrade):
			return false
	## Population is reserved as soon as an item enters the queue (not when it
	## actually spawns) so a player can't queue past the cap; Unit.release()s
	## the same amount when the resulting unit later dies.
	if item.kind == ProducibleItem.Kind.UNIT and not Population.has_room(owner_peer_id, item.get_population_cost()):
		return false
	ResourceStockpile.spend(owner_peer_id, item.get_costs())
	if item.kind == ProducibleItem.Kind.UNIT:
		Population.reserve(owner_peer_id, item.get_population_cost())
	queue.append(item)
	queue_changed.emit()
	return true

func time_remaining() -> float:
	if queue.is_empty():
		return 0.0
	return maxf(queue[0].build_time - build_timer, 0.0)

## Buildings can't fight back themselves, but they can call nearby units in to defend.
func take_damage(amount: int, attacker: Node3D = null) -> void:
	if not is_multiplayer_authority() or is_destroyed:
		return
	damaged.emit(amount)
	current_health = maxi(current_health - amount, 0)
	health_fraction = float(current_health) / float(maxi(max_health, 1))
	if current_health <= 0:
		_begin_destruction()
		return
	CombatUtils.alert_nearby_allies(get_tree(), global_position, owner_peer_id, attacker)

## How far NavigationObstacle3D avoidance keeps agents pushed back from this
## building's center; units attacking a building need to account for this so
## they don't try to stand somewhere avoidance will never let them reach.
func get_footprint_radius() -> float:
	var obstacle: NavigationObstacle3D = get_node_or_null("NavigationObstacle3D")
	return obstacle.radius if obstacle else 0.0

func _begin_destruction() -> void:
	is_destroyed = true
	is_under_construction = false
	_destroy_timer = 0.0
	_destroy_start_y = position.y
	destroyed.emit()

func _process(delta: float) -> void:
	_update_health_bar_visual()
	## Materials aren't a networked property, so every peer must apply/revert
	## this locally off the already-synced is_under_construction flag, not
	## just the host.
	_update_construction_visual()

	if not is_multiplayer_authority():
		return

	if is_destroyed:
		_destroy_timer += delta
		var t: float = clampf(_destroy_timer / DESTROY_SINK_DURATION, 0.0, 1.0)
		position.y = lerpf(_destroy_start_y, _destroy_start_y - construction_sink_depth, t)
		if t >= 1.0:
			queue_free()
		return

	if is_under_construction:
		## Prune builders that died, were freed, or otherwise left without
		## formally releasing this site (shouldn't normally happen since
		## Unit._leave_build_site() covers those paths, but stay defensive).
		for i in range(builders.size() - 1, -1, -1):
			if not is_instance_valid(builders[i]) or builders[i].status_activity == Unit.Activity.DEAD:
				builders.remove_at(i)
		synced_builder_count = builders.size()

		if not builders.is_empty():
			construction_progress = clampf(
				construction_progress + (builders.size() / maxf(construction_time, 0.01)) * delta, 0.0, 1.0
			)
		if construction_progress >= 1.0:
			is_under_construction = false
			for builder in builders.duplicate():
				builder.end_build_command()
			construction_finished.emit()
		return

	if queue.is_empty():
		build_timer = 0.0
	else:
		build_timer += delta
		if build_timer >= queue[0].build_time:
			var item: ProducibleItem = queue.pop_front()
			build_timer = 0.0
			item_completed.emit(item)
			queue_changed.emit()

	synced_queue_size = queue.size()
	synced_time_remaining = time_remaining()
	synced_current_item_name = queue[0].item_name if not queue.is_empty() else ""
	synced_current_item_progress = clampf(1.0 - synced_time_remaining / maxf(queue[0].build_time, 0.01), 0.0, 1.0) \
			if not queue.is_empty() else 0.0

	var counts: Dictionary = {}
	for queued_item in queue:
		counts[queued_item.item_name] = counts.get(queued_item.item_name, 0) + 1
	synced_queue_counts = counts

func _update_health_bar_visual() -> void:
	if not health_bar:
		return
	var fraction: float = clampf(health_fraction, 0.0, 1.0)
	health_bar.visible = fraction < 0.999 and not is_destroyed
	## Scale from center only (no position offset) so Fill can't visually drift
	## away from Background as the camera orbits.
	health_bar_fill.scale.x = _fill_base_scale_x * maxf(fraction, 0.001)

func _update_construction_visual() -> void:
	if is_under_construction:
		if not _construction_visual_applied:
			_apply_construction_transparency()
			_construction_visual_applied = true
			## Fires once per peer, right when is_under_construction is first
			## seen true — not gated to the host, since this flag is what
			## _process() already uses on every peer to notice the transition
			## (is_under_construction itself is synced, but arrives async, so
			## polling for the change here is more reliable than trying to
			## catch it exactly once in _ready()).
			if placement_particles:
				placement_particles.restart()
		_update_construction_rise()
		## Checked every frame (not just on the transition above) so the dust
		## follows synced_builder_count live — it should stop the moment the
		## last builder leaves/dies and resume as soon as one arrives, not
		## just run continuously for the whole (possibly builder-less) time
		## the site sits under construction.
		if construction_particles:
			construction_particles.emitting = synced_builder_count > 0
	elif _construction_visual_applied:
		_restore_materials()
		_construction_visual_applied = false
		if construction_particles:
			construction_particles.emitting = false

const _CONSTRUCTION_ALPHA: float = 0.45

func _apply_construction_transparency() -> void:
	_original_materials.clear()
	_tint_recursive(self)

## Only the mesh nodes are affected (never the root/collision, which must
## stay put and clickable from the moment the building is placed). Each
## mesh's own local Y and the local Y of its own bottom edge (from its AABB)
## are remembered so it can grow from a thin sliver at ground level up to its
## full height as construction_progress advances — the bottom edge stays
## fixed the whole time (so it's never invisible below the ground, and never
## needs to "pop in" at 100%), only the top rises.
func _tint_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance: MeshInstance3D = node
		var surface_count: int = mesh_instance.mesh.get_surface_count() if mesh_instance.mesh else 0
		var originals: Array = []
		for i in surface_count:
			originals.append(mesh_instance.get_surface_override_material(i))
			var base: Material = mesh_instance.get_active_material(i)
			var ghost: StandardMaterial3D = base.duplicate() if base is StandardMaterial3D else StandardMaterial3D.new()
			ghost.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			ghost.albedo_color.a = _CONSTRUCTION_ALPHA
			mesh_instance.set_surface_override_material(i, ghost)
		if surface_count > 0:
			_original_materials[mesh_instance] = {
				"materials": originals,
				"base_y": mesh_instance.position.y,
				"base_scale_y": mesh_instance.scale.y,
				"aabb_bottom": mesh_instance.mesh.get_aabb().position.y if mesh_instance.mesh else 0.0,
			}
	for child in node.get_children():
		_tint_recursive(child)

## Never lets progress reach a literal 0 scale — a completely flat mesh is an
## easy-to-misread "did it vanish?" state, so there's always a thin sliver
## visible immediately on placement.
const _MIN_RISE_FRACTION: float = 0.05

func _update_construction_rise() -> void:
	var t: float = clampf(construction_progress, _MIN_RISE_FRACTION, 1.0)
	for mesh_instance in _original_materials:
		if not is_instance_valid(mesh_instance):
			continue
		var info: Dictionary = _original_materials[mesh_instance]
		var base_scale_y: float = info["base_scale_y"]
		var scale_y: float = base_scale_y * t
		mesh_instance.scale.y = scale_y
		mesh_instance.position.y = info["base_y"] + info["aabb_bottom"] * base_scale_y * (1.0 - t)

func _restore_materials() -> void:
	for mesh_instance in _original_materials:
		if is_instance_valid(mesh_instance):
			var info: Dictionary = _original_materials[mesh_instance]
			var originals: Array = info["materials"]
			for i in originals.size():
				mesh_instance.set_surface_override_material(i, originals[i])
			mesh_instance.position.y = info["base_y"]
			mesh_instance.scale.y = info["base_scale_y"]
	_original_materials.clear()
