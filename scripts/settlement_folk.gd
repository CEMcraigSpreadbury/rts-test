class_name SettlementFolk
extends Node3D

## A settlement's townsfolk: tiny peg people, one per cottage and one per slot
## building, painted in the owner's colour. Purely cosmetic and local to each
## peer — nothing here is sent anywhere, and nothing reads it back. The whole
## crowd is one MultiMesh (plus one for what they carry), and it stops moving
## (and drawing) whenever nobody could see it: off-screen, under fog, or with
## the camera pulled far out.
##
## Cottage folk run errands to the hall and the slot buildings and stop to
## chat; a Granary, Market or Lumberyard's peg carries its goods to the hall;
## a military building's peg drills on the spot. Everyone runs indoors while
## enemies are about and some of them stay in at night. Cottages smoke, a
## lantern by each door glows after dark, and a close camera hears the square.

const BODY_RADIUS: float = 0.18
const BODY_HEIGHT: float = 0.6
const HEAD_RADIUS: float = 0.17
const HEAD_Y: float = 0.75
## Out past this the pegs are too small to read, so they aren't drawn at all.
const DRAW_DISTANCE: float = 60.0
const REFRESH_SECONDS: float = 2.0
## Clearance kept between a peg and anything standing in the square.
const STAND_GAP: float = 0.5
const DETOUR_GAP: float = 0.8
## Fallbacks when a building has no footprint to read.
const HOUSE_RADIUS: float = 1.3
const SLOT_RADIUS: float = 2.5
const HALL_RADIUS: float = 3.0

const HOP_HEIGHT: float = 0.18
const HOP_TIME: float = 0.3
const HOP_GAP := Vector2(2.0, 6.0)
const TURN_GAP := Vector2(2.5, 7.0)
const TURN_SPEED: float = 2.5
const WALK_SPEED: float = 1.3
const RUN_SPEED: float = 3.2
## One little hop per this many metres walked.
const STRIDE: float = 0.35
const STRIDE_HEIGHT: float = 0.08
const POP_TIME: float = 0.15

const IDLE_TIME := Vector2(4.0, 12.0)
const PAUSE_TIME := Vector2(2.0, 4.0)
const CHAT_TIME := Vector2(3.0, 5.0)
const CHAT_BEAT: float = 0.5
const CHAT_CHANCE: float = 0.25
## A chat's two pegs meet halfway, unless that is a long way off.
const CHAT_MAX_SPAN: float = 14.0
const CHAT_WAIT: float = 10.0
const CARRIER_REST := Vector2(2.0, 5.0)
const DRILL_BEAT: float = 0.8

## How far past the capture ring an enemy sends everyone indoors, how often
## that is looked for, and how long the coast stays clear before they return.
const THREAT_MARGIN: float = 3.0
const THREAT_CHECK: float = 0.5
const ALL_CLEAR: float = 3.0
const NIGHT_FROM: float = 0.5
## Share of folk who go home for the night.
const NIGHT_HOMEBODIES: float = 0.5

## Chimney smoke: puffs per chimney, how long one lasts, how high it climbs,
## and the share of cottages with a fire going.
const PUFFS: int = 6
const PUFF_LIFE: float = 3.2
const PUFF_RISE: float = 2.4
const PUFF_SIZE := Vector2(0.14, 0.5)
const PUFF_ALPHA: float = 0.55
## How far a puff drifts sideways per metre it rises, each chimney its own way.
const SMOKE_DRIFT: float = 0.55
const SMOKING_SHARE: float = 0.65
## Door lanterns: beside each cottage door, lit by how dark it is.
const LANTERN_SIDE: float = 0.8
const LANTERN_HEIGHT: float = 1.1
const LANTERN_GLOW: float = 3.0
## The square's sounds, only with the camera close in: one every so often,
## picked by who is about.
const MURMUR_GAP := Vector2(8.0, 16.0)
const MURMUR_REACH: float = 25.0
const MURMUR_MAX_ZOOM: float = 22.0
const MURMUR_DB: float = 0.0

enum Role { FOLK, CARRIER, DRILL, SENTRY }
enum State { IDLE, WALK, PAUSE, WAIT, CHAT, HIDING, HIDDEN }
enum Prop { NONE, SACK, LOG, CRATE, POLE }

## Each people's head colour (bodies wear the owner's colour).
const HEAD_COLOURS: Dictionary = {
	"Human": Color(0.93, 0.76, 0.62),
	"Dark Elves": Color(0.62, 0.6, 0.78),
	"Star Wanderers": Color(0.6, 0.85, 0.9),
	"Beastmen": Color(0.6, 0.45, 0.32),
}
const DEFAULT_HEAD := Color(0.93, 0.76, 0.62)
## Prop -> [size, colour, height above the feet].
const PROPS: Dictionary = {
	Prop.SACK: [Vector3(0.32, 0.26, 0.32), Color(0.82, 0.7, 0.45), 1.05],
	Prop.LOG: [Vector3(0.8, 0.16, 0.16), Color(0.5, 0.33, 0.18), 1.0],
	Prop.CRATE: [Vector3(0.3, 0.24, 0.3), Color(0.95, 0.75, 0.25), 1.04],
	Prop.POLE: [Vector3(0.06, 1.0, 0.06), Color(0.55, 0.4, 0.25), 0.5],
}
const CARRIED: Dictionary = {
	Objective.GRANARY: Prop.SACK,
	Objective.LUMBERYARD: Prop.LOG,
	Objective.MARKET: Prop.CRATE,
}

