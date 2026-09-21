extends SceneTree
## Regenerates assets/ui/theme/dark_ages_theme.tres from the UiStyle tokens.
##
##   godot --path . --headless --script res://scripts/tools/build_ui_theme.gd
##
## The theme is a build artefact, not a hand-authored resource. Editing the .tres
## directly is how the old UI ended up with nine different golds -- change
## scripts/ui_style.gd and re-run this instead.
##
## It replaces the 32x32 tilesheet StyleBoxTextures wholesale: every surface is
## now a StyleBoxFlat, so nothing in the UI is a stretched bitmap any more. The
## theme references no bitmap at all: even the checkbox ticks are generated.

const THEME_PATH: String = "res://assets/ui/theme/dark_ages_theme.tres"

func _init() -> void:
	var theme := Theme.new()

	theme.default_font = UiStyle.font_data()
	theme.default_font_size = UiStyle.SIZE_BODY

	_labels(theme)
	_buttons(theme)
	_panels(theme)
	_inputs(theme)
	_containers(theme)
	_progress(theme)
	_lists(theme)
	_checks(theme)

	var err := ResourceSaver.save(theme, THEME_PATH)
	if err != OK:
		push_error("build_ui_theme: save failed (%d)" % err)
		quit(1)
		return
	print("BUILD_UI_THEME ok -> %s" % THEME_PATH)
	quit(0)

func _labels(theme: Theme) -> void:
	theme.set_color("font_color", "Label", UiStyle.INK)
	## No drop shadows. Every label in the new UI sits on a panel, and a shadow
	## over a panel just muddies the glyph edges we went to 1920 to sharpen.
	theme.set_constant("shadow_offset_x", "Label", 0)
	theme.set_constant("shadow_offset_y", "Label", 0)

	theme.set_color("default_color", "RichTextLabel", UiStyle.INK)
	theme.set_font("normal_font", "RichTextLabel", UiStyle.font_data())
	theme.set_font_size("normal_font_size", "RichTextLabel", UiStyle.SIZE_BODY)
	## The event log is the one label that sits on bare terrain rather than on a
	## panel, and white text over sunlit grass is unreadable. A RichTextLabel has
	## its own background stylebox, so it carries its own card and fades with the
	## label when the log times out.
	var log_card := UiStyle.flat(Color(0.1176, 0.0902, 0.0667, 0.72), Color(0.7294, 0.5608, 0.3098, 0.3), UiStyle.RADIUS_SLOT)
	log_card.content_margin_left = UiStyle.SPACE_M
	log_card.content_margin_right = UiStyle.SPACE_M
	log_card.content_margin_top = UiStyle.SPACE_S
	log_card.content_margin_bottom = UiStyle.SPACE_S
	theme.set_stylebox("normal", "RichTextLabel", log_card)

	## Section headings and object names, wherever a plain Label needs the
	## display face without a component wrapping it.
	theme.set_type_variation("TitleLabel", "Label")
	theme.set_font("font", "TitleLabel", UiStyle.font_display())
	theme.set_font_size("font_size", "TitleLabel", UiStyle.SIZE_NAME)
	theme.set_color("font_color", "TitleLabel", UiStyle.INK)

	## The dim caption above a value.
	theme.set_type_variation("CaptionLabel", "Label")
	theme.set_font("font", "CaptionLabel", UiStyle.font_display())
	theme.set_font_size("font_size", "CaptionLabel", UiStyle.SIZE_LABEL)
	theme.set_color("font_color", "CaptionLabel", UiStyle.DIM)

	## Numbers line up in columns, so they get the tabular data face.
	theme.set_type_variation("ValueLabel", "Label")
	theme.set_font("font", "ValueLabel", UiStyle.font_data_bold())
	theme.set_font_size("font_size", "ValueLabel", UiStyle.SIZE_VALUE)
	theme.set_color("font_color", "ValueLabel", UiStyle.INK)

	## Dialogue and briefings, the only prose in the game.
	theme.set_type_variation("ProseLabel", "Label")
	theme.set_font("font", "ProseLabel", UiStyle.font_prose())
	theme.set_font_size("font_size", "ProseLabel", UiStyle.SIZE_VALUE)
	theme.set_color("font_color", "ProseLabel", UiStyle.INK)

