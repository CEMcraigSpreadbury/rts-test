class_name StockpileBar
extends PanelContainer
## The top-left stockpile: one cell per resource the player can actually earn or
## spend, divided by hairlines, sized to its contents so a Pact currency can
## join without the panel jumping.
##
## A resource shows its name over its amount. The mockup drew a glyph instead of
## the name, but the game has no resource icons yet, and a name is better than a
## placeholder shape.

const CELL_GAP: int = 13

var _row: HBoxContainer
var _cells: Dictionary = {}

func _init() -> void:
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 0)
	add_child(_row)
	add_child(UiCaps.new())

## `entries` is an ordered array of {name: String, amount: int, flash: bool,
## accent: bool}. Cells are reused between calls so the panel does not rebuild
## its whole subtree every time a villager drops a log.
func set_entries(entries: Array) -> void:
	for i in entries.size():
		var entry: Dictionary = entries[i]
		var key: String = entry.get("name", "")
		var cell: Dictionary = _cells.get(key, {})
		if cell.is_empty():
			cell = _make_cell(key)
			_cells[key] = cell
			_row.add_child(cell["root"])
		_row.move_child(cell["root"] as Node, i)
		(cell["root"] as Control).visible = true
		(cell["divider"] as Control).visible = i > 0
		var shown: String = str(entry.get("amount", 0))
		## Population carries a cap, so it reads "31/60" while a resource is a
		## bare total.
		if entry.has("cap"):
			shown += "/" + str(entry["cap"])
		(cell["value"] as UiTextLine).set_text(shown)
		var colour: Color = UiStyle.INK
		if entry.get("flash", false):
			colour = UiStyle.BAD
		elif entry.get("accent", false):
			colour = UiStyle.ACCENT
		(cell["value"] as UiTextLine).label.add_theme_color_override("font_color", colour)

	## Cells for resources that no longer apply (a Pact currency on a reset) are
	## hidden rather than freed, so the next match reuses them.
	var live: Array = []
	for entry: Dictionary in entries:
		live.append(entry.get("name", ""))
	for key: String in _cells:
		if not live.has(key):
			(_cells[key]["root"] as Control).visible = false

	## The panel has explicit offsets in the scene, so it will not shrink to its
	## contents on its own -- without this a four-resource bar keeps the width of
	## a six-resource one and trails empty brass across the corner of the screen.
	reset_size()

func _make_cell(display_name: String) -> Dictionary:
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 0)

	var divider := Panel.new()
	divider.custom_minimum_size = Vector2(UiStyle.BORDER, 0)
	divider.add_theme_stylebox_override("panel",
		UiStyle.flat(UiStyle.LINE, UiStyle.LINE, 0, 0))
	root.add_child(divider)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	column.add_theme_constant_override("margin_left", CELL_GAP)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", CELL_GAP)
	pad.add_theme_constant_override("margin_right", CELL_GAP)
	pad.add_child(column)
	root.add_child(pad)

	var caption := UiTextLine.make(display_name, &"CaptionLabel", UiStyle.SIZE_LABEL, UiStyle.DIM)
	column.add_child(caption)
	var value := UiTextLine.make("0", &"ValueLabel", UiStyle.SIZE_VALUE, UiStyle.INK)
	column.add_child(value)

	return {"root": root, "divider": divider, "value": value, "caption": caption}
