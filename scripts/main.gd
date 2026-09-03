extends Node3D

const TEAM_COLORS: Array[Color] = [
	Color(0.25, 0.55, 1.0), Color(1.0, 0.35, 0.3), Color(0.35, 1.0, 0.45), Color(1.0, 0.85, 0.3)
]

## Command-card hotkeys. The camera reads W/A/S/D/Q/E via raw Input.is_key_pressed()
## polling every frame (see rts_camera.gd), completely bypassing _unhandled_input,
## so none of these can safely use those letters — set_input_as_handled() would
## not stop the camera from also reacting to them.
const UNIT_MOVE_KEY: Key = KEY_M
const UNIT_STOP_KEY: Key = KEY_H
const UNIT_ATTACK_KEY: Key = KEY_F
const UNIT_PATROL_KEY: Key = KEY_P
## Only shown/live when at least one selected unit has can_build; opens the
## same construction menu the idle action panel shows, reusing BUILDING_HOTKEYS
## for the actual building choice — safe since only one of the two menus is
## ever live for a given selection state.
const UNIT_BUILD_KEY: Key = KEY_B
## Assigned by position in a Monarch's monarch_abilities, same convention as
## PRODUCIBLE_HOTKEYS/BUILDING_HOTKEYS below — a passive ability still claims
## a slot (shown disabled) so hotkeys stay stable regardless of ability order.
const MONARCH_ABILITY_HOTKEYS: Array[Key] = [KEY_R, KEY_T, KEY_Y, KEY_U]
const PRODUCIBLE_HOTKEYS: Array[Key] = [KEY_I, KEY_J, KEY_K, KEY_L]
const BUILDING_HOTKEYS: Array[Key] = [KEY_Z, KEY_X, KEY_C, KEY_V, KEY_B, KEY_N, KEY_G]
## The action panel's grid always has exactly this many slots (4 columns x 3
## rows), padded with blank placeholders, so its size never changes with context.
const ACTION_PANEL_SLOT_COUNT: int = 12

## Same list (and order) as lobby.tscn's Lobby.available_factions — that
## shared order is what a "faction_index" in Network.players refers to.
@export var available_factions: Array[Faction] = []

@onready var camera: Camera3D = $CameraRig/Yaw/Pitch/Camera3D
@onready var camera_rig: Node3D = $CameraRig
@onready var selection_box: ColorRect = $UI/SelectionBox
@onready var resource_label: RichTextLabel = $UI/ResourceLabel
@onready var units_root: Node3D = $Units
@onready var unit_spawner: MultiplayerSpawner = $UnitSpawner
@onready var buildings_root: Node3D = $Buildings
@onready var building_spawner: MultiplayerSpawner = $BuildingSpawner
@onready var player_spawn_points: Node3D = $PlayerSpawnPoints

@onready var info_panel: PanelContainer = $UI/InfoPanel
@onready var info_panel_name_label: Label = $UI/InfoPanel/Margin/VBox/BuildingNameLabel
@onready var info_panel_content: VBoxContainer = $UI/InfoPanel/Margin/VBox/InfoContainer

## Single contextual action panel — always visible, its grid's contents and
## title change with the selection: nothing selected shows the construction
## menu, a selected building shows its producibles, selected units show the
## Move/Stop/Attack/Patrol commands.
@onready var action_panel_title: Label = $UI/ActionPanel/Margin/VBox/Title
@onready var action_panel_grid: GridContainer = $UI/ActionPanel/Margin/VBox/Grid

@onready var chat_log: RichTextLabel = $UI/ChatLog
@onready var chat_input: LineEdit = $UI/ChatInput

## Non-positional (unlike Unit/ProductionBuilding's OnSelectSoundEffect) since
## this is feedback for the local player's own click/hotkey, not something
## happening at a world location — it should always be clearly audible
## regardless of camera position.
@onready var command_audio_player: AudioStreamPlayer = $UI/CommandAudioPlayer
## One played at random whenever a command is actually issued — by button
## click or hotkey, both funnel through the same dispatch functions below —
## covering unit orders (move/attack/stop/patrol/build/promote/abilities),
## confirmed building placement, and queuing production/upgrades.
@export var on_command_sound_effects: Array[AudioStream] = []
## Played (locally, throttled) whenever one of the local player's own units or
## buildings takes damage — see _maybe_alert_under_attack.
@export var on_under_attack_sound_effects: Array[AudioStream] = []

@onready var ui_root: Node = $UI
@onready var minimap: Control = $UI/Minimap

func _play_command_sound() -> void:
	AudioUtils.play_random(command_audio_player, on_command_sound_effects)

## Purely local (like the sound above and the rally marker) — a quick
## expanding, fading ring at the clicked ground point, so a right-click order
## has an immediate visual confirmation beyond just the sound. White for a
## plain move, red for an attack/attack-move order.
func _play_command_feedback(world_pos: Vector3, is_attack: bool) -> void:
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

## Persistent (until reached/cleared) flag marking one point in a unit's
## shift-drawn path — see _path_markers. Only actually shown while that unit
## is selected — see _update_path_markers.
func _add_path_marker(unit: Unit, world_pos: Vector3) -> void:
	var markers: Array = _path_markers.get(unit, [])

	var marker := Node3D.new()
	add_child(marker)
	marker.global_position = world_pos + Vector3(0, 0.05, 0)
	marker.visible = selected_units.has(unit)

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

func _clear_path_markers(unit: Unit) -> void:
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
func _update_path_markers() -> void:
	for unit in _path_markers.keys():
		if not is_instance_valid(unit):
			_clear_path_markers(unit)
			continue
		var markers: Array = _path_markers[unit]
		while not markers.is_empty() and is_instance_valid(markers[0]) \
				and unit.global_position.distance_to(markers[0].global_position) <= PATH_MARKER_ARRIVAL_DISTANCE:
			markers[0].queue_free()
			markers.pop_front()
		if markers.is_empty():
			_path_markers.erase(unit)
			continue
		var is_selected := selected_units.has(unit)
		for marker in markers:
			if is_instance_valid(marker):
				marker.visible = is_selected

@onready var game_over_panel: PanelContainer = $UI/GameOverPanel
@onready var game_over_label: Label = $UI/GameOverPanel/Margin/VBox/ResultLabel

## Local-only overlay (see Settings autoload) — does not pause the match for
## anyone else, just gates this peer's own input and shows volume sliders.
@onready var pause_menu: PanelContainer = $UI/PauseMenu
@onready var master_volume_slider: HSlider = $UI/PauseMenu/Margin/VBox/MasterRow/Slider
@onready var music_volume_slider: HSlider = $UI/PauseMenu/Margin/VBox/MusicRow/Slider
@onready var ambience_volume_slider: HSlider = $UI/PauseMenu/Margin/VBox/AmbienceRow/Slider
@onready var sfx_volume_slider: HSlider = $UI/PauseMenu/Margin/VBox/SfxRow/Slider

var selected_units: Array[Unit] = []
var selected_building: ProductionBuilding = null
## Left-click-selected resource node (tree/berry bush/gold deposit/farm),
## shown read-only in the info panel with its remaining amount — mutually
## exclusive with selected_building/selected_units, same as those are with
## each other.
var selected_resource: Gatherable = null
var drag_start: Vector2 = Vector2.ZERO
var dragging: bool = false
## Captured from the press event (double_click is only ever set there, not on
## release) and consumed by _finish_selection once the button comes back up.
var _pending_double_click: bool = false
## Unit -> Array[Node3D], the flag markers for its still-pending shift-drawn
## waypoints, in order. Purely a local visual aid on this client (not driven
## by the host's real, authoritative order_queue) so a multi-point path is
## visible on screen after being planned out — see _add_path_marker/
## _update_path_markers/_clear_path_markers.
var _path_markers: Dictionary = {}
const PATH_MARKER_ARRIVAL_DISTANCE: float = 1.0

## "" | "move" | "attack" | "patrol" — armed by a command-card button/hotkey,
## consumed by the next left-click (see _handle_pending_order_input).
var pending_order_mode: String = ""
## True once the first click of the current patrol-targeting session has been
## sent, so later shift-clicks append a waypoint instead of starting a new patrol.
var _patrol_started_this_session: bool = false
## Armed by pressing a Monarch's activated-ability button; consumed by the
## next left-click, same as pending_order_mode == "move"/"attack", but needs
## its own state since the ability only ever targets its own Monarch unit,
## not the whole current selection. {"unit": Unit, "ability_index": int} or {}.
var _armed_monarch_ability: Dictionary = {}
## Which unit selection the command panel's buttons were last built for, so
## _process() only rebuilds them when the selection actually changed.
var _last_command_panel_units: Array[Unit] = []

## True while the action panel is showing the construction menu on behalf of
## a selected unit's Build button (as opposed to the always-available idle
## construction menu when nothing is selected).
var _showing_build_submenu: bool = false
## Captured when a construction button is pressed while _showing_build_submenu
## is true, so the host can send these units to build what gets placed.
var _pending_builder_paths: Array[NodePath] = []
## True once a placement has been confirmed with Shift held — the current
## placement (or the next one, even a different building type — see
## _on_construction_button_pressed) continues that same builder chain rather
## than starting a fresh one. See _confirm_placement/_rpc_request_build.
var _build_queue_active: bool = false

## Command panel info section — built once per selection change, then only
## had their values (not structure) updated every frame, to avoid rebuilding
## Control nodes 60 times a second for something that just needs a number to move.
var _info_progress_bar: ProgressBar = null
var _info_empty_label: Label = null
var _info_slot_row: HBoxContainer = null
var _info_last_queue_size: int = -1
## item_name -> its producible button's queued-count badge; updated every
## frame in _refresh_building_info() from ProductionBuilding.synced_queue_counts.
var _info_producible_badges: Dictionary = {}
var _info_stats_label: Label = null
## Parallel to selected_units when more than one is selected.
var _info_unit_portrait_bars: Array[ProgressBar] = []
var _info_resource_label: Label = null

## Purely local UI state: which units/buildings belong to each numbered
## control group (Ctrl+1-9 assigns, 1-9 selects / recalls camera).
var control_groups: Dictionary = {}
## Which group number the CURRENT selection came from via a number-key press
## — cleared by any other selection action, so pressing the same digit twice
## in a row (with nothing else selected in between) means "snap the camera
## there" rather than "reselect it".
var _active_group_number: int = -1

const CLICK_DRAG_THRESHOLD: float = 6.0

const VALID_GHOST_COLOR: Color = Color(0.3, 1.0, 0.3, 0.45)
const INVALID_GHOST_COLOR: Color = Color(1.0, 0.3, 0.3, 0.45)
## Minimum surface-normal Y component a placement point must have to count as
## "flat enough to build on" — roughly cos(41°). Below this the raycast hit a
## slope/cliff face (e.g. TileMapLayer3D terrain) rather than open ground.
const MAX_BUILD_SLOPE_NORMAL_Y: float = 0.75
## How many points around a footprint's edge (in addition to its center) get
## checked for flatness — catches a building whose center sits on flat ground
## but whose edge would overhang a nearby cliff.
const FOOTPRINT_SAMPLE_COUNT: int = 8
## Max height difference tolerated between the footprint's center and any
## edge sample — rejects straddling a level change even where both sides are
## individually flat (e.g. half on a raised terrace, half on the ground below).
const MAX_FOOTPRINT_HEIGHT_VARIANCE: float = 0.3

var placing_type: BuildingType = null
## Root of a stripped-down, translucent copy of the real building model (not
## the actual networked building) — purely a local visual preview.
var placement_ghost: Node3D = null
## (material, base_albedo_color) pairs collected while building the ghost, so
## its valid/invalid tint can be updated every frame without re-walking the
## node tree — see _set_ghost_valid().
var _ghost_surfaces: Array = []
var placement_valid: bool = false
## Only set when placing_type.requires_deposit — the specific world node the
## ghost is currently snapped to, sent to the host so it can position the
## building there itself rather than trusting a client-supplied position.
var _placement_target: Gatherable = null

## Purely local visual: only ever shown for the local player's own selected
## building, so it's built on demand rather than living in a networked scene.
var rally_marker: Node3D = null

## Purely local visual too — just feedback for whatever the mouse is
## currently over, built on demand like rally_marker.
var hover_ring: MeshInstance3D = null
## The last Unit/ProductionBuilding/Gatherable single-left-clicked (own or
## not) — keeps the hover ring showing on it even when the mouse moves away,
## until a different single-click or a click on empty space replaces/clears it.
var clicked_ring_target: Node3D = null

