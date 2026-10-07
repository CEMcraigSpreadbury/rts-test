class_name UiStyle
extends RefCounted
## Toy-plastic design tokens -- the single source of truth for every colour,
## size and face in the game's UI. Nothing else declares a UI colour.
##
## The look: moulded plastic pieces from the same toy set as the battlefield.
## Panels are smoked translucent plastic frosting the battle behind them
## (UiPlasticBody), keys and buttons are solid plastic with a lip and a soft
## shadow (UiPlasticBox), sockets are dips moulded into the panel. The living
## mockup is https://claude.ai/artifact/TR29NUsZULdSuVvJZC5nvk.
##
## The theme resource is GENERATED from these values, it is not hand-authored:
##   godot --path . --headless --script res://scripts/tools/build_ui_theme.gd
## Run that after changing anything here, or the .tres and the components drift.
##
## Authored against a 1920x1080 base viewport, so every number below is a real
## screen pixel at 1080p and matches the mockup 1:1.

# ---------------------------------------------------------------- colour
## The plastic every panel is moulded from ("Smoke").
const TRAY := Color(0.1843, 0.2039, 0.2235)               # 2F3439
## How opaque a panel's plastic is over the frosted battle behind it.
const PANEL_OPACITY: float = 0.8
## A panel body where something must draw one without UiPlasticBody.
const SURFACE := Color(0.1843, 0.2039, 0.2235, 0.8)
## Plain keys and buttons: the same plastic, solid.
const RAISED := TRAY
## The player's keys: command buttons, the primary button, the portrait.
const KEY := Color(0.2392, 0.3725, 0.6588)                # 3D5FA8
## Recessed sockets: command slots, stat tiles, text inputs, bar tracks.
const SLOT := Color(0.0, 0.0, 0.0, 0.2)
## Hairlines: dividers and quiet outlines.
const LINE := Color(1.0, 1.0, 1.0, 0.1)
## A hovered or emphasised outline.
const LINE_STRONG := Color(1.0, 1.0, 1.0, 0.3)
## Primary text.
const INK := Color(0.9333, 0.9412, 0.9255)                # EEF0EC
## Labels, hotkey badges, timestamps.
const DIM := Color(0.6627, 0.6902, 0.7020)                # A9B0B3
## Spent only on selection, progress, the active tab.
const ACCENT := Color(0.9098, 0.7765, 0.4157)             # E8C66A
## Text that sits on top of ACCENT.
const ACCENT_INK := Color(0.1686, 0.1412, 0.0627)         # 2B2410
const GOOD := Color(0.5255, 0.7176, 0.3961)               # 86B765
const BAD := Color(0.8784, 0.4392, 0.3608)                # E0705C
## A destructive button's plastic (Surrender, Quit).
const DANGER := Color(0.6627, 0.2667, 0.2039)             # A94434
## Wavering morale (a routing one uses BAD).
const WAVER := Color(0.8902, 0.5255, 0.2275)              # E3863A
## Tooltips are near-opaque: they must stay readable over whatever they cover.
const TOOLTIP_BG := Color(0.1843, 0.2039, 0.2235, 0.96)
## Disabled controls keep their shape and lose their contrast.
const DISABLED_MODULATE := Color(1.0, 1.0, 1.0, 0.34)

# ---------------------------------------------------------------- metrics
## Panels.
const RADIUS: int = 16
## Keys, buttons, tooltips.
const RADIUS_KEY: int = 12
## Sockets and bar tracks.
const RADIUS_SLOT: int = 10
const BORDER: int = 1
## The moulded lip under a panel and under a key.
const LIP: int = 3

const SPACE_XS: int = 4
const SPACE_S: int = 8
const SPACE_M: int = 12
const SPACE_L: int = 14
const SPACE_XL: int = 22
## Distance from a screen edge to a docked module.
const SCREEN_MARGIN: int = 24

