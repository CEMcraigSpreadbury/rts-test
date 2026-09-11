class_name Main
extends Node3D

## The match scene's root. Owns the shared match state — selection, control
## groups, factions, win condition — plus input, spawning and the order RPCs.
## Everything else lives in child components created in _add_components():
##   GroupMovement     — formation slots, chokepoint funnelling, reformation
##   WorldFeedback     — popups, projectiles, bursts, alerts, hover/rally visuals
##   Hud               — resource bar, info panel, action panel
##   BuildingPlacement — placement ghosts, wall drag, gate tool, build RPCs
##   ChatConsole       — chat, debug commands, minimap pings

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
## automatic; see update_reformation). F4 continues the F1-F3 shape row.
const FORMATION_REFORM_KEY: Key = KEY_F4
## Assigned by position in Unit.get_abilities(), same convention as
## PRODUCIBLE_HOTKEYS/BUILDING_HOTKEYS below — a passive ability still claims
## a slot (shown disabled) so hotkeys stay stable regardless of ability order.
const ABILITY_HOTKEYS: Array[Key] = [KEY_R, KEY_T, KEY_Y, KEY_U]
const PRODUCIBLE_HOTKEYS: Array[Key] = [KEY_I, KEY_J, KEY_K, KEY_L]
const BUILDING_HOTKEYS: Array[Key] = [KEY_Z, KEY_X, KEY_C, KEY_V, KEY_B, KEY_N, KEY_G, KEY_O]
## Same list (and order) as lobby.tscn's Lobby.available_factions — that
## shared order is what a "faction_index" in Network.players refers to.
@export var available_factions: Array[Faction] = []

@onready var camera: Camera3D = $CameraRig/Yaw/Pitch/Camera3D
@onready var camera_rig: Node3D = $CameraRig
@onready var selection_box: ColorRect = $UI/SelectionBox
## Shows the current selection's move-order formation shape — see
## current_formation_type/_set_formation_type. Purely a display; the actual
## shape logic lives host-side in Formation/formation_positions.
@onready var formation_label: Label = $UI/FormationLabel
@onready var fog_of_war: FogOfWar = $FogOfWar
@onready var units_root: Node3D = $Units
@onready var unit_spawner: MultiplayerSpawner = $UnitSpawner
@onready var buildings_root: Node3D = $Buildings
@onready var building_spawner: MultiplayerSpawner = $BuildingSpawner
@onready var player_spawn_points: Node3D = $PlayerSpawnPoints

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
## Conquest alerts, all played locally by ConquestHud off the synced objective
## state. Defaults are placeholders — swap real clips in on map_base.tscn.
@export var on_point_captured_sound_effects: Array[AudioStream] = [preload("res://assets/sfx/Construction/Building_Complete_2.wav")]
@export var on_point_lost_sound_effects: Array[AudioStream] = [preload("res://assets/sfx/UI SFX/07_decline_1.wav")]
@export var on_point_under_attack_sound_effects: Array[AudioStream] = [preload("res://assets/sfx/UI SFX/07_decline_2.wav")]
@export var on_enemy_near_victory_sound_effects: Array[AudioStream] = [preload("res://assets/sfx/UI SFX/08_start_game.wav")]


@onready var ui_root: Node = $UI
@onready var minimap: Control = $UI/BottomBar/MinimapFrame/Minimap

func play_command_sound() -> void:
	AudioUtils.play_random(command_audio_player, on_command_sound_effects)

func play_placement_blocked_sound() -> void:
	AudioUtils.play_random(command_audio_player, on_placement_blocked_sound_effects)

@onready var game_over_panel: PanelContainer = $UI/GameOverPanel
@onready var game_over_label: Label = $UI/GameOverPanel/Margin/VBox/ResultLabel

## Local-only overlay (see Settings autoload) — does not pause the match for
## anyone else, just gates this peer's own input. Options swaps it for the
## same OptionsMenu the main menu uses, instanced in _ready().
@onready var pause_menu: PanelContainer = $UI/PauseMenu
const OPTIONS_MENU_SCENE: PackedScene = preload("res://scenes/options_menu.tscn")
const MAIN_MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"
var _options_menu: OptionsMenu

var selected_units: Array[Unit] = []
## Client-local formation shape choice — which Formation.Type the next move/
## attack-move order for the current selection will use. Set via
## _set_formation_type (FORMATION_BOX_KEY/LINE_KEY/STAGGERED_KEY below) and
## sent along with each move order's RPC so the host (the only side that
## simulates movement) knows which shape to arrange the group's slots into.
var current_formation_type: Formation.Type = Formation.DEFAULT_TYPE
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
## "" | "move" | "attack" | "patrol" — armed by a command-card button/hotkey,
## consumed by the next left-click (see _handle_pending_order_input).
var pending_order_mode: String = ""
## True once the first click of the current patrol-targeting session has been
## sent, so later shift-clicks append a waypoint instead of starting a new patrol.
var _patrol_started_this_session: bool = false
## Armed by pressing a unit's activated-ability button; consumed by the next
## left-click, same as pending_order_mode == "move"/"attack", but needs its
## own state since the ability belongs to one unit, not the whole current
## selection. {"unit": Unit, "ability_index": int} or {}.
var _armed_ability: Dictionary = {}
## Purely local UI state: which units/buildings belong to each numbered
## control group (Ctrl+1-9 assigns, 1-9 selects / recalls camera).
var control_groups: Dictionary = {}
## Which group number the CURRENT selection came from via a number-key press
## — cleared by any other selection action, so pressing the same digit twice
## in a row (with nothing else selected in between) means "snap the camera
## there" rather than "reselect it".
var _active_group_number: int = -1

const CLICK_DRAG_THRESHOLD: float = 6.0

## Right-drag formation (Total War style): with units selected, pressing right
## orders nothing yet. Releasing without moving far is the usual right-click
## order; dragging lays the front rank out along the drag line, previewed with
## a ghost decal per slot, and releasing sends the group there in that shape.
## Wider than CLICK_DRAG_THRESHOLD so a slightly shaky right-click doesn't
## turn into a one-unit-wide column.
const FORMATION_DRAG_THRESHOLD: float = 14.0
## The drag line is raycast against everything except units (layer 3, value 4
## — see collision_layer on scenes/units/unit.tscn): the cursor sweeps across
## the very units being ordered, and hitting their capsules would make the line
## jump up and sideways every time it crossed one.
const FORMATION_DRAG_RAY_MASK: int = 0xFFFFFFFF & ~4
var _formation_drag_pressed: bool = false
var _formation_drag_active: bool = false
var _formation_drag_start_screen: Vector2 = Vector2.ZERO
var _formation_drag_start_world: Vector3 = Vector3.ZERO
var _formation_drag_end_world: Vector3 = Vector3.ZERO
var _formation_drag_facing: Vector3 = Vector3.ZERO

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
## Host-only: peers who left mid-match. Like a defeated player, their units
## and buildings stay (with nobody controlling them) but they earn no Favour
## and can't win.
var disconnected_peers: Dictionary = {}
var game_over: bool = false
## This peer has been knocked out of a match that carries on without them
## (an FFA elimination) — blocks their input like game_over does, without
## stopping the host's own win checks when the host is the one knocked out.
var local_player_out: bool = false
## Conquest mode: the first active player to favour_target Favour wins.
## Destroying every enemy main base wins in either mode. Both come from the
## lobby (Network.game_mode / favour_target) and are set identically on every
## peer in _ready, so clients know the target without being told.
var conquest_enabled: bool = true
var favour_target: int = 0
## peer_id -> {score: int, active: bool}, for every player in the match —
## broadcast by the host (see _broadcast_scores) since ResourceStockpile only
## ever tells a client its own totals. Read by ConquestHud.
var scores: Dictionary = {}
const SCORE_BROADCAST_INTERVAL: float = 0.25
var _score_broadcast_timer: float = 0.0
var conquest_hud: ConquestHud = null
const FAVOUR_RESOURCE: ResourceType = preload("res://resources/favour_resource_type.tres")

