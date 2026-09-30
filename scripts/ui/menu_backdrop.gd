class_name MenuBackdrop
extends TextureRect
## The main menu's background: the MenuBackground diorama, rendered at a
## fraction of the screen's resolution in its own world, blurred at that size,
## and stretched to fill. Rendering it small is what keeps a live 3D scene
## behind the menu cheap, and the blur hides that it is small.

const SCENE: PackedScene = preload("res://scenes/menu_background.tscn")
const BLUR_SHADER: Shader = preload("res://shaders/menu_blur.gdshader")
## Fraction of the screen's resolution the diorama renders at.
const RENDER_SCALE: float = 0.25

var _scene_viewport: SubViewport
var _blur_viewport: SubViewport
var _blur_rect: ColorRect

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

	_scene_viewport = SubViewport.new()
	_scene_viewport.own_world_3d = true
	_scene_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_scene_viewport.add_child(SCENE.instantiate())
	add_child(_scene_viewport)

	_blur_viewport = SubViewport.new()
	_blur_viewport.disable_3d = true
	_blur_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_blur_rect = ColorRect.new()
	var material := ShaderMaterial.new()
	material.shader = BLUR_SHADER
	material.set_shader_parameter(&"scene", _scene_viewport.get_texture())
	_blur_rect.material = material
	_blur_viewport.add_child(_blur_rect)
	add_child(_blur_viewport)

	texture = _blur_viewport.get_texture()
	resized.connect(_fit)
	_fit()

func _fit() -> void:
	var render_size := Vector2i((size * RENDER_SCALE).round()).max(Vector2i.ONE)
	_scene_viewport.size = render_size
	_blur_viewport.size = render_size
	_blur_rect.size = Vector2(render_size)
