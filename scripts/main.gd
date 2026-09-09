extends Node3D

## The team color palette lives on Network (Network.TEAM_COLORS) rather than
## here, so the lobby offers exactly the choices this scene spawns players
## with. get_team_tint() below resolves a peer's actual color.

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
## Formation-shape hotkeys — cycles the active selection's move-order shape
## (see Formation.Type / current_formation_type / _set_formation_type). F1-F3
## are unused elsewhere (camera only reads W/A/S/D/Q/E, see above), matching
## the AoE-style formation hotkey convention.
const FORMATION_BOX_KEY: Key = KEY_F1
const FORMATION_LINE_KEY: Key = KEY_F2
const FORMATION_STAGGERED_KEY: Key = KEY_F3
## Re-form: re-solves the current selection's formation shape around where the
## group is standing right now and walks them into it — the on-demand half of
## reformation (the other half, closing ranks when a member dies mid-move, is
## automatic; see _update_reformation). F4 continues the F1-F3 shape row.
const FORMATION_REFORM_KEY: Key = KEY_F4
## Assigned by position in a Monarch's monarch_abilities, same convention as
## PRODUCIBLE_HOTKEYS/BUILDING_HOTKEYS below — a passive ability still claims
## a slot (shown disabled) so hotkeys stay stable regardless of ability order.
const MONARCH_ABILITY_HOTKEYS: Array[Key] = [KEY_R, KEY_T, KEY_Y, KEY_U]
const PRODUCIBLE_HOTKEYS: Array[Key] = [KEY_I, KEY_J, KEY_K, KEY_L]
const BUILDING_HOTKEYS: Array[Key] = [KEY_Z, KEY_X, KEY_C, KEY_V, KEY_B, KEY_N, KEY_G, KEY_O]
## The action panel's grid always has exactly this many slots (4 columns x 3
## rows), padded with blank placeholders, so its size never changes with context.
const ACTION_PANEL_SLOT_COUNT: int = 12
const QUEUE_SLOT_TEXTURE: Texture2D = preload("res://assets/ui/HUD/elements/square_frame_dark.png")
const RALLY_BANNER_SCENE: PackedScene = preload("res://assets/art/Models/Banner/banner.glb")
const RALLY_DUST_HEIGHT: float = 0.35
const SELECTION_PORTRAIT_COLUMNS: int = 6
const SELECTION_PORTRAIT_LIMIT: int = 12
const RESOURCE_TICK_RATE: float = 6.0
const RESOURCE_TICK_MIN_SPEED: float = 12.0
const BAR_FRAME_TEXTURE: Texture2D = preload("res://assets/ui/HUD/scaled/bar_frame.png")
const BAR_FILL_TEXTURE: Texture2D = preload("res://assets/ui/HUD/scaled/bar_fill_green.png")
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

## Same list (and order) as lobby.tscn's Lobby.available_factions — that
## shared order is what a "faction_index" in Network.players refers to.
@export var available_factions: Array[Faction] = []

@onready var camera: Camera3D = $CameraRig/Yaw/Pitch/Camera3D
@onready var camera_rig: Node3D = $CameraRig
@onready var selection_box: ColorRect = $UI/SelectionBox
@onready var resource_label: RichTextLabel = $UI/ResourceLabel
## Shows the current selection's move-order formation shape — see
## current_formation_type/_set_formation_type. Purely a display; the actual
## shape logic lives host-side in Formation/_formation_positions.
@onready var formation_label: Label = $UI/FormationLabel
@onready var fog_of_war: FogOfWar = $FogOfWar
@onready var units_root: Node3D = $Units
@onready var unit_spawner: MultiplayerSpawner = $UnitSpawner
@onready var buildings_root: Node3D = $Buildings
@onready var building_spawner: MultiplayerSpawner = $BuildingSpawner
@onready var player_spawn_points: Node3D = $PlayerSpawnPoints

@onready var info_panel_divider: TextureRect = $UI/BottomBar/InfoPanel/Margin/VBox/TitleDivider
@onready var info_panel_name_label: Label = $UI/BottomBar/InfoPanel/Margin/VBox/BuildingNameLabel
@onready var info_panel_content: VBoxContainer = $UI/BottomBar/InfoPanel/Margin/VBox/InfoContainer
@onready var portrait_frame: TextureRect = $UI/BottomBar/InfoPanel/PortraitFrame
@onready var portrait_rect: ColorRect = $UI/BottomBar/InfoPanel/PortraitFrame/Portrait
@onready var portrait_health_label: Label = $UI/BottomBar/InfoPanel/PortraitHealthLabel

## Single contextual action panel — always visible, its grid's contents and
## title change with the selection: nothing selected shows the construction
## menu, a selected building shows its producibles, selected units show the
## Move/Stop/Attack/Patrol commands.
@onready var action_panel_grid: GridContainer = $UI/BottomBar/ActionPanel/Margin/VBox/Grid

@onready var chat_log: RichTextLabel = $UI/BottomBar/ChatLog
@onready var chat_input: LineEdit = $UI/BottomBar/ChatInput

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
## Played for the placing player the moment a build order goes out, in place
## of the generic command sound.
@export var on_building_placed_sound_effects: Array[AudioStream] = []
## Played for a building's owner when it finishes construction — relayed from
## the host, which is the only peer where construction_finished fires.
@export var on_building_completed_sound_effects: Array[AudioStream] = []
## Played when a placement click lands somewhere the current ghost can't
## actually go. Placement mode deliberately stays armed afterward, so this is
## the only feedback the player gets that the click did nothing — see
## _confirm_placement.
@export var on_placement_blocked_sound_effects: Array[AudioStream] = []
## Played for the owner when they plant a rally banner.
@export var on_rally_set_sound_effects: Array[AudioStream] = []


## The lines a unit can shout back when an order is issued, one list per
## command kind (keys match _spawn_command_popup's `kind`). Each entry pairs
## the text with its own voice clip, so adding or reordering lines can't
## desync the two — see CommandLine. Entries with no text are skipped and
## entries with no clip pop silently, so these can be filled in gradually.
@export var move_command_lines: Array[CommandLine] = []
@export var attack_command_lines: Array[CommandLine] = []
@export var patrol_command_lines: Array[CommandLine] = []
@export var build_command_lines: Array[CommandLine] = []

@onready var ui_root: Node = $UI
@onready var minimap: Control = $UI/BottomBar/MinimapFrame/Minimap

func _play_command_sound() -> void:
	AudioUtils.play_random(command_audio_player, on_command_sound_effects)

func _play_placement_blocked_sound() -> void:
	AudioUtils.play_random(command_audio_player, on_placement_blocked_sound_effects)

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

## The authored lines for `kind`, or an empty list if it has none. Kept as a
## match rather than a Dictionary because the arrays are @export vars, which
## can't be referenced from a const.
func _command_lines_for(kind: String) -> Array[CommandLine]:
	match kind:
		"move": return move_command_lines
		"attack": return attack_command_lines
		"patrol": return patrol_command_lines
		"build": return build_command_lines
	return []

## The CommandLine most recently played for each command kind, so the next
## pick for that kind can exclude it. See _spawn_command_popup.
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
func _spawn_command_popup(kind: String, world_pos: Vector3) -> void:
	if ui_root == null:
		return
	## Same behind-camera rejection as _spawn_pinned_popup: a point behind the
	## camera unprojects to a plausible-looking on-screen position, so an
	## order issued and then spun away from would pop up in mid-view.
	if camera.is_position_behind(world_pos):
		return
	## Blank entries are skipped rather than picked and shown empty, so a
	## part-filled array in the inspector never produces an invisible popup.
	var choices: Array[CommandLine] = []
	for line in _command_lines_for(kind):
		if line != null and not line.text.is_empty():
			choices.append(line)
	if choices.is_empty():
		return

	## Same no-repeat rule as AudioUtils.play_random, tracked per kind here
	## because text and voice are picked together as one CommandLine: hearing
	## (and reading) the identical line on two consecutive clicks is the most
	## noticeable way a small pool of lines sounds wrong.
	if choices.size() > 1:
		var last: CommandLine = _last_command_line.get(kind, null)
		var unrepeated: Array[CommandLine] = []
		for line in choices:
			if line != last:
				unrepeated.append(line)
		if not unrepeated.is_empty():
			choices = unrepeated

	var chosen: CommandLine = choices[randi() % choices.size()]
	_last_command_line[kind] = chosen
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
	ui_root.add_child(label)

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
		if camera.is_position_behind(anchor):
			label.visible = false
			return
		label.visible = true
		label.position = camera.unproject_position(anchor) - half + drift * t
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
## Client-local formation shape choice — which Formation.Type the next move/
## attack-move order for the current selection will use. Set via
## _set_formation_type (FORMATION_BOX_KEY/LINE_KEY/STAGGERED_KEY below) and
## sent along with each move order's RPC so the host (the only side that
## simulates movement) knows which shape to arrange the group's slots into.
var current_formation_type: Formation.Type = Formation.DEFAULT_TYPE
## Host-only reformation bookkeeping — one record per in-flight multi-unit
## formation move (see _register_formation/_update_reformation). Records are
## created when a move is dispatched, polled once a frame to notice members
## dropping out (death, or being pulled into a fight), and dropped as soon as
## fewer than two members are still walking this order. Never networked and
## never touched on a client: only the host ever solves or issues slots.
var _active_formations: Array[Dictionary] = []
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
var _info_progress_bar: TextureProgressBar = null
var _info_empty_label: Label = null
var _info_slot_row: HBoxContainer = null
var _info_last_queue_size: int = -1
## The building state the info section's structure was built for. Ownership and
## construction state both change what gets built (an enemy or half-built
## building has no queue rows), and both can flip while the building stays
## selected — capturing an objective being the obvious case — so the structure
## is rebuilt when either stops matching.
var _info_built_commandable: bool = false
var _info_built_under_construction: bool = false
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

## --- Wall drag placement (placing_type.is_wall) ---
## True from the moment the left mouse button goes down over valid ground
## until it's released — _update_wall_drag() only grows _wall_drag_points
## while this is true; before/after that a click just arms or ends the drag.
var _wall_dragging: bool = false
## Sampled every _process() frame while dragging, spaced ~wall_segment_length
## apart along the actual cursor path (not a straight line from start to
## current point) so the wall follows curves/turns the same way the mouse
## drew them — see _wall_extend_path_to().
var _wall_drag_points: Array[Vector3] = []
## One ghost Node3D per would-be segment/corner, rebuilt (not just
## repositioned) every time _wall_drag_points changes length, since the
## count of pieces changes as the drag grows. Tinted per-piece (unlike the
## single-ghost case) so one bad segment in an otherwise-clear run is visible
## without invalidating pieces that are actually fine.
var _wall_ghosts: Array[Node3D] = []
## Live "N segments — cost" readout shown while dragging — see its creation
## in _ready() and updates in _rebuild_wall_ghost().
var _wall_drag_label: Label = null
## Voice lines get their own player rather than sharing
## command_audio_player: that one is a single stream, so a voice line sent
## through it would cut off the command sound firing at the same moment.
## Built in code for the same reason as _wall_drag_label below.
var _voice_audio_player: AudioStreamPlayer = null
const WALL_SEGMENT_FOOTPRINT_RADIUS: float = 0.9
const WALL_CORNER_FOOTPRINT_RADIUS: float = 0.45
## Minimum direction change (radians) between two consecutive straight runs
## of the drag path before a corner piece is inserted — small jitter in the
## mouse path shouldn't spam corner posts along an otherwise-straight wall.
const WALL_CORNER_ANGLE_THRESHOLD: float = 0.28
## Hard cap on segments per single drag — keeps one drag's RPC payload and
## cost bounded even if a player drags all the way across the map.
const WALL_MAX_SEGMENTS: int = 80

## --- Gate tool (placing_type.is_gate_tool) ---
## The owned wall segment/corner currently under the mouse that the gate
## would replace if clicked, or null when nothing valid is hovered.
var _gate_target: ProductionBuilding = null

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
	preload("res://resources/favour_resource_type.tres"),
]
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
var chat_lines: Array[String] = []
## Bumped on every show/hide request so a stale timer (from an older message)
## doesn't hide the log after a newer one already reset the countdown.
var _chat_hide_token: int = 0
const CHAT_LOG_VISIBLE_DURATION: float = 3.0
const CHAT_LOG_FADE_DURATION: float = 0.5
var _chat_log_tween: Tween

## resource_label shows every resource total plus population on one line;
## rebuilt in full on any single change since there are only a handful of values.
var _resource_totals: Dictionary = {}
var _population_used: int = 0
var _population_cap: int = 0

## resource_name -> true while it's one of the ones flashing red because the
## last attempted purchase couldn't afford it — see _flash_missing_resources.
var _flashing_resource_names: Dictionary = {}
var _resource_display_totals: Dictionary = {}
var _impact_process_material: ParticleProcessMaterial
var _impact_mesh: QuadMesh
var _rally_dust_material: ParticleProcessMaterial
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
	## Connected before _spawn_all_players() (not after) so the host's own
	## spawn fires this too, not just a joining client's replicated one —
	## CameraRig's authored position in main.tscn only happens to line up
	## with spawn index 0, so every peer needs this to see their own base.
	building_spawner.spawned.connect(_on_building_spawned_for_camera)
	if multiplayer.is_server():
		_spawn_all_players()

	## After _spawn_all_players(), so the starting bases are carved by the
	## very first bake instead of triggering a second one a poll later. A
	## joining client has none of that yet and picks them up as they replicate.
	_start_navigation_blockers()

	_build_impact_effect_resources()
	chat_input.text_submitted.connect(_on_chat_submitted)
	minimap.ping_requested.connect(_on_minimap_ping_requested)

	var utility_buttons: VBoxContainer = $UI/BottomBar/UtilityButtons
	utility_buttons.get_node(^"IdleButton").pressed.connect(_select_next_idle_villager)
	utility_buttons.get_node(^"FormationBoxButton").pressed.connect(_set_formation_type.bind(Formation.Type.BOX))
	utility_buttons.get_node(^"FormationLineButton").pressed.connect(_set_formation_type.bind(Formation.Type.LINE))
	utility_buttons.get_node(^"FormationStaggeredButton").pressed.connect(_set_formation_type.bind(Formation.Type.STAGGERED))
	chat_log.visible = false
	UiDebugEditor.register_editable_root(ui_root, "main")

	game_over_panel.visible = false
	$UI/GameOverPanel/Margin/VBox/ReturnButton.pressed.connect(_on_return_to_lobby_pressed)

	Network.player_disconnected.connect(_on_network_player_disconnected)
	Network.server_disconnected.connect(_on_network_server_disconnected)
	_build_opponent_left_panel()

	## Live "N segments — cost" readout for the wall drag tool — built here
	## rather than in main.tscn: a small always-on-top overlay isn't worth
	## another hand-edit to an already enormous scene file. Hidden except
	## mid-drag; see _rebuild_wall_ghost().
	_voice_audio_player = AudioStreamPlayer.new()
	_voice_audio_player.bus = &"SFX"
	ui_root.add_child(_voice_audio_player)

	_wall_drag_label = Label.new()
	_wall_drag_label.visible = false
	_wall_drag_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wall_drag_label.add_theme_font_size_override("font_size", 20)
	_wall_drag_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_wall_drag_label.add_theme_constant_override("shadow_offset_x", 1)
	_wall_drag_label.add_theme_constant_override("shadow_offset_y", 1)
	_wall_drag_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_wall_drag_label.position = Vector2(-100.0, 12.0)
	_wall_drag_label.custom_minimum_size = Vector2(200.0, 0.0)
	_wall_drag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui_root.add_child(_wall_drag_label)

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