## Extend this when new resource types (Stone, ...) are added.
const DEBUG_RESOURCE_TYPES: Array[ResourceType] = [
	preload("res://resources/wood_resource_type.tres"),
	preload("res://resources/gold_resource_type.tres"),
	preload("res://resources/favour_resource_type.tres"),
]

var group_movement: GroupMovement
var feedback: WorldFeedback
var hud: Hud
var placement: BuildingPlacement
var chat: ChatConsole

## Components are created here rather than in _ready(): Objectives are
## children of this scene, and their own _ready() — which runs before this
## node's — already calls register_objective_unit/building, which wire signals
## straight into WorldFeedback.
func _enter_tree() -> void:
	if group_movement == null:
		_add_components()

func _ready() -> void:
	## Before hud.setup(), which draws the resource bar off conquest_enabled.
	conquest_enabled = Network.game_mode == Network.GameMode.CONQUEST
	## Objectives join their group in their own _ready, which has already run
	## by now (children ready before their parent) — so a lobby target of 0
	## (the map default) is worked out from the real point count here.
	favour_target = Network.favour_target if Network.favour_target > 0 \
			else MapInfo.FAVOUR_TARGET_PER_POINT * get_tree().get_nodes_in_group(&"objectives").size()
	_assign_objective_letters()

	hud.setup()
	if conquest_enabled:
		conquest_hud = ConquestHud.new()
		conquest_hud.main = self
		ui_root.add_child(conquest_hud)

	unit_spawner.spawn_function = _spawn_unit_from_data
	building_spawner.spawn_function = _spawn_building_from_data
	## Connected before _spawn_all_players() (not after) so the host's own
	## spawn fires this too, not just a joining client's replicated one —
	## CameraRig's authored position in main.tscn only happens to line up
	## with spawn index 0, so every peer needs this to see their own base.
	building_spawner.spawned.connect(_on_building_spawned_for_camera)
	if multiplayer.is_server():
		_spawn_all_players()
		## MultiplayerSpawner.spawned only fires on remote peers, so the host
		## (and single player) centres on its own base here instead.
		if town_centers.has(my_peer_id()):
			_camera_centered_on_spawn = true
			_center_camera_on([town_centers[my_peer_id()]])

	## After _spawn_all_players(), so the starting bases are carved by the
	## very first bake instead of triggering a second one a poll later. A
	## joining client has none of that yet and picks them up as they replicate.
	_start_navigation_blockers()

	feedback.setup()
	chat.setup()

	var utility_buttons: VBoxContainer = $UI/BottomBar/UtilityButtons
	utility_buttons.get_node(^"IdleButton").pressed.connect(_select_next_idle_villager)
	utility_buttons.get_node(^"FormationBoxButton").pressed.connect(_set_formation_type.bind(Formation.Type.BOX))
	utility_buttons.get_node(^"FormationLineButton").pressed.connect(_set_formation_type.bind(Formation.Type.LINE))
	utility_buttons.get_node(^"FormationStaggeredButton").pressed.connect(_set_formation_type.bind(Formation.Type.STAGGERED))
	UiDebugEditor.register_editable_root(ui_root, "main")

	game_over_panel.visible = false
	$UI/GameOverPanel/Margin/VBox/ReturnButton.pressed.connect(_return_to_main_menu)
	_build_spectate_button()

	Network.player_disconnected.connect(_on_network_player_disconnected)
	Network.server_disconnected.connect(_on_network_server_disconnected)
	_build_opponent_left_panel()
	placement.setup()

	pause_menu.visible = false
	$UI/PauseMenu/Margin/VBox/ResumeButton.pressed.connect(_close_pause_menu)
	$UI/PauseMenu/Margin/VBox/OptionsButton.pressed.connect(_open_options_menu)
	$UI/PauseMenu/Margin/VBox/LeaveButton.pressed.connect(_return_to_main_menu)
	_options_menu = OPTIONS_MENU_SCENE.instantiate()
	_options_menu.visible = false
	_options_menu.closed.connect(_open_pause_menu)
	ui_root.add_child(_options_menu)

## Built in code rather than authored into main.tscn (same as
## NavigationBlockers), under fixed names so each component's RPCs resolve to
## the same node path on every peer. `main` is assigned before add_child()
## because Hud and ChatConsole resolve their @onready UI nodes through it.
## Anything that needs this node's own @onready vars waits for each
## component's setup(), called from _ready().
func _add_components() -> void:
	group_movement = GroupMovement.new()
	group_movement.name = "GroupMovement"
	add_child(group_movement)

	feedback = WorldFeedback.new()
	feedback.main = self
	feedback.name = "WorldFeedback"
	add_child(feedback)

	hud = Hud.new()
	hud.main = self
	hud.name = "Hud"
	add_child(hud)

	placement = BuildingPlacement.new()
	placement.main = self
	placement.name = "BuildingPlacement"
	add_child(placement)

	chat = ChatConsole.new()
	chat.main = self
	chat.name = "ChatConsole"
	add_child(chat)

func _open_pause_menu() -> void:
	pause_menu.visible = true

func _close_pause_menu() -> void:
	pause_menu.visible = false

func _open_options_menu() -> void:
	pause_menu.visible = false
	_options_menu.open()

func _is_pause_menu_open() -> bool:
	return pause_menu.visible or _options_menu.visible

func my_peer_id() -> int:
	return multiplayer.get_unique_id()

