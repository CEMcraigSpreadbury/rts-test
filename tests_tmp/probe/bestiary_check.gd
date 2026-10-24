extends Node
## Loads the Pirate and Robot Bestiaries: their model's BeastSpot, their
## beast, the roster and their race upgrades.
func _ready() -> void:
	for path in ["res://scenes/buildings/pirates/pirate_bestiary_building.tscn", "res://scenes/buildings/robots/robot_bestiary_building.tscn"]:
		var b := (load(path) as PackedScene).instantiate() as ProductionBuilding
		var spot := b.find_child("BeastSpot", true, false)
		print(path.get_file(), " spot=", spot != null, " race=", b.race_name, " items=", b.producibles.map(func(i): return i.item_name))
		RaceTraits.offer_upgrades(b)
		print("  with upgrades: ", b.producibles.map(func(i): return i.item_name))
		b.free()
	for race in ["Pirates", "Robots"]:
		print(race, " kinds=", RealmRoster.kinds_for(race), " scene=", RealmRoster.scene_for(race, RealmRoster.Kind.BESTIARY))
	for f in ["res://resources/factions/faction_pirates.tres", "res://resources/factions/faction_robots.tres"]:
		var fac = load(f)
		print(f.get_file(), " last type=", fac.building_types[-1].display_name)
	get_tree().quit()
