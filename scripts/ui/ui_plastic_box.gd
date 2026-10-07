@tool
class_name UiPlasticBox
extends StyleBox
## A moulded-plastic stylebox for the solid parts of the UI: keys, buttons,
## tooltips (RAISED) and the recessed sockets they sit in (WELL).
##
## Built from stacked StyleBoxFlats rather than a shader, so it works anywhere a
## stylebox does (theme, overrides, draw_style_box). The soft vertical shading
## is a few faint bands, each too small a step to read as an edge. Panels that
## frost the battlefield behind them use UiPlasticBody instead.
##
## RAISED mirrors the mockup's .key: a top highlight, a darker lip under the
## bottom edge and a soft drop shadow; `pressed` pushes the face down onto its
## lip. WELL mirrors .sock/.well: a dark translucent dip, shaded inside its top
## edge and catching light along its bottom one. `ring` outlines either: around
## a raised key (selection), inside a well (its state colour).

enum Kind { RAISED, WELL }

const BANDS: int = 4

@export var kind: Kind = Kind.RAISED:
	set(value):
		kind = value
		_changed()
@export var base: Color = Color(0.184, 0.204, 0.224):
	set(value):
		base = value
		_changed()
@export var radius: int = 12:
	set(value):
		radius = value
		_changed()
@export var lip: int = 3:
	set(value):
		lip = value
		_changed()
## The lip is the base colour darkened by this much.
@export var lip_darken: float = 0.45:
	set(value):
		lip_darken = value
		_changed()
@export var shadow_alpha: float = 0.4:
	set(value):
		shadow_alpha = value
		_changed()
@export var shadow_size: int = 8:
	set(value):
		shadow_size = value
		_changed()
@export var shadow_y: int = 6:
	set(value):
		shadow_y = value
		_changed()
## How much lighter the top of the face is, and how much darker the bottom.
@export var hi: float = 0.14:
	set(value):
		hi = value
		_changed()
@export var lo: float = 0.12:
	set(value):
		lo = value
		_changed()
## The highlight line along the top edge.
@export var rim: float = 0.35:
	set(value):
		rim = value
		_changed()
@export var pressed: bool = false:
	set(value):
		pressed = value
		_changed()
@export var ring: Color = Color(0, 0, 0, 0):
	set(value):
		ring = value
		_changed()
@export var ring_width: int = 2:
	set(value):
		ring_width = value
		_changed()
## Clear space between a raised key and its ring.
@export var ring_gap: int = 2:
	set(value):
		ring_gap = value
		_changed()

## Rounded height -> [[StyleBoxFlat, offset: Vector2, grow: float], ...]
var _layers: Dictionary = {}

func _changed() -> void:
	_layers.clear()
	emit_changed()

func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	var key := int(round(rect.size.y))
	if not _layers.has(key):
		_layers[key] = _build(rect.size.y)
	for layer: Array in _layers[key]:
		var box: StyleBoxFlat = layer[0]
		var at := Rect2(rect.position + (layer[1] as Vector2), rect.size).grow(layer[2])
		box.draw(to_canvas_item, at)

func _get_draw_rect(rect: Rect2) -> Rect2:
	var reach := float(shadow_size + ring_gap + ring_width + 2)
	return rect.grow_individual(reach, reach, reach, reach + shadow_y + lip)

func _build(height: float) -> Array:
	return _build_well(height) if kind == Kind.WELL else _build_raised(height)

func _box(fill: Color, r: int, draw_center: bool = true) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.draw_center = draw_center
	box.set_corner_radius_all(r)
	box.anti_aliasing_size = 0.8
	return box

## A border-only box: one edge band of `width` in `colour`.
func _edge(colour: Color, side: Side, width: int, r: int) -> StyleBoxFlat:
	var box := _box(Color(0, 0, 0, 0), r, false)
	box.border_color = colour
	box.set_border_width(side, width)
	return box

## The alpha that, stacked BANDS times, adds up to `total`.
static func _band_alpha(total: float) -> float:
	return 1.0 - pow(1.0 - clampf(total, 0.0, 0.99), 1.0 / BANDS)

func _build_raised(height: float) -> Array:
	var out: Array = []
	var sink := float(lip - 1) if pressed else 0.0
	var face := Vector2(0, sink)
	var lip_px := 1 if pressed else lip

	## Lip, with the drop shadow cast from it. The face covers all but its
	## bottom edge, and is opaque, so the shadow under the middle never shows.
	var under := _box(base.darkened(lip_darken), radius)
	under.shadow_color = Color(0.04, 0.06, 0.12, shadow_alpha * (0.5 if pressed else 1.0))
	under.shadow_size = (shadow_size >> 1) if pressed else shadow_size
	under.shadow_offset = Vector2(0, maxf(shadow_y - lip_px, 0.0) * (0.5 if pressed else 1.0))
	out.append([under, face + Vector2(0, lip_px), 0.0])

	out.append([_box(base, radius), face, 0.0])
	var hi_a := _band_alpha(hi)
	var lo_a := _band_alpha(lo)
	for i in BANDS:
		var top_w := int(ceil(height * 0.3 * float(i + 1) / BANDS))
		out.append([_edge(Color(1, 1, 1, hi_a), SIDE_TOP, top_w, radius), face, 0.0])
		var bottom_w := int(ceil(height * 0.7 * float(i + 1) / BANDS))
		out.append([_edge(Color(0, 0, 0, lo_a), SIDE_BOTTOM, bottom_w, radius), face, 0.0])
	if pressed:
		## Pushed in: the top edge falls into shade instead of catching light.
		out.append([_edge(Color(0, 0, 0, 0.14), SIDE_TOP, 3, radius), face, 0.0])
		out.append([_edge(Color(0, 0, 0, 0.1), SIDE_TOP, 1, radius), face, 0.0])
	else:
		out.append([_edge(Color(1, 1, 1, rim), SIDE_TOP, 1, radius), face, 0.0])
	out.append([_edge(Color(0, 0, 0, 0.12), SIDE_BOTTOM, 2, radius), face, 0.0])

	if ring.a > 0.0:
		var reach := ring_gap + ring_width
		var outline := _box(Color(0, 0, 0, 0), radius + reach, false)
		outline.border_color = ring
		outline.set_border_width_all(ring_width)
		out.append([outline, face, float(reach)])
	return out

func _build_well(_height: float) -> Array:
	var out: Array = []
	out.append([_box(base, radius), Vector2.ZERO, 0.0])
	## The inner shadow under the top edge (inset 0 2px 4px).
	out.append([_edge(Color(0, 0, 0, 0.1), SIDE_TOP, 4, radius), Vector2.ZERO, 0.0])
	out.append([_edge(Color(0, 0, 0, 0.1), SIDE_TOP, 2, radius), Vector2.ZERO, 0.0])
	out.append([_edge(Color(0, 0, 0, 0.08), SIDE_TOP, 1, radius), Vector2.ZERO, 0.0])
	## The far lip of the dip catching light.
	out.append([_edge(Color(1, 1, 1, 0.2), SIDE_BOTTOM, 1, radius), Vector2.ZERO, 0.0])
	if ring.a > 0.0:
		var outline := _box(Color(0, 0, 0, 0), radius, false)
		outline.border_color = ring
		outline.set_border_width_all(ring_width)
		out.append([outline, Vector2.ZERO, 0.0])
	return out
