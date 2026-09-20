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
##   Weather           — rain that comes and goes, synced from the host

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
## Shares G with BUILDING_HOTKEYS, which only take it while the build submenu
## is open (checked first in _unhandled_input), so the two never collide.
const UNIT_HOLD_KEY: Key = KEY_G
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
## Opens/closes the Research panel (see ResearchPanel, which listens for it).
const RESEARCH_PANEL_KEY: Key = KEY_TAB
## One per PowerBar slot, in tree order. Every letter is already a command,
## camera or building key.
const POWER_HOTKEYS: Array[Key] = [KEY_F5, KEY_F6, KEY_F7, KEY_F8, KEY_F9]
## Assigned by position in Unit.get_abilities(), same convention as
## PRODUCIBLE_HOTKEYS/BUILDING_HOTKEYS below — a passive ability still claims
## a slot (shown disabled) so hotkeys stay stable regardless of ability order.
const ABILITY_HOTKEYS: Array[Key] = [KEY_R, KEY_T, KEY_Y, KEY_U]
const PRODUCIBLE_HOTKEYS: Array[Key] = [KEY_I, KEY_J, KEY_K, KEY_L]
const BUILDING_HOTKEYS: Array[Key] = [KEY_Z, KEY_X, KEY_C, KEY_V, KEY_B, KEY_N, KEY_G, KEY_O]
## The unit/building roster. Only [0] is used — every player gets the same
## one (see _faction_for_peer).
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
## Every building a double-click gathered up, selected_building among them;
## empty for an ordinary single-building selection. The command panel still
## shows selected_building, but units trained from it are spread across the
## whole group (see on_producible_button_pressed).
var selected_buildings: Array[ProductionBuilding] = []
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
## pending_order_mode == "power": which of the local Ruler's nodes the next
## left-click casts (see arm_power).
var _armed_power_index: int = -1
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
## Shift doubles as queue-order and flip-facing during a right-drag: its state
## when the drag began decides queueing, and pressing or releasing it mid-drag
## flips the facing (flipped whenever it differs from that starting state).
var _formation_drag_shift_at_start: bool = false
var _formation_drag_flipped: bool = false

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
## No winning team: two crossing the line on the same tick, or everyone gone.
## Never a real team id (see Teams.team_of).
const DRAW: int = -1
## This peer has been knocked out of a match that carries on without them
## (an FFA elimination) — blocks their input like game_over does, without
## stopping the host's own win checks when the host is the one knocked out.
var local_player_out: bool = false
## Conquest mode: the first active team to favour_target Favour wins.
## Destroying every enemy main base wins in either mode. Both come from the
## lobby (Network.game_mode / favour_target) and are set identically on every
## peer in _ready, so clients know the target without being told.
var conquest_enabled: bool = true
var favour_target: int = 0
## The Scenario node in this scene, or null in an ordinary skirmish. Set in
## _ready from MatchRules, which the node itself installed on entering.
var scenario: Scenario = null
## Scenario slot index -> the peer playing it. The same on every machine.
var scenario_peer_by_slot: Dictionary = {}
## Authored name ("Guard1") -> the placed unit/building it became, so quest
## steps can name the things a scenario put on the map even though adopting
## them renames and reparents them.
var scenario_entities: Dictionary = {}
## team -> {score: int, active: bool, tint: Color} — a team's members' Favour
## added together, since a team wins together (see Teams). Broadcast by the
## host (see _broadcast_scores) because ResourceStockpile only ever tells a
## client its own totals. Read by ConquestHud.
var scores: Dictionary = {}
const SCORE_BROADCAST_INTERVAL: float = 0.25
var _score_broadcast_timer: float = 0.0
var conquest_hud: ConquestHud = null
## The tracker, dialogue box and briefing screen; only in a scenario.
var quest_ui: QuestUi = null
var research_panel: ResearchPanel = null
var power_bar: PowerBar = null
const FAVOUR_RESOURCE: ResourceType = preload("res://resources/favour_resource_type.tres")
const UnitGrid = preload("res://scripts/unit_grid.gd")

## Extend this when new resource types (Stone, ...) are added.
## What every player starts a skirmish with. Favour is score and research
## points are earned, so only the two spendable resources are stocked; a Pact
## currency needs its Pact before there is anywhere to put it.
const STARTING_RESOURCES: Dictionary = {
	preload("res://resources/gold_resource_type.tres"): 300,
	preload("res://resources/wood_resource_type.tres"): 300,
}

const DEBUG_RESOURCE_TYPES: Array[ResourceType] = [
	preload("res://resources/wood_resource_type.tres"),
	preload("res://resources/gold_resource_type.tres"),
	preload("res://resources/favour_resource_type.tres"),
	preload("res://resources/research_resource_type.tres"),
]

var group_movement: GroupMovement
var feedback: WorldFeedback
var hud: Hud
var placement: BuildingPlacement
var chat: ChatConsole
var weather: Weather
var day_night: DayNight
var research: Research
var pacts: Pacts
var wildlife: Wildlife
var quests: QuestRunner

## Components are created here rather than in _ready(): Objectives are
## children of this scene, and their own _ready() — which runs before this
## node's — already calls register_objective_unit/building, which wire signals
## straight into WorldFeedback.
func _enter_tree() -> void:
	if group_movement == null:
		_add_components()
	## Cleared per match, before any child's _enter_tree: a Scenario node in
	## this scene installs its own rules there, and everything that asks
	## (a Shrine rolling monsters, a building pricing an item) runs in _ready,
	## after both. An ordinary match leaves this null and gets the defaults.
	MatchRules.current = null

## "cmd speed" (see ChatConsole) changes the engine-wide time scale; it must
## not follow the player out to the menus or into their next match.
func _exit_tree() -> void:
	Engine.time_scale = 1.0

## The cloud layer both casts the drifting shadows and draws the faint visible
## wisps, so hiding it turns off both.
func _apply_clouds_setting(key: StringName) -> void:
	if key != &"clouds":
		return
	var clouds: Node3D = get_node_or_null(^"CloudShadowLayer")
	if clouds:
		clouds.visible = Settings.get_value(&"clouds")