## Which faction each peer picked in the lobby, resolved once in _spawn_player_base
## and read by every peer thereafter (both for their own UI and, on the host,
## for validating build requests against the sender's actual roster).
var faction_by_peer: Dictionary = {}
## Host-only bookkeeping: which team index / Town Center belongs to each peer.
var team_index_by_peer: Dictionary = {}
var town_centers: Dictionary = {}
## Host-only: peer_id -> how many is_main_base buildings they still have.
var main_base_count_by_peer: Dictionary = {}
var defeated_peers: Dictionary = {}
var game_over: bool = false

const MAX_CHAT_LINES: int = 8
## Extend this when new resource types (Stone, ...) are added.
const DEBUG_RESOURCE_TYPES: Array[ResourceType] = [
	preload("res://resources/wood_resource_type.tres"),
	preload("res://resources/food_resource_type.tres"),
	preload("res://resources/gold_resource_type.tres"),
]
var chat_lines: Array[String] = []

## resource_label shows every resource total plus population on one line;
## rebuilt in full on any single change since there are only a handful of values.
var _resource_totals: Dictionary = {}
var _population_used: int = 0
var _population_cap: int = 0

## resource_name -> true while it's one of the ones flashing red because the
## last attempted purchase couldn't afford it — see _flash_missing_resources.
var _flashing_resource_names: Dictionary = {}
var _resource_flash_on: bool = false
var _resource_flash_tween: Tween
const RESOURCE_FLASH_CYCLE_COUNT: int = 4
const RESOURCE_FLASH_INTERVAL: float = 0.15

func _ready() -> void:
	ResourceStockpile.changed.connect(_on_stockpile_changed)
	Population.changed.connect(_on_population_changed)
	_populate_construction_buttons()

	unit_spawner.spawn_function = _spawn_unit_from_data
	building_spawner.spawn_function = _spawn_building_from_data
	if multiplayer.is_server():
		_spawn_all_players()

	chat_input.text_submitted.connect(_on_chat_submitted)
	minimap.ping_requested.connect(_on_minimap_ping_requested)

	game_over_panel.visible = false
	$UI/GameOverPanel/Margin/VBox/ReturnButton.pressed.connect(_on_return_to_lobby_pressed)

	## Built in code rather than saved in the scene — it's just a full-screen
	## color wash, nothing worth hand-authoring, and this avoids yet another
	## edit to the already-enormous main.tscn.
	_under_attack_flash = ColorRect.new()
	_under_attack_flash.color = Color(1.0, 0.15, 0.1, 0.0)
	_under_attack_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_under_attack_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.add_child(_under_attack_flash)

	pause_menu.visible = false
	master_volume_slider.value = Settings.volumes["Master"] * 100.0
	music_volume_slider.value = Settings.volumes["Music"] * 100.0
	ambience_volume_slider.value = Settings.volumes["Ambience"] * 100.0
	sfx_volume_slider.value = Settings.volumes["SFX"] * 100.0
	master_volume_slider.value_changed.connect(func(v): Settings.set_bus_volume("Master", v / 100.0))
	music_volume_slider.value_changed.connect(func(v): Settings.set_bus_volume("Music", v / 100.0))
	ambience_volume_slider.value_changed.connect(func(v): Settings.set_bus_volume("Ambience", v / 100.0))
	sfx_volume_slider.value_changed.connect(func(v): Settings.set_bus_volume("SFX", v / 100.0))
	$UI/PauseMenu/Margin/VBox/ResumeButton.pressed.connect(_close_pause_menu)
	$UI/PauseMenu/Margin/VBox/LeaveButton.pressed.connect(_on_return_to_lobby_pressed)

func _open_pause_menu() -> void:
	pause_menu.visible = true

func _close_pause_menu() -> void:
	pause_menu.visible = false

func _my_peer_id() -> int:
	return multiplayer.get_unique_id()

## Resolves (and caches) the local player's own faction on demand, rather than
## relying on a one-time _ready() population — _my_peer_id() can't be trusted
## to be stable/meaningful before a peer is ever assigned (e.g. running
## main.tscn directly without going through the lobby).
func _my_faction() -> Faction:
	var id: int = _my_peer_id()
	if not faction_by_peer.has(id):
		faction_by_peer[id] = _faction_for_peer(id)
	return faction_by_peer[id]

## --- Player / unit / building spawning (host only) ---

func _spawn_all_players() -> void:
	var peer_ids: Array = [1]
	if multiplayer.multiplayer_peer != null:
		peer_ids.append_array(multiplayer.get_peers())
	for i in peer_ids.size():
		_spawn_player_base(peer_ids[i], i)

## Public lookup so scripts outside main.gd (e.g. objective.gd, reached via
## get_tree().current_scene) can re-tint a unit/building on a post-spawn
## ownership change without duplicating TEAM_COLORS/team_index_by_peer.
func get_team_tint(peer_id: int) -> Color:
	var team_index: int = team_index_by_peer.get(peer_id, 0)
	return TEAM_COLORS[team_index % TEAM_COLORS.size()]

## index < 0 (or unset) defaults everyone to available_factions[0] — the safe
## fallback for the established direct-run-main.tscn-in-editor workflow, which
## bypasses the lobby (and thus Network.players) entirely.
func _faction_for_peer(peer_id: int) -> Faction:
	var faction_index: int = Network.players.get(peer_id, {}).get("faction_index", 0)
	return available_factions[faction_index] if faction_index < available_factions.size() else available_factions[0]

func _spawn_player_base(peer_id: int, index: int) -> void:
	var spawn_point: PlayerSpawnPoint = player_spawn_points.get_child(index % player_spawn_points.get_child_count())
	var tint: Color = TEAM_COLORS[index % TEAM_COLORS.size()]
	team_index_by_peer[peer_id] = index
	var faction: Faction = _faction_for_peer(peer_id)
	faction_by_peer[peer_id] = faction

	## Free starting villagers never went through ProductionBuilding.enqueue()
	## (which is where population is normally reserved), so it has to be
	## reserved for them here instead or they'd stand outside the population
	## count entirely.
	var unit_positions: Array[Vector3] = spawn_point.get_unit_positions()
	for i in mini(faction.starting_units.size(), unit_positions.size()):
		var starting_unit: Unit = unit_spawner.spawn({
			"scene_path": faction.starting_units[i].resource_path,
			"peer_id": peer_id,
			"tint": tint,
			"position": unit_positions[i],
		})
		Population.reserve(peer_id, starting_unit.population_cost)

	## A map/faction pairing can start a player with more than one building
	## (extra BuildingSpawns markers + a matching extra Faction.starting_buildings
	## entry) — town_centers[peer_id] is whichever one is flagged as the real
	## main base, not just whichever spawned first.
	var building_positions: Array[Vector3] = spawn_point.get_building_positions()
	for i in mini(faction.starting_buildings.size(), building_positions.size()):
		var building: ProductionBuilding = building_spawner.spawn({
			"scene_path": faction.starting_buildings[i].resource_path,
			"peer_id": peer_id,
			"position": building_positions[i],
			"tint": tint,
		})
		if building.is_main_base or not town_centers.has(peer_id):
			town_centers[peer_id] = building
		## Each starting building is placed pre-built (begin_construction() is
		## never called for it), so its population capacity is granted
		## immediately rather than waiting on a construction_finished signal
		## that will never fire.
		if building.population_capacity > 0:
			Population.add_cap(peer_id, building.population_capacity)
			building.destroyed.connect(
				func(): Population.add_cap(peer_id, -building.population_capacity), CONNECT_ONE_SHOT
			)

func _spawn_unit_from_data(data: Dictionary) -> Node:
	var scene: PackedScene = load(data.scene_path)
	var unit: Unit = scene.instantiate()
	unit.owner_peer_id = data.peer_id
	unit.team_tint = data.tint
	unit.position = data.position
	unit.animation_changed.connect(_on_unit_animation_changed.bind(unit))
	unit.projectile_fired.connect(_on_unit_projectile_fired.bind(unit))
	unit.damaged.connect(_relay_damage_number.bind(unit))
	unit.resource_deposited.connect(_on_unit_resource_deposited.bind(unit))
	unit.order_completed.connect(_on_unit_order_completed.bind(unit))
	return unit

## RPCs declared directly on dynamically-spawned Unit nodes weren't reaching
## clients, so units relay animation changes here and this (statically present,
## proven-reliable) node broadcasts them instead. Sprite flip is NOT relayed
## this way — it's inherently viewer-dependent, so each peer computes it locally
## from the unit's synced rotation and that peer's own camera (see Unit._process()).
func _on_unit_animation_changed(anim_name: String, unit: Unit) -> void:
	if multiplayer.is_server() and multiplayer.multiplayer_peer != null:
		_rpc_unit_animation.rpc(unit.get_path(), anim_name)

@rpc("authority", "call_remote", "reliable")
func _rpc_unit_animation(unit_path: NodePath, anim_name: String) -> void:
	var unit := get_node_or_null(unit_path) as Unit
	if unit:
		unit.sprite.play(anim_name)

## Order-dispatch functions below only ever run on the host (inside its
## RPC handlers), so — same reasoning as animation_changed above — playing
## the sound directly there would only ever be heard on the host's own
## machine. This plays it locally right away, then relays to every other peer.
func _play_unit_order_sound(unit: Unit, kind: Unit.OrderSoundKind) -> void:
	unit.play_order_sound(kind)
	if multiplayer.is_server() and multiplayer.multiplayer_peer != null:
		_rpc_unit_order_sound.rpc(unit.get_path(), kind)

@rpc("authority", "call_remote", "reliable")
func _rpc_unit_order_sound(unit_path: NodePath, kind: Unit.OrderSoundKind) -> void:
	var unit := get_node_or_null(unit_path) as Unit
	if unit:
		unit.play_order_sound(kind)

## projectile_fired only ever fires on the host's own copy (only the host runs
## combat logic — see Unit._physics_process), so the host spawns its own local
## visual immediately here and relays to every other peer to do the same. Real
## damage timing is decided entirely by the host's own Unit._pending_projectile_hits;
## this is purely cosmetic and never affects gameplay outcome.
func _on_unit_projectile_fired(target: Node3D, unit: Unit) -> void:
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

## Damage taken and resources deposited only ever happen on the host (both
## take_damage() and Unit._deposit_and_continue() are authority-gated), so —
## same reasoning as animation/projectile relaying above — the host spawns its
## own local popup immediately and relays to every other peer to do the same.
func _relay_damage_number(amount: int, node: Node3D) -> void:
	_show_damage_feedback(node, amount)
	if multiplayer.is_server() and multiplayer.multiplayer_peer != null:
		_rpc_damage_number.rpc(node.get_path(), amount)

@rpc("authority", "call_remote", "reliable")
func _rpc_damage_number(node_path: NodePath, amount: int) -> void:
	var node := get_node_or_null(node_path) as Node3D
	if node:
		_show_damage_feedback(node, amount)

## Floating number for anything damageable; the hit flash only applies to
## Unit (buildings have no sprite to flash).
func _show_damage_feedback(node: Node3D, amount: int) -> void:
	_spawn_floating_number(node.global_position + Vector3(0, 1.2, 0), str(amount), Color(1.0, 0.3, 0.25))
	if node is Unit:
		node.play_hit_flash()
	_maybe_alert_under_attack(node)

## Purely local per-viewer decision (this runs identically for every peer,
## on both the host's immediate call and every client's relayed RPC) — only
## fires when it's specifically *this* viewer's own stuff being hit, throttled
## so a sustained attack pings/flashes once every few seconds instead of once
## per hit. Records where, so KEY_BACKSPACE can jump the camera there.
const UNDER_ATTACK_ALERT_COOLDOWN_MS: int = 6000
var _last_under_attack_alert_ms: int = -UNDER_ATTACK_ALERT_COOLDOWN_MS
var _last_attack_position: Vector3 = Vector3.ZERO
var _has_attack_alert: bool = false
var _under_attack_flash: ColorRect

func _maybe_alert_under_attack(node: Node3D) -> void:
	var node_owner_peer_id: int = -1
	if node is Unit:
		node_owner_peer_id = (node as Unit).owner_peer_id
	elif node is ProductionBuilding:
		node_owner_peer_id = (node as ProductionBuilding).owner_peer_id
	if node_owner_peer_id != _my_peer_id():
		return
	var now := Time.get_ticks_msec()
	if now - _last_under_attack_alert_ms < UNDER_ATTACK_ALERT_COOLDOWN_MS:
		return
	_last_under_attack_alert_ms = now
	_last_attack_position = node.global_position
	_has_attack_alert = true
	AudioUtils.play_random(command_audio_player, on_under_attack_sound_effects)
	_under_attack_flash.color.a = 0.0
	var tween := create_tween()
	tween.tween_property(_under_attack_flash, "color:a", 0.35, 0.1)
	tween.tween_property(_under_attack_flash, "color:a", 0.0, 1.0)

func _jump_to_last_attack() -> void:
	if not _has_attack_alert:
		return
	camera_rig.global_position.x = _last_attack_position.x
	camera_rig.global_position.z = _last_attack_position.z