func _buttons(theme: Theme) -> void:
	theme.set_font("font", "Button", UiStyle.font_display())
	theme.set_font_size("font_size", "Button", UiStyle.SIZE_BUTTON)
	theme.set_color("font_color", "Button", UiStyle.INK)
	theme.set_color("font_hover_color", "Button", UiStyle.ACCENT)
	theme.set_color("font_pressed_color", "Button", UiStyle.ACCENT)
	theme.set_color("font_focus_color", "Button", UiStyle.INK)
	theme.set_color("font_disabled_color", "Button", Color(UiStyle.DIM, 0.42))
	theme.set_stylebox("normal", "Button", UiStyle.button_box())
	theme.set_stylebox("hover", "Button", UiStyle.button_box(UiStyle.LINE_STRONG))
	theme.set_stylebox("pressed", "Button", UiStyle.button_box(UiStyle.ACCENT))
	theme.set_stylebox("focus", "Button", UiStyle.button_box(UiStyle.LINE_STRONG))
	theme.set_stylebox("disabled", "Button", UiStyle.button_box(Color(UiStyle.LINE, 0.22)))

	## Main-menu navigation: text on the ground with an accent bar, not a plate.
	## The menu is a list of destinations, and five stacked plates read as a form.
	theme.set_type_variation("NavButton", "Button")
	theme.set_font("font", "NavButton", UiStyle.font_display())
	theme.set_font_size("font_size", "NavButton", UiStyle.SIZE_CLOCK)
	theme.set_color("font_color", "NavButton", UiStyle.DIM)
	theme.set_color("font_hover_color", "NavButton", UiStyle.ACCENT)
	theme.set_color("font_pressed_color", "NavButton", UiStyle.ACCENT)
	theme.set_color("font_focus_color", "NavButton", UiStyle.ACCENT)
	var nav_idle := UiStyle.empty_box()
	nav_idle.content_margin_left = UiStyle.SPACE_XL
	nav_idle.content_margin_right = UiStyle.SPACE_L
	nav_idle.content_margin_top = 9
	nav_idle.content_margin_bottom = 9
	theme.set_stylebox("normal", "NavButton", nav_idle)
	theme.set_stylebox("disabled", "NavButton", nav_idle)
	var nav_active := UiStyle.flat(Color(0.1176, 0.0902, 0.0667, 0.55), UiStyle.ACCENT, 0, 0)
	nav_active.border_width_left = 3
	nav_active.content_margin_left = UiStyle.SPACE_XL - 3
	nav_active.content_margin_right = UiStyle.SPACE_L
	nav_active.content_margin_top = 9
	nav_active.content_margin_bottom = 9
	theme.set_stylebox("hover", "NavButton", nav_active)
	theme.set_stylebox("pressed", "NavButton", nav_active)
	theme.set_stylebox("focus", "NavButton", nav_active)

	## A vertical rail entry (the options screen's category list). Same idea as
	## NavButton but at body scale, and it is a toggle, so `pressed` carries the
	## active state rather than hover.
	theme.set_type_variation("RailButton", "Button")
	theme.set_font("font", "RailButton", UiStyle.font_display())
	theme.set_font_size("font_size", "RailButton", UiStyle.SIZE_TOOLTIP_NAME)
	theme.set_color("font_color", "RailButton", UiStyle.DIM)
	theme.set_color("font_hover_color", "RailButton", UiStyle.INK)
	theme.set_color("font_pressed_color", "RailButton", UiStyle.ACCENT)
	theme.set_color("font_focus_color", "RailButton", UiStyle.ACCENT)
	var rail_idle := UiStyle.empty_box()
	rail_idle.content_margin_left = UiStyle.SPACE_M
	rail_idle.content_margin_right = UiStyle.SPACE_M
	rail_idle.content_margin_top = 9
	rail_idle.content_margin_bottom = 9
	theme.set_stylebox("normal", "RailButton", rail_idle)
	theme.set_stylebox("hover", "RailButton", rail_idle)
	theme.set_stylebox("disabled", "RailButton", rail_idle)
	var rail_active := UiStyle.flat(Color(0.0706, 0.0510, 0.0353, 0.5), UiStyle.ACCENT, 0, 0)
	rail_active.border_width_left = 3
	rail_active.content_margin_left = UiStyle.SPACE_M - 3
	rail_active.content_margin_right = UiStyle.SPACE_M
	rail_active.content_margin_top = 9
	rail_active.content_margin_bottom = 9
	theme.set_stylebox("pressed", "RailButton", rail_active)
	theme.set_stylebox("focus", "RailButton", rail_active)

	## The square utility buttons beside the minimap: a slot, not a plate.
	theme.set_type_variation("SquareButton", "Button")
	theme.set_font("font", "SquareButton", UiStyle.font_data_bold())
	theme.set_font_size("font_size", "SquareButton", UiStyle.SIZE_BODY)
	theme.set_color("font_color", "SquareButton", UiStyle.DIM)
	theme.set_color("font_hover_color", "SquareButton", UiStyle.ACCENT)
	theme.set_color("font_pressed_color", "SquareButton", UiStyle.ACCENT)
	theme.set_stylebox("normal", "SquareButton", UiStyle.slot_box())
	theme.set_stylebox("hover", "SquareButton", UiStyle.slot_box(UiStyle.LINE_STRONG))
	theme.set_stylebox("pressed", "SquareButton", UiStyle.slot_box(UiStyle.ACCENT))
	theme.set_stylebox("focus", "SquareButton", UiStyle.slot_box(UiStyle.LINE_STRONG))
	theme.set_stylebox("disabled", "SquareButton", UiStyle.slot_box(Color(UiStyle.LINE, 0.22)))

