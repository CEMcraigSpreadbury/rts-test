class_name BakedLightingMaterial
extends RefCounted
## The "shaded" GLB exports (tree, gold deposit, bush, field, ...) carry their
## lighting baked into an emission texture with albedo left black, and
## emission ignores lights entirely — so cloud shadows passed straight over
## them. This swaps those surfaces onto shaders/baked_emission.gdshader, which
## draws the same baked texture but darkens it under directional shadows.
## Buildings don't go through here: TeamColorMaterial already does the same
## thing for them, plus the team recolor.

const SHADER: Shader = preload("res://shaders/baked_emission.gdshader")

## One material per source material, shared by every instance so a forest of
## the same tree still batches the way the imported material did. Keyed by
## the material itself (not its id) so the key keeps it alive.
static var _cache: Dictionary = {}

## Walks `node` and its descendants. Anything that isn't a baked-emission
## StandardMaterial3D (lit models, already-swapped or overridden surfaces) is
## left as it is, so calling this twice on the same tree is harmless.
static func apply_to(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance: MeshInstance3D = node
		var surface_count: int = mesh_instance.mesh.get_surface_count() if mesh_instance.mesh else 0
		for i in surface_count:
			var baked: ShaderMaterial = _baked_for(mesh_instance.get_active_material(i))
			if baked:
				mesh_instance.set_surface_override_material(i, baked)
	for child in node.get_children():
		apply_to(child)

static func _baked_for(source: Material) -> ShaderMaterial:
	var standard: StandardMaterial3D = source as StandardMaterial3D
	if standard == null or not standard.emission_enabled or standard.emission_texture == null:
		return null
	if _cache.has(standard):
		return _cache[standard]
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("source_texture", standard.emission_texture)
	material.set_shader_parameter("emission_color", standard.emission)
	material.set_shader_parameter("emission_energy", standard.emission_energy_multiplier)
	_cache[standard] = material
	return material
