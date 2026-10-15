extends Node
## Run this scene (F6) to regenerate every command-card icon that comes from
## art: each of the faction's buildings and each settlement-only building,
## rendered from its model. Units need none: their buttons show figure
## portraits made at runtime (UnitPortrait). Quits when done. Single icons are made from the Icon Maker dock instead.

const FACTION_PATH: String = "res://resources/factions/faction_one.tres"
const OUTPUT_DIR: String = "res://assets/ui/icons"
## Built in settlement slots or standing in a settlement, never from the
## faction's build menu. Saved under the scene's name (see Objective._building_icon_for).
const SETTLEMENT_BUILDINGS: Array[String] = [
	"res://scenes/settlements/granary_building.tscn",
	"res://scenes/settlements/market_building.tscn",
	"res://scenes/settlements/lumberyard_building.tscn",
	"res://scenes/buildings/beastmen_barracks_building.tscn",
	"res://scenes/buildings/dark_elf_spire_building.tscn",
	"res://scenes/buildings/dark_elf_coven_building.tscn",
	"res://scenes/buildings/star_gate_building.tscn",
	"res://scenes/buildings/star_sanctum_building.tscn",
]

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR + "/buildings")

	var model_options := IconMaker.Options.new()
	var faction: Faction = load(FACTION_PATH)
	for building_type in faction.building_types:
		var icon: Image = await IconMaker.render_model(self, building_type.scene, model_options)
		_save(icon, "buildings", building_type.building_name)
	for scene_path in SETTLEMENT_BUILDINGS:
		var icon: Image = await IconMaker.render_model(self, load(scene_path), model_options)
		_save(icon, "buildings", scene_path.get_file().get_basename().trim_suffix("_building"))

	get_tree().quit()

func _save(icon: Image, folder: String, display_name: String) -> void:
	var path := "%s/%s/%s.png" % [OUTPUT_DIR, folder, display_name.to_lower().replace(" ", "_")]
	if icon == null:
		push_warning("No icon for %s" % display_name)
		return
	icon.save_png(path)
	print("ICON ", path)
