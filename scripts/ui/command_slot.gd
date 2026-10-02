class_name CommandSlot
extends Button
## One cell of a command grid.
##
## Anything with art shows it, with the hotkey as a small corner badge: pixel
## art at 1x of its 32px source, or a command's glyph (UiGlyphs) tinted brass.
## Anything with neither falls back to its hotkey letter alone. No cost number
## either way: affordability is carried by colour, a red wash over the art, a
## red glyph or a red letter.

enum State { NORMAL, SELECTED, UNAFFORDABLE, LOCKED, EMPTY }

## Over the art of something the player cannot pay for yet.
const UNAFFORDABLE_ICON_TINT := Color(1.0, 0.5, 0.45, 0.8)
const BADGE_OUTLINE := Color(0.0706, 0.0510, 0.0353)
const BADGE_OUTLINE_SIZE: int = 4
## A glyph at rest: halfway between DIM and INK, so it reads beside pixel art
## without outshining it. Hover, press and selection take it to ACCENT.
const GLYPH_TINT := Color(0.8275, 0.7706, 0.6784)
## Glyphs sit this far above centre, clear of the hotkey badge.
const GLYPH_LIFT: float = 3.0

var state: State = State.NORMAL:
	set(value):
		state = value
		_restyle()

var _letter: Label
var _icon: TextureRect
var _badge: Label
## The icon is a glyph rather than pixel art (see setup_glyph).
var _glyph: bool = false
var _tip_name: String = ""
var _tip_costs: Array = []
var _tip_hotkey: String = ""
## Under the name in the tooltip (buildings and upgrades).
var tip_description: String = ""

func _init() -> void:
	custom_minimum_size = Vector2(UiStyle.SLOT_CMD, UiStyle.SLOT_CMD)
	focus_mode = Control.FOCUS_NONE
	## The default tooltip would pop the theme's own panel with plain text in it;
	## _make_custom_tooltip below replaces the contents, and this makes Godot
	## actually ask for one.
	tooltip_text = " "
	_restyle()

## A building or an action: one letter, centred.
func setup_letter(letter: String, display_name: String, costs: Array = []) -> void:
	_tip_name = display_name
	_tip_costs = costs
	_tip_hotkey = ""
	if _letter == null:
		_letter = Label.new()
		_letter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_letter.add_theme_font_override("font", UiStyle.font_display())
		_letter.add_theme_font_size_override("font_size", UiStyle.SIZE_SLOT_LETTER)
		add_child(_letter)
	_letter.text = letter
	_restyle()

## Art at 1x, with the hotkey as a small corner badge.
func setup_icon(texture: Texture2D, hotkey: String, display_name: String, costs: Array = []) -> void:
	_tip_name = display_name
	_tip_costs = costs
	_tip_hotkey = ""
	if _icon == null:
		_icon = TextureRect.new()
		_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		## Anchored rather than positioned, so the same slot works at 50px in a
		## command grid and 40px in a production queue.
		_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		UiStyle.make_pixel_crisp(_icon)
		add_child(_icon)
	_icon.texture = texture
	if _badge == null:
		_badge = Label.new()
		_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_badge.add_theme_font_override("font", UiStyle.font_data_bold())
		_badge.add_theme_font_size_override("font_size", UiStyle.SIZE_BADGE)
		_badge.add_theme_color_override("font_color", UiStyle.DIM)
		## The badge sits on the art itself, and vanished against a bright roof.
		_badge.add_theme_color_override("font_outline_color", BADGE_OUTLINE)
		_badge.add_theme_constant_override("outline_size", BADGE_OUTLINE_SIZE)
		_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_badge.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		_badge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_badge.offset_right = -3
		_badge.offset_bottom = -1
		add_child(_badge)
	_badge.text = hotkey
	_restyle()

## A command with no art of its own: its glyph, centred and lifted clear of
## the badge, drawn 1:1 at GLYPH_CMD and tinted by state (see _glyph_tint).
func setup_glyph(glyph: StringName, hotkey: String, display_name: String, costs: Array = []) -> void:
	setup_icon(UiGlyphs.texture(glyph, UiStyle.GLYPH_CMD), hotkey, display_name, costs)
	_glyph = true
	var half: float = UiStyle.GLYPH_CMD * 0.5
	_icon.set_anchors_preset(Control.PRESET_CENTER)
	_icon.offset_left = -half
	_icon.offset_right = half
	_icon.offset_top = -half - GLYPH_LIFT
	_icon.offset_bottom = half - GLYPH_LIFT
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_restyle()

## A padding cell in a fixed grid: visible, obviously not a control.
func make_empty() -> void:
	state = State.EMPTY
	disabled = true
	tooltip_text = ""
	if _letter != null:
		_letter.text = ""
	if _badge != null:
		_badge.text = ""
	if _icon != null:
		_icon.texture = null

func _restyle() -> void:
	var border := UiStyle.LINE
	var letter_colour := UiStyle.INK
	match state:
		State.SELECTED:
			border = UiStyle.ACCENT
			letter_colour = UiStyle.ACCENT
		State.UNAFFORDABLE:
			letter_colour = UiStyle.BAD
		State.LOCKED:
			letter_colour = UiStyle.DIM
		State.EMPTY:
			pass
	var normal := UiStyle.empty_slot_box() if state == State.EMPTY else UiStyle.slot_box(border)
	add_theme_stylebox_override("normal", normal)
	add_theme_stylebox_override("disabled", normal)
	add_theme_stylebox_override("hover", normal if state == State.EMPTY else UiStyle.slot_box(UiStyle.LINE_STRONG))
	add_theme_stylebox_override("pressed", normal if state == State.EMPTY else UiStyle.slot_box(UiStyle.ACCENT))
	modulate = UiStyle.DISABLED_MODULATE if state == State.LOCKED else Color.WHITE
	if _letter != null:
		_letter.add_theme_color_override("font_color", letter_colour)
	if _badge != null:
		_badge.add_theme_color_override("font_color", UiStyle.DIM if state == State.NORMAL else letter_colour)
	if _icon != null:
		_icon.modulate = UNAFFORDABLE_ICON_TINT if state == State.UNAFFORDABLE and not _glyph else Color.WHITE
	queue_redraw()

## A Button redraws whenever it is hovered, pressed or toggled (the Hold button
## is toggled without a signal), so that is where a glyph takes its colour.
func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAW and _glyph and _icon != null:
		_icon.self_modulate = _glyph_tint()

func _glyph_tint() -> Color:
	if state == State.UNAFFORDABLE:
		return UiStyle.BAD
	if state == State.SELECTED:
		return UiStyle.ACCENT
	match get_draw_mode():
		DRAW_HOVER, DRAW_PRESSED, DRAW_HOVER_PRESSED:
			return UiStyle.ACCENT
	return GLYPH_TINT

func _make_custom_tooltip(_for_text: String) -> Object:
	if _tip_name.is_empty():
		return null
	return UiTooltip.build(_tip_name, _tip_costs, _tip_hotkey, tip_description)
