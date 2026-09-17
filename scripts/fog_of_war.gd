class_name FogOfWar
extends Node3D
## Local-only fog of war, split across two very different-cost layers:
##  - "Currently visible" is smooth, moves every frame, and is cheap to get
##    exactly right — so it's computed analytically per-pixel in the shader
##    (see fog_of_war.gdshader) from the local player's own unit/building
##    positions, never rasterized onto a grid at all.
##  - "Explored" is a slow-changing memory of where you've ever been, where a
##    coarse grid is fine (it's dim, static, and nobody scrutinizes its edges)
##    — that part stays a baked low-res texture, updated a few times a second.
## Every peer computes their OWN fog independently from their OWN units'/
## buildings' positions — "what have I seen" is inherently per-viewer, like
## sprite flip_h and the rally marker, so none of this is networked.

signal fog_updated

## World-space rectangle the explored-memory grid covers; should match the terrain.
@export var map_origin: Vector2 = Vector2(-30, -30)
@export var map_size: Vector2 = Vector2(60, 60)
## The terrain's own MeshInstance3D — its fragment shader material must chain
## a ShaderMaterial using fog_of_war.gdshader via `next_pass` (see
## StandardMaterial3D_b6ruc/ShaderMaterial_terrain_fog in main.tscn). Fog used
## to be a separate floating overlay plane instead, but a flat plane can only
## ever hide things shorter than itself (raised terrain, tall props poked
## through) and can't be raised much before it clears the camera's own
## downward-only view rays entirely (see rts_camera.gd; min eye height is
## zoom_distance * sin(pitch_degrees), just 4.0 at min_zoom). Running the
## identical shader as a second pass directly on the terrain's own geometry
## instead means it naturally follows the terrain's real height/contours
## exactly, since it's reading the terrain's own vertices, not a proxy's.
## Units/buildings/tagged props are still hidden by toggling their own
## .visible off in _update_node_visibility() below, same as always — this is
## only about terrain, which can't be toggled the same way.
@export var terrain_mesh_path: NodePath
## Only affects how blocky the dim "remembered but not currently seen" areas
## look — current vision is a smooth analytic circle regardless of this value.
## Cell size is map_size / grid_resolution: this was tuned for the original
## 60x60 map (0.625 world units/cell); after extending the map to 168x150
## without raising this, cells grew to ~1.75x1.56 units and the blend looked
## chunky. 256 restores roughly the original density (~0.66/0.59 units/cell)
## — cheap to push higher still, _rebuild_texture()'s full-grid pass runs only
## a few times a second and grid_resolution^2 simple ops is trivial even at
## much larger sizes.
@export var grid_resolution: int = 256
@export var explored_update_interval: float = 0.15

## Must match MAX_VISION_SOURCES in fog_of_war.gdshader and
## FOG_MAX_VISION_SOURCES in grass_wind.gdshader and shaders/terrain/binbun_fog.gdshaderinc.
const MAX_VISION_SOURCES: int = 64
## Units within one cell of this size share a vision source (see _update_vision_sources).
const VISION_MERGE_CELL: float = 3.0

## explored[] no longer stores a plain 0/1 flag — it stores 0..255 "how
## strongly explored" per cell, with a smoothstep falloff baked in at stamp
## time (see _stamp_explored) instead of a hard in/out circle test. Relying on
## GPU bilinear filtering alone wasn't enough of a blend across only ~1-2 grid
## cells to hide the grid at this resolution; baking the falloff into the
## data itself gives a properly anti-aliased edge instead of a hard step.
## It's uploaded to fog_texture as-is (one byte per cell); the fog colour and
## opacity it stands for are worked out in the shaders (fog_of_war.gdshader,
## grass_wind.gdshader, and the minimap's) rather than in a per-pixel script loop.
var explored: PackedByteArray = PackedByteArray()

