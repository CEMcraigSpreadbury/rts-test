class_name WorldFeedback
extends Node3D
## Cosmetic, per-viewer feedback split out of main.gd: command/damage/resource
## popups, projectile visuals, hit bursts, screen shake, under-attack alerts,
## path markers, the hover ring and the rally banner. Most gameplay events only
## fire on the host, so the relays here replay them on every other peer —
## nothing in this file ever changes a gameplay outcome.
##
## Created by Main._enter_tree() under a fixed name, so its RPCs resolve to
## the same node path on every peer.

var main: Main

const RALLY_BANNER_SCENE: PackedScene = preload("res://assets/art/Models/Banner/banner.glb")
const RALLY_DUST_HEIGHT: float = 0.35
## The game's single display font. Control-based UI picks this up from the
## project theme (dark_ages_theme.tres) automatically; this const is for the
## labels built in code that never enter the themed UI tree — the command
## popups below and the pinned world popups (damage, resources, Favour).
const GAME_FONT: Font = preload("res://assets/fonts/MedievalSharp-Book.ttf")

## Tint per command kind for the popup that jumps out of the ordered spot when
## an order is issued. The lines themselves are inspector-authored — see
## move_command_lines and friends below.
const COMMAND_POPUP_COLORS: Dictionary = {
	"move": Color(1.0, 0.98, 0.86),
	"attack": Color(1.0, 0.42, 0.32),
	"patrol": Color(0.55, 0.85, 1.0),
	"build": Color(1.0, 0.82, 0.38),
}
const COMMAND_POPUP_FONT_SIZE: int = 22
## Lifts the command line off the clicked ground so it reads as a callout
## rather than as text lying on the terrain.
const COMMAND_POPUP_HEIGHT: float = 0.6

## Called from Main._ready(), once Main's own @onready nodes exist.
func setup() -> void:
	_build_impact_effect_resources()
	_voice_audio_player = AudioStreamPlayer.new()
	_voice_audio_player.bus = &"SFX"
	main.ui_root.add_child(_voice_audio_player)

## Purely local (like the sound above and the rally marker) — a quick
## expanding, fading ring at the clicked ground point, so a right-click order
## has an immediate visual confirmation beyond just the sound. White for a
## plain move, red for an attack/attack-move order.
func play_command_feedback(world_pos: Vector3, is_attack: bool) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.35
	torus.outer_radius = 0.55
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.3, 0.25, 0.9) if is_attack else Color(1.0, 1.0, 1.0, 0.9)
	## render_priority controls draw order between transparent objects
	## (higher draws later/on top, independent of distance sorting) — this is
	## what keeps the ring drawing over dense grass, without no_depth_test,
	## which would also make it ignore the unit/building's own opaque sprite
	## and draw in front of that too.
	mat.render_priority = 10
	ring.material_override = mat
	add_child(ring)
	ring.global_position = world_pos + Vector3(0, 0.1, 0)
	ring.scale = Vector3.ONE * 0.3
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3.ONE * 1.6, 0.35) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.35)
	tween.set_parallel(false)
	tween.tween_callback(ring.queue_free)

const PATH_MARKER_COLOR: Color = Color(0.45, 0.75, 1.0, 0.9)

## The unit whose voice answers for a whole selection. One line per order, not
## one per unit — same representative convention as _play_random_select_sound
## and _play_order_sound_once, which is what keeps a 20-unit move order from
## reading as one clip getting louder. Random rather than selected_units[0] so
## a mixed group doesn't always answer in the same unit's voice.
func command_speaker() -> Unit:
	var speakers: Array[Unit] = []
	for unit in main.selected_units:
		if is_instance_valid(unit) and not unit.command_lines_for("move").is_empty():
			speakers.append(unit)
	## Nobody in the selection has authored lines (an all-monster group, say) —
	## fall back to the plain selection so the caller still gets a valid unit
	## and the per-kind lookup can decide it has nothing to say.
	if speakers.is_empty():
		if main.selected_units.is_empty():
			return null
		return main.selected_units[randi() % main.selected_units.size()]
	return speakers[randi() % speakers.size()]

## The CommandLine most recently played for each (unit type, command kind), so
## the next pick for that pair can exclude it. Keyed by scene path as well as
## kind: keying by kind alone would let an archer's last line suppress a
## villager's identical-text line for no audible reason. See
## spawn_command_popup.
var _last_command_line: Dictionary = {}

## Damaged node instance_id -> {"total": int, "label": Label, "started": float}
## for the aggregation window above. See _show_damage_feedback.
var _damage_aggregates: Dictionary = {}

## Local-only "juice" — a random line for the command kind that jumps out of
## the ordered spot, drifts up and fades. Peers never see this (it is
## deliberately not part of any command RPC): it is feedback about *this*
## player's click, not about what the units end up doing.
##
## Pinned to world_pos (the clicked ground/target, or the placed building)
## rather than to the screen position of the cursor: the camera can be panning
## while the line is still on screen — edge scroll, or a middle-drag started
## right after the click — and a screen-anchored line then slides away from the
## spot it is talking about. Follows _spawn_pinned_popup's re-projection.
## `speaker` is the unit answering for the selection (see command_speaker) —
## the words and the clip both come from its own authored pool, so a villager,
## a knight and a hydra no longer share one human voice.
func spawn_command_popup(kind: String, world_pos: Vector3, speaker: Unit) -> void:
	if main.ui_root == null or speaker == null or not is_instance_valid(speaker):
		return
	## Same behind-camera rejection as _spawn_pinned_popup: a point behind the
	## camera unprojects to a plausible-looking on-screen position, so an
	## order issued and then spun away from would pop up in mid-view.
	if main.camera.is_position_behind(world_pos):
		return
	## Blank entries are skipped rather than picked and shown empty, so a
	## part-filled array in the inspector never produces an invisible popup.
	var choices: Array[CommandLine] = []
	for line in speaker.command_lines_for(kind):
		if line != null and not line.text.is_empty():
			choices.append(line)
	if choices.is_empty():
		return

	## Same no-repeat rule as AudioUtils.play_random, tracked per kind here
	## because text and voice are picked together as one CommandLine: hearing
	## (and reading) the identical line on two consecutive clicks is the most
	## noticeable way a small pool of lines sounds wrong.
	var repeat_key := "%s|%s" % [speaker.scene_file_path, kind]
	if choices.size() > 1:
		var last: CommandLine = _last_command_line.get(repeat_key, null)
		var unrepeated: Array[CommandLine] = []
		for line in choices:
			if line != last:
				unrepeated.append(line)
		if not unrepeated.is_empty():
			choices = unrepeated

	var chosen: CommandLine = choices[randi() % choices.size()]
	_last_command_line[repeat_key] = chosen
	if chosen.voice != null and _voice_audio_player != null:
		_voice_audio_player.stream = chosen.voice
		_voice_audio_player.play()

	var label := Label.new()
	label.text = chosen.text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", GAME_FONT)
	label.add_theme_font_size_override("font_size", COMMAND_POPUP_FONT_SIZE)
	label.add_theme_color_override("font_color", COMMAND_POPUP_COLORS.get(kind, Color.WHITE))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	main.ui_root.add_child(label)

	## reset_size() forces the layout now instead of next frame — without it
	## size is still zero here, so centring on the anchor and the centre pivot
	## the scale punch needs would both be computed from nothing and the first
	## frame would pop in offset.
	label.reset_size()
	label.pivot_offset = label.size * 0.5
	label.scale = Vector2(0.35, 0.35)
	label.rotation = deg_to_rad(randf_range(-7.0, 7.0))

	var drift := Vector2(randf_range(-14.0, 14.0), -46.0)
	var anchor := world_pos + Vector3(0.0, COMMAND_POPUP_HEIGHT, 0.0)
	## Offset kept from the old cursor-anchored version: the line sits above the
	## ordered spot rather than on it, so it never covers what was clicked.
	var half := label.size * 0.5 + Vector2(0.0, 20.0)
	## Re-projected every frame (as a 0..1 drift fraction) instead of tweening
	## `position` to a fixed screen target — see _spawn_pinned_popup, which
	## does the same for the world numbers.
	var follow := func(t: float) -> void:
		if not is_instance_valid(label):
			return
		if main.camera.is_position_behind(anchor):
			label.visible = false
			return
		label.visible = true
		label.position = main.camera.unproject_position(anchor) - half + drift * t
	follow.call(0.0)

	var tween := create_tween()
	tween.set_parallel(true)
	## TRANS_BACK/EASE_OUT overshoots past full size and settles back — that
	## overshoot is the "jump"; a plain linear grow reads as a fade-in instead.
	tween.tween_property(label, "scale", Vector2.ONE, 0.22) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_method(follow, 0.0, 1.0, 0.6) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.28).set_delay(0.34)
	tween.set_parallel(false)
	tween.tween_callback(label.queue_free)

