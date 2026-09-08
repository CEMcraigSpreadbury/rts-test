class_name TeamColorMaterial
extends RefCounted
## Builds the materials that put a building on shaders/team_color.gdshader,
## which recolors only the blue, team-colored parts of its texture and leaves
## the wood, thatch and stone alone. A static helper for the same reason
## CombatUtils is one: ProductionBuilding drives the actual swap (it already
## walks its own meshes for the construction and damage-flash effects), and
## this owns the part worth keeping in one place — reading whatever material a
## model shipped with and translating it into the shader's uniforms.

const TEAM_SHADER: Shader = preload("res://shaders/team_color.gdshader")
const CONSTRUCTION_SHADER: Shader = preload("res://shaders/team_color_construction.gdshader")

## Every (source material, team color) pair resolves to one shared material
## rather than one per building. A long wall is hundreds of ProductionBuildings
## and handing each its own ShaderMaterial would give them each their own draw
## call; sharing keeps them batching as they did before any of this. Safe to
## share because nothing mutates these in place — the under-construction
## variant duplicates first (see to_construction_variant) — and it stays small
## on its own, since the inputs are the handful of materials the building
## models ship with times at most Network.TEAM_COLORS.size() colors.
static var _cache: Dictionary = {}

## Builds one surface's team-colored material from whatever the model shipped
## with. `shader` picks the finished-building or under-construction variant —
## both read the same uniforms, so they're filled in identically here.
static func build(source: Material, team_color: Color, shader: Shader) -> ShaderMaterial:
	var key: String = "%d:%d:%s" % [
		source.get_instance_id() if source != null else 0, shader.get_instance_id(), team_color
	]
	if _cache.has(key):
		return _cache[key]["material"]
	var material: ShaderMaterial = _build(source, team_color, shader)
	## Keeping the source material referenced here is what makes the key
	## trustworthy: Godot recycles instance ids once a resource is freed, so a
	## cache holding ids alone could hand back a material built from some
	## unrelated texture that happened to land on the same id later.
	_cache[key] = {"source": source, "material": material}
	return material

static func _build(source: Material, team_color: Color, shader: Shader) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("team_color", team_color)

	var standard: StandardMaterial3D = source as StandardMaterial3D
	if standard == null:
		return material

	## The building GLBs are "shaded" exports — baked lighting in an emission
	## texture with albedo left black — so for those the map carrying the art
	## is the emission one and reading albedo_texture would find nothing at
	## all. Nothing guarantees that for a model added later though, so take
	## whichever map is actually populated and tell the shader which it was,
	## rather than hard-coding the assumption in the shader itself.
	var emission_texture: Texture2D = standard.emission_texture if standard.emission_enabled else null
	if emission_texture != null:
		material.set_shader_parameter("source_texture", emission_texture)
		material.set_shader_parameter("texture_drives_emission", true)
		material.set_shader_parameter("emission_color", standard.emission)
		material.set_shader_parameter("emission_energy", standard.emission_energy_multiplier)
	else:
		material.set_shader_parameter("source_texture", standard.albedo_texture)
		material.set_shader_parameter("texture_drives_emission", false)

	material.set_shader_parameter("base_albedo", standard.albedo_color)
	material.set_shader_parameter("metallic_value", standard.metallic)
	material.set_shader_parameter("roughness_value", standard.roughness)
	return material

## Rebuilds an already-applied surface for the under-construction look, keeping
## every uniform the finished version resolved (which texture drives it, the
## model's own albedo/emission/roughness) instead of working them out twice.
static func to_construction_variant(source: ShaderMaterial, alpha: float) -> ShaderMaterial:
	var material: ShaderMaterial = source.duplicate()
	material.shader = CONSTRUCTION_SHADER
	material.set_shader_parameter("construction_alpha", alpha)
	## Same render-priority fix as the placement ghost in main.gd — grass
	## alpha-blends at priority 0 too and would otherwise draw over this.
	material.render_priority = 1
	return material