## How often the vision circles are re-gathered and pushed to the shaders. A
## unit covers ~0.12m between pushes, well inside the circles' feathered edge.
const VISION_UPDATE_INTERVAL: float = 1.0 / 30.0
var _vision_timer: float = 0.0

## Stamp shapes per vision radius. The falloff only depends on whole-cell
## offsets from the source's own cell, so one radius always stamps the same
## pattern wherever it lands: {dx, dy, value (PackedInt32Array), reach (Vector2i)}.
var _stamp_kernels: Dictionary = {}
## The (x, z, radius) of every source stamped last pass. One that hasn't moved
## since (any building, any idle unit) would write exactly the same values
## again — explored only ever grows — so it's skipped.
var _last_stamp_keys: Dictionary = {}
## Set whenever explored actually changes, so the texture is only re-uploaded then.
var _explored_dirty: bool = true

## Resource nodes and fog_static_props that haven't been seen yet. They never
## move and explored never shrinks, so each only needs checking until it first
## shows — after that it stays visible for the rest of the match. Untyped, as
## it can hold nodes freed since (a tree cut down before it was ever seen).
var _static_pending: Array = []
var _static_tracking: bool = false
## Spectating (an eliminated player watching the rest of the match): the
## whole map is explored and in vision. Done as one map-sized vision source
## rather than every player's units, which would blow MAX_VISION_SOURCES.
## Spots a quest has opened up: {position: Vector2, radius: float, until:
## float seconds, 0 = for the rest of the match}. They see like a unit does,
## so what they show goes stale the same way once they expire.
var _reveals: Array[Dictionary] = []

## A quest revealing part of the map (RevealAreaAction). `seconds` of 0 leaves
## it revealed for the rest of the match.
func add_reveal(world_pos: Vector3, radius: float, seconds: float = 0.0) -> void:
	_reveals.append({
		position = Vector2(world_pos.x, world_pos.z),
		radius = radius,
		until = (Time.get_ticks_msec() / 1000.0 + seconds) if seconds > 0.0 else 0.0,
	})

var reveal_all: bool = false:
	set(value):
		reveal_all = value
		if value:
			explored.fill(255)
			_explored_dirty = true
var fog_texture: ImageTexture

var _image: Image
var _explored_timer: float = 0.0

## The local player's own vision sources this frame — (x, z) position + radius,
## kept as flat, fixed-size arrays (matching the shader's declared array size
## exactly, with _vision_count marking how many entries are actually in use)
## so they can be pushed straight into the shader uniforms and also used for
## exact (non-grid) is_visible_at() queries.
var _vision_positions: PackedVector2Array = PackedVector2Array()
var _vision_radii: PackedFloat32Array = PackedFloat32Array()
var _vision_count: int = 0

## Deliberately created here at runtime rather than saved as a next_pass in
## the .tscn — a next_pass baked into the scene file renders in the EDITOR'S
## own 3D viewport too (with garbage default uniforms, since nothing drives
## them outside of Play), making the terrain unusable to look at while
## building maps. Chaining it here instead means the terrain's saved material
## never has a next_pass on disk at all; it only exists in memory while the
## game is actually running, so the editor view stays permanently clean with
## nothing to remember to toggle.
@onready var _material: ShaderMaterial = _setup_terrain_fog_material()