## --- Navigation ---

## Runs on every peer, not just the host: the navmesh is what every local
## NavigationAgent3D plans against, and buildings replicate to everyone, so
## each peer keeps its own copy carved. Created in code rather than authored
## into main.tscn — it needs no configuration beyond the region it watches,
## and main.tscn is already enormous.
func _start_navigation_blockers() -> void:
	var region := get_node_or_null(^"NavigationRegion3D") as NavigationRegion3D
	if region == null:
		return
	var blockers := NavigationBlockers.new()
	blockers.name = "NavigationBlockers"
	add_child(blockers)
	blockers.setup(region)

## --- Player / unit / building spawning (host only) ---

func _spawn_all_players() -> void:
	var peer_ids: Array = [1]
	if multiplayer.multiplayer_peer != null:
		peer_ids.append_array(multiplayer.get_peers())
	for i in peer_ids.size():
		_spawn_player_base(peer_ids[i], i)

## The color this player chose in the lobby, and the single place that answer
## comes from — every spawn path here and scripts outside main.gd (objective.gd
## re-tinting a captured building, reached via get_tree().current_scene) go
## through this rather than resolving a palette entry themselves.
##
## Falls back to the palette by join order for anyone who reaches a match
## without a choice: the established run-main.tscn-straight-from-the-editor
## workflow bypasses the lobby entirely, so Network.players is empty there and
## nobody ever picked.
func get_team_tint(peer_id: int) -> Color:
	var chosen: Color = Network.players.get(peer_id, {}).get("color", Color.WHITE)
	if chosen != Color.WHITE:
		return chosen
	var team_index: int = team_index_by_peer.get(peer_id, 0)
	return Network.TEAM_COLORS[team_index % Network.TEAM_COLORS.size()]

## index < 0 (or unset) defaults everyone to available_factions[0] — the safe
## fallback for the established direct-run-main.tscn-in-editor workflow, which
## bypasses the lobby (and thus Network.players) entirely.
func _faction_for_peer(peer_id: int) -> Faction:
	var faction_index: int = Network.players.get(peer_id, {}).get("faction_index", 0)
	return available_factions[faction_index] if faction_index < available_factions.size() else available_factions[0]

func _spawn_player_base(peer_id: int, index: int) -> void:
	var spawn_point: PlayerSpawnPoint = player_spawn_points.get_child(index % player_spawn_points.get_child_count())
	team_index_by_peer[peer_id] = index
	var tint: Color = get_team_tint(peer_id)
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
	unit.resource_harvested.connect(_on_unit_resource_harvested)
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

## Order-dispatch functions below only ever run on the host (inside its RPC
## handlers), so — same reasoning as animation_changed above — playing the
## sound directly there would only ever be heard on the host's own machine.
## Unlike animation, though, this goes to exactly ONE peer rather than all of
## them: an order acknowledgment is interface feedback on the ordering
## player's own click, and letting an opponent hear it would leak both what
## they're doing and roughly where. So the host either owns the unit and plays
## it locally, or forwards it to the single peer that does.
func _play_unit_order_sound(unit: Unit, kind: Unit.OrderSoundKind) -> void:
	if unit.owner_peer_id == _my_peer_id():
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

## Building equivalent of _on_unit_projectile_fired/_rpc_spawn_projectile_visual/
## _spawn_projectile_visual above — kept separate rather than sharing those
## (typed for Unit) since Unit and ProductionBuilding have no common combat
## base class (see CombatUtils' own header comment for why).
func _on_building_projectile_fired(target: Node3D, building: ProductionBuilding) -> void:
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
	## get() rather than node.owner_peer_id: this takes a plain Node3D (Unit
	## and ProductionBuilding both land here), and a missing property comes
	## back null, which simply compares unequal.
	var mine: bool = node.get("owner_peer_id") == multiplayer.get_unique_id()
	_show_damage_number(node, amount, mine)
	_spawn_impact_burst(node.global_position + Vector3(0, 0.9, 0))
	if node is Unit:
		node.play_hit_flash()
	elif node is ProductionBuilding:
		node.play_hit_flash()
		node.play_squash()
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
	if not node.is_visible_in_tree():
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
func _spawn_rally_dust(world_pos: Vector3) -> void:
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
func _relay_impact_shake(world_pos: Vector3, amount: float) -> void:
	camera_rig.shake_at(world_pos, amount)
	if multiplayer.is_server() and multiplayer.multiplayer_peer != null:
		_rpc_impact_shake.rpc(world_pos, amount)

@rpc("authority", "call_remote", "unreliable")
func _rpc_impact_shake(world_pos: Vector3, amount: float) -> void:
	camera_rig.shake_at(world_pos, amount)

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
	if node_owner_peer_id != _my_peer_id():
		return
	var now := Time.get_ticks_msec()
	if now - _last_under_attack_alert_ms < UNDER_ATTACK_ALERT_COOLDOWN_MS:
		return
	_last_under_attack_alert_ms = now
	_last_attack_position = node.global_position
	_has_attack_alert = true
	AudioUtils.play_random(command_audio_player, on_under_attack_sound_effects)
	minimap.show_attack_ping(node.global_position)

func _jump_to_last_attack() -> void:
	if not _has_attack_alert:
		return
	camera_rig.global_position.x = _last_attack_position.x
	camera_rig.global_position.z = _last_attack_position.z

## Production and resource deposits both resolve host-side, so a building's
## squash is relayed out the same way the gatherable's is.
func _relay_building_squash(building: ProductionBuilding) -> void:
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
func _on_unit_resource_harvested(node: Gatherable) -> void:
	node.play_harvest_squash()
	if multiplayer.is_server() and multiplayer.multiplayer_peer != null:
		_rpc_harvest_squash.rpc(node.get_path())

@rpc("authority", "call_remote", "unreliable")
func _rpc_harvest_squash(node_path: NodePath) -> void:
	var node := get_node_or_null(node_path) as Gatherable
	if node:
		node.play_harvest_squash()

func _on_unit_resource_deposited(amount: int, color: Color, unit: Unit) -> void:
	_spawn_deposit_popup(unit, amount, color)
	var dropoff := unit.dropoff_point.get_parent() as ProductionBuilding if unit.dropoff_point else null
	if dropoff:
		_relay_building_squash(dropoff)
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
## goes through here. Built like _spawn_command_popup (2D Label in ui_root,
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
	if ui_root == null:
		return null
	if not ignore_fog and not fog_of_war.is_visible_at(world_pos):
		return null
	## A point behind the camera still unprojects to a plausible-looking
	## on-screen position, so it has to be rejected explicitly or popups from
	## behind the player would appear in the middle of the view.
	if camera.is_position_behind(world_pos):
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
	ui_root.add_child(label)

	## See _spawn_command_popup — size is zero until this forces the layout.
	label.reset_size()
	label.pivot_offset = label.size * 0.5
	label.rotation = deg_to_rad(randf_range(-7.0, 7.0))

	## Perspective cue the Label3D version got for free: a label over a distant
	## unit shrinks, one over a zoomed-in fight grows. Applied as a scale
	## multiplier rather than a font_size, so the punch tween below stays a
	## single property animation and no re-layout is needed. Sampled once at
	## spawn — a popup only lives ~0.6s, so zooming mid-flight is not worth
	## fighting the scale tween over.
	var camera_scale := clampf(POPUP_REFERENCE_DISTANCE / maxf(camera.global_position.distance_to(world_pos), 0.001),
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
		if camera.is_position_behind(anchor):
			label.visible = false
			return
		label.visible = true
		label.position = camera.unproject_position(anchor) - half + drift * t
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

## Hand-placed buildings (currently just Objective guards' buildings) never
## go through _spawn_building_from_data below, so without this their
## item_completed/destroyed signals have no listener and producing a unit
## silently does nothing. Called by objective.gd once per building at _ready.
## The unit equivalent of register_objective_building below: an Objective's
## guards are hand-placed in its .tscn rather than going through
## _spawn_unit_from_data, so nothing had ever connected their signals — hitting
## one produced no damage number, and on a client it neither animated nor drew
## the arrows it was shooting. Called by objective.gd.
##
## Deliberately a complete mirror of the connections in _spawn_unit_from_data
## rather than only the ones a guard demonstrably needs today. The two lists
## drifting apart is what caused this in the first place, and a guard does not
## stay a guard: capturing an objective hands it to a player (see
## Objective._capture), after which it takes orders like any other unit —
## order_completed in particular is what advances a shift-queued order chain,
## so without it a captured guard would run the first order of a queue and
## silently drop the rest.
func register_objective_unit(unit: Unit) -> void:
	unit.animation_changed.connect(_on_unit_animation_changed.bind(unit))
	unit.projectile_fired.connect(_on_unit_projectile_fired.bind(unit))
	unit.damaged.connect(_relay_damage_number.bind(unit))
	unit.resource_deposited.connect(_on_unit_resource_deposited.bind(unit))
	unit.resource_harvested.connect(_on_unit_resource_harvested)
	unit.order_completed.connect(_on_unit_order_completed.bind(unit))

func register_objective_building(building: ProductionBuilding) -> void:
	building.item_completed.connect(_on_building_item_completed.bind(building))
	building.destroyed.connect(_on_building_destroyed.bind(building))
	building.damaged.connect(_relay_damage_number.bind(building))
	building.projectile_fired.connect(_on_building_projectile_fired.bind(building))

## Most buildable structures are ProductionBuildings (Town Center, Barracks,
## House), but Farm is a buildable Gatherable (no construction/production
## queue, just gathered from directly) — so this has to handle both instead
## of assuming ProductionBuilding.
func _spawn_building_from_data(data: Dictionary) -> Node:
	var scene: PackedScene = load(data.scene_path)
	var node: Node = scene.instantiate()
	node.position = data.position
	## Only wall pieces ever supply this — every other buildable structure is
	## placed axis-aligned, so this key is simply absent for them.
	if data.has("rotation") and node is Node3D:
		(node as Node3D).rotation = data.rotation

	if node is ProductionBuilding:
		var building: ProductionBuilding = node
		building.owner_peer_id = data.peer_id
		building.team_tint = data.get("tint", Color.WHITE)
		building.item_completed.connect(_on_building_item_completed.bind(building))
		building.destroyed.connect(_on_building_destroyed.bind(building))
		building.damaged.connect(_relay_damage_number.bind(building))
		building.construction_finished.connect(_on_building_construction_finished.bind(building))
		building.projectile_fired.connect(_on_building_projectile_fired.bind(building))
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
	_relay_impact_shake(building.global_position, 0.55)
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

## Built in code rather than added to main.tscn, same reasoning as the wall
## drag label above — this is small and only needs to exist at all
## once Quick Play makes opponent disconnects a routine occurrence rather
## than the rare LAN-friend-crashed case it used to be.
var _opponent_left_panel: PanelContainer = null
var _opponent_left_label: Label = null

func _build_opponent_left_panel() -> void:
	_opponent_left_panel = PanelContainer.new()
	_opponent_left_panel.visible = false
	_opponent_left_panel.set_anchors_preset(Control.PRESET_CENTER)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_opponent_left_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(vbox)

	_opponent_left_label = Label.new()
	_opponent_left_label.add_theme_font_size_override("font_size", 24)
	_opponent_left_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_opponent_left_label)

	var return_button := Button.new()
	return_button.text = "Return to Lobby"
	return_button.pressed.connect(_on_return_to_lobby_pressed)
	vbox.add_child(return_button)

	ui_root.add_child(_opponent_left_panel)

func _show_opponent_left(message: String) -> void:
	if game_over:
		return
	_opponent_left_label.text = message
	_opponent_left_panel.visible = true

func _on_network_player_disconnected(_peer_id: int, player_data: Dictionary) -> void:
	_show_opponent_left("%s disconnected." % player_data.get("name", "Opponent"))

func _on_network_server_disconnected() -> void:
	_show_opponent_left("Lost connection to host.")

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
	## population_cost isn't passed here — the spawned scene's own Unit.population_cost
	## (set right on the unit for balancing, see get_population_cost()) is already authoritative.
	var unit: Unit = unit_spawner.spawn({
		"scene_path": item.unit_scene.resource_path,
		"peer_id": building.owner_peer_id,
		"tint": get_team_tint(building.owner_peer_id),
		"position": spawn_pos,
	})
	_relay_building_squash(building)
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
	_relay_impact_shake(building.global_position, 0.25)
	if not multiplayer.is_server():
		return
	_rpc_display_chat.rpc_id(building.owner_peer_id, "Construction complete: %s" % building.building_name)
	_rpc_building_completed_sound.rpc_id(building.owner_peer_id)

@rpc("authority", "call_local", "reliable")
func _rpc_building_completed_sound() -> void:
	AudioUtils.play_random(command_audio_player, on_building_completed_sound_effects)