# ---------------------------------------------------------------- type
const FONT_DISPLAY_PATH: String = "res://assets/fonts/Fraunces-Variable.ttf"
const FONT_DATA_PATH: String = "res://assets/fonts/BarlowSemiCondensed-SemiBold.ttf"
const FONT_DATA_BOLD_PATH: String = "res://assets/fonts/BarlowSemiCondensed-Bold.ttf"
const FONT_PROSE_PATH: String = "res://assets/fonts/Spectral-Regular.ttf"

const SIZE_BADGE: int = 12
const SIZE_COST: int = 13
const SIZE_LABEL: int = 15
const SIZE_TAB: int = 16
const SIZE_BODY: int = 17
const SIZE_TOOLTIP_NAME: int = 19
const SIZE_BUTTON: int = 20
const SIZE_VALUE: int = 21
## The stockpile totals, the HUD's biggest numbers.
const SIZE_STOCK: int = 26
const SIZE_NAME: int = 22
## The selection panel's name line.
const SIZE_SELECTION_NAME: int = 28
const SIZE_SLOT_LETTER: int = 25
const SIZE_CLOCK: int = 26
const SIZE_MODAL_TITLE: int = 34
const SIZE_GAME_TITLE: int = 62

# ---------------------------------------------------------------- control sizes
const SLOT_CMD: int = 52
const SLOT_QUEUE: int = 44
const SLOT_TOOL: int = 44
const SLOT_POINT: int = 30
const PORTRAIT: int = 120
const MINIMAP: int = 264
## Pixel art renders at 1x or 2x of its 32px source and never in between --
## anything else smears it however it is filtered.
const ICON_1X: int = 32
const ICON_2X: int = 64
## Glyphs (UiGlyphs) are vector and drawn at exactly these sizes: in a command
## slot, a tool button, a stockpile cell, a tooltip's cost line and a capture
## point slot.
const GLYPH_CMD: int = 32
const GLYPH_QUEUE: int = 24
## A research node's glyph, beside its name.
const GLYPH_NODE: int = 40
## A selected building's portrait (a 104 well) and a Lord's tab (44).
const GLYPH_PORTRAIT: int = 64
const GLYPH_TAB: int = 28
const GLYPH_TOOL: int = 22
const GLYPH_STOCK: int = 28
const GLYPH_TIP: int = 15
const GLYPH_POINT: int = 22

## The selection panel never changes size, whatever is selected.
const SEL_PANEL_SIZE := Vector2(702, 238)
## Gaps in the command grid and the queue row.
const SLOT_GAP: int = 8
## Command grid is a fixed 9 x 2; a sparse menu pads with empties.
const CMD_COLUMNS: int = 9
const CMD_ROWS: int = 2

# ---------------------------------------------------------------- fonts, lazily
## Loaded on demand, never in a static initialiser -- those run before autoloads
## are ready and have broken this project's scripts at compile time before.
static var _display: FontVariation
static var _data: FontFile
static var _data_bold: FontFile
static var _prose: FontFile

## Fraunces is a variable font: SemiBold, at the soft end of its SOFT axis
## (rounded terminals that sit with the plastic), cut for display sizes.
static func font_display() -> Font:
	if _display == null:
		var ts := TextServerManager.get_primary_interface()
		_display = FontVariation.new()
		_display.base_font = load(FONT_DISPLAY_PATH)
		_display.variation_opentype = {
			ts.name_to_tag("wght"): 600,
			ts.name_to_tag("SOFT"): 100,
			ts.name_to_tag("opsz"): 48,
		}
	return _display

static func font_data() -> FontFile:
	if _data == null:
		_data = load(FONT_DATA_PATH)
	return _data

static func font_data_bold() -> FontFile:
	if _data_bold == null:
		_data_bold = load(FONT_DATA_BOLD_PATH)
	return _data_bold

static func font_prose() -> FontFile:
	if _prose == null:
		_prose = load(FONT_PROSE_PATH)
	return _prose

# ---------------------------------------------------------------- style boxes
## Public because components build their own variants from it (a tab needs a
## box with no bottom border, for instance).
static func flat(bg: Color, border: Color, radius: int, border_width: int = BORDER) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	return box