func _ready() -> void:
	## Both are autoloads and outlive a match, so a second one in the same
	## session — the next campaign mission, or another skirmish — would open
	## holding the last one's gold, population and research points.
	ResourceStockpile.reset()
	Population.reset()
	UnitUpgrades.reset()
	## A scenario scene is an ordinary map with a Scenario node added; it
	## installed itself in MatchRules while entering the tree, so there is no
	## mode to switch on — this is the whole of "are we in a mission".
	scenario = MatchRules.active().scenario
	## Before hud.setup(), which draws the resource bar off conquest_enabled.
	conquest_enabled = scenario.favour_enabled if scenario != null \
			else Network.game_mode == Network.GameMode.CONQUEST
	## Objectives join their group in their own _ready, which has already run
	## by now (children ready before their parent) — so a target of 0 (the map
	## default) is worked out from the real point count here.
	var wanted_target: int = scenario.favour_target if scenario != null else Network.favour_target
	favour_target = wanted_target if wanted_target > 0 \
			else MapInfo.FAVOUR_TARGET_PER_POINT * get_tree().get_nodes_in_group(&"objectives").size()
	_assign_objective_letters()
	## Map dressing like the border trees uses the same baked-lighting GLBs as
	## gatherables, which convert themselves in Gatherable._ready().
	var scenery: Node = get_node_or_null(^"Scenery")
	if scenery:
		BakedLightingMaterial.apply_to(scenery)
		TreeWind.apply_to_trees_in(scenery)
	_apply_clouds_setting(&"clouds")
	Settings.changed.connect(_apply_clouds_setting)

	hud.setup()
	if conquest_enabled:
		conquest_hud = ConquestHud.new()
		conquest_hud.main = self
		ui_root.add_child(conquest_hud)
	research_panel = ResearchPanel.new()
	research_panel.main = self
	ui_root.add_child(research_panel)
	power_bar = PowerBar.new()
	power_bar.main = self
	ui_root.add_child(power_bar)

	## Every peer works out the same sides and adopts the same hand-placed
	## units — none of it is networked (see Scenario.resolve_players).
	if scenario != null:
		scenario_peer_by_slot = scenario.resolve_players()
		_apply_scenario_modifiers()
		_adopt_scenario_entities()

	unit_spawner.spawn_function = _spawn_unit_from_data
	building_spawner.spawn_function = _spawn_building_from_data
	## Connected before _spawn_all_players() (not after) so the host's own
	## spawn fires this too, not just a joining client's replicated one —
	## CameraRig's authored position in main.tscn only happens to line up
	## with spawn index 0, so every peer needs this to see their own base.
	building_spawner.spawned.connect(_on_building_spawned_for_camera)
	if multiplayer.is_server():
		_spawn_all_players()
		_snapshot_roster()
		## MultiplayerSpawner.spawned only fires on remote peers, so the host
		## (and single player) centres on its own base here instead.
		if town_centers.has(my_peer_id()):
			_camera_centered_on_spawn = true
			_center_camera_on([town_centers[my_peer_id()]])

	## After _spawn_all_players(), so the starting bases are carved by the
	## very first bake instead of triggering a second one a poll later. A
	## joining client has none of that yet and picks them up as they replicate.
	_start_navigation_blockers()

	## The UI goes up before the quest is read, or the very first step's
	## dialogue is announced to a screen that does not exist yet and is lost —
	## which is every mission's opening line. It queues behind the briefing and
	## plays once that is closed.
	if scenario != null:
		quest_ui = QuestUi.new()
		quest_ui.main = self
		quest_ui.runner = quests
		ui_root.add_child(quest_ui)
	## After spawning, so a first step that counts what the team has starts
	## from the real numbers.
	quests.setup()

	feedback.setup()
	chat.setup()
	weather.setup()
	## After the weather, which the lighting reads its rain dimming from.
	day_night.setup()
	## After the map's resource nodes and player bases exist — the herds are
	## placed relative to both.
	wildlife.setup()

	var utility_buttons: VBoxContainer = $UI/BottomBar/UtilityButtons
	utility_buttons.get_node(^"IdleButton").pressed.connect(_select_all_idle_villagers)
	utility_buttons.get_node(^"FormationBoxButton").pressed.connect(_set_formation_type.bind(Formation.Type.BOX))
	utility_buttons.get_node(^"FormationLineButton").pressed.connect(_set_formation_type.bind(Formation.Type.LINE))
	utility_buttons.get_node(^"FormationStaggeredButton").pressed.connect(_set_formation_type.bind(Formation.Type.STAGGERED))
	_scale_bottom_bar()
	UiDebugEditor.register_editable_root(ui_root, "main")

	game_over_panel.visible = false
	$UI/GameOverPanel/Margin/VBox/ReturnButton.pressed.connect(_return_to_main_menu)
	_build_spectate_button()
	_build_next_mission_button()
	_build_rematch_button()
	_build_match_summary()
	_build_game_over_backdrop()

	Network.player_disconnected.connect(_on_network_player_disconnected)
	Network.server_disconnected.connect(_on_network_server_disconnected)
	_build_opponent_left_panel()
	placement.setup()

	pause_menu.visible = false
	pause_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	$UI/PauseMenu/Margin/VBox/ResumeButton.pressed.connect(_close_pause_menu)
	$UI/PauseMenu/Margin/VBox/OptionsButton.pressed.connect(_open_options_menu)
	$UI/PauseMenu/Margin/VBox/LeaveButton.pressed.connect(_return_to_main_menu)
	_options_menu = OPTIONS_MENU_SCENE.instantiate()
	_options_menu.visible = false
	_options_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	_options_menu.closed.connect(_open_pause_menu)
	ui_root.add_child(_options_menu)
	var pause_listener := PauseEscapeListener.new()
	pause_listener.main = self
	add_child(pause_listener)

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

	weather = Weather.new()
	weather.main = self
	weather.name = "Weather"
	add_child(weather)

	day_night = DayNight.new()
	day_night.main = self
	day_night.name = "DayNight"
	add_child(day_night)

	research = Research.new()
	research.main = self
	research.name = "Research"
	add_child(research)

	pacts = Pacts.new()
	pacts.main = self
	pacts.name = "Pacts"
	add_child(pacts)

	wildlife = Wildlife.new()
	wildlife.main = self
	wildlife.name = "Wildlife"
	add_child(wildlife)

	quests = QuestRunner.new()
	quests.main = self
	quests.name = "QuestRunner"
	add_child(quests)

## Single player only: the pause menu (and Options behind it) actually stops
## the match. With other humans in it the menu stays a local overlay.
func _open_pause_menu() -> void:
	## It sits above the pause menu in the UI.
	research_panel.close()
	pause_menu.visible = true
	if Network.is_single_player() and not game_over:
		get_tree().paused = true

func _close_pause_menu() -> void:
	pause_menu.visible = false
	get_tree().paused = false

## Main (and so its _unhandled_input) stops while the tree is paused, so Escape
## closing the pause menu needs a listener of its own that only runs then.
## Options handles its own Escape (see OptionsMenu._input).
class PauseEscapeListener extends Node:
	var main: Main

	func _init() -> void:
		process_mode = Node.PROCESS_MODE_WHEN_PAUSED

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE \
				and main.pause_menu.visible:
			main._close_pause_menu()
			get_viewport().set_input_as_handled()

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

## Humans first (host, then everyone connected), then AIs. Spawn points are
## shuffled each match so nobody is always at the same corner. More players
## than the map has spawn points is refused past the last point (AIs are
## the ones left out) rather than stacking two bases on one spot.
func _spawn_all_players() -> void:
	if scenario != null:
		_spawn_scenario_sides()
		return
	var peer_ids: Array = [1]
	if multiplayer.multiplayer_peer != null:
		peer_ids.append_array(multiplayer.get_peers())
	peer_ids.append_array(Network.ai_peer_ids())
	var spawn_count: int = player_spawn_points.get_child_count()
	if peer_ids.size() > spawn_count:
		push_warning("Main: %d players but only %d spawn points; extra players not spawned." % [peer_ids.size(), spawn_count])
		peer_ids.resize(spawn_count)
	var spawn_order: Array = range(spawn_count)
	spawn_order.shuffle()
	for i in peer_ids.size():
		_spawn_player_base(peer_ids[i], i, spawn_order[i])
		_grant_starting_resources(peer_ids[i])
	for peer_id in peer_ids:
		if Network.is_ai(peer_id):
			_start_ai_player(peer_id)

## Host only. Everyone opens a skirmish with the same purse, AI included —
## a scenario says what its own sides start with instead (see
## ScenarioSlot.starting_resources), so this is deliberately skipped there.
func _grant_starting_resources(peer_id: int) -> void:
	for resource_type in STARTING_RESOURCES:
		ResourceStockpile.add(peer_id, resource_type, STARTING_RESOURCES[resource_type])

## --- Scenario sides ---

## Each side's own modifiers, so prices and rosters are right from the first
## frame. Every peer does this: they all resolved the same sides.
func _apply_scenario_modifiers() -> void:
	var rules := MatchRules.active()
	var slots := scenario.slots()
	for i in slots.size():
		if scenario_peer_by_slot.has(i):
			rules.assign(scenario_peer_by_slot[i], slots[i].modifiers)

## Runs on every peer. Units and buildings a scenario placed by hand are in the
## scene file on all of them, so each peer gives them their owner and colour
## and moves them into the usual Units/Buildings containers — where the AI, the
## minimap and the fog all look for them. Nothing is spawned and nothing is
## sent; the result is identical everywhere because the scene is.
func _adopt_scenario_entities() -> void:
	var slots := scenario.slots()
	for i in slots.size():
		var peer_id: int = scenario_peer_by_slot.get(i, 0)
		var tint: Color = get_team_tint(peer_id) if peer_id > 0 else Objective.NEUTRAL_TINT
		for entity in slots[i].placed_entities():
			entity.owner_peer_id = peer_id
			entity.team_tint = tint
			## Remembered under the name it was authored with, which is what
			## quest steps refer to.
			scenario_entities[String(entity.name)] = entity
			## Renamed before the move so two slots can both hold a "Guard",
			## and named the same way on every peer so the NodePaths that
			## orders travel as still line up.
			entity.name = "Slot%d_%s" % [i, entity.name]
			if entity is Unit:
				entity.reparent(units_root, true)
				register_objective_unit(entity)
				_leash_defender(slots[i], entity)
			else:
				entity.reparent(buildings_root, true)
				_register_placed_building(entity)
			## Already in the tree, so the usual ready-hook in the spawn
			## functions can't do it.
			research.apply_all_to(entity)

## A garrison stays a garrison: a DEFENDERS unit will chase what attacks it,
## then come back to where it was put. The post is a node of its own because
## a unit can't be leashed to itself once it starts moving — the same
## arrangement Objective guards use.
func _leash_defender(slot: ScenarioSlot, unit: Unit) -> void:
	if slot.kind != ScenarioSlot.Kind.DEFENDERS or slot.defender_leash_radius <= 0.0:
		return
	var post := Node3D.new()
	post.name = "%sPost" % unit.name
	slot.add_child(post)
	post.global_position = unit.global_position
	unit.leash_origin = post
	unit.leash_radius = slot.defender_leash_radius

