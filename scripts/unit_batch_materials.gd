class_name UnitBatchMaterials
extends RefCounted
## The material SpriteBatcher draws one sprite sheet's units with: the sprite
## itself, then the same three overlay passes each unit sprite used to wear
## one by one (see UnitSilhouetteMaterial) — night lift, silhouette mask,
## silhouette — each now drawn once for the whole sheet.

const SPRITE_SHADER: Shader = preload("res://shaders/unit_batch_sprite.gdshader")
const LIFT_SHADER: Shader = preload("res://shaders/unit_batch_lift.gdshader")
const MASK_SHADER: Shader = preload("res://shaders/unit_batch_mask.gdshader")
const SILHOUETTE_SHADER: Shader = preload("res://shaders/unit_batch_silhouette.gdshader")
const UnitSilhouetteMaterial = preload("res://scripts/unit_silhouette_material.gd")

## For SpriteBatcher.set_material_factory: `cell_uv` is one cell of `sheet`
## as a fraction of the whole.
static func build(sheet: Texture2D, cell_uv: Vector2) -> Material:
	var sprite := _pass(SPRITE_SHADER, sheet, cell_uv, 0)
	var lift := _pass(LIFT_SHADER, sheet, cell_uv, UnitSilhouetteMaterial.LIFT_RENDER_PRIORITY)
	## The unit's own pixels, so exactly where the sprite is (as the unbatched
	## overlay sets it).
	lift.set_shader_parameter("occlusion_bias", 0.0)
	var mask := _pass(MASK_SHADER, sheet, cell_uv, UnitSilhouetteMaterial.MASK_RENDER_PRIORITY)
	var silhouette := _pass(SILHOUETTE_SHADER, sheet, cell_uv, UnitSilhouetteMaterial.SILHOUETTE_RENDER_PRIORITY)
	silhouette.set_shader_parameter("silhouette_alpha", UnitSilhouetteMaterial.SILHOUETTE_ALPHA)
	sprite.next_pass = lift
	lift.next_pass = mask
	mask.next_pass = silhouette
	return sprite

static func _pass(shader: Shader, sheet: Texture2D, cell_uv: Vector2, priority: int) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.render_priority = priority
	material.set_shader_parameter("sprite_sheet", sheet)
	material.set_shader_parameter("cell_uv", cell_uv)
	return material