## Resolves (and caches) the local player's own faction on demand, rather than
## relying on a one-time _ready() population — my_peer_id() can't be trusted
## to be stable/meaningful before a peer is ever assigned (e.g. running
## main.tscn directly without going through the lobby).
func my_faction() -> Faction:
	var id: int = my_peer_id()
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
	unit.animation_changed.connect(feedback.on_unit_animation_changed.bind(unit))
	unit.projectile_fired.connect(feedback.on_unit_projectile_fired.bind(unit))
	unit.damaged.connect(feedback.relay_damage_number.bind(unit))
	unit.resource_deposited.connect(feedback.on_unit_resource_deposited.bind(unit))
	unit.resource_harvested.connect(feedback.on_unit_resource_harvested)
	unit.order_completed.connect(_on_unit_order_completed.bind(unit))
	unit.ability_cast.connect(_on_unit_ability_cast.bind(unit))
	unit.ability_launched.connect(feedback.relay_ability_launch.bind(unit))
	unit.status_applied.connect(feedback.relay_status_effects.bind(unit))
	return unit

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
## drifting apart is what caused this in the first place.
func register_objective_unit(unit: Unit) -> void:
	unit.animation_changed.connect(feedback.on_unit_animation_changed.bind(unit))
	unit.projectile_fired.connect(feedback.on_unit_projectile_fired.bind(unit))
	unit.damaged.connect(feedback.relay_damage_number.bind(unit))
	unit.resource_deposited.connect(feedback.on_unit_resource_deposited.bind(unit))
	unit.resource_harvested.connect(feedback.on_unit_resource_harvested)
	unit.order_completed.connect(_on_unit_order_completed.bind(unit))
	unit.ability_cast.connect(_on_unit_ability_cast.bind(unit))
	unit.ability_launched.connect(feedback.relay_ability_launch.bind(unit))
	unit.status_applied.connect(feedback.relay_status_effects.bind(unit))

## Objective Favour income "+N" — called by objective.gd (via current_scene,
## so it has to stay reachable on Main); the popup itself is WorldFeedback's.
func show_favour_popup(objective: Objective, amount: int) -> void:
	feedback.show_favour_popup(objective, amount)

func register_objective_building(building: ProductionBuilding) -> void:
	building.item_completed.connect(_on_building_item_completed.bind(building))
	building.destroyed.connect(_on_building_destroyed.bind(building))
	building.damaged.connect(feedback.relay_damage_number.bind(building))
	building.projectile_fired.connect(feedback.on_building_projectile_fired.bind(building))

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
		building.damaged.connect(feedback.relay_damage_number.bind(building))
		building.construction_finished.connect(_on_building_construction_finished.bind(building))
		building.projectile_fired.connect(feedback.on_building_projectile_fired.bind(building))
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
	feedback.relay_impact_shake(building.global_position, 0.55)
	if not multiplayer.is_server() or not building.is_main_base or game_over:
		return
	var peer_id: int = building.owner_peer_id
	main_base_count_by_peer[peer_id] = maxi(main_base_count_by_peer.get(peer_id, 1) - 1, 0)
	if main_base_count_by_peer[peer_id] <= 0 and not defeated_peers.has(peer_id):
		defeated_peers[peer_id] = true
		_check_for_game_over()
		## Knocked out of a match that carries on (FFA): their own Defeat
		## screen now, rather than waiting for everyone else to finish.
		if not game_over and not disconnected_peers.has(peer_id):
			_rpc_player_out.rpc_id(peer_id)

## Still in the running: not eliminated, still connected. Only an active
## player earns Favour (see Objective._tick_favour) or can win.
func is_peer_active(peer_id: int) -> bool:
	return peer_id > 0 and not defeated_peers.has(peer_id) and not disconnected_peers.has(peer_id)

## Last player standing — by elimination or by everyone else leaving.
func _check_for_game_over() -> void:
	if game_over:
		return
	var all_peers: Array = main_base_count_by_peer.keys()
	if all_peers.size() <= 1:
		return
	var remaining: Array = all_peers.filter(is_peer_active)
	if remaining.size() <= 1:
		_end_game(remaining[0] if remaining.size() == 1 else -1)

## Run by the host at the start of every physics tick — before any Objective
## ticks, since Main is their ancestor — so everything banked during the
## previous tick is judged together: two players crossing the line on the
## same tick is a draw.
func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or game_over or not conquest_enabled or favour_target <= 0:
		return
	_score_broadcast_timer -= delta
	if _score_broadcast_timer <= 0.0:
		_score_broadcast_timer = SCORE_BROADCAST_INTERVAL
		_broadcast_scores()
	var winners: Array = []
	for peer_id in main_base_count_by_peer.keys():
		if is_peer_active(peer_id) and ResourceStockpile.get_amount(peer_id, FAVOUR_RESOURCE) >= favour_target:
			winners.append(peer_id)
	if not winners.is_empty():
		_end_game(winners[0] if winners.size() == 1 else -1)

## -1 = draw.
func _end_game(winner_peer_id: int) -> void:
	game_over = true
	## One last push so every bar shows the finishing total, not the one from
	## up to a broadcast interval ago.
	if conquest_enabled:
		_broadcast_scores()
	_rpc_game_over.rpc(winner_peer_id)

func _broadcast_scores() -> void:
	var snapshot: Dictionary = {}
	for peer_id in main_base_count_by_peer.keys():
		snapshot[peer_id] = {score = ResourceStockpile.get_amount(peer_id, FAVOUR_RESOURCE), active = is_peer_active(peer_id)}
	_rpc_scores.rpc(snapshot)

@rpc("authority", "call_local", "unreliable_ordered")
func _rpc_scores(snapshot: Dictionary) -> void:
	scores = snapshot

## "A", "B", ... going clockwise (seen from above, -Z up) from due north of
## the map's middle, with the point sitting at the middle itself (if any)
## last. Worked out identically on every peer from positions alone, so no
## syncing is needed.
func _assign_objective_letters() -> void:
	var objectives: Array = get_tree().get_nodes_in_group(&"objectives")
	if objectives.is_empty():
		return
	var middle := Vector3.ZERO
	for o in objectives:
		middle += o.global_position
	middle /= objectives.size()
	var centre: Node3D = null
	if objectives.size() > 2:
		for o in objectives:
			if Vector2(o.global_position.x - middle.x, o.global_position.z - middle.z).length() < CENTRE_POINT_RADIUS:
				centre = o
				break
	var ring: Array = objectives.filter(func(o): return o != centre)
	var angle_of := func(o: Node3D) -> float:
		return fposmod(atan2(o.global_position.x - middle.x, -(o.global_position.z - middle.z)), TAU)
	ring.sort_custom(func(a, b):
		var da: float = angle_of.call(a)
		var db: float = angle_of.call(b)
		if absf(da - db) > 0.0001:
			return da < db
		return a.global_position.distance_squared_to(middle) < b.global_position.distance_squared_to(middle))
	if centre != null:
		ring.append(centre)
	for i in ring.size():
		ring[i].set_letter(String.chr(65 + i))

## How close to the average of every point's position a point must be to
## count as the map's centre point for lettering.
const CENTRE_POINT_RADIUS: float = 5.0

## Only offered to a player knocked out of a match that's still going — see
## _rpc_player_out. Hidden again once the match actually ends.
var _spectate_button: Button = null

func _build_spectate_button() -> void:
	_spectate_button = Button.new()
	_spectate_button.text = "Spectate"
	_spectate_button.visible = false
	_spectate_button.pressed.connect(_start_spectating)
	var return_button: Button = $UI/GameOverPanel/Margin/VBox/ReturnButton
	return_button.add_sibling(_spectate_button)
	return_button.get_parent().move_child(_spectate_button, return_button.get_index())