class Peg:
	var home: Vector3
	var role: int = Role.FOLK
	var prop: int = Prop.NONE
	var carrying: bool = false
	var state: int = State.IDLE
	var pos: Vector3
	var yaw: float = 0.0
	var yaw_target: float = 0.0
	var path: Array[Vector3] = []
	var running: bool = false
	## What happens on arriving: the state to take up.
	var arrive: int = State.PAUSE
	var until: float = 0.0
	var hop_at: float = 0.0
	var hops_left: int = 0
	var turn_at: float = 0.0
	var stride: float = 0.0
	var partner: Peg = null
	var chat_lead: bool = false
	## 1 drawn, 0 popped indoors.
	var pop: float = 1.0
	var homebody: bool = false
	var beat: int = 0

static var _peg_meshes: Dictionary = {}
static var _prop_mesh: BoxMesh = null
static var _puff_mesh: SphereMesh = null
static var _lantern_mesh: ArrayMesh = null
static var _lamp_material: StandardMaterial3D = null
static var _lamp_frame: int = -1

var _settlement: Objective
var _mmi: MultiMeshInstance3D
var _props: MultiMeshInstance3D
var _notifier: VisibleOnScreenNotifier3D
var _smoke: MultiMeshInstance3D
var _lanterns: MultiMeshInstance3D
## [where (settlement space), phase, drift] per smoking chimney.
var _chimneys: Array[Array] = []
var _murmur_at: float = 0.0
var _rng := RandomNumberGenerator.new()
var _pegs: Array[Peg] = []
var _homes: Array[Vector3] = []
## {c: Vector3 (flat), r: float} for the hall, cottages and slot buildings.
var _obstacles: Array[Dictionary] = []
var _hall_radius: float = HALL_RADIUS
var _has_hall: bool = false
var _hall_c: Vector3 = Vector3.ZERO
var _tint: Color = Color.TRANSPARENT
var _tier: int = -1
var _time: float = 0.0
var _refresh_timer: float = 0.0
var _threat_timer: float = 0.0
var _threatened: bool = false
var _clear_for: float = 0.0
var _night: bool = false

func _init(settlement: Objective) -> void:
	_settlement = settlement
	name = "Folk"

func _ready() -> void:
	_rng.seed = hash(Vector2i(roundi(_settlement.global_position.x), roundi(_settlement.global_position.z)))
	var reach: float = Objective.HOUSE_RING.y + 2.0
	var bounds := AABB(Vector3(-reach, -1.0, -reach), Vector3(reach * 2.0, 3.5, reach * 2.0))
	_mmi = _make_crowd(_peg_mesh(_settlement.race_name), bounds)
	if _prop_mesh == null:
		_prop_mesh = BoxMesh.new()
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.roughness = 0.6
		_prop_mesh.material = material
	_props = _make_crowd(_prop_mesh, bounds)
	if _puff_mesh == null:
		_puff_mesh = SphereMesh.new()
		_puff_mesh.radius = 1.0
		_puff_mesh.height = 2.0
		_puff_mesh.radial_segments = 8
		_puff_mesh.rings = 4
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.roughness = 1.0
		_puff_mesh.material = material
	_smoke = _make_crowd(_puff_mesh, AABB(bounds.position, bounds.size + Vector3(0.0, PUFF_RISE + 2.0, 0.0)))
	## Lanterns are fixtures: shown wherever the map is explored, like the
	## cottages, rather than only while the square is in plain sight.
	_lanterns = MultiMeshInstance3D.new()
	_lanterns.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lanterns.multimesh = MultiMesh.new()
	_lanterns.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_lanterns.multimesh.mesh = _lantern()
	_lanterns.visibility_range_end = DRAW_DISTANCE * 2.0
	_lanterns.add_to_group(&"fog_static_props")
	add_child(_lanterns)
	_murmur_at = _rng.randf_range(0.0, MURMUR_GAP.y)
	_notifier = VisibleOnScreenNotifier3D.new()
	_notifier.aabb = bounds
	add_child(_notifier)
	refresh()

## The crowd moves, so the engine's culling box is set to the whole square.
func _make_crowd(mesh: Mesh, bounds: AABB) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	mmi.multimesh = multimesh
	mmi.custom_aabb = bounds
	add_child(mmi)
	return mmi

