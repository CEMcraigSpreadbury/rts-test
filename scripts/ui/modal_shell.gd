class_name ModalShell
extends RefCounted
## Builds the shell every setup screen shares -- eyebrow, title, rule, a
## two-column body and a right-aligned footer -- INTO a PanelContainer the caller
## owns, and hands back the slots to fill.
##
## A builder rather than a base class: the screens that need it already extend
## PanelContainer, and inheriting would collide on member names like _title.
##
## Skirmish, Multiplayer, Campaigns and Missions all use it, which is the point:
## starting a game and joining one should not look like different programs.

## Fill these. `left` takes the list, `right` the detail, `footer` the buttons.
var left: VBoxContainer
var right: VBoxContainer
var footer: HBoxContainer

var eyebrow_label: Label
var title_label: Label

## Dresses `panel` and returns the slots. `height` 0 lets the content decide.
static func dress(panel: PanelContainer, eyebrow: String, title: String,
		width: int = 960, height: int = 0) -> ModalShell:
	var shell := ModalShell.new()
	panel.theme_type_variation = &"ModalPanel"
	panel.custom_minimum_size = Vector2(width, height)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UiStyle.SPACE_S)
	panel.add_child(column)
	panel.add_child(UiCaps.new())

	var eyebrow_line := UiTextLine.make(eyebrow.to_upper(), &"CaptionLabel",
			UiStyle.SIZE_LABEL, UiStyle.ACCENT)
	shell.eyebrow_label = eyebrow_line.label
	column.add_child(eyebrow_line)

	var title_line := UiTextLine.make(title, &"TitleLabel", UiStyle.SIZE_MODAL_TITLE,
			UiStyle.INK, UiStyle.SIZE_MODAL_TITLE)
	shell.title_label = title_line.label
	column.add_child(title_line)

	var rule := SectionRule.new()
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(rule)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, UiStyle.SPACE_S)
	column.add_child(gap)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 26)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)

	shell.left = VBoxContainer.new()
	shell.left.add_theme_constant_override("separation", UiStyle.SPACE_S)
	shell.left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(shell.left)

	shell.right = VBoxContainer.new()
	shell.right.add_theme_constant_override("separation", UiStyle.SPACE_S)
	shell.right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(shell.right)

	shell.footer = HBoxContainer.new()
	shell.footer.alignment = BoxContainer.ALIGNMENT_END
	shell.footer.add_theme_constant_override("separation", UiStyle.SPACE_S)
	column.add_child(shell.footer)

	return shell

## Bounds a control's width so it can never push its panel wider.
##
## THIS IS THE RULE FOR EVERY PANEL IN THE GAME: changing an option must never
## change the size of the piece of UI showing it. A PanelContainer grows to its
## content's MINIMUM size, and a Button or OptionButton takes its minimum width
## from its longest text -- so adding a row, or picking a longer item, silently
## widens the window unless every control in it is bounded like this.
##
## `clip_text` is the important half: without it a Button refuses to be narrower
## than its label whatever its size flags say.
static func bound(control: Control, min_width: int) -> Control:
	control.custom_minimum_size.x = min_width
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if control is Button:
		(control as Button).clip_text = true
	return control

## A cell that holds nothing but keeps its column's width, so a row without an
## optional control still lines up with the rows that have one.
static func spacer(min_width: int) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size.x = min_width
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap

## The small brass heading that labels a column.
static func column_head(text: String) -> Control:
	return UiTextLine.make(text.to_upper(), &"CaptionLabel", UiStyle.SIZE_LABEL, UiStyle.ACCENT)
