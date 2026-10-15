class_name FigureMaterials
extends RefCounted
## The material FigureBatcher draws one figure type with: the figure itself
## (shaders/unit_figure.gdshader, its palette), then the same see-through-
## buildings pair the sprites wear (mask, then silhouette; see
## UnitBatchMaterials), as next passes. The night lift is in the figure shader
## itself, off the same global the sprites' lift reads.

const FIGURE_SHADER: Shader = preload("res://shaders/unit_figure.gdshader")
const MASK_SHADER: Shader = preload("res://shaders/unit_figure_mask.gdshader")
const SILHOUETTE_SHADER: Shader = preload("res://shaders/unit_figure_silhouette.gdshader")
const UnitSilhouetteMaterial = preload("res://scripts/unit_silhouette_material.gd")
## A figure with no palette of its own (Unit.figure_palette) is painted with this.
const DEFAULT_PALETTE: Texture2D = preload("res://assets/art/Models/Units/palettes/aldmere.png")

## For FigureBatcher.set_material_factory.
static func build(_mesh: Mesh, palette: Texture2D) -> Material:
	var figure := ShaderMaterial.new()
	figure.shader = FIGURE_SHADER
	figure.set_shader_parameter("palette", palette if palette != null else DEFAULT_PALETTE)
	var mask := ShaderMaterial.new()
	mask.shader = MASK_SHADER
	mask.render_priority = UnitSilhouetteMaterial.MASK_RENDER_PRIORITY
	var silhouette := ShaderMaterial.new()
	silhouette.shader = SILHOUETTE_SHADER
	silhouette.render_priority = UnitSilhouetteMaterial.SILHOUETTE_RENDER_PRIORITY
	silhouette.set_shader_parameter("silhouette_alpha", UnitSilhouetteMaterial.SILHOUETTE_ALPHA)
	figure.next_pass = mask
	mask.next_pass = silhouette
	return figure

## One figure drawn on its own, outside FigureBatcher (a carcass, a beast in
## its Bestiary cage, the menu backdrop's villagers): a one-instance MultiMesh
## carrying the same material and per-instance data the batcher gives a
## corpse, so it looks just as it does in the field. `pose` places the mesh
## within the returned node.
static func standalone(mesh: Mesh, palette: Texture2D, team_tint: Color, pose: Transform3D = Transform3D.IDENTITY) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = 1
	multimesh.set_instance_transform(0, pose)
	## Team colour, white status tint, no flash, fully shown (negative: no
	## see-through silhouette).
	multimesh.set_instance_custom_data(0, Color(pack_rgb(team_tint), pack_rgb(Color.WHITE), 0.0, -1.0))
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	instance.material_override = build(mesh, palette)
	return instance

## A colour as the figure shader unpacks it: 0xRRGGBB in a float.
static func pack_rgb(colour: Color) -> float:
	return float((colour.r8 << 16) | (colour.g8 << 8) | colour.b8)
