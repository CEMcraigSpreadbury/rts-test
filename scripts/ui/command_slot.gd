class_name CommandSlot
extends Button
## One cell of a command grid.
##
## Buildings and actions show their hotkey LETTER and nothing else: no icon, no
## cost number. Affordability is carried by the letter's colour instead, so the
## slot stays a single readable glyph. Units show their real sprite, because that
## art comes from the game itself, at 1x of its 32px source.

enum State { NORMAL, SELECTED, UNAFFORDABLE, LOCKED, EMPTY }

var state: State = State.NORMAL:
	set(value):
		state = value
		_restyle()

var _letter: Label
var _icon: TextureRect
var _badge: Label
var _tip_name: String = ""
var _tip_costs: Array = []
var _tip_hotkey: String = ""

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

## A unit: its own sprite at 1x, with the hotkey as a small corner badge.
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
		_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_badge.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		_badge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_badge.offset_right = -3
		_badge.offset_bottom = -1
		add_child(_badge)
	_badge.text = hotkey
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

func _make_custom_tooltip(_for_text: String) -> Object:
	if _tip_name.is_empty():
		return null
	return UiTooltip.build(_tip_name, _tip_costs, _tip_hotkey)