## Stays in the match with the whole map revealed. Esc brings the panel back
## (see _unhandled_input) to leave later.
func _start_spectating() -> void:
	game_over_panel.visible = false
	fog_of_war.reveal_all = true
	## Nothing left to command — and a lingering selection would keep its
	## command-card buttons live.
	prune_selected_units()
	for u in selected_units:
		u.selected = false
	selected_units.clear()
	select_building(null)
	select_resource(null)

@rpc("authority", "call_local", "reliable")
func _rpc_player_out() -> void:
	local_player_out = true
	game_over_panel.visible = true
	game_over_label.text = "Defeat"
	_spectate_button.visible = true
	## The host IS the server: quitting takes the match down for everyone
	## still playing, and there's no host migration to hand it off to.
	if multiplayer.is_server() and not multiplayer.get_peers().is_empty():
		$UI/GameOverPanel/Margin/VBox/ReturnButton.text = "Leave (ends the match for everyone)"

@rpc("authority", "call_local", "reliable")
func _rpc_game_over(winner_peer_id: int) -> void:
	game_over = true
	game_over_panel.visible = true
	_spectate_button.visible = false
	$UI/GameOverPanel/Margin/VBox/ReturnButton.text = "Return to Main Menu"
	if winner_peer_id == -1:
		game_over_label.text = "Draw!"
	elif winner_peer_id == my_peer_id():
		game_over_label.text = "Victory!"
	else:
		game_over_label.text = "Defeat"

func _return_to_main_menu() -> void:
	Network.leave_game()
	SceneLoader.change_scene(MAIN_MENU_SCENE_PATH)

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
	return_button.text = "Return to Main Menu"
	return_button.pressed.connect(_return_to_main_menu)
	vbox.add_child(return_button)

	ui_root.add_child(_opponent_left_panel)

func _show_opponent_left(message: String) -> void:
	if game_over:
		return
	_opponent_left_label.text = message
	_opponent_left_panel.visible = true

## The match carries on without them (their units and buildings stay put,
## uncontrolled), so this is a chat line rather than the blocking panel — the
## host alone decides whether it ends the game (see _check_for_game_over).
func _on_network_player_disconnected(peer_id: int, player_data: Dictionary) -> void:
	if not multiplayer.is_server() or game_over:
		return
	disconnected_peers[peer_id] = true
	var line := "%s disconnected." % player_data.get("name", "A player")
	for peer in _chat_recipients():
		chat.send_line(peer, line)
	_check_for_game_over()

## Host only: everyone in the match, the host included.
func _chat_recipients() -> Array:
	var recipients: Array = [my_peer_id()]
	recipients.append_array(multiplayer.get_peers())
	return recipients

## Host only — called by Objective._set_owner whenever a point is taken.
## The capturer reads "You", everyone else the capturer's name.
func announce_point_captured(peer_id: int, letter: String) -> void:
	var name_text: String = Network.players.get(peer_id, {}).get("name", "Player %d" % peer_id)
	for peer in _chat_recipients():
		chat.send_line(peer, "%s captured %s." % ["You" if peer == peer_id else name_text, letter])

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
		chat.send_line(building.owner_peer_id, "Upgrade complete: %s" % item.item_name)
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
	building.register_produced_unit(unit)
	feedback.relay_building_squash(building)
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
	feedback.relay_impact_shake(building.global_position, 0.25)
	if not multiplayer.is_server():
		return
	chat.send_line(building.owner_peer_id, "Construction complete: %s" % building.building_name)
	_rpc_building_completed_sound.rpc_id(building.owner_peer_id)

@rpc("authority", "call_local", "reliable")
func _rpc_building_completed_sound() -> void:
	AudioUtils.play_random(command_audio_player, on_building_completed_sound_effects)

func _get_dropoff_for(peer_id: int) -> Node3D:
	var town_center: ProductionBuilding = town_centers.get(peer_id)
	if town_center == null:
		return null
	return town_center.get_node_or_null("DropoffPoint")

## Components are ticked from here rather than from their own _process so the
## per-frame order stays explicit: HUD first, then placement ghosts, then the
## world visuals that read placement state, then the host's reformation poll.
func _process(delta: float) -> void:
	hud.update(delta)
	placement.update()
	feedback.update_hover_ring()
	feedback.update_ability_target_decal()
	feedback.update_path_markers()
	_poll_formation_drag()
	group_movement.update_reformation(delta)

func _unhandled_input(event: InputEvent) -> void:
	if game_over:
		return
	if local_player_out:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			game_over_panel.visible = not game_over_panel.visible
			get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE and pause_menu.visible:
		_close_pause_menu()
		get_viewport().set_input_as_handled()
		return
	if _is_pause_menu_open():
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if chat.is_input_open() and event.keycode == KEY_ESCAPE:
			chat.close_chat_input()
			get_viewport().set_input_as_handled()
			return
		if not chat.is_input_open() and event.keycode == KEY_ENTER:
			chat.open_chat_input()
			get_viewport().set_input_as_handled()
			return
	if chat.is_input_open():
		return

	if event is InputEventKey and event.pressed and not event.echo:
		hud.pulse_action_button(OS.get_keycode_string(event.keycode))

	if placement.is_placing():
		placement.handle_placement_input(event)
		return

	if hud.showing_build_submenu and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		hud.close_build_submenu()
		get_viewport().set_input_as_handled()
		return

	if pending_order_mode != "":
		_handle_pending_order_input(event)
		return

	if _formation_drag_pressed and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_cancel_formation_drag()
		get_viewport().set_input_as_handled()
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

	if Settings.is_action_key_event(event, &"last_attack"):
		feedback.jump_to_last_attack()
		get_viewport().set_input_as_handled()
		return

	if Settings.is_action_key_event(event, &"idle_villager"):
		_select_next_idle_villager()
		get_viewport().set_input_as_handled()
		return

	if Settings.is_action_key_event(event, &"select_military"):
		_select_all_military()
		get_viewport().set_input_as_handled()
		return

	if Settings.is_action_key_event(event, &"center_selection"):
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
			and ((selected_building == null and selected_units.is_empty()) or hud.showing_build_submenu):
		var building_index: int = BUILDING_HOTKEYS.find(event.keycode)
		var my_building_types: Array[BuildingType] = my_faction().building_types
		if building_index != -1 and building_index < my_building_types.size():
			placement.on_construction_button_pressed(my_building_types[building_index])
			get_viewport().set_input_as_handled()
			return

	if event is InputEventKey and event.pressed and not event.echo and not selected_units.is_empty() \
			and not hud.showing_build_submenu:
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
			arm_move_mode()
			get_viewport().set_input_as_handled()
			return
		elif event.keycode == UNIT_STOP_KEY:
			issue_stop_order()
			get_viewport().set_input_as_handled()
			return
		elif event.keycode == UNIT_ATTACK_KEY:
			arm_attack_mode()
			get_viewport().set_input_as_handled()
			return
		elif event.keycode == UNIT_PATROL_KEY:
			arm_patrol_mode()
			get_viewport().set_input_as_handled()
			return
		elif event.keycode == UNIT_BUILD_KEY and any_selected_can_build():
			hud.open_build_submenu()
			get_viewport().set_input_as_handled()
			return
		elif selected_units.size() == 1 and ABILITY_HOTKEYS.has(event.keycode):
			var unit: Unit = selected_units[0]
			var ability_index: int = ABILITY_HOTKEYS.find(event.keycode)
			var ability: Ability = unit.get_ability(ability_index)
			if ability != null and ability.is_activated() and unit.owner_peer_id == my_peer_id():
				arm_ability(unit, ability_index)
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
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				if can_command_building(selected_building) and selected_building.can_rally:
					_set_rally_point(event.position)
				else:
					_begin_formation_drag(event.position)
			elif _formation_drag_pressed:
				_finish_formation_drag(event.shift_pressed)
	elif event is InputEventMouseMotion:
		if dragging and drag_start.distance_to(event.position) > CLICK_DRAG_THRESHOLD:
			selection_box.visible = true
			_update_selection_box(event.position)
		if _formation_drag_pressed:
			_update_formation_drag(event.position)