## Persistent (until reached/cleared) flag marking one point in a unit's
## shift-drawn path — see _path_markers. Only actually shown while that unit
## is selected — see update_path_markers.
func add_path_marker(unit: Unit, world_pos: Vector3) -> void:
	var markers: Array = _path_markers.get(unit, [])

	var marker := Node3D.new()
	add_child(marker)
	marker.global_position = world_pos + Vector3(0, 0.05, 0)
	marker.visible = main.selected_units.has(unit)

	var flag_mesh := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.18
	torus.outer_radius = 0.28
	flag_mesh.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = PATH_MARKER_COLOR
	mat.render_priority = 10
	flag_mesh.material_override = mat
	marker.add_child(flag_mesh)

	markers.append(marker)
	_path_markers[unit] = markers

func clear_path_markers(unit: Unit) -> void:
	if not _path_markers.has(unit):
		return
	for marker in _path_markers[unit]:
		if is_instance_valid(marker):
			marker.queue_free()
	_path_markers.erase(unit)

## Pops (and frees) the oldest marker for each unit once it's actually gotten
## close to that point — an approximation of "this waypoint was reached"
## driven by the unit's own replicated position, since the host's real
## order_queue isn't networked and this is cosmetic-only anyway. Also keeps
## each remaining marker's visibility in sync with whether its unit is
## currently selected, every frame (selection changes constantly and isn't
## routed through a single choke point worth hooking instead).
func update_path_markers() -> void:
	for unit in _path_markers.keys():
		if not is_instance_valid(unit):
			clear_path_markers(unit)
			continue
		var markers: Array = _path_markers[unit]
		while not markers.is_empty() and is_instance_valid(markers[0]) \
				and unit.global_position.distance_to(markers[0].global_position) <= PATH_MARKER_ARRIVAL_DISTANCE:
			markers[0].queue_free()
			markers.pop_front()
		if markers.is_empty():
			_path_markers.erase(unit)
			continue
		var is_selected := main.selected_units.has(unit)
		for marker in markers:
			if is_instance_valid(marker):
				marker.visible = is_selected

## Unit -> Array[Node3D], the flag markers for its still-pending shift-drawn
## waypoints, in order. Purely a local visual aid on this client (not driven
## by the host's real, authoritative order_queue) so a multi-point path is
## visible on screen after being planned out — see add_path_marker/
## update_path_markers/clear_path_markers.
var _path_markers: Dictionary = {}
const PATH_MARKER_ARRIVAL_DISTANCE: float = 1.0

## Voice lines get their own player rather than sharing
## command_audio_player: that one is a single stream, so a voice line sent
## through it would cut off the command sound firing at the same moment.
## Built in code (see _ready) for the same reason as BuildingPlacement's
## wall drag label.
var _voice_audio_player: AudioStreamPlayer = null
## Purely local visual: only ever shown for the local player's own selected
## building, so it's built on demand rather than living in a networked scene.
var rally_marker: Node3D = null

## Purely local visual too — just feedback for whatever the mouse is
## currently over, built on demand like rally_marker.
var hover_ring: MeshInstance3D = null
## Clears the Shrine model and its health bar (which sits at y 2.8).
const FAVOUR_POPUP_HEIGHT: float = 3.4
## Favour is the one resource with no ResourceCost lying around to read its
## colour off at popup time (objectives grant it directly), so its type is
## reached by name here.
const FAVOUR_RESOURCE_TYPE: ResourceType = preload("res://resources/favour_resource_type.tres")
## Clears a villager's head — deposit popups anchor to the villager, not the
## building it is delivering into.
const DEPOSIT_POPUP_HEIGHT: float = 1.2
## Same head clearance as a deposit popup, but kept separate: this one also
## has to sit above buildings, which take damage but never deliver.
const DAMAGE_POPUP_HEIGHT: float = 1.2
## Red only for hits landing on the local player's own units and buildings —
## that is the one the player has to react to. Damage their own side deals
## is the bone colour, so a fight reads as "red means me" at a glance
## instead of every number in a melee being the same alarm colour.
const DAMAGE_TAKEN_POPUP_COLOR: Color = Color(1.0, 0.42, 0.38)
const DAMAGE_DEALT_POPUP_COLOR: Color = Color(0.96, 0.94, 0.88)
## Pinned world popups run smaller than the command popup at the cursor: that
## one is a single deliberate response to a click, whereas these are ambient
## and several can be on screen at once.
const PINNED_POPUP_FONT_SIZE: int = 18
## Smaller again — damage is the highest-volume popup by far, and in a real
## fight legibility comes from the numbers not overlapping.
const DAMAGE_POPUP_FONT_SIZE: int = 15
## Camera distance at which a pinned popup renders at its authored size —
## rts_camera.gd's own starting zoom_distance, so the default view is 1:1.
const POPUP_REFERENCE_DISTANCE: float = 18.0
## Bounds on the distance scaling. Without them the range is unusable at the
## extremes of rts_camera.gd's 8-22 zoom (fully in would be 2.25x).
const POPUP_SCALE_MIN: float = 0.6
const POPUP_SCALE_MAX: float = 1.25
## Hits landing on one target inside this window are summed into a single
## popup rather than stacking a label per hit. Measured from the first hit of
## a run, not refreshed per hit, so sustained fire still ticks over into a new
## number instead of one label absorbing an entire fight.
const DAMAGE_AGGREGATE_WINDOW: float = 0.35
## Only sweep _damage_aggregates for expired entries once it is at least this
## big — below it the dictionary is smaller than the walk would cost.
const DAMAGE_AGGREGATE_PRUNE_SIZE: int = 64
## Meta key under which a pinned popup carries its own flight tween — see
## _spawn_pinned_popup.
const POPUP_TWEEN_META: StringName = &"pinned_popup_tween"
var _impact_process_material: ParticleProcessMaterial
var _impact_mesh: QuadMesh
var _rally_dust_material: ParticleProcessMaterial
## RPCs declared directly on dynamically-spawned Unit nodes weren't reaching
## clients, so units relay animation changes here and this (statically present,
## proven-reliable) node broadcasts them instead. Sprite flip is NOT relayed
## this way — it's inherently viewer-dependent, so each peer computes it locally
## from the unit's synced rotation and that peer's own camera (see Unit._process()).
func on_unit_animation_changed(anim_name: String, unit: Unit) -> void:
	if multiplayer.is_server() and multiplayer.multiplayer_peer != null:
		_rpc_unit_animation.rpc(unit.get_path(), anim_name)

@rpc("authority", "call_remote", "reliable")
func _rpc_unit_animation(unit_path: NodePath, anim_name: String) -> void:
	var unit := get_node_or_null(unit_path) as Unit
	if unit:
		unit.sprite.play(anim_name)
		## The attack lunge is driven off this same relay rather than a channel
		## of its own — the host's _play_attack_swing pairs the two locally, and
		## the direction is derived from replicated facing on each peer.
		if anim_name == "attack":
			unit.play_attack_lunge()

## Order-dispatch functions below only ever run on the host (inside its RPC
## handlers), so — same reasoning as animation_changed above — playing the
## sound directly there would only ever be heard on the host's own machine.
## Unlike animation, though, this goes to exactly ONE peer rather than all of
## them: an order acknowledgment is interface feedback on the ordering
## player's own click, and letting an opponent hear it would leak both what
## they're doing and roughly where. So the host either owns the unit and plays
## it locally, or forwards it to the single peer that does.
func play_unit_order_sound(unit: Unit, kind: Unit.OrderSoundKind) -> void:
	if unit.owner_peer_id == main.my_peer_id():
		_play_order_sound_once(unit, kind)
	elif multiplayer.is_server() and multiplayer.multiplayer_peer != null:
		_rpc_unit_order_sound.rpc_id(unit.owner_peer_id, unit.get_path(), kind)