func _get_dropoff_for(peer_id: int) -> Node3D:
	var town_center: ProductionBuilding = town_centers.get(peer_id)
	if town_center == null:
		return null
	return town_center.get_node_or_null("DropoffPoint")

func _process(delta: float) -> void:
	_update_resource_ticker(delta)
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
		if placing_type.is_wall:
			_update_wall_drag()
		elif placing_type.is_gate_tool:
			_update_gate_ghost()
		else:
			_update_placement_ghost()
	_update_hover_ring()
	_update_path_markers()
	_update_reformation(delta)

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

	if event is InputEventKey and event.pressed and not event.echo:
		_pulse_action_button(OS.get_keycode_string(event.keycode))

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
		if event.keycode == FORMATION_BOX_KEY:
			_set_formation_type(Formation.Type.BOX)
			get_viewport().set_input_as_handled()
			return
		elif event.keycode == FORMATION_LINE_KEY:
			_set_formation_type(Formation.Type.LINE)
			get_viewport().set_input_as_handled()
			return
		elif event.keycode == FORMATION_STAGGERED_KEY:
			_set_formation_type(Formation.Type.STAGGERED)
			get_viewport().set_input_as_handled()
			return
		elif event.keycode == FORMATION_REFORM_KEY:
			_issue_reform_order()
			get_viewport().set_input_as_handled()
			return
		elif event.keycode == UNIT_MOVE_KEY:
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
			if _can_command_building(selected_building) and selected_building.can_rally:
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

## Fires for every unit/building spawn on every peer (see the spawner.spawned
## connection above); only acts on this peer's own main-base Town Center, and
## only the first time, so the camera opens over your own base instead of
## wherever CameraRig happens to be authored in main.tscn.
var _camera_centered_on_spawn: bool = false

func _on_building_spawned_for_camera(node: Node) -> void:
	if _camera_centered_on_spawn:
		return
	if not (node is ProductionBuilding):
		return
	var building: ProductionBuilding = node
	if building.owner_peer_id != _my_peer_id() or not building.is_main_base:
		return
	_camera_centered_on_spawn = true
	_center_camera_on([building])

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
		## Any building is selectable, not just your own — an enemy's is worth
		## inspecting. A fogged building keeps its collider (fog only toggles
		## .visible, see fog_of_war.gd), so revealed-ness is checked here or
		## you could click buildings you haven't scouted yet.
		elif collider is ProductionBuilding and collider.visible:
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

## A right-click is a move order by default, but right-clicking something
## hostile issues an attack instead (see _rpc_issue_command) — so the popup
## has to read the same target _resolve_order_target_path does rather than
## assuming "move", or clicking an enemy would cheerfully answer "On my way!".
## Deliberately only enemy-owned things count: _resolve_order_target_path also
## returns a path for Gatherables and for friendly buildings that are under
## construction or sit on a deposit, and none of those are attacks.
func _popup_kind_for_order(result: Dictionary) -> String:
	var collider = result.get("collider")
	if (collider is Unit or collider is ProductionBuilding) \
			and collider.owner_peer_id != _my_peer_id():
		return "attack"
	return "move"

## Selection is local, but actually moving/gathering only ever happens on the
## host, so the command is sent there and executed on its authoritative units.
## append: true while Shift is held — the order is queued to run after
## whatever this unit is currently doing (including any earlier shift-queued
## orders) instead of replacing it — see _rpc_issue_command.
## Client-local: no networking needed here since it only decides which shape
## *this* player's own next move order will request — the host is still the
## one that actually computes and enforces the resulting slot positions (see
## current_formation_type/_rpc_issue_command).
func _set_formation_type(type: Formation.Type) -> void:
	current_formation_type = type
	formation_label.text = "Formation: %s" % Formation.type_name(type)

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
	_rpc_issue_command.rpc_id(1, unit_paths, target_path, result.position, false, append, current_formation_type)
	_play_command_sound()
	_play_command_feedback(result.position, false)
	_spawn_command_popup(_popup_kind_for_order(result), result.position)
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
	_rpc_issue_command.rpc_id(1, unit_paths, target_path, result.position, true, append, current_formation_type)
	_play_command_sound()
	_play_command_feedback(result.position, true)
	_spawn_command_popup("attack", result.position)
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
func _rpc_issue_command(unit_paths: Array[NodePath], target_path: NodePath, world_pos: Vector3, attack_move_fallback: bool, append: bool, formation_type: Formation.Type = Formation.DEFAULT_TYPE) -> void:
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

	var formation_positions := _formation_positions(units, world_pos, formation_type)
	## Chokepoint funnelling: if the route to the destination has to thread
	## something narrower than this formation is wide (a gate, a slot between
	## buildings), every unit heads for a shared waypoint just past that gap
	## first and only disperses to its own slot once through — otherwise the
	## flanks of a wide shape each path to their own slot independently and the
	## group smears itself along the wall instead of columning up. Empty (the
	## common case: open ground, or a single/small group) leaves dispatch
	## exactly as it was. Host-side and one-shot, same as the formation shape
	## itself — see _find_funnel_point.
	##
	## Computed lazily, at the first unit that actually gets an immediate
	## ground-move dispatch: the analysis costs a navmesh path query plus a pass
	## over every building, and a gather/attack/build order (target_node set —
	## those ignore world_pos entirely) or a wholly shift-queued one would throw
	## the answer away.
	var funnel: Dictionary = {}
	var funnel_resolved: bool = target_node != null
	## Capping the whole group to its slowest member's speed is what actually
	## keeps a mixed-speed selection's formation shape intact throughout the
	## move — the nearest-slot assignment above already gets everyone to the
	## right place, but without this a fast unit reaches its slot early and
	## drifts/jostles around while slower units are still catching up.
	var group_speed := _slowest_move_speed(units)
	## Group cohesion (see Unit.formation_group/_update_cohesion) piggybacks
	## on the same "is this an actual multi-unit formation move" signal as
	## group_speed itself — only wire units together into a shared group when
	## there's more than one of them, so a single-unit order never carries
	## cohesion tracking it has no use for.
	## One shared array reference handed to every unit in the group (cheaper
	## than a per-unit filtered copy) — it therefore includes the unit itself
	## alongside its groupmates. Unit._update_cohesion is responsible for
	## skipping `other == self` when it averages this group's progress, so a
	## unit's own progress never counts toward its own "group average".
	var cohesion_group: Array[Unit] = units if group_speed > 0.0 else ([] as Array[Unit])
	for i in units.size():
		var unit := units[i]
		## append only actually queues if the unit is currently mid-order —
		## an idle unit (nothing to finish first) or one that already has a
		## queue going dispatches/appends normally either way, but a unit
		## with nothing in flight has nothing for order_completed to ever
		## fire from, so queuing here would silently strand the order forever.
		var unit_is_busy := unit.status_command != Unit.Command.NONE or not unit.order_queue.is_empty()
		if append and unit_is_busy:
			unit.queue_order(target_path, formation_positions[i], attack_move_fallback, group_speed, cohesion_group)
		else:
			unit.clear_order_queue()
			_dispatch_smart_command(unit, target_node, formation_positions[i], attack_move_fallback, group_speed, cohesion_group)
			## Only on the immediately-dispatched branch, never on a queued one:
			## the gap geometry was measured against where the group is standing
			## right now, and a shift-queued leg doesn't start until some
			## unknown amount of movement later, by which point that waypoint
			## could be anywhere relative to the unit. set_funnel_waypoint is
			## itself a no-op unless the dispatch above actually resulted in a
			## move/attack-move (a gather/attack/build target ignores the slot
			## position entirely, so it has no funnel leg to run).
			if not funnel_resolved:
				funnel_resolved = true
				funnel = _find_funnel_point(units, _group_centroid(units), world_pos, formation_positions)
			if not funnel.is_empty():
				_apply_funnel(unit, funnel)
	## Reformation bookkeeping: remember this group's destination and shape so
	## the host can close ranks around whoever is still walking it when members
	## die en route (see _update_reformation). Registered from the units'
	## post-dispatch state rather than blindly from `units` — a shift-queued
	## member hasn't started this leg yet, and a gather/attack/build target
	## ignores formation slots entirely, so neither belongs in a record whose
	## whole job is re-solving move slots.
	_register_formation(cohesion_group, world_pos, formation_type, attack_move_fallback)

## Arranges units into the given Formation.Type shape, oriented to face the
## direction of travel — front rank/slot arrives exactly at target_pos,
## further ranks trail behind it — instead of a fixed screen-space block
## that never rotated with the order. Only matters for the plain-move/
## attack-move fallback in _dispatch_smart_command; a gather/attack/build
## target ignores its assigned position entirely and paths to the target
## node itself. Actual per-shape geometry lives in Formation
## (scripts/formation.gd) — this just builds the facing and hands off to it.
##
## Returned positions are aligned to `units` by index (result[i] is where
## units[i] should go), but which unit gets which shape slot is decided by
## nearest-available-slot assignment (see _assign_slots_to_units), not by
## raw selection order — assigning slot i to units[i] directly would send
## units to whichever slot their index happened to land on regardless of
## where they actually are, causing them to needlessly cross paths to swap
## places with each other.
func _formation_positions(units: Array[Unit], target_pos: Vector3, formation_type: Formation.Type = Formation.DEFAULT_TYPE) -> Array[Vector3]:
	if units.is_empty():
		return []
	if units.size() == 1:
		return [target_pos]

	var forward := _group_forward(_group_centroid(units), target_pos)
	var right := Vector3(forward.z, 0.0, -forward.x)

	var formation := Formation.new(units, formation_type)
	var slots := formation.get_slot_positions(target_pos, forward, right)

	return _assign_slots_to_units(units, slots)

func _group_centroid(units: Array[Unit]) -> Vector3:
	var centroid := Vector3.ZERO
	if units.is_empty():
		return centroid
	for unit in units:
		centroid += unit.global_position
	centroid /= units.size()
	return centroid

## The group's direction of travel, flattened to XZ. Degenerate case (target
## basically on top of the group's own centroid) still needs a facing to build
## `right` from — arbitrary is fine, it only affects which way a
## near-zero-distance formation fans out.
func _group_forward(centroid: Vector3, target_pos: Vector3) -> Vector3:
	var to_target := target_pos - centroid
	to_target.y = 0.0
	return to_target.normalized() if to_target.length_squared() > 0.0001 else Vector3.FORWARD

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

## Chokepoint funnelling (see _find_funnel_point). How far to either side of the
## route we bother looking for something that constricts it — anything further
## out than this isn't shaping the corridor the group walks down, and treating
## it as "the corridor edge" would make wide-open ground read as a gap.
const CHOKE_PROBE_HALF_WIDTH: float = 12.0
## Granularity of the corridor-width scan along the route, in meters. The gap
## we care about (a gate, a slot between two buildings) is a couple of meters
## across, so anything much finer than this only costs cycles.
const CHOKE_BIN_SIZE: float = 2.0
## Gaps narrower than this aren't a chokepoint to thread, they're a wall. Herding
## the whole group at a waypoint they physically can't squeeze through would be
## strictly worse than letting them path individually, so we leave those alone.
const CHOKE_MIN_GAP: float = 1.0
## How much narrower than the formation a gap has to be before it's worth
## funnelling. Without a margin, a formation that fits with centimeters to spare
## would still trigger the whole two-stage detour for no visible gain.
const CHOKE_WIDTH_MARGIN: float = 1.5
## Funnelling is a group behavior; a pair of units negotiates a gate fine on its
## own and the waypoint detour would just be overhead.
const CHOKE_MIN_UNITS: int = 3
## How far past the gap the funnel waypoint is placed. Has to clear the gap
## itself (so "reached the waypoint" genuinely means "through"), but staying
## modest keeps units fanning out to their slots promptly on the far side.
const CHOKE_EXIT_AHEAD: float = 3.5
## Ignore constrictions this close to either end of the route: one right on top
## of the group is something they're already inside (funnelling backwards into
## it helps nobody), and one at the destination is just the destination being
## tight, which the formation shape itself has to deal with.
const CHOKE_MIN_DISTANCE_FROM_GROUP: float = 5.0
const CHOKE_MIN_DISTANCE_FROM_TARGET: float = 4.0
## Radius of the NavigationObstacle3D a passage's flanking structure carries per
## side (0.2 per post on wall_gate.tscn). It isn't the physical geometry that
## decides whether a unit fits through an opening — RVO steers off obstacle
## centres, so each side effectively reaches this far in on top of its own
## agent-radius standoff.
const CHOKE_PASSAGE_SIDE_RADIUS: float = 0.2
## Narrowest opening worth funnelling a group at. An agent needs its own radius
## plus the flanking obstacle's on BOTH sides before any of it is walkable, so a
## bare agent diameter is nominal rather than protective — a 1.0m opening would
## clear that and still be impassable. Conservative by a little: the obstacles
## sit at the post CENTRES, slightly outside the clear span passage_width
## measures, so real clearance is marginally better than this assumes. A
## passage below it isn't skipped, it stops counting as a doorway and falls
## through to the footprint scan as the blocker it effectively is.
const CHOKE_MIN_PASSAGE_WIDTH: float = (Unit.FORMATION_BASE_RADIUS + CHOKE_PASSAGE_SIDE_RADIUS) * 2.0
## How closely a passage's own axis has to agree with the group's direction of
## travel (|dot|, so either facing counts) before it's accepted. A gate set in a
## wall running alongside the route isn't on the way to anywhere — without this,
## one up to CHOKE_PROBE_HALF_WIDTH off-route would short-circuit the scan and
## drag the formation sideways through a doorway nobody needed. 0.5 is a 60
## degree cone, so an angled but sensible approach still qualifies while a
## near-parallel one (where the through-direction's sign is arbitrary anyway,
## and the waypoint could land on the wrong side of the wall) is rejected.
const CHOKE_PASSAGE_AXIS_DOT: float = 0.5
## Slack added to the formation's raw slot spread to get the width it actually
## needs to pass somewhere — roughly one unit's body diameter (the physical
## CapsuleShape3D radius on scenes/units/unit.tscn is 0.4), since the spread is
## measured between slot centers.
const CHOKE_UNIT_WIDTH: float = 1.0

## Host-side, one-shot-per-order chokepoint analysis: does the route from this
## group's centroid to its destination pass through somewhere narrower than the
## formation is wide? If so, returns the waypoint every unit should thread
## before dispersing to its own slot (see Unit.set_funnel_waypoint), otherwise
## an empty Dictionary and the order dispatches exactly as it always has.
##
## Why geometry and not the navmesh: NavigationBlockers does carve buildings
## out of the region, so the route below already goes *around* them — but a
## navmesh path is a corridor of arbitrary width reduced to a center line, and
## nothing in it says whether the gap it threads is a wide street or a gate
## barely wider than one unit. The navmesh path is used as the route's *shape*
## (so terrain and building detours are both followed), while the corridor
## width along it is measured against the actual building footprints.
##
## Cost: one path query plus one pass over the building list, and only on an
## order that could actually use the answer. No per-frame work and no raycasts.
func _find_funnel_point(units: Array[Unit], centroid: Vector3, target_pos: Vector3, slots: Array[Vector3]) -> Dictionary:
	if units.size() < CHOKE_MIN_UNITS:
		return {}
	## Cheap rejections first — everything past this point costs a navmesh path
	## query and a pass over every building on the map, so a formation narrow
	## enough to fit through any gap worth funnelling toward, or a map with
	## nothing built on it, bails before paying for either.
	var required_width := _formation_required_width(slots, centroid, target_pos)
	if required_width < CHOKE_MIN_GAP + CHOKE_WIDTH_MARGIN:
		return {}
	var buildings := get_tree().get_nodes_in_group("buildings")
	if buildings.is_empty():
		return {}

	var route := _route_polyline(units[0], centroid, target_pos)
	if route.size() < 2:
		return {}

	## Cumulative arclength at each route vertex, so a building's projection onto
	## the polyline can be expressed as a single distance-along-route.
	var cumulative: Array[float] = [0.0]
	for i in route.size() - 1:
		cumulative.append(cumulative[i] + _flat_distance(route[i], route[i + 1]))
	var total_length: float = cumulative[cumulative.size() - 1]
	if total_length < CHOKE_MIN_DISTANCE_FROM_GROUP + CHOKE_MIN_DISTANCE_FROM_TARGET:
		return {}

	var bin_count: int = maxi(1, ceili(total_length / CHOKE_BIN_SIZE))
	## Free space remaining on each side of the route center line, per bin, named
	## for the side of the direction of travel they actually describe (`right` is
	## Vector3(forward.z, 0, -forward.x), the same axis the formation shape is
	## built against). Starts "unconstrained" and is whittled down by each
	## building that reaches into the corridor.
	var right_free: Array[float] = []
	var left_free: Array[float] = []
	for i in bin_count:
		right_free.append(CHOKE_PROBE_HALF_WIDTH)
		left_free.append(CHOKE_PROBE_HALF_WIDTH)

	## Nearest walkable opening found on the route, if any — see
	## ProductionBuilding.passage_width and _passage_funnel.
	var best_passage: Dictionary = {}

	for node in buildings:
		var building := node as Node3D
		if building == null or not is_instance_valid(building):
			continue
		var production := building as ProductionBuilding
		if production != null and production.is_destroyed:
			continue
		var hit := _project_onto_route(route, cumulative, building.global_position)
		var arc: float = hit["arc"]
		var lateral: float = hit["lateral_distance"]

		## A gate is a HOLE in a wall, not a blocker, and its footprint describes
		## the structure to either side of that hole rather than the hole itself
		## (wall_gate carries one small obstacle per post, at x = +/-0.85). Run
		## through the obstacle branch below it would read as a solid lump across
		## the very spot units are meant to walk through. Gates are therefore
		## their own kind of candidate: an opening of known width, centred on the
		## node origin.
		##
		## Two things demote one back to an ordinary obstacle rather than skipping
		## it — in both cases it really is blocking the corridor, and the scan
		## should see it as such:
		##   - still under construction (sunk into the ground by
		##     construction_sink_depth, so there's no doorway there yet);
		##   - too narrow for anything to fit through (see
		##     CHOKE_MIN_PASSAGE_WIDTH).
		var passage_width: float = production.passage_width if production != null else 0.0
		if production != null and production.is_under_construction:
			passage_width = 0.0
		if passage_width < CHOKE_MIN_PASSAGE_WIDTH:
			passage_width = 0.0
		if passage_width > 0.0:
			## Wide enough that the formation doesn't have to change shape for
			## it: not a chokepoint at all, and not a blocker either, so it
			## contributes nothing either way.
			if passage_width + CHOKE_WIDTH_MARGIN > required_width:
				continue
			if lateral > CHOKE_PROBE_HALF_WIDTH:
				continue
			if arc < CHOKE_MIN_DISTANCE_FROM_GROUP or arc > total_length - CHOKE_MIN_DISTANCE_FROM_TARGET:
				continue
			## The opening has to actually point the way the group is going. Its
			## axis is the gate's local Z (the structure sits either side of it on
			## local X), flipped where needed so it runs with the route rather
			## than against it.
			var route_forward: Vector3 = _route_point_at(route, cumulative, arc)["forward"]
			var through: Vector3 = building.global_transform.basis.z
			through.y = 0.0
			if through.length_squared() < 0.0001:
				continue
			through = through.normalized()
			var alignment: float = through.dot(route_forward)
			if absf(alignment) < CHOKE_PASSAGE_AXIS_DOT:
				continue
			if alignment < 0.0:
				through = -through
			## Nearest to the route line wins: with several gates in one wall, the
			## one the group is already walking at is the one it should use.
			if best_passage.is_empty() or lateral < float(best_passage["lateral_distance"]):
				best_passage = {"node": building, "lateral_distance": lateral, "through": through}
			continue

		var radius: float = building.get_footprint_radius() if building.has_method("get_footprint_radius") else 0.0
		if radius <= 0.0:
			continue
		var free: float = lateral - radius
		if free > CHOKE_PROBE_HALF_WIDTH:
			continue
		free = maxf(free, 0.0)
		## A building of radius r constricts the corridor over the whole stretch
		## of route it sits alongside, not just the single point it projects to.
		var first_bin: int = clampi(int(floor((arc - radius) / CHOKE_BIN_SIZE)), 0, bin_count - 1)
		var last_bin: int = clampi(int(floor((arc + radius) / CHOKE_BIN_SIZE)), 0, bin_count - 1)
		for b in range(first_bin, last_bin + 1):
			if hit["lateral_sign"] >= 0.0:
				right_free[b] = minf(right_free[b], free)
			else:
				left_free[b] = minf(left_free[b], free)

	## An actual gate on the route beats anything the footprint scan could infer
	## from the wall around it: its width and centre are known exactly rather
	## than measured off neighbouring pieces, and that wall would otherwise
	## register as an impassable stretch and be thrown away below.
	if not best_passage.is_empty():
		return _passage_funnel(best_passage)

	var best_bin: int = -1
	var best_gap: float = INF
	for b in bin_count:
		## Constricted on BOTH sides or it isn't a chokepoint — a single building
		## beside the route is something to walk around, not something to funnel
		## through, and treating it as one edge of a "gap" whose other edge is
		## open ground would fire on any building the group happens to pass.
		if right_free[b] >= CHOKE_PROBE_HALF_WIDTH or left_free[b] >= CHOKE_PROBE_HALF_WIDTH:
			continue
		var arc: float = (b + 0.5) * CHOKE_BIN_SIZE
		if arc < CHOKE_MIN_DISTANCE_FROM_GROUP or arc > total_length - CHOKE_MIN_DISTANCE_FROM_TARGET:
			continue
		var gap: float = right_free[b] + left_free[b]
		if gap < best_gap:
			best_gap = gap
			best_bin = b
	if best_bin < 0 or best_gap < CHOKE_MIN_GAP or best_gap + CHOKE_WIDTH_MARGIN > required_width:
		return {}

	var arc_at_gap: float = (best_bin + 0.5) * CHOKE_BIN_SIZE
	var at := _route_point_at(route, cumulative, arc_at_gap)
	var forward: Vector3 = at["forward"]
	var right := Vector3(forward.z, 0.0, -forward.x)
	## The route center line isn't necessarily the gap's center (the gap can sit
	## off to one side of it) — recenter on the free span actually measured,
	## which runs from -left_free to +right_free along `right`.
	var gap_center: Vector3 = at["position"] + right * ((right_free[best_bin] - left_free[best_bin]) * 0.5)
	return {
		"gap": gap_center,
		"point": gap_center + forward * CHOKE_EXIT_AHEAD,
		"forward": forward,
	}

## Funnel data for a walkable opening (see ProductionBuilding.passage_width).
## Both the gap centre and the direction through it come from the gate's own
## transform rather than from the route: the doorway is centred on the node
## origin and runs along its local Z (already resolved and direction-checked by
## the caller), so a gate approached at an angle still gets a waypoint squarely
## in front of its opening instead of one nudged toward a post.
func _passage_funnel(passage: Dictionary) -> Dictionary:
	var gate: Node3D = passage["node"]
	var through: Vector3 = passage["through"]
	return {
		"gap": gate.global_position,
		"point": gate.global_position + through * CHOKE_EXIT_AHEAD,
		"forward": through,
	}

## Navmesh path when there is one (so the route follows terrain and built-up
## ground rather than cutting through them), straight line otherwise. Only
## ever the *shape* of the route — see _find_funnel_point on why the corridor
## width can't come from the navmesh.
func _route_polyline(unit: Unit, from: Vector3, to: Vector3) -> PackedVector3Array:
	var map: RID = unit.nav_agent.get_navigation_map()
	if map.is_valid():
		var path := NavigationServer3D.map_get_path(map, from, to, true)
		if path.size() >= 2:
			return path
	return PackedVector3Array([from, to])

## Closest point on the route polyline to `point`, as distance-along-route
## ("arc"), perpendicular distance, and which side of the route it's on
## (positive = the route's right-hand side, matching the formation's `right`).
func _project_onto_route(route: PackedVector3Array, cumulative: Array[float], point: Vector3) -> Dictionary:
	var best := {"arc": 0.0, "lateral_distance": INF, "lateral_sign": 1.0}
	var flat_point := Vector3(point.x, 0.0, point.z)
	for i in route.size() - 1:
		var a := Vector3(route[i].x, 0.0, route[i].z)
		var b := Vector3(route[i + 1].x, 0.0, route[i + 1].z)
		var segment := b - a
		var length_squared: float = segment.length_squared()
		if length_squared < 0.0001:
			continue
		var t: float = clampf((flat_point - a).dot(segment) / length_squared, 0.0, 1.0)
		var projected: Vector3 = a + segment * t
		var offset: Vector3 = flat_point - projected
		var distance: float = offset.length()
		if distance >= best["lateral_distance"]:
			continue
		var direction: Vector3 = segment.normalized()
		var right := Vector3(direction.z, 0.0, -direction.x)
		best = {
			"arc": cumulative[i] + sqrt(length_squared) * t,
			"lateral_distance": distance,
			"lateral_sign": 1.0 if offset.dot(right) >= 0.0 else -1.0,
		}
	return best

## Inverse of _project_onto_route: the world position `arc` meters along the
## route, plus the direction of travel there.
func _route_point_at(route: PackedVector3Array, cumulative: Array[float], arc: float) -> Dictionary:
	for i in route.size() - 1:
		var segment_length: float = cumulative[i + 1] - cumulative[i]
		if segment_length < 0.0001:
			continue
		if arc > cumulative[i + 1] and i < route.size() - 2:
			continue
		var t: float = clampf((arc - cumulative[i]) / segment_length, 0.0, 1.0)
		var direction: Vector3 = route[i + 1] - route[i]
		direction.y = 0.0
		return {
			"position": route[i].lerp(route[i + 1], t),
			"forward": direction.normalized() if direction.length_squared() > 0.0001 else Vector3.FORWARD,
		}
	return {"position": route[0], "forward": Vector3.FORWARD}

## How wide a corridor this formation actually needs: the lateral spread of its
## slots (measured on the same left/right axis the shape was built against, so
## trailing ranks don't inflate it) plus one unit's body width, since the spread
## is between slot centers.
func _formation_required_width(slots: Array[Vector3], centroid: Vector3, target_pos: Vector3) -> float:
	if slots.size() < 2:
		return 0.0
	var forward := _group_forward(centroid, target_pos)
	var right := Vector3(forward.z, 0.0, -forward.x)
	var smallest: float = INF
	var largest: float = -INF
	for slot in slots:
		var lateral: float = (slot - target_pos).dot(right)
		smallest = minf(smallest, lateral)
		largest = maxf(largest, lateral)
	return (largest - smallest) + CHOKE_UNIT_WIDTH

## Arms the funnel waypoint on one unit, unless it's already past the gap — a
## unit on the far side would otherwise be sent backwards through the
## chokepoint just to come back out again.
func _apply_funnel(unit: Unit, funnel: Dictionary) -> void:
	var forward: Vector3 = funnel["forward"]
	var offset: Vector3 = unit.global_position - funnel["gap"]
	offset.y = 0.0
	if offset.dot(forward) > 0.0:
		return
	unit.set_funnel_waypoint(funnel["point"], forward)

func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(b.x - a.x, b.z - a.z).length()

## -1 (no override) for a single-unit selection — see Unit.formation_speed.
func _slowest_move_speed(units: Array[Unit]) -> float:
	if units.size() <= 1:
		return -1.0
	var slowest: float = units[0].move_speed
	for unit in units:
		slowest = minf(slowest, unit.move_speed)
	return slowest

## ---------------------------------------------------------------------------
## Reformation
##
## A formation is solved once, at order time (_formation_positions). Without
## anything else that layout is frozen for the whole journey: if four of a
## twelve-unit box die on the way, the eight survivors keep walking to their
## original twelve-slot layout and arrive as a block with four holes in it,
## and a group scattered by a fight or an obstacle never pulls itself back
## together. The two entry points below fix exactly that and nothing else —
## they re-solve and re-issue slots, and never change how a shape is generated
## (Formation), how cohesion paces it (Unit._update_cohesion) or how the
## funnel threads it (_find_funnel_point):
##   — automatic: _update_reformation polls each live formation record for
##     members dropping out and closes ranks around the survivors;
##   — explicit: _issue_reform_order (FORMATION_REFORM_KEY) re-tightens the
##     current selection around its own centroid.
## Both are host-side. The explicit one is a plain RPC to the server exactly
## like a move order; no formation state is ever predicted or solved client-side.
## ---------------------------------------------------------------------------

