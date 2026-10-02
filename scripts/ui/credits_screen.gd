class_name CreditsScreen
extends Control
## Full-screen rolling credits over the main menu backdrop. The roll climbs from
## below the screen, and starts again from the bottom once it has passed the top.
## Escape, a click or Back closes it.

signal closed

const LOGO_PATH: String = "res://assets/art/Logos/Little Keep Games Logo.png"
const ROLL_WIDTH: int = 760
const SCROLL_SPEED: float = 55.0

## [heading, [[work, author], ...]]. An empty work puts the author on its own.
const SECTIONS: Array = [
	["Design & Development", [
		["", "Craig Spreadbury"],
	]],
	["Music", [
		["Original soundtrack", "Created with Suno"],
	]],
	["Characters", [
		["MiniFolks: Humans, Villagers 2, Forest Animals", "LYASeeK"],
		["MiniFolks Plus: Dark Elves, Gnolls, Beastmens, Big Monsters, Mythical Creatures", "Dreamir"],
		["MiniFolks Star Wanderers", "Dreamir"],
	]],
	["Environment", [
		["Free Stylized Low Poly Forest & Nature Pack", "AmiPolyGon"],
		["Forgotten Memories 32x32 Tileset", "Immunity"],
		["Stylized Grass Shader", "Binbun"],
	]],
	["Interface", [
		["Dark Ages UI", "Hypnobius"],
		["Icons from game-icons.net", "Lorc, Delapouite, Skoll, Sbed, Carl Olsen, Caro Asercion, Cathelineau, DarkZaitzev, Faithtoken, Kier Heyl and Sparker (CC BY 3.0)"],
	]],
	["Sound", [
		["Universal UI/Menu Soundpack", "Nathan Gibson (CC BY 4.0)"],
		["Human Settlement RTS SFX", "Leohpaz"],
		["Inventory SFX Pack", "Leohpaz"],
		["Free Fantasy 200 SFX Pack", "TomMusic"],
		["Park Ambiance", "klankbeeld, freesound.org"],
	]],
	["Fonts", [
		["Marcellus SC", "Astigmatic (SIL Open Font License 1.1)"],
		["Barlow Semi Condensed", "The Barlow Project Authors (SIL Open Font License 1.1)"],
		["Spectral", "Production Type (SIL Open Font License 1.1)"],
		["MedievalSharp", "Wojciech Kalinowski (SIL Open Font License 1.1)"],
	]],
	["Engine & Plugins", [
		["Godot Engine", "Juan Linietsky, Ariel Manzur and contributors (MIT)"],
		["TerraBrush", "spimort (MIT)"],
		["TileMapLayer3D", "DanTrz (MIT)"],
		["GodotSteam", "GP Garcia, Chris Ridenour and contributors (MIT)"],
	]],
]

var _roll: VBoxContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	set_process(false)

	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.82)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var clip := Control.new()
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(clip)
	clip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_roll = VBoxContainer.new()
	_roll.custom_minimum_size = Vector2(ROLL_WIDTH, 0)
	_roll.add_theme_constant_override("separation", UiStyle.SPACE_XS)
	_roll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(_roll)
	_build_roll()

	var back := UiButton.new()
	back.text = "Back"
	back.pressed.connect(close)
	add_child(back)
	_pin_bottom_right(back)

## Anchored to the corner and grown up/left, so it keeps its margin whatever
## size the button's text makes it.
static func _pin_bottom_right(control: Control) -> void:
	control.anchor_left = 1.0
	control.anchor_top = 1.0
	control.anchor_right = 1.0
	control.anchor_bottom = 1.0
	control.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	control.grow_vertical = Control.GROW_DIRECTION_BEGIN
	control.offset_left = -UiStyle.SCREEN_MARGIN
	control.offset_right = -UiStyle.SCREEN_MARGIN
	control.offset_top = -UiStyle.SCREEN_MARGIN
	control.offset_bottom = -UiStyle.SCREEN_MARGIN

func open() -> void:
	visible = true
	set_process(true)
	_restart_roll()

func close() -> void:
	visible = false
	set_process(false)
	closed.emit()

func _process(delta: float) -> void:
	_roll.position.y -= SCROLL_SPEED * delta
	_roll.position.x = (size.x - _roll.size.x) * 0.5
	if _roll.position.y + _roll.size.y < 0.0:
		_restart_roll()

func _restart_roll() -> void:
	_roll.position = Vector2((size.x - _roll.size.x) * 0.5, size.y)

## _input so Escape never also reaches the menu underneath.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()
		accept_event()

## --- Roll contents ---

func _build_roll() -> void:
	var logo := TextureRect.new()
	logo.texture = load(LOGO_PATH)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(0, 220)
	_roll.add_child(logo)

	var title := _line("Crowns of Aldmere", UiStyle.font_display(), UiStyle.SIZE_GAME_TITLE, UiStyle.INK)
	_roll.add_child(title)
	_roll.add_child(_gap(UiStyle.SPACE_XL * 3))

	for section in SECTIONS:
		_roll.add_child(_line(section[0].to_upper(), UiStyle.font_display(), UiStyle.SIZE_TAB, UiStyle.ACCENT))
		_roll.add_child(_gap(UiStyle.SPACE_S))
		for entry in section[1]:
			if entry[0] != "":
				_roll.add_child(_line(entry[0], UiStyle.font_display(), UiStyle.SIZE_NAME, UiStyle.INK))
			_roll.add_child(_line(entry[1], UiStyle.font_prose(), UiStyle.SIZE_BODY,
					UiStyle.INK if entry[0] == "" else UiStyle.DIM))
			_roll.add_child(_gap(UiStyle.SPACE_M))
		_roll.add_child(_gap(UiStyle.SPACE_XL * 2))

	_roll.add_child(_line("Thank you for playing", UiStyle.font_display(), UiStyle.SIZE_MODAL_TITLE, UiStyle.INK))

func _line(text: String, font: Font, font_size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	return label

func _gap(height: int) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, height)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap
