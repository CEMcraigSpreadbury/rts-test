class_name AiPlayer
extends Node
## The brain of one AI player. Host only — created by Main._start_ai_player
## for every AI entry in Network.players, never on a client.
##
## It plays by exactly the rules a human does: every order goes through the
## same Main/BuildingPlacement *_as() entry points a human's RPCs end up in,
## with this AI's own peer id as the sender, so ownership, cost and placement
## checks all apply. The only thing it can do that a human can't is read the
## host's copy of its own state directly instead of from the HUD.
##
## Split into parts that each own one job, run in priority order every think
## (see _think): AiEconomy (houses, villagers, worker jobs), AiBaseBuilder
## (build order, site finding, rally points), AiMilitary (army production),
## AiCombat (defend/attack/abilities), AiResearch (Ruler tree and powers).
## Spending is prioritised through `reserved`: a higher-priority want that
## can't be afforded yet sets its cost aside, and everything after it only
## spends what's left, so the army never starves the next House.

const PROFILES: Array[AiProfile] = [
	preload("res://resources/ai/ai_easy.tres"),
	preload("res://resources/ai/ai_normal.tres"),
	preload("res://resources/ai/ai_hard.tres"),
]
const WOOD: ResourceType = preload("res://resources/wood_resource_type.tres")
const GOLD: ResourceType = preload("res://resources/gold_resource_type.tres")

enum UnitRole { WORKER, INFANTRY, SPEAR, RANGED, CAVALRY, MONSTER }
enum BuildingRole { TOWN_CENTER, HOUSE, MINE, MILITARY, OTHER }

## Raycasts for ground height skip units (layer 3, value 4), same as Main's
## formation drag — a unit standing on a site mustn't read as its ground.
const GROUND_RAY_MASK: int = 0xFFFFFFFF & ~4
## How close to the navmesh a point must be to count as reachable ground.
const NAVMESH_TOLERANCE: float = 0.8

## What this brain is currently trying to do. A skirmish AI is always NORMAL;
## a scenario sets a slot's starting mode and a quest step can change it (see
## SetAiModeAction), which is how "the garrison notices you" works.
enum Mode {
	## Plays the whole game: expands, takes points, attacks where it likes.
	NORMAL,
	## Builds and defends, but never sends a wave out.
	DEFEND,
	## Throws its waves at one place, whatever else is going on.
	ATTACK,
}

var main: Main
var peer_id: int = 0
var profile: AiProfile
var mode: Mode = Mode.NORMAL
## Where ATTACK mode sends its waves.
var attack_position: Vector3 = Vector3.ZERO

var economy: AiEconomy
var builder: AiBaseBuilder
var military: AiMilitary
var combat: AiCombat
var research: AiResearch
## Allied-race build-up (see AiPacts).
var pacts: AiPacts

## --- Refreshed at the start of every think (see _refresh_world) ---
var villagers: Array[Unit] = []
var army: Array[Unit] = []
var my_buildings: Array[ProductionBuilding] = []
## The main-base building everything is planned around, or null once lost.
var town_center: ProductionBuilding = null
var home: Vector3 = Vector3.ZERO
## Middle of the map (average of every spawn point) — "forward" for this base
## is towards it.
var map_centre: Vector3 = Vector3.ZERO
var objectives: Array = []

## ResourceType -> amount set aside this think by wants that couldn't be
## afforded yet. Cleared every think.
var reserved: Dictionary = {}
## Unit orders still allowed this think (profile.max_orders_per_think).
var orders_left: int = 0

## --- Type caches (filled once in setup, or lazily) ---
## BuildingType -> BuildingRole / index in the faction roster / cost.
var building_roles: Dictionary = {}
var building_type_index: Dictionary = {}
var building_costs: Dictionary = {}
## scene_file_path -> BuildingType, to recognise our own placed buildings.
var building_type_by_scene: Dictionary = {}
## Unit scene_file_path -> {costs, population_cost, role, strength}
var _unit_info: Dictionary = {}

var _think_timer: float = 0.0
## Seconds of match time this brain has been running — stops while paused,
## unlike the wall clock. What every AI timer is measured against.
var game_time: float = 0.0

func setup(p_main: Main, p_peer_id: int, difficulty: int) -> void:
	main = p_main
	peer_id = p_peer_id
	profile = PROFILES[clampi(difficulty, 0, PROFILES.size() - 1)]
	economy = AiEconomy.new(self)
	builder = AiBaseBuilder.new(self)
	military = AiMilitary.new(self)
	combat = AiCombat.new(self)
	research = AiResearch.new(self)
	pacts = AiPacts.new(self)

func _ready() -> void:
	var faction: Faction = main.faction_by_peer.get(peer_id)
	if faction != null:
		for i in faction.building_types.size():
			var type: BuildingType = faction.building_types[i]
			if type.scene == null or type.is_wall or type.is_gate_tool:
				continue
			building_type_index[type] = i
			building_costs[type] = type.get_costs()
			building_type_by_scene[type.scene.resource_path] = type
			building_roles[type] = _role_of_building_type(type)
	var spawn_sum := Vector3.ZERO
	var spawns: Array[Node] = main.player_spawn_points.get_children()
	for spawn in spawns:
		spawn_sum += (spawn as Node3D).global_position
	map_centre = spawn_sum / maxf(spawns.size(), 1.0)
	objectives = get_tree().get_nodes_in_group(&"objectives")
	## Several AIs thinking on the same frame would stack their cost there.
	_think_timer = randf() * profile.think_interval

func _physics_process(delta: float) -> void:
	if main.game_over or not main.is_peer_active(peer_id):
		return
	game_time += delta
	_think_timer -= delta
	if _think_timer > 0.0:
		return
	_think_timer = profile.think_interval
	_think()

func _think() -> void:
	_refresh_world()
	if my_buildings.is_empty():
		return
	reserved.clear()
	orders_left = profile.max_orders_per_think
	## Spending, most important first — see `reserved`. The build order goes
	## ahead of villagers: villagers are always affordable soon, so letting
	## them go first would put off every building until the villager target
	## was reached. Villagers and soldiers take turns being first by how the
	## army is keeping up (AiProfile.army_per_villager), for the same reason.
	economy.think_houses()
	builder.think()
	## Early on the economy comes first whatever the army ratio says — soldiers
	## bought with the wood for villagers 6-10 cost the whole game.
	var economy_started: bool = villagers.size() >= int(profile.target_villagers * profile.economy_first_share)
	if economy_started and army.size() < villagers.size() * profile.army_per_villager:
		military.think()
		economy.think_villagers()
	else:
		economy.think_villagers()
		military.think()
	## Fighting before worker jobs, so villagers told to flee aren't handed
	## a tree in the same breath.
	combat.think()
	## After combat, so powers are aimed off this think's view of the enemy.
	research.think()
	## Last of the spenders: a Pact is what an AI does with a surplus, never
	## at the cost of its opening build order.
	pacts.think()
	## Orders last, so builders picked above aren't also handed a tree.
	economy.think_workers()

func _refresh_world() -> void:
	villagers.clear()
	army.clear()
	for child in main.units_root.get_children():
		var unit := child as Unit
		if unit == null or unit.owner_peer_id != peer_id or unit.status_activity == Unit.Activity.DEAD:
			continue
		if unit.can_gather:
			villagers.append(unit)
		elif unit.can_fight:
			army.append(unit)
	my_buildings.clear()
	town_center = null
	for node in get_tree().get_nodes_in_group("buildings"):
		var building := node as ProductionBuilding
		if building == null or building.owner_peer_id != peer_id or building.is_destroyed:
			continue
		my_buildings.append(building)
		if building.is_main_base and not building.is_under_construction and town_center == null:
			town_center = building
	if town_center != null:
		home = town_center.global_position
	elif not my_buildings.is_empty():
		home = my_buildings[0].global_position

## --- Spending ---

func stock(type: ResourceType) -> int:
	return ResourceStockpile.get_amount(peer_id, type)

## Affordable out of what hasn't been set aside for something more important.
func can_afford(costs: Array[ResourceCost]) -> bool:
	for cost in costs:
		if stock(cost.resource_type) - int(reserved.get(cost.resource_type, 0)) < cost.amount:
			return false
	return true

func reserve(costs: Array[ResourceCost]) -> void:
	for cost in costs:
		reserved[cost.resource_type] = int(reserved.get(cost.resource_type, 0)) + cost.amount

## --- Orders (all through Main's *_as entry points) ---

func use_order() -> bool:
	if orders_left <= 0:
		return false
	orders_left -= 1
	return true

## Gather a resource, build a site, attack something — whatever a right-click
## on `target` would mean.
## `units` is a plain Array of Unit so callers can pass a literal like [unit].
func order_target(units: Array, target: Node3D) -> void:
	if units.is_empty() or not is_instance_valid(target):
		return
	main.issue_command_as(peer_id, _paths(units), target.get_path(), target.global_position, false, false)

