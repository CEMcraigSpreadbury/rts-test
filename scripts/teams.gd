class_name Teams
extends RefCounted
## Who fights whom. A player's team is the team colour they picked: two players
## on Blue are allies, and the old free-for-all is just everyone picking a
## different colour. Campaign scenarios will instead set a team directly in
## Network.players (every human on one team), which team_of() prefers when it
## is there.
##
## Static, and read straight out of Network.players, so units, buildings, the
## AI and the fog can all ask without reaching through Main.

## Peer 0 owns neutral guards and unclaimed resources: hostile to everyone,
## allied with nobody, itself included.
const NEUTRAL: int = 0

## Anyone who reached a match without going through a lobby (the
## run-main.tscn-straight-from-the-editor workflow) has no entry in
## Network.players, so they get a private team of their own rather than
## silently ending up allied with another such player.
static func team_of(peer_id: int) -> int:
	if peer_id <= 0:
		return NEUTRAL
	var data: Dictionary = Network.players.get(peer_id, {})
	if data.has("team"):
		return int(data["team"])
	var color_index: int = Network.TEAM_COLORS.find(data.get("color", Color.WHITE))
	## -(peer + 1) rather than -peer so no private team can ever come out as
	## -1, which Main uses as its "draw" sentinel for a winning team.
	return color_index + 1 if color_index >= 0 else -(peer_id + 1)

## The one question combat, vision and capture ask. Nothing is ever its own
## enemy; peer 0 is everyone else's.
static func is_enemy(a: int, b: int) -> bool:
	if a == b:
		return false
	var team_a := team_of(a)
	var team_b := team_of(b)
	if team_a == NEUTRAL or team_b == NEUTRAL:
		return true
	return team_a != team_b

## Same side, a peer included with itself. The inverse of is_enemy, spelled out
## because call sites read better one way or the other.
static func is_friendly(a: int, b: int) -> bool:
	return not is_enemy(a, b)

## Every player on `team`, AIs included.
static func peers_on_team(team: int) -> Array[int]:
	var out: Array[int] = []
	for id in Network.players:
		if team_of(id) == team:
			out.append(id)
	out.sort()
	return out

## The distinct teams among `peer_ids`, in the order first seen.
static func teams_of(peer_ids: Array) -> Array[int]:
	var out: Array[int] = []
	for id in peer_ids:
		var team := team_of(id)
		if not out.has(team):
			out.append(team)
	return out

## The colour a team is known by — its members all share it. Falls back to the
## first member's own tint for a team that isn't one of the palette entries
## (an explicit scenario team), and white for one with nobody on it.
static func team_color(team: int) -> Color:
	var index := team - 1
	if index >= 0 and index < Network.TEAM_COLORS.size():
		return Network.TEAM_COLORS[index]
	var members := peers_on_team(team)
	if members.is_empty():
		return Color.WHITE
	return Network.players.get(members[0], {}).get("color", Color.WHITE)
