class_name TreeWind
extends RefCounted
## Ambient wind sway for trees (shaders/util/tree_wind.gdshaderinc). Only
## models instanced from a tree*.glb get it — the pine atlas material is shared
## with bushes/logs/sticks, so trees are picked by scene file, not material.
## Run after BakedLightingMaterial.apply_to, so baked tree surfaces are already
## on baked_emission.gdshader and just need the wind uniforms switched on.

const LIT_SHADER: Shader = preload("res://shaders/tree_wind_lit.gdshader")
## Fraction of the tree's height its top sways by at peak.
const STRENGTH: float = 0.03

## One material per (source material, mesh height), shared across instances
## so a forest of the same tree still batches.
static var _cache: Dictionary = {}

## Walks `node`, applying wind to every tree model found (not descending into
## them past the model root). Safe to call twice on the same nodes.
static func apply_to_trees_in(node: Node) -> void:
	if node is Node3D and node.scene_file_path.get_file().to_lower().begins_with("tree"):
		_apply(node)
		return
	for child in node.get_children():
		apply_to_trees_in(child)

## Re-applies the Wind setting to every tree material already built.
static func refresh() -> void:
	for material: ShaderMaterial in _cache.values():
		material.set_shader_parameter("wind_strength", _strength())

static func _strength() -> float:
	return STRENGTH if Settings.get_value(&"wind") else 0.0

static func _apply(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance: MeshInstance3D = node
		if mesh_instance.mesh:
			var height: float = maxf(mesh_instance.mesh.get_aabb().end.y, 0.01)
			for i in mesh_instance.mesh.get_surface_count():
				var windy: Material = _windy_for(mesh_instance.get_active_material(i), height)
				if windy:
					mesh_instance.set_surface_override_material(i, windy)
	for child in node.get_children():
		_apply(child)

static func _windy_for(source: Material, height: float) -> Material:
	if source == null or source.has_meta(&"tree_wind"):
		return null
	var key: Array = [source, snappedf(height, 0.01)]
	if _cache.has(key):
		return _cache[key]
	var material: ShaderMaterial
	var shader_source := source as ShaderMaterial
	var standard := source as StandardMaterial3D
	if shader_source and shader_source.shader == BakedLightingMaterial.SHADER:
		material = shader_source.duplicate()
	elif standard:
		material = ShaderMaterial.new()
		material.shader = LIT_SHADER
		material.set_shader_parameter("albedo_texture", standard.albedo_texture)
		material.set_shader_parameter("albedo_color", standard.albedo_color)
		material.set_shader_parameter("use_vertex_color", standard.vertex_color_use_as_albedo)
		material.set_shader_parameter("roughness", standard.roughness)
		material.set_shader_parameter("metallic", standard.metallic)
	else:
		return null
	material.set_shader_parameter("wind_strength", _strength())
	material.set_shader_parameter("wind_height", height)
	material.set_meta(&"tree_wind", true)
	_cache[key] = material
	return material
