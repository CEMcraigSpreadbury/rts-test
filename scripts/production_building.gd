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
signal damaged(amount: int, attacker_path: NodePath, fatal: bool)
## Purely cosmetic (see Unit.projectile_fired) — real damage lands later, off
## _pending_projectile_hits, entirely independent of this signal/its visual.
signal projectile_fired(target: Node3D)

const DESTROY_SINK_DURATION: float = 1.5
## Most items a building will hold at once, counting the one it's currently
## working on — enqueue() refuses anything past this (and, since nothing is
## charged for a refused order, the player keeps their resources).
const MAX_QUEUE_SIZE: int = 7

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
## Which resources a gatherer may drop off here. Only read for buildings in
## the "dropoff_points" group (see Unit._nearest_dropoff) — empty means "every
## type", which is what the Town Center wants; a Mill lists Food alone so wood
## and gold still get hauled back to the Town Center rather than to whichever
## Mill happens to be closer.
@export var dropoff_resource_types: Array[ResourceType] = []
## Set alongside owner_peer_id at spawn time. Drives the minimap dot color and
## the team_color.gdshader recolor of the model's blue parts (its flags,
## banners and painted panels) — the wood, thatch and stone stay as painted.
## Setter-driven so a post-spawn ownership change (objective.gd capturing a
## building) re-tints it immediately rather than only ever applying at spawn.
@export var team_tint: Color = Color.WHITE:
	set(value):
		team_tint = value
		_apply_team_color()
## Set once a ProducibleItem with kind == UPGRADE and unlocks_monarch_promotion
## completes on this building (see main.gd:_on_building_item_completed).
## Mirrored to non-authoritative peers so their own command panel can tell
## whether promotion is available.
@export var can_promote_monarch: bool = false
## How far the model sinks into the ground as it's destroyed.
@export var construction_sink_depth: float = 3.0
## >0 marks this building as a walkable OPENING rather than a solid obstacle,
## and is the clear width (meters) of that opening. The passage is centred on
## this node's own origin and runs along its local Z; the structure itself sits
## to either side on local X. Only wall_gate.tscn sets it (1.4 — its two posts
## sit at x=+/-0.85 and are 0.3 wide, so the clear span between their inner
## faces is 1.7 - 0.3 = 1.4). Read host-side by main.gd's _find_funnel_point.
## An opening's NavigationObstacle3D footprints must sit on the structure to
## either side of it, never in the opening itself: RVO keeps every unit
## agent-radius clear of an obstacle centre, so an obstacle parked in a doorway
## makes that doorway unusable no matter how wide it physically is (wall_gate
## carried exactly that bug — one radius-0.3 obstacle at the node origin —
## until this was added, and it is why it now has one small obstacle per post).
@export var passage_width: float = 0.0
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
## 0 (the default) means this building never attacks — set above 0 to make it
## a defensive structure (e.g. a Watchtower) that fires on its own at any
## enemy Unit that wanders within range, no player command involved.
@export var attack_range: float = 0.0
@export var attack_damage: int = 0
@export var attack_cooldown: float = 1.5
## Left null for a hitscan/instant attack; set to fire a visual projectile
## (travel-time-delayed damage) instead — same scene/timing convention as
## Unit.projectile_scene (e.g. res://scenes/effects/projectile_arrow.tscn).
@export var projectile_scene: PackedScene = null
@export var projectile_speed: float = 20.0

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

## Same throttled-rescan/delayed-hit pattern as Unit's own combat (see there
## for why: an unthrottled O(units) scan every frame, and instant on-fire
## damage instead of matching the projectile's actual travel time, are both
## worth avoiding even for a stationary attacker).
const _ENEMY_SCAN_INTERVAL: float = 0.25
var attack_target: Unit = null
## Damage already committed to this building by shots currently in the air,
## same reservation scheme as Unit.incoming_damage — see CombatUtils.
var incoming_damage: int = 0
var attack_timer: float = 0.0
var _enemy_scan_timer: float = 0.0
var _pending_projectile_hits: Array[Dictionary] = []

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

