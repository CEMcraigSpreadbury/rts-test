class_name PlasticMaterial
extends RefCounted
## Puts a model's plain imported materials (rocks, gold deposits, the farm
## field, scenery props) on shaders/plastic_prop.gdshader: the moulded-plastic
## finish every model shares, at the buildings' gloss
## (shaders/util/plastic_light.gdshaderinc), plus the per-instance `tint` the
## farm field grows its crop with.
##
## Run after BakedLightingMaterial.apply_to, so baked surfaces are already on
## their own shader (which carries the finish itself) and are left alone.
## Tree models are skipped: TreeWind builds theirs from the source materials.

const SHADER: Shader = preload("res://shaders/plastic_prop.gdshader")

## One material per source material, shared by every instance so repeated
## props still batch; the tint is per instance, so sharing doesn't stop it.
static var _cache: Dictionary = {}

static func apply_to(node: Node) -> void:
	if node is Node3D and node.scene_file_path.get_file().to_lower().begins_with("tree"):
		return
	if node is MeshInstance3D:
		var mesh_instance: MeshInstance3D = node
		var surface_count: int = mesh_instance.mesh.get_surface_count() if mesh_instance.mesh else 0
		for i in surface_count:
			var coloured: bool = (mesh_instance.mesh.surface_get_format(i) & Mesh.ARRAY_FORMAT_COLOR) != 0
			var plastic: Material = _plastic_for(mesh_instance.get_active_material(i), coloured)
			if plastic:
				mesh_instance.set_surface_override_material(i, plastic)
	for child in node.get_children():
		apply_to(child)

static func _plastic_for(source: Material, coloured: bool) -> Material:
	var standard := source as StandardMaterial3D
	if standard == null:
		return null
	var key: Array = [standard, coloured]
	if _cache.has(key):
		return _cache[key]
	var plastic := ShaderMaterial.new()
	plastic.shader = SHADER
	plastic.set_shader_parameter(&"albedo_texture", standard.albedo_texture)
	plastic.set_shader_parameter(&"albedo_color", standard.albedo_color)
	plastic.set_shader_parameter(&"use_vertex_color", standard.vertex_color_use_as_albedo or coloured)
	## Leaf materials (the toy bushes') take the pines' softer finish.
	plastic.set_shader_parameter(&"foliage", standard.resource_name.begins_with("Leaf"))
	_cache[key] = plastic
	return plastic
