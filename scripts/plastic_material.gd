class_name PlasticMaterial
extends RefCounted
## Gives a model's plain imported materials (rocks, gold deposits, scenery
## props) the moulded-plastic finish every model shares: a satin roughness and
## a thin clear coat, as tree_wind_lit.gdshader gives the trees and
## shaders/util/plastic_light.gdshaderinc gives the buildings. Kept in step
## with the constants there.
##
## Run after BakedLightingMaterial.apply_to, so baked surfaces are already on
## their own shader (which carries the finish itself) and are left alone.
## Tree models are skipped: TreeWind builds theirs from the source materials.

const ROUGHNESS: float = 0.5
const SPECULAR: float = 0.5
const CLEARCOAT: float = 0.25
const CLEARCOAT_ROUGHNESS: float = 0.35

## One material per source material, shared by every instance so repeated
## props still batch.
static var _cache: Dictionary = {}

static func apply_to(node: Node) -> void:
	if node is Node3D and node.scene_file_path.get_file().to_lower().begins_with("tree"):
		return
	if node is MeshInstance3D:
		var mesh_instance: MeshInstance3D = node
		var surface_count: int = mesh_instance.mesh.get_surface_count() if mesh_instance.mesh else 0
		for i in surface_count:
			var plastic: Material = _plastic_for(mesh_instance.get_active_material(i))
			if plastic:
				mesh_instance.set_surface_override_material(i, plastic)
	for child in node.get_children():
		apply_to(child)

static func _plastic_for(source: Material) -> Material:
	var standard := source as StandardMaterial3D
	if standard == null or standard.has_meta(&"plastic"):
		return null
	if _cache.has(standard):
		return _cache[standard]
	var plastic: StandardMaterial3D = standard.duplicate()
	plastic.metallic = 0.0
	plastic.roughness = ROUGHNESS
	plastic.metallic_specular = SPECULAR
	plastic.clearcoat_enabled = true
	plastic.clearcoat = CLEARCOAT
	plastic.clearcoat_roughness = CLEARCOAT_ROUGHNESS
	plastic.set_meta(&"plastic", true)
	_cache[standard] = plastic
	return plastic