## Squash/flash visuals. The model is a differently-named child in every
## building scene, so it's identified as "the direct children that actually
## contain meshes" — which also skips the HealthBar (Sprite3D) and the
## particle emitters.
const SQUASH_SCALE: Vector3 = Vector3(1.06, 0.9, 1.06)
const SQUASH_DURATION: float = 0.4
const FLASH_ALPHA: float = 0.5
const FLASH_DURATION: float = 0.25
## A busy building (several villagers depositing, a fast production queue, or
## sustained fire) would otherwise restart the squash every few frames.
const SQUASH_COOLDOWN_MSEC: int = 400

var _model_roots: Array[Node3D] = []
var _model_base_scales: Array[Vector3] = []
var _squash_tween: Tween
var _next_squash_msec: int = 0
var _flash_meshes: Array[MeshInstance3D] = []
var _flash_material: StandardMaterial3D
var _flash_tween: Tween
## MeshInstance3D -> Array[Material], as the model shipped. See _capture_source_materials().
var _source_materials: Dictionary = {}

func _ready() -> void:
	current_health = max_health
	if health_bar_fill:
		_fill_base_scale_x = health_bar_fill.scale.x
	_collect_visuals()
	## team_tint is normally assigned at spawn time, before there is a tree to
	## walk, so the setter's own call is a no-op and this is where it lands.
	_apply_team_color()

func _collect_visuals() -> void:
	for child in get_children():
		if child is Node3D:
			var meshes: Array[MeshInstance3D] = []
			_collect_meshes(child, meshes)
			if not meshes.is_empty():
				_model_roots.append(child)
				_model_base_scales.append((child as Node3D).scale)
				_flash_meshes.append_array(meshes)
	_capture_source_materials()

## The material every model surface shipped with, taken once before any team
## recolor so re-tinting (an objective building changing hands mid-match)
## always rebuilds from the original art rather than from the previous team's
## already-recolored version — recoloring a recolor would drift the hue.
func _capture_source_materials() -> void:
	for mesh_instance in _flash_meshes:
		var surface_count: int = mesh_instance.mesh.get_surface_count() if mesh_instance.mesh else 0
		var sources: Array = []
		for i in surface_count:
			sources.append(mesh_instance.get_active_material(i))
		_source_materials[mesh_instance] = sources

## Puts every model surface on shaders/team_color.gdshader, which repaints
## just the blue parts of the texture (flags, banners, painted panels) in
## team_tint and leaves wood, thatch and stone exactly as painted.
##
## A no-op before _ready — team_tint's setter usually fires at spawn time,
## when _flash_meshes/_source_materials haven't been collected yet, so _ready()
## calls this again once they have.
func _apply_team_color() -> void:
	if _source_materials.is_empty():
		return
	## Color.WHITE is the "no team assigned" default — a placement ghost, or a
	## building sitting in a scene opened straight in the editor — not a real
	## team choice. It also has zero saturation, so recoloring with it would
	## drain the blue parts to grey rather than leave them alone. Either way
	## the right answer is the art exactly as painted.
	var untinted: bool = team_tint == Color.WHITE
	for mesh_instance in _source_materials:
		if not is_instance_valid(mesh_instance):
			continue
		var sources: Array = _source_materials[mesh_instance]
		var team_materials: Array = []
		for i in sources.size():
			var team_material: Material = sources[i] if untinted else TeamColorMaterial.build(
				sources[i], team_tint, TeamColorMaterial.TEAM_SHADER
			)
			team_materials.append(team_material)
			mesh_instance.set_surface_override_material(i, team_material)

		## Re-tinting mid-construction (a half-built objective changing hands)
		## has to leave the see-through version on the surface and hand the
		## fresh opaque one to _restore_materials for when it finishes, rather
		## than snapping the site to solid early.
		if _construction_visual_applied and _original_materials.has(mesh_instance):
			_original_materials[mesh_instance]["materials"] = team_materials
			for i in team_materials.size():
				mesh_instance.set_surface_override_material(i, _construction_ghost_for(team_materials[i]))
	_flash_material = StandardMaterial3D.new()
	_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_material.albedo_color = Color(1, 1, 1, 0)

