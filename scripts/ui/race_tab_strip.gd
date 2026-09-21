class_name RaceTabStrip
extends HBoxContainer
## The pact race tabs above the build menu.
##
## The strip is deliberately NOT a child of the panel's content: it sits above
## the panel's top edge so that switching race cannot change the panel's size,
## and it starts at the panel's inset so it clears the top-left corner cap.
## It is only ever shown for a unit that can build.

signal race_selected(race_id: StringName)

const OFFSET_FROM_INSET: int = UiStyle.SPACE_L

var _buttons: Dictionary = {}
var _selected: StringName = &""
var _spec: Array = []

func _init() -> void:
	add_theme_constant_override("separation", 3)

## `unlocked` false renders the tab dimmed and inert -- a pact not yet sealed is
## shown so the player knows it exists, not hidden.
func add_race(race_id: StringName, display_name: String, pip: Color, unlocked: bool) -> void:
	var tab := Button.new()
	tab.text = display_name
	tab.focus_mode = Control.FOCUS_NONE
	tab.disabled = not unlocked
	tab.add_theme_font_override("font", UiStyle.font_display())
	tab.add_theme_font_size_override("font_size", UiStyle.SIZE_TAB)
	tab.add_theme_constant_override("h_separation", 7)
	if unlocked:
		tab.icon = _pip_texture(pip)
		tab.pressed.connect(func() -> void: select_race(race_id))
	else:
		tab.icon = _pip_texture(Color(UiStyle.DIM, 0.42))
	_buttons[race_id] = tab
	add_child(tab)
	if unlocked and _selected == &"":
		select_race(race_id)
	else:
		_restyle()

func select_race(race_id: StringName) -> void:
	if not _buttons.has(race_id):
		return
	_selected = race_id
	_restyle()
	race_selected.emit(race_id)

func selected_race() -> StringName:
	return _selected

func _restyle() -> void:
	for race_id: StringName in _buttons:
		var tab: Button = _buttons[race_id]
		var active: bool = race_id == _selected
		var box := UiStyle.flat(
			UiStyle.SURFACE if active else UiStyle.SLOT,
			UiStyle.LINE_STRONG if active else UiStyle.LINE,
			UiStyle.RADIUS)
		box.border_width_bottom = 0
		box.corner_radius_bottom_left = 0
		box.corner_radius_bottom_right = 0
		box.content_margin_left = UiStyle.SPACE_L + 1
		box.content_margin_right = UiStyle.SPACE_L + 1
		box.content_margin_top = 7
		box.content_margin_bottom = 6
		tab.add_theme_stylebox_override("normal", box)
		tab.add_theme_stylebox_override("hover", box)
		tab.add_theme_stylebox_override("pressed", box)
		tab.add_theme_stylebox_override("disabled", box)
		var ink := UiStyle.ACCENT if active else UiStyle.DIM
		tab.add_theme_color_override("font_color", ink)
		tab.add_theme_color_override("font_hover_color", UiStyle.INK if not active else ink)
		tab.add_theme_color_override("font_pressed_color", ink)
		tab.add_theme_color_override("font_disabled_color", Color(UiStyle.DIM, 0.42))

## A tab's race is identified by a small colour dot, drawn rather than shipped as
## an asset so a new pact race needs no new art.
static func _pip_texture(colour: Color) -> ImageTexture:
	var size := 7
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var centre := (size - 1) * 0.5
	for y in size:
		for x in size:
			if Vector2(x - centre, y - centre).length() <= centre + 0.15:
				image.set_pixel(x, y, colour)
	return ImageTexture.create_from_image(image)

## Rebuilds the whole strip from a spec of
## {id: StringName, name: String, colour: Color, unlocked: bool}.
## Used instead of add_race when the set of races can change mid-match -- a Pact
## sealed during play adds a tab.
func rebuild(spec: Array) -> void:
	var previous := _selected
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_buttons.clear()
	_selected = &""
	_spec = spec.duplicate(true)
	for entry: Dictionary in spec:
		add_race(entry["id"], entry["name"], entry["colour"], entry["unlocked"])
	## Keep the player on the tab they were on if it is still unlocked.
	if _buttons.has(previous) and not (_buttons[previous] as Button).disabled:
		select_race(previous)

## True when the strip already shows exactly this spec, so a refresh that
## changes nothing does not rebuild the buttons and drop the selection.
func matches(spec: Array) -> bool:
	if spec.size() != _spec.size():
		return false
	for i in spec.size():
		var a: Dictionary = spec[i]
		var b: Dictionary = _spec[i]
		if a["id"] != b["id"] or a["unlocked"] != b["unlocked"]:
			return false
	return true