## How long a record waits after noticing it lost members before re-solving.
## Deaths cluster — a volley of arrows or an area ability takes several units
## out of one group in the same frame or across a handful of frames — and
## re-solving per death would issue a full re-path per casualty for what the
## player reads as a single event. Waiting a beat batches the whole burst into
## one re-solve, and re-arming the timer on each further loss means a group
## being steadily ground down re-forms once when the bleeding stops rather
## than continuously mid-fight.
const REFORM_DEBOUNCE: float = 0.4
## Retry delay when a re-solve is due but the group is mid-chokepoint. Slots
## must not move while units are threading a gap (see Unit.is_funnelling), so
## the re-solve waits for the last member through — Unit's own FUNNEL_TIMEOUT
## guarantees that always eventually happens.
const REFORM_FUNNEL_RETRY: float = 0.3
## Facing an explicit re-form falls back to when the group has no usable
## average heading (see _group_facing).
const REFORM_DEFAULT_FORWARD: Vector3 = Vector3.FORWARD

## Starts tracking a dispatched multi-unit formation move. `group` is the exact
## array instance handed to those units as their cohesion group — it doubles as
## this order's identity token, since a unit later given any other order gets a
## different (or empty) formation_group, which is what _formation_record_members
## uses to tell "still walking this order" from "has moved on". Single-unit and
## non-formation dispatches carry an empty group and are never tracked.
func _register_formation(group: Array[Unit], target_pos: Vector3, formation_type: Formation.Type, attack_move: bool) -> void:
	if not multiplayer.is_server() or group.size() < 2:
		return
	var members := _formation_record_members(group)
	if members.size() < 2:
		return
	## No need to hunt down an older record these units were in: they are
	## carrying this new group array now, so they no longer read as live
	## members of it and the next poll retires it on its own.
	_active_formations.append({
		"group": group,
		"target": target_pos,
		"type": formation_type,
		"attack_move": attack_move,
		"count": members.size(),
		"timer": 0.0,
		"dirty": false,
	})

## The members of `group` still actually walking this order: alive, still on a
## move/attack-move command, and still carrying this exact group array. A unit
## that died, was given a new order, or peeled off into a fight drops out here
## — which is both how ranks-closing notices a loss and how a record eventually
## retires itself.
func _formation_record_members(group: Array[Unit]) -> Array[Unit]:
	var members: Array[Unit] = []
	for unit in group:
		if unit == null or not is_instance_valid(unit) or unit.status_activity == Unit.Activity.DEAD:
			continue
		if unit.status_command != Unit.Command.MOVE and unit.status_command != Unit.Command.ATTACK_MOVE:
			continue
		if not is_same(unit.formation_group, group):
			continue
		members.append(unit)
	return members

## Polled once a frame on the host. Notices a record losing members (the common
## cause being death mid-move, but a unit yanked into a fight or given a fresh
## order counts the same way), waits out REFORM_DEBOUNCE so a burst of losses
## collapses into a single re-solve, then re-solves the shape for whoever is
## left — closing the holes the dead units' slots would otherwise leave.
## Polling membership rather than hooking each individual death is what keeps
## this one batched check no matter how many units die at once, and it also
## covers hand-placed units that never went through the spawner's signal wiring.
func _update_reformation(delta: float) -> void:
	if not multiplayer.is_server() or _active_formations.is_empty():
		return
	for i in range(_active_formations.size() - 1, -1, -1):
		var record: Dictionary = _active_formations[i]
		var group: Array[Unit] = record["group"]
		var members := _formation_record_members(group)
		## Nothing left to hold a shape: everyone arrived, died, or moved on.
		if members.size() < 2:
			_active_formations.remove_at(i)
			continue
		if members.size() < int(record["count"]):
			record["count"] = members.size()
			record["dirty"] = true
			record["timer"] = REFORM_DEBOUNCE
		if not record["dirty"]:
			continue
		record["timer"] = float(record["timer"]) - delta
		if record["timer"] > 0.0:
			continue
		## Never re-solve slots out from under a group that is mid-gap: a
		## funnelled unit is deliberately steered at a shared waypoint with its
		## real slot parked away until it's through, and re-issuing here would
		## send it straight at a far-side slot through whatever it was being
		## funnelled around. Retried, not dropped — the group re-forms as soon
		## as the last member clears the gap.
		if _any_funnelling(members):
			record["timer"] = REFORM_FUNNEL_RETRY
			continue
		record["dirty"] = false
		_reform_group(members, record["target"], record["type"], record["attack_move"])
		## The re-issue hands the survivors a new group array as their cohesion
		## group, so the record has to follow it or every member would read as
		## "moved on" on the very next poll.
		record["group"] = members

func _any_funnelling(units: Array[Unit]) -> bool:
	for unit in units:
		if unit.is_funnelling():
			return true
	return false

## Re-issues a formation move for `units`, re-solved for their current count.
## Goes through command_move/command_attack_move directly rather than
## _dispatch_smart_command: there is no target node to re-resolve (a gather/
## attack/build order never had formation slots to begin with), and this is a
## continuation of an order the player already gave, so it deliberately plays
## no order sound and never touches order_queue — anything shift-queued behind
## this leg still runs when this leg completes. command_move re-baselines
## cohesion for the new leg on its own (Unit._set_formation_cohesion), which is
## exactly what a re-solved slot needs, and clears any stale funnel with it.
func _reform_group(units: Array[Unit], target_pos: Vector3, formation_type: Formation.Type, attack_move: bool, forward_override: Vector3 = Vector3.ZERO) -> void:
	var slots: Array[Vector3] = _formation_positions(units, target_pos, formation_type) if forward_override == Vector3.ZERO \
			else _reform_positions(units, target_pos, formation_type, forward_override)
	var speed := _slowest_move_speed(units)
	for i in units.size():
		if attack_move:
			units[i].command_attack_move(slots[i], speed, units)
		else:
			units[i].command_move(slots[i], speed, units)

## Same slot solve as _formation_positions, but with the group's facing supplied
## rather than derived from (target - centroid): an explicit re-form is centered
## on the group's own centroid, so there is no direction of travel to derive a
## facing from and every re-form would otherwise come out pointing the same
## arbitrary way (see _group_forward's degenerate case).
func _reform_positions(units: Array[Unit], target_pos: Vector3, formation_type: Formation.Type, forward: Vector3) -> Array[Vector3]:
	if units.is_empty():
		return []
	if units.size() == 1:
		return [target_pos]
	var right := Vector3(forward.z, 0.0, -forward.x)
	var formation := Formation.new(units, formation_type)
	return _assign_slots_to_units(units, formation.get_slot_positions(target_pos, forward, right))

## The group's average heading, taken from the direction each unit is actually
## facing (units rotate toward their movement direction, so after a move or a
## fight this is where they were last heading/looking). Averaged as vectors
## rather than angles so opposing headings cancel instead of averaging into a
## meaningless midpoint — a group facing every which way after a brawl falls
## back to the default instead of inheriting one member's spin.
func _group_facing(units: Array[Unit]) -> Vector3:
	var facing := Vector3.ZERO
	for unit in units:
		facing += Vector3(sin(unit.rotation.y), 0.0, cos(unit.rotation.y))
	facing.y = 0.0
	return facing.normalized() if facing.length_squared() > 0.0001 else REFORM_DEFAULT_FORWARD

## Explicit re-form (FORMATION_REFORM_KEY): pulls a selection that combat, an
## obstacle or a chokepoint has smeared into a blob back into its formation
## shape, in place. Client-local only as far as the RPC — same shape as every
## other order here, the host does the solving.
func _issue_reform_order() -> void:
	_prune_selected_units()
	if selected_units.size() < 2:
		return
	var unit_paths: Array[NodePath] = []
	for unit in selected_units:
		unit_paths.append(unit.get_path())
		_clear_path_markers(unit)
	_rpc_issue_reform.rpc_id(1, unit_paths, current_formation_type)
	_play_command_sound()

## Host-side half of the explicit re-form. Centered on the group's own centroid
## and oriented to its own average facing, so the block forms up where it
## already is and pointing where it already points instead of marching off to a
## destination — the player asked for tidier ranks, not a move order. Registered
## as a formation record like any other formation move, so ranks still close if
## someone dies while forming up.
@rpc("any_peer", "call_local", "reliable")
func _rpc_issue_reform(unit_paths: Array[NodePath], formation_type: Formation.Type = Formation.DEFAULT_TYPE) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = _my_peer_id()

	var units: Array[Unit] = []
	for path in unit_paths:
		var unit := get_node_or_null(path) as Unit
		if unit != null and unit.owner_peer_id == sender_id and unit.status_activity != Unit.Activity.DEAD:
			units.append(unit)
	if units.size() < 2:
		return
	## A group still threading a gap is already deliberately in single file;
	## re-forming it mid-gap would fight the funnel, so the request is dropped
	## rather than queued — the player can simply press it again once through.
	if _any_funnelling(units):
		return

	var centroid := _group_centroid(units)
	_reform_group(units, centroid, formation_type, false, _group_facing(units))
	_register_formation(units, centroid, formation_type, false)

## Fires whenever a unit's current command runs its own natural course (a
## move arrives, a fight runs out of enemies, a build finishes) — see
## Unit.order_completed. Only ever emitted host-side, so this only ever runs
## on the host too, same as every other order-dispatch path here.
func _on_unit_order_completed(unit: Unit) -> void:
	if unit.order_queue.is_empty():
		return
	var order: Dictionary = unit.order_queue.pop_front()
	var target_node: Node = get_node_or_null(order["target_path"]) if order["target_path"] != NodePath() else null
	## Dictionary values don't reliably preserve inner-array typing, so the
	## formation group read back out is a plain Array — re-typed here via
	## assign() rather than handing it straight to cohesion_group's typed
	## Array[Unit] parameter.
	var formation_group: Array[Unit] = []
	formation_group.assign(order["formation_group"])
	_dispatch_smart_command(unit, target_node, order["world_pos"], order["attack_move_fallback"], order["speed_override"], formation_group)

## Shared by right-click/attack-order dispatch and a rally point resolving
## onto a resource/enemy/under-construction building: gather/attack/build the
## target if it makes sense for one, otherwise fall back to a plain move (or
## attack-move, when armed). world_pos/speed_override are only used by that
## fallback branch — a gather/attack/build target ignores both, same reasoning
## as the formation slot position itself (see _formation_positions).
func _dispatch_smart_command(unit: Unit, target_node: Node, world_pos: Vector3, attack_move_fallback: bool, speed_override: float = -1.0, cohesion_group: Array[Unit] = []) -> void:
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
		unit.command_attack_move(world_pos, speed_override, cohesion_group)
		_play_unit_order_sound(unit, Unit.OrderSoundKind.ATTACK)
	else:
		unit.command_move(world_pos, speed_override, cohesion_group)
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
			_spawn_command_popup("patrol", result.position)
			_patrol_started_this_session = true
			if not event.shift_pressed:
				pending_order_mode = ""

func _on_stockpile_changed(resource_name: String, amount: int) -> void:
	## First value for a resource (the starting stockpile) snaps — only later
	## changes are worth counting up to.
	if not _resource_display_totals.has(resource_name):
		_resource_display_totals[resource_name] = float(amount)
	_resource_totals[resource_name] = amount
	_update_resource_label()

## Eases each displayed total toward its real value so income reads as a
## counter ticking up rather than numbers popping between frames.
func _update_resource_ticker(delta: float) -> void:
	var changed := false
	for resource_name in _resource_totals:
		var target := float(_resource_totals[resource_name])
		var current: float = _resource_display_totals.get(resource_name, target)
		if is_equal_approx(current, target):
			continue
		var speed: float = maxf(absf(target - current) * RESOURCE_TICK_RATE, RESOURCE_TICK_MIN_SPEED)
		current = move_toward(current, target, speed * delta)
		if absf(target - current) < 0.5:
			current = target
		_resource_display_totals[resource_name] = current
		changed = true
	if changed:
		_update_resource_label()

func _on_population_changed(used: int, cap: int) -> void:
	_population_used = used
	_population_cap = cap
	_update_resource_label()

func _update_resource_label() -> void:
	var parts: Array[String] = []
	for resource_type in DEBUG_RESOURCE_TYPES:
		var shown: int = int(round(_resource_display_totals.get(resource_type.display_name, float(_resource_totals.get(resource_type.display_name, 0)))))
		var text := "%s: %d" % [resource_type.display_name, shown]
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

## Returns the types themselves rather than just their display names so the
## caller can reach each one's insufficient_sound_effects as well as its label.
func _missing_resource_types(costs: Array[ResourceCost]) -> Array[ResourceType]:
	var missing: Array[ResourceType] = []
	for cost in costs:
		if _resource_totals.get(cost.resource_type.display_name, 0) < cost.amount:
			missing.append(cost.resource_type)
	return missing

## Called wherever a purchase is refused locally for lack of funds (building
## placement, producible items). No-ops (no flash) if the costs are actually
## affordable — callers don't need to check _can_afford_locally themselves first.
func _flash_missing_resources(costs: Array[ResourceCost]) -> void:
	var missing := _missing_resource_types(costs)
	if missing.is_empty():
		return

	## Only the first shortfall is sounded even when a purchase is short on
	## two resources at once: command_audio_player is a single stream, so
	## playing both would just cut the first off mid-sample. The bar still
	## flashes every missing resource.
	AudioUtils.play_random(command_audio_player, missing[0].insufficient_sound_effects)

	for resource_type in missing:
		_flashing_resource_names[resource_type.display_name] = true

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

## Whether the local player may actually USE this building, as opposed to
## merely looking at it. An enemy building can be selected and inspected for
## as long as fog of war has it revealed, but never produces, rallies, or
## takes orders — see _select_building and the rally handling.
func _can_command_building(building: ProductionBuilding) -> bool:
	return building != null and building.owner_peer_id == _my_peer_id()