func _update_selection_box(current_pos: Vector2) -> void:
	var top_left := Vector2(min(drag_start.x, current_pos.x), min(drag_start.y, current_pos.y))
	var size := (current_pos - drag_start).abs()
	selection_box.position = top_left
	selection_box.size = size

## --- Right-drag formation (see FORMATION_DRAG_THRESHOLD) ---

func _begin_formation_drag(screen_pos: Vector2) -> void:
	prune_selected_units()
	if selected_units.is_empty():
		return
	var hit := raycast(screen_pos, FORMATION_DRAG_RAY_MASK)
	if hit.is_empty():
		return
	_formation_drag_pressed = true
	_formation_drag_active = false
	_formation_drag_start_screen = screen_pos
	_formation_drag_start_world = hit.position
	_formation_drag_end_world = hit.position

func _update_formation_drag(screen_pos: Vector2) -> void:
	if not _formation_drag_active:
		if screen_pos.distance_to(_formation_drag_start_screen) < FORMATION_DRAG_THRESHOLD:
			return
		_formation_drag_active = true
	prune_selected_units()
	if selected_units.is_empty():
		_cancel_formation_drag()
		return
	## Off the edge of the map: hold the last good line rather than dropping it.
	var hit := raycast(screen_pos, FORMATION_DRAG_RAY_MASK)
	if not hit.is_empty():
		_formation_drag_end_world = hit.position
	_formation_drag_facing = group_movement.drag_facing(selected_units, _formation_drag_start_world, _formation_drag_end_world)
	feedback.show_formation_preview(group_movement.drag_preview_slots(
			selected_units, _formation_drag_start_world, _formation_drag_end_world, _formation_drag_facing))

## Never dragged far enough: exactly the right-click order the press used to
## issue on its own, from where the button went down.
func _finish_formation_drag(append: bool) -> void:
	if _formation_drag_active:
		_issue_formation_drag_order(append)
	else:
		_issue_move_order(_formation_drag_start_screen, append)
	_cancel_formation_drag()

func _cancel_formation_drag() -> void:
	_formation_drag_pressed = false
	_formation_drag_active = false
	feedback.hide_formation_preview()

## The release can go missing — let go over the HUD and the GUI eats it, or
## something else (chat, placement, an armed order) claims input mid-drag — so
## the button's real state is polled as a backstop instead of trusting the
## release event alone, which would otherwise leave the preview stuck on screen.
func _poll_formation_drag() -> void:
	if not _formation_drag_pressed or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		return
	if game_over or local_player_out or _is_pause_menu_open() or chat.is_input_open() or placement.is_placing():
		_cancel_formation_drag()
	else:
		_finish_formation_drag(Input.is_key_pressed(KEY_SHIFT))

func _issue_formation_drag_order(append: bool) -> void:
	prune_selected_units()
	if selected_units.is_empty():
		return
	var unit_paths: Array[NodePath] = []
	for unit in selected_units:
		unit_paths.append(unit.get_path())
	var midpoint := (_formation_drag_start_world + _formation_drag_end_world) * 0.5
	var front_width := Vector2(_formation_drag_end_world.x - _formation_drag_start_world.x,
			_formation_drag_end_world.z - _formation_drag_start_world.z).length()
	_rpc_issue_command.rpc_id(1, unit_paths, NodePath(), midpoint, false, append, current_formation_type, front_width, _formation_drag_facing)
	play_command_sound()
	feedback.play_command_feedback(midpoint, false)
	feedback.spawn_command_popup("move", midpoint, feedback.command_speaker())
	_update_order_path_markers(midpoint, append)

## Units can die (and be freed) between selection and the next click/order, so
## any stored reference must be validity-checked before use, not just trusted.
func prune_selected_units() -> void:
	for i in range(selected_units.size() - 1, -1, -1):
		if not is_instance_valid(selected_units[i]):
			selected_units.remove_at(i)

## --- Control groups ---

func _assign_control_group(number: int) -> void:
	prune_selected_units()
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
	select_building(null)
	select_resource(null)

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
		select_building(building_in_group)
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
		if unit and unit.owner_peer_id == my_peer_id() and unit.can_gather \
				and unit.status_activity == Unit.Activity.IDLE and unit.status_command == Unit.Command.NONE:
			idle_villagers.append(unit)
	if idle_villagers.is_empty():
		return

	_idle_villager_cycle_index = (_idle_villager_cycle_index + 1) % idle_villagers.size()
	var villager := idle_villagers[_idle_villager_cycle_index]

	for u in selected_units:
		u.selected = false
	selected_units.clear()
	select_building(null)
	select_resource(null)
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
		if child is Unit and child.owner_peer_id == my_peer_id() and child.display_name == unit_type \
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
		if unit and unit.owner_peer_id == my_peer_id() and not unit.can_gather:
			military.append(unit)
	if military.is_empty():
		return

	for u in selected_units:
		u.selected = false
	selected_units.clear()
	select_building(null)
	select_resource(null)
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
	if building.owner_peer_id != my_peer_id() or not building.is_main_base:
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
	prune_selected_units()
	_active_group_number = -1
	var rect := Rect2(
		Vector2(min(start_pos.x, end_pos.x), min(start_pos.y, end_pos.y)),
		(end_pos - start_pos).abs()
	)

	for u in selected_units:
		u.selected = false
	selected_units.clear()

	if start_pos.distance_to(end_pos) <= CLICK_DRAG_THRESHOLD:
		var collider: Object = raycast(end_pos).get("collider")
		if collider is Unit and collider.owner_peer_id == my_peer_id():
			select_building(null)
			select_resource(null)
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
			select_building(collider)
			collider.play_select_sound()
			select_resource(null)
			clicked_ring_target = collider
			if double_click:
				_center_camera_on([collider])
		elif collider is Gatherable:
			## Any resource node (own or not — trees/berries/gold deposits have
			## no owner) shows its remaining amount in the info panel; unlike
			## a unit/building this isn't "yours to command", just informational.
			select_building(null)
			select_resource(collider)
			collider.play_select_sound()
			clicked_ring_target = collider
		elif collider is Unit or collider is ProductionBuilding:
			## Not "selectable" (enemy unit/building) but still a valid thing
			## to click-highlight.
			select_building(null)
			select_resource(null)
			clicked_ring_target = collider
			if double_click and collider is ProductionBuilding:
				_center_camera_on([collider])
		else:
			select_building(null)
			select_resource(null)
			clicked_ring_target = null
		return

	select_building(null)
	select_resource(null)
	clicked_ring_target = null
	for child in units_root.get_children():
		if child is Unit and child.owner_peer_id == my_peer_id() and not camera.is_position_behind(child.global_position):
			var screen_pos: Vector2 = camera.unproject_position(child.global_position)
			if rect.has_point(screen_pos):
				child.selected = true
				selected_units.append(child)
	_play_random_select_sound(selected_units)