@rpc("authority", "call_remote", "reliable")
func _rpc_unit_order_sound(unit_path: NodePath, kind: Unit.OrderSoundKind) -> void:
	var unit := get_node_or_null(unit_path) as Unit
	if unit:
		_play_order_sound_once(unit, kind)

## The frame each order sound kind was last played on. One acknowledgment per
## kind per frame, not one per unit: a batch order used to fire an identical
## clip from every unit in the selection at once, which doesn't read as a
## chorus, it reads as one line getting louder the bigger the group is. Same
## one-representative convention as _play_random_select_sound. A whole batch
## is dispatched inside a single RPC handler (so, one frame), and keying by
## kind rather than globally keeps a mixed right-click — some units gathering,
## some attacking — sounding like both orders instead of only the first.
var _order_sound_frames: Dictionary = {}

func _play_order_sound_once(unit: Unit, kind: Unit.OrderSoundKind) -> void:
	var frame := Engine.get_process_frames()
	if _order_sound_frames.get(kind, -1) == frame:
		return
	_order_sound_frames[kind] = frame
	unit.play_order_sound(kind)

## projectile_fired only ever fires on the host's own copy (only the host runs
## combat logic — see Unit._physics_process), so the host spawns its own local
## visual immediately here and relays to every other peer to do the same. Real
## damage timing is decided entirely by the host's own Unit._pending_projectile_hits;
## this is purely cosmetic and never affects gameplay outcome.
func on_unit_projectile_fired(target: Node3D, unit: Unit) -> void:
	if not is_instance_valid(target):
		return
	_spawn_projectile_visual(unit, target)
	if multiplayer.is_server() and multiplayer.multiplayer_peer != null:
		_rpc_spawn_projectile_visual.rpc(unit.get_path(), target.get_path())

@rpc("authority", "call_remote", "reliable")
func _rpc_spawn_projectile_visual(shooter_path: NodePath, target_path: NodePath) -> void:
	var shooter := get_node_or_null(shooter_path) as Unit
	var target := get_node_or_null(target_path) as Node3D
	if shooter == null or target == null or not is_instance_valid(target):
		return
	_spawn_projectile_visual(shooter, target)

## Flies a purely local, non-networked projectile mesh from the shooter to
## wherever the target currently is, over the same travel time the host is
## using for its authoritative delayed-damage timer, then frees itself.
func _spawn_projectile_visual(shooter: Unit, target: Node3D) -> void:
	if shooter.projectile_scene == null or not is_instance_valid(target):
		return
	var projectile: Node3D = shooter.projectile_scene.instantiate()
	add_child(projectile)
	var start_pos: Vector3 = shooter.global_position + Vector3(0, 1.2, 0)
	var end_pos: Vector3 = target.global_position + Vector3(0, 0.8, 0)
	var dist: float = start_pos.distance_to(end_pos)
	var duration: float = maxf(dist / maxf(shooter.projectile_speed, 0.01), 0.05)
	var arc_height: float = clampf(dist * 0.15, 0.2, 1.5)
	projectile.global_position = start_pos
	var tween := create_tween()
	tween.tween_method(
		func(t: float): projectile.global_position = start_pos.lerp(end_pos, t) + Vector3(0, arc_height * sin(t * PI), 0),
		0.0, 1.0, duration
	)
	tween.tween_callback(projectile.queue_free)

## Building equivalent of on_unit_projectile_fired/_rpc_spawn_projectile_visual/
## _spawn_projectile_visual above — kept separate rather than sharing those
## (typed for Unit) since Unit and ProductionBuilding have no common combat
## base class (see CombatUtils' own header comment for why).
func on_building_projectile_fired(target: Node3D, building: ProductionBuilding) -> void:
	if not is_instance_valid(target):
		return
	_spawn_building_projectile_visual(building, target)
	if multiplayer.is_server() and multiplayer.multiplayer_peer != null:
		_rpc_spawn_building_projectile_visual.rpc(building.get_path(), target.get_path())

@rpc("authority", "call_remote", "reliable")
func _rpc_spawn_building_projectile_visual(shooter_path: NodePath, target_path: NodePath) -> void:
	var shooter := get_node_or_null(shooter_path) as ProductionBuilding
	var target := get_node_or_null(target_path) as Node3D
	if shooter == null or target == null or not is_instance_valid(target):
		return
	_spawn_building_projectile_visual(shooter, target)

func _spawn_building_projectile_visual(shooter: ProductionBuilding, target: Node3D) -> void:
	if shooter.projectile_scene == null or not is_instance_valid(target):
		return
	var projectile: Node3D = shooter.projectile_scene.instantiate()
	add_child(projectile)
	var start_pos: Vector3 = shooter.global_position + Vector3(0, 2.5, 0)
	var end_pos: Vector3 = target.global_position + Vector3(0, 0.8, 0)
	var dist: float = start_pos.distance_to(end_pos)
	var duration: float = maxf(dist / maxf(shooter.projectile_speed, 0.01), 0.05)
	var arc_height: float = clampf(dist * 0.15, 0.2, 1.5)
	projectile.global_position = start_pos
	var tween := create_tween()
	tween.tween_method(
		func(t: float): projectile.global_position = start_pos.lerp(end_pos, t) + Vector3(0, arc_height * sin(t * PI), 0),
		0.0, 1.0, duration
	)
	tween.tween_callback(projectile.queue_free)

## Damage taken and resources deposited only ever happen on the host (both
## take_damage() and Unit._deposit_and_continue() are authority-gated), so —
## same reasoning as animation/projectile relaying above — the host spawns its
## own local popup immediately and relays to every other peer to do the same.
func relay_damage_number(amount: int, attacker_path: NodePath, fatal: bool, node: Node3D) -> void:
	_show_damage_feedback(node, amount, attacker_path, fatal)
	if multiplayer.is_server() and multiplayer.multiplayer_peer != null:
		_rpc_damage_number.rpc(node.get_path(), amount, attacker_path, fatal)

@rpc("authority", "call_remote", "reliable")
func _rpc_damage_number(node_path: NodePath, amount: int, attacker_path: NodePath, fatal: bool) -> void:
	var node := get_node_or_null(node_path) as Node3D
	if node:
		_show_damage_feedback(node, amount, attacker_path, fatal)

## Floating number for anything damageable; the hit reaction (flash, recoil,
## squash) only applies to Unit, and buildings get their own flash/squash
## instead — they have no sprite to shove around.
##
## `attacker_path` and `fatal` come straight off the damaged signal (see
## Unit.take_damage). The attacker is looked up per-peer rather than having its
## position sent, so a hit always recoils away from where that peer actually
## sees the attacker standing.
func _show_damage_feedback(node: Node3D, amount: int, attacker_path: NodePath, fatal: bool) -> void:
	## get() rather than node.owner_peer_id: this takes a plain Node3D (Unit
	## and ProductionBuilding both land here), and a missing property comes
	## back null, which simply compares unequal.
	var mine: bool = node.get("owner_peer_id") == multiplayer.get_unique_id()
	_show_damage_number(node, amount, mine)
	_spawn_impact_burst(node.global_position + Vector3(0, 0.9, 0))
	var attacker: Node3D = null
	if not attacker_path.is_empty():
		attacker = get_node_or_null(attacker_path) as Node3D
	if node is Unit:
		## Falling back to the victim's own position means "no direction" to
		## play_hit_reaction, which then skips the recoil rather than shoving the
		## unit somewhere arbitrary.
		var from_position: Vector3 = node.global_position
		if attacker != null:
			from_position = attacker.global_position
		node.play_hit_reaction(from_position)
	elif node is ProductionBuilding:
		node.play_hit_flash()
		node.play_squash()
	if fatal and attacker is Unit:
		attacker.play_hitstop()
	_maybe_alert_under_attack(node)