func _process(delta: float) -> void:
	_light_lamps()
	if not _can_be_seen():
		_mmi.visible = false
		_props.visible = false
		_smoke.visible = false
		return
	if not _mmi.visible:
		_mmi.visible = true
		_props.visible = true
		_smoke.visible = true
		refresh()
	_refresh_timer += delta
	if _refresh_timer >= REFRESH_SECONDS:
		refresh()
	_time += delta
	_watch_for_trouble(delta)
	for peg in _pegs:
		_think(peg, delta)
	_draw_pegs()
	_draw_smoke()
	_murmur()

func _can_be_seen() -> bool:
	if not _notifier.is_on_screen():
		return false
	var camera := get_viewport().get_camera_3d()
	if camera == null or camera.global_position.distance_to(global_position) > DRAW_DISTANCE:
		return false
	var fog := _main_field(&"fog_of_war") as FogOfWar
	return fog == null or fog.is_visible_at(global_position)

func _main_field(field: StringName) -> Object:
	var main := get_tree().current_scene
	return main.get(field) if main != null and field in main else null

## --- Who lives here ---

## Re-reads where everyone lives and what colour they wear. Pegs whose home
## still stands keep their place and whatever they were doing; new homes get
## a fresh peg.
func refresh() -> void:
	_refresh_timer = 0.0
	var found := _find_homes()
	var homes: Array[Vector3] = []
	for entry in found:
		homes.append(entry.home)
	var recolour: bool = false
	if homes != _homes:
		var kept: Array[Peg] = []
		for entry in found:
			var peg: Peg = null
			for old in _pegs:
				if old.home == entry.home:
					peg = old
					break
			if peg == null:
				peg = _new_peg(entry.home, entry.role, entry.prop)
			kept.append(peg)
		for old in _pegs:
			if not kept.has(old) and old.partner != null:
				old.partner.partner = null
		_pegs = kept
		_homes = homes
		_place_fixtures()
		_mmi.multimesh.instance_count = _pegs.size()
		_props.multimesh.instance_count = _pegs.size()
		recolour = true
	var tint: Color = _settlement.owner_tint()
	if tint != _tint or recolour:
		## A new owner's people celebrate (not a fresh crowd's first paint).
		if tint != _tint and _tint != Color.TRANSPARENT:
			_hop_everyone(1)
		_tint = tint
		for i in _pegs.size():
			_mmi.multimesh.set_instance_color(i, tint)
	if _tier >= 0 and _settlement.tier > _tier:
		_hop_everyone(2)
	_tier = _settlement.tier
	for i in _pegs.size():
		var prop: int = _pegs[i].prop
		if prop != Prop.NONE:
			_props.multimesh.set_instance_color(i, PROPS[prop][1])
	_draw_pegs()

## [{home, role, prop}]: a peg before each cottage (towards the square), then
## one beside each slot building. Also lays out what pegs walk around.
func _find_homes() -> Array[Dictionary]:
	_obstacles.clear()
	_has_hall = false
	var found: Array[Dictionary] = []
	if _settlement.razed:
		return found
	var hall := _settlement.hall
	if hall != null and is_instance_valid(hall):
		var r: float = hall.get_footprint_radius()
		_hall_radius = r if r > 0.0 else HALL_RADIUS
		_obstacles.append({c = _flat(_settlement.to_local(hall.global_position)), r = _hall_radius})
		_has_hall = true
		_hall_c = _obstacles[0].c
	var first_house: int = _obstacles.size()
	var houses: Array[Vector3] = []
	for house in _settlement._houses:
		if is_instance_valid(house):
			var c := _flat(house.position)
			_obstacles.append({c = c, r = _house_radius(house)})
			houses.append(c)
	var slots: Array[ProductionBuilding] = []
	for node in get_tree().get_nodes_in_group(&"buildings"):
		var building := node as ProductionBuilding
		if building == null or building.settlement != _settlement or building.is_destroyed \
				or building == hall or building.get_meta(&"wall_piece", false):
			continue
		var r: float = building.get_footprint_radius()
		_obstacles.append({c = _flat(_settlement.to_local(building.global_position)), r = r if r > 0.0 else SLOT_RADIUS})
		slots.append(building)
	for i in houses.size():
		var c: Vector3 = houses[i]
		found.append({home = _stand_point(c, _obstacles[first_house + i].r, [-c]), role = Role.FOLK, prop = Prop.NONE})
	var first_slot: int = _obstacles.size() - slots.size()
	for i in slots.size():
		var building := slots[i]
		var o: Dictionary = _obstacles[first_slot + i]
		var c: Vector3 = o.c
		var side := Vector3(-c.z, 0.0, c.x)
		var role: int = Role.SENTRY
		var prop: int = Prop.NONE
		if CARRIED.has(building.building_name):
			role = Role.CARRIER
			prop = CARRIED[building.building_name]
		elif building.slot_kind >= 0:
			role = Role.DRILL
			prop = Prop.POLE
		found.append({home = _stand_point(c, o.r, [side, -side, -c]), role = role, prop = prop})
	return found

