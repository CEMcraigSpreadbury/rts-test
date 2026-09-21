extends Control
## Dev screen that builds the mockup's build-menu panel out of the real
## components, so the Godot output can be diffed against the mockup render
## instead of eyeballed.
##
##   godot --path . scenes/tools/ui_shot.tscn -- --out=X.png \
##       --scene=res://scenes/tools/ui_gallery.tscn --wait=3
##
## Reproduces the "Build menu" screen of
## https://claude.ai/artifact/EWAC2gtpYTe3nGzPSQ4Fy5

const ALDMERE: Array = [
	["H", "House", 30], ["S", "Storehouse", 80], ["M", "Mine", 80],
	["B", "Barracks", 150], ["R", "Archery Range", 150], ["T", "Stables", 175],
	["K", "Blacksmith", 120], ["W", "Watchtower", 90], ["V", "Wall", 10],
	["G", "Gate", 40], ["E", "Siege Workshop", 200], ["A", "Arcane Sanctum", 250],
	["P", "Pact Hall", 300], ["O", "Observatory", 220], ["N", "Shrine", 140],
]

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.29, 0.42, 0.25)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_build_selection_panel()
	_build_component_row()

func _build_selection_panel() -> void:
	var panel := UiPanel.new()
	panel.size = UiStyle.SEL_PANEL_SIZE
	panel.position = Vector2(UiStyle.SCREEN_MARGIN,
		1080 - UiStyle.SCREEN_MARGIN - UiStyle.SEL_PANEL_SIZE.y)
	panel.set_insets(UiStyle.SPACE_L, UiStyle.SPACE_L, UiStyle.SPACE_L, UiStyle.SPACE_XL)
	add_child(panel)

	## Above the panel box, inset so it clears the top-left corner cap.
	var tabs := RaceTabStrip.new()
	tabs.add_race(&"aldmere", "Aldmere", Color("4f8ede"), true)
	tabs.add_race(&"gnolls", "Gnolls", Color("a9702f"), true)
	tabs.add_race(&"dark_elves", "Dark Elves", UiStyle.DIM, false)
	tabs.add_race(&"star_wanderers", "Star Wanderers", UiStyle.DIM, false)
	add_child(tabs)
	tabs.position = Vector2(panel.position.x + RaceTabStrip.OFFSET_FROM_INSET, 0)
	## Measured after the strip has sized itself, so it sits on the panel's edge.
	await get_tree().process_frame
	tabs.position.y = panel.position.y - tabs.size.y

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiStyle.SPACE_L)
	panel.content.add_child(row)

	row.add_child(_portrait("res://assets/ui/icons/units/villager.png"))

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", UiStyle.SPACE_S)
	row.add_child(body)

	body.add_child(UiTextLine.make("Villager", &"TitleLabel", UiStyle.SIZE_NAME))

	body.add_child(_stat_row([["Hit points", "40 / 40"], ["Armour", "0%"], ["Carrying", "8 Wood"]]))

	var grid := GridContainer.new()
	grid.columns = UiStyle.CMD_COLUMNS
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	body.add_child(grid)

	for i in UiStyle.CMD_COLUMNS * UiStyle.CMD_ROWS:
		var slot := CommandSlot.new()
		grid.add_child(slot)
		if i >= ALDMERE.size():
			slot.make_empty()
			continue
		var entry: Array = ALDMERE[i]
		slot.setup_letter(entry[0], entry[1], [{"amount": entry[2]}])
		if entry[0] == "H":
			slot.state = CommandSlot.State.SELECTED
		elif entry[0] == "P":
			slot.state = CommandSlot.State.UNAFFORDABLE

func _portrait(icon_path: String) -> Control:
	var frame := Panel.new()
	frame.custom_minimum_size = Vector2(UiStyle.PORTRAIT, UiStyle.PORTRAIT)
	frame.add_theme_stylebox_override("panel", UiStyle.slot_box(UiStyle.LINE_STRONG))

	var icon := TextureRect.new()
	icon.texture = load(icon_path)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size = Vector2(UiStyle.ICON_2X, UiStyle.ICON_2X)
	icon.position = Vector2((UiStyle.PORTRAIT - UiStyle.ICON_2X) * 0.5, 14)
	UiStyle.make_pixel_crisp(icon)
	frame.add_child(icon)

	var health := StatBar.new()
	health.ratio = 1.0
	health.size = Vector2(UiStyle.PORTRAIT - 14, 7)
	health.position = Vector2(7, UiStyle.PORTRAIT - 14)
	frame.add_child(health)
	return frame

func _stat_row(pairs: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	for pair: Array in pairs:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 3)
		cell.add_child(UiTextLine.make(pair[0], &"CaptionLabel", UiStyle.SIZE_LABEL, UiStyle.DIM))
		cell.add_child(UiTextLine.make(pair[1], &"ValueLabel", UiStyle.SIZE_BODY, UiStyle.INK, UiStyle.SIZE_BODY))
		row.add_child(cell)
	return row

## Buttons, a rule and a bar on their own, where a panel's content cannot hide a
## styling mistake in them.
func _build_component_row() -> void:
	var panel := UiPanel.new()
	panel.size = Vector2(430, 400)
	panel.position = Vector2(UiStyle.SCREEN_MARGIN, 120)
	add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UiStyle.SPACE_M)
	panel.content.add_child(column)

	column.add_child(UiTextLine.make("Components", &"TitleLabel", UiStyle.SIZE_NAME))
	column.add_child(SectionRule.new())

	var primary := UiButton.new()
	primary.text = "Resume"
	primary.primary = true
	column.add_child(primary)

	var secondary := UiButton.new()
	secondary.text = "Options"
	column.add_child(secondary)

	var disabled := UiButton.new()
	disabled.text = "Leave Match"
	disabled.disabled = true
	column.add_child(disabled)

	for ratio: float in [1.0, 0.62, 0.24]:
		var bar := StatBar.new()
		bar.ratio = ratio
		bar.fill_color = UiStyle.GOOD if ratio > 0.5 else UiStyle.BAD
		bar.custom_minimum_size = Vector2(0, 7)
		column.add_child(bar)

	var queue := HBoxContainer.new()
	queue.add_theme_constant_override("separation", 6)
	for i in 5:
		var slot := CommandSlot.new()
		slot.custom_minimum_size = Vector2(UiStyle.SLOT_QUEUE, UiStyle.SLOT_QUEUE)
		queue.add_child(slot)
		if i < 3:
			slot.setup_icon(load("res://assets/ui/icons/units/spearman.png"), str(i + 1), "Spearman", [{"amount": 50}])
		else:
			slot.make_empty()
	column.add_child(queue)
