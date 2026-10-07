class_name LensPass
extends RefCounted
## Puts the lens pass (shaders/post/lens.gdshader) over a camera's view: a
## full-screen rect on its own canvas layer, under the HUD, that softens the
## edges and corners, darkens them and hazes the far ground.

const SHADER: Shader = preload("res://shaders/post/lens.gdshader")
## Under the HUD (CanvasLayer 1) and anything else drawn in screen space.
const LAYER: int = -1
## The corner blur's full radius; the Depth of Field option switches it off.
const CORNER_BLUR: float = 6.0

static func attach(camera: Camera3D) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.name = "LensPass"
	layer.layer = LAYER
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	## World clicks go through _unhandled_input; a rect that stopped the mouse
	## would swallow every one of them.
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"corner_blur", CORNER_BLUR)
	rect.material = material
	layer.add_child(rect)
	camera.add_child(layer)
	return layer

## Turns the corner blur on or off with the depth of field.
static func set_blur(layer: CanvasLayer, on: bool) -> void:
	if layer == null or layer.get_child_count() == 0:
		return
	var material := (layer.get_child(0) as ColorRect).material as ShaderMaterial
	material.set_shader_parameter(&"corner_blur", CORNER_BLUR if on else 0.0)