func raycast(screen_pos: Vector2, collision_mask: int = 0xFFFFFFFF) -> Dictionary:
	var space_state := get_world_3d().direct_space_state
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 1000.0
	var query := PhysicsRayQueryParameters3D.create(from, to, collision_mask)
	return space_state.intersect_ray(query)

## Gatherable / enemy Unit / enemy-or-under-construction-or-deposit-linked
## ProductionBuilding -> its path, else an empty path meaning "plain ground".
func _resolve_order_target_path(result: Dictionary) -> NodePath:
	if result.collider is Gatherable:
		return result.collider.get_path()
	elif result.collider is Unit and result.collider.owner_peer_id != my_peer_id():
		return result.collider.get_path()
	## A friendly building under construction is also a valid target (to send
	## builders to it), and so is a friendly building with a linked_deposit
	## (e.g. a Mine — right-clicking the mine itself should still gather from
	## the deposit it sits on), alongside the existing enemy-building-attack case.
	elif result.collider is ProductionBuilding and \
			((result.collider.owner_peer_id != my_peer_id() and result.collider.can_be_attacked()) \
				or result.collider.is_under_construction or result.collider.linked_deposit != null):
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
	if collider is ProductionBuilding and not collider.can_be_attacked():
		return "move"
	if (collider is Unit or collider is ProductionBuilding) \
			and collider.owner_peer_id != my_peer_id():
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
	prune_selected_units()
	if selected_units.is_empty():
		return
	var result := raycast(screen_pos)
	if result.is_empty():
		return

	var unit_paths: Array[NodePath] = []
	for unit in selected_units:
		unit_paths.append(unit.get_path())

	var target_path := _resolve_order_target_path(result)
	_rpc_issue_command.rpc_id(1, unit_paths, target_path, result.position, false, append, current_formation_type)
	play_command_sound()
	feedback.play_command_feedback(result.position, false)
	feedback.spawn_command_popup(_popup_kind_for_order(result), result.position, feedback.command_speaker())
	_update_order_path_markers(result.position, append)

## A shift-queued order adds a waypoint marker per unit; a fresh one replaces
## whatever queue they were showing.
func _update_order_path_markers(world_pos: Vector3, append: bool) -> void:
	for unit in selected_units:
		if append:
			feedback.add_path_marker(unit, world_pos)
		else:
			feedback.clear_path_markers(unit)

## Same target inference as a plain move order, except empty ground issues an
## attack-move instead of a plain move — see _rpc_issue_command's attack_move_fallback.
func _issue_attack_order(screen_pos: Vector2, append: bool = false) -> void:
	prune_selected_units()
	if selected_units.is_empty():
		return
	var result := raycast(screen_pos)
	if result.is_empty():
		return

	var unit_paths: Array[NodePath] = []
	for unit in selected_units:
		unit_paths.append(unit.get_path())

	var target_path := _resolve_order_target_path(result)
	_rpc_issue_command.rpc_id(1, unit_paths, target_path, result.position, true, append, current_formation_type)
	play_command_sound()
	feedback.play_command_feedback(result.position, true)
	feedback.spawn_command_popup("attack", result.position, feedback.command_speaker())
	_update_order_path_markers(result.position, append)

func issue_stop_order() -> void:
	prune_selected_units()
	if selected_units.is_empty():
		return
	var unit_paths: Array[NodePath] = []
	for unit in selected_units:
		unit_paths.append(unit.get_path())
		feedback.clear_path_markers(unit)
	_rpc_issue_stop.rpc_id(1, unit_paths)
	play_command_sound()

## front_width/facing: a right-drag formation (see _issue_formation_drag_order)
## — the front-rank width the player dragged out and the facing the preview
## was drawn with, so the host builds exactly the shape that was shown.
## Negative/zero for an ordinary click order.
@rpc("any_peer", "call_local", "reliable")
func _rpc_issue_command(unit_paths: Array[NodePath], target_path: NodePath, world_pos: Vector3, attack_move_fallback: bool, append: bool, formation_type: Formation.Type = Formation.DEFAULT_TYPE, front_width: float = -1.0, facing: Vector3 = Vector3.ZERO) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = my_peer_id()
	## Client-supplied, so flattened and renormalized rather than trusted as-is.
	facing.y = 0.0
	facing = facing.normalized() if facing.length_squared() > 0.0001 else Vector3.ZERO

	var target_node: Node = get_node_or_null(target_path) if target_path != NodePath() else null

	var units: Array[Unit] = []
	for path in unit_paths:
		var unit := get_node_or_null(path) as Unit
		if unit != null and unit.owner_peer_id == sender_id:
			units.append(unit)

	var formation_positions := group_movement.formation_positions(units, world_pos, formation_type, facing, front_width)
	## Chokepoint funnelling: if the route to the destination has to thread
	## something narrower than this formation is wide (a gate, a slot between
	## buildings), every unit heads for a shared waypoint just past that gap
	## first and only disperses to its own slot once through — otherwise the
	## flanks of a wide shape each path to their own slot independently and the
	## group smears itself along the wall instead of columning up. Empty (the
	## common case: open ground, or a single/small group) leaves dispatch
	## exactly as it was. Host-side and one-shot, same as the formation shape
	## itself — see find_funnel_point.
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
	var group_speed := group_movement.slowest_move_speed(units)
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
				funnel = group_movement.find_funnel_point(units, group_movement.group_centroid(units), world_pos, formation_positions)
			if not funnel.is_empty():
				group_movement.apply_funnel(unit, funnel)
	## Reformation bookkeeping: remember this group's destination and shape so
	## the host can close ranks around whoever is still walking it when members
	## die en route (see update_reformation). Registered from the units'
	## post-dispatch state rather than blindly from `units` — a shift-queued
	## member hasn't started this leg yet, and a gather/attack/build target
	## ignores formation slots entirely, so neither belongs in a record whose
	## whole job is re-solving move slots.
	group_movement.register_formation(cohesion_group, world_pos, formation_type, attack_move_fallback, facing, front_width)

