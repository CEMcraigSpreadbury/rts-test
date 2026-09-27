class_name RaceModels
extends RefCounted
## Each people's own look for the buildings every settlement shares (a Range,
## a Granary, a Watchtower...): one scene per building kind, with the model
## swapped for the settlement's race when the slot building goes up (see
## ProductionBuilding.setup_slot). A people with no model of its own for a
## building keeps the scene's (Human) one. Buildings only one people has (a
## Gnoll Den, a Star Gate) carry their model in their own scene instead.

const RACES_DIR: String = "res://assets/art/Models/Races/"
## A settlement's ring of Walls asks for these two.
const WALL_SEGMENT: String = "Wall Segment"
const WALL_GATE: String = "Wall Gate"

## Race -> building name (the slot item's name) -> model.
const MODELS: Dictionary = {
	"Human": {
		"Cottage": "res://assets/art/Models/TownBuildings/House.glb",
	},
	"Gnolls": {
		"Range": RACES_DIR + "Gnolls/Range.glb",
		"Stables": RACES_DIR + "Gnolls/Stables.glb",
		"Bestiary": RACES_DIR + "Gnolls/Bestiary.glb",
		"Granary": RACES_DIR + "Gnolls/Granary.glb",
		"Market": RACES_DIR + "Gnolls/Market.glb",
		"Lumberyard": RACES_DIR + "Gnolls/Lumberyard.glb",
		"Watchtower": RACES_DIR + "Gnolls/Watchtower.glb",
		"Cottage": RACES_DIR + "Gnolls/Cottage.glb",
		WALL_SEGMENT: RACES_DIR + "Gnolls/WallSegment.glb",
		WALL_GATE: RACES_DIR + "Gnolls/WallGate.glb",
	},
	"Dark Elves": {
		"Range": RACES_DIR + "DarkElves/Range.glb",
		"Stables": RACES_DIR + "DarkElves/Stables.glb",
		"Bestiary": RACES_DIR + "DarkElves/Bestiary.glb",
		"Granary": RACES_DIR + "DarkElves/Granary.glb",
		"Market": RACES_DIR + "DarkElves/Market.glb",
		"Lumberyard": RACES_DIR + "DarkElves/Lumberyard.glb",
		"Watchtower": RACES_DIR + "DarkElves/Watchtower.glb",
		"Cottage": RACES_DIR + "DarkElves/Cottage.glb",
		WALL_SEGMENT: RACES_DIR + "DarkElves/WallSegment.glb",
		WALL_GATE: RACES_DIR + "DarkElves/WallGate.glb",
	},
	"Star Wanderers": {
		"Range": RACES_DIR + "StarWanderers/Range.glb",
		"Stables": RACES_DIR + "StarWanderers/Stables.glb",
		"Bestiary": RACES_DIR + "StarWanderers/Bestiary.glb",
		"Granary": RACES_DIR + "StarWanderers/Granary.glb",
		"Market": RACES_DIR + "StarWanderers/Market.glb",
		"Lumberyard": RACES_DIR + "StarWanderers/Lumberyard.glb",
		"Watchtower": RACES_DIR + "StarWanderers/Watchtower.glb",
		"Cottage": RACES_DIR + "StarWanderers/Cottage.glb",
		WALL_SEGMENT: RACES_DIR + "StarWanderers/WallSegment.glb",
		WALL_GATE: RACES_DIR + "StarWanderers/WallGate.glb",
	},
	"Beastmen": {
		"Range": RACES_DIR + "Beastmen/Range.glb",
		"Stables": RACES_DIR + "Beastmen/Stables.glb",
		"Sanctum": RACES_DIR + "Beastmen/Sanctum.glb",
		"Granary": RACES_DIR + "Beastmen/Granary.glb",
		"Market": RACES_DIR + "Beastmen/Market.glb",
		"Lumberyard": RACES_DIR + "Beastmen/Lumberyard.glb",
		"Watchtower": RACES_DIR + "Beastmen/Watchtower.glb",
		"Cottage": RACES_DIR + "Beastmen/Cottage.glb",
		WALL_SEGMENT: RACES_DIR + "Beastmen/WallSegment.glb",
		WALL_GATE: RACES_DIR + "Beastmen/WallGate.glb",
	},
}

## Cottages are drawn this big across (the House model is a town's house).
const COTTAGE_WIDTH: float = 1.9

static func model_for(race: String, building_name: String) -> String:
	var own: Dictionary = MODELS.get(race, {})
	var path: String = own.get(building_name, "")
	if path.is_empty() or not ResourceLoader.exists(path):
		return ""
	return path

## Swaps `building`'s model for `race`'s, before it enters the tree (its
## materials are collected in _ready). The model is whichever child was
## instanced from a .glb/.gltf.
static func apply(building: Node3D, race: String, building_name: String) -> void:
	var path := model_for(race, building_name)
	if path.is_empty():
		return
	for child in building.get_children():
		var file: String = child.scene_file_path
		if file.ends_with(".glb") or file.ends_with(".gltf") or child.name == &"Model":
			if file == path:
				return
			building.remove_child(child)
			child.free()
			break
	var model := (load(path) as PackedScene).instantiate() as Node3D
	model.name = "Model"
	building.add_child(model)
	building.move_child(model, 0)

## A settlement cottage in `race`'s style, or null to fall back to the box one.
static func cottage(race: String) -> Node3D:
	var path := model_for(race, "Cottage")
	if path.is_empty():
		return null
	var model := (load(path) as PackedScene).instantiate() as Node3D
	var widest: float = 0.0
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = (mesh as MeshInstance3D).get_aabb()
		widest = maxf(widest, maxf(box.size.x, box.size.z))
	if widest > 0.0:
		model.scale = Vector3.ONE * (COTTAGE_WIDTH / widest)
	## The settlement bounces and squashes the cottage itself (scale back to
	## one), so the sizing lives a level down.
	var holder := Node3D.new()
	holder.add_child(model)
	return holder