func _panels(theme: Theme) -> void:
	var panel := UiStyle.panel_box()
	panel.content_margin_left = UiStyle.SPACE_L
	panel.content_margin_right = UiStyle.SPACE_L
	panel.content_margin_top = UiStyle.SPACE_L
	panel.content_margin_bottom = UiStyle.SPACE_L
	theme.set_stylebox("panel", "Panel", panel)
	theme.set_stylebox("panel", "PanelContainer", panel)

	var modal := UiStyle.panel_box()
	modal.content_margin_left = 32
	modal.content_margin_right = 32
	modal.content_margin_top = 30
	modal.content_margin_bottom = 28
	theme.set_type_variation("ModalPanel", "PanelContainer")
	theme.set_stylebox("panel", "ModalPanel", modal)

	theme.set_stylebox("panel", "PopupPanel", UiStyle.tooltip_box())
	## Godot wraps a custom tooltip in this, so the popup carries the brass
	## surface and UiTooltip only has to supply the words.
	theme.set_stylebox("panel", "TooltipPanel", UiStyle.tooltip_box())
	theme.set_color("font_color", "TooltipLabel", UiStyle.INK)
	theme.set_font("font", "TooltipLabel", UiStyle.font_data())
	theme.set_font_size("font_size", "TooltipLabel", UiStyle.SIZE_BODY)

func _inputs(theme: Theme) -> void:
	var well := UiStyle.slot_box()
	well.content_margin_left = UiStyle.SPACE_M
	well.content_margin_right = UiStyle.SPACE_M
	well.content_margin_top = 9
	well.content_margin_bottom = 9
	theme.set_stylebox("normal", "LineEdit", well)
	theme.set_stylebox("focus", "LineEdit", UiStyle.slot_box(UiStyle.ACCENT))
	theme.set_color("font_color", "LineEdit", UiStyle.INK)
	theme.set_color("font_placeholder_color", "LineEdit", Color(UiStyle.DIM, 0.7))
	theme.set_color("caret_color", "LineEdit", UiStyle.ACCENT)

	theme.set_stylebox("normal", "OptionButton", well)
	theme.set_stylebox("hover", "OptionButton", UiStyle.slot_box(UiStyle.LINE_STRONG))
	theme.set_stylebox("pressed", "OptionButton", UiStyle.slot_box(UiStyle.ACCENT))
	theme.set_stylebox("focus", "OptionButton", UiStyle.slot_box(UiStyle.LINE_STRONG))
	theme.set_stylebox("disabled", "OptionButton", UiStyle.slot_box(Color(UiStyle.LINE, 0.22)))
	theme.set_font("font", "OptionButton", UiStyle.font_data())
	theme.set_font_size("font_size", "OptionButton", UiStyle.SIZE_BODY)
	theme.set_color("font_color", "OptionButton", UiStyle.INK)

	theme.set_stylebox("normal", "SpinBox", well)
	theme.set_stylebox("panel", "PopupMenu", UiStyle.tooltip_box())
	theme.set_color("font_color", "PopupMenu", UiStyle.INK)
	theme.set_color("font_hover_color", "PopupMenu", UiStyle.ACCENT)
	theme.set_font("font", "PopupMenu", UiStyle.font_data())
	theme.set_font_size("font_size", "PopupMenu", UiStyle.SIZE_BODY)

	var grabber := UiStyle.flat(UiStyle.ACCENT, UiStyle.ACCENT, 8)
	theme.set_stylebox("grabber_area", "HSlider", grabber)
	theme.set_stylebox("grabber_area_highlight", "HSlider", grabber)
	theme.set_stylebox("slider", "HSlider", UiStyle.flat(UiStyle.SLOT, UiStyle.LINE, 4))