func _select_building(building: ProductionBuilding) -> void:
	selected_building = building
	_update_rally_marker()
	if building == null:
		_refresh_command_panel()
		return
	selected_resource = null

	_show_info_header()
	info_panel_name_label.text = building.building_name
	_update_portrait(building.team_tint, "")
	for child in action_panel_grid.get_children():
		child.queue_free()
	_build_building_info(building)

	if building.is_under_construction:
		if not building.construction_finished.is_connected(_on_selected_building_constructed):
			building.construction_finished.connect(_on_selected_building_constructed.bind(building), CONNECT_ONE_SHOT)
		_fill_action_panel_grid([])
		return

	## Info panel and portrait are filled in above for any owner; the action
	## panel is where "yours to command" starts, so an enemy building simply
	## gets an empty grid instead of its production buttons.
	if not _can_command_building(building):
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
		_show_info_header()
		_populate_unit_command_buttons()
		_build_unit_info()
		_refresh_unit_info_values()
		return

	_populate_construction_buttons()

	if selected_resource != null and is_instance_valid(selected_resource):
		_show_info_header()
		info_panel_name_label.text = selected_resource.display_name
		portrait_frame.visible = false
		portrait_health_label.visible = false
		_info_resource_label = Label.new()
		info_panel_content.add_child(_info_resource_label)
		_refresh_resource_info()
		return

	_clear_info_header()

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
	slot.custom_minimum_size = Vector2(40, 40)
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

## The info panel's frame is part of the bottom bar's stonework, so it stays
## on screen with nothing selected — only its contents come and go.
func _show_info_header() -> void:
	info_panel_name_label.visible = true
	info_panel_divider.visible = true

func _clear_info_header() -> void:
	info_panel_name_label.visible = false
	info_panel_divider.visible = false
	portrait_frame.visible = false
	portrait_health_label.visible = false

func _update_portrait(tint: Color, health_text: String) -> void:
	portrait_frame.visible = true
	portrait_health_label.visible = true
	portrait_rect.color = tint
	portrait_health_label.text = health_text
	_punch_control(portrait_frame)

func _flat_bar_stylebox(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	return box

## TextureProgressBar rather than ProgressBar: it clips texture_progress to
## the current value instead of scaling it, so the fill art stays laid out
## across the bar's full width and is revealed as the value climbs. The
## nine-patch margins keep the art's end caps from smearing when the bar is
## wider than the source image.
func _make_progress_bar_with_overlay() -> TextureProgressBar:
	var bar := TextureProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 20)
	bar.max_value = 1.0
	bar.step = 0.0
	bar.texture_under = BAR_FRAME_TEXTURE
	bar.texture_progress = BAR_FILL_TEXTURE
	bar.fill_mode = TextureProgressBar.FILL_LEFT_TO_RIGHT
	bar.nine_patch_stretch = true
	bar.stretch_margin_left = 10
	bar.stretch_margin_right = 10
	bar.stretch_margin_top = 6
	bar.stretch_margin_bottom = 6
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
	_info_built_commandable = _can_command_building(building)
	_info_built_under_construction = building.is_under_construction

	_info_progress_bar = _make_progress_bar_with_overlay()
	info_panel_content.add_child(_info_progress_bar)

	if building.is_under_construction:
		return

	## What an opponent has queued isn't observable from outside their base,
	## so the queue rows are only built for a building you own. Everything
	## above this (name, portrait, health, construction progress) still fills
	## in for an enemy building.
	if not _can_command_building(building):
		return

	_info_empty_label = Label.new()
	_info_empty_label.text = "Queue: empty"
	info_panel_content.add_child(_info_empty_label)
	_info_slot_row = HBoxContainer.new()
	_info_slot_row.add_theme_constant_override("separation", 6)
	info_panel_content.add_child(_info_slot_row)

func _refresh_building_info() -> void:
	var building := selected_building
	var shown_health: int = int(round(building.health_fraction * building.max_health))
	portrait_health_label.text = "%d / %d" % [shown_health, building.max_health]
	if _info_progress_bar == null 			or _info_built_commandable != _can_command_building(building) 			or _info_built_under_construction != building.is_under_construction:
		_build_building_info(building)

	if building.is_under_construction:
		_info_progress_bar.value = building.construction_progress
		(_info_progress_bar.get_node("Overlay") as Label).text = _format_construction_status(building)
		return

	## _build_building_info stops before creating the queue rows for a
	## building you don't own, so there's nothing further to update here.
	if not _can_command_building(building):
		_info_progress_bar.visible = false
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
			var slot := TextureRect.new()
			slot.custom_minimum_size = Vector2(24, 24)
			slot.texture = QUEUE_SLOT_TEXTURE
			slot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
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
		_update_portrait(unit.team_tint, "")
		_info_stats_label = Label.new()
		_info_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		_info_stats_label.add_theme_font_size_override("font_size", 14)
		info_panel_content.add_child(_info_stats_label)
		return

	info_panel_name_label.text = "%d units selected" % selected_units.size()
	_update_portrait(selected_units[0].team_tint, "%d units" % selected_units.size())
	var portrait_grid := GridContainer.new()
	portrait_grid.columns = SELECTION_PORTRAIT_COLUMNS
	## Shrink-to-fit, or the columns stretch across the panel and the square
	## portrait slots come out as wide rectangles.
	portrait_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	portrait_grid.add_theme_constant_override("h_separation", 5)
	portrait_grid.add_theme_constant_override("v_separation", 5)
	## Two rows' worth is all the info panel has room for; the name label above
	## already reports the true count when the selection runs past that.
	for i in mini(selected_units.size(), SELECTION_PORTRAIT_LIMIT):
		var unit := selected_units[i]
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 3)
		var portrait := Button.new()
		portrait.custom_minimum_size = Vector2(27, 27)
		portrait.tooltip_text = unit.display_name
		portrait.add_theme_stylebox_override("normal", _flat_bar_stylebox(unit.team_tint))
		portrait.add_theme_stylebox_override("hover", _flat_bar_stylebox(unit.team_tint.lightened(0.3)))
		portrait.add_theme_stylebox_override("pressed", _flat_bar_stylebox(unit.team_tint.darkened(0.2)))
		portrait.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		portrait.pressed.connect(_on_unit_portrait_pressed.bind(unit))
		cell.add_child(portrait)
		var health_bar := ProgressBar.new()
		health_bar.custom_minimum_size = Vector2(27, 5)
		health_bar.max_value = 1.0
		health_bar.step = 0.0
		health_bar.show_percentage = false
		health_bar.add_theme_stylebox_override("background", _flat_bar_stylebox(Color(0.08, 0.08, 0.09)))
		health_bar.add_theme_stylebox_override("fill", _flat_bar_stylebox(Color(0.35, 0.75, 0.3)))
		cell.add_child(health_bar)
		portrait_grid.add_child(cell)
		_info_unit_portrait_bars.append(health_bar)
	info_panel_content.add_child(portrait_grid)

## Clicking one portrait in a multi-unit selection narrows the selection down
## to just that unit — _process notices selected_units changed and rebuilds the
## panel into its single-unit form on the next frame.
func _on_unit_portrait_pressed(unit: Unit) -> void:
	if not is_instance_valid(unit):
		return
	for u in selected_units:
		u.selected = false
	selected_units.clear()
	_active_group_number = -1
	unit.selected = true
	selected_units.append(unit)
	unit.play_select_sound()

func _refresh_unit_info_values() -> void:
	if selected_units.size() == 1:
		var unit := selected_units[0]
		portrait_health_label.text = "%d / %d" % [unit.status_current_health, unit.max_health]
		if _info_stats_label:
			_info_stats_label.text = _format_unit_stats(unit)
		return
	for i in _info_unit_portrait_bars.size():
		if i < selected_units.size() and is_instance_valid(selected_units[i]):
			var unit := selected_units[i]
			_info_unit_portrait_bars[i].value = float(unit.status_current_health) / float(maxi(unit.max_health, 1))

## Health already reads out under the portrait, and the info panel is only as
## wide as the console allows — so these stay short enough not to wrap.
func _format_unit_stats(unit: Unit) -> String:
	var lines: Array[String] = []
	if unit.can_fight:
		lines.append("Dmg %d / %.1fs (rng %.1f)" % [unit.attack_damage, unit.attack_cooldown, unit.attack_range])
	if unit.can_gather:
		lines.append("Gather lvl %d (carries %d)" % [unit.gather_level, unit.carry_capacity])
	lines.append("Speed %.1f" % unit.move_speed)
	return "\n".join(lines)

func _populate_unit_command_buttons() -> void:
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
	_spawn_rally_dust(result.position)
	AudioUtils.play_random(command_audio_player, on_rally_set_sound_effects)
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
	if _can_command_building(selected_building) and selected_building.can_rally and selected_building.has_rally_point:
		_ensure_rally_marker()
		rally_marker.visible = true
		rally_marker.global_position = selected_building.rally_point
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
	button.theme_type_variation = &"SquareButton"
	button.custom_minimum_size = Vector2(40, 40)
	button.text = hotkey_label
	button.tooltip_text = tooltip
	button.icon = icon
	button.pressed.connect(callback)
	button.pressed.connect(_punch_control.bind(button))
	return button

## Quick squash-and-settle on a HUD control, so a click or hotkey visibly
## registers on the panel itself rather than only in the world.
func _punch_control(control: Control) -> void:
	if control.size == Vector2.ZERO:
		return
	control.pivot_offset = control.size * 0.5
	control.scale = Vector2.ONE * 0.86
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "scale", Vector2.ONE, 0.18)

## Hotkeys drive the same actions as the command-card buttons but never touch
## them, which left the panel looking inert during keyboard play. Buttons are
## labelled with their own hotkey, so that label is the lookup key.
func _pulse_action_button(hotkey_label: String) -> void:
	for child in action_panel_grid.get_children():
		var button := child as Button
		if button and button.text == hotkey_label:
			_punch_control(button)
			return

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
	if building_type.is_wall or building_type.is_gate_tool:
		## Both use their own snap/rebuild logic each frame instead of a
		## single mouse-following ghost — see _update_wall_drag/_update_gate_ghost.
		return
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
			## Grass (grass_wind_material.tres) alpha-blends at render_priority 0
			## too, and a MultiMeshInstance3D sorts as one draw call against this
			## ghost's distance rather than per-blade — so without outranking it
			## here, whichever one's centroid happens to read as "farther" can
			## draw last and blot out the other. Bumping priority above 0 always
			## wins the tie, regardless of distance.
			ghost_material.render_priority = 1
			mesh_instance.set_surface_override_material(i, ghost_material)
			_ghost_surfaces.append({"material": ghost_material, "base_color": base_color})
	for child in node.get_children():
		_collect_ghost_surfaces(child)

func _set_ghost_valid(valid: bool) -> void:
	var tint: Color = VALID_GHOST_COLOR if valid else INVALID_GHOST_COLOR
	for entry in _ghost_surfaces:
		var material: StandardMaterial3D = entry["material"]
		var base_color: Color = entry["base_color"]
		## Multiplying straight through (base * tint) crushes to near-black on
		## a dark-shaded source model (e.g. base_basic_shaded.glb), making
		## valid/invalid unreadable — blending toward the tint instead keeps
		## some of the original hue while still guaranteeing the red/green
		## signal reads clearly regardless of how dark the source material is.
		var blended: Color = base_color.lerp(tint, 0.75)
		material.albedo_color = Color(blended.r, blended.g, blended.b, tint.a)

func _update_placement_ghost() -> void:
	if placing_type.requires_deposit:
		_update_deposit_snap_ghost()
		return

	var mouse_pos := get_viewport().get_mouse_position()
	var result := _raycast(mouse_pos)
	if result.is_empty():
		placement_ghost.visible = false
		placement_valid = false
		return
	placement_ghost.visible = true
	placement_ghost.global_position = result.position

	## _is_placement_valid's overlap check alone only ever compared against
	## other buildings/resources, never terrain, so a ghost could sit embedded
	## in a slope/cliff (e.g. TileMapLayer3D terrain) and still read as valid.
	var on_flat_ground: bool = _footprint_is_flat(result.position, placing_type.footprint_radius)
	placement_valid = on_flat_ground \
			and _is_placement_valid(result.position, placing_type.footprint_radius) \
			and _has_nearby_host(result.position, placing_type, _my_peer_id())
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

func _matches_any_scene(node: Node, scenes: Array[PackedScene]) -> bool:
	for scene in scenes:
		if _matches_scene(node, scene):
			return true
	return false