## How far a cottage (or a City's landmark) reaches, off its drawn meshes.
func _house_radius(house: Node3D) -> float:
	if house.has_meta(&"folk_radius"):
		return house.get_meta(&"folk_radius")
	var reach: float = 0.0
	var top: float = 0.0
	for node in house.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var box: AABB = house.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()
		top = maxf(top, box.end.y)
		for corner in [box.position, box.end, Vector3(box.position.x, 0.0, box.end.z), Vector3(box.end.x, 0.0, box.position.z)]:
			reach = maxf(reach, Vector2(corner.x, corner.z).length())
	## Corners overstate a round hut; the house is rebuilt (and re-measured)
	## whenever it changes.
	var r: float = reach * 0.8 if reach > 0.0 else HOUSE_RADIUS
	house.set_meta(&"folk_radius", r)
	house.set_meta(&"folk_top", top if top > 0.0 else 2.0)
	return r

## Just outside `c`'s footprint, along the first direction that isn't inside
## something else.
func _stand_point(c: Vector3, r: float, directions: Array) -> Vector3:
	for dir in directions:
		var d: Vector3 = dir
		if d.length_squared() < 0.0001:
			continue
		var p: Vector3 = c + d.normalized() * (r + STAND_GAP)
		if not _blocked_at(p):
			return p
	var first: Vector3 = directions[0]
	return c + first.normalized() * (r + STAND_GAP) if first.length_squared() > 0.0001 else c

func _blocked_at(p: Vector3) -> bool:
	for o in _obstacles:
		if p.distance_to(o.c) < o.r + 0.1:
			return true
	return false

static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)

func _new_peg(home: Vector3, role: int, prop: int) -> Peg:
	var peg := Peg.new()
	peg.home = home
	peg.pos = home
	peg.role = role
	peg.prop = prop
	peg.yaw = _face(home, Vector3.ZERO) + _rng.randf_range(-0.6, 0.6)
	peg.yaw_target = peg.yaw
	peg.homebody = role == Role.FOLK and _rng.randf() < NIGHT_HOMEBODIES
	peg.hop_at = _time + _rng.randf_range(0.0, HOP_GAP.y)
	peg.turn_at = _time + _rng.randf_range(0.0, TURN_GAP.y)
	peg.until = _time + _rng.randf_range(0.0, IDLE_TIME.y)
	return peg

## The yaw that faces from `from` towards `to` (a peg looks down -Z).
static func _face(from: Vector3, to: Vector3) -> float:
	var d := to - from
	return atan2(-d.x, -d.z)

func _hop_everyone(hops: int) -> void:
	for peg in _pegs:
		if peg.state != State.HIDDEN:
			peg.hops_left = hops
			peg.hop_at = _time + _rng.randf_range(0.0, 0.25)

## --- Trouble and night ---

## Anyone hostile near the square sends the whole settlement indoors; they come
## out again once it has been clear for a moment. Night keeps the homebodies in.
func _watch_for_trouble(delta: float) -> void:
	_threat_timer -= delta
	if _threat_timer <= 0.0:
		_threat_timer = THREAT_CHECK
		var threatened := _enemy_near()
		if threatened:
			_clear_for = 0.0
		if threatened and not _threatened:
			for peg in _pegs:
				_send_indoors(peg)
		_threatened = threatened
		var day_night := _main_field(&"day_night") as DayNight
		_night = day_night != null and day_night.night_amount >= NIGHT_FROM
	if not _threatened:
		_clear_for += delta
	var calm: bool = not _threatened and _clear_for >= ALL_CLEAR
	for peg in _pegs:
		var stays_in: bool = not calm or (_night and peg.homebody)
		if stays_in and peg.state != State.HIDING and peg.state != State.HIDDEN and calm:
			_send_indoors(peg)
		## Staggered, so a settlement doesn't refill in one frame.
		elif not stays_in and peg.state == State.HIDDEN and _rng.randf() < delta * 1.5:
			peg.state = State.IDLE
			peg.pos = peg.home
			peg.until = _time + _rng.randf_range(IDLE_TIME.x, IDLE_TIME.y) * 0.5
			peg.hops_left = 1
			peg.hop_at = _time + POP_TIME

func _enemy_near() -> bool:
	if ArmyBridge.current == null:
		return false
	var owner_id: int = _settlement.owner_peer_id
	for unit in ArmyBridge.current.units_in_circle(global_position, _settlement.capture_radius() + THREAT_MARGIN):
		if unit.status_activity == Unit.Activity.DEAD or not unit.can_fight or unit.owner_peer_id <= 0:
			continue
		if owner_id <= 0 or Teams.is_enemy(unit.owner_peer_id, owner_id):
			return true
	return false

func _send_indoors(peg: Peg) -> void:
	_end_chat(peg)
	peg.carrying = false
	peg.running = _threatened
	_walk(peg, peg.home, State.HIDING)