## The wiring _spawn_building_from_data gives a spawned building, for one placed
## by hand in a scenario — nothing spawned it, so nothing had connected it.
func _register_placed_building(building: ProductionBuilding) -> void:
	register_objective_building(building)
	building.construction_finished.connect(_on_building_construction_finished.bind(building))
	if not multiplayer.is_server() or building.owner_peer_id <= 0:
		return
	if building.is_main_base:
		main_base_count_by_peer[building.owner_peer_id] = main_base_count_by_peer.get(building.owner_peer_id, 0) + 1
	if building.is_main_base or not town_centers.has(building.owner_peer_id):
		town_centers[building.owner_peer_id] = building
	## Placed pre-built, so its population room is granted now rather than
	## waiting on a construction_finished that will never fire.
	if building.population_capacity > 0:
		Population.add_cap(building.owner_peer_id, building.population_capacity, building.population_pool)
		building.destroyed.connect(
			func(): Population.add_cap(building.owner_peer_id, -building.population_capacity, building.population_pool), CONNECT_ONE_SHOT
		)

## Host only. A side with a spawn point gets the usual starting base (from its
## own lists when it has them), every side gets its starting resources, and an
## ENEMY_AI side gets a brain. A DEFENDERS side deliberately never enters
## main_base_count_by_peer, so wiping out a garrison isn't a win condition —
## the quests decide that.
func _spawn_scenario_sides() -> void:
	var slots := scenario.slots()
	for i in slots.size():
		if not scenario_peer_by_slot.has(i):
			continue
		var slot: ScenarioSlot = slots[i]
		var peer_id: int = scenario_peer_by_slot[i]
		## An enemy's purse grows or shrinks with the campaign difficulty; the
		## player's stipend is whatever the mission says it is.
		## Asked of the scenario, not the quest runner: sides are set up before
		## the runner has read the quest.
		var purse: float = 1.0 if slot.team == scenario.player_team() else MatchRules.enemy_scale()
		for cost in slot.starting_resources:
			ResourceStockpile.add(peer_id, cost.resource_type, roundi(cost.amount * purse))
		if slot.spawn_point_index >= 0 and slot.spawn_point_index < player_spawn_points.get_child_count():
			_spawn_player_base(peer_id, i, slot.spawn_point_index, slot)
		## A brain for every side that isn't a person: the scenario's own AI
		## opponents, and any human seat an allied AI has taken (see
		## Scenario.resolve_players).
		if slot.kind == ScenarioSlot.Kind.ENEMY_AI or (slot.kind == ScenarioSlot.Kind.HUMAN and Network.is_ai(peer_id)):
			_start_ai_player(peer_id)
			var ai: AiPlayer = ai_players[peer_id]
			## Enemies and allies alike: an ally left on Normal plays its own
			## skirmish game (wandering off after capture points), so a mission
			## can instead send its armies to guard the village the quest is about.
			ai.mode = slot.ai_mode as AiPlayer.Mode
			if slot.attack_at != &"":
				ai.attack_position = scenario.position_of(slot.attack_at)

## Host-only: peer_id -> the AiPlayer brain playing that slot.
var ai_players: Dictionary = {}

func _start_ai_player(peer_id: int) -> void:
	var ai := AiPlayer.new()
	ai.name = "AiPlayer%d" % peer_id
	ai.setup(self, peer_id, Network.players[peer_id].get("difficulty", Network.AiDifficulty.NORMAL))
	add_child(ai)
	ai_players[peer_id] = ai

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

## Everyone plays the same roster — players differ by Ruler instead (see
## Ruler). Still a per-peer lookup so a Ruler-specific roster would only need
## to change this.
func _faction_for_peer(_peer_id: int) -> Faction:
	return available_factions[0]

## Gap between starting units placed past a spawn point's last unit marker —
## wider than two avoidance radii (see the spawn jitter note in
## _on_building_item_completed for what overlapping spawns do).
const EXTRA_START_UNIT_SPACING: float = 1.5