## A panel body for code that can't add a UiPlasticBody (a theme Panel used
## bare): the translucent plastic and its lip, without the frosting or the
## drop shadow (which a stylebox would paint under the translucent face).
## Content margins are the caller's business, because a docked module and a
## modal want different insets from the same material.
static func panel_box() -> UiPlasticBox:
	var box := UiPlasticBox.new()
	box.base = SURFACE
	box.radius = RADIUS
	box.lip = LIP
	box.lip_darken = 0.4
	box.shadow_alpha = 0.0
	box.hi = 0.09
	box.lo = 0.05
	box.rim = 0.3
	return box

enum KeyState { NORMAL, HOVER, PRESSED, SELECTED, DISABLED }

## A solid plastic key in `base` (KEY for the player's own, RAISED for a plain
## one, DANGER for a destructive one).
static func key_box(base: Color = RAISED, state: KeyState = KeyState.NORMAL) -> UiPlasticBox:
	var box := UiPlasticBox.new()
	box.radius = RADIUS_KEY
	box.lip = LIP
	box.base = base
	match state:
		KeyState.HOVER:
			box.base = base.lightened(0.08)
		KeyState.PRESSED:
			box.pressed = true
		KeyState.SELECTED:
			box.pressed = true
			box.ring = ACCENT
		KeyState.DISABLED:
			var grey := base.get_luminance()
			box.base = base.lerp(Color(grey, grey, grey), 0.85)
			box.shadow_alpha = 0.2
	return box

## A team colour as UI plastic: the game's team colours are tuned to read on
## the battlefield and come out loud on a key, so they are muted a step.
static func plastic(tint: Color) -> Color:
	var grey := tint.get_luminance()
	return tint.lerp(Color(grey, grey, grey), 0.25).darkened(0.2)

## A key sized as a text button: the padding around its label.
static func button_box(base: Color = RAISED, state: KeyState = KeyState.NORMAL) -> UiPlasticBox:
	var box := key_box(base, state)
	box.content_margin_left = 28
	box.content_margin_right = 28
	box.content_margin_top = 12
	box.content_margin_bottom = 14
	return box

## A recessed socket. Pass ACCENT for a selected one, BAD for an unaffordable
## one; LINE (the default) leaves it unoutlined.
static func slot_box(border: Color = LINE) -> UiPlasticBox:
	var box := UiPlasticBox.new()
	box.kind = UiPlasticBox.Kind.WELL
	box.base = SLOT
	box.radius = RADIUS_SLOT
	if border != LINE:
		box.ring = border
	return box

## An empty socket in a fixed grid: present, obviously not a control.
static func empty_slot_box() -> UiPlasticBox:
	var box := slot_box()
	box.base = Color(0, 0, 0, 0.12)
	return box

static func tooltip_box() -> UiPlasticBox:
	var box := UiPlasticBox.new()
	box.base = TOOLTIP_BG
	box.radius = RADIUS_KEY
	box.lip = 2
	box.lip_darken = 0.4
	box.shadow_alpha = 0.35
	box.shadow_size = 12
	box.hi = 0.09
	box.lo = 0.05
	box.rim = 0.3
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 14
	box.content_margin_bottom = 16
	return box

static func empty_box(margin: int = 0) -> StyleBoxEmpty:
	var box := StyleBoxEmpty.new()
	box.content_margin_left = margin
	box.content_margin_right = margin
	box.content_margin_top = margin
	box.content_margin_bottom = margin
	return box

# ---------------------------------------------------------------- helpers
## Applies the pixel-art rule to a texture rect: integer scale, no filtering.
static func make_pixel_crisp(node: CanvasItem) -> void:
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

## The icon saved at assets/ui/icons/<folder>/<icon_name>.png, or null when none
## has been made yet (the slot then shows its letter).
static func icon_art(folder: String, icon_name: String) -> Texture2D:
	var path := "res://assets/ui/icons/%s/%s.png" % [folder, icon_name]
	return load(path) if ResourceLoader.exists(path) else null
