class_name UnitPortrait
extends RefCounted
## A unit's portrait: the dialogue box's speaker, the HUD's selection
## portrait, the selection tray, the regiment cards and standards.
##
## A unit drawn as a 3D figure shows its rendered portrait when there is one:
## PORTRAIT_DIR/<figure model name>.png, made by the Blender kit
## (build.py --portraits). That image is the head-and-shoulders render, its
## team rows left grey, on the left half and a mask of those rows on the
## right; here the grey under the mask is multiplied by the team colour the
## way shaders/unit_figure.gdshader does it, once per type and colour.
## Anything else is cut out of its sprite sheet (below). Cached, because
## neither ever changes.
##
## A unit can set its own sprite crop instead (Unit.portrait_region).

const PORTRAIT_DIR: String = "res://assets/art/Models/Units/portraits/"
## shaders/unit_figure.gdshader's team_grey_ref and team_saturation.
const TEAM_GREY_REF: float = 0.42
const TEAM_SATURATION: float = 0.88
## The colour a portrait takes where nobody owns the unit (a dialogue speaker).
const DEFAULT_TINT := Color(0.25, 0.55, 1.0)
## Marks a rendered portrait's texture (see filter_for).
const RENDERED_META: StringName = &"figure_portrait"

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
## Figure name -> the portrait-plus-mask Image, or null when there is none.
static var _sources: Dictionary = {}

## For a unit that exists: its rendered figure portrait in `tint` (its own
## team's colour by default), else its own sheet, cell size, idle row and any
## crop it sets for itself.
static func of_unit(unit: Unit, tint: Color = Color(0, 0, 0, 0)) -> Texture2D:
	if unit == null:
		return null
	var rendered: Texture2D = rendered_of(unit, owner_tint(unit) if tint.a == 0.0 else tint)
	if rendered != null:
		return rendered
	if unit.sprite_sheet == null:
		return null
	return of_sheet(unit.sprite_sheet, unit.sprite_cell_size, unit.idle_row, unit.portrait_region)

## The colour of the player who owns `unit`: its team tint, or (before that
## is set) its owner's colour from the match.
static func owner_tint(unit: Unit) -> Color:
	if unit.team_tint != Color.WHITE:
		return unit.team_tint
	var main := _main()
	return main.get_team_tint(unit.owner_peer_id) if main != null else DEFAULT_TINT

## The local player's colour, for a portrait nobody owns yet (a dialogue
## speaker, a unit offered for training).
static func local_tint() -> Color:
	var main := _main()
	return main.get_team_tint(main.my_peer_id()) if main != null else DEFAULT_TINT

static func _main() -> Main:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.current_scene as Main if tree != null else null

## For a unit scene nobody has spawned — a dialogue line's speaker, a roster
## entry — in `tint` (the local player's colour when not given).
static func of_scene(scene_path: String, tint: Color = Color(0, 0, 0, 0)) -> Texture2D:
	if tint.a == 0.0:
		tint = local_tint()
	var key := "%s|%s" % [scene_path, tint.to_html()]
	if _cache.has(key):
		return _cache[key]
	var texture: Texture2D = null
	if ResourceLoader.exists(scene_path):
		var scene: PackedScene = load(scene_path)
		var unit: Node = scene.instantiate()
		if unit is Unit:
			texture = of_unit(unit, tint)
		unit.free()
	_cache[key] = texture
	return texture

## The filter a portrait wants: smooth for a render, crisp for pixel art.
static func filter_for(texture: Texture2D) -> CanvasItem.TextureFilter:
	if texture != null and texture.has_meta(RENDERED_META):
		return CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return CanvasItem.TEXTURE_FILTER_NEAREST

## The name its rendered portrait is filed under: its figure model's file
## name. Empty for a sprite-only unit.
static func figure_name(unit: Unit) -> String:
	if unit == null or unit.figure_model == null:
		return ""
	return unit.figure_model.resource_path.get_file().get_basename()

## The rendered portrait as an Image in `tint` (null with none): for the
## regiment standards, which paint it onto their token.
static func rendered_image(unit: Unit, tint: Color) -> Image:
	var source: Image = _source(figure_name(unit))
	if source == null:
		return null
	var key := "img|%s|%s" % [figure_name(unit), tint.to_html()]
	if not _cache.has(key):
		_cache[key] = _tinted(source, tint)
	return _cache[key]

static func rendered_of(unit: Unit, tint: Color) -> Texture2D:
	var name: String = figure_name(unit)
	if name == "":
		return null
	var key := "tex|%s|%s" % [name, tint.to_html()]
	if not _cache.has(key):
		var image: Image = rendered_image(unit, tint)
		var texture: ImageTexture = null
		if image != null:
			var mipped: Image = image.duplicate()
			mipped.generate_mipmaps()
			texture = ImageTexture.create_from_image(mipped)
			texture.set_meta(RENDERED_META, true)
		_cache[key] = texture
	return _cache[key]

static func _source(name: String) -> Image:
	if name == "":
		return null
	if not _sources.has(name):
		var path := PORTRAIT_DIR + name + ".png"
		var image: Image = null
		if ResourceLoader.exists(path):
			var texture := load(path) as Texture2D
			image = texture.get_image() if texture != null else null
			if image != null:
				if image.is_compressed():
					image.decompress()
				image.convert(Image.FORMAT_RGBA8)
		_sources[name] = image
	return _sources[name]

## The portrait half with the mask half's team rows multiplied by `tint`, as
## the figure shader does: in linear light, the colour a little desaturated,
## a swatch of TEAM_GREY_REF showing it as it is.
static func _tinted(source: Image, tint: Color) -> Image:
	var side: int = source.get_height()
	var team: Color = tint.srgb_to_linear()
	var grey: float = team.get_luminance()
	team = Color(grey, grey, grey).lerp(team, TEAM_SATURATION)
	var out := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
	for y in side:
		for x in side:
			var c: Color = source.get_pixel(x, y)
			var m: float = source.get_pixel(x + side, y).r
			if m > 0.0 and c.a > 0.0:
				var lin: Color = c.srgb_to_linear()
				## Per channel, so the warm light on the grey carries over.
				var dyed := Color(minf(team.r * lin.r / TEAM_GREY_REF, 1.0),
						minf(team.g * lin.g / TEAM_GREY_REF, 1.0),
						minf(team.b * lin.b / TEAM_GREY_REF, 1.0))
				var mixed: Color = Color(lin.r, lin.g, lin.b).lerp(dyed, m).linear_to_srgb()
				c = Color(mixed.r, mixed.g, mixed.b, c.a)
			out.set_pixel(x, y, c)
	return out

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