## Grass layers painted with the Grass Painter editor plugin (addons/grass_painter)
## get fog support wired straight onto their own material's uniforms (see
## grass_wind.gdshader's fog_enabled/fog_tex/fog_map_origin/.../fog_vision_*)
## rather than a chained next_pass — a next_pass was tried first but relies
## on every grass layer's node already being in the tree by the time this
## node's _ready() runs, which sibling order in the scene doesn't guarantee
## (this project already hit that same class of ordering bug once before,
## with Objective guard ownership).
##
## Found by matching the shader itself (any MultiMeshInstance3D anywhere in
## the tree whose material uses grass_wind.gdshader), not a "fog_grass" group
## tag — a tag would only ever get added to a layer the next time it's
## selected/created in the dock, silently leaving every layer painted before
## this fix (or a scene resave) unfogged forever. Matching by shader instead
## means every grass layer gets fog for free, with nothing to remember to redo.
##
## TerraBrush maps have no terrain mesh to chain the overlay onto: their terrain
## and Binbun grass shaders take the same fog_ uniforms instead, set on the
## material copies TerraBrush renders its internal nodes with.
const GRASS_SHADER: Shader = preload("res://shaders/grass_wind.gdshader")
const FOGGED_SHADERS: Array[Shader] = [
	GRASS_SHADER,
	preload("res://shaders/terrain/binbun_terrain.gdshader"),
	preload("res://shaders/terrain/binbun_foliage.gdshader"),
	preload("res://shaders/terrain/water_placeholder.gdshader"),
]
var _grass_materials: Array[ShaderMaterial] = []

## Ambient dust (ForestDust in map_base.tscn) floats above the terrain, so the
## terrain fog pass never covers it — ambient_dust.gdshader takes the same
## vision uniforms and only shows motes inside current vision. Found by shader
## like the grass. Its emitter is also stretched over this map's rect, since
## maps range from 144 to 208 across and the scene can't know which it's in.
const DUST_SHADER: Shader = preload("res://shaders/ambient_dust.gdshader")
## Motes per square world unit — the original 200 over a 60x60 box.
const DUST_DENSITY: float = 200.0 / 3600.0
var _dust_materials: Array[ShaderMaterial] = []

## Grass wind ramps between random strengths for the whole match, its direction
## drifting slowly. The shaders scroll their wind noise by wind_offset, which is
## integrated here rather than derived from TIME, so changing velocity mid-match
## doesn't jump the noise pattern.
@export var wind_strength_range: Vector2 = Vector2(1.5, 7.0)
## Seconds between picking a new target strength/direction.
@export var wind_change_interval: Vector2 = Vector2(6.0, 20.0)
## How quickly strength eases toward its target (higher = sharper gusts).
@export var wind_ramp_rate: float = 0.3
## Most the direction can swing, in degrees, each time a new target is picked.
@export var wind_direction_swing: float = 40.0
var _wind_direction: float = randf() * TAU
var _wind_target_direction: float = _wind_direction
var _wind_strength: float = 0.0
var _wind_target_strength: float = 0.0
var _wind_timer: float = 0.0
var _wind_offset: Vector2 = Vector2.ZERO

func _setup_terrain_fog_material() -> ShaderMaterial:
	var fog_material := ShaderMaterial.new()
	fog_material.shader = preload("res://shaders/fog_of_war.gdshader")
	var terrain_mesh := get_node_or_null(terrain_mesh_path) as MeshInstance3D
	if terrain_mesh != null:
		terrain_mesh.get_active_material(0).next_pass = fog_material
	return fog_material

func _setup_fogged_materials() -> void:
	_grass_materials.clear()
	_dust_materials.clear()
	_find_fogged_materials(get_tree().root)

func _find_fogged_materials(node: Node) -> void:
	if node is MeshInstance3D or node is MultiMeshInstance3D:
		var grass_material := (node as GeometryInstance3D).material_override as ShaderMaterial
		if grass_material and grass_material.shader in FOGGED_SHADERS:
			grass_material.set_shader_parameter("fog_enabled", true)
			grass_material.set_shader_parameter("fog_tex", fog_texture)
			grass_material.set_shader_parameter("fog_map_origin", map_origin)
			grass_material.set_shader_parameter("fog_map_size", map_size)
			_grass_materials.append(grass_material)
	elif node is GPUParticles3D:
		var dust_material := (node as GPUParticles3D).material_override as ShaderMaterial
		if dust_material and dust_material.shader == DUST_SHADER:
			dust_material.set_shader_parameter("fog_enabled", true)
			_dust_materials.append(dust_material)
			_fit_dust_to_map(node as GPUParticles3D)
	for child in node.get_children(true):
		_find_fogged_materials(child)