## team_index: join order, only used for get_team_tint's fallback colour.
## `slot` (scenarios only) replaces what the player starts with.
func _spawn_player_base(peer_id: int, team_index: int, spawn_index: int, slot: ScenarioSlot = null) -> void:
	var spawn_point: PlayerSpawnPoint = player_spawn_points.get_child(spawn_index)
	team_index_by_peer[peer_id] = team_index
	var tint: Color = get_team_tint(peer_id)
	var faction: Faction = _faction_for_peer(peer_id)
	faction_by_peer[peer_id] = faction
	var starting_units: Array[PackedScene] = faction.starting_units
	var starting_buildings: Array[PackedScene] = faction.starting_buildings
	if slot != null and not slot.starting_units.is_empty():
		starting_units = slot.starting_units
	if slot != null and not slot.starting_buildings.is_empty():
		starting_buildings = slot.starting_buildings

	## Free starting villagers never went through ProductionBuilding.enqueue()
	## (which is where population is normally reserved), so it has to be
	## reserved for them here instead or they'd stand outside the population
	## count entirely.
	## A map whose spawn points have fewer unit markers than the faction has
	## starting units still gets every unit: the extras stand in a short row
	## beside the last marker rather than being dropped.
	var unit_positions: Array[Vector3] = spawn_point.get_unit_positions()
	for i in starting_units.size():
		var pos: Vector3 = spawn_point.global_position
		if i < unit_positions.size():
			pos = unit_positions[i]
		elif not unit_positions.is_empty():
			pos = unit_positions[-1] + Vector3(EXTRA_START_UNIT_SPACING * (i - unit_positions.size() + 1), 0.0, 0.0)
		var starting_unit: Unit = unit_spawner.spawn({
			"scene_path": starting_units[i].resource_path,
			"peer_id": peer_id,
			"tint": tint,
			"position": pos,
		})
		Population.reserve(peer_id, starting_unit.population_cost)

	## A map/faction pairing can start a player with more than one building
	## (extra BuildingSpawns markers + a matching extra Faction.starting_buildings
	## entry) — town_centers[peer_id] is whichever one is flagged as the real
	## main base, not just whichever spawned first.
	var building_positions: Array[Vector3] = spawn_point.get_building_positions()
	for i in mini(starting_buildings.size(), building_positions.size()):
		var building: ProductionBuilding = building_spawner.spawn({
			"scene_path": starting_buildings[i].resource_path,
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
			Population.add_cap(peer_id, building.population_capacity, building.population_pool)
			building.destroyed.connect(
				func(): Population.add_cap(peer_id, -building.population_capacity, building.population_pool), CONNECT_ONE_SHOT
			)

func _spawn_unit_from_data(data: Dictionary) -> Node:
	var scene: PackedScene = load(data.scene_path)
	var unit: Unit = scene.instantiate()
	unit.owner_peer_id = data.peer_id
	unit.team_tint = data.tint
	unit.position = data.position
	unit.animation_changed.connect(feedback.on_unit_animation_changed.bind(unit))
	unit.work_role_swapped.connect(func(): feedback.spawn_rally_dust(unit.global_position))
	unit.projectile_fired.connect(feedback.on_unit_projectile_fired.bind(unit))
	unit.damaged.connect(feedback.relay_damage_number.bind(unit))
	unit.resource_deposited.connect(feedback.on_unit_resource_deposited.bind(unit))
	unit.resource_harvested.connect(feedback.on_unit_resource_harvested)
	unit.order_completed.connect(_on_unit_order_completed.bind(unit))
	unit.ability_cast.connect(_on_unit_ability_cast.bind(unit))
	unit.ability_launched.connect(feedback.relay_ability_launch.bind(unit))
	unit.status_applied.connect(feedback.relay_status_effects.bind(unit))
	## After Unit._ready has set its health, so research raises it from there.
	unit.ready.connect(research.apply_all_to.bind(unit), CONNECT_ONE_SHOT)
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
	unit.work_role_swapped.connect(func(): feedback.spawn_rally_dust(unit.global_position))
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
		building.ready.connect(research.apply_all_to.bind(building), CONNECT_ONE_SHOT)
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
		if not game_over and not disconnected_peers.has(peer_id) and Network.can_rpc_to(peer_id):
			_rpc_player_out.rpc_id(peer_id)

## Still in the running: not eliminated, still connected. Only an active
## player earns Favour (see Objective._tick_favour) or can win.
func is_peer_active(peer_id: int) -> bool:
	return peer_id > 0 and not defeated_peers.has(peer_id) and not disconnected_peers.has(peer_id)

## Last team standing — by elimination or by everyone else leaving. A player
## who loses their own last base is out (see _rpc_player_out), but their team
## plays on while any ally still holds one.
func _check_for_game_over() -> void:
	if game_over:
		return
	var all_peers: Array = main_base_count_by_peer.keys()
	## A mission's quest decides when it is won — so its closing lines play —
	## and a team wiped out loses it. The enemy is often a garrison with no
	## main base at all (DEFENDERS never count, see _spawn_scenario_sides), so
	## "last team standing" would never fire here: the players are the only
	## team with bases, and losing them all used to leave the match running.
	if scenario != null:
		var player_team: int = scenario.player_team()
		var seats: Array = all_peers.filter(func(p): return Teams.team_of(p) == player_team)
		if not seats.is_empty() and seats.filter(is_peer_active).is_empty():
			end_mission(false, player_team)
		return
	if Teams.teams_of(all_peers).size() <= 1:
		return
	var remaining: Array[int] = Teams.teams_of(all_peers.filter(is_peer_active))
	if remaining.size() <= 1:
		_end_game(remaining[0] if remaining.size() == 1 else DRAW)

## Run by the host at the start of every physics tick — before any Objective
## ticks, since Main is their ancestor — so everything banked during the
## previous tick is judged together: two players crossing the line on the
## same tick is a draw.
func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or game_over or not conquest_enabled or favour_target <= 0:
		return
	## A mission scores Favour for its quest to count; it only ends the match
	## by itself when the scenario asks for a plain race.
	var race_wins: bool = scenario == null or scenario.favour_race_wins
	var totals: Dictionary = _team_scores()
	_score_broadcast_timer -= delta
	if _score_broadcast_timer <= 0.0:
		_score_broadcast_timer = SCORE_BROADCAST_INTERVAL
		_rpc_scores.rpc(totals)
	if not race_wins:
		return
	var winners: Array = []
	for team in totals:
		if totals[team].active and totals[team].score >= favour_target:
			winners.append(team)
	if not winners.is_empty():
		_end_game(winners[0] if winners.size() == 1 else DRAW)

## A team nobody is on, so a mission lost by the player team shows everyone
## Defeat rather than crowning some enemy AI.
const NO_TEAM: int = -99

## A scenario's quest decided the outcome (see QuestRunner.end_mission). The
## player team wins or loses together.
func end_mission(victory: bool, player_team: int) -> void:
	if game_over:
		return
	_end_game(player_team if victory else NO_TEAM)

## `winner_team` is a Teams team id, or DRAW.
func _end_game(winner_team: int) -> void:
	game_over = true
	## One last push so every bar shows the finishing total, not the one from
	## up to a broadcast interval ago.
	if conquest_enabled:
		_broadcast_scores()
	_rpc_game_over.rpc(winner_team, _final_scoreboard(winner_team))

func _broadcast_scores() -> void:
	_rpc_scores.rpc(_team_scores())

## Each team's Favour (its members' totals added together), whether anyone on
## it is still in the running, and the colour it plays in — its members all
## share one, so the first member's tint stands for the team.
func _team_scores() -> Dictionary:
	var snapshot: Dictionary = {}
	for peer_id in main_base_count_by_peer.keys():
		var team: int = Teams.team_of(peer_id)
		if not snapshot.has(team):
			snapshot[team] = {score = 0, active = false, tint = get_team_tint(peer_id)}
		var entry: Dictionary = snapshot[team]
		entry.score += ResourceStockpile.get_amount(peer_id, FAVOUR_RESOURCE)
		entry.active = entry.active or is_peer_active(peer_id)
	return snapshot

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

## Host only: peer_id -> {name, team, tint}, taken as the match starts — a
## player who leaves mid-match is gone from Network.players by the end, but
## still belongs on the final scoreboard under the team they played for.
var _roster: Dictionary = {}

func _snapshot_roster() -> void:
	for peer_id in main_base_count_by_peer.keys():
		_roster[peer_id] = {
			name = Network.players.get(peer_id, {}).get("name", "Player %d" % peer_id),
			team = Teams.team_of(peer_id),
			tint = get_team_tint(peer_id),
		}

## One row per team, winner first then by Favour: {team, tint, names, score}.
func _final_scoreboard(winner_team: int) -> Array:
	var rows_by_team: Dictionary = {}
	for peer_id in main_base_count_by_peer.keys():
		var info: Dictionary = _roster.get(peer_id, {
			name = "Player %d" % peer_id, team = Teams.team_of(peer_id), tint = get_team_tint(peer_id)})
		if not rows_by_team.has(info.team):
			rows_by_team[info.team] = {team = info.team, tint = info.tint, names = [], score = 0}
		var row: Dictionary = rows_by_team[info.team]
		row.names.append(info.name)
		row.score += ResourceStockpile.get_amount(peer_id, FAVOUR_RESOURCE)
	var rows: Array = rows_by_team.values()
	rows.sort_custom(func(a, b):
		if (a.team == winner_team) != (b.team == winner_team):
			return a.team == winner_team
		return a.score > b.score)
	return rows

## Seconds of play, counted locally; stops while paused and once it's over.
var _match_seconds: float = 0.0

## Scoreboard and time played, between the title and the buttons.
var _summary_box: VBoxContainer = null
var _scoreboard: GridContainer = null
var _time_label: Label = null

func _build_match_summary() -> void:
	_summary_box = VBoxContainer.new()
	_summary_box.add_theme_constant_override("separation", 10)
	_summary_box.visible = false
	var divider: Control = $UI/GameOverPanel/Margin/VBox/TitleDivider
	divider.add_sibling(_summary_box)

	_scoreboard = GridContainer.new()
	_scoreboard.columns = 3
	_scoreboard.add_theme_constant_override("h_separation", 14)
	_scoreboard.add_theme_constant_override("v_separation", 6)
	_summary_box.add_child(_scoreboard)

	_time_label = Label.new()
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_label.add_theme_color_override("font_color", Color(0.72, 0.64, 0.46))
	_summary_box.add_child(_time_label)

func _fill_match_summary(board: Array, winner_team: int) -> void:
	for child in _scoreboard.get_children():
		child.queue_free()
	var my_team: int = Teams.team_of(my_peer_id())
	_scoreboard.columns = 3 if conquest_enabled else 2
	for row in board:
		var swatch := ColorRect.new()
		swatch.color = row.tint
		swatch.custom_minimum_size = Vector2(14, 14)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_scoreboard.add_child(swatch)

		var names := Label.new()
		names.text = ", ".join(row.names)
		names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		names.custom_minimum_size.x = 180
		names.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if row.team == my_team:
			names.add_theme_color_override("font_color", Color.WHITE)
		_scoreboard.add_child(names)

		if conquest_enabled:
			var score := Label.new()
			score.text = str(row.score)
			score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			score.add_theme_font_size_override("font_size", 20)
			if row.team == winner_team:
				score.add_theme_color_override("font_color", VICTORY_COLOR)
			_scoreboard.add_child(score)
	_scoreboard.visible = not board.is_empty()
	_time_label.text = "Time played: %s" % _format_duration(_match_seconds)
	_summary_box.visible = true

static func _format_duration(seconds: float) -> String:
	var total: int = int(seconds)
	if total >= 3600:
		return "%d:%02d:%02d" % [total / 3600, (total / 60) % 60, total % 60]
	return "%d:%02d" % [total / 60, total % 60]

## Replays this same map with the same players, rulers and settings. The host
## decides for everyone, as it does when starting a match from the lobby.
var _rematch_button: Button = null

func _build_rematch_button() -> void:
	_rematch_button = Button.new()
	_rematch_button.text = "Rematch"
	_rematch_button.visible = false
	_rematch_button.pressed.connect(_start_rematch)
	var return_button: Button = $UI/GameOverPanel/Margin/VBox/ReturnButton
	return_button.add_sibling(_rematch_button)
	return_button.get_parent().move_child(_rematch_button, return_button.get_index())

func _start_rematch() -> void:
	_rematch_button.disabled = true
	if Network.is_single_player():
		SceneLoader.change_scene(scene_file_path)
	else:
		SceneLoader.start_match(scene_file_path)

## Offered to a player knocked out of a match that's still going (see
## _rpc_player_out), and to everyone once the match ends (_rpc_game_over).
var _spectate_button: Button = null

## Offered on the victory screen when the mission just won has another after it
## — carrying on shouldn't mean a trip back through the menus. Single player
## only: in co-op one player cannot decide what everyone plays next.
var _next_mission_button: Button = null

func _build_next_mission_button() -> void:
	_next_mission_button = Button.new()
	_next_mission_button.visible = false
	var return_button: Button = $UI/GameOverPanel/Margin/VBox/ReturnButton
	return_button.add_sibling(_next_mission_button)
	return_button.get_parent().move_child(_next_mission_button, return_button.get_index())

func _offer_next_mission() -> void:
	if scenario == null or not Network.is_single_player():
		return
	var next: ScenarioInfo = Campaign.next_mission_after(Network.current_scenario_id)
	if next == null or next.scene_path.is_empty():
		return
	_next_mission_button.text = "Next: %s" % next.scenario_name
	_next_mission_button.visible = true
	_next_mission_button.pressed.connect(_start_next_mission.bind(next), CONNECT_ONE_SHOT)

func _start_next_mission(next: ScenarioInfo) -> void:
	Network.current_scenario_id = next.id
	SceneLoader.change_scene(next.scene_path)

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

## Result title colours: gold, blood red, and the theme's own parchment.
const VICTORY_COLOR := Color(1.0, 0.82, 0.36)
const DEFEAT_COLOR := Color(0.86, 0.29, 0.22)
const DRAW_COLOR := Color(0.863, 0.769, 0.486)

## Dims and blocks the battlefield behind the result panel. Follows the panel's
## visibility (Esc toggles it while spectating) rather than being driven
## separately.
var _game_over_backdrop: ColorRect = null
var _game_over_tween: Tween = null

func _build_game_over_backdrop() -> void:
	_game_over_backdrop = ColorRect.new()
	_game_over_backdrop.color = Color(0.02, 0.01, 0.0, 0.6)
	_game_over_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_game_over_backdrop.visible = false
	game_over_panel.add_sibling(_game_over_backdrop)
	game_over_panel.get_parent().move_child(_game_over_backdrop, game_over_panel.get_index())
	game_over_panel.pivot_offset_ratio = Vector2(0.5, 0.5)
	game_over_panel.visibility_changed.connect(_on_game_over_panel_visibility_changed)

func _on_game_over_panel_visibility_changed() -> void:
	_game_over_backdrop.visible = game_over_panel.visible
	if _game_over_tween != null:
		_game_over_tween.kill()
	if not game_over_panel.visible:
		return
	_game_over_backdrop.modulate.a = 0.0
	game_over_panel.modulate.a = 0.0
	game_over_panel.scale = Vector2(0.85, 0.85)
	_game_over_tween = create_tween().set_parallel()
	_game_over_tween.tween_property(_game_over_backdrop, "modulate:a", 1.0, 0.5)
	_game_over_tween.tween_property(game_over_panel, "modulate:a", 1.0, 0.3).set_delay(0.1)
	_game_over_tween.tween_property(game_over_panel, "scale", Vector2.ONE, 0.45).set_delay(0.1) 			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _set_result(text: String, color: Color) -> void:
	game_over_label.text = text
	game_over_label.add_theme_color_override("font_color", color)

@rpc("authority", "call_local", "reliable")
func _rpc_player_out() -> void:
	local_player_out = true
	_set_result("Defeat", DEFEAT_COLOR)
	_spectate_button.visible = true
	game_over_panel.visible = true
	## The host IS the server: quitting takes the match down for everyone
	## still playing, and there's no host migration to hand it off to.
	if multiplayer.is_server() and not multiplayer.get_peers().is_empty():
		$UI/GameOverPanel/Margin/VBox/ReturnButton.text = "Leave (ends the match for everyone)"

@rpc("authority", "call_local", "reliable")
func _rpc_game_over(winner_team: int, board: Array) -> void:
	game_over = true
	_spectate_button.visible = true
	_rematch_button.visible = Network.is_host() and not scene_file_path.is_empty()
	_fill_match_summary(board, winner_team)
	$UI/GameOverPanel/Margin/VBox/ReturnButton.text = "Return to Main Menu"
	var won := winner_team != DRAW and winner_team == Teams.team_of(my_peer_id())
	if winner_team == DRAW:
		_set_result("Draw!", DRAW_COLOR)
	elif won:
		_set_result("Victory!", VICTORY_COLOR)
		## Written down on each winner's own machine, so in co-op everyone who
		## played it has it unlocked afterwards. Recorded before the offer
		## below, which needs the next mission to be unlocked.
		if scenario != null:
			CampaignProgress.mark_completed(Network.current_scenario_id, Network.campaign_difficulty)
			_offer_next_mission()
	else:
		_set_result("Defeat", DEFEAT_COLOR)
	## A mission's closing lines are usually said as it ends — let the player
	## read them out before the result panel goes up over them.
	if quest_ui != null and quest_ui.is_presenting():
		game_over_panel.visible = false
		quest_ui.presentation_finished.connect(_reveal_result.bind(won), CONNECT_ONE_SHOT)
	else:
		_reveal_result(won)

func _reveal_result(won: bool) -> void:
	$MusicPlayer.play_outcome($MusicPlayer.victory_music if won else null)
	game_over_panel.visible = true

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
	quests.notify(&"point_captured", {peer_id = peer_id, letter = letter})
	var name_text: String = Network.players.get(peer_id, {}).get("name", "Player %d" % peer_id)
	for peer in _chat_recipients():
		chat.send_line(peer, "%s captured %s." % ["You" if peer == peer_id else name_text, letter])

func _on_network_server_disconnected() -> void:
	_show_opponent_left("Lost connection to host.")

## Host only. Feeds one of the owner's own units to the Altar that finished
## this item and pays them for it (see ProductionBuilding.sacrifice_victim).
## Nothing is paid if the victim wandered off while the rite was running.
func _resolve_sacrifice(item: ProducibleItem, building: ProductionBuilding) -> void:
	var victim: Unit = building.sacrifice_victim()
	if victim == null:
		chat.send_line(building.owner_peer_id, "Sacrifice failed: nobody at the altar.")
		return
	if building.sacrifice_resource != null and item.sacrifice_payout > 0:
		ResourceStockpile.add(building.owner_peer_id, building.sacrifice_resource, item.sacrifice_payout)
	## Killed by its own side: take_damage with no attacker, so it dies the
	## ordinary way (population released, corpse thrown, Pacts paid).
	victim.take_damage(victim.max_health * 100, null)

## Everything `peer_id` may place: their own roster first, then each allied
## race's buildings in the order their Pacts were made (see Pacts). Both the
## client asking to build and the host validating that request index into
## this same list — Pacts only ever append, so one sealed mid-request can't
## shift an index already in flight.
func buildable_types_for(peer_id: int) -> Array[BuildingType]:
	var types: Array[BuildingType] = []
	if faction_by_peer.has(peer_id):
		types.append_array(faction_by_peer[peer_id].building_types)
	for page in Pacts.building_pages(peer_id):
		types.append_array(page["buildings"])
	return types

func _on_building_item_completed(item: ProducibleItem, building: ProductionBuilding) -> void:
	if not multiplayer.is_server():
		return
	if item.kind != ProducibleItem.Kind.PACT:
		quests.notify(&"unit_trained" if item.kind == ProducibleItem.Kind.UNIT else &"upgrade_bought",
				{peer_id = building.owner_peer_id, item_name = item.item_name})
	if item.kind == ProducibleItem.Kind.PACT:
		if item.pact_race == null or not pacts.grant(building.owner_peer_id, item.pact_race.race_name):
			return
		## Recorded on the hall itself (and replicated) so the two races it
		## didn't ally with leave its menu for good.
		building.synced_pact_name = item.pact_race.race_name
		chat.send_line(building.owner_peer_id, "Pact sealed: %s" % item.pact_race.race_name)
		return
	if item.kind == ProducibleItem.Kind.SACRIFICE:
		_resolve_sacrifice(item, building)
		return
	if item.kind == ProducibleItem.Kind.UPGRADE:
		building._purchased_upgrades.append(item)
		## Extension point: a future upgrade effect is another optional flag
		## on ProducibleItem plus a matching `if` here.
		if item.upgrade_bonus != 0:
			UnitUpgrades.add_bonus(building.owner_peer_id, item.upgrade_category, item.upgrade_stat, item.upgrade_bonus)
		chat.send_line(building.owner_peer_id, "Upgrade complete: %s" % item.item_name)
		return
	if item.kind != ProducibleItem.Kind.UNIT or item.unit_scene == null:
		return
	var spawn_point: Node3D = building.get_node_or_null(building.spawn_point_path)
	var spawn_pos: Vector3 = spawn_point.global_position if spawn_point else building.global_position
	## A previously-spawned, un-ordered unit may still be standing exactly on the
	## spawn point; a small jitter keeps spawns from ever landing exactly on top
	## of each other, which separation can only part along an arbitrary angle.
	spawn_pos += Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.6, 0.6))
	## A Star Gate lands its unit on the rally point instead of walking it
	## there — but only where the owner can actually see, so the gate can't
	## drop troops into fog on the far side of the map.
	if building.teleports_produced_units and building.has_rally_point \
			and pacts.can_see_position(building.owner_peer_id, building.rally_point):
		spawn_pos = building.rally_point + Vector3(randf_range(-1.2, 1.2), 0.0, randf_range(-1.2, 1.2))
	## population_cost isn't passed here — the spawned scene's own Unit.population_cost
	## (set right on the unit for balancing, see get_population_cost()) is already authoritative.
	var unit: Unit = unit_spawner.spawn({
		"scene_path": item.unit_scene.resource_path,
		"peer_id": building.owner_peer_id,
		"tint": get_team_tint(building.owner_peer_id),
		"position": spawn_pos,
	})
	building.register_produced_unit(unit)
	## A litter: one cost, one build time, several bodies (Gnolls). The extras
	## are spawned here rather than queued so they arrive together; their
	## population was already reserved for the whole litter at enqueue time
	## (ProductionBuilding.population_for). Every one of them is rallied
	## below, not just the first — a pack that walked off one body at a time
	## was the whole point of training them as a litter.
	var litter: Array[Unit] = [unit]
	for i in range(1, maxi(item.spawn_count, 1)):
		var litter_pos := spawn_pos + Vector3(randf_range(-1.6, 1.6), 0.0, randf_range(-1.6, 1.6))
		var mate: Unit = unit_spawner.spawn({
			"scene_path": item.unit_scene.resource_path,
			"peer_id": building.owner_peer_id,
			"tint": get_team_tint(building.owner_peer_id),
			"position": litter_pos,
		})
		building.register_produced_unit(mate)
		litter.append(mate)
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
		for member in litter:
			var rally_pos := building.rally_point + Vector3(randf_range(-1.2, 1.2), 0.0, randf_range(-1.2, 1.2))
			_dispatch_smart_command(member, rally_target, rally_pos, false)