## --- What each peg does ---

func _think(peg: Peg, delta: float) -> void:
	match peg.state:
		State.WALK:
			_step(peg, delta)
		State.HIDING:
			if peg.path.is_empty():
				peg.pop = move_toward(peg.pop, 0.0, delta / POP_TIME)
				if peg.pop <= 0.0:
					peg.state = State.HIDDEN
			else:
				_step(peg, delta)
		State.HIDDEN:
			peg.pop = 0.0
		State.PAUSE:
			if _time >= peg.until:
				_after_pause(peg)
		State.WAIT:
			if peg.partner == null or _time >= peg.until:
				_end_chat(peg)
				_go_home(peg)
			elif peg.partner.state == State.WAIT:
				_start_chat(peg)
		State.CHAT:
			_chat(peg)
		State.IDLE:
			_idle(peg)
	if peg.state != State.HIDING and peg.state != State.HIDDEN:
		peg.pop = move_toward(peg.pop, 1.0, delta / POP_TIME)
	var turn_speed: float = TURN_SPEED * (2.0 if peg.state == State.WALK else 1.0)
	peg.yaw = lerp_angle(peg.yaw, peg.yaw_target, minf(1.0, turn_speed * delta))

func _idle(peg: Peg) -> void:
	match peg.role:
		Role.DRILL:
			_drill(peg)
			return
		Role.CARRIER:
			if _time >= peg.until and _hall_exists():
				peg.carrying = true
				_walk(peg, _hall_stand(peg.home), State.PAUSE)
				return
	if _time >= peg.turn_at:
		peg.turn_at = _time + _rng.randf_range(TURN_GAP.x, TURN_GAP.y)
		peg.yaw_target = peg.yaw + _rng.randf_range(-1.6, 1.6)
	if peg.hops_left <= 0 and _time >= peg.hop_at:
		peg.hops_left = 1
	if peg.role != Role.FOLK or _time < peg.until:
		return
	if _night:
		peg.until = _time + _rng.randf_range(IDLE_TIME.x, IDLE_TIME.y)
		return
	if _rng.randf() < CHAT_CHANCE and _try_chat(peg):
		return
	var spots: Array[Vector3] = []
	if _hall_exists():
		spots.append(_hall_stand(peg.home))
		spots.append(_hall_stand(peg.home))
	for other in _pegs:
		if other != peg and other.role != Role.FOLK:
			spots.append(other.home)
	if spots.is_empty():
		peg.until = _time + _rng.randf_range(IDLE_TIME.x, IDLE_TIME.y)
		return
	_walk(peg, spots[_rng.randi() % spots.size()], State.PAUSE)

## Done standing about at the far end of an errand (or a carrier dropping
## off): back home.
func _after_pause(peg: Peg) -> void:
	## A carrier has delivered at the hall.
	peg.carrying = false
	_go_home(peg)

func _go_home(peg: Peg) -> void:
	if peg.pos.distance_to(peg.home) < 0.1:
		_settle(peg)
		return
	_walk(peg, peg.home, State.IDLE)

func _settle(peg: Peg) -> void:
	peg.state = State.IDLE
	peg.pos = peg.home
	peg.until = _time + _rng.randf_range(IDLE_TIME.x, IDLE_TIME.y)
	if peg.role == Role.CARRIER:
		peg.until = _time + _rng.randf_range(CARRIER_REST.x, CARRIER_REST.y)
	peg.yaw_target = _face(peg.home, Vector3.ZERO)

## On the spot, in time: a hop on every beat, a quarter turn every fourth.
func _drill(peg: Peg) -> void:
	var beat: int = int(_time / DRILL_BEAT)
	if beat == peg.beat:
		return
	peg.beat = beat
	peg.hops_left = 1
	peg.hop_at = _time
	if beat % 4 == 0:
		peg.yaw_target = peg.yaw_target + PI * 0.5 * (1.0 if beat % 8 == 0 else -1.0)

func _hall_exists() -> bool:
	return _has_hall

## A spot at the hall's edge on the side facing `from`, a little scattered so
## visitors don't stack up.
func _hall_stand(from: Vector3) -> Vector3:
	var hall_c: Vector3 = _hall_c
	var dir := (from - hall_c).rotated(Vector3.UP, _rng.randf_range(-0.35, 0.35))
	return _stand_point(hall_c, _hall_radius, [dir, dir.rotated(Vector3.UP, 0.8), dir.rotated(Vector3.UP, -0.8)])

## --- Chatting ---