func _fit_dust_to_map(particles: GPUParticles3D) -> void:
	var half := map_size * 0.5
	var center := map_origin + half
	particles.global_position = Vector3(center.x, particles.global_position.y, center.y)
	## Duplicated so the resized box doesn't leak into the cached map_base scene.
	var process := particles.process_material.duplicate() as ParticleProcessMaterial
	process.emission_box_extents = Vector3(half.x, process.emission_box_extents.y, half.y)
	particles.process_material = process
	particles.amount = maxi(1, int(map_size.x * map_size.y * DUST_DENSITY))
	particles.visibility_aabb = AABB(Vector3(-half.x - 4.0, -6.0, -half.y - 4.0), Vector3(map_size.x + 8.0, 12.0, map_size.y + 8.0))

func _ready() -> void:
	explored.resize(grid_resolution * grid_resolution)

	_image = Image.create(grid_resolution, grid_resolution, false, Image.FORMAT_R8)
	_image.fill(Color.BLACK)
	fog_texture = ImageTexture.create_from_image(_image)

	_material.set_shader_parameter("fog_tex", fog_texture)
	_material.set_shader_parameter("map_origin", map_origin)
	_material.set_shader_parameter("map_size", map_size)

	call_deferred("_setup_fogged_materials")
	Settings.changed.connect(_on_settings_changed)

	_vision_positions.resize(MAX_VISION_SOURCES)
	_vision_radii.resize(MAX_VISION_SOURCES)

	_update_vision_sources()
	_push_vision_to_shader()
	_update_explored()

func _process(delta: float) -> void:
	_update_wind(delta)

	## Vision sources move constantly, so this (and the shader push) runs at a
	## steady VISION_UPDATE_INTERVAL rather than on the slower explored timer.
	_vision_timer -= delta
	if _vision_timer <= 0.0:
		_vision_timer = VISION_UPDATE_INTERVAL
		_update_vision_sources()
		_push_vision_to_shader()

	_explored_timer += delta
	if _explored_timer < explored_update_interval:
		return
	_explored_timer = 0.0
	_update_explored()

func _update_wind(delta: float) -> void:
	_wind_timer -= delta
	if _wind_timer <= 0.0:
		_wind_timer = randf_range(wind_change_interval.x, wind_change_interval.y)
		_wind_target_strength = randf_range(wind_strength_range.x, wind_strength_range.y)
		_wind_target_direction += deg_to_rad(randf_range(-wind_direction_swing, wind_direction_swing))
	var blend := 1.0 - exp(-wind_ramp_rate * delta)
	_wind_strength = lerpf(_wind_strength, _wind_target_strength, blend)
	_wind_direction = lerp_angle(_wind_direction, _wind_target_direction, blend)
	var velocity := Vector2(cos(_wind_direction), sin(_wind_direction)) * _wind_strength
	if not Settings.get_value(&"wind"):
		velocity = Vector2.ZERO
	_wind_offset += velocity * 0.01 * delta
	for material in _grass_materials:
		material.set_shader_parameter("wind_velocity", velocity)
		material.set_shader_parameter("wind_offset", _wind_offset)

func _on_settings_changed(key: StringName) -> void:
	if key == &"wind":
		TreeWind.refresh()

