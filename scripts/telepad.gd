class_name Telepad
extends ProductionBuilding
## The Robots' Telepad. Two of one owner's pads are linked (a new pad links
## itself to an unlinked one when it finishes; right-clicking another pad with
## one selected relinks it, see Main._set_rally_point), and robots ordered onto
## a linked pad walk to it and come out of its partner. Arrivals at the far pad
## go on to its rally point, if it has one.

## Metres past the footprint within which a traveller steps onto the pad.
const STEP_ON_REACH: float = 3.0
## A traveller whose block has stopped (arrived, its rear ranks still short of
## the pad) is sent through from up to this far past the footprint.
const ARRIVED_REACH: float = 12.0
## How far round the partner, past its footprint, travellers come out.
const EXIT_MIN: float = 1.2
const EXIT_MAX: float = 3.2
const TICK: float = 0.2
## Once the first robot goes through, the link stays open this long for the
## rest of his group to follow, then needs COOLDOWN to recharge. Robots that
## reach a pad while it recharges wait there and go when it is ready.
const OPEN_TIME: float = 4.0
const COOLDOWN: float = 60.0
const FLASH_COLOR: Color = Color(0.62, 0.35, 1.0, 0.85)
const FLASH_TIME: float = 0.45
## The arc drawn to the partner while either pad is selected: how high it rises
## over its length, and how many pieces it is drawn in.
const ARC_RISE: float = 0.18
const ARC_SEGMENTS: int = 32
const ARC_LIFT: float = 2.6
## The recharge ring round the pad's foot: how far out past the footprint, how
## wide, how far off the ground, and how many pieces round.
const RING_GAP: float = 0.5
const RING_WIDTH: float = 0.4
const RING_LIFT: float = 0.25
const RING_SEGMENTS: int = 48
const RING_TRACK_COLOR: Color = Color(0.1, 0.08, 0.14, 0.55)
const RING_READY_PULSE: float = 0.6

## The pad this one sends to, replicated so every peer can draw the link.
@export var partner_path: NodePath = NodePath()

## Host: unit -> the assault_center its walk here was given. A unit given any
## other order since then (a new destination, or no longer a plain move) drops
## out rather than being whisked away later.
var _travellers: Dictionary = {}
var _tick_left: float = 0.0
## Host, GameClock ms, kept the same on both pads of a link: the open window
## for a group going through ends at _open_until_ms, and the link can send
## again from _ready_at_ms.
var _open_until_ms: int = 0
var _ready_at_ms: int = 0
var _column_material: StandardMaterial3D = null
var _arc: MeshInstance3D = null
## Where the arc was last drawn between, so it is redrawn only when that changes.
var _arc_ends: Array[Vector3] = []
## Every peer, GameClock ms: the link stays open until _open_until_local, then
## recharges until _ready_at_local (see _rpc_recharge). Drawn as _ring.
var _open_until_local: int = 0
var _ready_at_local: int = 0
var _ring: MeshInstance3D = null
var _ring_material: StandardMaterial3D = null
## When the ring last finished, for the brief "ready" pulse after it.
var _ready_pulse_from: int = -1

func partner() -> Telepad:
	if partner_path == NodePath():
		return null
	var pad := get_node_or_null(partner_path) as Telepad
	return pad if pad != null and not pad.is_destroyed else null

## Whether `peer_id`'s units can be sent through here right now.
func can_send(peer_id: int) -> bool:
	var other := partner()
	return owner_peer_id == peer_id and not is_destroyed and not is_under_construction \
			and other != null and not other.is_under_construction and other.owner_peer_id == owner_peer_id

## Host.
func link_to(other: Telepad) -> void:
	if other == self or other == null or other.owner_peer_id != owner_peer_id:
		return
	for pad: Telepad in [self, other]:
		var old := pad.partner()
		if old != null and old != self and old != other:
			old.partner_path = NodePath()
		pad._travellers.clear()
	partner_path = get_path_to(other)
	other.partner_path = other.get_path_to(self)

## Host: an unlinked finished pad of the same owner, nearest first, takes this
## one as its partner.
func link_to_spare() -> void:
	if partner() != null:
		return
	var best: Telepad = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group(&"buildings"):
		var pad := node as Telepad
		if pad == null or pad == self or pad.is_destroyed or pad.is_under_construction \
				or pad.owner_peer_id != owner_peer_id or pad.partner() != null:
			continue
		var distance := global_position.distance_to(pad.global_position)
		if distance < best_distance:
			best = pad
			best_distance = distance
	if best != null:
		link_to(best)