func _try_chat(peg: Peg) -> bool:
	var candidates: Array[Peg] = []
	for other in _pegs:
		if other != peg and other.role == Role.FOLK and other.state == State.IDLE and other.partner == null \
				and other.home.distance_to(peg.home) <= CHAT_MAX_SPAN:
			candidates.append(other)
	if candidates.is_empty():
		return false
	var other: Peg = candidates[_rng.randi() % candidates.size()]
	var middle: Vector3 = (peg.home + other.home) * 0.5
	var across: Vector3 = (other.home - peg.home).normalized() * 0.45
	if _blocked_at(middle - across) or _blocked_at(middle + across):
		return false
	peg.partner = other
	other.partner = peg
	peg.chat_lead = true
	other.chat_lead = false
	_walk(peg, middle - across, State.WAIT)
	_walk(other, middle + across, State.WAIT)
	peg.until = _time + CHAT_WAIT
	other.until = _time + CHAT_WAIT
	return true

func _start_chat(peg: Peg) -> void:
	var other := peg.partner
	var length: float = _rng.randf_range(CHAT_TIME.x, CHAT_TIME.y)
	for p in [peg, other]:
		p.state = State.CHAT
		p.until = _time + length
		p.beat = -1
	peg.yaw_target = _face(peg.pos, other.pos)
	other.yaw_target = _face(other.pos, peg.pos)

## Turn about: one hops on even beats, the other on odd ones.
func _chat(peg: Peg) -> void:
	if peg.partner == null or _time >= peg.until:
		_end_chat(peg)
		_go_home(peg)
		return
	var beat: int = int(_time / CHAT_BEAT)
	if beat != peg.beat:
		peg.beat = beat
		if (beat % 2 == 0) == peg.chat_lead and _rng.randf() < 0.8:
			peg.hops_left = 1
			peg.hop_at = _time

func _end_chat(peg: Peg) -> void:
	var other := peg.partner
	peg.partner = null
	if other != null and other.partner == peg:
		other.partner = null

## --- Walking ---

func _walk(peg: Peg, to: Vector3, arrive: int) -> void:
	peg.path = _route(peg.pos, to)
	peg.arrive = arrive
	peg.state = State.HIDING if arrive == State.HIDING else State.WALK
	if arrive != State.HIDING:
		peg.running = false

func _step(peg: Peg, delta: float) -> void:
	var speed: float = RUN_SPEED if peg.running else WALK_SPEED
	var travel: float = speed * delta
	while travel > 0.0 and not peg.path.is_empty():
		var target: Vector3 = peg.path[0]
		var to_target: Vector3 = target - peg.pos
		var d: float = to_target.length()
		if d > 0.001:
			peg.yaw_target = _face(peg.pos, target)
		if d <= travel:
			peg.pos = target
			peg.path.pop_front()
			travel -= d
			peg.stride += d
		else:
			peg.pos += to_target / d * travel
			peg.stride += travel
			travel = 0.0
	if peg.path.is_empty():
		_arrive(peg)

func _arrive(peg: Peg) -> void:
	peg.stride = 0.0
	match peg.arrive:
		State.HIDING:
			## Waits for the pop in _think.
			pass
		State.IDLE:
			_settle(peg)
		State.WAIT:
			peg.state = State.WAIT
		State.PAUSE:
			peg.state = State.PAUSE
			peg.until = _time + _rng.randf_range(PAUSE_TIME.x, PAUSE_TIME.y)
			if peg.role == Role.CARRIER:
				peg.until = _time + PAUSE_TIME.x * 0.75
			if _hall_exists() and peg.pos.distance_to(_hall_c) <= _hall_radius + STAND_GAP + 0.3:
				peg.yaw_target = _face(peg.pos, _hall_c)

