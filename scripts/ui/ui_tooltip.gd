class_name UiTooltip
extends VBoxContainer
## Contents of a Forged Brass tooltip: a name, and the costs if the thing has
## any. No descriptive copy -- a tooltip states what something is and what it
## takes, never what to do with it.
##
## It draws no background of its own. Godot wraps a custom tooltip in a
## PopupPanel, and the theme's TooltipPanel style supplies the opaque brass
## surface, so the popup and the panel can never drift apart.

static func build(display_name: String, costs: Array = [], hotkey: String = "") -> UiTooltip:
	var tip := UiTooltip.new()
	tip.add_theme_constant_override("separation", UiStyle.SPACE_S)

	var title := Label.new()
	title.text = display_name
	title.add_theme_font_override("font", UiStyle.font_display())
	title.add_theme_font_size_override("font_size", UiStyle.SIZE_TOOLTIP_NAME)
	title.add_theme_color_override("font_color", UiStyle.INK)
	tip.add_child(title)

	if not costs.is_empty() or not hotkey.is_empty():
		tip.add_child(SectionRule.new())

	if not costs.is_empty():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", UiStyle.SPACE_L)
		for cost: Dictionary in costs:
			var cell := HBoxContainer.new()
			cell.add_theme_constant_override("separation", 5)
			var label_text: String = cost.get("label", "")
			if not label_text.is_empty():
				var caption := Label.new()
				caption.text = label_text
				caption.add_theme_font_override("font", UiStyle.font_display())
				caption.add_theme_font_size_override("font_size", UiStyle.SIZE_LABEL)
				caption.add_theme_color_override("font_color", UiStyle.DIM)
				cell.add_child(caption)
			var icon: Texture2D = cost.get("icon")
			if icon != null:
				var tex := TextureRect.new()
				tex.texture = icon
				tex.custom_minimum_size = Vector2(15, 15)
				tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				cell.add_child(tex)
			var amount := Label.new()
			amount.text = str(cost.get("amount", 0))
			amount.add_theme_font_override("font", UiStyle.font_data_bold())
			amount.add_theme_font_size_override("font_size", 16)
			amount.add_theme_color_override("font_color", UiStyle.INK)
			cell.add_child(amount)
			row.add_child(cell)
		tip.add_child(row)

	if not hotkey.is_empty():
		var key := Label.new()
		key.text = hotkey
		key.add_theme_font_override("font", UiStyle.font_data())
		key.add_theme_font_size_override("font_size", UiStyle.SIZE_LABEL)
		key.add_theme_color_override("font_color", UiStyle.DIM)
		tip.add_child(key)

	return tip