## Explicit re-form (FORMATION_REFORM_KEY): pulls a selection that combat, an
## obstacle or a chokepoint has smeared into a blob back into its formation
## shape, in place. Client-local only as far as the RPC — same shape as every
## other order here, the host does the solving.
func _issue_reform_order() -> void:
	prune_selected_units()
	if selected_units.size() < 2:
		return
	var unit_paths: Array[NodePath] = []
	for unit in selected_units:
		unit_paths.append(unit.get_path())
		feedback.clear_path_markers(unit)
	_rpc_issue_reform.rpc_id(1, unit_paths, current_formation_type)
	play_command_sound()

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
		sender_id = my_peer_id()

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
	if group_movement.any_funnelling(units):
		return

	var centroid := group_movement.group_centroid(units)
	var facing := group_movement.group_facing(units)
	group_movement.reform_group(units, centroid, formation_type, false, facing)
	group_movement.register_formation(units, centroid, formation_type, false, facing)

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
## as the formation slot position itself (see formation_positions).
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
		feedback.play_unit_order_sound(unit, Unit.OrderSoundKind.GATHER)
	## Right-clicking a finished building built on a deposit (e.g. a Mine)
	## should gather from what it sits on, same as clicking the deposit
	## directly — checked before the attack/build branches since a
	## same-owner building would never match attack anyway, and this only
	## applies once construction is done (still-building falls through to
	## the command_build branch below).
	elif target_node is ProductionBuilding and target_node.linked_deposit != null \
			and not target_node.is_under_construction and target_node.linked_deposit.can_be_gathered():
		unit.command_gather(target_node.linked_deposit, _get_dropoff_for(unit.owner_peer_id))
		feedback.play_unit_order_sound(unit, Unit.OrderSoundKind.GATHER)
	elif (target_node is Unit or (target_node is ProductionBuilding and target_node.can_be_attacked())) \
			and target_node.owner_peer_id != unit.owner_peer_id:
		unit.command_attack(target_node)
		feedback.play_unit_order_sound(unit, Unit.OrderSoundKind.ATTACK)
	elif target_node is ProductionBuilding and target_node.is_under_construction:
		unit.command_build(target_node)
		feedback.play_unit_order_sound(unit, Unit.OrderSoundKind.BUILD)
	elif attack_move_fallback:
		unit.command_attack_move(world_pos, speed_override, cohesion_group)
		feedback.play_unit_order_sound(unit, Unit.OrderSoundKind.ATTACK)
	else:
		unit.command_move(world_pos, speed_override, cohesion_group)
		feedback.play_unit_order_sound(unit, Unit.OrderSoundKind.MOVE)