## Straight there, stepping round anything in the way (a few detours deep).
func _route(from: Vector3, to: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var goals: Array[Vector3] = [to]
	var at := from
	var guard: int = 0
	while not goals.is_empty() and guard < 12:
		guard += 1
		var next: Vector3 = goals.back()
		var hit: int = _first_block(at, next)
		if hit < 0 or goals.size() > 4:
			out.append(next)
			at = next
			goals.pop_back()
			continue
		goals.append(_detour(at, next, _obstacles[hit]))
	if goals.size() > 0:
		out.append(to)
	return out

func _first_block(a: Vector3, b: Vector3) -> int:
	var best: int = -1
	var best_t: float = INF
	var ab := b - a
	var length_sq: float = ab.length_squared()
	if length_sq < 0.0001:
		return -1
	for i in _obstacles.size():
		var o: Dictionary = _obstacles[i]
		var c: Vector3 = o.c
		var r: float = o.r
		## An end already inside it (a stand point squeezed in) can't avoid it.
		if a.distance_to(c) < r or b.distance_to(c) < r:
			continue
		var t: float = clampf((c - a).dot(ab) / length_sq, 0.0, 1.0)
		if (a + ab * t).distance_to(c) < r + 0.25 and t < best_t:
			best_t = t
			best = i
	return best

func _detour(a: Vector3, b: Vector3, o: Dictionary) -> Vector3:
	var c: Vector3 = o.c
	var ab := b - a
	var t: float = clampf((c - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	var side: Vector3 = (a + ab * t) - c
	if side.length_squared() < 0.0001:
		side = Vector3(-ab.z, 0.0, ab.x)
	return c + side.normalized() * (o.r + DETOUR_GAP)

## --- Drawing ---

func _draw_pegs() -> void:
	for i in _pegs.size():
		var peg: Peg = _pegs[i]
		var lift: float = 0.0
		var squash: float = 1.0
		if peg.state == State.WALK or (peg.state == State.HIDING and not peg.path.is_empty()):
			var phase: float = fmod(peg.stride / STRIDE, 1.0)
			lift = sin(phase * PI) * STRIDE_HEIGHT * (1.5 if peg.running else 1.0)
		elif peg.hops_left > 0 and _time >= peg.hop_at:
			var since: float = _time - peg.hop_at
			if since < HOP_TIME:
				var t: float = since / HOP_TIME
				lift = sin(t * PI) * HOP_HEIGHT
				squash = 1.0 + 0.12 * sin(t * PI)
			elif since < HOP_TIME + 0.12:
				squash = 0.88
			else:
				peg.hops_left -= 1
				peg.hop_at = _time if peg.hops_left > 0 else _time + _rng.randf_range(HOP_GAP.x, HOP_GAP.y)
		var pop: float = maxf(peg.pop, 0.0)
		var width: float = pop / sqrt(squash)
		var basis := Basis(Vector3.UP, peg.yaw).scaled(Vector3(width, squash * pop, width))
		var at: Vector3 = peg.pos + Vector3(0.0, lift, 0.0)
		_mmi.multimesh.set_instance_transform(i, Transform3D(basis, at))
		_props.multimesh.set_instance_transform(i, _prop_transform(peg, at, pop))

## On the head when carried; a drilling peg shoulders its pole.
func _prop_transform(peg: Peg, at: Vector3, pop: float) -> Transform3D:
	var shown: bool = peg.prop == Prop.POLE or (peg.carrying and peg.prop != Prop.NONE)
	if not shown or pop <= 0.0:
		return Transform3D(Basis().scaled(Vector3.ZERO), at)
	var spec: Array = PROPS[peg.prop]
	var size: Vector3 = spec[0]
	var turn := Basis(Vector3.UP, peg.yaw)
	var offset := Vector3(0.0, spec[2], 0.0)
	if peg.prop == Prop.POLE:
		offset += turn * Vector3(BODY_RADIUS + 0.06, 0.0, 0.0)
	return Transform3D(turn.scaled(size * pop), at + offset * pop)

## A capsule body (tinted per peg by the MultiMesh colour) and a ball head in
## the people's own colour — two surfaces of one mesh, shared by every
## settlement of that race.
static func _peg_mesh(race: String) -> ArrayMesh:
	if _peg_meshes.has(race):
		return _peg_meshes[race]
	var mesh := ArrayMesh.new()
	var body := CapsuleMesh.new()
	body.radius = BODY_RADIUS
	body.height = BODY_HEIGHT
	body.radial_segments = 10
	body.rings = 4
	var st := SurfaceTool.new()
	st.append_from(body, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, BODY_HEIGHT * 0.5, 0.0)))
	st.commit(mesh)
	var head := SphereMesh.new()
	head.radius = HEAD_RADIUS
	head.height = HEAD_RADIUS * 2.0
	head.radial_segments = 10
	head.rings = 6
	st = SurfaceTool.new()
	st.append_from(head, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, HEAD_Y, 0.0)))
	st.commit(mesh)
	var body_material := StandardMaterial3D.new()
	body_material.vertex_color_use_as_albedo = true
	body_material.roughness = 0.45
	mesh.surface_set_material(0, body_material)
	var head_material := StandardMaterial3D.new()
	head_material.albedo_color = HEAD_COLOURS.get(race, DEFAULT_HEAD)
	head_material.roughness = 0.45
	mesh.surface_set_material(1, head_material)
	_peg_meshes[race] = mesh
	return mesh

## --- Smoke, lanterns and sound ---

## Chimneys on most cottages (the same ones on every peer), and a lantern
## beside each cottage door.
func _place_fixtures() -> void:
	_chimneys.clear()
	for house in _settlement._houses:
		if not is_instance_valid(house) or not house.has_meta(&"folk_radius"):
			continue
		var r: float = house.get_meta(&"folk_radius")
		## A City's landmark is no cottage.
		if r > HOUSE_RADIUS * 1.8:
			continue
		var pick := RandomNumberGenerator.new()
		pick.seed = hash(Vector2i(roundi(house.position.x * 10.0), roundi(house.position.z * 10.0)))
		if pick.randf() >= SMOKING_SHARE:
			continue
		var top: float = house.get_meta(&"folk_top")
		var flue: Vector3 = Basis(Vector3.UP, house.rotation.y) * Vector3(r * 0.35, 0.0, 0.0)
		var drift_angle: float = pick.randf() * TAU
		var drift := Vector3(cos(drift_angle), 0.0, sin(drift_angle)) * SMOKE_DRIFT * pick.randf_range(0.5, 1.0)
		_chimneys.append([house.position + flue + Vector3(0.0, top * 0.92, 0.0), pick.randf() * PUFF_LIFE, drift])
	_smoke.multimesh.instance_count = _chimneys.size() * PUFFS
	var lamps: Array[Transform3D] = []
	for peg in _pegs:
		if peg.role != Role.FOLK:
			continue
		var side := Vector3(-peg.home.z, 0.0, peg.home.x).normalized() * LANTERN_SIDE
		lamps.append(Transform3D(Basis.IDENTITY, peg.home + side))
	_lanterns.multimesh.instance_count = lamps.size()
	for i in lamps.size():
		_lanterns.multimesh.set_instance_transform(i, lamps[i])

