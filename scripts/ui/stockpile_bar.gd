class_name StockpileBar
extends PanelContainer
## The top-left stockpile: one cell per resource the player can actually earn or
## spend, divided by hairlines, sized to its contents so a resource can join
## without the panel jumping.
##
## A resource shows its glyph (UiGlyphs, in the resource's own colour) beside
## its amount, as the mockup drew it; anything without a glyph shows its name.

const CELL_GAP: int = 14
const GLYPH_GAP: int = 6
const INSET_X: int = 12
const INSET_Y: int = 10
const RATE_GAP: int = 5

var _row: HBoxContainer
var _cells: Dictionary = {}

func _init() -> void:
	var inset := UiStyle.empty_box()
	inset.content_margin_left = INSET_X
	inset.content_margin_right = INSET_X
	inset.content_margin_top = INSET_Y
	inset.content_margin_bottom = INSET_Y
	add_theme_stylebox_override(&"panel", inset)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 0)
	_row.custom_minimum_size.y = 44
	add_child(_row)
	add_child(UiPlasticBody.new())

## `entries` is an ordered array of {name: String, amount: int, flash: bool,
## accent: bool}, an optional `glyph` and its `tint`, plus an optional `rate` (a per-minute change shown after the
## amount, red when negative; 0 hides it). Cells are reused between calls so the panel does not rebuild
## its whole subtree every time a villager drops a log.
func set_entries(entries: Array) -> void:
	for i in entries.size():
		var entry: Dictionary = entries[i]
		var key: String = entry.get("name", "")
		var cell: Dictionary = _cells.get(key, {})
		if cell.is_empty():
			cell = _make_cell(key, entry.get("glyph", &""), entry.get("tint", UiStyle.INK))
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
		var rate: int = entry.get("rate", 0)
		var rate_line: UiTextLine = cell["rate"]
		rate_line.visible = rate != 0
		if rate != 0:
			rate_line.set_text(("+%d" if rate > 0 else "−%d") % absi(rate))
			rate_line.label.add_theme_color_override("font_color", UiStyle.GOOD if rate > 0 else UiStyle.BAD)

	## Cells for resources that no longer apply (Food leaving on a reset) are
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

func _make_cell(display_name: String, glyph: StringName, tint: Color) -> Dictionary:
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 0)

	## A seam moulded into the plastic: a dark line catching light on one side,
	## stopping short of the tray's edges.
	var divider := MarginContainer.new()
	divider.add_theme_constant_override("margin_top", 6)
	divider.add_theme_constant_override("margin_bottom", 6)
	var seam := Panel.new()
	seam.custom_minimum_size = Vector2(2, 0)
	var seam_box := UiStyle.flat(UiStyle.SLOT, Color(1, 1, 1, 0.12), 0, 0)
	seam_box.border_width_right = 1
	seam.add_theme_stylebox_override("panel", seam_box)
	divider.add_child(seam)
	root.add_child(divider)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", GLYPH_GAP)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", CELL_GAP)
	pad.add_theme_constant_override("margin_right", CELL_GAP)
	pad.add_child(row)
	root.add_child(pad)

	if glyph != &"":
		var icon := UiGlyphs.rect(glyph, UiStyle.GLYPH_STOCK, tint)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(icon)
	else:
		var caption := UiTextLine.make(display_name, &"CaptionLabel", UiStyle.SIZE_LABEL, UiStyle.DIM)
		caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(caption)
	var value_row := HBoxContainer.new()
	value_row.add_theme_constant_override("separation", RATE_GAP)
	row.add_child(value_row)
	var value := UiTextLine.make("0", &"ValueLabel", UiStyle.SIZE_STOCK, UiStyle.INK)
	value_row.add_child(value)
	var rate := UiTextLine.make("", &"ValueLabel", 17, UiStyle.BAD)
	rate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rate.visible = false
	value_row.add_child(rate)

	return {"root": root, "divider": divider, "value": value, "rate": rate}
