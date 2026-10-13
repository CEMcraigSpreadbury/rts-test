class_name RoundParticle
extends RefCounted
## The one particle shape: a soft round puff that fades at its edge, rather
## than a flat square quad. Every dust, spark and status particle wears it.

static var _texture: GradientTexture2D = null

static func texture() -> GradientTexture2D:
	if _texture == null:
		var fade := Gradient.new()
		fade.set_color(0, Color(1, 1, 1, 1))
		fade.set_color(1, Color(1, 1, 1, 0))
		fade.add_point(0.55, Color(1, 1, 1, 0.8))
		_texture = GradientTexture2D.new()
		_texture.fill = GradientTexture2D.FILL_RADIAL
		_texture.fill_from = Vector2(0.5, 0.5)
		_texture.fill_to = Vector2(1.0, 0.5)
		_texture.width = 64
		_texture.height = 64
		_texture.gradient = fade
	return _texture

## Rounds a particle mesh's own material in place (a scene's shared quad, so
## every instance of that scene is done at once).
static func apply(mesh: Mesh) -> void:
	if mesh == null:
		return
	var material := mesh.surface_get_material(0) as BaseMaterial3D if mesh.get_surface_count() > 0 else null
	if material == null and mesh is PrimitiveMesh:
		material = (mesh as PrimitiveMesh).material as BaseMaterial3D
	if material == null or material.albedo_texture == texture():
		return
	material.albedo_texture = texture()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
