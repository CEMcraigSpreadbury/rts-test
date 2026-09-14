class_name QuestRunner
extends Node
## Runs a scenario's quest: works out which steps are active, watches their
## conditions, fires their actions, and tells every player where things stand.
##
## Host-authoritative, the same shape as Research: only the host evaluates
## anything or runs an action, and the resulting state is broadcast so every
## client's tracker (step 4) draws the same thing. That is also what makes
## co-op work — the team shares one quest, and counting is team-wide.

## The state snapshot changed; the tracker redraws off this.
signal changed
## Something for the players to see (a line of dialogue, a camera pan). Step 4
## hangs the UI off this; until then it simply goes nowhere.
signal presentation(payload: Dictionary)

const POLL_INTERVAL: float = 0.25

var main: Main
var scenario: Scenario = null
## In authored order; a step's index here is its id in every snapshot.
var steps: Array[QuestStep] = []
## index -> QuestStep.State, on every peer.
var states: Dictionary = {}
## index -> PackedInt32Array laid out [current, target, current, target, ...],
## one pair per condition. On every peer.
var progress: Dictionary = {}
## Match time in seconds, host-side (conditions only ever run there).
var time: float = 0.0
var mission_over: bool = false
## True while the host has a line of dialogue or a briefing on screen: the
## quest stops advancing behind it, so the step a line announces can't complete
## and fire its own lines before the player has read the first one. Match time
## holds too, so a deadline doesn't tick away while someone is reading. Set by
## QuestUi, and only on the host — in co-op one player reading must not stop
## the mission for everyone.
var presentation_hold: bool = false

var _poll: float = 0.0
## Copies, so a condition that counts events can hold its own tally and two
## steps sharing one authored resource never cross wires.
var _conditions: Dictionary = {}
var _fail_conditions: Dictionary = {}
## index -> the match time the step became active (what a deadline measures).
var _started_at: Dictionary = {}
var _player_team: int = 1

func setup() -> void:
	scenario = main.scenario
	if scenario == null:
		return
	_player_team = scenario.player_team()
	var root: Node = scenario.get_node_or_null(^"Quests")
	if root == null:
		root = scenario
	for child in root.get_children():
		if child is QuestStep:
			steps.append(child)
	for i in steps.size():
		states[i] = QuestStep.State.LOCKED
		progress[i] = PackedInt32Array()
		_conditions[i] = _copies(steps[i].conditions)
		_fail_conditions[i] = _copies(steps[i].fail_conditions)
	if multiplayer.is_server():
		_evaluate()

func _copies(list: Array[QuestCondition]) -> Array[QuestCondition]:
	var out: Array[QuestCondition] = []
	for condition in list:
		if condition != null:
			out.append(condition.duplicate())
	return out

func _physics_process(delta: float) -> void:
	if scenario == null or not multiplayer.is_server() or mission_over or main.game_over:
		return
	if presentation_hold:
		return
	time += delta
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = POLL_INTERVAL
	_evaluate()

## --- Evaluation (host only) ---

func _evaluate() -> void:
	var dirty := false
	for i in steps.size():
		if states[i] == QuestStep.State.LOCKED and _requirements_met(i):
			_activate(i)
			dirty = true
	for i in steps.size():
		if states[i] != QuestStep.State.ACTIVE:
			continue
		if _any_met(_fail_conditions[i]):
			_finish(i, QuestStep.State.FAILED)
			dirty = true
			continue
		var pairs := PackedInt32Array()
		var met_count := 0
		for condition in _conditions[i]:
			var p: Vector2i = condition.progress(self)
			pairs.append(p.x)
			pairs.append(p.y)
			if p.x >= p.y:
				met_count += 1
		if pairs != progress[i]:
			progress[i] = pairs
			dirty = true
		var total: int = _conditions[i].size()
		var done: bool = met_count >= total if steps[i].completion == QuestStep.Completion.ALL else met_count > 0
		## A step with no conditions at all is pure plumbing: it fires its
		## actions and completes at once.
		if total == 0 or done:
			_finish(i, QuestStep.State.COMPLETE)
			dirty = true
	if dirty:
		_broadcast()

## Complete already, or an optional step that failed — either way it no longer
## holds anything up. A failed required step does hold its dependants back.
func _requirements_met(index: int) -> bool:
	var step := steps[index]
	for path in step.requires:
		var other := _index_of(step.get_parent().get_node_or_null(path))
		if other < 0:
			continue
		if states[other] == QuestStep.State.COMPLETE:
			continue
		if states[other] == QuestStep.State.FAILED and steps[other].optional:
			continue
		return false
	return true

