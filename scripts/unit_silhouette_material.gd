extends RefCounted
## Builds the material_overlay every unit sprite wears. Three chained passes:
## the night lift adds moonlight back onto the unit itself (see
## shaders/unit_night_lift.gdshader), then the silhouette pair shows it as a
## team-colored outline wherever a building, tree or hill is hiding it — the
## mask marks every pixel where some unit is visible, then the silhouette
## draws only where this one is occluded and no other unit is showing.

const LIFT_SHADER: Shader = preload("res://shaders/unit_night_lift.gdshader")
const MASK_SHADER: Shader = preload("res://shaders/unit_silhouette_mask.gdshader")
const SILHOUETTE_SHADER: Shader = preload("res://shaders/unit_silhouette.gdshader")

const SILHOUETTE_ALPHA: float = 0.55

## Every mask must land before any silhouette reads the stencil, and both
## after grass (alpha-blended at 0), but under selection rings (10) and health
## bars (20). The lift goes first of all, so the silhouette of an occluded
## unit draws over it rather than under.
const LIFT_RENDER_PRIORITY: int = 7
const MASK_RENDER_PRIORITY: int = 8
const SILHOUETTE_RENDER_PRIORITY: int = 9

## One material per (sheet, color) rather than per unit, same reasoning as
## TeamColorMaterial's cache. The sheet itself is held in the entry so a freed
## texture's recycled instance id can't alias onto a stale material.
static var _cache: Dictionary = {}

static func build(sheet: Texture2D, color: Color) -> ShaderMaterial:
	var key: String = "%d:%s" % [sheet.get_instance_id(), color]
	if _cache.has(key):
		return _cache[key]["material"]

	var silhouette := ShaderMaterial.new()
	silhouette.shader = SILHOUETTE_SHADER
	silhouette.render_priority = SILHOUETTE_RENDER_PRIORITY
	silhouette.set_shader_parameter("sprite_sheet", sheet)
	silhouette.set_shader_parameter("silhouette_color", Color(color, SILHOUETTE_ALPHA))

	var mask := ShaderMaterial.new()
	mask.shader = MASK_SHADER
	mask.render_priority = MASK_RENDER_PRIORITY
	mask.set_shader_parameter("sprite_sheet", sheet)
	mask.next_pass = silhouette

	var lift := ShaderMaterial.new()
	lift.shader = LIFT_SHADER
	lift.render_priority = LIFT_RENDER_PRIORITY
	lift.set_shader_parameter("sprite_sheet", sheet)
	## The other two passes deliberately test depth as if they stood closer
	## (see the .gdshaderinc); this one is the unit's own pixels, so it sits
	## exactly where the sprite does.
	lift.set_shader_parameter("occlusion_bias", 0.0)
	lift.next_pass = mask

	_cache[key] = {"sheet": sheet, "material": lift}
	return lift
