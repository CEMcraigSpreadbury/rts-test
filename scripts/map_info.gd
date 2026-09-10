class_name MapInfo
extends Resource
## One playable map, as offered by the main menu's single player map select
## and the lobby's map picker. Both reference the same .tres files here (see
## resources/maps/) in the same order — that shared order is what
## Network.map_index refers to.

@export var map_name: String = "Map"
## Kept as a path rather than a PackedScene so listing the maps in a menu
## doesn't load every map scene up front — SceneLoader loads the chosen one.
@export_file("*.tscn") var scene_path: String = ""