## The Farm/Mill rule: a building_type with requires_nearby_host may only go
## down within host_radius of a finished, same-owner instance of its
## host_scene. Every other building type passes straight through. Checked on
## both sides — locally for the ghost's red/green, and again host-side in
## _rpc_request_build so a client can't place a Farm out in open country.
func _has_nearby_host(pos: Vector3, building_type: BuildingType, peer_id: int) -> bool:
	if not building_type.requires_nearby_host:
		return true
	for node in get_tree().get_nodes_in_group("buildings"):
		var building := node as ProductionBuilding
		if building == null or building.owner_peer_id != peer_id or building.is_under_construction:
			continue
		if not _matches_scene(building, building_type.host_scene):
			continue
		if building.global_position.distance_to(pos) <= building_type.host_radius:
			return true
	return false

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
	if placing_type.is_wall:
		_handle_wall_drag_input(event)
		return
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
	if placing_type.is_gate_tool:
		_confirm_gate_placement()
		return
	## Staying armed (rather than dropping the ghost) is deliberate: a click
	## on unbuildable ground is nearly always a misjudged spot, not a change
	## of mind, so the tool stays live and the player just clicks again. Same
	## reasoning as the can't-afford branch below.
	if not placement_valid:
		_play_placement_blocked_sound()
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
	var build_position := placement_ghost.global_position
	_rpc_request_build.rpc_id(1, type_index, build_position, target_path, _pending_builder_paths, shift_held)
	AudioUtils.play_random(command_audio_player, on_building_placed_sound_effects)
	_spawn_command_popup("build", build_position)

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
			or not _is_placement_valid(world_pos, building_type.footprint_radius) \
			or not _has_nearby_host(world_pos, building_type, sender_id):
		return

	ResourceStockpile.spend(sender_id, costs)
	if deposit:
		deposit.is_claimed = true

	var spawn_data: Dictionary = {
		"scene_path": building_type.scene.resource_path,
		"peer_id": sender_id,
		"position": build_pos,
		"tint": get_team_tint(sender_id),
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

		_dispatch_builders_to(building, builder_paths, sender_id, append)

## Sends whichever villager(s) opened the build menu to go build what they
## just placed, instead of leaving them standing idle next to it. Shared by
## the normal/wall/gate build RPCs. Shift-chained placements queue this after
## the builder's current order instead — see _confirm_placement/
## _on_unit_order_completed. Same "only actually queue if there's something to
## finish first" logic as _rpc_issue_command — an idle builder with nothing in
## flight would never have anything trigger order_completed to dispatch a
## queued order.
func _dispatch_builders_to(building: ProductionBuilding, builder_paths: Array[NodePath], sender_id: int, append: bool) -> void:
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
	_cancel_wall_drag()
	_gate_target = null

## --- Wall drag placement ---
## Click-drag a run of wall segments (Age of Empires IV-style): the path
## follows the actual cursor movement rather than snapping to a straight
## line, sampled every wall_segment_length along the way; a corner piece is
## auto-inserted wherever the path bends past WALL_CORNER_ANGLE_THRESHOLD.
## _wall_compute_pieces() is the single source of truth for what a drag would
## build — both the live ghost and the final RPC call it fresh off the same
## _wall_drag_points, so what's previewed is always exactly what gets built
## (no silent per-piece drop on confirm, unlike AoE4's own wall tool).

func _handle_wall_drag_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_wall_drag()
		elif _wall_dragging:
			_confirm_wall_placement()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_cancel_placement()
		_pending_builder_paths.clear()
		_build_queue_active = false
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_cancel_placement()
		_pending_builder_paths.clear()
		_build_queue_active = false

func _begin_wall_drag() -> void:
	var mouse_pos := get_viewport().get_mouse_position()
	var result := _raycast(mouse_pos)
	if result.is_empty():
		return
	_wall_dragging = true
	_wall_drag_points = [result.position]
	_rebuild_wall_ghost()

func _update_wall_drag() -> void:
	if not _wall_dragging:
		return
	var mouse_pos := get_viewport().get_mouse_position()
	var result := _raycast(mouse_pos)
	if result.is_empty():
		return
	## Backtracking over already-placed pieces takes priority over extending
	## forward — a player correcting a mistake by dragging back over the wall
	## should retract it, not simultaneously grow a new branch from wherever
	## the cursor happens to be.
	if _wall_try_backtrack(result.position):
		_rebuild_wall_ghost()
		return
	if _wall_extend_path_to(result.position):
		_rebuild_wall_ghost()

## How close the cursor needs to get to an already-placed piece (measured to
## the segment itself, not just its endpoints) to count as "hovering back
## over it" and retract the path there. Generous enough to be easy to land
## on, tight enough not to trigger from a normal straight forward drag.
const WALL_UNDO_THRESHOLD: float = WALL_SEGMENT_FOOTPRINT_RADIUS + 0.3

## Retracts _wall_drag_points back to just past the piece the cursor is now
## hovering, so moving the mouse back over a mistake undoes it (and every
## piece placed after it) in real time instead of requiring a full restart.
## Never considers the live frontier segment (the one currently being drawn
## toward the cursor) a backtrack target, and only fires when the cursor sits
## closer to that old piece than to the current end of the drag — otherwise a
## plain straight drag would trip it constantly, since the cursor is always
## incidentally near the extended line of earlier segments too.
func _wall_try_backtrack(target: Vector3) -> bool:
	if _wall_drag_points.size() < 3:
		return false
	var flat_target := Vector3(target.x, 0.0, target.z)
	var best_i := -1
	var best_dist := INF
	for i in _wall_drag_points.size() - 2:
		var flat_a := _wall_drag_points[i]
		flat_a.y = 0.0
		var flat_b := _wall_drag_points[i + 1]
		flat_b.y = 0.0
		var dist := _distance_point_to_segment(flat_target, flat_a, flat_b)
		if dist < best_dist:
			best_dist = dist
			best_i = i
	if best_i == -1 or best_dist > WALL_UNDO_THRESHOLD:
		return false
	## Compared against the frontier SEGMENT (not just its far endpoint) —
	## comparing to the endpoint alone would make the cursor read as "closer
	## to the old piece" for the whole near half of the segment currently
	## being drawn, retracting it during perfectly ordinary forward dragging.
	var frontier_a: Vector3 = _wall_drag_points[-2]
	frontier_a.y = 0.0
	var frontier_b: Vector3 = _wall_drag_points[-1]
	frontier_b.y = 0.0
	var frontier_dist := _distance_point_to_segment(flat_target, frontier_a, frontier_b)
	if frontier_dist <= best_dist:
		return false
	_wall_drag_points = _wall_drag_points.slice(0, best_i + 1)
	return true

func _distance_point_to_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 0.0001:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)

## Walks from the last committed point toward target in fixed
## wall_segment_length steps (re-sampling ground height at each new point),
## rather than just drawing one straight line from drag-start to the current
## mouse position — that's what lets the wall follow a curved drag instead of
## always being a single straight chord. Returns whether any point was added.
func _wall_extend_path_to(target: Vector3) -> bool:
	if _wall_drag_points.is_empty() or _wall_drag_points.size() > WALL_MAX_SEGMENTS:
		return false
	var seg_len: float = placing_type.wall_segment_length
	var added := false
	var last: Vector3 = _wall_drag_points[-1]
	var to_target := target - last
	to_target.y = 0.0
	while to_target.length() >= seg_len and _wall_drag_points.size() <= WALL_MAX_SEGMENTS:
		var dir := to_target.normalized()
		var next_point := last + dir * seg_len
		## A straight step that would clip a tree/resource gets bent sideways
		## just enough to clear it instead of just landing on an invalid,
		## red-tinted piece — see _wall_find_blocking_obstacle/_wall_deflect_around.
		var obstacle := _wall_find_blocking_obstacle(last, next_point)
		if obstacle != null:
			next_point = _wall_deflect_around(last, next_point, dir, obstacle)
		next_point.y = _sample_ground_y(next_point, next_point.y)
		_wall_drag_points.append(next_point)
		last = next_point
		to_target = target - last
		to_target.y = 0.0
		added = true
	return added

## Shape-queries the corridor a straight step from a to b would sweep through
## (segment-length long, wall-width wide) and returns the nearest Gatherable
## overlapping it, or null if the step is clear.
func _wall_find_blocking_obstacle(a: Vector3, b: Vector3) -> Gatherable:
	var dir := b - a
	dir.y = 0.0
	if dir.length() < 0.001:
		return null
	dir = dir.normalized()
	var mid := (a + b) * 0.5
	var shape := BoxShape3D.new()
	shape.size = Vector3(a.distance_to(b), 2.0, WALL_SEGMENT_FOOTPRINT_RADIUS * 2.0 + 1.0)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(dir, Vector3.UP, dir.cross(Vector3.UP)), mid)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var closest: Gatherable = null
	var closest_dist := INF
	var space_state := get_world_3d().direct_space_state
	for result in space_state.intersect_shape(query, 8):
		if result.collider is Gatherable:
			var dist: float = mid.distance_to(result.collider.global_position)
			if dist < closest_dist:
				closest_dist = dist
				closest = result.collider
	return closest

## How far a resource node's own footprint extends, read off its
## NavigationObstacle3D the same way ProductionBuilding.get_footprint_radius()
## does — falls back to a generic clearance if a given Gatherable has none.
func _obstacle_radius(node: Node3D) -> float:
	var obstacle := node.get_node_or_null("NavigationObstacle3D") as NavigationObstacle3D
	return obstacle.radius if obstacle else 1.2

## Pushes next_point sideways, away from whichever side of the a->next_point
## line the obstacle sits on, by enough to clear its footprint plus the
## wall's own, then re-projects back onto the segment_length-from-`a` circle
## so the piece a player actually sees rejected/accepted is the one this
## directly targets. Not a real pathfinder — a long straight drag through a
## cluster of trees can still take a couple of separately-deflected pieces to
## fully clear (each step only reacts to what's directly in front of it) —
## but every individual step it produces is provably clear of what it was
## deflected for, unlike a pivot-around-`a` approach (which under-corrects
## for any obstacle not near the far end of the step: rotating a line around
## a fixed point can't move a point close to that pivot very far no matter
## how hard you rotate, so it would often still leave the piece invalid).
func _wall_deflect_around(a: Vector3, next_point: Vector3, dir: Vector3, obstacle: Gatherable) -> Vector3:
	var perp := dir.cross(Vector3.UP).normalized()
	var mid := (a + next_point) * 0.5
	var to_obstacle := obstacle.global_position - mid
	to_obstacle.y = 0.0
	var lateral: float = perp.dot(to_obstacle)
	var clearance: float = _obstacle_radius(obstacle) + WALL_SEGMENT_FOOTPRINT_RADIUS + 0.4
	var needed: float = clearance - absf(lateral)
	if needed <= 0.0:
		return next_point
	var side := signf(lateral) if lateral != 0.0 else 1.0
	## Only next_point moves (a is already committed), so the midpoint only
	## moves by half of whatever next_point shifts by — shifting next_point by
	## 2x what the midpoint needs is what actually gets the midpoint clear.
	return next_point - perp * side * (needed * 2.0)

func _sample_ground_y(pos: Vector3, fallback_y: float) -> float:
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(pos + Vector3(0.0, 5.0, 0.0), pos - Vector3(0.0, 5.0, 0.0))
	var result := space_state.intersect_ray(query)
	return result.position.y if not result.is_empty() else fallback_y

## Turns _wall_drag_points into the actual list of pieces a confirm would
## build: one "segment" per consecutive pair of points, plus a "corner" at
## any interior point where the path bends more than WALL_CORNER_ANGLE_THRESHOLD.
## Deterministic and side-effect-free (only reads _wall_drag_points/placing_type
## and runs placement-validity queries) so the ghost and the confirm RPC can
## both call it and always agree.
func _wall_compute_pieces() -> Array[Dictionary]:
	var pieces: Array[Dictionary] = []
	var pts := _wall_drag_points
	## Segment midpoints placed so far, checked below against every new
	## segment — legitimate end-to-end neighbors sit wall_segment_length apart
	## (comfortably more than twice the footprint radius), so this only ever
	## trips when the drag genuinely doubles back over ground it already
	## covered (a hairpin or a literal backtrack), which _is_placement_valid
	## alone can't catch since stripped ghosts carry no collision shape.
	var segment_positions: Array[Vector3] = []
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var dir := b - a
		dir.y = 0.0
		if dir.length() < 0.001:
			continue
		dir = dir.normalized()
		var mid := (a + b) * 0.5
		var valid: bool = _footprint_is_flat(mid, WALL_SEGMENT_FOOTPRINT_RADIUS) \
				and _is_placement_valid(mid, WALL_SEGMENT_FOOTPRINT_RADIUS) \
				and not _wall_overlaps_own_run(segment_positions, mid, WALL_SEGMENT_FOOTPRINT_RADIUS)
		segment_positions.append(mid)
		pieces.append({"kind": "segment", "position": mid, "direction": dir, "valid": valid})

		if i > 0 and placing_type.wall_corner_scene:
			var prev_dir: Vector3 = pts[i] - pts[i - 1]
			prev_dir.y = 0.0
			if prev_dir.length() > 0.001:
				prev_dir = prev_dir.normalized()
				if prev_dir.angle_to(dir) > WALL_CORNER_ANGLE_THRESHOLD:
					var bisector := prev_dir + dir
					bisector = bisector.normalized() if bisector.length() > 0.001 else dir
					var corner_valid: bool = _footprint_is_flat(pts[i], WALL_CORNER_FOOTPRINT_RADIUS) \
							and _is_placement_valid(pts[i], WALL_CORNER_FOOTPRINT_RADIUS)
					pieces.append({"kind": "corner", "position": pts[i], "direction": bisector, "valid": corner_valid})
	return pieces

func _wall_overlaps_own_run(existing_midpoints: Array[Vector3], mid: Vector3, radius: float) -> bool:
	for other in existing_midpoints:
		if other.distance_to(mid) < radius * 2.0:
			return true
	return false

func _wall_all_pieces_valid(pieces: Array[Dictionary]) -> bool:
	for piece in pieces:
		if not piece["valid"]:
			return false
	return true

## Sums per-piece costs into one merged ResourceCost per resource type —
## ResourceStockpile.can_afford()/spend() check each array entry independently
## against the live balance, so N separate "8 wood" entries would each pass
## the same affordability check without ever accounting for each other.
func _wall_total_cost(pieces: Array[Dictionary]) -> Array[ResourceCost]:
	var totals: Dictionary = {}
	for piece in pieces:
		var unit_costs: Array[ResourceCost] = placing_type.get_costs() if piece["kind"] == "segment" else placing_type.get_corner_costs()
		for cost in unit_costs:
			totals[cost.resource_type] = totals.get(cost.resource_type, 0) + cost.amount
	return _totals_to_costs(totals)

func _totals_to_costs(totals: Dictionary) -> Array[ResourceCost]:
	var result: Array[ResourceCost] = []
	for resource_type in totals:
		var cost := ResourceCost.new()
		cost.resource_type = resource_type
		cost.amount = totals[resource_type]
		result.append(cost)
	return result

func _rebuild_wall_ghost() -> void:
	for ghost in _wall_ghosts:
		if is_instance_valid(ghost):
			ghost.queue_free()
	_wall_ghosts.clear()
	var pieces := _wall_compute_pieces()
	for piece in pieces:
		var scene: PackedScene = placing_type.scene if piece["kind"] == "segment" else placing_type.wall_corner_scene
		if scene == null:
			continue
		_wall_ghosts.append(_build_wall_piece_ghost(scene, piece["position"], piece["direction"], piece["valid"]))
	_update_wall_drag_label(pieces)

## Segment/corner counts and a live running total, refreshed every time the
## drag grows — this is the gap AoE4 itself leaves (you only learn the true
## cost after releasing the drag); showing it live is a deliberate improvement.
func _update_wall_drag_label(pieces: Array[Dictionary]) -> void:
	if pieces.is_empty():
		_wall_drag_label.visible = false
		return
	var segment_count := 0
	var corner_count := 0
	for piece in pieces:
		if piece["kind"] == "segment":
			segment_count += 1
		else:
			corner_count += 1
	var cost_text := _format_costs(_wall_total_cost(pieces))
	var piece_text := "%d wall%s" % [segment_count, "" if segment_count == 1 else "s"]
	if corner_count > 0:
		piece_text += " + %d corner%s" % [corner_count, "" if corner_count == 1 else "s"]
	_wall_drag_label.text = "%s — %s" % [piece_text, cost_text]
	_wall_drag_label.modulate = Color.WHITE if _wall_all_pieces_valid(pieces) else Color(1.0, 0.55, 0.5)
	_wall_drag_label.visible = true