## Sums hits on one target inside DAMAGE_AGGREGATE_WINDOW into a single popup,
## so a battle line focusing one unit shows "37" rather than five overlapping
## labels. The running label is replaced outright rather than having its text
## rewritten in place: a new label re-punches and re-centres on the new text
## width for free, where an in-place edit would have to fight the drift tween
## and recompute the centring offset the follow lambda captured.
func _show_damage_number(node: Node3D, amount: int, mine: bool) -> void:
	## Gated on what is actually on screen rather than on a fog query of its
	## own: FogOfWar already decides this per node, and it uses different rules
	## for units (in vision now) and buildings (explored once, remembered), so
	## re-deriving it here could only ever disagree with what the player sees.
	if not node.is_visible_in_tree() or not Settings.get_value(&"damage_numbers"):
		return
	var id := node.get_instance_id()
	var now := Time.get_ticks_msec() / 1000.0
	var total := amount
	var entry: Dictionary = _damage_aggregates.get(id, {})
	if not entry.is_empty() and now - float(entry["started"]) <= DAMAGE_AGGREGATE_WINDOW:
		total += int(entry["total"])
		var previous: Label = entry["label"]
		if is_instance_valid(previous):
			var previous_tween: Tween = previous.get_meta(POPUP_TWEEN_META, null)
			if previous_tween != null and previous_tween.is_valid():
				previous_tween.kill()
			previous.queue_free()
	else:
		## Only reset the clock when this hit starts a fresh run, so the window
		## stays anchored to the first hit rather than sliding forward forever
		## under continuous fire.
		entry = {"started": now}

	var color := DAMAGE_TAKEN_POPUP_COLOR if mine else DAMAGE_DEALT_POPUP_COLOR
	## ignore_fog: the is_visible_in_tree() check above is the stricter and more
	## accurate version of what the helper's own fog gate would do.
	var label := _spawn_pinned_popup(node.global_position + Vector3(0.0, DAMAGE_POPUP_HEIGHT, 0.0),
			str(total), color, true, DAMAGE_POPUP_FONT_SIZE)
	## A popup skipped by the behind-camera check still has to keep
	## accumulating: the target may come back into view mid-run, and the number
	## shown then should be the whole run, not just the hits since it appeared.
	_damage_aggregates[id] = {"total": total, "label": label, "started": entry["started"]}
	_prune_damage_aggregates(now)

## Entries are keyed by instance_id and only ever overwritten by a later hit on
## the same node, so units that die mid-run would otherwise leave theirs behind
## for the rest of the match. Only worth walking once the dictionary is big
## enough that stale entries are plausible.
func _prune_damage_aggregates(now: float) -> void:
	if _damage_aggregates.size() <= DAMAGE_AGGREGATE_PRUNE_SIZE:
		return
	for id in _damage_aggregates.keys():
		if now - float(_damage_aggregates[id]["started"]) > DAMAGE_AGGREGATE_WINDOW:
			_damage_aggregates.erase(id)

## One-shot dust/spark puff at the point of a hit. The process material and
## mesh are built once in _ready and shared by every burst — only the emitter
## node itself is per-hit, and it frees itself once the burst finishes.
func _spawn_impact_burst(world_pos: Vector3) -> void:
	_spawn_burst(_impact_process_material, world_pos, 8, 0.35)

## Ring of dust kicked up where a rally banner is planted. Emitted above the
## grass rather than at ground level — blades are ~0.55m tall and dense enough
## to swallow a burst that starts on the ground.
func spawn_rally_dust(world_pos: Vector3) -> void:
	_spawn_burst(_rally_dust_material, world_pos + Vector3(0, RALLY_DUST_HEIGHT, 0), 16, 0.5)

func _spawn_burst(material: ParticleProcessMaterial, world_pos: Vector3, amount: int, lifetime: float) -> void:
	var particles := GPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = lifetime
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.process_material = material
	particles.draw_pass_1 = _impact_mesh
	add_child(particles)
	particles.global_position = world_pos
	particles.emitting = true
	particles.finished.connect(particles.queue_free)

func _build_impact_effect_resources() -> void:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.15
	process.direction = Vector3(0, 1, 0)
	process.spread = 65.0
	process.initial_velocity_min = 1.4
	process.initial_velocity_max = 3.0
	process.gravity = Vector3(0, -5.0, 0)
	process.scale_min = 0.3
	process.scale_max = 0.8
	process.color = Color(0.95, 0.85, 0.6, 0.9)
	_impact_process_material = process

	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.billboard_keep_scale = true
	material.albedo_color = Color(0.95, 0.85, 0.6, 0.9)
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.14, 0.14)
	mesh.material = material
	_impact_mesh = mesh

	## Emitted from a ring lying flat on the ground and pushed outward by
	## radial velocity, so it reads as dust thrown out from the banner's base
	## rather than a puff rising off it.
	var dust := ParticleProcessMaterial.new()
	dust.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	dust.emission_ring_axis = Vector3(0, 1, 0)
	dust.emission_ring_radius = 0.35
	dust.emission_ring_inner_radius = 0.2
	dust.emission_ring_height = 0.05
	dust.direction = Vector3(0, 1, 0)
	dust.spread = 25.0
	dust.initial_velocity_min = 0.4
	dust.initial_velocity_max = 0.9
	dust.radial_velocity_min = 1.2
	dust.radial_velocity_max = 2.1
	dust.damping_min = 1.5
	dust.damping_max = 2.5
	dust.gravity = Vector3(0, -1.0, 0)
	dust.scale_min = 0.5
	dust.scale_max = 1.1
	dust.color = Color(0.82, 0.74, 0.6, 0.75)
	_rally_dust_material = dust

## Screen shake is per-viewer (rts_camera drops it when the source is off
## screen), but the events that cause it only fire on the host — so it relays
## the world position out the same way damage numbers do.
func relay_impact_shake(world_pos: Vector3, amount: float) -> void:
	main.camera_rig.shake_at(world_pos, amount)
	if multiplayer.is_server() and multiplayer.multiplayer_peer != null:
		_rpc_impact_shake.rpc(world_pos, amount)

@rpc("authority", "call_remote", "unreliable")
func _rpc_impact_shake(world_pos: Vector3, amount: float) -> void:
	main.camera_rig.shake_at(world_pos, amount)

## Purely local per-viewer decision (this runs identically for every peer,
## on both the host's immediate call and every client's relayed RPC) — only
## fires when it's specifically *this* viewer's own stuff being hit, throttled
## so a sustained attack pings once every few seconds instead of once per hit.
## Records where, so KEY_BACKSPACE can jump the camera there.
const UNDER_ATTACK_ALERT_COOLDOWN_MS: int = 6000
var _last_under_attack_alert_ms: int = -UNDER_ATTACK_ALERT_COOLDOWN_MS
var _last_attack_position: Vector3 = Vector3.ZERO
var _has_attack_alert: bool = false

func _maybe_alert_under_attack(node: Node3D) -> void:
	var node_owner_peer_id: int = -1
	if node is Unit:
		node_owner_peer_id = (node as Unit).owner_peer_id
	elif node is ProductionBuilding:
		node_owner_peer_id = (node as ProductionBuilding).owner_peer_id
	if node_owner_peer_id != main.my_peer_id():
		return
	var now := Time.get_ticks_msec()
	if now - _last_under_attack_alert_ms < UNDER_ATTACK_ALERT_COOLDOWN_MS:
		return
	_last_under_attack_alert_ms = now
	_last_attack_position = node.global_position
	_has_attack_alert = true
	AudioUtils.play_random(main.command_audio_player, main.on_under_attack_sound_effects)
	main.minimap.show_attack_ping(node.global_position)

func jump_to_last_attack() -> void:
	if not _has_attack_alert:
		return
	main.camera_rig.global_position.x = _last_attack_position.x
	main.camera_rig.global_position.z = _last_attack_position.z

## Production and resource deposits both resolve host-side, so a building's
## squash is relayed out the same way the gatherable's is.
func relay_building_squash(building: ProductionBuilding) -> void:
	building.play_squash()
	if multiplayer.is_server() and multiplayer.multiplayer_peer != null:
		_rpc_building_squash.rpc(building.get_path())

@rpc("authority", "call_remote", "unreliable")
func _rpc_building_squash(building_path: NodePath) -> void:
	var building := get_node_or_null(building_path) as ProductionBuilding
	if building:
		building.play_squash()

## Gathering is simulated host-side only, so the harvested node's squash has to
## be relayed the same way damage numbers and hit flashes are.
func on_unit_resource_harvested(node: Gatherable) -> void:
	node.play_harvest_squash()
	if multiplayer.is_server() and multiplayer.multiplayer_peer != null:
		_rpc_harvest_squash.rpc(node.get_path())