## Only ever fires host-side (construction progress is host-authoritative),
## so the chat line is sent explicitly to whichever peer owns the building
## rather than shown locally — same reasoning as the debug command replies
## above, just the message differs.
func _on_building_construction_finished(building: ProductionBuilding) -> void:
	feedback.relay_impact_shake(building.global_position, 0.25)
	if not multiplayer.is_server():
		return
	quests.notify(&"building_completed", {peer_id = building.owner_peer_id, building_name = building.building_name})
	chat.send_line(building.owner_peer_id, "Construction complete: %s" % building.building_name)
	if Network.can_rpc_to(building.owner_peer_id):
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
	if PerfStats.enabled:
		var hud_start := Time.get_ticks_usec()
		hud.update(delta)
		PerfStats.add_section(&"hud", Time.get_ticks_usec() - hud_start)
	else:
		hud.update(delta)
	placement.update()
	feedback.update_hover_ring()
	feedback.update_ability_target_decal()
	feedback.update_path_markers()
	_poll_formation_drag()
	if PerfStats.enabled:
		var start := Time.get_ticks_usec()
		group_movement.update_reformation(delta)
		PerfStats.add_section(&"march", Time.get_ticks_usec() - start)
	else:
		group_movement.update_reformation(delta)
	if not game_over:
		_match_seconds += delta

