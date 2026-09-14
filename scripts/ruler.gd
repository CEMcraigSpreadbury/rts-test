class_name Ruler
extends Resource
## A Ruler picked per player in the lobby / single player setup: the research
## tree they spend research points on during a match. Every Ruler shares the
## same units and buildings (see Faction). Listed from resources/rulers/ in
## file name order — that order is what a "ruler_index" in Network.players
## refers to.

const RULERS_DIR: String = "res://resources/rulers/"
## A ruler_index still to be rolled — resolved by the host just before the
## match loads (see Network.resolve_random_rulers).
const RANDOM: int = -1

@export var ruler_name: String = "Ruler"
@export var nodes: Array[ResearchNode] = []

static var _all: Array[Ruler] = []

static func list_all() -> Array[Ruler]:
	if not _all.is_empty():
		return _all
	var files: PackedStringArray = ResourceLoader.list_directory(RULERS_DIR)
	files.sort()
	for file in files:
		if not (file.ends_with(".tres") or file.ends_with(".res")):
			continue
		var ruler := load(RULERS_DIR + file) as Ruler
		if ruler != null:
			_all.append(ruler)
	return _all

static func display_name_for(ruler_index: int) -> String:
	if ruler_index == RANDOM:
		return "Random"
	var rulers := list_all()
	return rulers[ruler_index].ruler_name if ruler_index >= 0 and ruler_index < rulers.size() else "?"