## Host: `units` have just been ordered onto this pad.
func add_travellers(units: Array[Unit]) -> void:
	for unit in units:
		if unit.owner_peer_id == owner_peer_id and unit.status_command == Unit.Command.MOVE:
			_travellers[unit] = unit.assault_center

func _ready() -> void:
	super._ready()
	if multiplayer.is_server():
		construction_finished.connect(link_to_spare)
		destroyed.connect(_on_destroyed)

func _on_destroyed() -> void:
	var other := partner()
	if other != null:
		other.partner_path = NodePath()
	partner_path = NodePath()
	_travellers.clear()

func _process(delta: float) -> void:
	super._process(delta)
	_update_arc()
	_update_ring()

## A ring round the pad's foot while the link is busy: solid violet while it is
## open for a group, then a violet arc filling round a dark track as it
## recharges, and a quick swell and fade the moment it is ready again.
func _update_ring() -> void:
	var now := GameClock.msec()
	var open := now < _open_until_local
	var charging := not open and now < _ready_at_local
	if not open and not charging and _ready_at_local > 0 and _ready_pulse_from < 0:
		_ready_pulse_from = now
	var pulsing := _ready_pulse_from >= 0 and now - _ready_pulse_from < int(RING_READY_PULSE * 1000.0)
	if is_destroyed or not (open or charging or pulsing):
		if _ring != null:
			_ring.visible = false
		return
	if _ring == null:
		_ring = MeshInstance3D.new()
		_ring.top_level = true
		_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ring_material = StandardMaterial3D.new()
		_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ring_material.vertex_color_use_as_albedo = true
		_ring_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_ring.material_override = _ring_material
		_ring.mesh = ImmediateMesh.new()
		add_child(_ring)
	_ring.visible = true
	_ring.global_transform = Transform3D(Basis.IDENTITY, global_position + Vector3.UP * RING_LIFT)
	var inner := get_footprint_radius() + RING_GAP
	var mesh := _ring.mesh as ImmediateMesh
	mesh.clear_surfaces()
	if pulsing:
		var k := float(now - _ready_pulse_from) / (RING_READY_PULSE * 1000.0)
		_ring_band(mesh, inner + k * 1.2, RING_WIDTH * (1.0 - k * 0.5), 1.0, Color(FLASH_COLOR, 0.9 * (1.0 - k)))
		return
	if open:
		_ring_band(mesh, inner, RING_WIDTH, 1.0, Color(FLASH_COLOR, 0.75 + 0.2 * sin(now * 0.012)))
		return
	var filled := clampf(1.0 - float(_ready_at_local - now) / (COOLDOWN * 1000.0), 0.0, 1.0)
	_ring_band(mesh, inner, RING_WIDTH, 1.0, RING_TRACK_COLOR)
	_ring_band(mesh, inner, RING_WIDTH, filled, FLASH_COLOR, 0.01)

## A flat band from `radius` out by `width`, `share` of the way round from
## twelve o'clock clockwise (seen from above).
func _ring_band(mesh: ImmediateMesh, radius: float, width: float, share: float, color: Color, lift: float = 0.0) -> void:
	var steps := maxi(roundi(RING_SEGMENTS * share), 1)
	if share <= 0.0:
		return
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in steps + 1:
		var a := TAU * share * float(i) / steps
		var dir := Vector3(sin(a), 0.0, -cos(a))
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(dir * radius + Vector3.UP * lift)
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(dir * (radius + width) + Vector3.UP * lift)
	mesh.surface_end()