func _index_of(node: Node) -> int:
	if node == null:
		return -1
	return steps.find(node)

func _activate(index: int) -> void:
	states[index] = QuestStep.State.ACTIVE
	_started_at[index] = time
	for condition in _conditions[index]:
		condition.setup(self)
	for condition in _fail_conditions[index]:
		condition.setup(self)
	_run(steps[index].on_start)

func _finish(index: int, state: QuestStep.State) -> void:
	states[index] = state
	if state == QuestStep.State.COMPLETE:
		_run(steps[index].on_complete)
	else:
		_run(steps[index].on_fail)

func _any_met(conditions: Array[QuestCondition]) -> bool:
	for condition in conditions:
		if condition.is_met(self):
			return true
	return false

func _run(actions: Array[QuestAction]) -> void:
	for action in actions:
		if action != null:
			action.run(self)

## When a step became active — what a deadline condition counts from.
func started_at(condition: QuestCondition) -> float:
	for i in steps.size():
		if _conditions.get(i, []).has(condition) or _fail_conditions.get(i, []).has(condition):
			return _started_at.get(i, 0.0)
	return 0.0

## --- Things that happen (host only) ---

## Called by Main as the match plays: a unit was trained, a building finished,
## something died, a capture point changed hands. Only conditions that count
## events care; everything else is polled.
func notify(event: StringName, data: Dictionary = {}) -> void:
	if scenario == null or not multiplayer.is_server() or mission_over:
		return
	for i in steps.size():
		if states[i] != QuestStep.State.ACTIVE:
			continue
		for condition in _conditions[i]:
			condition.on_event(self, event, data)
		for condition in _fail_conditions[i]:
			condition.on_event(self, event, data)

## The local player did something a tutorial might be waiting for — selected
## units, moved the camera, pressed a hotkey. Input happens on each player's own
## machine, so a client tells the host and the host turns it into an ordinary
## event. Nothing is validated beyond who sent it: a tutorial step is not worth
## cheating at, and the worst case is a player ticking off their own objective.
func report_input(kind: StringName, detail: String = "") -> void:
	if scenario == null or mission_over:
		return
	if multiplayer.is_server():
		notify(&"player_input", {peer_id = main.my_peer_id(), kind = kind, detail = detail})
	else:
		_rpc_input.rpc_id(1, kind, detail)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_input(kind: StringName, detail: String) -> void:
	if multiplayer.is_server():
		notify(&"player_input", {peer_id = multiplayer.get_remote_sender_id(), kind = kind, detail = detail})

## Ends the mission for everyone. Victory is judged for the player team, so a
## co-op team wins or loses together.
func end_mission(victory: bool) -> void:
	if mission_over or main.game_over:
		return
	mission_over = true
	_broadcast()
	main.end_mission(victory, player_team())

## --- Sharing state ---

func _broadcast() -> void:
	var snapshot: Dictionary = {}
	for i in steps.size():
		snapshot[i] = {state = states[i], progress = progress[i]}
	_rpc_state.rpc(snapshot)

@rpc("authority", "call_local", "reliable")
func _rpc_state(snapshot: Dictionary) -> void:
	for i in snapshot:
		states[i] = snapshot[i].state
		progress[i] = snapshot[i].progress
	changed.emit()

## Host -> everyone on the player team: something to show (step 4 renders it).
func show_to_players(payload: Dictionary) -> void:
	_rpc_presentation.rpc(payload)

@rpc("authority", "call_local", "reliable")
func _rpc_presentation(payload: Dictionary) -> void:
	presentation.emit(payload)

## --- Changes every peer has to hear about ---

## Placed entities aren't replicated by a spawner (each peer worked out their
## owner for itself), so handing one over mid-mission has to be told to
## everyone rather than set on the host alone.
func set_entity_owner(entity_name: String, peer_id: int) -> void:
	_rpc_entity_owner.rpc(entity_name, peer_id)

@rpc("authority", "call_local", "reliable")
func _rpc_entity_owner(entity_name: String, peer_id: int) -> void:
	var entity = main.scenario_entities.get(entity_name, null)
	if not is_instance_valid(entity):
		return
	entity.owner_peer_id = peer_id
	entity.team_tint = main.get_team_tint(peer_id) if peer_id > 0 else Objective.NEUTRAL_TINT

