extends Node
## Run this scene (F6) to regenerate every command-card icon that comes from
## art: each of the faction's buildings, rendered from its model, and each
## trainable unit, cut from its idle sprite. Quits when done. Single icons
## are made from the Icon Maker dock instead.

const FACTION_PATH: String = "res://resources/factions/faction_one.tres"
const BUILDINGS_DIR: String = "res://scenes/buildings"
const OUTPUT_DIR: String = "res://assets/ui/icons"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR + "/buildings")
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR + "/units")

	var model_options := IconMaker.Options.new()
	var faction: Faction = load(FACTION_PATH)
	for building_type in faction.building_types:
		var icon: Image = await IconMaker.render_model(self, building_type.scene, model_options)
		_save(icon, "buildings", building_type.building_name)

	var sprite_options := IconMaker.Options.new()
	sprite_options.outline = false
	var done: Dictionary = {}
	for file in DirAccess.get_files_at(BUILDINGS_DIR):
		if not file.ends_with(".tscn"):
			continue
		var building: Node = load(BUILDINGS_DIR + "/" + file).instantiate()
		var producibles: Array = building.get("producibles") if building.get("producibles") != null else []
		building.free()
		## One zoom for the whole roster, taken from whichever of its units has
		## the largest figure: these buttons sit side by side on the command
		## card, and a unit drawn small looked blown up next to its own kin.
		var roster: Array[ProducibleItem] = []
		for item: ProducibleItem in producibles:
			if item.kind == ProducibleItem.Kind.UNIT and item.unit_scene != null:
				roster.append(item)
		sprite_options.scale = 0.0
		for item in roster:
			var scale: float = IconMaker.unit_scale(item.unit_scene, sprite_options.size)
			sprite_options.scale = scale if sprite_options.scale <= 0.0 else minf(sprite_options.scale, scale)
		for item in roster:
			if done.has(item.item_name):
				continue
			done[item.item_name] = true
			_save(IconMaker.unit_icon(item.unit_scene, sprite_options), "units", item.item_name)
	get_tree().quit()

func _save(icon: Image, folder: String, display_name: String) -> void:
	var path := "%s/%s/%s.png" % [OUTPUT_DIR, folder, display_name.to_lower().replace(" ", "_")]
	if icon == null:
		push_warning("No icon for %s" % display_name)
		return
	icon.save_png(path)
	print("ICON ", path)
