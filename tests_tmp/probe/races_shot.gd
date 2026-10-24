extends Node
## Opens the menu's Races screen on each race and saves a shot of it.
func _ready() -> void:
	var menu: Node = load("res://scenes/main_menu.tscn").instantiate()
	get_tree().root.add_child.call_deferred(menu)
	await get_tree().create_timer(1.5).timeout
	var tutorial = menu.get("_tutorial_offer")
	if tutorial != null:
		menu.call("_close_tutorial_offer")
	menu.call("_on_races_pressed")
	var races: RacesScreen = menu.get("_races")
	for i in 3:
		races.open_race(i)
		await get_tree().create_timer(1.2).timeout
		get_viewport().get_texture().get_image().save_png("C:/Users/craig/AppData/Local/Temp/claude/c--Users-craig-Documents-rts-test/8a48143e-93c9-4ef4-9c7c-da4ad5ba7f20/scratchpad/races_%d.png" % i)
	get_tree().quit()
