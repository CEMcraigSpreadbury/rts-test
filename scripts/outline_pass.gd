class_name OutlinePass
extends RefCounted
## Puts the ink-outline pass (shaders/post/outline.gdshader) in front of a
## camera: a full-screen quad that draws dark edges on whatever wrote
## OUTLINE_STENCIL to the stencil buffer. Not on the Compatibility renderer
## (the web build), which has no normal buffer to find creases in.

const SHADER: Shader = preload("res://shaders/post/outline.gdshader")
## What an outlined material writes. Kept in step with the
## `stencil_mode write, compare_always, 2;` lines in the world shaders. Not 1:
## the unit silhouette masks (unit_batch_mask.gdshader) already write that.
const OUTLINE_STENCIL: int = 2
## ...and a roughness inside the id range of shaders/util/outline_mark.gdshaderinc.
const OUTLINE_ROUGHNESS: float = 153.0 / 255.0

## Forward+ and Mobile only: the Compatibility renderer has no normal-roughness
## buffer to read, nor the instance uniform the ids use.
static func supported() -> bool:
	return RenderingServer.get_current_rendering_method() != "gl_compatibility"

static func attach(camera: Camera3D) -> void:
	if not supported():
		return
	var quad := MeshInstance3D.new()
	quad.name = "OutlinePass"
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2.0, 2.0)
	quad.mesh = mesh
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.render_priority = Material.RENDER_PRIORITY_MAX
	quad.material_override = material
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	## Never culled: the vertex shader pins it to the screen wherever it is.
	quad.extra_cull_margin = 16384.0
	camera.add_child(quad)

## For a StandardMaterial3D (props, rocks) rather than one of the world shaders.
static func mark(material: BaseMaterial3D) -> void:
	material.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
	material.stencil_flags = BaseMaterial3D.STENCIL_FLAG_WRITE
	material.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_ALWAYS
	material.stencil_reference = OUTLINE_STENCIL
	material.roughness = OUTLINE_ROUGHNESS