func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_collect_meshes(child, out)

## Squashes the whole model on production, damage and resource deposits. Held
## off during construction, where _update_construction_rise() is already
## driving the meshes' own Y scale.
func play_squash() -> void:
	if is_under_construction or is_destroyed or _model_roots.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	if now < _next_squash_msec:
		return
	_next_squash_msec = now + SQUASH_COOLDOWN_MSEC
	if _squash_tween and _squash_tween.is_valid():
		_squash_tween.kill()
	_squash_tween = create_tween()
	_squash_tween.set_parallel(true)
	for i in _model_roots.size():
		var root: Node3D = _model_roots[i]
		root.scale = _model_base_scales[i] * SQUASH_SCALE
		_squash_tween.tween_property(root, "scale", _model_base_scales[i], SQUASH_DURATION) \
				.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

## White flash on taking damage. Applied as a material_overlay so it layers on
## top of whatever the surfaces are currently using — the construction ghost
## swaps surface override materials, and this must not fight that.
func play_hit_flash() -> void:
	if _flash_meshes.is_empty():
		return
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_material.albedo_color.a = FLASH_ALPHA
	for mesh in _flash_meshes:
		if is_instance_valid(mesh):
			mesh.material_overlay = _flash_material
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash_material, "albedo_color:a", 0.0, FLASH_DURATION)
	_flash_tween.tween_callback(_clear_hit_flash)

func _clear_hit_flash() -> void:
	for mesh in _flash_meshes:
		if is_instance_valid(mesh):
			mesh.material_overlay = null

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
	if queue.size() >= MAX_QUEUE_SIZE:
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

## Most buildings can't fight back themselves, but any can call nearby units in
## to defend — a Watchtower-style attacker (attack_range > 0) additionally
## fights back on its own via _tick_tower_combat().
func take_damage(amount: int, attacker: Node3D = null) -> void:
	if not is_multiplayer_authority() or is_destroyed:
		return
	## Same shape as Unit.take_damage — see the signal declaration above. A
	## building never recoils (it has no sprite to shove), but the attacker
	## still earns its kill hitstop for levelling one.
	var fatal: bool = current_health - amount <= 0
	var attacker_path: NodePath = NodePath()
	if attacker != null and is_instance_valid(attacker) and attacker.is_inside_tree():
		attacker_path = attacker.get_path()
	damaged.emit(amount, attacker_path, fatal)
	current_health = maxi(current_health - amount, 0)
	health_fraction = float(current_health) / float(maxi(max_health, 1))
	if current_health <= 0:
		_begin_destruction()
		return
	CombatUtils.alert_nearby_allies(get_tree(), global_position, owner_peer_id, attacker)

## --- Combat (only runs when attack_range > 0, e.g. a Watchtower) ---

func _tick_tower_combat(delta: float) -> void:
	_tick_pending_projectiles(delta)

	## Dropping an already-doomed target here, not just an out-of-range one, is
	## what makes a tower re-aim instead of emptying its next shots into a unit
	## the arrows already in the air will finish.
	if attack_target != null and (not _is_attack_target_in_range(attack_target) \
			or not CombatUtils.is_worth_attacking(attack_target)):
		attack_target = null
	_enemy_scan_timer -= delta
	if attack_target == null and _enemy_scan_timer <= 0.0:
		_enemy_scan_timer = _ENEMY_SCAN_INTERVAL
		attack_target = CombatUtils.find_nearest_enemy_unit(get_tree(), global_position, owner_peer_id, attack_range)
	if attack_target == null:
		return

	attack_timer += delta
	if attack_timer < attack_cooldown:
		return
	attack_timer = 0.0
	if projectile_scene != null:
		## Damage lands later, when the shot actually arrives (see
		## _tick_pending_projectiles) — same reasoning as Unit._fire_projectile.
		_fire_projectile(attack_target)
	else:
		attack_target.take_damage(attack_damage, self)
		if not _is_attack_target_in_range(attack_target):
			attack_target = null