## Each chimney keeps PUFFS puffs going round: rising, swelling, drifting
## downwind and fading out.
func _draw_smoke() -> void:
	var multimesh := _smoke.multimesh
	for c in _chimneys.size():
		var flue: Vector3 = _chimneys[c][0]
		var phase: float = _chimneys[c][1]
		var drift: Vector3 = _chimneys[c][2]
		for k in PUFFS:
			var age: float = fmod(_time + phase + PUFF_LIFE * float(k) / float(PUFFS), PUFF_LIFE)
			var t: float = age / PUFF_LIFE
			var at: Vector3 = flue + Vector3(0.0, PUFF_RISE * t, 0.0) + drift * pow(t, 1.5) * PUFF_RISE
			var size: float = lerpf(PUFF_SIZE.x, PUFF_SIZE.y, t)
			var index: int = c * PUFFS + k
			multimesh.set_instance_transform(index, Transform3D(Basis().scaled(Vector3.ONE * size), at))
			multimesh.set_instance_color(index, Color(0.9, 0.9, 0.88, PUFF_ALPHA * (1.0 - t) * minf(1.0, t * 6.0)))

## Every settlement's lanterns share one lamp material: whichever settlement
## gets here first each frame sets its glow from the time of day.
func _light_lamps() -> void:
	var frame: int = Engine.get_process_frames()
	if frame == _lamp_frame or _lamp_material == null:
		return
	_lamp_frame = frame
	var day_night := _main_field(&"day_night") as DayNight
	var night: float = day_night.night_amount if day_night != null else 0.0
	_lamp_material.emission_energy_multiplier = LANTERN_GLOW * night

## Now and then, with the camera close over the square and someone about: the
## market's chatter, a farmyard, or the drill yard.
func _murmur() -> void:
	if _time < _murmur_at:
		return
	_murmur_at = _time + _rng.randf_range(MURMUR_GAP.x, MURMUR_GAP.y)
	var rig := _main_field(&"camera_rig") as RtsCamera
	if rig == null or rig.zoom_distance > MURMUR_MAX_ZOOM:
		return
	if _flat(rig.global_position).distance_to(_flat(global_position)) > MURMUR_REACH:
		return
	var sets: Array[StringName] = []
	for peg in _pegs:
		if peg.state == State.HIDDEN or peg.state == State.HIDING:
			continue
		match peg.role:
			Role.FOLK:
				sets.append(&"town_murmur")
			Role.CARRIER:
				sets.append(&"town_farm" if peg.prop == Prop.SACK else &"town_murmur")
			Role.DRILL:
				sets.append(&"town_drill")
	if not sets.is_empty():
		Sfx.play_at(sets[_rng.randi() % sets.size()], global_position, MURMUR_DB, _rng.randf_range(0.95, 1.05))

## A wooden post with a lamp on top, two surfaces of one mesh.
static func _lantern() -> ArrayMesh:
	if _lantern_mesh != null:
		return _lantern_mesh
	_lantern_mesh = ArrayMesh.new()
	var post := CylinderMesh.new()
	post.top_radius = 0.04
	post.bottom_radius = 0.05
	post.height = LANTERN_HEIGHT
	post.radial_segments = 6
	post.rings = 1
	var st := SurfaceTool.new()
	st.append_from(post, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, LANTERN_HEIGHT * 0.5, 0.0)))
	st.commit(_lantern_mesh)
	var lamp := SphereMesh.new()
	lamp.radius = 0.12
	lamp.height = 0.24
	lamp.radial_segments = 8
	lamp.rings = 4
	st = SurfaceTool.new()
	st.append_from(lamp, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, LANTERN_HEIGHT + 0.08, 0.0)))
	st.commit(_lantern_mesh)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.45, 0.31, 0.2)
	wood.roughness = 0.8
	_lantern_mesh.surface_set_material(0, wood)
	_lamp_material = StandardMaterial3D.new()
	_lamp_material.albedo_color = Color(1.0, 0.82, 0.45)
	_lamp_material.roughness = 0.4
	_lamp_material.emission_enabled = true
	_lamp_material.emission = Color(1.0, 0.7, 0.3)
	_lamp_material.emission_energy_multiplier = 0.0
	_lantern_mesh.surface_set_material(1, _lamp_material)
	return _lantern_mesh
