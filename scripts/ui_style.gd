class_name UiStyle
extends RefCounted
## "Forged Brass" design tokens -- the single source of truth for every colour,
## size and face in the game's UI. Nothing else declares a UI colour.
##
## The theme resource is GENERATED from these values, it is not hand-authored:
##   godot --path . --headless --script res://scripts/tools/build_ui_theme.gd
## Run that after changing anything here, or the .tres and the components drift.
##
## Authored against a 1920x1080 base viewport, so every number below is a real
## screen pixel at 1080p and matches the mockup 1:1.

# ---------------------------------------------------------------- colour
## Panel bodies. Translucent so the battle stays readable underneath.
const SURFACE := Color(0.1176, 0.0902, 0.0667, 0.86)      # 1E1711
## Raised faces: buttons, the lighter half of a control.
const RAISED := Color(0.1725, 0.1333, 0.0980, 0.92)       # 2C2219
## Recessed wells: command slots, stat tiles, text inputs.
const SLOT := Color(0.0706, 0.0510, 0.0353, 0.78)         # 120D09
## The one border weight in the whole UI.
const LINE := Color(0.7294, 0.5608, 0.3098, 0.46)         # BA8F4F
## Rules, corner caps, portrait frames -- brass that reads as brass.
const LINE_STRONG := Color(0.8392, 0.6745, 0.4078, 0.85)  # D6AC68
## Primary text.
const INK := Color(0.9412, 0.8980, 0.8196)                # F0E5D1
## Labels, hotkey badges, timestamps.
const DIM := Color(0.7137, 0.6431, 0.5373)                # B6A489
## Spent only on selection, progress, the active tab and primary buttons.
const ACCENT := Color(0.8510, 0.6745, 0.3294)             # D9AC54
## Text that sits on top of ACCENT.
const ACCENT_INK := Color(0.1412, 0.1020, 0.0627)         # 241A10
const GOOD := Color(0.5608, 0.7490, 0.3843)               # 8FBF62
const BAD := Color(0.8118, 0.3804, 0.2667)                # CF6144
## Wavering morale (a routing one uses BAD).
const WAVER := Color(0.8902, 0.5255, 0.2275)              # E3863A
## Tooltips are the one OPAQUE surface: they must stay readable over whatever
## they cover, and a translucent one let the text behind bleed through.
const TOOLTIP_BG := Color(0.1725, 0.1333, 0.0980, 1.0)    # 2C2219
## Disabled controls keep their shape and lose their contrast.
const DISABLED_MODULATE := Color(1.0, 1.0, 1.0, 0.34)

# ---------------------------------------------------------------- metrics
const RADIUS: int = 2
const RADIUS_SLOT: int = 1
const BORDER: int = 1
## The one ornament in the system: a brass L in two opposite corners.
const CAP_LENGTH: int = 11
const CAP_WIDTH: int = 2

const SPACE_XS: int = 4
const SPACE_S: int = 8
const SPACE_M: int = 12
const SPACE_L: int = 14
const SPACE_XL: int = 22
## Distance from a screen edge to a docked module.
const SCREEN_MARGIN: int = 24

# ---------------------------------------------------------------- type
const FONT_DISPLAY_PATH: String = "res://assets/fonts/MarcellusSC-Regular.ttf"
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
const SIZE_NAME: int = 22
const SIZE_SLOT_LETTER: int = 25
const SIZE_CLOCK: int = 26
const SIZE_MODAL_TITLE: int = 34
const SIZE_GAME_TITLE: int = 62

# ---------------------------------------------------------------- control sizes
const SLOT_CMD: int = 50
const SLOT_QUEUE: int = 40
const SLOT_TOOL: int = 40
const SLOT_POINT: int = 30
const PORTRAIT: int = 104
const MINIMAP: int = 236
## Pixel art renders at 1x or 2x of its 32px source and never in between --
## anything else smears it however it is filtered.
const ICON_1X: int = 32
const ICON_2X: int = 64

## The selection panel never changes size: not on selection, not on race tab.
const SEL_PANEL_SIZE := Vector2(646, 214)
## Command grid is a fixed 9 x 2 in every race; sparse pacts pad with empties.
const CMD_COLUMNS: int = 9
const CMD_ROWS: int = 2

# ---------------------------------------------------------------- fonts, lazily
## Loaded on demand, never in a static initialiser -- those run before autoloads
## are ready and have broken this project's scripts at compile time before.
static var _display: FontFile
static var _data: FontFile
static var _data_bold: FontFile
static var _prose: FontFile

static func font_display() -> FontFile:
	if _display == null:
		_display = load(FONT_DISPLAY_PATH)
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

## A panel body. Content margins are the caller's business, because a docked
## module and a modal want different insets from the same material.
static func panel_box() -> StyleBoxFlat:
	return flat(SURFACE, LINE, RADIUS)

## A recessed well. Pass ACCENT for a selected slot, BAD for an unaffordable one.
static func slot_box(border: Color = LINE) -> StyleBoxFlat:
	return flat(SLOT, border, RADIUS_SLOT)

## An empty slot in a fixed grid: present, obviously not a control.
static func empty_slot_box() -> StyleBoxFlat:
	return flat(Color(0.0706, 0.0510, 0.0353, 0.42), Color(0.7294, 0.5608, 0.3098, 0.18), RADIUS_SLOT)

static func button_box(border: Color = LINE, bg: Color = RAISED) -> StyleBoxFlat:
	var box := flat(bg, border, RADIUS)
	box.content_margin_left = SPACE_XL
	box.content_margin_right = SPACE_XL
	box.content_margin_top = 11
	box.content_margin_bottom = 11
	return box

static func tooltip_box() -> StyleBoxFlat:
	var box := flat(TOOLTIP_BG, LINE_STRONG, RADIUS)
	box.content_margin_left = SPACE_L
	box.content_margin_right = SPACE_L
	box.content_margin_top = 11
	box.content_margin_bottom = 11
	return box

static func empty_box(margin: int = 0) -> StyleBoxEmpty:
	var box := StyleBoxEmpty.new()
	box.content_margin_left = margin
	box.content_margin_right = margin
	box.content_margin_top = margin
	box.content_margin_bottom = margin
	return box

# ---------------------------------------------------------------- helpers
## Draws the brass L caps on the top-left and bottom-right of a rect. Every
## panel in the game carries these; the user checks for them.
static func draw_corner_caps(canvas: CanvasItem, rect: Rect2, colour: Color = LINE_STRONG) -> void:
	var w := float(CAP_WIDTH)
	var l := float(CAP_LENGTH)
	var tl := rect.position
	canvas.draw_rect(Rect2(tl, Vector2(l, w)), colour)
	canvas.draw_rect(Rect2(tl, Vector2(w, l)), colour)
	var br := rect.position + rect.size
	canvas.draw_rect(Rect2(br - Vector2(l, w), Vector2(l, w)), colour)
	canvas.draw_rect(Rect2(br - Vector2(w, l), Vector2(w, l)), colour)

## Applies the pixel-art rule to a texture rect: integer scale, no filtering.
static func make_pixel_crisp(node: CanvasItem) -> void:
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