## `append` queues it after the units' current order, like a shift-click.
func order_move(units: Array, pos: Vector3, attack_move: bool = false, append: bool = false) -> void:
	if units.is_empty():
		return
	main.issue_command_as(peer_id, _paths(units), NodePath(), pos, attack_move, append)

func group_centroid(units: Array) -> Vector3:
	var sum := Vector3.ZERO
	var count := 0
	for unit in units:
		if is_instance_valid(unit):
			sum += unit.global_position
			count += 1
	return sum / count if count > 0 else home

func _paths(units: Array) -> Array[NodePath]:
	var paths: Array[NodePath] = []
	for unit in units:
		if is_instance_valid(unit):
			paths.append(unit.get_path())
	return paths

## --- World queries ---

## The ground under (pos.x, pos.z), or null over nothing.
func ground_at(pos: Vector3) -> Variant:
	var space := main.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(Vector3(pos.x, 60.0, pos.z), Vector3(pos.x, -30.0, pos.z), GROUND_RAY_MASK)
	var hit := space.intersect_ray(query)
	if hit.is_empty() or hit.collider is ProductionBuilding or hit.collider is Gatherable:
		return null
	return hit.position

## Judged sideways: the navmesh floats a little above the ground it covers.
func on_navmesh(pos: Vector3) -> bool:
	if not nav_ready():
		return false
	var closest := nearest_navmesh_point(pos)
	return Vector2(closest.x - pos.x, closest.z - pos.z).length() <= NAVMESH_TOLERANCE \
			and absf(closest.y - pos.y) <= 2.0

## The navmesh only exists from its first sync, a frame or so into the match;
## queries before then error and answer nonsense.
func nav_ready() -> bool:
	return NavigationServer3D.map_get_iteration_id(main.get_world_3d().navigation_map) > 0

## Ready, and not part-way through a re-bake (see NavigationBlockers) — what
## a verdict that gets remembered should wait for.
func nav_settled() -> bool:
	if not nav_ready():
		return false
	var blockers := main.get_node_or_null(^"NavigationBlockers") as NavigationBlockers
	return blockers == null or not blockers.is_baking()

## `pos` itself until the navmesh is ready.
func nearest_navmesh_point(pos: Vector3) -> Vector3:
	if not nav_ready():
		return pos
	return NavigationServer3D.map_get_closest_point(main.get_world_3d().navigation_map, pos)

## Whether a unit at `origin` (home by default) could actually walk to
## within `tolerance` of `pos` — on the navmesh isn't enough, it could be a
## cut-off plateau. False until the navmesh is ready.
func is_reachable(pos: Vector3, tolerance: float, origin: Variant = null) -> bool:
	if not nav_ready():
		return false
	var nav_map: RID = main.get_world_3d().navigation_map
	var from: Vector3 = origin if origin != null else _reach_origin()
	var path: PackedVector3Array = NavigationServer3D.map_get_path(nav_map, nearest_navmesh_point(from), pos, true)
	if path.is_empty():
		return false
	var end: Vector3 = path[path.size() - 1]
	return Vector2(end.x - pos.x, end.z - pos.z).length() <= tolerance

## Where "can a villager get there from home" paths start: the Town Center's
## drop-off point, just outside its footprint. Not its centre — that sits in
## the hole the building carves out of the navmesh, and the navmesh point
## nearest to it can be a scrap cut off from the rest of the map, which makes
## nearly everything look unreachable.
func _reach_origin() -> Vector3:
	if town_center != null:
		var dropoff: Node3D = town_center.get_node_or_null("DropoffPoint")
		if dropoff != null:
			return dropoff.global_position
	return home

## Direction from the map's middle out to this base (flattened) — "behind".
func away_from_centre() -> Vector3:
	var away := home - map_centre
	away.y = 0.0
	return away.normalized() if away.length_squared() > 0.01 else Vector3.BACK

## Somewhere a villager shouldn't wander: near a capture point this AI
## doesn't own (guards, or someone else's army), or nearer another player's
## Town Center than our own.
func is_dangerous(pos: Vector3) -> bool:
	for objective in objectives:
		if is_instance_valid(objective) and Teams.is_enemy(peer_id, objective.owner_peer_id) \
				and objective.global_position.distance_to(pos) < DANGER_RADIUS_OBJECTIVE:
			return true
	var my_distance: float = pos.distance_to(home)
	for other_peer in main.town_centers:
		if other_peer == peer_id:
			continue
		## Untyped: a razed Town Center is freed but stays in town_centers.
		var tc = main.town_centers[other_peer]
		if is_instance_valid(tc) and not tc.is_destroyed and tc.global_position.distance_to(pos) < my_distance:
			return true
	return false