## Each pad of a selected pair draws the arc from itself, so only one is ever
## shown: the selected one's.
func _update_arc() -> void:
	var main := get_tree().current_scene as Main
	var other := partner()
	var show := other != null and main != null and main.selected_building == self and not is_destroyed
	if not show:
		if _arc != null:
			_arc.visible = false
		return
	if _arc == null:
		_arc = MeshInstance3D.new()
		_arc.top_level = true
		_arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = FLASH_COLOR
		material.no_depth_test = true
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_arc.material_override = material
		_arc.mesh = ImmediateMesh.new()
		add_child(_arc)
		_arc.global_transform = Transform3D.IDENTITY
	_arc.visible = true
	var ends: Array[Vector3] = [global_position, other.global_position]
	if ends == _arc_ends:
		return
	_arc_ends = ends
	var mesh := _arc.mesh as ImmediateMesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var rise := ends[0].distance_to(ends[1]) * ARC_RISE
	for i in ARC_SEGMENTS + 1:
		var t := float(i) / ARC_SEGMENTS
		mesh.surface_add_vertex(ends[0].lerp(ends[1], t) + Vector3.UP * (ARC_LIFT + rise * 4.0 * t * (1.0 - t)))
	mesh.surface_end()

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_tick_left -= delta
	if _tick_left > 0.0:
		return
	_tick_left = TICK
	var other := partner()
	## Taken over, or the partner was: the link goes with it.
	if other != null and other.owner_peer_id != owner_peer_id:
		other.partner_path = NodePath()
		partner_path = NodePath()
		other = null
	if _travellers.is_empty():
		return
	if not can_send(owner_peer_id):
		_travellers.clear()
		return
	var reach := get_footprint_radius()
	var sent: Array[Unit] = []
	for unit: Unit in _travellers.keys():
		if not is_instance_valid(unit) or unit.status_activity == Unit.Activity.DEAD \
				or unit.owner_peer_id != owner_peer_id \
				or not unit.assault_center.is_equal_approx(_travellers[unit]):
			_travellers.erase(unit)
			continue
		var distance := Vector2(unit.global_position.x - global_position.x, unit.global_position.z - global_position.z).length() - reach
		var walking := unit.status_command == Unit.Command.MOVE
		var stopped := unit.status_command == Unit.Command.NONE
		if not walking and not stopped:
			_travellers.erase(unit)
			continue
		if distance <= STEP_ON_REACH or (stopped and distance <= ARRIVED_REACH):
			if not _charged():
				continue
			if GameClock.msec() >= _open_until_ms:
				_open_link(other)
			_travellers.erase(unit)
			_send(unit, other)
			sent.append(unit)
		elif stopped:
			_travellers.erase(unit)
	if sent.is_empty():
		return
	_rpc_flash.rpc()
	other._rpc_flash.rpc()
	if other.has_rally_point:
		var main := get_tree().current_scene as Main
		if main != null:
			var paths: Array[NodePath] = []
			for unit in sent:
				paths.append(unit.get_path())
			main.issue_command_as(owner_peer_id, paths, other.rally_target_path, other.rally_point, false, false)

## Host: open for a group now, or recharged.
func _charged() -> bool:
	var now := GameClock.msec()
	return now < _open_until_ms or now >= _ready_at_ms

## Host: the first robot of a group is going through; both pads of the link
## stay open for the rest, then recharge.
func _open_link(other: Telepad) -> void:
	var open_until := GameClock.msec() + int(OPEN_TIME * 1000.0)
	var ready_at := open_until + int(COOLDOWN * 1000.0)
	for pad: Telepad in [self, other]:
		pad._open_until_ms = open_until
		pad._ready_at_ms = ready_at
		pad._rpc_recharge.rpc(OPEN_TIME, COOLDOWN)

## Every peer: the link has just opened for a group; show it open, then
## recharging. Sent as durations so no peer needs the host's clock.
@rpc("authority", "call_local", "reliable")
func _rpc_recharge(open_seconds: float, cooldown_seconds: float) -> void:
	_open_until_local = GameClock.msec() + int(open_seconds * 1000.0)
	_ready_at_local = _open_until_local + int(cooldown_seconds * 1000.0)
	_ready_pulse_from = -1

func _send(unit: Unit, other: Telepad) -> void:
	var angle := randf() * TAU
	var spot := other.global_position + Vector3(cos(angle), 0.0, sin(angle)) \
			* (other.get_footprint_radius() + randf_range(EXIT_MIN, EXIT_MAX))
	spot = NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, spot)
	unit.global_position = spot
	unit.reset_physics_interpolation()
	if unit.sim_id >= 0 and ArmyBridge.current != null:
		var flat := Vector2(spot.x, spot.z)
		ArmyBridge.current.sim.set_unit_position(unit.sim_id, flat)
		ArmyBridge.current.sim.release(unit.sim_id, flat)
	unit.clear_order_queue()
	unit.command_stop()

## A violet column of light up out of the pad, and a zap.
@rpc("authority", "call_local", "unreliable")
func _rpc_flash() -> void:
	Sfx.play_at(&"arcane_impact", global_position)
	if _column_material == null:
		_column_material = StandardMaterial3D.new()
		_column_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_column_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_column_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.1
	mesh.bottom_radius = 1.1
	mesh.height = 4.0
	mesh.cap_top = false
	mesh.cap_bottom = false
	var material := _column_material.duplicate() as StandardMaterial3D
	material.albedo_color = FLASH_COLOR
	mesh.material = material
	var column := MeshInstance3D.new()
	column.mesh = mesh
	column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(column)
	column.position = Vector3(0.0, 2.3, 0.0)
	column.scale = Vector3(0.4, 1.0, 0.4)
	var tween := column.create_tween().set_parallel()
	tween.tween_property(column, "scale", Vector3(1.0, 1.0, 1.0), FLASH_TIME).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color:a", 0.0, FLASH_TIME)
	tween.chain().tween_callback(column.queue_free)