func _on_unit_resource_deposited(amount: int, color: Color, unit: Unit) -> void:
	_spawn_floating_number(unit.global_position + Vector3(0, 1.2, 0), "+%d" % amount, color)
	if multiplayer.is_server() and multiplayer.multiplayer_peer != null:
		_rpc_resource_number.rpc(unit.get_path(), amount, color)

@rpc("authority", "call_remote", "reliable")
func _rpc_resource_number(unit_path: NodePath, amount: int, color: Color) -> void:
	var unit := get_node_or_null(unit_path) as Unit
	if unit:
		_spawn_floating_number(unit.global_position + Vector3(0, 1.2, 0), "+%d" % amount, color)

## Purely local cosmetic popup — rises and fades in place, then frees itself.
## Shared by damage numbers (red, flat integer) and resource numbers ("+N" in
## the resource's own display_color).
func _spawn_floating_number(world_pos: Vector3, text: String, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 56
	label.outline_size = 12
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	add_child(label)
	label.global_position = world_pos + Vector3(randf_range(-0.3, 0.3), 0.0, randf_range(-0.3, 0.3))
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y + 1.2, 0.9) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.9).set_delay(0.3)
	tween.set_parallel(false)
	tween.tween_callback(label.queue_free)

## Hand-placed buildings (currently just Objective guards' buildings) never
## go through _spawn_building_from_data below, so without this their
## item_completed/destroyed signals have no listener and producing a unit
## silently does nothing. Called by objective.gd once per building at _ready.
func register_objective_building(building: ProductionBuilding) -> void:
	building.item_completed.connect(_on_building_item_completed.bind(building))
	building.destroyed.connect(_on_building_destroyed.bind(building))
	building.damaged.connect(_relay_damage_number.bind(building))

## Most buildable structures are ProductionBuildings (Town Center, Barracks,
## House), but Farm is a buildable Gatherable (no construction/production
## queue, just gathered from directly) — so this has to handle both instead
## of assuming ProductionBuilding.
func _spawn_building_from_data(data: Dictionary) -> Node:
	var scene: PackedScene = load(data.scene_path)
	var node: Node = scene.instantiate()
	node.position = data.position

	if node is ProductionBuilding:
		var building: ProductionBuilding = node
		building.owner_peer_id = data.peer_id
		building.team_tint = data.get("tint", Color.WHITE)
		building.item_completed.connect(_on_building_item_completed.bind(building))
		building.destroyed.connect(_on_building_destroyed.bind(building))
		building.damaged.connect(_relay_damage_number.bind(building))
		building.construction_finished.connect(_on_building_construction_finished.bind(building))
		if multiplayer.is_server() and building.is_main_base:
			main_base_count_by_peer[data.peer_id] = main_base_count_by_peer.get(data.peer_id, 0) + 1
		if data.has("deposit_path"):
			## Resolved independently on every peer (Gatherables aren't
			## networked nodes, but every peer has the same static resource
			## nodes at the same NodePath, so this still lines up correctly).
			building.linked_deposit = get_node_or_null(data.deposit_path) as Gatherable
	elif node is Gatherable:
		## Unlike natural resources (trees, berry bushes, gold mines — always
		## owner_peer_id 0), a player-built Farm is locked to whoever built it.
		node.owner_peer_id = data.peer_id

	return node

## --- Win condition (host only) ---

func _on_building_destroyed(building: ProductionBuilding) -> void:
	if not multiplayer.is_server() or not building.is_main_base or game_over:
		return
	var peer_id: int = building.owner_peer_id
	main_base_count_by_peer[peer_id] = maxi(main_base_count_by_peer.get(peer_id, 1) - 1, 0)
	if main_base_count_by_peer[peer_id] <= 0 and not defeated_peers.has(peer_id):
		defeated_peers[peer_id] = true
		_check_for_game_over()

func _check_for_game_over() -> void:
	var all_peers: Array = main_base_count_by_peer.keys()
	if all_peers.size() <= 1:
		return
	var remaining: Array = []
	for peer_id in all_peers:
		if not defeated_peers.has(peer_id):
			remaining.append(peer_id)
	if remaining.size() <= 1:
		game_over = true
		var winner_id: int = remaining[0] if remaining.size() == 1 else -1
		_rpc_game_over.rpc(winner_id)

@rpc("authority", "call_local", "reliable")
func _rpc_game_over(winner_peer_id: int) -> void:
	game_over = true
	game_over_panel.visible = true
	if winner_peer_id == -1:
		game_over_label.text = "Draw!"
	elif winner_peer_id == _my_peer_id():
		game_over_label.text = "Victory!"
	else:
		game_over_label.text = "Defeat"

func _on_return_to_lobby_pressed() -> void:
	Network.leave_game()
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")

func _on_building_item_completed(item: ProducibleItem, building: ProductionBuilding) -> void:
	if not multiplayer.is_server():
		return
	if item.kind == ProducibleItem.Kind.UPGRADE:
		building._purchased_upgrades.append(item)
		## Extension point: a future upgrade effect is another optional flag
		## on ProducibleItem plus a matching `if` here.
		if item.unlocks_monarch_promotion:
			building.can_promote_monarch = true
		if item.upgrade_bonus != 0:
			UnitUpgrades.add_bonus(building.owner_peer_id, item.upgrade_category, item.upgrade_stat, item.upgrade_bonus)
		_rpc_display_chat.rpc_id(building.owner_peer_id, "Upgrade complete: %s" % item.item_name)
		return
	if item.kind != ProducibleItem.Kind.UNIT or item.unit_scene == null:
		return
	var spawn_point: Node3D = building.get_node_or_null(building.spawn_point_path)
	var spawn_pos: Vector3 = spawn_point.global_position if spawn_point else building.global_position
	## A previously-spawned, un-ordered unit may still be standing exactly on the
	## spawn point; spawning a new one at those identical coordinates makes their
	## avoidance radii perfectly overlap, which sends NavigationAgent3D's RVO
	## avoidance into a degenerate case (near-zero separation) that can fling one
	## of them across the map trying to resolve it. A small jitter keeps spawns
	## from ever landing exactly on top of each other.
	spawn_pos += Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.6, 0.6))
	var team_index: int = team_index_by_peer.get(building.owner_peer_id, 0)
	## population_cost isn't passed here — the spawned scene's own Unit.population_cost
	## (set right on the unit for balancing, see get_population_cost()) is already authoritative.
	var unit: Unit = unit_spawner.spawn({
		"scene_path": item.unit_scene.resource_path,
		"peer_id": building.owner_peer_id,
		"tint": TEAM_COLORS[team_index % TEAM_COLORS.size()],
		"position": spawn_pos,
	})
	if building.can_rally and building.has_rally_point:
		var rally_target: Node = get_node_or_null(building.rally_target_path) \
				if building.rally_target_path != NodePath() else null
		## Same reasoning as spawn_pos's jitter above: every unit this building
		## ever produces would otherwise be sent to this exact same coordinate.
		## Once a few units are already standing there, a new arrival's
		## avoidance fights the crowd for that one precise point and can get
		## stuck jittering right next to them, stuck in the walk animation
		## instead of ever settling — a small spread lets them actually
		## cluster around the rally point instead of stacking on it. Only
		## meaningful for a plain-ground rally; a rally_target (gather/attack/
		## build) makes _dispatch_smart_command path to the target node
		## itself and ignore this position entirely.
		var rally_pos := building.rally_point + Vector3(randf_range(-1.2, 1.2), 0.0, randf_range(-1.2, 1.2))
		_dispatch_smart_command(unit, rally_target, rally_pos, false)

## Only ever fires host-side (construction progress is host-authoritative),
## so the chat line is sent explicitly to whichever peer owns the building
## rather than shown locally — same reasoning as the debug command replies
## above, just the message differs.
func _on_building_construction_finished(building: ProductionBuilding) -> void:
	if not multiplayer.is_server():
		return
	_rpc_display_chat.rpc_id(building.owner_peer_id, "Construction complete: %s" % building.building_name)

func _get_dropoff_for(peer_id: int) -> Node3D:
	var town_center: ProductionBuilding = town_centers.get(peer_id)
	if town_center == null:
		return null
	return town_center.get_node_or_null("DropoffPoint")

func _process(_delta: float) -> void:
	if selected_building:
		_refresh_building_info()
	elif not selected_units.is_empty():
		## Catches every way selected_units can change (drag-select, control
		## groups, a selected unit dying mid-fight) without needing a refresh
		## call at each individual mutation site; only rebuilds the panel's
		## buttons/info structure when the selection actually changed since
		## last frame — otherwise just updates the already-built info values
		## (health, etc.) in place.
		_prune_selected_units()
		if selected_units != _last_command_panel_units:
			_refresh_command_panel()
		else:
			_refresh_unit_info_values()
	elif selected_resource != null:
		## A gathered-out resource node frees itself (Gatherable.gather()),
		## so this also has to notice when it's no longer valid.
		if not is_instance_valid(selected_resource):
			_select_resource(null)
		else:
			_refresh_resource_info()
	if placing_type:
		_update_placement_ghost()
	_update_hover_ring()
	_update_path_markers()

func _unhandled_input(event: InputEvent) -> void:
	if game_over:
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE and pause_menu.visible:
		_close_pause_menu()
		get_viewport().set_input_as_handled()
		return
	if pause_menu.visible:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if chat_input.visible and event.keycode == KEY_ESCAPE:
			_close_chat_input()
			get_viewport().set_input_as_handled()
			return
		if not chat_input.visible and event.keycode == KEY_ENTER:
			_open_chat_input()
			get_viewport().set_input_as_handled()
			return
	if chat_input.visible:
		return

	if placing_type:
		_handle_placement_input(event)
		return

	if _showing_build_submenu and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_close_build_submenu()
		get_viewport().set_input_as_handled()
		return

	if pending_order_mode != "":
		_handle_pending_order_input(event)
		return

	## Fallback: nothing above claimed this Escape (not chatting, not
	## placing, no build submenu, no pending order), so it opens the pause
	## menu instead.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_open_pause_menu()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode >= KEY_1 and event.keycode <= KEY_9:
		var group_number: int = event.keycode - KEY_1 + 1
		if event.ctrl_pressed:
			_assign_control_group(group_number)
		else:
			_activate_control_group(group_number)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_BACKSPACE:
		_jump_to_last_attack()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_PERIOD:
		_select_next_idle_villager()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_COMMA:
		_select_all_military()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		if not selected_units.is_empty():
			_center_camera_on(selected_units)
		elif selected_building != null and is_instance_valid(selected_building):
			_center_camera_on([selected_building])
		get_viewport().set_input_as_handled()
		return

	## Gated on nothing being selected (the idle construction menu) or the
	## build submenu being open (a unit's Build button) — the only two times
	## the action panel actually shows these buttons, matching what's on
	## screen instead of secretly still working while it shows something else.
	if event is InputEventKey and event.pressed and not event.echo \
			and ((selected_building == null and selected_units.is_empty()) or _showing_build_submenu):
		var building_index: int = BUILDING_HOTKEYS.find(event.keycode)
		var my_building_types: Array[BuildingType] = _my_faction().building_types
		if building_index != -1 and building_index < my_building_types.size():
			_on_construction_button_pressed(my_building_types[building_index])
			get_viewport().set_input_as_handled()
			return

	if event is InputEventKey and event.pressed and not event.echo and not selected_units.is_empty() \
			and not _showing_build_submenu:
		if event.keycode == UNIT_MOVE_KEY:
			_arm_move_mode()
			get_viewport().set_input_as_handled()
			return
		elif event.keycode == UNIT_STOP_KEY:
			_issue_stop_order()
			get_viewport().set_input_as_handled()
			return
		elif event.keycode == UNIT_ATTACK_KEY:
			_arm_attack_mode()
			get_viewport().set_input_as_handled()
			return
		elif event.keycode == UNIT_PATROL_KEY:
			_arm_patrol_mode()
			get_viewport().set_input_as_handled()
			return
		elif event.keycode == UNIT_BUILD_KEY and _any_selected_can_build():
			_open_build_submenu()
			get_viewport().set_input_as_handled()
			return
		elif selected_units.size() == 1 and selected_units[0].is_monarch:
			var ability_index: int = MONARCH_ABILITY_HOTKEYS.find(event.keycode)
			var unit := selected_units[0]
			if ability_index != -1 and ability_index < unit.monarch_abilities.size() \
					and unit.monarch_abilities[ability_index].kind == Ability.Kind.ACTIVATED_TARGET_POINT:
				_arm_monarch_ability(unit, ability_index)
				get_viewport().set_input_as_handled()
				return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				drag_start = event.position
				dragging = true
				_pending_double_click = event.double_click
			elif dragging:
				dragging = false
				selection_box.visible = false
				_finish_selection(drag_start, event.position, _pending_double_click)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if selected_building != null and selected_building.can_rally:
				_set_rally_point(event.position)
			else:
				_issue_move_order(event.position, event.shift_pressed)
	elif event is InputEventMouseMotion and dragging:
		if drag_start.distance_to(event.position) > CLICK_DRAG_THRESHOLD:
			selection_box.visible = true
			_update_selection_box(event.position)