## Rules are held per peer (the menus read them locally), so unlocks travel
## too. `research_tier_cap` of -2 leaves the cap alone.
func set_unlocks(peer_id: int, unlock_buildings: Array[String], lock_buildings: Array[String],
		unlock_items: Array[String], lock_items: Array[String], research_tier_cap: int,
		unlock_hud: Array[String] = [], lock_hud: Array[String] = []) -> void:
	_rpc_unlocks.rpc(peer_id, unlock_buildings, lock_buildings, unlock_items, lock_items,
			research_tier_cap, unlock_hud, lock_hud)

@rpc("authority", "call_local", "reliable")
func _rpc_unlocks(peer_id: int, unlock_buildings: Array, lock_buildings: Array,
		unlock_items: Array, lock_items: Array, research_tier_cap: int,
		unlock_hud: Array, lock_hud: Array) -> void:
	var modifiers := MatchRules.active().editable_modifiers_for(peer_id)
	modifiers.allowed_buildings = _edited(modifiers.allowed_buildings, unlock_buildings, lock_buildings, _every_building_name())
	modifiers.allowed_items = _edited(modifiers.allowed_items, unlock_items, lock_items, [])
	if research_tier_cap > -2:
		modifiers.research_tier_cap = research_tier_cap
	## The HUD list works the other way round from the allowed lists: it names
	## what is taken away, so unlocking removes and locking adds.
	var hud_locks: Array[String] = modifiers.locked_hud.duplicate()
	for feature in unlock_hud:
		hud_locks.erase(String(feature))
	for feature in lock_hud:
		if not hud_locks.has(String(feature)):
			hud_locks.append(String(feature))
	modifiers.locked_hud = hud_locks
	## The build menu is only rebuilt when the selection changes, so a mid-
	## mission unlock would otherwise not show until the player clicked away.
	if peer_id == main.my_peer_id():
		if main.hud != null:
			main.hud.refresh_command_panel()
		if main.power_bar != null:
			main.power_bar._rebuild()

## An empty allowed list means "everything", so adding to one changes nothing,
## and taking something away has to write the full roster out first —
## `everything` is that roster, where one is known (buildings), or empty
## (producibles, which differ per building) in which case locking only works
## for a side that already has an allowed list.
func _edited(current: Array[String], add: Array, remove: Array, everything: Array[String]) -> Array[String]:
	var out: Array[String] = current.duplicate()
	if out.is_empty() and not remove.is_empty():
		out = everything.duplicate()
	if not out.is_empty():
		for entry in add:
			if not out.has(entry):
				out.append(entry)
	for entry in remove:
		out.erase(entry)
	return out

func _every_building_name() -> Array[String]:
	var names: Array[String] = []
	var faction: Faction = main.my_faction()
	if faction != null:
		for building_type in faction.building_types:
			names.append(building_type.building_name)
	return names

## --- Helpers for conditions and actions ---

func player_team() -> int:
	return _player_team

func player_peers() -> Array[int]:
	return Teams.peers_on_team(_player_team)

## The peer playing a scenario slot, or 0 for a slot nobody filled.
func peer_for_slot(slot_index: int) -> int:
	return main.scenario_peer_by_slot.get(slot_index, 0)

## Every living unit on a team (the player team by default).
func team_units(team: int = -1) -> Array[Unit]:
	var wanted: int = team if team >= 0 else _player_team
	var out: Array[Unit] = []
	for node in get_tree().get_nodes_in_group(&"units"):
		var unit := node as Unit
		if unit != null and unit.status_activity != Unit.Activity.DEAD \
				and Teams.team_of(unit.owner_peer_id) == wanted:
			out.append(unit)
	return out

func team_buildings(team: int = -1) -> Array[ProductionBuilding]:
	var wanted: int = team if team >= 0 else _player_team
	var out: Array[ProductionBuilding] = []
	for node in get_tree().get_nodes_in_group(&"buildings"):
		var building := node as ProductionBuilding
		if building != null and not building.is_destroyed \
				and Teams.team_of(building.owner_peer_id) == wanted:
			out.append(building)
	return out

func zone(zone_name: StringName) -> ScenarioZone:
	return scenario.zone(zone_name) if scenario != null else null

## A named zone's centre, a named marker's position, or ZERO.
func position_of(place_name: StringName) -> Vector3:
	return scenario.position_of(place_name) if scenario != null else Vector3.ZERO

## Host only: changes what an AI side is doing (see AiPlayer.Mode). The brains
## only exist on the host, so nothing has to be sent anywhere.
func set_ai_mode(slot_index: int, mode: int, at: StringName = &"") -> void:
	var ai = main.ai_players.get(peer_for_slot(slot_index), null)
	if ai == null:
		return
	ai.mode = mode
	if at != &"":
		ai.attack_position = position_of(at)