func _is_attack_target_in_range(target: Unit) -> bool:
	return is_instance_valid(target) and target.status_activity != Unit.Activity.DEAD \
			and global_position.distance_to(target.global_position) <= attack_range

func _fire_projectile(target: Unit) -> void:
	var dist := global_position.distance_to(target.global_position)
	var travel_time := dist / maxf(projectile_speed, 0.01)
	_pending_projectile_hits.append({
		"time_remaining": travel_time,
		"target": target,
		"damage": attack_damage,
	})
	CombatUtils.reserve_damage(target, attack_damage)
	projectile_fired.emit(target)

## Real, authoritative delayed damage — projectile_fired's visual is purely
## cosmetic and never applies damage itself. Keeps ticking even after
## attack_target changes/clears, so a shot already in the air still lands.
func _tick_pending_projectiles(delta: float) -> void:
	for i in range(_pending_projectile_hits.size() - 1, -1, -1):
		var hit: Dictionary = _pending_projectile_hits[i]
		hit["time_remaining"] -= delta
		if hit["time_remaining"] > 0.0:
			continue
		_pending_projectile_hits.remove_at(i)
		var target: Unit = hit["target"]
		## Released whether the shot lands or the target died first — the
		## reservation only ever covers time in the air.
		CombatUtils.reserve_damage(target, -int(hit["damage"]))
		if is_instance_valid(target) and target.status_activity != Unit.Activity.DEAD:
			target.take_damage(hit["damage"], self)

## Whether a gatherer carrying `type` may unload here — see
## dropoff_resource_types.
func accepts_dropoff(type: ResourceType) -> bool:
	return dropoff_resource_types.is_empty() or dropoff_resource_types.has(type)

## How far NavigationObstacle3D avoidance keeps agents pushed back from this
## building's center; units attacking a building need to account for this so
## they don't try to stand somewhere avoidance will never let them reach.
##
## Covers EVERY obstacle the building has, offset included, not just one named
## node: a structure whose footprint is described by several off-centre
## obstacles (wall_gate's two posts at x = +/-0.85, say) is as wide as its
## furthest obstacle edge, and reading a single one's radius would report a
## 2m-wide gate as a 0.2m pebble — which then under-reports it to the corridor
## scan in main.gd's _find_funnel_point and lets builders and attackers walk far
## closer to it than avoidance will ever actually permit.
func get_footprint_radius() -> float:
	var radius: float = 0.0
	for child in get_children():
		var obstacle := child as NavigationObstacle3D
		if obstacle == null:
			continue
		## Flattened: only the horizontal reach matters to anything that consumes
		## this, and an obstacle raised or sunk on Y is no wider for it.
		var offset: Vector3 = obstacle.position
		offset.y = 0.0
		radius = maxf(radius, offset.length() + obstacle.radius)
	return radius

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

	if attack_range > 0.0:
		_tick_tower_combat(delta)

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

## The see-through version of one surface's material. A team-colored surface
## has to fade its recolored self — swapping in a plain StandardMaterial3D
## would drop both the team color and (since these models keep their art in an
## emission map, not an albedo one) the texture itself, leaving a white box.
func _construction_ghost_for(base: Material) -> Material:
	if base is ShaderMaterial:
		return TeamColorMaterial.to_construction_variant(base, _CONSTRUCTION_ALPHA)
	var ghost: StandardMaterial3D = base.duplicate() if base is StandardMaterial3D else StandardMaterial3D.new()
	ghost.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost.albedo_color.a = _CONSTRUCTION_ALPHA
	## Same render-priority fix as the placement ghost (main.gd) — grass
	## alpha-blends at priority 0 too and would otherwise draw over this.
	ghost.render_priority = 1
	return ghost

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
			mesh_instance.set_surface_override_material(i, _construction_ghost_for(base))
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