func _update_selection_box(current_pos: Vector2) -> void:
	var top_left := Vector2(min(drag_start.x, current_pos.x), min(drag_start.y, current_pos.y))
	var size := (current_pos - drag_start).abs()
	selection_box.position = top_left
	selection_box.size = size

## Units can die (and be freed) between selection and the next click/order, so
## any stored reference must be validity-checked before use, not just trusted.
func _prune_selected_units() -> void:
	for i in range(selected_units.size() - 1, -1, -1):
		if not is_instance_valid(selected_units[i]):
			selected_units.remove_at(i)

## --- Control groups ---

func _assign_control_group(number: int) -> void:
	_prune_selected_units()
	var members: Array[Node3D] = []
	for unit in selected_units:
		members.append(unit)
	if selected_building != null and is_instance_valid(selected_building):
		members.append(selected_building)
	control_groups[number] = members
	## Assigning doesn't change what's currently selected, but the group this
	## selection "came from" (if any) is no longer meaningfully this number
	## specifically — next press of it should reselect, not recenter.
	_active_group_number = -1

## One representative sound for the whole selection, not one per unit —
## matches convention (Warcraft 3/AoE) rather than every newly-selected unit
## firing its own voice line simultaneously.
func _play_random_select_sound(units: Array[Unit]) -> void:
	if not units.is_empty():
		units[randi() % units.size()].play_select_sound()

func _activate_control_group(number: int) -> void:
	var members: Array = control_groups.get(number, [])
	for i in range(members.size() - 1, -1, -1):
		if not is_instance_valid(members[i]):
			members.remove_at(i)
	control_groups[number] = members
	if members.is_empty():
		_active_group_number = -1
		return

	if _active_group_number == number:
		_center_camera_on(members)
		return

	for u in selected_units:
		u.selected = false
	selected_units.clear()
	_select_building(null)
	_select_resource(null)

	## A mixed group (units + a building) selects the units, same as
	## drag-select already does — only a building-only group opens its panel.
	var units_in_group: Array[Unit] = []
	var building_in_group: ProductionBuilding = null
	for member in members:
		if member is Unit:
			units_in_group.append(member)
		elif member is ProductionBuilding and building_in_group == null:
			building_in_group = member

	if not units_in_group.is_empty():
		for unit in units_in_group:
			unit.selected = true
			selected_units.append(unit)
		_play_random_select_sound(units_in_group)
	elif building_in_group != null:
		_select_building(building_in_group)
		building_in_group.play_select_sound()

	_active_group_number = number

## Cycles through the local player's own fully-idle gatherers (can_gather,
## not off doing anything else) each press, wrapping around — same
## select-and-recenter pattern as reactivating a control group.
var _idle_villager_cycle_index: int = -1

func _select_next_idle_villager() -> void:
	var idle_villagers: Array[Unit] = []
	for node in get_tree().get_nodes_in_group("units"):
		var unit := node as Unit
		if unit and unit.owner_peer_id == _my_peer_id() and unit.can_gather \
				and unit.status_activity == Unit.Activity.IDLE and unit.status_command == Unit.Command.NONE:
			idle_villagers.append(unit)
	if idle_villagers.is_empty():
		return

	_idle_villager_cycle_index = (_idle_villager_cycle_index + 1) % idle_villagers.size()
	var villager := idle_villagers[_idle_villager_cycle_index]

	for u in selected_units:
		u.selected = false
	selected_units.clear()
	_select_building(null)
	_select_resource(null)
	_active_group_number = -1

	villager.selected = true
	selected_units.append(villager)
	villager.play_select_sound()
	_center_camera_on([villager])

## Double-clicking a unit selects every other owned unit of the same type
## currently visible on screen — same "same type" notion as display_name
## already uses elsewhere (Villager/Soldier/Cavalry/...).
func _select_all_visible_units_of_type(unit_type: String) -> void:
	for u in selected_units:
		u.selected = false
	selected_units.clear()
	var viewport_rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	for child in units_root.get_children():
		if child is Unit and child.owner_peer_id == _my_peer_id() and child.display_name == unit_type \
				and not camera.is_position_behind(child.global_position):
			var screen_pos: Vector2 = camera.unproject_position(child.global_position)
			if viewport_rect.has_point(screen_pos):
				child.selected = true
				selected_units.append(child)
	_play_random_select_sound(selected_units)

## Selects every owned combat unit (can_gather == false) anywhere on the map,
## not just what's on screen — matches the usual RTS "select army" hotkey,
## which is meant to work regardless of where those units currently are.
func _select_all_military() -> void:
	var military: Array[Unit] = []
	for node in get_tree().get_nodes_in_group("units"):
		var unit := node as Unit
		if unit and unit.owner_peer_id == _my_peer_id() and not unit.can_gather:
			military.append(unit)
	if military.is_empty():
		return

	for u in selected_units:
		u.selected = false
	selected_units.clear()
	_select_building(null)
	_select_resource(null)
	_active_group_number = -1

	for unit in military:
		unit.selected = true
		selected_units.append(unit)
	_play_random_select_sound(selected_units)

func _center_camera_on(members: Array) -> void:
	var sum := Vector3.ZERO
	var count := 0
	for member in members:
		if is_instance_valid(member):
			sum += member.global_position
			count += 1
	if count == 0:
		return
	var avg := sum / count
	camera_rig.global_position.x = avg.x
	camera_rig.global_position.z = avg.z

func _finish_selection(start_pos: Vector2, end_pos: Vector2, double_click: bool = false) -> void:
	_prune_selected_units()
	_active_group_number = -1
	var rect := Rect2(
		Vector2(min(start_pos.x, end_pos.x), min(start_pos.y, end_pos.y)),
		(end_pos - start_pos).abs()
	)

	for u in selected_units:
		u.selected = false
	selected_units.clear()

	if start_pos.distance_to(end_pos) <= CLICK_DRAG_THRESHOLD:
		var collider: Object = _raycast(end_pos).get("collider")
		if collider is Unit and collider.owner_peer_id == _my_peer_id():
			_select_building(null)
			_select_resource(null)
			if double_click:
				_select_all_visible_units_of_type(collider.display_name)
			else:
				collider.selected = true
				selected_units.append(collider)
				collider.play_select_sound()
			clicked_ring_target = collider
		elif collider is ProductionBuilding and collider.owner_peer_id == _my_peer_id():
			_select_building(collider)
			collider.play_select_sound()
			_select_resource(null)
			clicked_ring_target = collider
			if double_click:
				_center_camera_on([collider])
		elif collider is Gatherable:
			## Any resource node (own or not — trees/berries/gold deposits have
			## no owner) shows its remaining amount in the info panel; unlike
			## a unit/building this isn't "yours to command", just informational.
			_select_building(null)
			_select_resource(collider)
			collider.play_select_sound()
			clicked_ring_target = collider
		elif collider is Unit or collider is ProductionBuilding:
			## Not "selectable" (enemy unit/building) but still a valid thing
			## to click-highlight.
			_select_building(null)
			_select_resource(null)
			clicked_ring_target = collider
			if double_click and collider is ProductionBuilding:
				_center_camera_on([collider])
		else:
			_select_building(null)
			_select_resource(null)
			clicked_ring_target = null
		return

	_select_building(null)
	_select_resource(null)
	clicked_ring_target = null
	for child in units_root.get_children():
		if child is Unit and child.owner_peer_id == _my_peer_id() and not camera.is_position_behind(child.global_position):
			var screen_pos: Vector2 = camera.unproject_position(child.global_position)
			if rect.has_point(screen_pos):
				child.selected = true
				selected_units.append(child)
	_play_random_select_sound(selected_units)

func _raycast(screen_pos: Vector2) -> Dictionary:
	var space_state := get_world_3d().direct_space_state
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 1000.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	return space_state.intersect_ray(query)

## Gatherable / enemy Unit / enemy-or-under-construction-or-deposit-linked
## ProductionBuilding -> its path, else an empty path meaning "plain ground".
func _resolve_order_target_path(result: Dictionary) -> NodePath:
	if result.collider is Gatherable:
		return result.collider.get_path()
	elif result.collider is Unit and result.collider.owner_peer_id != _my_peer_id():
		return result.collider.get_path()
	## A friendly building under construction is also a valid target (to send
	## builders to it), and so is a friendly building with a linked_deposit
	## (e.g. a Mine — right-clicking the mine itself should still gather from
	## the deposit it sits on), alongside the existing enemy-building-attack case.
	elif result.collider is ProductionBuilding and \
			(result.collider.owner_peer_id != _my_peer_id() or result.collider.is_under_construction \
				or result.collider.linked_deposit != null):
		return result.collider.get_path()
	return NodePath()

## Selection is local, but actually moving/gathering only ever happens on the
## host, so the command is sent there and executed on its authoritative units.
## append: true while Shift is held — the order is queued to run after
## whatever this unit is currently doing (including any earlier shift-queued
## orders) instead of replacing it — see _rpc_issue_command.
func _issue_move_order(screen_pos: Vector2, append: bool = false) -> void:
	_prune_selected_units()
	if selected_units.is_empty():
		return
	var result := _raycast(screen_pos)
	if result.is_empty():
		return

	var unit_paths: Array[NodePath] = []
	for unit in selected_units:
		unit_paths.append(unit.get_path())

	var target_path := _resolve_order_target_path(result)
	_rpc_issue_command.rpc_id(1, unit_paths, target_path, result.position, false, append)
	_play_command_sound()
	_play_command_feedback(result.position, false)
	for unit in selected_units:
		if append:
			_add_path_marker(unit, result.position)
		else:
			_clear_path_markers(unit)

## Same target inference as a plain move order, except empty ground issues an
## attack-move instead of a plain move — see _rpc_issue_command's attack_move_fallback.
func _issue_attack_order(screen_pos: Vector2, append: bool = false) -> void:
	_prune_selected_units()
	if selected_units.is_empty():
		return
	var result := _raycast(screen_pos)
	if result.is_empty():
		return

	var unit_paths: Array[NodePath] = []
	for unit in selected_units:
		unit_paths.append(unit.get_path())

	var target_path := _resolve_order_target_path(result)
	_rpc_issue_command.rpc_id(1, unit_paths, target_path, result.position, true, append)
	_play_command_sound()
	_play_command_feedback(result.position, true)
	for unit in selected_units:
		if append:
			_add_path_marker(unit, result.position)
		else:
			_clear_path_markers(unit)

func _issue_stop_order() -> void:
	_prune_selected_units()
	if selected_units.is_empty():
		return
	var unit_paths: Array[NodePath] = []
	for unit in selected_units:
		unit_paths.append(unit.get_path())
		_clear_path_markers(unit)
	_rpc_issue_stop.rpc_id(1, unit_paths)
	_play_command_sound()

