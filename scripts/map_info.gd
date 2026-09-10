class_name MapInfo
extends Resource
## One playable map, as offered by the main menu's single player map select
## and the lobby's map picker. Both list every MapInfo in resources/maps/ via
## list_all(), sorted by file name — that shared order is what
## Network.map_index refers to.

const MAPS_DIR: String = "res://resources/maps/"

@export var map_name: String = "Map"
## Kept as a path rather than a PackedScene so listing the maps in a menu
## doesn't load every map scene up front — SceneLoader loads the chosen one.
@export_file("*.tscn") var scene_path: String = ""
## Number of PlayerSpawnPoints on the map; 0 if unknown.
@export var max_players: int = 0

static func list_all() -> Array[MapInfo]:
	var maps: Array[MapInfo] = []
	var files: PackedStringArray = ResourceLoader.list_directory(MAPS_DIR)
	files.sort()
	for file in files:
		if not (file.ends_with(".tres") or file.ends_with(".res")):
			continue
		var info := load(MAPS_DIR + file) as MapInfo
		if info != null:
			maps.append(info)
	return maps