@rpc("authority", "call_remote", "unreliable")
func _rpc_harvest_squash(node_path: NodePath) -> void:
	var node := get_node_or_null(node_path) as Gatherable
	if node:
		node.play_harvest_squash()

func on_unit_resource_deposited(amount: int, color: Color, unit: Unit) -> void:
	_spawn_deposit_popup(unit, amount, color)
	var dropoff := unit.dropoff_point.get_parent() as ProductionBuilding if unit.dropoff_point else null
	if dropoff:
		relay_building_squash(dropoff)
	if multiplayer.is_server() and multiplayer.multiplayer_peer != null:
		_rpc_resource_number.rpc(unit.get_path(), amount, color)

@rpc("authority", "call_remote", "reliable")
func _rpc_resource_number(unit_path: NodePath, amount: int, color: Color) -> void:
	var unit := get_node_or_null(unit_path) as Unit
	if unit:
		_spawn_deposit_popup(unit, amount, color)

## Anchored at the depositing villager rather than at the drop-off building
## itself: the villager is standing on the building when this fires, so it
## reads as coming from the delivery, and it keeps a Town Center taking two
## deliveries at once from stacking both popups on the same pixel.
func _spawn_deposit_popup(unit: Unit, amount: int, color: Color) -> void:
	var mine := unit.owner_peer_id == multiplayer.get_unique_id()
	_spawn_pinned_popup(unit.global_position + Vector3(0.0, DEPOSIT_POPUP_HEIGHT, 0.0),
			"+%d" % amount, color, mine)

## Objective Favour income is banked host-side only (see objective.gd), so the
## "+N" over the shrine has to be relayed the same way damage and resource
## numbers are, rather than each peer spawning its own off local state.
##
## Fog-gated per peer, unlike the other floating numbers: those fire on
## one-off events, whereas this one repeats for as long as an objective is
## held, so an unguarded popup would be a permanent "someone owns this shrine
## and is earning from it" beacon through unexplored fog. Owning it counts as
## seeing it (same rule as fog_of_war.gd's own node visibility), though in
## practice a held objective's buildings already grant vision over themselves.
func show_favour_popup(objective: Objective, amount: int) -> void:
	_spawn_favour_popup(objective, amount)
	if multiplayer.is_server() and multiplayer.multiplayer_peer != null:
		_rpc_favour_popup.rpc(objective.get_path(), amount)

## Unreliable, unlike the otherwise-identical _rpc_resource_number: that one
## fires on a discrete event a player would notice missing, whereas this
## repeats every time an objective banks a point, so a dropped packet costs
## one popup in a steady stream of them and isn't worth the retransmit.
@rpc("authority", "call_remote", "unreliable")
func _rpc_favour_popup(objective_path: NodePath, amount: int) -> void:
	var objective := get_node_or_null(objective_path) as Objective
	if objective:
		_spawn_favour_popup(objective, amount)

func _spawn_favour_popup(objective: Objective, amount: int) -> void:
	var mine := objective.owner_peer_id == multiplayer.get_unique_id()
	_spawn_pinned_popup(objective.global_position + Vector3(0.0, FAVOUR_POPUP_HEIGHT, 0.0),
			"+%d" % amount, FAVOUR_RESOURCE_TYPE.display_color, mine)

## Every floating world label — damage, resource deliveries, Favour income —
## goes through here. Built like spawn_command_popup (2D Label in ui_root,
## scale-punch then drift-and-fade) rather than as a world-space Label3D,
## which these all used to be: a Label3D sits in the scene's own lighting and
## depth and reads as part of the terrain, which is why it was hard to see
## over grass. It differs from the command popup in staying pinned to
## world_pos (see the follow lambda below) rather than drifting from a screen
## position captured once at the cursor.
##
## Fog-gated, unlike the Label3D numbers this replaced for shrine income and
## resource deliveries: a UI-layer label draws over everything, so an enemy's
## popup would otherwise be a legible callout sitting on top of fog that is
## deliberately hiding the unit or building underneath it. ignore_fog is for
## callers that already know the popup is the local player's own.
func _spawn_pinned_popup(world_pos: Vector3, text: String, color: Color, ignore_fog: bool = false,
		font_size: int = PINNED_POPUP_FONT_SIZE) -> Label:
	if main.ui_root == null:
		return null
	if not ignore_fog and not main.fog_of_war.is_visible_at(world_pos):
		return null
	## A point behind the camera still unprojects to a plausible-looking
	## on-screen position, so it has to be rejected explicitly or popups from
	## behind the player would appear in the middle of the view.
	if main.camera.is_position_behind(world_pos):
		return null

	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", GAME_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	main.ui_root.add_child(label)

	## See spawn_command_popup — size is zero until this forces the layout.
	label.reset_size()
	label.pivot_offset = label.size * 0.5
	label.rotation = deg_to_rad(randf_range(-7.0, 7.0))

	## Perspective cue the Label3D version got for free: a label over a distant
	## unit shrinks, one over a zoomed-in fight grows. Applied as a scale
	## multiplier rather than a font_size, so the punch tween below stays a
	## single property animation and no re-layout is needed. Sampled once at
	## spawn — a popup only lives ~0.6s, so zooming mid-flight is not worth
	## fighting the scale tween over.
	var camera_scale := clampf(POPUP_REFERENCE_DISTANCE / maxf(main.camera.global_position.distance_to(world_pos), 0.001),
			POPUP_SCALE_MIN, POPUP_SCALE_MAX)
	label.scale = Vector2(0.35, 0.35) * camera_scale

	var drift := Vector2(randf_range(-14.0, 14.0), -46.0)
	var anchor := world_pos
	var half := label.size * 0.5
	## Unlike the command popup, which drifts from a screen position captured
	## once, this re-projects its anchor every frame so the text stays over the
	## thing it is labelling while the camera pans — a cursor popup is about a
	## click that has already happened, but these label something in the world
	## and visibly slide off it otherwise. Hence tween_method driving the drift
	## as a 0..1 fraction rather than tweening `position` to a fixed target:
	## same TRANS_QUAD/EASE_OUT curve, recomputed against the current view.
	var follow := func(t: float) -> void:
		## The label can be freed mid-flight when a later hit replaces this
		## popup (see _show_damage_number). That kills the tween too, but a
		## tween already mid-step still finishes the current call, and a freed
		## Object reads back as Nil rather than erroring on the check itself.
		if not is_instance_valid(label):
			return
		if main.camera.is_position_behind(anchor):
			label.visible = false
			return
		label.visible = true
		label.position = main.camera.unproject_position(anchor) - half + drift * t
	follow.call(0.0)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "scale", Vector2.ONE * camera_scale, 0.22) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_method(follow, 0.0, 1.0, 0.62) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.28).set_delay(0.34)
	tween.set_parallel(false)
	tween.tween_callback(label.queue_free)
	## Only needed by callers that may free the label before the tween ends —
	## without killing it first, its tween_method keeps calling follow on a
	## freed label and its final tween_callback calls queue_free on one.
	label.set_meta(POPUP_TWEEN_META, tween)
	return label

func update_rally_marker() -> void:
	if main.can_command_building(main.selected_building) and main.selected_building.can_rally and main.selected_building.has_rally_point:
		_ensure_rally_marker()
		rally_marker.visible = true
		rally_marker.global_position = main.selected_building.rally_point
	elif rally_marker:
		rally_marker.visible = false

func _ensure_rally_marker() -> void:
	if rally_marker:
		return
	rally_marker = RALLY_BANNER_SCENE.instantiate()
	rally_marker.scale = Vector3.ONE * 0.8
	add_child(rally_marker)

## --- Hover highlight ---

const HOVER_RING_COLOR: Color = Color(1.0, 1.0, 1.0, 0.55)
## Units have no NavigationObstacle3D to read a radius from, so this is just
## a reasonable fixed size matching their own SelectionRing.
const HOVER_RING_UNIT_RADIUS: float = 0.75

func _ensure_hover_ring() -> void:
	if hover_ring:
		return
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.9
	mesh.outer_radius = 1.0
	hover_ring = MeshInstance3D.new()
	hover_ring.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = HOVER_RING_COLOR
	## render_priority (not no_depth_test — that would also draw this in
	## front of the unit/building's own opaque sprite) forces this to draw
	## after dense grass in the transparent pass, on top of it, while still
	## depth-testing normally against opaque geometry.
	material.render_priority = 10
	hover_ring.set_surface_override_material(0, material)
	hover_ring.visible = false
	add_child(hover_ring)