@rpc("any_peer", "call_local", "reliable")
func _rpc_issue_command(unit_paths: Array[NodePath], target_path: NodePath, world_pos: Vector3, attack_move_fallback: bool, append: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = _my_peer_id()

	var target_node: Node = get_node_or_null(target_path) if target_path != NodePath() else null

	var units: Array[Unit] = []
	for path in unit_paths:
		var unit := get_node_or_null(path) as Unit
		if unit != null and unit.owner_peer_id == sender_id:
			units.append(unit)

	var formation_positions := _formation_positions(units, world_pos)
	## Capping the whole group to its slowest member's speed is what actually
	## keeps a mixed-speed selection's formation shape intact throughout the
	## move — the nearest-slot assignment above already gets everyone to the
	## right place, but without this a fast unit reaches its slot early and
	## drifts/jostles around while slower units are still catching up.
	var group_speed := _slowest_move_speed(units)
	for i in units.size():
		var unit := units[i]
		## append only actually queues if the unit is currently mid-order —
		## an idle unit (nothing to finish first) or one that already has a
		## queue going dispatches/appends normally either way, but a unit
		## with nothing in flight has nothing for order_completed to ever
		## fire from, so queuing here would silently strand the order forever.
		var unit_is_busy := unit.status_command != Unit.Command.NONE or not unit.order_queue.is_empty()
		if append and unit_is_busy:
			unit.queue_order(target_path, formation_positions[i], attack_move_fallback, group_speed)
		else:
			unit.clear_order_queue()
			_dispatch_smart_command(unit, target_node, formation_positions[i], attack_move_fallback, group_speed)

const FORMATION_COLUMNS: int = 4
## Wider than it looks like it needs to be on paper: each unit's
## NavigationAgent3D avoidance radius is 0.45 (unit.gd), so at the old 1.2
## spacing adjacent slots left almost no slack for avoidance to negotiate,
## and a group would jostle into whatever gap opened up instead of settling
## into its exact assigned slot — looking like a scrambled cluster instead
## of a grid even though the math was correct.
const FORMATION_SPACING: float = 2.0

## Arranges units into a grid oriented to face the direction of travel —
## front rank arrives exactly at target_pos, further ranks trail behind it —
## instead of the old fixed screen-space block that never rotated with the
## order. Only matters for the plain-move/attack-move fallback in
## _dispatch_smart_command; a gather/attack/build target ignores its
## assigned position entirely and paths to the target node itself.
##
## Returned positions are aligned to `units` by index (result[i] is where
## units[i] should go), but which unit gets which grid slot is decided by
## nearest-available-slot assignment (see _assign_slots_to_units), not by
## raw selection order — assigning slot i to units[i] directly would send
## units to whichever slot their index happened to land on regardless of
## where they actually are, causing them to needlessly cross paths to swap
## places with each other.
func _formation_positions(units: Array[Unit], target_pos: Vector3) -> Array[Vector3]:
	if units.is_empty():
		return []
	if units.size() == 1:
		return [target_pos]

	var centroid := Vector3.ZERO
	for unit in units:
		centroid += unit.global_position
	centroid /= units.size()

	var to_target := target_pos - centroid
	to_target.y = 0.0
	## Degenerate case (target basically on top of the group's own centroid)
	## still needs a facing to build `right` from — arbitrary is fine, it
	## only affects which way a near-zero-distance formation fans out.
	var forward: Vector3 = to_target.normalized() if to_target.length_squared() > 0.0001 else Vector3.FORWARD
	var right := Vector3(forward.z, 0.0, -forward.x)

	var slots: Array[Vector3] = []
	for i in units.size():
		var col: int = i % FORMATION_COLUMNS
		var row: int = i / FORMATION_COLUMNS
		var col_offset: float = (col - (FORMATION_COLUMNS - 1) / 2.0) * FORMATION_SPACING
		var row_offset: float = row * FORMATION_SPACING
		slots.append(target_pos + right * col_offset - forward * row_offset)

	return _assign_slots_to_units(units, slots)

## Greedy nearest-pair assignment: repeatedly claims the closest remaining
## (unit, slot) pair until every unit has one. Not globally optimal (that's
## the Hungarian algorithm), but for RTS-sized selections this is more than
## good enough and avoids the crossing-paths problem a fixed index mapping has.
func _assign_slots_to_units(units: Array[Unit], slots: Array[Vector3]) -> Array[Vector3]:
	var pairs: Array = []
	for ui in units.size():
		for si in slots.size():
			pairs.append([units[ui].global_position.distance_squared_to(slots[si]), ui, si])
	pairs.sort_custom(func(a, b): return a[0] < b[0])

	var result: Array[Vector3] = []
	result.resize(units.size())
	var unit_taken: Array[bool] = []
	unit_taken.resize(units.size())
	var slot_taken: Array[bool] = []
	slot_taken.resize(slots.size())

	var assigned := 0
	for pair in pairs:
		if assigned >= units.size():
			break
		var ui: int = pair[1]
		var si: int = pair[2]
		if unit_taken[ui] or slot_taken[si]:
			continue
		unit_taken[ui] = true
		slot_taken[si] = true
		result[ui] = slots[si]
		assigned += 1
	return result

## -1 (no override) for a single-unit selection — see Unit.formation_speed.
func _slowest_move_speed(units: Array[Unit]) -> float:
	if units.size() <= 1:
		return -1.0
	var slowest: float = units[0].move_speed
	for unit in units:
		slowest = minf(slowest, unit.move_speed)
	return slowest

## Fires whenever a unit's current command runs its own natural course (a
## move arrives, a fight runs out of enemies, a build finishes) — see
## Unit.order_completed. Only ever emitted host-side, so this only ever runs
## on the host too, same as every other order-dispatch path here.
func _on_unit_order_completed(unit: Unit) -> void:
	if unit.order_queue.is_empty():
		return
	var order: Dictionary = unit.order_queue.pop_front()
	var target_node: Node = get_node_or_null(order["target_path"]) if order["target_path"] != NodePath() else null
	_dispatch_smart_command(unit, target_node, order["world_pos"], order["attack_move_fallback"], order["speed_override"])

## Shared by right-click/attack-order dispatch and a rally point resolving
## onto a resource/enemy/under-construction building: gather/attack/build the
## target if it makes sense for one, otherwise fall back to a plain move (or
## attack-move, when armed). world_pos/speed_override are only used by that
## fallback branch — a gather/attack/build target ignores both, same reasoning
## as the formation slot position itself (see _formation_positions).
func _dispatch_smart_command(unit: Unit, target_node: Node, world_pos: Vector3, attack_move_fallback: bool, speed_override: float = -1.0) -> void:
	## Natural resources (owner_peer_id 0) are gatherable by anyone; a
	## player-built Farm is locked to whoever built it. A resource that
	## requires_building_on_top (e.g. a Gold Deposit) also isn't gatherable
	## until that building has actually finished — this is the
	## authoritative check, since the caller only proposes a target and
	## the host decides what actually happens.
	if target_node is Gatherable and target_node.can_be_gathered() \
			and (target_node.owner_peer_id == 0 or target_node.owner_peer_id == unit.owner_peer_id):
		unit.command_gather(target_node, _get_dropoff_for(unit.owner_peer_id))
		_play_unit_order_sound(unit, Unit.OrderSoundKind.GATHER)
	## Right-clicking a finished building built on a deposit (e.g. a Mine)
	## should gather from what it sits on, same as clicking the deposit
	## directly — checked before the attack/build branches since a
	## same-owner building would never match attack anyway, and this only
	## applies once construction is done (still-building falls through to
	## the command_build branch below).
	elif target_node is ProductionBuilding and target_node.linked_deposit != null \
			and not target_node.is_under_construction and target_node.linked_deposit.can_be_gathered():
		unit.command_gather(target_node.linked_deposit, _get_dropoff_for(unit.owner_peer_id))
		_play_unit_order_sound(unit, Unit.OrderSoundKind.GATHER)
	elif (target_node is Unit or target_node is ProductionBuilding) and target_node.owner_peer_id != unit.owner_peer_id:
		unit.command_attack(target_node)
		_play_unit_order_sound(unit, Unit.OrderSoundKind.ATTACK)
	elif target_node is ProductionBuilding and target_node.is_under_construction:
		unit.command_build(target_node)
		_play_unit_order_sound(unit, Unit.OrderSoundKind.BUILD)
	elif attack_move_fallback:
		unit.command_attack_move(world_pos, speed_override)
		_play_unit_order_sound(unit, Unit.OrderSoundKind.ATTACK)
	else:
		unit.command_move(world_pos, speed_override)
		_play_unit_order_sound(unit, Unit.OrderSoundKind.MOVE)

## append: true once the current patrol-targeting session's first click has
## already gone out, so further shift-clicks extend the loop instead of
## restarting it (see _handle_pending_order_input).
@rpc("any_peer", "call_local", "reliable")
func _rpc_issue_patrol(unit_paths: Array[NodePath], world_pos: Vector3, append: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = _my_peer_id()

	for path in unit_paths:
		var unit := get_node_or_null(path) as Unit
		if unit == null or unit.owner_peer_id != sender_id:
			continue
		if append and unit.status_command == Unit.Command.PATROL:
			unit.command_patrol_add_waypoint(world_pos)
		else:
			unit.command_patrol([unit.global_position, world_pos])
		_play_unit_order_sound(unit, Unit.OrderSoundKind.PATROL)

@rpc("any_peer", "call_local", "reliable")
func _rpc_issue_stop(unit_paths: Array[NodePath]) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = _my_peer_id()

	for path in unit_paths:
		var unit := get_node_or_null(path) as Unit
		if unit == null or unit.owner_peer_id != sender_id:
			continue
		unit.clear_order_queue()
		unit.command_stop()
		_play_unit_order_sound(unit, Unit.OrderSoundKind.STOP)

## Mirrors _handle_placement_input's pattern: Escape/right-click cancels,
## left-click dispatches based on which order is currently armed. Move/Attack
## are single-shot; Patrol stays armed while Shift is held so multiple clicks
## chain into one patrol loop.
func _handle_pending_order_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		pending_order_mode = ""
		_armed_monarch_ability = {}
		return
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		pending_order_mode = ""
		_armed_monarch_ability = {}
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	match pending_order_mode:
		"monarch_ability":
			var result := _raycast(event.position)
			pending_order_mode = ""
			if result.is_empty() or _armed_monarch_ability.is_empty():
				_armed_monarch_ability = {}
				return
			var unit: Unit = _armed_monarch_ability["unit"]
			if is_instance_valid(unit):
				_rpc_request_monarch_ability.rpc_id(1, unit.get_path(), _armed_monarch_ability["ability_index"], result.position)
				_play_command_sound()
			_armed_monarch_ability = {}
		"move":
			_issue_move_order(event.position, event.shift_pressed)
			if not event.shift_pressed:
				pending_order_mode = ""
		"attack":
			_issue_attack_order(event.position, event.shift_pressed)
			if not event.shift_pressed:
				pending_order_mode = ""
		"patrol":
			var result := _raycast(event.position)
			if result.is_empty():
				return
			_prune_selected_units()
			if selected_units.is_empty():
				pending_order_mode = ""
				return
			var unit_paths: Array[NodePath] = []
			for unit in selected_units:
				unit_paths.append(unit.get_path())
			_rpc_issue_patrol.rpc_id(1, unit_paths, result.position, _patrol_started_this_session)
			_play_command_sound()
			_patrol_started_this_session = true
			if not event.shift_pressed:
				pending_order_mode = ""

func _on_stockpile_changed(resource_name: String, amount: int) -> void:
	_resource_totals[resource_name] = amount
	_update_resource_label()

func _on_population_changed(used: int, cap: int) -> void:
	_population_used = used
	_population_cap = cap
	_update_resource_label()

func _update_resource_label() -> void:
	var parts: Array[String] = []
	for resource_type in DEBUG_RESOURCE_TYPES:
		var text := "%s: %d" % [resource_type.display_name, _resource_totals.get(resource_type.display_name, 0)]
		if _resource_flash_on and _flashing_resource_names.has(resource_type.display_name):
			text = "[color=#ff4433]%s[/color]" % text
		parts.append(text)
	parts.append("Population: %d/%d" % [_population_used, _population_cap])
	resource_label.text = "   ".join(parts)

## Mirrors ResourceStockpile.can_afford(), but against this client's own
## _resource_totals rather than the singleton directly — ResourceStockpile's
## totals are only meaningful on the host (see resource_stockpile.gd), so a
## non-host client calling can_afford() on it directly would always read 0.
func _can_afford_locally(costs: Array[ResourceCost]) -> bool:
	for cost in costs:
		if _resource_totals.get(cost.resource_type.display_name, 0) < cost.amount:
			return false
	return true

func _missing_resource_names(costs: Array[ResourceCost]) -> Array[String]:
	var missing: Array[String] = []
	for cost in costs:
		if _resource_totals.get(cost.resource_type.display_name, 0) < cost.amount:
			missing.append(cost.resource_type.display_name)
	return missing

## Called wherever a purchase is refused locally for lack of funds (building
## placement, producible items). No-ops (no flash) if the costs are actually
## affordable — callers don't need to check _can_afford_locally themselves first.
func _flash_missing_resources(costs: Array[ResourceCost]) -> void:
	var missing := _missing_resource_names(costs)
	if missing.is_empty():
		return

	for resource_name in missing:
		_flashing_resource_names[resource_name] = true

	if _resource_flash_tween and _resource_flash_tween.is_valid():
		_resource_flash_tween.kill()
	_resource_flash_tween = create_tween()
	for i in RESOURCE_FLASH_CYCLE_COUNT:
		_resource_flash_tween.tween_callback(func():
			_resource_flash_on = not _resource_flash_on
			_update_resource_label()
		).set_delay(RESOURCE_FLASH_INTERVAL)
	_resource_flash_tween.tween_callback(func():
		_flashing_resource_names.clear()
		_resource_flash_on = false
		_update_resource_label()
	)

func _select_building(building: ProductionBuilding) -> void:
	selected_building = building
	_update_rally_marker()
	if building == null:
		_refresh_command_panel()
		return
	selected_resource = null

	info_panel.visible = true
	info_panel_name_label.text = building.building_name
	action_panel_title.text = building.building_name
	for child in action_panel_grid.get_children():
		child.queue_free()
	_build_building_info(building)

	if building.is_under_construction:
		if not building.construction_finished.is_connected(_on_selected_building_constructed):
			building.construction_finished.connect(_on_selected_building_constructed.bind(building), CONNECT_ONE_SHOT)
		_fill_action_panel_grid([])
		return

	## Rebuilds the menu whenever this building's queue changes — mainly so a
	## just-purchased Blacksmith upgrade's button disappears (and the next
	## tier's appears) immediately rather than only on next reselection.
	## Not CONNECT_ONE_SHOT since more items can complete later; guarded so
	## reselecting the same building doesn't stack duplicate connections.
	if not building.item_completed.is_connected(_on_selected_building_item_completed):
		building.item_completed.connect(_on_selected_building_item_completed.bind(building))

	var buttons: Array[Control] = []
	_info_producible_badges.clear()
	for i in building.producibles.size():
		var item: ProducibleItem = building.producibles[i]
		if not _producible_is_visible(building, item):
			continue
		## Hotkeys map to on-screen position, not the item's true index into
		## producibles — otherwise the visible buttons would jump to
		## whatever hotkey their hidden neighbors happened to occupy.
		var slot: int = buttons.size()
		var hotkey: String = OS.get_keycode_string(PRODUCIBLE_HOTKEYS[slot]) if slot < PRODUCIBLE_HOTKEYS.size() else "?"
		var tooltip := "%s (%s)" % [item.item_name, _format_item_costs(item)]
		var button := _make_command_button(hotkey, tooltip, item.icon, _on_producible_button_pressed.bind(building, i))
		_info_producible_badges[item.item_name] = _add_queue_count_badge(button)
		buttons.append(button)
	_fill_action_panel_grid(buttons)

## A trainable UNIT is always offered. An UPGRADE is hidden once already
## purchased, and hidden until its prerequisite tier (if any) is purchased —
## only the next actually-buyable tier in a line should ever show, not the
## whole line at once (ProductionBuilding.enqueue() already refuses both
## cases server-side; this just keeps the menu matching what's legal).
func _producible_is_visible(building: ProductionBuilding, item: ProducibleItem) -> bool:
	if item.kind != ProducibleItem.Kind.UPGRADE:
		return true
	if building._purchased_upgrades.has(item):
		return false
	return item.requires_upgrade == null or building._purchased_upgrades.has(item.requires_upgrade)

## The action panel is always visible; this only rebuilds its grid/title and
## the info panel for the current selection when no building is selected:
## the four unit-command buttons if units are selected, a resource node's
## remaining amount if one is selected, otherwise the construction menu.
## (Building content is built directly in _select_building.)
func _refresh_command_panel() -> void:
	if selected_building != null:
		return
	for child in action_panel_grid.get_children():
		child.queue_free()
	for child in info_panel_content.get_children():
		child.queue_free()
	_info_stats_label = null
	_info_unit_portrait_bars.clear()
	_info_resource_label = null
	_last_command_panel_units = selected_units.duplicate()
	_showing_build_submenu = false

	if not selected_units.is_empty():
		info_panel.visible = true
		_populate_unit_command_buttons()
		_build_unit_info()
		_refresh_unit_info_values()
		return

	action_panel_title.text = "Construct"
	_populate_construction_buttons()

	if selected_resource != null and is_instance_valid(selected_resource):
		info_panel.visible = true
		info_panel_name_label.text = selected_resource.display_name
		_info_resource_label = Label.new()
		info_panel_content.add_child(_info_resource_label)
		_refresh_resource_info()
		return

	info_panel.visible = false

## Left-click select/deselect a resource node (see selected_resource);
## null clears it back to whatever the rest of the selection implies.
func _select_resource(resource: Gatherable) -> void:
	selected_resource = resource
	if resource != null:
		for u in selected_units:
			if is_instance_valid(u):
				u.selected = false
		selected_units.clear()
		selected_building = null
	_refresh_command_panel()

func _refresh_resource_info() -> void:
	if _info_resource_label and is_instance_valid(selected_resource):
		_info_resource_label.text = "%d remaining" % selected_resource.amount_remaining

func _populate_construction_buttons() -> void:
	var my_building_types: Array[BuildingType] = _my_faction().building_types
	var buttons: Array[Control] = []
	for i in my_building_types.size():
		var building_type: BuildingType = my_building_types[i]
		var hotkey: String = OS.get_keycode_string(BUILDING_HOTKEYS[i]) if i < BUILDING_HOTKEYS.size() else "?"
		var tooltip := "%s (%s)" % [building_type.building_name, _format_costs(building_type.get_costs())]
		buttons.append(_make_command_button(hotkey, tooltip, building_type.icon, _on_construction_button_pressed.bind(building_type)))
	_fill_action_panel_grid(buttons)

## The action panel's grid is a fixed-size 4-column layout (see
## ACTION_PANEL_SLOT_COUNT) regardless of how many real buttons a given
## context has, so its on-screen size/shape never changes with selection —
## needed so a frame image can be overlaid on top of it consistently. Unused
## slots are filled with an invisible, non-interactive placeholder of the
## same size instead of just leaving the grid short.
func _fill_action_panel_grid(buttons: Array[Control]) -> void:
	for button in buttons:
		action_panel_grid.add_child(button)
	for i in range(buttons.size(), ACTION_PANEL_SLOT_COUNT):
		action_panel_grid.add_child(_make_empty_action_slot())

func _make_empty_action_slot() -> Control:
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(56, 56)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return slot

## Idle construction menu and a unit's Build submenu both funnel through here:
## while the submenu is open this also captures which selected units (that
## can build) should be sent to build whatever gets placed.
## Holding Shift while picking the NEXT building (even a different type) keeps
## the same builders queued up from a chain already in progress — see
## _confirm_placement, which is what actually starts/continues _build_queue_active.
func _on_construction_button_pressed(building_type: BuildingType) -> void:
	if not (_build_queue_active and Input.is_key_pressed(KEY_SHIFT)):
		_pending_builder_paths.clear()
		_build_queue_active = false
		if _showing_build_submenu:
			for unit in selected_units:
				if is_instance_valid(unit) and unit.can_build:
					_pending_builder_paths.append(unit.get_path())
	_start_placement(building_type)
	_play_command_sound()

func _any_selected_can_build() -> bool:
	for unit in selected_units:
		if is_instance_valid(unit) and unit.can_build:
			return true
	return false

func _open_build_submenu() -> void:
	_showing_build_submenu = true
	action_panel_title.text = "Build"
	for child in action_panel_grid.get_children():
		child.queue_free()
	_populate_construction_buttons()
	_play_command_sound()

func _close_build_submenu() -> void:
	_showing_build_submenu = false
	for child in action_panel_grid.get_children():
		child.queue_free()
	_populate_unit_command_buttons()

## --- Command panel info section ---

func _make_progress_bar_with_overlay() -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 20)
	bar.max_value = 1.0
	bar.show_percentage = false
	var overlay := Label.new()
	overlay.name = "Overlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	overlay.add_theme_font_size_override("font_size", 12)
	bar.add_child(overlay)
	return bar

## Builds the (structural) queue/construction display once per selection
## change; _refresh_building_info() then just updates values every frame.
func _build_building_info(building: ProductionBuilding) -> void:
	for child in info_panel_content.get_children():
		child.queue_free()
	_info_progress_bar = null
	_info_empty_label = null
	_info_slot_row = null
	_info_last_queue_size = -1

	_info_progress_bar = _make_progress_bar_with_overlay()
	info_panel_content.add_child(_info_progress_bar)

	if building.is_under_construction:
		return

	_info_empty_label = Label.new()
	_info_empty_label.text = "Queue: empty"
	info_panel_content.add_child(_info_empty_label)
	_info_slot_row = HBoxContainer.new()
	_info_slot_row.add_theme_constant_override("separation", 6)
	info_panel_content.add_child(_info_slot_row)

func _refresh_building_info() -> void:
	var building := selected_building
	if _info_progress_bar == null:
		_build_building_info(building)

	if building.is_under_construction:
		_info_progress_bar.value = building.construction_progress
		(_info_progress_bar.get_node("Overlay") as Label).text = _format_construction_status(building)
		return

	if building.synced_queue_size <= 0:
		_info_progress_bar.visible = false
		_info_empty_label.visible = true
		_info_slot_row.visible = false
		return

	_info_progress_bar.visible = true
	_info_empty_label.visible = false
	_info_slot_row.visible = true
	_info_progress_bar.value = building.synced_current_item_progress
	(_info_progress_bar.get_node("Overlay") as Label).text = "%s (%.1fs)" % [
		building.synced_current_item_name, building.synced_time_remaining
	]

	## Items queued behind the current one (synced_queue_size includes it),
	## shown as blank slots rather than icons since there's no per-item icon
	## art yet — just enough to see how deep the queue is at a glance.
	var queued_behind: int = building.synced_queue_size - 1
	if queued_behind != _info_last_queue_size:
		_info_last_queue_size = queued_behind
		for child in _info_slot_row.get_children():
			child.queue_free()
		for i in queued_behind:
			var slot := ColorRect.new()
			slot.custom_minimum_size = Vector2(20, 20)
			slot.color = Color(1, 1, 1, 0.2)
			_info_slot_row.add_child(slot)

	_refresh_producible_badges(building)

func _refresh_producible_badges(building: ProductionBuilding) -> void:
	for item_name in _info_producible_badges:
		var badge: Label = _info_producible_badges[item_name]
		var count: int = building.synced_queue_counts.get(item_name, 0)
		badge.visible = count > 0
		if count > 0:
			badge.text = str(count)

## Builds either a single unit's stat readout or a grid of portrait+health
## widgets for a multi-unit selection — structural, called once per selection
## change; _refresh_unit_info_values() updates values every frame after.
func _build_unit_info() -> void:
	if selected_units.size() == 1:
		var unit := selected_units[0]
		info_panel_name_label.text = unit.display_name
		_info_stats_label = Label.new()
		_info_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		info_panel_content.add_child(_info_stats_label)
		return

	info_panel_name_label.text = "%d units selected" % selected_units.size()
	var portrait_grid := GridContainer.new()
	portrait_grid.columns = 4
	portrait_grid.add_theme_constant_override("h_separation", 6)
	portrait_grid.add_theme_constant_override("v_separation", 6)
	for unit in selected_units:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 3)
		var portrait := ColorRect.new()
		portrait.custom_minimum_size = Vector2(36, 36)
		portrait.color = unit.team_tint
		cell.add_child(portrait)
		var health_bar := ProgressBar.new()
		health_bar.custom_minimum_size = Vector2(36, 6)
		health_bar.max_value = 1.0
		health_bar.show_percentage = false
		cell.add_child(health_bar)
		portrait_grid.add_child(cell)
		_info_unit_portrait_bars.append(health_bar)
	info_panel_content.add_child(portrait_grid)

