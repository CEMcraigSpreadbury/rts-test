class_name UiGlyphs
## Flat single-colour icons from game-icons.net (CC BY 3.0, credited in the
## credits screen; sources in assets/ui/glyphs/SOURCES.txt) for everything that
## has no art of its own: commands, resources, settlement tiers. White on clear,
## tinted by whatever draws them.
##
## The SVGs are imported as "keep", so they ship as-is and are rasterised here at
## the exact pixel size asked for: a glyph stays crisp in a 50px command slot, a
## 40px tool button and a 15px tooltip line alike, where one imported bitmap
## scaled to each would go soft at most of them.

const DIR: String = "res://assets/ui/glyphs/"
## The viewBox every game-icons.net SVG is drawn in.
const SOURCE_SIZE: float = 512.0

## "name@px" -> ImageTexture.
static var _cache: Dictionary = {}
## Unit scene path -> its Unit.glyph.
static var _unit_glyphs: Dictionary = {}

static func texture(glyph: StringName, px: int) -> Texture2D:
	var key := "%s@%d" % [glyph, px]
	if _cache.has(key):
		return _cache[key]
	var svg := FileAccess.get_file_as_string(DIR + String(glyph) + ".svg")
	var image := Image.new()
	if svg.is_empty() or image.load_svg_from_string(svg, px / SOURCE_SIZE) != OK:
		push_warning("UiGlyphs: no glyph '%s'" % glyph)
		_cache[key] = null
		return null
	var glyph_texture := ImageTexture.create_from_image(image)
	_cache[key] = glyph_texture
	return glyph_texture

## The glyph of a unit scene nobody has spawned (a training button, a queue
## slot): read off one instance, once per scene.
static func unit_glyph(scene_path: String) -> StringName:
	if not _unit_glyphs.has(scene_path):
		var glyph: StringName = &""
		if ResourceLoader.exists(scene_path):
			var unit: Node = (load(scene_path) as PackedScene).instantiate()
			if unit is Unit:
				glyph = unit.glyph
			unit.free()
		_unit_glyphs[scene_path] = glyph
	return _unit_glyphs[scene_path]

## A glyph sized and tinted for a plain TextureRect (stockpile, tooltip, tool).
static func rect(glyph: StringName, px: int, tint: Color) -> TextureRect:
	var out := TextureRect.new()
	out.texture = texture(glyph, px)
	out.custom_minimum_size = Vector2(px, px)
	out.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	out.self_modulate = tint
	out.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return out
