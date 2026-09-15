class_name Scenario
extends Node3D
## Root of a scenario: a scene that inherits an ordinary map and adds this node
## with the sides, zones, markers and (from step 3) quest steps under it.
##
## Main finds this node by itself, so loading a scenario is just loading its
## scene — there is no separate mode to switch on.

@export var scenario_name: String = "Scenario"
@export var briefing_title: String = ""
@export_multiline var briefing_text: String = ""
## Favour is not scored in a scenario unless a mission wants it: points pay it
## and the Conquest bar shows it. Quest steps can then count it (FavourCondition).
@export var favour_enabled: bool = false
## The mark the Conquest bar measures towards. 0 = the map's default
## (MapInfo.FAVOUR_TARGET_PER_POINT per capture point).
@export var favour_target: int = 0
## Whether the first team to favour_target simply wins, as in a Conquest
## skirmish. Off, reaching it does nothing by itself and the quest decides —
## so the mission can play its closing lines, or treat the enemy getting there
## as a failed step.
@export var favour_race_wins: bool = false
## Applies to any side without its own, and supplies the map-wide Shrine
## monster pool.
@export var modifiers: ScenarioModifiers = null

func _enter_tree() -> void:
	add_to_group(&"scenario")
	MatchRules.current = MatchRules.new(self)
	## Before anything in the scene has run its _ready: a placed unit that
	## spends even one frame owned by peer 1 can be caught by FogOfWar's
	## one-time "explored" stamp and permanently reveal this corner of the map
	## to the host — the same trap Objective guards have. Real owners are
	## assigned while the sides are set up.
	for slot in slots():
		for entity in slot.placed_entities():
			entity.owner_peer_id = 0

## In authored order, which is the order humans fill them.
func slots() -> Array[ScenarioSlot]:
	var parent: Node = get_node_or_null(^"Slots")
	if parent == null:
		parent = self
	var out: Array[ScenarioSlot] = []
	for child in parent.get_children():
		if child is ScenarioSlot:
			out.append(child)
	return out

## The side the mission belongs to: whoever plays the human slots. Everything
## that asks "is this lot the player's?" goes through here.
func player_team() -> int:
	for slot in slots():
		if slot.kind == ScenarioSlot.Kind.HUMAN:
			return slot.team
	return 1

func zone(zone_name: StringName) -> ScenarioZone:
	for node in get_tree().get_nodes_in_group(&"scenario_zones"):
		if node.name == zone_name:
			return node
	return null

## A Marker3D (or anything else) under the Markers node.
func marker(marker_name: StringName) -> Node3D:
	var markers: Node = get_node_or_null(^"Markers")
	if markers == null:
		return null
	return markers.get_node_or_null(NodePath(String(marker_name))) as Node3D

## A named zone's centre, a named marker's position, or ZERO — what every
## "where?" field on a slot or a quest action is resolved through.
func position_of(place_name: StringName) -> Vector3:
	var area := zone(place_name)
	if area != null:
		return area.global_position
	var point := marker(place_name)
	return point.global_position if point != null else Vector3.ZERO

## slot index -> peer id. Worked out identically on every machine, so which
## side each player ends up on never has to be sent anywhere: humans take the
## HUMAN slots in peer-id order (the host first), and every other side gets the
## lowest free small peer id. Also writes each side's team and colour into this
## peer's own copy of Network.players, adding an entry for the AI-run sides.
##
## A HUMAN slot with nobody left to fill it is left out of the mapping (the
## campaign lobby will fill those with an allied AI).
func resolve_players() -> Dictionary:
	var humans: Array = []
	for id in Network.players:
		if not Network.is_ai(id):
			humans.append(id)
	humans.sort()
	## The host leads the queue whatever the id sort says.
	if humans.has(1):
		humans.erase(1)
		humans.push_front(1)
	## Running a scenario scene straight from the editor bypasses the lobby, so
	## there are no player entries at all — fall back to peer 1, which is who
	## Main spawns for in that workflow anyway.
	if humans.is_empty():
		humans.append(1)
		if not Network.players.has(1):
			Network.players[1] = {"name": "You", "color": Network.TEAM_COLORS[0], "ruler_index": 0, "ready": true}

	var taken: Array = Network.players.keys()
	var mapping: Dictionary = {}
	var list := slots()
	var next_human: int = 0
	for i in list.size():
		var slot: ScenarioSlot = list[i]
		var peer_id: int = 0
		var is_human_seat: bool = slot.kind == ScenarioSlot.Kind.HUMAN
		if is_human_seat and next_human < humans.size():
			peer_id = humans[next_human]
			next_human += 1
			Network.players[peer_id]["team"] = slot.team
			Network.players[peer_id]["color"] = _slot_color(slot)
		elif is_human_seat and not slot.fill_with_ai:
			## A seat the mission is happy to leave empty.
			continue
		else:
			peer_id = _free_peer_id(taken)
			taken.append(peer_id)
			## Campaign difficulty shifts enemy brains a level either way; an
			## ally filling an empty seat is not made worse by a harder
			## campaign, so it plays at the level the slot asks for.
			var difficulty: int = slot.ai_difficulty
			if not is_human_seat:
				difficulty = clampi(slot.ai_difficulty + Network.campaign_difficulty - 1, 0, 2)
			Network.players[peer_id] = {
				"name": "%s (AI)" % slot.name if is_human_seat else String(slot.name),
				"color": _slot_color(slot),
				"team": slot.team,
				"ruler_index": _slot_ruler(slot, i),
				"ready": true,
				"ai": true,
				"difficulty": difficulty,
				## Marks a side the scenario invented, so nothing mistakes it
				## for a lobby AI slot the host added.
				"scenario": true,
			}
		mapping[i] = peer_id
	return mapping

func _slot_color(slot: ScenarioSlot) -> Color:
	return Network.TEAM_COLORS[clampi(slot.color_index, 0, Network.TEAM_COLORS.size() - 1)]

## A slot left on "random" picks from its own index rather than randi(), so
## every machine resolves the same Ruler without being told.
func _slot_ruler(slot: ScenarioSlot, slot_index: int) -> int:
	var count := Ruler.list_all().size()
	if count <= 0:
		return 0
	if slot.ruler_index < 0:
		return slot_index % count
	return mini(slot.ruler_index, count - 1)

## Small ids only: Unit puts each owner on avoidance layer bit
## (owner_peer_id + 1), so a big one would fall off the 32-bit mask.
func _free_peer_id(taken: Array) -> int:
	var id: int = Network.FIRST_AI_PEER_ID
	while taken.has(id):
		id += 1
	return id