func _refresh_unit_info_values() -> void:
	if selected_units.size() == 1:
		if _info_stats_label:
			_info_stats_label.text = _format_unit_stats(selected_units[0])
		return
	for i in _info_unit_portrait_bars.size():
		if i < selected_units.size() and is_instance_valid(selected_units[i]):
			var unit := selected_units[i]
			_info_unit_portrait_bars[i].value = float(unit.status_current_health) / float(maxi(unit.max_health, 1))

func _format_unit_stats(unit: Unit) -> String:
	var lines: Array[String] = ["HP: %d / %d" % [unit.status_current_health, unit.max_health]]
	if unit.can_fight:
		lines.append("Attack: %d dmg every %.1fs (range %.1f)" % [unit.attack_damage, unit.attack_cooldown, unit.attack_range])
	if unit.can_gather:
		lines.append("Gather level %d (carries %d)" % [unit.gather_level, unit.carry_capacity])
	lines.append("Move speed: %.1f" % unit.move_speed)
	return "\n".join(lines)

func _populate_unit_command_buttons() -> void:
	action_panel_title.text = "Commands"
	var buttons: Array[Control] = [
		_make_command_button(OS.get_keycode_string(UNIT_MOVE_KEY), "Move", null, _arm_move_mode),
		_make_command_button(OS.get_keycode_string(UNIT_STOP_KEY), "Stop", null, _issue_stop_order),
		_make_command_button(OS.get_keycode_string(UNIT_ATTACK_KEY), "Attack", null, _arm_attack_mode),
		_make_command_button(OS.get_keycode_string(UNIT_PATROL_KEY), "Patrol", null, _arm_patrol_mode),
	]
	if _any_selected_can_build():
		buttons.append(_make_command_button(OS.get_keycode_string(UNIT_BUILD_KEY), "Build", null, _open_build_submenu))

	## Promotion and Monarch abilities only make sense for a single selected
	## unit — a group promote/activate has no sensible target.
	if selected_units.size() == 1:
		var unit := selected_units[0]
		if unit.is_monarch:
			for i in unit.monarch_abilities.size():
				var ability: Ability = unit.monarch_abilities[i]
				var hotkey_label: String = OS.get_keycode_string(MONARCH_ABILITY_HOTKEYS[i]) if i < MONARCH_ABILITY_HOTKEYS.size() else "?"
				var tooltip: String = "%s\n%s" % [ability.ability_name, ability.description] if ability.description != "" else ability.ability_name
				if ability.kind == Ability.Kind.PASSIVE_AURA:
					## Shown for visibility (so a player can see what their
					## Monarch grants) but never actionable — it just works
					## continuously, there's nothing to click.
					var button := _make_command_button(hotkey_label, tooltip, ability.icon, func(): pass)
					button.disabled = true
					buttons.append(button)
				else:
					buttons.append(_make_command_button(hotkey_label, tooltip, ability.icon, _arm_monarch_ability.bind(unit, i)))
		elif unit.can_fight and not unit.monarch_abilities.is_empty() and _player_has_monarch_unlocked(unit.owner_peer_id):
			buttons.append(_make_command_button("Promote", "Promote to Monarch", null, _issue_promote_order.bind(unit)))
	_fill_action_panel_grid(buttons)