## Peer 0 is the neutral/AI-owner sentinel (Gatherable, Objective guards
## before capture) — never a real player, so it must never be treated as
## "mine" here even though multiplayer.get_unique_id() degrades to 0 (instead
## of the usual 1) in the direct-run-main.tscn-bypassing-the-lobby test
## workflow. Without this guard, that mode wrongly grants full vision from
## every un-captured Objective's guards, and _update_node_visibility() below
## wrongly renders them (and their buildings) through the fog entirely.
func _update_vision_sources() -> void:
	_vision_count = 0
	if reveal_all:
		_vision_positions[0] = map_origin + map_size * 0.5
		_vision_radii[0] = map_size.length()
		_vision_count = 1
		return
	var my_peer := multiplayer.get_unique_id()
	if my_peer == 0:
		return

	## Units standing together see practically the same circle, and a squad is
	## several men in one block — so units share one source per
	## VISION_MERGE_CELL cell (at their average position, with the widest sight
	## among them). Keeps a big army under MAX_VISION_SOURCES instead of every
	## unit past the cap silently going blind.
	var cell_index: Dictionary = {}
	var cell_counts: PackedInt32Array = PackedInt32Array()
	for node in get_tree().get_nodes_in_group("units"):
		var unit := node as Unit
		if not unit or not Teams.is_friendly(my_peer, unit.owner_peer_id) or unit.status_activity == Unit.Activity.DEAD:
			continue
		var pos := Vector2(unit.global_position.x, unit.global_position.z)
		var key := Vector2i(floori(pos.x / VISION_MERGE_CELL), floori(pos.y / VISION_MERGE_CELL))
		var index: int = cell_index.get(key, -1)
		if index >= 0:
			_vision_positions[index] += pos
			_vision_radii[index] = maxf(_vision_radii[index], unit.vision_range)
			cell_counts[index] += 1
			continue
		if _vision_count >= MAX_VISION_SOURCES:
			continue
		cell_index[key] = _vision_count
		_vision_positions[_vision_count] = pos
		_vision_radii[_vision_count] = unit.vision_range
		cell_counts.append(1)
		_vision_count += 1
	for i in _vision_count:
		_vision_positions[i] /= cell_counts[i]

	## Places a quest has revealed (see add_reveal) see for themselves, for as
	## long as they last.
	var now: float = Time.get_ticks_msec() / 1000.0
	for i in range(_reveals.size() - 1, -1, -1):
		var entry: Dictionary = _reveals[i]
		if entry.until > 0.0 and now >= entry.until:
			_reveals.remove_at(i)
			continue
		if _vision_count >= MAX_VISION_SOURCES:
			continue
		_vision_positions[_vision_count] = entry.position
		_vision_radii[_vision_count] = entry.radius
		_vision_count += 1

	for node in get_tree().get_nodes_in_group("buildings"):
		if _vision_count >= MAX_VISION_SOURCES:
			break
		var building := node as ProductionBuilding
		## Under-construction sites grant no vision at all — otherwise a player
		## could scatter cheap unbuilt foundations across the map and scout it
		## for free, without ever paying a builder's time to finish one.
		var is_mine_and_alive: bool = building and Teams.is_friendly(my_peer, building.owner_peer_id) and not building.is_destroyed
		if is_mine_and_alive and not building.is_under_construction:
			_vision_positions[_vision_count] = Vector2(building.global_position.x, building.global_position.z)
			_vision_radii[_vision_count] = building.vision_range
			_vision_count += 1

func _push_vision_to_shader() -> void:
	## _vision_positions/_vision_radii are always exactly MAX_VISION_SOURCES
	## long (fixed-size, matching the shader's array uniforms); only the
	## first _vision_count entries are meaningful, and the shader never reads
	## past vision_count either, so the unused tail is harmless.
	_material.set_shader_parameter("vision_count", _vision_count)
	_material.set_shader_parameter("vision_positions", _vision_positions)
	_material.set_shader_parameter("vision_radii", _vision_radii)
	## grass_wind.gdshader's fog uniforms are named with a fog_ prefix (see
	## that shader) since it also has its own unrelated uniforms — different
	## names than fog_of_war.gdshader's, same values.
	for grass_material in _grass_materials:
		grass_material.set_shader_parameter("fog_vision_count", _vision_count)
		grass_material.set_shader_parameter("fog_vision_positions", _vision_positions)
		grass_material.set_shader_parameter("fog_vision_radii", _vision_radii)
	for dust_material in _dust_materials:
		dust_material.set_shader_parameter("fog_vision_count", _vision_count)
		dust_material.set_shader_parameter("fog_vision_positions", _vision_positions)
		dust_material.set_shader_parameter("fog_vision_radii", _vision_radii)