func _unhandled_input(event: InputEvent) -> void:
	if game_over or local_player_out:
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
		## Past the chat and menu guards, so a tutorial waiting on "press B"
		## isn't ticked off by typing one into the chat box.
		report_tutorial_input(&"hotkey", OS.get_keycode_string(event.keycode))

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

	if research_panel.visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		research_panel.close()
		get_viewport().set_input_as_handled()
		return

	## Fallback: nothing above claimed this Escape (not chatting, not
	## placing, no build submenu, no pending order, no Research panel), so it
	## opens the pause menu instead.
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
		## Whichever roster the menu is currently showing — the player's own,
		## or an allied race's on its Pact page.
		var my_building_types: Array[BuildingType] = hud.current_construction_types()
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
		elif event.keycode == UNIT_HOLD_KEY:
			toggle_hold_position()
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
	_formation_drag_shift_at_start = Input.is_key_pressed(KEY_SHIFT)
	_formation_drag_flipped = false

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
	_refresh_formation_drag_preview()

func _refresh_formation_drag_preview() -> void:
	_formation_drag_facing = group_movement.drag_facing(selected_units, _formation_drag_start_world, _formation_drag_end_world)
	if _formation_drag_flipped:
		_formation_drag_facing = -_formation_drag_facing
	feedback.show_formation_preview(group_movement.drag_preview_slots(
			selected_units, _formation_drag_start_world, _formation_drag_end_world, _formation_drag_facing),
			(_formation_drag_start_world + _formation_drag_end_world) * 0.5, _formation_drag_facing,
			_formation_drag_start_world.distance_to(_formation_drag_end_world))

## Never dragged far enough: exactly the right-click order the press used to
## issue on its own, from where the button went down.
func _finish_formation_drag(append: bool) -> void:
	if _formation_drag_active:
		_issue_formation_drag_order(_formation_drag_shift_at_start)
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
	if not _formation_drag_pressed:
		return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		## Polled rather than caught as a key event so a Shift tap flips the
		## preview at once, even with the mouse held still.
		var flipped := Input.is_key_pressed(KEY_SHIFT) != _formation_drag_shift_at_start
		if _formation_drag_active and flipped != _formation_drag_flipped:
			_formation_drag_flipped = flipped
			prune_selected_units()
			if not selected_units.is_empty():
				_refresh_formation_drag_preview()
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
	if not MatchRules.active().hud_allowed(my_peer_id(), "control_groups"):
		return
	report_tutorial_input(&"control_group", str(number))
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
	if not MatchRules.active().hud_allowed(my_peer_id(), "control_groups"):
		return
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

func _idle_villagers() -> Array[Unit]:
	var idle_villagers: Array[Unit] = []
	for node in get_tree().get_nodes_in_group("units"):
		var unit := node as Unit
		if unit and unit.owner_peer_id == my_peer_id() and unit.can_gather \
				and unit.status_activity == Unit.Activity.IDLE and unit.status_command == Unit.Command.NONE:
			idle_villagers.append(unit)
	return idle_villagers

## The utility bar's idle button: every idle gatherer at once, left where the
## camera is (they may be scattered across the map).
func _select_all_idle_villagers() -> void:
	var idle_villagers := _idle_villagers()
	if idle_villagers.is_empty():
		return

	for u in selected_units:
		u.selected = false
	selected_units.clear()
	select_building(null)
	select_resource(null)
	_active_group_number = -1

	for villager in idle_villagers:
		villager.selected = true
		selected_units.append(villager)
	_play_random_select_sound(idle_villagers)

func _select_next_idle_villager() -> void:
	var idle_villagers := _idle_villagers()
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

## Double-clicking one of your finished buildings adds every other finished
## building of yours with the same name that's on screen, so one Barracks'
## command panel trains from all of them. Anything else (an enemy building,
## one still going up) just gets the camera centred on it, as before.
func _select_all_visible_buildings_of_type(clicked: ProductionBuilding) -> void:
	if not can_command_building(clicked) or clicked.is_under_construction:
		_center_camera_on([clicked])
		return
	var group: Array[ProductionBuilding] = [clicked]
	var viewport_rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	for child in buildings_root.get_children():
		var building := child as ProductionBuilding
		if building == null or building == clicked or not can_command_building(building) \
				or building.building_name != clicked.building_name \
				or building.is_under_construction or building.is_destroyed \
				or camera.is_position_behind(building.global_position):
			continue
		if viewport_rect.has_point(camera.unproject_position(building.global_position)):
			group.append(building)
	if group.size() > 1:
		_set_building_group(group)

func _set_building_group(group: Array[ProductionBuilding]) -> void:
	selected_buildings = group
	feedback.show_building_group_rings(group)
	if selected_building != null:
		hud.show_building(selected_building)

## The group's buildings still standing, selected_building first; just
## [selected_building] when there's no group.
func selected_building_group() -> Array[ProductionBuilding]:
	var group: Array[ProductionBuilding] = []
	if selected_building == null or not is_instance_valid(selected_building):
		return group
	group.append(selected_building)
	for building in selected_buildings:
		if building != selected_building and is_instance_valid(building) and not building.is_destroyed:
			group.append(building)
	return group

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

## Tells the quest what the player just did, for the tutorial conditions that
## wait on it. Safe to call from anywhere and in any match: outside a scenario
## the runner drops it.
func report_tutorial_input(kind: StringName, detail: String = "") -> void:
	if quests != null:
		quests.report_input(kind, detail)

## Puts the camera over a spot — what a quest's camera pan uses.
func focus_camera_on(world_pos: Vector3) -> void:
	camera_rig.global_position.x = world_pos.x
	camera_rig.global_position.z = world_pos.z

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
				_select_all_visible_buildings_of_type(collider)
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
	_report_selection()

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
	elif result.collider is Unit and Teams.is_enemy(my_peer_id(), result.collider.owner_peer_id):
		return result.collider.get_path()
	## A friendly building under construction is also a valid target (to send
	## builders to it), and so is a friendly building with a linked_deposit
	## (e.g. a Mine — right-clicking the mine itself should still gather from
	## the deposit it sits on), alongside the existing enemy-building-attack case.
	elif result.collider is ProductionBuilding and \
			((Teams.is_enemy(my_peer_id(), result.collider.owner_peer_id) and result.collider.can_be_attacked()) \
				or result.collider.is_under_construction or is_instance_valid(result.collider.linked_deposit)):
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
			and Teams.is_enemy(my_peer_id(), collider.owner_peer_id):
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
## Whole bottom HUD (minimap, info/action panels, chat) shrinks by this.
const HUD_SCALE: float = 0.8