func _arm_move_mode() -> void:
	pending_order_mode = "move"
	_play_command_sound()

func _arm_attack_mode() -> void:
	pending_order_mode = "attack"
	_play_command_sound()

func _arm_patrol_mode() -> void:
	pending_order_mode = "patrol"
	_patrol_started_this_session = false
	_play_command_sound()

func _player_has_monarch_unlocked(peer_id: int) -> bool:
	for node in get_tree().get_nodes_in_group("buildings"):
		if node is ProductionBuilding and node.owner_peer_id == peer_id and node.can_promote_monarch:
			return true
	return false

func _issue_promote_order(unit: Unit) -> void:
	_rpc_request_promote_monarch.rpc_id(1, unit.get_path())
	_play_command_sound()

func _arm_monarch_ability(unit: Unit, ability_index: int) -> void:
	_armed_monarch_ability = {"unit": unit, "ability_index": ability_index}
	pending_order_mode = "monarch_ability"
	_play_command_sound()

func _on_selected_building_constructed(building: ProductionBuilding) -> void:
	if selected_building == building:
		_select_building(building)

func _on_selected_building_item_completed(_item: ProducibleItem, building: ProductionBuilding) -> void:
	if selected_building == building:
		_select_building(building)

func _on_producible_button_pressed(building: ProductionBuilding, item_index: int) -> void:
	var item := building.producibles[item_index]
	if not _can_afford_locally(item.get_costs()):
		_flash_missing_resources(item.get_costs())
		return
	_rpc_enqueue.rpc_id(1, building.get_path(), item_index)
	_play_command_sound()

@rpc("any_peer", "call_local", "reliable")
func _rpc_enqueue(building_path: NodePath, item_index: int) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = _my_peer_id()

	var building := get_node_or_null(building_path) as ProductionBuilding
	if building == null or building.owner_peer_id != sender_id:
		return
	if item_index < 0 or item_index >= building.producibles.size():
		return
	building.enqueue(building.producibles[item_index])

## --- Monarch promotion / abilities ---