func _build_wall_piece_ghost(scene: PackedScene, pos: Vector3, dir: Vector3, valid: bool) -> Node3D:
	var ghost: Node3D = scene.instantiate()
	ghost.set_script(null)
	_strip_ghost_children(ghost)
	var surfaces: Array = []
	_collect_ghost_surfaces_into(ghost, surfaces)
	ghost.set_meta(&"ghost_surfaces", surfaces)
	add_child(ghost)
	ghost.global_position = pos
	ghost.global_basis = Basis(dir, Vector3.UP, dir.cross(Vector3.UP))
	_tint_wall_ghost(ghost, valid)
	return ghost

## Same per-surface translucent-material approach as _collect_ghost_surfaces(),
## but writing into a caller-supplied array instead of the single shared
## _ghost_surfaces list — a wall drag has many ghosts on screen at once, each
## needing its own independent valid/invalid tint, unlike every other
## placement type's single ghost.
func _collect_ghost_surfaces_into(node: Node, out: Array) -> void:
	if node is MeshInstance3D:
		var mesh_instance: MeshInstance3D = node
		var surface_count: int = mesh_instance.mesh.get_surface_count() if mesh_instance.mesh else 0
		for i in surface_count:
			var base: Material = mesh_instance.get_active_material(i)
			var base_color: Color = base.albedo_color if base is StandardMaterial3D else Color.WHITE
			var ghost_material := StandardMaterial3D.new()
			ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			ghost_material.render_priority = 1
			mesh_instance.set_surface_override_material(i, ghost_material)
			out.append({"material": ghost_material, "base_color": base_color})
	for child in node.get_children():
		_collect_ghost_surfaces_into(child, out)

func _tint_wall_ghost(ghost: Node3D, valid: bool) -> void:
	var tint: Color = VALID_GHOST_COLOR if valid else INVALID_GHOST_COLOR
	for entry in ghost.get_meta(&"ghost_surfaces", []):
		var material: StandardMaterial3D = entry["material"]
		var base_color: Color = entry["base_color"]
		var blended: Color = base_color.lerp(tint, 0.75)
		material.albedo_color = Color(blended.r, blended.g, blended.b, tint.a)

func _confirm_wall_placement() -> void:
	_wall_dragging = false
	var pieces := _wall_compute_pieces()
	if pieces.is_empty() or not _wall_all_pieces_valid(pieces):
		_play_placement_blocked_sound()
		_cancel_wall_drag()
		return
	var costs := _wall_total_cost(pieces)
	if not _can_afford_locally(costs):
		_flash_missing_resources(costs)
		return

	var my_building_types: Array[BuildingType] = _my_faction().building_types
	var type_index: int = my_building_types.find(placing_type)
	var positions: Array[Vector3] = []
	var directions: Array[Vector3] = []
	var kinds: Array[String] = []
	for piece in pieces:
		positions.append(piece["position"])
		directions.append(piece["direction"])
		kinds.append(piece["kind"])
	_rpc_request_build_wall.rpc_id(1, type_index, positions, directions, kinds, _pending_builder_paths)
	AudioUtils.play_random(command_audio_player, on_building_placed_sound_effects)
	## Last piece rather than the first: that is where the drag ended, so it is
	## where the player is actually looking when the line pops.
	_spawn_command_popup("build", positions[positions.size() - 1])

	for path in _pending_builder_paths:
		var builder := get_node_or_null(path) as Unit
		if builder:
			_clear_path_markers(builder)
	_cancel_wall_drag()
	_pending_builder_paths.clear()
	_build_queue_active = false
	if _showing_build_submenu:
		_close_build_submenu()

func _cancel_wall_drag() -> void:
	_wall_dragging = false
	_wall_drag_points.clear()
	for ghost in _wall_ghosts:
		if is_instance_valid(ghost):
			ghost.queue_free()
	_wall_ghosts.clear()
	if _wall_drag_label:
		_wall_drag_label.visible = false

@rpc("any_peer", "call_local", "reliable")
func _rpc_request_build_wall(type_index: int, positions: Array[Vector3], directions: Array[Vector3], kinds: Array[String], builder_paths: Array[NodePath]) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = _my_peer_id()
	if not faction_by_peer.has(sender_id):
		return
	var sender_building_types: Array[BuildingType] = faction_by_peer[sender_id].building_types
	if type_index < 0 or type_index >= sender_building_types.size():
		return
	var building_type: BuildingType = sender_building_types[type_index]
	if not building_type.is_wall:
		return
	var count: int = positions.size()
	if count == 0 or count != directions.size() or count != kinds.size() or count > WALL_MAX_SEGMENTS * 2:
		return

	## Re-validated piece-by-piece against the host's own world state rather
	## than trusting the client's ghost — the drag may be stale (something
	## else got built in that spot meanwhile) or the client tampered with it.
	## Any single invalid piece rejects the whole run instead of silently
	## building the rest, so what the player saw as "valid" is exactly what
	## either does or doesn't appear.
	var totals: Dictionary = {}
	var sanitized_dirs: Array[Vector3] = []
	var segment_positions: Array[Vector3] = []
	for i in count:
		var kind: String = kinds[i]
		if kind != "segment" and kind != "corner":
			return
		if kind == "corner" and building_type.wall_corner_scene == null:
			return
		var radius: float = WALL_SEGMENT_FOOTPRINT_RADIUS if kind == "segment" else WALL_CORNER_FOOTPRINT_RADIUS
		if not _footprint_is_flat(positions[i], radius) or not _is_placement_valid(positions[i], radius):
			return
		## A client's ghost only ever sends a normalized, horizontal direction
		## (see _wall_compute_pieces) — never trust that blindly, since this
		## gets written straight into a replicated Basis/rotation below and a
		## degenerate or non-horizontal vector there can produce NaN that
		## propagates to every peer.
		var dir: Vector3 = directions[i]
		dir.y = 0.0
		if dir.length() < 0.01:
			return
		dir = dir.normalized()
		sanitized_dirs.append(dir)
		if kind == "segment":
			if _wall_overlaps_own_run(segment_positions, positions[i], WALL_SEGMENT_FOOTPRINT_RADIUS):
				return
			segment_positions.append(positions[i])
		var unit_costs: Array[ResourceCost] = building_type.get_costs() if kind == "segment" else building_type.get_corner_costs()
		for cost in unit_costs:
			totals[cost.resource_type] = totals.get(cost.resource_type, 0) + cost.amount

	var merged_costs := _totals_to_costs(totals)
	if not ResourceStockpile.can_afford(sender_id, merged_costs):
		return
	ResourceStockpile.spend(sender_id, merged_costs)

	var spawned_buildings: Array[ProductionBuilding] = []
	for i in count:
		var kind: String = kinds[i]
		var scene: PackedScene = building_type.scene if kind == "segment" else building_type.wall_corner_scene
		var duration: float = building_type.construction_time if kind == "segment" else building_type.construction_time * 0.5
		var dir: Vector3 = sanitized_dirs[i]
		var rot_basis := Basis(dir, Vector3.UP, dir.cross(Vector3.UP))
		var spawn_data: Dictionary = {
			"scene_path": scene.resource_path,
			"peer_id": sender_id,
			"position": positions[i],
			"rotation": rot_basis.get_euler(),
			"tint": get_team_tint(sender_id),
		}
		var spawned: Node = building_spawner.spawn(spawn_data)
		if spawned is ProductionBuilding:
			var building: ProductionBuilding = spawned
			building.begin_construction(duration)
			spawned_buildings.append(building)

	_dispatch_builders_across(spawned_buildings, builder_paths, sender_id)

## Distributes wall pieces round-robin across however many builders were
## selected, so a long drag with e.g. 3 villagers queued has each of them
## start on a different segment and then work down their own third of the
## run, instead of all piling onto the first piece one at a time.
func _dispatch_builders_across(buildings: Array[ProductionBuilding], builder_paths: Array[NodePath], sender_id: int) -> void:
	var builders: Array[Unit] = []
	for path in builder_paths:
		var builder := get_node_or_null(path) as Unit
		if builder and builder.owner_peer_id == sender_id:
			builders.append(builder)
	if builders.is_empty() or buildings.is_empty():
		return
	for i in buildings.size():
		var builder: Unit = builders[i % builders.size()]
		var building: ProductionBuilding = buildings[i]
		if i < builders.size():
			builder.clear_order_queue()
			builder.command_build(building)
		else:
			builder.queue_order(building.get_path(), building.global_position, false)

## --- Gate tool ---
## A second construction-menu entry (is_gate_tool) rather than a drag
## modifier: click an already-placed (fully built) wall segment/corner
## matching gate_target_scenes to swap it for wall_gate_scene. Reuses the single-ghost
## machinery (placement_ghost/_ghost_surfaces/_set_ghost_valid) since, unlike
## the wall drag, this only ever shows one ghost at a time.

func _update_gate_ghost() -> void:
	var mouse_pos := get_viewport().get_mouse_position()
	var result := _raycast(mouse_pos)
	_gate_target = _find_valid_gate_target(result.get("collider"))

	if _gate_target == null:
		if placement_ghost:
			placement_ghost.visible = false
		placement_valid = false
		return

	if placement_ghost == null:
		placement_ghost = _build_ghost(placing_type.scene)
		add_child(placement_ghost)
	placement_ghost.visible = true
	placement_ghost.global_transform = _gate_target.global_transform
	placement_valid = true
	_set_ghost_valid(true)

## Only a fully-built segment can become a gate — a segment still under
## construction has (possibly several) builders actively referencing it as
## their build_target, and there's no clean way to hand that work off to a
## brand new node mid-build, so it's simplest and safest to just require the
## wall to finish first, same as AoE4's normal (non-blueprint-conversion) flow.
func _find_valid_gate_target(collider: Object) -> ProductionBuilding:
	if collider == null or not (collider is ProductionBuilding):
		return null
	var target: ProductionBuilding = collider
	if target.is_destroyed or target.is_under_construction or target.owner_peer_id != _my_peer_id():
		return null
	if not _matches_any_scene(target, placing_type.gate_target_scenes):
		return null
	return target

func _confirm_gate_placement() -> void:
	if _gate_target == null or not is_instance_valid(_gate_target):
		_play_placement_blocked_sound()
		return
	if not _can_afford_locally(placing_type.get_costs()):
		_flash_missing_resources(placing_type.get_costs())
		return

	var my_building_types: Array[BuildingType] = _my_faction().building_types
	var type_index: int = my_building_types.find(placing_type)
	var target_path := _gate_target.get_path()
	var gate_position := _gate_target.global_position
	_rpc_request_build_gate.rpc_id(1, type_index, target_path, _pending_builder_paths)
	AudioUtils.play_random(command_audio_player, on_building_placed_sound_effects)
	_spawn_command_popup("build", gate_position)

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
func _rpc_request_build_gate(type_index: int, target_path: NodePath, builder_paths: Array[NodePath]) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = _my_peer_id()
	if not faction_by_peer.has(sender_id):
		return
	var sender_building_types: Array[BuildingType] = faction_by_peer[sender_id].building_types
	if type_index < 0 or type_index >= sender_building_types.size():
		return
	var building_type: BuildingType = sender_building_types[type_index]
	if not building_type.is_gate_tool:
		return
	var target := get_node_or_null(target_path) as ProductionBuilding
	if target == null or target.is_destroyed or target.is_under_construction or target.owner_peer_id != sender_id:
		return
	if not _matches_any_scene(target, building_type.gate_target_scenes):
		return
	var costs := building_type.get_costs()
	if not ResourceStockpile.can_afford(sender_id, costs):
		return
	ResourceStockpile.spend(sender_id, costs)

	var replace_pos: Vector3 = target.global_position
	var replace_rot: Vector3 = target.rotation
	target.queue_free()

	var spawn_data: Dictionary = {
		"scene_path": building_type.scene.resource_path,
		"peer_id": sender_id,
		"position": replace_pos,
		"rotation": replace_rot,
		"tint": get_team_tint(sender_id),
	}
	var spawned: Node = building_spawner.spawn(spawn_data)
	if spawned is ProductionBuilding:
		var building: ProductionBuilding = spawned
		building.begin_construction(building_type.construction_time)
		_dispatch_builders_to(building, builder_paths, sender_id, false)

## --- Chat / debug console ---
## Type a normal message to broadcast it to everyone, or "cmd ..." for a
## debug command (currently: "cmd add <resource> <amount>" grants yourself
## that resource without playing, e.g. "cmd add wood 10").

func _open_chat_input() -> void:
	chat_input.visible = true
	chat_input.text = ""
	chat_input.grab_focus()
	## Bump the token so any pending auto-hide timer skips its hide while
	## the log needs to stay up for typing.
	_chat_hide_token += 1
	if _chat_log_tween:
		_chat_log_tween.kill()
	chat_log.visible = true
	chat_log.modulate.a = 1.0

func _close_chat_input() -> void:
	chat_input.visible = false
	chat_input.text = ""
	chat_input.release_focus()
	_show_chat_log()

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
	_show_chat_log()

## Shows the chat log and (re)starts its auto-hide countdown; a stale timer
## from an earlier call is ignored via the token check.
func _show_chat_log() -> void:
	if _chat_log_tween:
		_chat_log_tween.kill()
	chat_log.visible = true
	chat_log.modulate.a = 1.0
	_chat_hide_token += 1
	var token := _chat_hide_token
	var timer := get_tree().create_timer(CHAT_LOG_VISIBLE_DURATION)
	timer.timeout.connect(func() -> void:
		if token == _chat_hide_token and not chat_input.visible:
			_chat_log_tween = create_tween()
			_chat_log_tween.tween_property(chat_log, "modulate:a", 0.0, CHAT_LOG_FADE_DURATION)
	)

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
	_show_chat_log()

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