## append: true once the current patrol-targeting session's first click has
## already gone out, so further shift-clicks extend the loop instead of
## restarting it (see _handle_pending_order_input).
@rpc("any_peer", "call_local", "reliable")
func _rpc_issue_patrol(unit_paths: Array[NodePath], world_pos: Vector3, append: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = my_peer_id()

	for path in unit_paths:
		var unit := get_node_or_null(path) as Unit
		if unit == null or unit.owner_peer_id != sender_id:
			continue
		if append and unit.status_command == Unit.Command.PATROL:
			unit.command_patrol_add_waypoint(world_pos)
		else:
			unit.command_patrol([unit.global_position, world_pos])
		feedback.play_unit_order_sound(unit, Unit.OrderSoundKind.PATROL)

@rpc("any_peer", "call_local", "reliable")
func _rpc_issue_stop(unit_paths: Array[NodePath]) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = my_peer_id()

	for path in unit_paths:
		var unit := get_node_or_null(path) as Unit
		if unit == null or unit.owner_peer_id != sender_id:
			continue
		unit.clear_order_queue()
		unit.command_stop()
		feedback.play_unit_order_sound(unit, Unit.OrderSoundKind.STOP)

## Mirrors handle_placement_input's pattern: Escape/right-click cancels,
## left-click dispatches based on which order is currently armed. Move/Attack
## are single-shot; Patrol stays armed while Shift is held so multiple clicks
## chain into one patrol loop.
func _handle_pending_order_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		pending_order_mode = ""
		_armed_ability = {}
		return
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		pending_order_mode = ""
		_armed_ability = {}
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	match pending_order_mode:
		"ability":
			var result := raycast(event.position)
			pending_order_mode = ""
			if result.is_empty() or _armed_ability.is_empty():
				_armed_ability = {}
				return
			var unit: Unit = _armed_ability["unit"]
			if is_instance_valid(unit):
				_rpc_request_ability.rpc_id(1, unit.get_path(), _armed_ability["ability_index"], result.position)
				play_command_sound()
				feedback.clear_path_markers(unit)
			_armed_ability = {}
		"move":
			_issue_move_order(event.position, event.shift_pressed)
			if not event.shift_pressed:
				pending_order_mode = ""
		"attack":
			_issue_attack_order(event.position, event.shift_pressed)
			if not event.shift_pressed:
				pending_order_mode = ""
		"patrol":
			var result := raycast(event.position)
			if result.is_empty():
				return
			prune_selected_units()
			if selected_units.is_empty():
				pending_order_mode = ""
				return
			var unit_paths: Array[NodePath] = []
			for unit in selected_units:
				unit_paths.append(unit.get_path())
			_rpc_issue_patrol.rpc_id(1, unit_paths, result.position, _patrol_started_this_session)
			play_command_sound()
			feedback.spawn_command_popup("patrol", result.position, feedback.command_speaker())
			_patrol_started_this_session = true
			if not event.shift_pressed:
				pending_order_mode = ""

## Whether the local player may actually USE this building, as opposed to
## merely looking at it. An enemy building can be selected and inspected for
## as long as fog of war has it revealed, but never produces, rallies, or
## takes orders — see Hud.show_building and the rally handling.
func can_command_building(building: ProductionBuilding) -> bool:
	return building != null and building.owner_peer_id == my_peer_id()

## null clears the building selection and hands the panels back to whatever
## the rest of the selection implies.
func select_building(building: ProductionBuilding) -> void:
	selected_building = building
	feedback.update_rally_marker()
	if building == null:
		hud.refresh_command_panel()
		return
	selected_resource = null
	hud.show_building(building)

## Clicking one portrait in a multi-unit selection narrows the selection down
## to just that unit — Hud.update notices selected_units changed and rebuilds
## the panel into its single-unit form on the next frame.
func select_only_unit(unit: Unit) -> void:
	if not is_instance_valid(unit):
		return
	for u in selected_units:
		u.selected = false
	selected_units.clear()
	_active_group_number = -1
	unit.selected = true
	selected_units.append(unit)
	unit.play_select_sound()

## Left-click select/deselect a resource node (see selected_resource);
## null clears it back to whatever the rest of the selection implies.
func select_resource(resource: Gatherable) -> void:
	selected_resource = resource
	if resource != null:
		for u in selected_units:
			if is_instance_valid(u):
				u.selected = false
		selected_units.clear()
		selected_building = null
	hud.refresh_command_panel()

func any_selected_can_build() -> bool:
	for unit in selected_units:
		if is_instance_valid(unit) and unit.can_build:
			return true
	return false

func arm_move_mode() -> void:
	pending_order_mode = "move"
	play_command_sound()

func arm_attack_mode() -> void:
	pending_order_mode = "attack"
	play_command_sound()

func arm_patrol_mode() -> void:
	pending_order_mode = "patrol"
	_patrol_started_this_session = false
	play_command_sound()

func player_has_monarch_unlocked(peer_id: int) -> bool:
	for node in get_tree().get_nodes_in_group("buildings"):
		if node is ProductionBuilding and node.owner_peer_id == peer_id and node.can_promote_monarch:
			return true
	return false

func issue_promote_order(unit: Unit) -> void:
	_rpc_request_promote_monarch.rpc_id(1, unit.get_path())
	play_command_sound()

## Refuses (silently — the HUD button is already greyed out) while the
## ability is still cooling down, rather than arming a click the host would
## only reject.
func arm_ability(unit: Unit, ability_index: int) -> void:
	if not is_instance_valid(unit) or not unit.is_ability_ready_locally(ability_index):
		return
	_armed_ability = {"unit": unit, "ability_index": ability_index}
	pending_order_mode = "ability"
	play_command_sound()

## The ability the next left-click will cast, or null — read every frame by
## WorldFeedback to draw the targeting decal. Drops the arming if its unit
## died or was deselected in the meantime.
func get_armed_ability() -> Ability:
	if pending_order_mode != "ability" or _armed_ability.is_empty():
		return null
	var unit = _armed_ability["unit"]
	if not is_instance_valid(unit) or unit.status_activity == Unit.Activity.DEAD or not selected_units.has(unit):
		pending_order_mode = ""
		_armed_ability = {}
		return null
	return unit.get_ability(_armed_ability["ability_index"])

func on_producible_button_pressed(building: ProductionBuilding, item_index: int) -> void:
	var item := building.producibles[item_index]
	## Hotkeys come straight here, bypassing the greyed-out button.
	if item.kind == ProducibleItem.Kind.UNIT and building.synced_unit_limit_reached:
		return
	if not hud.can_afford_locally(item.get_costs()):
		hud.flash_missing_resources(item.get_costs())
		return
	_rpc_enqueue.rpc_id(1, building.get_path(), item_index)
	play_command_sound()

@rpc("any_peer", "call_local", "reliable")
func _rpc_enqueue(building_path: NodePath, item_index: int) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = my_peer_id()

	var building := get_node_or_null(building_path) as ProductionBuilding
	if building == null or building.owner_peer_id != sender_id:
		return
	if item_index < 0 or item_index >= building.producibles.size():
		return
	building.enqueue(building.producibles[item_index])

## queue_index 0 is the item in progress (the progress bar); 1+ are the slots
## queued behind it, in order.
func cancel_production(building: ProductionBuilding, queue_index: int) -> void:
	_rpc_cancel_production.rpc_id(1, building.get_path(), queue_index)
	play_command_sound()

@rpc("any_peer", "call_local", "reliable")
func _rpc_cancel_production(building_path: NodePath, queue_index: int) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = my_peer_id()

	var building := get_node_or_null(building_path) as ProductionBuilding
	if building == null or building.owner_peer_id != sender_id:
		return
	building.cancel_at(queue_index)

## --- Monarch promotion / abilities ---

@rpc("any_peer", "call_local", "reliable")
func _rpc_request_promote_monarch(unit_path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = my_peer_id()

	var unit := get_node_or_null(unit_path) as Unit
	if unit == null or unit.owner_peer_id != sender_id:
		return
	if not unit.can_fight or unit.is_monarch or unit.monarch_abilities.is_empty():
		return
	if not player_has_monarch_unlocked(sender_id):
		return
	if not ResourceStockpile.can_afford(sender_id, unit.monarch_promotion_costs):
		return
	ResourceStockpile.spend(sender_id, unit.monarch_promotion_costs)
	unit.promote_to_monarch()

## Validation only — range isn't checked here, since an out-of-range target
## just makes the unit walk until it's in range (see Unit.command_cast_ability).
## Cooldown and cost are checked again at the moment of casting.
@rpc("any_peer", "call_local", "reliable")
func _rpc_request_ability(unit_path: NodePath, ability_index: int, target_pos: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = my_peer_id()

	var unit := get_node_or_null(unit_path) as Unit
	if unit == null or unit.owner_peer_id != sender_id:
		return
	var ability: Ability = unit.get_ability(ability_index)
	if ability == null or not ability.is_activated() or not unit.is_ability_ready(ability_index):
		return
	if not ResourceStockpile.can_afford(sender_id, ability.costs):
		return
	unit.clear_order_queue()
	unit.command_cast_ability(ability_index, target_pos)

## Host-only (Unit.ability_cast only fires there). Tells the owner when the
## ability comes back so their HUD can grey it out, and shows everyone the
## caster winding up. The projectile and impact follow later, off
## Unit.ability_launched (see WorldFeedback.relay_ability_launch).
func _on_unit_ability_cast(ability_index: int, _target_pos: Vector3, unit: Unit) -> void:
	var ability: Ability = unit.get_ability(ability_index)
	if ability == null:
		return
	## Peer 0 is "neutral", not a real peer — rpc_id(0) would broadcast.
	if unit.owner_peer_id > 0:
		_rpc_ability_cooldown_started.rpc_id(unit.owner_peer_id, unit.get_path(), ability_index, ability.cooldown)
	if ability.kind == Ability.Kind.ACTIVATED_AREA:
		feedback.relay_cast_windup(unit, ability_index)

## Stamped on the receiver's own clock, so it never depends on host and client
## agreeing on Time.get_ticks_msec().
@rpc("authority", "call_local", "reliable")
func _rpc_ability_cooldown_started(unit_path: NodePath, ability_index: int, cooldown: float) -> void:
	var unit := get_node_or_null(unit_path) as Unit
	if unit != null:
		unit.start_local_cooldown(ability_index, cooldown)

## --- Rally points ---

## Applied to our own local copy immediately (for instant marker feedback and,
## if we're the host, because that copy IS the authoritative one), and also
## sent to the host so a non-host owner's rally point actually affects spawning.
func _set_rally_point(screen_pos: Vector2) -> void:
	var result := raycast(screen_pos)
	if result.is_empty():
		return
	var target_path := _resolve_order_target_path(result)
	selected_building.rally_point = result.position
	selected_building.rally_target_path = target_path
	selected_building.has_rally_point = true
	feedback.update_rally_marker()
	feedback.spawn_rally_dust(result.position)
	AudioUtils.play_random(command_audio_player, on_rally_set_sound_effects)
	_rpc_set_rally_point.rpc_id(1, selected_building.get_path(), result.position, target_path)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_rally_point(building_path: NodePath, world_pos: Vector3, target_path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = my_peer_id()

	var building := get_node_or_null(building_path) as ProductionBuilding
	if building == null or building.owner_peer_id != sender_id or not building.can_rally:
		return
	building.rally_point = world_pos
	building.rally_target_path = target_path
	building.has_rally_point = true