## Exact (not grid-quantized) check against this tick's own vision sources —
## smoother and cheaper than a lookup into a rasterized grid would be, since
## there are only ever a handful of these to check against.
func is_visible_at(world_pos: Vector3) -> bool:
	var p := Vector2(world_pos.x, world_pos.z)
	for i in _vision_count:
		if p.distance_to(_vision_positions[i]) <= _vision_radii[i]:
			return true
	return false

func _world_to_cell(world_pos: Vector3) -> Vector2i:
	var u := (world_pos.x - map_origin.x) / map_size.x
	var v := (world_pos.z - map_origin.y) / map_size.y
	return Vector2i(int(u * grid_resolution), int(v * grid_resolution))

## Half strength, not merely non-zero — the outermost fringe of a stamp is
## still near-black on the terrain, so props there would otherwise pop in
## fully drawn over what still looks like unexplored ground.
const EXPLORED_THRESHOLD: int = 128

func is_explored_at(world_pos: Vector3) -> bool:
	var c := _world_to_cell(world_pos)
	if c.x < 0 or c.x >= grid_resolution or c.y < 0 or c.y >= grid_resolution:
		return false
	return explored[c.y * grid_resolution + c.x] >= EXPLORED_THRESHOLD

## Writes a smoothstep falloff (255 deep inside the circle, fading to 0 over
## the outer ~15% of the radius) rather than a hard 1/0 cutoff, so the grid
## itself holds an anti-aliased edge instead of depending on texture
## filtering to hide a single hard step. Cells already explored by an earlier,
## stronger stamp are never dimmed back down (max, not overwrite).
func _stamp_explored(world_pos: Vector3, world_radius: float) -> void:
	var center := _world_to_cell(world_pos)
	var kernel := _stamp_kernel(world_radius)
	var dxs: PackedInt32Array = kernel.dx
	var dys: PackedInt32Array = kernel.dy
	var values: PackedInt32Array = kernel.value
	var reach: Vector2i = kernel.reach
	var inside: bool = center.x - reach.x >= 0 and center.x + reach.x < grid_resolution \
			and center.y - reach.y >= 0 and center.y + reach.y < grid_resolution
	var changed := false
	for k in dxs.size():
		var x: int = center.x + dxs[k]
		var y: int = center.y + dys[k]
		if not inside and (x < 0 or x >= grid_resolution or y < 0 or y >= grid_resolution):
			continue
		var idx: int = y * grid_resolution + x
		if explored[idx] < values[k]:
			explored[idx] = values[k]
			changed = true
	if changed:
		_explored_dirty = true

## Every cell a circle of `world_radius` stamps, relative to its centre cell,
## with the value it stamps there. Cells the falloff leaves at 0 are dropped,
## since max() with 0 never changes anything.
func _stamp_kernel(world_radius: float) -> Dictionary:
	if _stamp_kernels.has(world_radius):
		return _stamp_kernels[world_radius]
	var cell_size_x: float = map_size.x / float(grid_resolution)
	var cell_size_y: float = map_size.y / float(grid_resolution)
	var reach := Vector2i(int(ceil(world_radius / cell_size_x)), int(ceil(world_radius / cell_size_y)))
	var dxs := PackedInt32Array()
	var dys := PackedInt32Array()
	var values := PackedInt32Array()
	for dy in range(-reach.y, reach.y + 1):
		for dx in range(-reach.x, reach.x + 1):
			var world_dx := dx * cell_size_x
			var world_dy := dy * cell_size_y
			var dist := sqrt(world_dx * world_dx + world_dy * world_dy)
			if dist > world_radius:
				continue
			var falloff := 1.0 - smoothstep(world_radius * 0.85, world_radius, dist)
			var value := int(round(falloff * 255.0))
			if value <= 0:
				continue
			dxs.append(dx)
			dys.append(dy)
			values.append(value)
	var kernel := {dx = dxs, dy = dys, value = values, reach = reach}
	_stamp_kernels[world_radius] = kernel
	return kernel