@rpc("any_peer", "call_local", "reliable")
func _rpc_request_promote_monarch(unit_path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = _my_peer_id()

	var unit := get_node_or_null(unit_path) as Unit
	if unit == null or unit.owner_peer_id != sender_id:
		return
	if not unit.can_fight or unit.is_monarch or unit.monarch_abilities.is_empty():
		return
	if not _player_has_monarch_unlocked(sender_id):
		return
	if not ResourceStockpile.can_afford(sender_id, unit.monarch_promotion_costs):
		return
	ResourceStockpile.spend(sender_id, unit.monarch_promotion_costs)
	unit.promote_to_monarch()

@rpc("any_peer", "call_local", "reliable")
func _rpc_request_monarch_ability(unit_path: NodePath, ability_index: int, target_pos: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = _my_peer_id()

	var unit := get_node_or_null(unit_path) as Unit
	if unit == null or unit.owner_peer_id != sender_id or not unit.is_monarch:
		return
	if ability_index < 0 or ability_index >= unit.monarch_abilities.size():
		return
	var ability: Ability = unit.monarch_abilities[ability_index]
	if ability.kind != Ability.Kind.ACTIVATED_TARGET_POINT:
		return
	var ready_at: int = unit._ability_ready_at_ms.get(ability_index, 0)
	if Time.get_ticks_msec() < ready_at:
		return
	if unit.global_position.distance_to(target_pos) > ability.activation_range:
		return
	if not ResourceStockpile.can_afford(sender_id, ability.costs):
		return
	ResourceStockpile.spend(sender_id, ability.costs)
	unit._ability_ready_at_ms[ability_index] = Time.get_ticks_msec() + int(ability.cooldown * 1000.0)
	unit.execute_teleport_ability(ability, target_pos)

## --- Rally points ---

## Applied to our own local copy immediately (for instant marker feedback and,
## if we're the host, because that copy IS the authoritative one), and also
## sent to the host so a non-host owner's rally point actually affects spawning.
func _set_rally_point(screen_pos: Vector2) -> void:
	var result := _raycast(screen_pos)
	if result.is_empty():
		return
	var target_path := _resolve_order_target_path(result)
	selected_building.rally_point = result.position
	selected_building.rally_target_path = target_path
	selected_building.has_rally_point = true
	_update_rally_marker()
	_rpc_set_rally_point.rpc_id(1, selected_building.get_path(), result.position, target_path)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_rally_point(building_path: NodePath, world_pos: Vector3, target_path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = _my_peer_id()

	var building := get_node_or_null(building_path) as ProductionBuilding
	if building == null or building.owner_peer_id != sender_id or not building.can_rally:
		return
	building.rally_point = world_pos
	building.rally_target_path = target_path
	building.has_rally_point = true

func _update_rally_marker() -> void:
	if selected_building != null and selected_building.can_rally and selected_building.has_rally_point:
		_ensure_rally_marker()
		rally_marker.visible = true
		rally_marker.global_position = selected_building.rally_point
	elif rally_marker:
		rally_marker.visible = false

func _ensure_rally_marker() -> void:
	if rally_marker:
		return
	rally_marker = Node3D.new()
	add_child(rally_marker)

	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.05
	pole_mesh.bottom_radius = 0.05
	pole_mesh.height = 1.4
	pole.mesh = pole_mesh
	pole.position = Vector3(0, 0.7, 0)
	var pole_mat := StandardMaterial3D.new()
	pole_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pole_mat.albedo_color = Color(0.9, 0.9, 0.9)
	pole.set_surface_override_material(0, pole_mat)
	rally_marker.add_child(pole)

	var flag := MeshInstance3D.new()
	var flag_mesh := BoxMesh.new()
	flag_mesh.size = Vector3(0.5, 0.3, 0.02)
	flag.mesh = flag_mesh
	flag.position = Vector3(0.27, 1.15, 0)
	var flag_mat := StandardMaterial3D.new()
	flag_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flag_mat.albedo_color = Color(1.0, 0.85, 0.2)
	flag.set_surface_override_material(0, flag_mat)
	rally_marker.add_child(flag)

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
func _update_hover_ring() -> void:
	if placing_type or dragging or chat_input.visible or game_over:
		if hover_ring:
			hover_ring.visible = false
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		return

	var collider: Object = _raycast(get_viewport().get_mouse_position()).get("collider")
	_update_hover_cursor(collider)
	var hovered: Node3D = collider if (collider != null and _is_ring_target(collider) and collider.visible) else null
	var target: Node3D = hovered if hovered else (clicked_ring_target if is_instance_valid(clicked_ring_target) else null)

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
	if selected_units.is_empty():
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		return
	if (collider is Unit and collider.owner_peer_id != _my_peer_id()) \
			or (collider is ProductionBuilding and collider.owner_peer_id != _my_peer_id()):
		Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	elif collider is Gatherable:
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
	else:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)

func _hover_ring_radius(node: Node) -> float:
	if node is Unit:
		return HOVER_RING_UNIT_RADIUS
	var obstacle: NavigationObstacle3D = node.get_node_or_null("NavigationObstacle3D")
	return obstacle.radius + 0.2 if obstacle else 1.0

func _format_construction_status(building: ProductionBuilding) -> String:
	var percent := int(building.construction_progress * 100)
	if building.synced_builder_count <= 0:
		return "Constructing... %d%% (needs a builder)" % percent
	return "Constructing... %d%% (%d building)" % [percent, building.synced_builder_count]

## Shared by the construction menu, a building's production menu, and the new
## unit-command panel: a square button showing only its hotkey letter (icon
## stays null everywhere today — no icon art exists yet, but the field is
## wired so real art can be dropped in later without touching this code).
func _make_command_button(hotkey_label: String, tooltip: String, icon: Texture2D, callback: Callable) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(56, 56)
	button.text = hotkey_label
	button.tooltip_text = tooltip
	button.icon = icon
	button.pressed.connect(callback)
	return button

## Small bottom-right count badge for a producible button, showing how many
## of that item are currently queued (including the one in progress). Hidden
## (count 0) rather than removed, so _refresh_building_info() can just flip
## visibility every frame instead of adding/removing nodes.
func _add_queue_count_badge(button: Button) -> Label:
	var badge := Label.new()
	badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	## Anchored corner is the growth pivot too, so a wider (multi-digit) label
	## expands up-and-left back into the button instead of out past its edge.
	badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	badge.grow_vertical = Control.GROW_DIRECTION_BEGIN
	badge.offset_right = -3
	badge.offset_bottom = -1
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge.add_theme_font_size_override("font_size", 20)
	badge.add_theme_color_override("font_shadow_color", Color.BLACK)
	badge.add_theme_constant_override("shadow_offset_x", 1)
	badge.add_theme_constant_override("shadow_offset_y", 1)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.visible = false
	button.add_child(badge)
	return badge

func _format_costs(costs: Array[ResourceCost]) -> String:
	var parts: Array[String] = []
	for cost in costs:
		parts.append("%d %s" % [cost.amount, cost.resource_type.display_name])
	return ", ".join(parts)

func _format_item_costs(item: ProducibleItem) -> String:
	var text := _format_costs(item.get_costs())
	if item.kind == ProducibleItem.Kind.UNIT:
		text += ", %d Pop" % item.get_population_cost()
	return text

## --- Building placement ---

func _start_placement(building_type: BuildingType) -> void:
	_cancel_placement()
	placing_type = building_type
	## Only needed to close an open building panel — skipped when a unit's
	## Build submenu started this placement, since _select_building(null)
	## would otherwise refresh the action panel back out of that submenu
	## (via _refresh_command_panel()) while the ghost is still following the mouse.
	if selected_building != null:
		_select_building(null)
	placement_ghost = _build_ghost(building_type.scene)
	add_child(placement_ghost)

## Builds a translucent, script-less, collision-less copy of a building's
## real scene for the placement preview — so the ghost always looks exactly
## like what will actually be built, not a generic stand-in shape.
func _build_ghost(scene: PackedScene) -> Node3D:
	var ghost: Node3D = scene.instantiate()
	ghost.set_script(null)
	_strip_ghost_children(ghost)
	_ghost_surfaces.clear()
	_collect_ghost_surfaces(ghost)
	return ghost

## Removes anything that would make the preview behave like a real building
## (collide, block pathing, replicate) — it's purely a harmless visual.
func _strip_ghost_children(node: Node) -> void:
	for child in node.get_children():
		var should_strip := child.name == "HealthBar" \
			or child is CollisionShape3D \
			or child is NavigationObstacle3D \
			or child is MultiplayerSynchronizer
		if should_strip:
			child.free()
		else:
			_strip_ghost_children(child)

## Applies a translucent material to every mesh surface and remembers each
## one's original color, so _set_ghost_valid() can re-tint them green/red
## every frame without re-walking the tree or losing each part's own color.
func _collect_ghost_surfaces(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance: MeshInstance3D = node
		var surface_count: int = mesh_instance.mesh.get_surface_count() if mesh_instance.mesh else 0
		for i in surface_count:
			var base: Material = mesh_instance.get_active_material(i)
			var base_color: Color = base.albedo_color if base is StandardMaterial3D else Color.WHITE
			var ghost_material := StandardMaterial3D.new()
			ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mesh_instance.set_surface_override_material(i, ghost_material)
			_ghost_surfaces.append({"material": ghost_material, "base_color": base_color})
	for child in node.get_children():
		_collect_ghost_surfaces(child)

func _set_ghost_valid(valid: bool) -> void:
	var tint: Color = VALID_GHOST_COLOR if valid else INVALID_GHOST_COLOR
	for entry in _ghost_surfaces:
		var material: StandardMaterial3D = entry["material"]
		var base_color: Color = entry["base_color"]
		material.albedo_color = Color(base_color.r * tint.r, base_color.g * tint.g, base_color.b * tint.b, tint.a)

func _update_placement_ghost() -> void:
	if placing_type.requires_deposit:
		_update_deposit_snap_ghost()
		return

	var mouse_pos := get_viewport().get_mouse_position()
	var result := _raycast(mouse_pos)
	if result.is_empty():
		placement_ghost.visible = false
		return
	placement_ghost.visible = true
	placement_ghost.global_position = result.position

	## _is_placement_valid's overlap check alone only ever compared against
	## other buildings/resources, never terrain, so a ghost could sit embedded
	## in a slope/cliff (e.g. TileMapLayer3D terrain) and still read as valid.
	var on_flat_ground: bool = _footprint_is_flat(result.position, placing_type.footprint_radius)
	placement_valid = on_flat_ground and _is_placement_valid(result.position, placing_type.footprint_radius)
	_set_ghost_valid(placement_valid)

## Samples the footprint's center plus FOOTPRINT_SAMPLE_COUNT points around
## its edge (straight-down raycasts, not just the single cursor ray) so a
## building can't have a flat center while an edge overhangs a nearby
## slope/cliff or straddles a level change undetected.
func _footprint_is_flat(center: Vector3, radius: float) -> bool:
	var space_state := get_world_3d().direct_space_state
	for i in FOOTPRINT_SAMPLE_COUNT + 1:
		var offset := Vector3.ZERO
		if i > 0:
			var angle := TAU * (i - 1) / float(FOOTPRINT_SAMPLE_COUNT)
			offset = Vector3(cos(angle), 0.0, sin(angle)) * radius
		var sample_xz := center + offset
		var query := PhysicsRayQueryParameters3D.create(
			sample_xz + Vector3(0.0, 5.0, 0.0), sample_xz - Vector3(0.0, 5.0, 0.0)
		)
		var result := space_state.intersect_ray(query)
		if result.is_empty():
			return false
		if result.normal.y < MAX_BUILD_SLOPE_NORMAL_Y:
			return false
		if absf(result.position.y - center.y) > MAX_FOOTPRINT_HEIGHT_VARIANCE:
			return false
	return true

## Snap-to-target variant: the ghost only ever shows at an existing,
## unclaimed instance of placing_type.deposit_scene under the mouse, never
## following the mouse freely.
func _update_deposit_snap_ghost() -> void:
	var mouse_pos := get_viewport().get_mouse_position()
	var result := _raycast(mouse_pos)
	_placement_target = _find_valid_deposit(result.get("collider"))

	if _placement_target == null:
		placement_ghost.visible = false
		placement_valid = false
		return

	placement_ghost.visible = true
	placement_ghost.global_position = _placement_target.global_position
	placement_valid = true
	_set_ghost_valid(true)

func _find_valid_deposit(collider: Object) -> Gatherable:
	if collider == null or not (collider is Gatherable):
		return null
	var deposit: Gatherable = collider
	if deposit.is_claimed or not _matches_scene(deposit, placing_type.deposit_scene):
		return null
	return deposit

func _matches_scene(node: Node, scene: PackedScene) -> bool:
	return scene != null and node.scene_file_path == scene.resource_path

func _is_placement_valid(pos: Vector3, radius: float) -> bool:
	var space_state := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), pos)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	for result in space_state.intersect_shape(query, 8):
		if result.collider is ProductionBuilding or result.collider is Gatherable:
			return false
	return true

func _handle_placement_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_confirm_placement()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_placement()
			_pending_builder_paths.clear()
			_build_queue_active = false
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_cancel_placement()
		_pending_builder_paths.clear()
		_build_queue_active = false

func _confirm_placement() -> void:
	if not placement_valid:
		_cancel_placement()
		return
	## Checked here (rather than only relying on the host's own can_afford
	## guard in _rpc_request_build) so an unaffordable click gets immediate
	## feedback instead of just silently doing nothing once the RPC reaches
	## the host and gets refused there. Placement mode is left running so the
	## player can keep waiting for resources and try the same spot again.
	if not _can_afford_locally(placing_type.get_costs()):
		_flash_missing_resources(placing_type.get_costs())
		return
	var my_building_types: Array[BuildingType] = _my_faction().building_types
	var type_index: int = my_building_types.find(placing_type)
	var target_path := _placement_target.get_path() if _placement_target else NodePath()
	var placed_type := placing_type
	var shift_held := Input.is_key_pressed(KEY_SHIFT)
	_rpc_request_build.rpc_id(1, type_index, placement_ghost.global_position, target_path, _pending_builder_paths, shift_held)
	_play_command_sound()

	## Holding Shift keeps the same builders and stays in placement mode
	## (re-arming the same building type) so the next click queues another
	## one instead of ending the session — see _on_unit_order_completed on
	## the host side for how builders actually work through the chain.
	if shift_held:
		_build_queue_active = true
		for path in _pending_builder_paths:
			var builder := get_node_or_null(path) as Unit
			if builder:
				_add_path_marker(builder, placement_ghost.global_position)
		_start_placement(placed_type)
		return

	for path in _pending_builder_paths:
		var builder := get_node_or_null(path) as Unit
		if builder:
			_clear_path_markers(builder)
	_cancel_placement()
	_pending_builder_paths.clear()
	_build_queue_active = false
	if _showing_build_submenu:
		_close_build_submenu()

@rpc("any_peer", "call_local", "reliable")
func _rpc_request_build(type_index: int, world_pos: Vector3, target_path: NodePath, builder_paths: Array[NodePath], append: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = _my_peer_id()

	## Resolved against the SENDER's own faction, never a shared/global list —
	## the same type_index means a different building depending on faction,
	## so trusting anything else here would let a client reference another
	## faction's roster.
	if not faction_by_peer.has(sender_id):
		return
	var sender_building_types: Array[BuildingType] = faction_by_peer[sender_id].building_types
	if type_index < 0 or type_index >= sender_building_types.size():
		return
	var building_type: BuildingType = sender_building_types[type_index]
	var costs := building_type.get_costs()
	if not ResourceStockpile.can_afford(sender_id, costs):
		return

	## Deposit-snapped buildings ignore the client's proposed position — the
	## host looks the target up itself and uses its real position, so a
	## tampered/stale client position can't matter.
	var build_pos := world_pos
	var deposit: Gatherable = null
	if building_type.requires_deposit:
		deposit = get_node_or_null(target_path) as Gatherable
		if deposit == null or deposit.is_claimed or not _matches_scene(deposit, building_type.deposit_scene):
			return
		build_pos = deposit.global_position
	elif not _footprint_is_flat(world_pos, building_type.footprint_radius) \
			or not _is_placement_valid(world_pos, building_type.footprint_radius):
		return

	ResourceStockpile.spend(sender_id, costs)
	if deposit:
		deposit.is_claimed = true

	var team_index: int = team_index_by_peer.get(sender_id, 0)
	var spawn_data: Dictionary = {
		"scene_path": building_type.scene.resource_path,
		"peer_id": sender_id,
		"position": build_pos,
		"tint": TEAM_COLORS[team_index % TEAM_COLORS.size()],
	}
	if deposit:
		spawn_data["deposit_path"] = deposit.get_path()
	var spawned: Node = building_spawner.spawn(spawn_data)
	## Farm (a buildable Gatherable, not a ProductionBuilding) has no
	## construction phase — it just appears complete.
	if spawned is ProductionBuilding:
		var building: ProductionBuilding = spawned
		building.begin_construction(building_type.construction_time)
		if building.population_capacity > 0:
			building.construction_finished.connect(func():
				Population.add_cap(sender_id, building.population_capacity)
				building.destroyed.connect(
					func(): Population.add_cap(sender_id, -building.population_capacity), CONNECT_ONE_SHOT
				)
			, CONNECT_ONE_SHOT)
		if deposit:
			building.construction_finished.connect(func():
				deposit.has_required_building = true
			, CONNECT_ONE_SHOT)
			building.destroyed.connect(func():
				deposit.has_required_building = false
				deposit.is_claimed = false
			, CONNECT_ONE_SHOT)

		## Sends whichever villager(s) opened the build menu to go build what
		## they just placed, instead of leaving them standing idle next to it.
		## Shift-chained placements queue this after the builder's current
		## order instead — see _confirm_placement/_on_unit_order_completed.
		## Same "only actually queue if there's something to finish first" logic
		## as _rpc_issue_command — an idle builder with nothing in flight would
		## never have anything trigger order_completed to dispatch a queued order.
		for path in builder_paths:
			var builder := get_node_or_null(path) as Unit
			if builder == null or builder.owner_peer_id != sender_id:
				continue
			var builder_is_busy := builder.status_command != Unit.Command.NONE or not builder.order_queue.is_empty()
			if append and builder_is_busy:
				builder.queue_order(building.get_path(), building.global_position, false)
			else:
				builder.clear_order_queue()
				builder.command_build(building)

func _cancel_placement() -> void:
	if placement_ghost:
		placement_ghost.queue_free()
		placement_ghost = null
	_ghost_surfaces.clear()
	placing_type = null
	_placement_target = null

## --- Chat / debug console ---
## Type a normal message to broadcast it to everyone, or "cmd ..." for a
## debug command (currently: "cmd add <resource> <amount>" grants yourself
## that resource without playing, e.g. "cmd add wood 10").

func _open_chat_input() -> void:
	chat_input.visible = true
	chat_input.text = ""
	chat_input.grab_focus()

func _close_chat_input() -> void:
	chat_input.visible = false
	chat_input.text = ""
	chat_input.release_focus()

func _on_chat_submitted(text: String) -> void:
	_close_chat_input()
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return
	_rpc_submit_chat.rpc_id(1, trimmed)

@rpc("any_peer", "call_local", "reliable")
func _rpc_submit_chat(text: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = _my_peer_id()

	if text.begins_with("cmd "):
		_execute_debug_command(sender_id, text.substr(4))
	else:
		_rpc_display_chat.rpc("Player %d: %s" % [sender_id, text])

func _execute_debug_command(sender_id: int, args_string: String) -> void:
	var parts: PackedStringArray = args_string.strip_edges().split(" ", false)
	if parts.is_empty():
		return

	match parts[0].to_lower():
		"add":
			if parts.size() < 3:
				_rpc_display_chat.rpc_id(sender_id, "[debug] usage: cmd add <resource> <amount>")
				return
			var resource_type: ResourceType = _find_resource_type_by_name(parts[1])
			if resource_type == null:
				_rpc_display_chat.rpc_id(sender_id, "[debug] unknown resource '%s'" % parts[1])
				return
			var amount: int = int(parts[2])
			ResourceStockpile.add(sender_id, resource_type, amount)
			_rpc_display_chat.rpc_id(sender_id, "[debug] +%d %s" % [amount, resource_type.display_name])
		"help":
			_rpc_display_chat.rpc_id(sender_id, "[debug] commands: cmd add <resource> <amount>")
		_:
			_rpc_display_chat.rpc_id(sender_id, "[debug] unknown command '%s'" % parts[0])

func _find_resource_type_by_name(resource_name: String) -> ResourceType:
	for resource_type in DEBUG_RESOURCE_TYPES:
		if resource_type.display_name.to_lower() == resource_name.to_lower():
			return resource_type
	return null

@rpc("authority", "call_local", "reliable")
func _rpc_display_chat(line: String) -> void:
	chat_lines.append(line)
	if chat_lines.size() > MAX_CHAT_LINES:
		chat_lines.pop_front()
	chat_log.text = "\n".join(chat_lines)

## Right-click on the minimap; relayed through the host (same call-to-1-then-
## broadcast shape as chat) so every player sees the same ping at once,
## including the one who placed it.
func _on_minimap_ping_requested(world_pos: Vector3) -> void:
	_rpc_request_ping.rpc_id(1, world_pos)

@rpc("any_peer", "call_local", "reliable")
func _rpc_request_ping(world_pos: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = _my_peer_id()
	_rpc_show_ping.rpc(world_pos, sender_id)

@rpc("authority", "call_local", "reliable")
func _rpc_show_ping(world_pos: Vector3, sender_id: int) -> void:
	minimap.show_ping(world_pos)
	_play_ping_effect(world_pos)
	chat_lines.append("Player %d pinged the map" % sender_id)
	if chat_lines.size() > MAX_CHAT_LINES:
		chat_lines.pop_front()
	chat_log.text = "\n".join(chat_lines)

## Bigger and longer-lived than _play_command_feedback's move/attack rings —
## a ping needs to catch the eye of someone who isn't even looking at this
## part of the map yet, not just confirm a click that was just made.
func _play_ping_effect(world_pos: Vector3) -> void:
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