func _is_ring_target(node: Object) -> bool:
	return node is Unit or node is ProductionBuilding or node is Gatherable

## Not shown while some other exclusive mode already owns the mouse
## (placing a building, dragging a selection box, chatting, game over).
## Otherwise prefers whatever's currently under the mouse (fog-of-war-hidden
## things don't count, even if their collider is still technically hit), and
## falls back to the last single-clicked target so the ring keeps showing on
## it even once the mouse moves away — see clicked_ring_target.
func update_hover_ring() -> void:
	if main.placement.is_placing() or main.dragging or main.chat.is_input_open() or main.game_over:
		if hover_ring:
			hover_ring.visible = false
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		return

	var collider: Object = main.raycast(get_viewport().get_mouse_position()).get("collider")
	_update_hover_cursor(collider)
	var hovered: Node3D = collider if (collider != null and _is_ring_target(collider) and collider.visible) else null
	var target: Node3D = hovered if hovered else (main.clicked_ring_target if is_instance_valid(main.clicked_ring_target) else null)

	## Selected units already show their own green SelectionRing — showing
	## this one too on top would be redundant.
	if target == null or (target is Unit and target.selected):
		if hover_ring:
			hover_ring.visible = false
		return

	_ensure_hover_ring()
	var radius: float = _hover_ring_radius(target)
	var mesh: TorusMesh = hover_ring.mesh
	mesh.outer_radius = radius
	mesh.inner_radius = maxf(radius - 0.08, 0.01)
	hover_ring.global_position = target.global_position + Vector3(0, 0.05, 0)
	hover_ring.visible = true

## Only meaningful feedback while units are actually selected (nothing to
## click-to-attack/gather with otherwise) — an enemy/resource still gets the
## plain arrow when nothing of mine is selected to act on it.
func _update_hover_cursor(collider: Object) -> void:
	if main.selected_units.is_empty():
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		return
	if (collider is Unit and collider.owner_peer_id != main.my_peer_id()) \
			or (collider is ProductionBuilding and collider.owner_peer_id != main.my_peer_id()):
		Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	elif collider is Gatherable:
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
	else:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)

## Clearance between a building's drawn edge and its ring. Sized off the
## model rather than the NavigationObstacle3D because several models overhang
## their obstacle badly (Town Center by 0.44, Beastmen Barracks by 0.74),
## which drew the ring inside the building instead of around it.
const HOVER_RING_BUILDING_MARGIN: float = 0.3

func _hover_ring_radius(node: Node) -> float:
	if node is Unit:
		return HOVER_RING_UNIT_RADIUS
	var obstacle: NavigationObstacle3D = node.get_node_or_null("NavigationObstacle3D")
	var obstacle_radius: float = obstacle.radius + 0.2 if obstacle else 1.0
	## Gatherables deliberately keep using the obstacle radius: a tree's
	## canopy reaches well past its trunk, and a ring out at the leaves would
	## cover its neighbours rather than marking the one under the cursor.
	if not (node is ProductionBuilding):
		return obstacle_radius
	## maxf keeps the obstacle as a floor, so this can only ever grow a ring.
	return maxf(obstacle_radius, _visual_radius(node) + HOVER_RING_BUILDING_MARGIN)

## How far the drawn geometry reaches from this node's origin, measured flat
## in XZ. Only ever runs for the single node under the cursor, so walking the
## mesh tree each frame costs nothing worth caching — and it stays correct if
## a model is rescaled, rotated, or swapped out.
func _visual_radius(node: Node3D) -> float:
	var furthest: float = 0.0
	for mesh_instance in _collect_mesh_instances(node):
		var aabb: AABB = mesh_instance.get_aabb()
		for i in 8:
			var corner: Vector3 = node.to_local(mesh_instance.global_transform * aabb.get_endpoint(i))
			furthest = maxf(furthest, Vector2(corner.x, corner.z).length())
	return furthest

## Sprite3D health bars and GPUParticles3D aren't MeshInstance3D, so they're
## skipped for free — only real geometry counts toward the size.
func _collect_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		found.append(node)
	for child in node.get_children():
		found.append_array(_collect_mesh_instances(child))
	return found

## Bigger and longer-lived than play_command_feedback's move/attack rings —
## a ping needs to catch the eye of someone who isn't even looking at this
## part of the map yet, not just confirm a click that was just made.
func play_ping_effect(world_pos: Vector3) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.5
	torus.outer_radius = 0.8
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.85, 0.1, 0.9)
	ring.material_override = mat
	add_child(ring)
	ring.global_position = world_pos + Vector3(0, 0.1, 0)
	ring.scale = Vector3.ONE * 0.3
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3.ONE * 4.0, 1.2) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, 1.2)
	tween.set_parallel(false)
	tween.tween_callback(ring.queue_free)

## --- Ability targeting and impact ---

## Tall enough that the projection still reaches the ground on a slope or a
## ridge edge, short enough not to paint the underside of anything overhead.
const ABILITY_DECAL_HEIGHT: float = 6.0
const ABILITY_TARGET_DECAL_ALPHA: float = 0.5

## Shared by the targeting decal and every impact flash (each tints it through
## its own Decal.modulate), so it's generated once, on first use.
var _ability_circle_texture: ImageTexture = null
var _ability_circle_emission_texture: ImageTexture = null
var _ability_target_decal: Decal = null

## Follows the mouse while an ability is armed (see Main.get_armed_ability),
## sized to what the cast will actually cover.
func update_ability_target_decal() -> void:
	var ability: Ability = main.get_armed_ability()
	var hit: Dictionary = {}
	if ability != null and not main.chat.is_input_open() and not main.game_over:
		hit = main.raycast(get_viewport().get_mouse_position())
	if hit.is_empty():
		if _ability_target_decal:
			_ability_target_decal.visible = false
		return
	if _ability_target_decal == null:
		_ability_target_decal = _make_ability_decal()
		add_child(_ability_target_decal)
	var radius: float = ability.area_radius if ability.kind == Ability.Kind.ACTIVATED_AREA else ability.affected_ally_radius
	_ability_target_decal.size = Vector3(radius * 2.0, ABILITY_DECAL_HEIGHT, radius * 2.0)
	_ability_target_decal.modulate = Color(ability.effect_color, ABILITY_TARGET_DECAL_ALPHA)
	_ability_target_decal.global_position = hit.position
	_ability_target_decal.visible = true

## The RPCs below carry the caster's path plus an ability index rather than
## the Ability itself (a resource can't cross the wire); each peer looks the
## same Ability up off its own copy of the unit. Casts and launches only happen
## on the host, so — same as damage numbers — the host plays its own copy and
## relays to everyone else.

## Charge-up at the caster for the length of the ability's windup — sparks in
## the ability's colour drawn in toward the launch point, and a glow under the
## caster's feet. Tells the target something is coming before it lands.
func relay_cast_windup(unit: Unit, ability_index: int) -> void:
	_play_cast_windup(unit, ability_index)
	if multiplayer.is_server() and multiplayer.multiplayer_peer != null:
		_rpc_cast_windup.rpc(unit.get_path(), ability_index)

@rpc("authority", "call_remote", "reliable")
func _rpc_cast_windup(unit_path: NodePath, ability_index: int) -> void:
	var unit := get_node_or_null(unit_path) as Unit
	if unit:
		_play_cast_windup(unit, ability_index)

