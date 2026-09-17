class_name GroundRingMaterial
extends RefCounted
## ShaderMaterial for flat ground rings that must stay visible over grass —
## see shaders/ground_ring.gdshader.

const SHADER: Shader = preload("res://shaders/ground_ring.gdshader")

## After the unit silhouette mask (8) and silhouette (9), under health bars.
const RENDER_PRIORITY: int = 10

static func build(color: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.render_priority = RENDER_PRIORITY
	material.set_shader_parameter("albedo_color", color)
	return material

## Tween-friendly fade: tween_method(set_alpha.bind(material), from, to, time).
static func set_alpha(alpha: float, material: ShaderMaterial) -> void:
	var color: Color = material.get_shader_parameter("albedo_color")
	color.a = alpha
	material.set_shader_parameter("albedo_color", color)