## Control.scale rather than resized offsets, so every panel, nine-patch and
## button inside keeps its authored proportions. Pivoted on the bottom-centre
## so the bar still hugs the screen's bottom edge, re-pivoted on resize.
func _scale_bottom_bar() -> void:
	var bottom_bar: Control = $UI/BottomBar
	bottom_bar.scale = Vector2.ONE * HUD_SCALE
	var repivot := func() -> void:
		bottom_bar.pivot_offset = Vector2(bottom_bar.size.x * 0.5, bottom_bar.size.y)
	repivot.call()
	bottom_bar.resized.connect(repivot)

func _set_formation_type(type: Formation.Type) -> void:
	if not MatchRules.active().hud_allowed(my_peer_id(), "formations"):
		return
	current_formation_type = type
	formation_label.text = "Formation: %s" % Formation.type_name(type)
	report_tutorial_input(&"formation", Formation.type_name(type))

func _issue_move_order(screen_pos: Vector2, append: bool = false) -> void:
	prune_selected_units()
	if selected_units.is_empty():
		return
	report_tutorial_input(&"move_order")
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

## Right-click on the minimap. There's no raycast to resolve a target from, so
## it's always a plain ground move, snapped onto the navmesh for a real ground
## height. Returns false when nothing of this player's own is selected, so the
## minimap falls back to a ping instead.
func issue_minimap_move_order(world_pos: Vector3, append: bool) -> bool:
	prune_selected_units()
	var unit_paths: Array[NodePath] = []
	for unit in selected_units:
		if unit.owner_peer_id == my_peer_id():
			unit_paths.append(unit.get_path())
	if unit_paths.is_empty():
		return false
	world_pos = NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, world_pos)
	_rpc_issue_command.rpc_id(1, unit_paths, NodePath(), world_pos, false, append, current_formation_type)
	play_command_sound()
	feedback.play_command_feedback(world_pos, false)
	feedback.spawn_command_popup("move", world_pos, feedback.command_speaker())
	_update_order_path_markers(world_pos, append)
	return true

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
	report_tutorial_input(&"attack_order")
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

## Turns hold position on for the whole selection unless every selected unit
## already holds, in which case it turns it off for all of them.
func toggle_hold_position() -> void:
	prune_selected_units()
	if selected_units.is_empty():
		return
	var unit_paths: Array[NodePath] = []
	for unit in selected_units:
		unit_paths.append(unit.get_path())
	_rpc_set_hold_position.rpc_id(1, unit_paths, not selection_holds_position())
	play_command_sound()

func selection_holds_position() -> bool:
	for unit in selected_units:
		if is_instance_valid(unit) and not unit.hold_position:
			return false
	return not selected_units.is_empty()

