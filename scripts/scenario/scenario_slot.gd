class_name ScenarioSlot
extends Node3D
## One side in a scenario: a human seat, an enemy AI, or a pack of defenders
## with no brain at all. Units and buildings placed as children of this node
## belong to that side when the match starts (Main adopts them into the usual
## Units/Buildings containers).
##
## The peer id playing a slot is worked out at load time and is the same on
## every machine (see Scenario.resolve_players), so nothing here is networked.

enum Kind {
	## Played by a human. Filled in slot order; a slot with nobody left to
	## fill it is skipped (allied AI fill comes with the campaign lobby).
	HUMAN,
	## An ordinary AI opponent, running the same brain a skirmish AI does.
	ENEMY_AI,
	## Owns its placed units and buildings and nothing else: no base, no
	## economy, no brain. Garrisons, outposts, a village to rescue.
	DEFENDERS,
}

@export var kind: Kind = Kind.HUMAN
## Sides sharing a team number are allies; see Teams. Team 1 is conventionally
## the player's side.
@export var team: int = 1
## Index into Network.TEAM_COLORS.
@export_range(0, 3) var color_index: int = 0
## ENEMY_AI only: 0 Easy, 1 Normal, 2 Hard. Campaign difficulty shifts this.
@export_enum("Easy", "Normal", "Hard") var ai_difficulty: int = 1
## ENEMY_AI only: what the brain starts out doing (see AiPlayer.Mode). A quest
## step can change it later, which is how "the enemy notices you" works.
@export_enum("Normal", "Defend", "Attack") var ai_mode: int = 0
## ENEMY_AI in Attack mode: the zone or marker its waves are aimed at.
@export var attack_at: StringName = &""
## DEFENDERS only: how far a placed unit will chase before going back to where
## it was put. 0 lets them chase as far as they like.
@export var defender_leash_radius: float = 14.0
## Index into Ruler.list_all(), or -1 for a random one.
@export var ruler_index: int = -1
## HUMAN only: when nobody is there to play it, an allied AI takes the seat so
## a co-op mission still works solo. Turn it off for a seat that should simply
## stand empty with fewer players.
@export var fill_with_ai: bool = true
## Which of the map's PlayerSpawnPoints this side starts at, or -1 for a side
## that has no base of its own (DEFENDERS, or anyone whose whole starting
## position is placed by hand under this node).
@export var spawn_point_index: int = -1
## Replaces Faction.starting_buildings/units for this side when non-empty.
@export var starting_buildings: Array[PackedScene] = []
@export var starting_units: Array[PackedScene] = []
## Banked before the first frame.
@export var starting_resources: Array[ResourceCost] = []
## Leave null for "play by the ordinary rules".
@export var modifiers: ScenarioModifiers = null

## The units and buildings authored under this node.
func placed_entities() -> Array[Node]:
	var out: Array[Node] = []
	for child in get_children():
		if child is Unit or child is ProductionBuilding:
			out.append(child)
	return out