const DANGER_RADIUS_OBJECTIVE: float = 14.0

## --- Type info ---

func building_role(building: ProductionBuilding) -> BuildingRole:
	var type: BuildingType = building_type_by_scene.get(building.scene_file_path)
	if type != null:
		return building_roles[type]
	## Not from our own roster — a captured objective's building.
	if building.is_main_base:
		return BuildingRole.TOWN_CENTER
	for item in building.producibles:
		if item.kind == ProducibleItem.Kind.UNIT and item.unit_scene != null and unit_role_of_scene(item.unit_scene) != UnitRole.WORKER:
			return BuildingRole.MILITARY
	return BuildingRole.OTHER

func unit_role_of_scene(scene: PackedScene) -> UnitRole:
	return _unit_info_for(scene).role

## Full-health fighting worth of what `scene` trains (see AiCombat.unit_strength).
func unit_strength_of_scene(scene: PackedScene) -> float:
	return _unit_info_for(scene).strength

func item_costs(item: ProducibleItem) -> Array[ResourceCost]:
	if item.kind == ProducibleItem.Kind.UNIT and item.unit_scene != null:
		return _unit_info_for(item.unit_scene).costs
	return item.costs

static func unit_role(unit: Unit) -> UnitRole:
	if unit.can_gather:
		return UnitRole.WORKER
	if unit.population_cost >= 3 or unit.scene_file_path.contains("/monsters/"):
		return UnitRole.MONSTER
	if unit.unit_category == Unit.UnitCategory.CAVALRY:
		return UnitRole.CAVALRY
	if unit.projectile_scene != null or unit.unit_category == Unit.UnitCategory.ARCHER:
		return UnitRole.RANGED
	if unit.damage_type == Unit.DamageType.SPEAR:
		return UnitRole.SPEAR
	return UnitRole.INFANTRY

## Instantiates the scene once, off-tree (same trick as ProducibleItem.
## get_costs), and remembers what it needs.
func _unit_info_for(scene: PackedScene) -> Dictionary:
	var path: String = scene.resource_path
	if not _unit_info.has(path):
		var temp: Unit = scene.instantiate()
		var costs: Array[ResourceCost] = temp.costs
		_unit_info[path] = {costs = costs, population_cost = temp.population_cost, role = unit_role(temp),
				strength = float(temp.max_health) * float(temp.attack_damage) / maxf(temp.attack_cooldown, 0.2)}
		temp.free()
	return _unit_info[path]

func _role_of_building_type(type: BuildingType) -> BuildingRole:
	if type.requires_deposit:
		return BuildingRole.MINE
	var temp = type.scene.instantiate()
	var role := BuildingRole.OTHER
	if temp is ProductionBuilding:
		var building: ProductionBuilding = temp
		if building.is_main_base:
			role = BuildingRole.TOWN_CENTER
		elif building.population_capacity > 0 and building.producibles.is_empty():
			role = BuildingRole.HOUSE
		else:
			for item in building.producibles:
				if item.kind == ProducibleItem.Kind.UNIT and item.unit_scene != null \
						and unit_role_of_scene(item.unit_scene) not in [UnitRole.WORKER, UnitRole.MONSTER]:
					role = BuildingRole.MILITARY
					break
	temp.free()
	return role

## Every UnitRole the building type can train (empty for non-producers).
func roles_trained_by_type(type: BuildingType) -> Array:
	var temp = type.scene.instantiate()
	var roles: Array = []
	if temp is ProductionBuilding:
		for item in temp.producibles:
			if item.kind == ProducibleItem.Kind.UNIT and item.unit_scene != null:
				var role := unit_role_of_scene(item.unit_scene)
				if not roles.has(role):
					roles.append(role)
	temp.free()
	return roles

func types_with_role(role: BuildingRole) -> Array[BuildingType]:
	var out: Array[BuildingType] = []
	for type in building_roles:
		if building_roles[type] == role:
			out.append(type)
	return out

## Our buildings (built or still going up) placed from `type`, not counting
## construction sites given up on (see AiBaseBuilder.is_abandoned).
func count_owned(type: BuildingType) -> int:
	var count := 0
	for building in my_buildings:
		if building.scene_file_path == type.scene.resource_path and not builder.is_abandoned(building):
			count += 1
	return count
