extends Node
func _ready() -> void:
	var icon: Image = await IconMaker.render_model(self, load("res://scenes/buildings/library_building.tscn"), IconMaker.Options.new())
	icon.save_png("res://assets/ui/icons/buildings/library.png")
	print("ICON saved ", icon.get_size())
	get_tree().quit()
