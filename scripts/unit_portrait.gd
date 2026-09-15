class_name UnitPortrait
extends RefCounted
## A unit's head, cut out of its sprite sheet — the dialogue box's speaker
## portrait and the HUD's selection portrait. Stands in until there is real
## portrait art. Cached per sheet, because it never changes.
##
## A unit can set its own crop instead (Unit.portrait_region).

## Every portrait is the whole figure. Off, units get a head-and-shoulders
## crop found from the art (below), and only side-on creatures (see
## WIDE_CELL_RATIO) show their whole figure.
const WHOLE_BODY: bool = true
## Head crops: a portrait is a square around the figure's head, this fraction of the
## figure's height on a side: 0.8 is head and shoulders. Lower it for a
## tighter face.
const HEAD_FRACTION: float = 0.8
## A pixel counts as part of the figure above this alpha.
const ALPHA_THRESHOLD: float = 0.15
## Narrower than this, a run of pixels is a weapon or a crest, not a head.
const MIN_HEAD_WIDTH: int = 3
## Fewer skin-coloured pixels than this near the top isn't a face.
const MIN_FACE_PIXELS: int = 4
## A cell at least this many times wider than it is tall holds a creature
## drawn side-on — the dragons, the Hydra — whose head is not on top of
## anything and cannot be found this way. Those show the whole figure.
const WIDE_CELL_RATIO: float = 2.0

static var _cache: Dictionary = {}

## For a unit that exists: its own sheet, cell size, idle row and any crop it
## sets for itself.
static func of_unit(unit: Unit) -> Texture2D:
	if unit == null or unit.sprite_sheet == null:
		return null
	return of_sheet(unit.sprite_sheet, unit.sprite_cell_size, unit.idle_row, unit.portrait_region)

## For a unit scene nobody has spawned — a dialogue line's speaker.
static func of_scene(scene_path: String) -> Texture2D:
	if _cache.has(scene_path):
		return _cache[scene_path]
	var texture: Texture2D = null
	if ResourceLoader.exists(scene_path):
		var scene: PackedScene = load(scene_path)
		var unit: Node = scene.instantiate()
		if unit is Unit:
			texture = of_unit(unit)
		unit.free()
	_cache[scene_path] = texture
	return texture

## `region`: a crop within the cell chosen by hand; empty works one out.
static func of_sheet(sheet: Texture2D, cell: Vector2i, row: int = 0, region: Rect2i = Rect2i()) -> Texture2D:
	var sheet_id: String = sheet.resource_path if sheet.resource_path != "" else str(sheet.get_instance_id())
	var key := "%s|%s|%d|%s" % [sheet_id, cell, row, region]
	if not _cache.has(key):
		_cache[key] = _crop(sheet, cell, row, region) if region.has_area() else _head_of(sheet, cell, row)
	return _cache[key]

static func _crop(sheet: Texture2D, cell: Vector2i, row: int, region: Rect2i) -> Texture2D:
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(region.position + Vector2i(0, row * cell.y), region.size)
	return atlas

## (start column, length) of the longest unbroken run of opaque pixels in one
## row of the cell.
static func _widest_run(image: Image, origin: Vector2i, y: int, width: int) -> Vector2i:
	var best := Vector2i(0, 0)
	var start := -1
	for x in width + 1:
		var solid: bool = x < width and image.get_pixel(origin.x + x, origin.y + y).a > ALPHA_THRESHOLD
		if solid and start < 0:
			start = x
		elif not solid and start >= 0:
			if x - start > best.y:
				best = Vector2i(start, x - start)
			start = -1
	return best

## Warm, light and ordered red > green > blue: the Minifolks skin tones.
static func _is_skin(c: Color) -> bool:
	return c.a > ALPHA_THRESHOLD and c.r > 0.75 and c.g > 0.5 and c.b > 0.35 and c.r > c.g and c.g > c.b

## Works out where the character actually sits inside its first idle frame —
## the art rarely fills the cell, and cutting a fixed slice off the top of the
## cell gets you the empty space above their head — then cuts a square around
## the head. Square and centred on the head rather than on the whole figure:
## a sword held out level widens the figure's outline, and a crop of its top
## half came out as a thin strip of helmet and blade with the face cut off.
static func _head_of(sheet: Texture2D, cell: Vector2i, row: int) -> Texture2D:
	var image: Image = sheet.get_image()
	if image == null:
		return null
	if image.is_compressed():
		image.decompress()
	var origin := Vector2i(0, row * cell.y)
	if origin.y + cell.y > image.get_height():
		origin.y = 0
	var width: int = mini(cell.x, image.get_width())
	var height: int = mini(cell.y, image.get_height() - origin.y)
	var min_x: int = width
	var max_x: int = -1
	var min_y: int = height
	var max_y: int = -1
	for y in height:
		for x in width:
			if image.get_pixel(origin.x + x, origin.y + y).a > ALPHA_THRESHOLD:
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
				min_y = mini(min_y, y)
				max_y = maxi(max_y, y)
	if max_x < min_x or max_y < min_y:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	## The whole figure, a pixel of margin round it — always, or for side-on
	## creatures only. Rarely square, which the portrait's keep-aspect stretch
	## letterboxes.
	if WHOLE_BODY or float(cell.x) >= float(cell.y) * WIDE_CELL_RATIO:
		var left_edge: int = maxi(min_x - 1, 0)
		var top_edge: int = maxi(min_y - 1, 0)
		atlas.region = Rect2(origin.x + left_edge, origin.y + top_edge,
				mini(max_x + 2, width) - left_edge, mini(max_y + 2, height) - top_edge)
		return atlas
	## The head is the widest solid run of pixels in each row near the top. A
	## raised sword or spear beside it is a line a pixel or two wide, so it
	## neither sets where the head starts nor drags its middle off the face.
	var head_top: int = min_y
	for y in range(min_y, max_y + 1):
		if _widest_run(image, origin, y, width).y >= MIN_HEAD_WIDTH:
			head_top = y
			break
	var head_depth: int = maxi(3, int((max_y - head_top + 1) * 0.35))
	var sum_x := 0.0
	var weight := 0.0
	for y in range(head_top, mini(head_top + head_depth, max_y + 1)):
		var run: Vector2i = _widest_run(image, origin, y, width)
		if run.y >= MIN_HEAD_WIDTH:
			sum_x += (run.x + (run.y - 1) * 0.5) * run.y
			weight += run.y
	var head_x: float = sum_x / weight if weight > 0.0 else (min_x + max_x) * 0.5
	## A face, when there is one, is what the portrait is of. The humans all
	## face right with the back of a helmet and a raised sword behind them, so
	## the middle of the head's outline sits a couple of pixels behind the face
	## and the crop came out with the face pushed against the right edge.
	## Monsters' faces are rarely skin-coloured, and they keep the outline.
	var face_sum := 0
	var face_count := 0
	for y in range(head_top, mini(head_top + int((max_y - head_top + 1) * 0.5), max_y + 1)):
		for x in width:
			if _is_skin(image.get_pixel(origin.x + x, origin.y + y)):
				face_sum += x
				face_count += 1
	if face_count >= MIN_FACE_PIXELS:
		head_x = float(face_sum) / face_count
	var side: int = clampi(roundi((max_y - head_top + 1) * HEAD_FRACTION), 6, mini(width, height))
	var left: int = clampi(roundi(head_x - (side - 1) * 0.5), 0, width - side)
	var top: int = clampi(head_top - 1, 0, height - side)
	atlas.region = Rect2(origin.x + left, origin.y + top, side, side)
	return atlas