func _play_cast_windup(unit: Unit, ability_index: int) -> void:
	var ability := unit.get_ability(ability_index)
	if ability == null or ability.cast_windup <= 0.0 or not unit.is_visible_in_tree():
		return
	var gather := ParticleProcessMaterial.new()
	gather.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	gather.emission_sphere_radius = 0.7
	gather.radial_velocity_min = -2.2
	gather.radial_velocity_max = -1.4
	gather.gravity = Vector3.ZERO
	gather.scale_min = 0.8
	gather.scale_max = 1.6
	var fade := Gradient.new()
	fade.set_color(0, Color(ability.effect_color, 0.0))
	fade.add_point(0.3, ability.effect_color)
	fade.set_color(fade.get_point_count() - 1, Color(ability.effect_color.lightened(0.5), 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	gather.color_ramp = ramp
	var particles := GPUParticles3D.new()
	particles.amount = 18
	particles.lifetime = 0.35
	particles.local_coords = true
	particles.process_material = gather
	particles.draw_pass_1 = _impact_mesh
	unit.add_child(particles)
	particles.global_position = unit.get_ability_launch_position(ability)
	particles.emitting = true

	var glow := _make_ability_decal()
	glow.size = Vector3(2.0, ABILITY_DECAL_HEIGHT, 2.0)
	glow.modulate = Color(ability.effect_color, 0.0)
	unit.add_child(glow)
	glow.position = Vector3.ZERO
	## Bound to the particles, which are freed last, so the tween outlives the
	## glow it frees partway through.
	var tween := particles.create_tween()
	tween.tween_property(glow, "modulate:a", 0.8, ability.cast_windup) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void: particles.emitting = false)
	tween.tween_property(glow, "modulate:a", 0.0, 0.25)
	tween.tween_callback(glow.queue_free)
	## Particles already in the air finish their short life before going.
	tween.tween_interval(particles.lifetime)
	tween.tween_callback(particles.queue_free)

## Host-side entry point, off Unit.ability_launched. `from_pos` is sent as-is
## rather than re-derived on each peer so the visual starts where the host's
## damage timer measured from, even if the caster has since turned.
func relay_ability_launch(ability_index: int, from_pos: Vector3, target_pos: Vector3, unit: Unit) -> void:
	_play_ability_launch(unit, ability_index, from_pos, target_pos)
	if multiplayer.is_server() and multiplayer.multiplayer_peer != null:
		_rpc_ability_launch.rpc(unit.get_path(), ability_index, from_pos, target_pos)

@rpc("authority", "call_remote", "reliable")
func _rpc_ability_launch(unit_path: NodePath, ability_index: int, from_pos: Vector3, target_pos: Vector3) -> void:
	var unit := get_node_or_null(unit_path) as Unit
	if unit:
		_play_ability_launch(unit, ability_index, from_pos, target_pos)

## Cast flash at the caster, then whatever carries the ability to the target,
## then the impact — all timed off Unit.ability_travel_time, the same number
## the host's damage timer uses, so the explosion and the damage land together.
func _play_ability_launch(unit: Unit, ability_index: int, from_pos: Vector3, target_pos: Vector3) -> void:
	var ability := unit.get_ability(ability_index)
	if ability == null:
		return
	var direction := target_pos - from_pos
	direction.y = 0.0
	if ability.cast_effect and main.fog_of_war.is_visible_at(from_pos):
		## An oriented effect (a breath plume) is pushed out by half its width
		## so it starts at the mouth rather than being centred on it.
		var push: float = ability.cast_effect.world_width() * 0.5 if ability.cast_effect.orient_to_direction else 0.0
		_spawn_sprite_effect(ability.cast_effect, from_pos + direction.normalized() * push, direction)
	var travel: float = Unit.ability_travel_time(ability, from_pos, target_pos)
	match ability.projectile_style:
		Ability.ProjectileStyle.FLYING:
			_fly_ability_projectile(ability, from_pos, target_pos, travel)
		Ability.ProjectileStyle.GROUND_WAVE:
			_run_ground_wave(ability, unit.global_position, target_pos, travel)
	if travel <= 0.0:
		_play_ability_impact(ability, target_pos)
	else:
		get_tree().create_timer(travel).timeout.connect(_play_ability_impact.bind(ability, target_pos))

func _fly_ability_projectile(ability: Ability, from_pos: Vector3, target_pos: Vector3, travel: float) -> void:
	if ability.projectile_effect == null or travel <= 0.0:
		return
	var end_pos: Vector3 = target_pos + Vector3.UP * (ability.projectile_effect.world_height() * 0.5)
	var sprite := _make_effect_sprite(ability.projectile_effect)
	sprite.play(SpriteEffect.LOOP)
	add_child(sprite)
	sprite.global_position = from_pos
	var trail: GPUParticles3D = null
	if ability.projectile_trail:
		trail = _make_projectile_trail(ability.effect_color)
		add_child(trail)
		trail.global_position = from_pos
	var arc: float = ability.projectile_arc_height
	var previous := [from_pos]
	var fly := func(t: float) -> void:
		var pos: Vector3 = from_pos.lerp(end_pos, t) + Vector3.UP * arc * sin(t * PI)
		sprite.global_position = pos
		sprite.visible = main.fog_of_war.is_visible_at(pos)
		if trail:
			trail.global_position = pos
			trail.emitting = sprite.visible
		if ability.projectile_effect.orient_to_direction:
			_orient_to_screen_direction(sprite, pos, pos - previous[0])
		previous[0] = pos
	fly.call(0.0)
	var tween := sprite.create_tween()
	tween.tween_method(fly, 0.0, 1.0, travel)
	if trail:
		## Left behind rather than freed with the sprite, so its last sparks
		## finish fading instead of vanishing mid-air on impact.
		tween.tween_callback(func() -> void:
			trail.emitting = false
			get_tree().create_timer(trail.lifetime).timeout.connect(trail.queue_free))
	tween.tween_callback(sprite.queue_free)

## Eruptions marching along the ground from the caster to the target, one
## every wave_spacing, reaching the target exactly when the impact does.
func _run_ground_wave(ability: Ability, from_ground: Vector3, target_pos: Vector3, travel: float) -> void:
	if ability.projectile_effect == null or travel <= 0.0:
		return
	var flat := Vector2(target_pos.x - from_ground.x, target_pos.z - from_ground.z)
	var steps := int(flat.length() / maxf(ability.wave_spacing, 0.1))
	## The last step would sit on the target itself, where the impact goes.
	for i in range(1, steps):
		var t := float(i) / steps
		var pos := from_ground.lerp(target_pos, t)
		get_tree().create_timer(travel * t).timeout.connect(_spawn_ground_effect.bind(ability.projectile_effect, pos, 0.85))

func _play_ability_impact(ability: Ability, target_pos: Vector3) -> void:
	_play_ability_effect(target_pos, ability.area_radius, ability.effect_color, ability.effect_duration, ability.effect_particle_lifetime)
	## Local, not relayed: every peer reaches this on its own timer.
	if ability.impact_shake > 0.0:
		main.camera_rig.shake_at(target_pos, ability.impact_shake)
	if ability.impact_effect == null:
		return
	_spawn_ground_effect(ability.impact_effect, target_pos, 1.0)
	for i in ability.impact_scatter_count:
		## sqrt keeps the scatter even across the disc instead of bunching
		## toward the middle.
		var angle := randf() * TAU
		var distance := sqrt(randf()) * ability.area_radius * 0.85
		var pos := target_pos + Vector3(cos(angle), 0.0, sin(angle)) * distance
		var delay := randf_range(0.03, 0.25)
		get_tree().create_timer(delay).timeout.connect(_spawn_ground_effect.bind(ability.impact_effect, pos, randf_range(0.55, 0.8)))

## Victim-side burning/slowed/stunned, relayed off Unit.status_applied (the
## effects themselves only run on the host).
func relay_status_effects(dot_seconds: float, slow_seconds: float, stun_seconds: float, color: Color, unit: Unit) -> void:
	unit.show_status_effects(dot_seconds, slow_seconds, stun_seconds, color)
	if multiplayer.is_server() and multiplayer.multiplayer_peer != null:
		_rpc_status_effects.rpc(unit.get_path(), dot_seconds, slow_seconds, stun_seconds, color)

@rpc("authority", "call_remote", "reliable")
func _rpc_status_effects(unit_path: NodePath, dot_seconds: float, slow_seconds: float, stun_seconds: float, color: Color) -> void:
	var unit := get_node_or_null(unit_path) as Unit
	if unit:
		unit.show_status_effects(dot_seconds, slow_seconds, stun_seconds, color)

## --- Sprite effects ---

## One-shot flipbook sitting on the ground at `ground_pos`, lifted so the
## bottom of the frame rests on the ground rather than its middle.
func _spawn_ground_effect(effect: SpriteEffect, ground_pos: Vector3, extra_scale: float) -> void:
	var pos: Vector3 = ground_pos + Vector3.UP * (effect.world_height(extra_scale) * 0.5 + effect.height_offset)
	if not main.fog_of_war.is_visible_at(pos):
		return
	_spawn_sprite_effect(effect, pos, Vector3.ZERO, extra_scale)

## One-shot flipbook centred on `world_pos`, freed when the clip ends.
## `direction` only matters for an effect that orients to it.
func _spawn_sprite_effect(effect: SpriteEffect, world_pos: Vector3, direction: Vector3, extra_scale: float = 1.0) -> void:
	var sprite := _make_effect_sprite(effect, extra_scale)
	add_child(sprite)
	sprite.global_position = world_pos
	if effect.orient_to_direction:
		_orient_to_screen_direction(sprite, world_pos, direction)
	sprite.animation_finished.connect(sprite.queue_free)
	sprite.play(SpriteEffect.ONCE)

func _make_effect_sprite(effect: SpriteEffect, extra_scale: float = 1.0) -> AnimatedSprite3D:
	var sprite := AnimatedSprite3D.new()
	sprite.sprite_frames = effect.get_frames()
	sprite.pixel_size = SpriteEffect.BASE_PIXEL_SIZE * effect.scale * extra_scale
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.shaded = not effect.unshaded
	sprite.modulate = effect.tint
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	## Same trick as the command rings: draw after the grass in the transparent
	## pass, so a ground burst isn't swallowed by the blades around it.
	sprite.render_priority = 10
	## Oriented sprites are turned by hand every frame to face the camera (see
	## _orient_to_screen_direction) — a billboard would discard that rotation.
	if not effect.orient_to_direction:
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	return sprite

## Faces the camera like a billboard, but rolled so the sheet's right-facing
## art points along `world_dir` as it appears on screen. Mirrored instead of
## rolled past vertical, so a breath aimed left isn't drawn upside down.
func _orient_to_screen_direction(sprite: SpriteBase3D, world_pos: Vector3, world_dir: Vector3) -> void:
	var camera: Camera3D = main.camera
	if world_dir.length_squared() < 0.000001 or camera.is_position_behind(world_pos):
		return
	var a := camera.unproject_position(world_pos)
	var b := camera.unproject_position(world_pos + world_dir.normalized())
	## Screen y runs down; the roll is measured with y up.
	var angle := atan2(-(b.y - a.y), b.x - a.x)
	sprite.flip_h = absf(angle) > PI * 0.5
	if sprite.flip_h:
		angle = angle - PI if angle > 0.0 else angle + PI
	sprite.global_basis = camera.global_basis * Basis(Vector3.BACK, angle)

## Sparks shed behind a flying projectile — emitted in world space so they
## hang in the air along its path.
func _make_projectile_trail(color: Color) -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.12
	process.direction = Vector3.UP
	process.spread = 180.0
	process.initial_velocity_min = 0.2
	process.initial_velocity_max = 0.6
	process.gravity = Vector3(0, -1.5, 0)
	process.scale_min = 0.7
	process.scale_max = 1.4
	var fade := Gradient.new()
	fade.set_color(0, color.lightened(0.3))
	fade.set_color(1, Color(color, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	var trail := GPUParticles3D.new()
	trail.amount = 28
	trail.lifetime = 0.45
	trail.local_coords = false
	trail.process_material = process
	trail.draw_pass_1 = _impact_mesh
	trail.emitting = true
	return trail

## A flash of the same disc the targeting decal showed, snapping out to full
## size, holding, then fading, plus a ring of sparks in the ability's colour.
## Skipped under fog, where it would give away a fight the viewer can't see.
func _play_ability_effect(world_pos: Vector3, radius: float, color: Color, duration: float, particle_lifetime: float) -> void:
	if not main.fog_of_war.is_visible_at(world_pos):
		return
	var decal := _make_ability_decal()
	decal.size = Vector3(radius * 2.0, ABILITY_DECAL_HEIGHT, radius * 2.0)
	decal.modulate = Color(color, 0.95)
	add_child(decal)
	decal.global_position = world_pos
	decal.scale = Vector3(0.3, 1.0, 0.3)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(decal, "scale", Vector3.ONE, 0.2) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(decal, "modulate:a", 0.0, duration * 0.5) \
			.set_delay(duration * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.set_parallel(false)
	tween.tween_callback(decal.queue_free)

	var sparks := ParticleProcessMaterial.new()
	sparks.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	sparks.emission_ring_axis = Vector3(0, 1, 0)
	sparks.emission_ring_radius = radius * 0.85
	sparks.emission_ring_inner_radius = radius * 0.2
	sparks.emission_ring_height = 0.1
	sparks.direction = Vector3(0, 1, 0)
	sparks.spread = 30.0
	sparks.initial_velocity_min = 1.5
	sparks.initial_velocity_max = 4.0
	sparks.gravity = Vector3(0, -4.0, 0)
	sparks.damping_min = 0.5
	sparks.damping_max = 1.5
	sparks.scale_min = 1.2
	sparks.scale_max = 2.4
	## Fades each spark out over its life rather than it blinking out at the
	## end, which a long effect_particle_lifetime would make very noticeable.
	var fade := Gradient.new()
	fade.set_color(0, color)
	fade.set_color(1, Color(color, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	sparks.color_ramp = ramp
	_spawn_burst(sparks, world_pos + Vector3(0, RALLY_DUST_HEIGHT, 0), int(clampf(radius * 14.0, 20.0, 80.0)), particle_lifetime)

## --- Formation drag preview ---

## One ghost disc per slot while the player right-drags a formation (see
## Main._update_formation_drag). Sized to a unit's footprint (0.4 capsule, see
## scenes/units/unit.tscn) with a little room around it, so a tight block of
## discs reads as how tight the finished formation will actually stand.
const FORMATION_PREVIEW_DISC_SIZE: float = 1.0
const FORMATION_PREVIEW_COLOR: Color = Color(1.0, 1.0, 1.0, 0.45)

## Pooled rather than rebuilt per mouse-motion event — a drag fires dozens of
## those a second, and the slot count only changes when the selection does.
var _formation_preview_decals: Array[Decal] = []

func show_formation_preview(slots: Array[Vector3]) -> void:
	while _formation_preview_decals.size() < slots.size():
		var decal := _make_ability_decal()
		decal.size = Vector3(FORMATION_PREVIEW_DISC_SIZE, ABILITY_DECAL_HEIGHT, FORMATION_PREVIEW_DISC_SIZE)
		decal.modulate = FORMATION_PREVIEW_COLOR
		add_child(decal)
		_formation_preview_decals.append(decal)
	for i in _formation_preview_decals.size():
		var decal := _formation_preview_decals[i]
		decal.visible = i < slots.size()
		if decal.visible:
			decal.global_position = slots[i]

func hide_formation_preview() -> void:
	for decal in _formation_preview_decals:
		decal.visible = false

func _make_ability_decal() -> Decal:
	var decal := Decal.new()
	_build_ability_circle_textures()
	decal.texture_albedo = _ability_circle_texture
	## Emission too, so the circle reads the same in a shadowed valley as in
	## full sun rather than vanishing into dark terrain.
	decal.texture_emission = _ability_circle_emission_texture
	decal.emission_energy = 0.6
	decal.upper_fade = 0.15
	decal.lower_fade = 0.15
	return decal

## A faint filled disc with a solid rim, white so Decal.modulate can colour it.
## Decal emission is added across the whole projection box and ignores alpha,
## so it gets its own copy with the alpha baked into the colour — black (no
## glow) outside the circle — or the decal lights up as a square.
func _build_ability_circle_textures() -> void:
	if _ability_circle_texture:
		return
	const SIZE: int = 256
	const FILL_ALPHA: float = 0.3
	var albedo := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var emission := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2(SIZE, SIZE) * 0.5
	for y in SIZE:
		for x in SIZE:
			var d: float = (Vector2(x + 0.5, y + 0.5) - center).length() / (SIZE * 0.5)
			var alpha: float = lerpf(FILL_ALPHA, 1.0, smoothstep(0.86, 0.94, d)) * (1.0 - smoothstep(0.96, 1.0, d))
			albedo.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
			emission.set_pixel(x, y, Color(alpha, alpha, alpha, 1.0))
	albedo.generate_mipmaps()
	emission.generate_mipmaps()
	_ability_circle_texture = ImageTexture.create_from_image(albedo)
	_ability_circle_emission_texture = ImageTexture.create_from_image(emission)