func _containers(theme: Theme) -> void:
	theme.set_constant("separation", "HBoxContainer", UiStyle.SPACE_S)
	theme.set_constant("separation", "VBoxContainer", UiStyle.SPACE_S)

func _progress(theme: Theme) -> void:
	theme.set_stylebox("background", "ProgressBar", UiStyle.slot_box())
	theme.set_stylebox("fill", "ProgressBar", UiStyle.flat(UiStyle.ACCENT, UiStyle.ACCENT, UiStyle.RADIUS_SLOT))
	theme.set_color("font_color", "ProgressBar", UiStyle.INK)
	theme.set_font("font", "ProgressBar", UiStyle.font_data_bold())
	theme.set_font_size("font_size", "ProgressBar", UiStyle.SIZE_LABEL)

func _lists(theme: Theme) -> void:
	theme.set_stylebox("panel", "ItemList", UiStyle.slot_box())
	theme.set_stylebox("selected", "ItemList", UiStyle.flat(Color(UiStyle.ACCENT, 0.22), UiStyle.ACCENT, UiStyle.RADIUS_SLOT))
	theme.set_stylebox("selected_focus", "ItemList", UiStyle.flat(Color(UiStyle.ACCENT, 0.22), UiStyle.ACCENT, UiStyle.RADIUS_SLOT))
	theme.set_stylebox("hovered", "ItemList", UiStyle.flat(Color(UiStyle.LINE, 0.12), Color(UiStyle.LINE, 0.3), UiStyle.RADIUS_SLOT))
	theme.set_color("font_color", "ItemList", UiStyle.INK)
	theme.set_color("font_selected_color", "ItemList", UiStyle.ACCENT)
	theme.set_font("font", "ItemList", UiStyle.font_data())
	theme.set_font_size("font_size", "ItemList", UiStyle.SIZE_BODY)

	theme.set_stylebox("panel", "ScrollContainer", UiStyle.empty_box())
	theme.set_stylebox("tab_selected", "TabContainer", UiStyle.flat(UiStyle.SURFACE, UiStyle.LINE_STRONG, UiStyle.RADIUS))
	theme.set_stylebox("tab_unselected", "TabContainer", UiStyle.flat(UiStyle.SLOT, UiStyle.LINE, UiStyle.RADIUS))

## Checkbox art is GENERATED from the tokens rather than cut from the tilesheet:
## the sheet's gold glyphs were the last bitmap in the options screen and read as
## tiny diamonds next to brass wells. A bordered well with an accent block in it
## is unambiguous and needs no art.
func _check_texture(checked: bool) -> ImageTexture:
	var size := 22
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(UiStyle.SLOT)
	for i in size:
		image.set_pixel(i, 0, UiStyle.LINE)
		image.set_pixel(i, size - 1, UiStyle.LINE)
		image.set_pixel(0, i, UiStyle.LINE)
		image.set_pixel(size - 1, i, UiStyle.LINE)
	if checked:
		for y in range(5, size - 5):
			for x in range(5, size - 5):
				image.set_pixel(x, y, UiStyle.ACCENT)
	return ImageTexture.create_from_image(image)

func _checks(theme: Theme) -> void:
	var on := _check_texture(true)
	var off := _check_texture(false)
	for type in ["CheckBox", "CheckButton"]:
		theme.set_icon("checked", type, on)
		theme.set_icon("unchecked", type, off)
		theme.set_icon("checked_disabled", type, on)
		theme.set_icon("unchecked_disabled", type, off)
		theme.set_stylebox("normal", type, UiStyle.empty_box(UiStyle.SPACE_S))
		theme.set_stylebox("hover", type, UiStyle.empty_box(UiStyle.SPACE_S))
		theme.set_stylebox("pressed", type, UiStyle.empty_box(UiStyle.SPACE_S))
		theme.set_stylebox("disabled", type, UiStyle.empty_box(UiStyle.SPACE_S))
		theme.set_stylebox("focus", type, UiStyle.empty_box(UiStyle.SPACE_S))
		theme.set_font("font", type, UiStyle.font_data())
		theme.set_font_size("font_size", type, UiStyle.SIZE_BODY)
		theme.set_color("font_color", type, UiStyle.INK)
		theme.set_color("font_hover_color", type, UiStyle.ACCENT)