func _update_explored() -> void:
	## Already fully explored by reveal_all's setter — stamping a map-sized
	## circle every tick would just redo that.
	if not reveal_all:
		var stamp_keys: Dictionary = {}
		for i in _vision_count:
			var pos := _vision_positions[i]
			var key := Vector3(pos.x, pos.y, _vision_radii[i])
			stamp_keys[key] = true
			if _last_stamp_keys.has(key):
				continue
			_stamp_explored(Vector3(pos.x, 0.0, pos.y), _vision_radii[i])
		_last_stamp_keys = stamp_keys

	if _explored_dirty:
		_explored_dirty = false
		_rebuild_texture()
	_update_node_visibility()
	fog_updated.emit()

func _rebuild_texture() -> void:
	_image.set_data(grid_resolution, grid_resolution, false, Image.FORMAT_R8, explored)
	fog_texture.update(_image)

## Allied units and buildings always render and always grant vision — a team
## shares what it can see. Enemy units only render while actually in vision
## (they move, so a stale position would be misleading). Enemy buildings and
## neutral resource nodes
## don't move, so once explored they stay visible at their known position —
## same "remembered map" idea classic RTS fog uses for static structures.
func _update_node_visibility() -> void:
	## 0 is never really "mine" — see the guard/comment in _update_vision_sources().
	var my_peer := multiplayer.get_unique_id()
	var i_am_valid_peer := my_peer != 0

	for node in get_tree().get_nodes_in_group("units"):
		var unit := node as Unit
		if unit:
			unit.visible = (i_am_valid_peer and Teams.is_friendly(my_peer, unit.owner_peer_id)) or is_visible_at(unit.global_position)

	for node in get_tree().get_nodes_in_group("buildings"):
		var building := node as ProductionBuilding
		if building:
			building.visible = (i_am_valid_peer and Teams.is_friendly(my_peer, building.owner_peer_id)) or is_explored_at(building.global_position)

	## Resource nodes, plus purely decorative scenery (imported models with no
	## Unit/ProductionBuilding script attached, e.g. an Objective's terrain
	## dressing) — add "fog_static_props" to a node's Groups in the Inspector to
	## have fog hide it too. Same "remembered map" rule as buildings above: once
	## explored it stays visible, since it's static and being wrong about its
	## remembered appearance never matters the way a stale unit position would.
	## That's also why each is dropped from the check the moment it shows.
	if not _static_tracking:
		_start_static_tracking()
	var i := _static_pending.size() - 1
	while i >= 0:
		var prop = _static_pending[i]
		if not is_instance_valid(prop):
			_drop_static_pending(i)
		elif prop.is_inside_tree():
			var seen := is_explored_at(prop.global_position)
			prop.visible = seen
			if seen:
				_drop_static_pending(i)
		i -= 1

## Swap-remove: order doesn't matter, and _update_node_visibility walks the
## list backwards, so the entry swapped in has already been checked this pass.
func _drop_static_pending(index: int) -> void:
	_static_pending[index] = _static_pending[_static_pending.size() - 1]
	_static_pending.pop_back()

func _start_static_tracking() -> void:
	_static_tracking = true
	for node in get_tree().get_nodes_in_group(&"gatherables"):
		_track_static(node)
	for node in get_tree().get_nodes_in_group(&"fog_static_props"):
		_track_static(node)
	## Anything placed later (a Farm, an Objective's letter) — groups from a
	## scene file or add_to_group-before-add_child are already set by now.
	get_tree().node_added.connect(_on_node_added)

func _on_node_added(node: Node) -> void:
	if node.is_in_group(&"gatherables") or node.is_in_group(&"fog_static_props"):
		_track_static(node)

func _track_static(node: Node) -> void:
	if node is Gatherable or (node is Node3D and node.is_in_group(&"fog_static_props")):
		_static_pending.append(node)