@rpc("any_peer", "call_local", "reliable")
func _rpc_set_hold_position(unit_paths: Array[NodePath], enabled: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = my_peer_id()
	for path in unit_paths:
		var unit := get_node_or_null(path) as Unit
		if unit != null and unit.owner_peer_id == sender_id:
			unit.hold_position = enabled

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
	issue_command_as(sender_id, unit_paths, target_path, world_pos, attack_move_fallback, append, formation_type, front_width, facing)

## Host only. The *_as() functions below are where each order RPC ends up
## once the sender is known, and what an AI player (see AiPlayer) calls
## directly with its own peer id — so an AI's orders pass exactly the same
## ownership/cost checks a human's do.
func issue_command_as(sender_id: int, unit_paths: Array[NodePath], target_path: NodePath, world_pos: Vector3, attack_move_fallback: bool, append: bool, formation_type: Formation.Type = Formation.DEFAULT_TYPE, front_width: float = -1.0, facing: Vector3 = Vector3.ZERO) -> void:
	if not multiplayer.is_server():
		return
	var perf_start := Time.get_ticks_usec() if PerfStats.enabled else 0
	## Client-supplied, so flattened and renormalized rather than trusted as-is.
	facing.y = 0.0
	facing = facing.normalized() if facing.length_squared() > 0.0001 else Vector3.ZERO

	var target_node: Node = get_node_or_null(target_path) if target_path != NodePath() else null

	var units: Array[Unit] = []
	for path in unit_paths:
		var unit := get_node_or_null(path) as Unit
		if unit != null and unit.owner_peer_id == sender_id:
			units.append(unit)

	## A ranged group ordered onto an enemy attacks as a block (see
	## GroupMovement.formation_attack). A shift-queued attack still queues
	## per unit below.
	if not append and target_node != null and group_movement.can_formation_attack(units, target_node):
		front_width = group_movement.resolve_dragged_width(units, formation_type, front_width)
		for unit in units:
			unit.clear_order_queue()
		group_movement.formation_attack(units, target_node, formation_type, front_width)
		for unit in units:
			feedback.play_unit_order_sound(unit, Unit.OrderSoundKind.ATTACK)
		if PerfStats.enabled:
			PerfStats.record_command((Time.get_ticks_usec() - perf_start) / 1000.0, units.size())
		return

	## A group the player laid out by right-dragging keeps that shape for its
	## later click orders too, rather than snapping back to the selected type.
	if target_node == null:
		front_width = group_movement.resolve_dragged_width(units, formation_type, front_width)
	## Resolved once here so the slots, the march and ranks closing later all
	## share one facing (see GroupMovement.order_facing).
	facing = group_movement.order_facing(units, world_pos, facing)
	var formation_positions := group_movement.formation_positions(units, world_pos, formation_type, facing, front_width)
	## Chokepoints are handled by the march itself (see register_formation
	## below and GroupMovement's Marching section), which squeezes the block
	## into a column wherever the route narrows.
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
	## Reformation bookkeeping: remember this group's destination and shape so
	## the host can close ranks around whoever is still walking it when members
	## die en route (see update_reformation). Registered from the units'
	## post-dispatch state rather than blindly from `units` — a shift-queued
	## member hasn't started this leg yet, and a gather/attack/build target
	## ignores formation slots entirely, so neither belongs in a record whose
	## whole job is re-solving move slots.
	group_movement.register_formation(cohesion_group, world_pos, formation_type, attack_move_fallback, facing, front_width)
	if attack_move_fallback and target_node == null and not append:
		_engage_at_attack_move_destination(units, world_pos, sender_id)
	if PerfStats.enabled:
		PerfStats.record_command((Time.get_ticks_usec() - perf_start) / 1000.0, units.size())

## An attack-move onto ground that already has enemies standing on it is an
## order to take *them* on, not to walk to the spot and only then turn round:
## the units go for the nearest one straight away, exactly as they would if
## they had met it on the march (GroupMovement.formation_contact for a group,
## a keep_assault attack for a lone unit). The assault survives either way, so
## the rest of the area is still cleared once that target is down.
func _engage_at_attack_move_destination(units: Array[Unit], world_pos: Vector3, sender_id: int) -> void:
	var marchers: Array[Unit] = []
	for unit in units:
		if unit.status_command == Unit.Command.ATTACK_MOVE and unit.assault_active:
			marchers.append(unit)
	if marchers.is_empty():
		return
	var enemy := _nearest_enemy_at(world_pos, sender_id)
	if enemy == null:
		return
	## One of these brings the whole block round; all false means there's no
	## group to bring (a lone unit, or a target it can't formation-attack), so
	## each marcher goes in on its own.
	for unit in marchers:
		if group_movement.formation_contact(unit, enemy):
			return
	for unit in marchers:
		unit.command_attack(enemy, true)

## Nearest enemy of `owner` standing inside the assault area a click at
## `point` would cover — a unit if there is one, otherwise an attackable
## building, matching how Unit._find_assault_target picks once the area is
## reached.
func _nearest_enemy_at(point: Vector3, owner: int) -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	for unit in UnitGrid.enemies_near(get_tree(), point, Unit.ASSAULT_AREA_RADIUS, owner):
		if not CombatUtils.is_worth_attacking(unit):
			continue
		var distance := Vector2(point.x - unit.global_position.x, point.z - unit.global_position.z).length()
		if distance < best_distance:
			best = unit
			best_distance = distance
	if best != null:
		return best
	for node in get_tree().get_nodes_in_group(&"buildings"):
		var building := node as ProductionBuilding
		if building == null or building.is_destroyed or not building.can_be_attacked() \
				or not Teams.is_enemy(owner, building.owner_peer_id):
			continue
		var distance := Vector2(point.x - building.global_position.x, point.z - building.global_position.z).length() \
				- building.get_footprint_radius()
		if distance > Unit.ASSAULT_AREA_RADIUS or distance >= best_distance:
			continue
		best = building
		best_distance = distance
	return best

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
	var front_width: float = group_movement.resolve_dragged_width(units, formation_type, -1.0)
	group_movement.reform_group(units, centroid, formation_type, false, facing, front_width)
	group_movement.register_formation(units, centroid, formation_type, false, facing, front_width)

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
	elif target_node is ProductionBuilding and is_instance_valid(target_node.linked_deposit) \
			and not target_node.is_under_construction and target_node.linked_deposit.can_be_gathered():
		unit.command_gather(target_node.linked_deposit, _get_dropoff_for(unit.owner_peer_id))
		feedback.play_unit_order_sound(unit, Unit.OrderSoundKind.GATHER)
	elif (target_node is Unit or (target_node is ProductionBuilding and target_node.can_be_attacked())) \
			and Teams.is_enemy(unit.owner_peer_id, target_node.owner_peer_id):
		unit.clear_work_role()
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
	issue_patrol_as(sender_id, unit_paths, world_pos, append)

func issue_patrol_as(sender_id: int, unit_paths: Array[NodePath], world_pos: Vector3, append: bool) -> void:
	if not multiplayer.is_server():
		return
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
	issue_stop_as(sender_id, unit_paths)

func issue_stop_as(sender_id: int, unit_paths: Array[NodePath]) -> void:
	if not multiplayer.is_server():
		return
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
		"power":
			## Only somewhere the player can currently see; a miss keeps the
			## power armed for another try, like a blocked building placement.
			var result := raycast(event.position)
			if result.is_empty() or not fog_of_war.is_visible_at(result.position):
				play_placement_blocked_sound()
				return
			pending_order_mode = ""
			research.request_cast(_armed_power_index, result.position)
			play_command_sound()
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
	if not selected_buildings.is_empty():
		selected_buildings.clear()
		feedback.show_building_group_rings(selected_buildings)
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
	_report_selection()

## A tutorial step can wait for "select a villager": the detail is what was
## picked, so a step can ask for a particular sort of unit.
func _report_selection() -> void:
	if not selected_units.is_empty():
		report_tutorial_input(&"select_units", selected_units[0].display_name)

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
		if not selected_buildings.is_empty():
			selected_buildings.clear()
			feedback.show_building_group_rings(selected_buildings)
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

## Same shape as arm_ability: refuses silently while the power is cooling down.
func arm_power(node_index: int) -> void:
	if research.power_cooldown_remaining_fraction(node_index) > 0.0:
		return
	_armed_power_index = node_index
	pending_order_mode = "power"
	play_command_sound()

## The power the next left-click will cast, or null — read every frame by
## WorldFeedback for the targeting ring.
func get_armed_power() -> ResearchNode:
	if pending_order_mode != "power" or _armed_power_index < 0:
		return null
	var ruler := Research.ruler_for(my_peer_id())
	return ruler.nodes[_armed_power_index] if ruler != null and _armed_power_index < ruler.nodes.size() else null

func on_producible_button_pressed(building: ProductionBuilding, item_index: int) -> void:
	var item := building.producibles[item_index]
	## Hotkeys come straight here, bypassing the greyed-out button.
	if item.kind == ProducibleItem.Kind.UNIT and building.synced_unit_limit_reached:
		return
	var costs := building.costs_for(item)
	if not hud.can_afford_locally(costs):
		hud.flash_missing_resources(costs)
		return
	## Upgrades are bought per building, so only units are spread over a group.
	var group: Array[ProductionBuilding] = []
	if building == selected_building:
		group = selected_building_group()
	if item.kind == ProducibleItem.Kind.UNIT and group.size() > 1:
		var paths: Array[NodePath] = []
		for member in group:
			paths.append(member.get_path())
		_rpc_enqueue_in_group.rpc_id(1, paths, item.item_name)
	else:
		_rpc_enqueue.rpc_id(1, building.get_path(), item_index)
	play_command_sound()

## Host picks whichever building in the group has the shortest queue (the
## first listed on a tie), so repeated clicks deal one unit to each in turn —
## decided here rather than on the client, whose synced queue sizes lag
## behind a quick run of clicks. Matched by name, not index, in case a
## building's menu differs from the one the player was looking at.
@rpc("any_peer", "call_local", "reliable")
func _rpc_enqueue_in_group(building_paths: Array[NodePath], item_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = my_peer_id()
	var candidates: Array[ProductionBuilding] = []
	for path in building_paths:
		var building := get_node_or_null(path) as ProductionBuilding
		if building != null and building.owner_peer_id == sender_id:
			candidates.append(building)
	## Stable sort by queue length: sort_custom isn't stable, so ties are
	## broken on original order explicitly.
	var order: Array[int] = []
	for i in candidates.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		var qa: int = candidates[a].queue.size()
		var qb: int = candidates[b].queue.size()
		return qa < qb or (qa == qb and a < b))
	for i in order:
		var building := candidates[i]
		for item in building.producibles:
			if item.item_name == item_name:
				if building.enqueue(item):
					return
				break

@rpc("any_peer", "call_local", "reliable")
func _rpc_enqueue(building_path: NodePath, item_index: int) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = my_peer_id()
	enqueue_as(sender_id, building_path, item_index)

## Returns whether it actually went into the queue.
func enqueue_as(sender_id: int, building_path: NodePath, item_index: int) -> bool:
	if not multiplayer.is_server():
		return false
	var building := get_node_or_null(building_path) as ProductionBuilding
	if building == null or building.owner_peer_id != sender_id:
		return false
	if item_index < 0 or item_index >= building.producibles.size():
		return false
	return building.enqueue(building.producibles[item_index])

## On a group, every building ends up matching what the clicked one is
## switching to — only those not already there are toggled.
func toggle_repeat_production(building: ProductionBuilding, item_index: int) -> void:
	var item_name := building.producibles[item_index].item_name
	var turning_on := building.synced_repeat_item_name != item_name
	var group: Array[ProductionBuilding] = [building]
	if building == selected_building:
		group = selected_building_group()
	for member in group:
		if member == building or (member.synced_repeat_item_name == item_name) != turning_on:
			for i in member.producibles.size():
				if member.producibles[i].item_name == item_name:
					_rpc_toggle_repeat.rpc_id(1, member.get_path(), i)
					break
	play_command_sound()

@rpc("any_peer", "call_local", "reliable")
func _rpc_toggle_repeat(building_path: NodePath, item_index: int) -> void:
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
	building.toggle_repeat(building.producibles[item_index])

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
	cancel_production_as(sender_id, building_path, queue_index)

func cancel_production_as(sender_id: int, building_path: NodePath, queue_index: int) -> void:
	if not multiplayer.is_server():
		return
	var building := get_node_or_null(building_path) as ProductionBuilding
	if building == null or building.owner_peer_id != sender_id:
		return
	building.cancel_at(queue_index)

## --- Abilities ---

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
	request_ability_as(sender_id, unit_path, ability_index, target_pos)

## Returns whether the cast order was accepted.
func request_ability_as(sender_id: int, unit_path: NodePath, ability_index: int, target_pos: Vector3) -> bool:
	if not multiplayer.is_server():
		return false
	var unit := get_node_or_null(unit_path) as Unit
	if unit == null or unit.owner_peer_id != sender_id:
		return false
	var ability: Ability = unit.get_ability(ability_index)
	if ability == null or not ability.is_activated() or not unit.is_ability_ready(ability_index):
		return false
	if not ResourceStockpile.can_afford(sender_id, ability.costs):
		return false
	unit.clear_order_queue()
	unit.command_cast_ability(ability_index, target_pos)
	return true

## Host-only (Unit.ability_cast only fires there). Tells the owner when the
## ability comes back so their HUD can grey it out, and shows everyone the
## caster winding up. The projectile and impact follow later, off
## Unit.ability_launched (see WorldFeedback.relay_ability_launch).
func _on_unit_ability_cast(ability_index: int, _target_pos: Vector3, unit: Unit) -> void:
	var ability: Ability = unit.get_ability(ability_index)
	if ability == null:
		return
	## Peer 0 is "neutral", not a real peer — rpc_id(0) would broadcast. An
	## AI has no machine to tell; its brain reads the host-side cooldown.
	if Network.can_rpc_to(unit.owner_peer_id):
		_rpc_ability_cooldown_started.rpc_id(unit.owner_peer_id, unit.get_path(), ability_index, unit.ability_cooldown(ability))
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
	for building in selected_building_group():
		building.rally_point = result.position
		building.rally_target_path = target_path
		building.has_rally_point = true
		_rpc_set_rally_point.rpc_id(1, building.get_path(), result.position, target_path)
	feedback.update_rally_marker()
	feedback.spawn_rally_dust(result.position)
	AudioUtils.play_random(command_audio_player, on_rally_set_sound_effects)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_rally_point(building_path: NodePath, world_pos: Vector3, target_path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = my_peer_id()
	set_rally_point_as(sender_id, building_path, world_pos, target_path)

func set_rally_point_as(sender_id: int, building_path: NodePath, world_pos: Vector3, target_path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	var building := get_node_or_null(building_path) as ProductionBuilding
	if building == null or building.owner_peer_id != sender_id or not building.can_rally:
		return
	building.rally_point = world_pos
	building.rally_target_path = target_path
	building.has_rally_point = true
