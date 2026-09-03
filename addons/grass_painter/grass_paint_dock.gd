@tool
extends ScrollContainer
## Built entirely in code (no companion .tscn) so the whole dock is one
## self-contained file — see grass_painter_plugin.gd, which owns an instance
## of this and reads its public state every paint event.
##
## Extends ScrollContainer (with an inner VBoxContainer holding the actual
## controls) rather than being the VBoxContainer directly — there are enough
## rows now that the dock's content reliably exceeds the visible dock panel
## height, and without scrolling the lower controls (Max Scale included)
## are just clipped off with no way to reach them.

signal clear_requested

## Set by grass_painter_plugin.gd right after instantiating this dock — used
## to ask it to prep a target's own material (ensure_target_ready) whenever
## a layer is created or selected, so this dock always edits that layer's
## own material rather than the shared template. Kept as the generic
## EditorPlugin type (not the concrete grass_painter_plugin.gd script) to
## avoid a circular preload between the two files.
var plugin: EditorPlugin

var paint_mode_active: bool = false
var erase_mode: bool = false
var brush_radius: float = 2.5
var density: int = 6
var min_scale: float = 0.8
var max_scale: float = 1.3

var _target: MultiMeshInstance3D = null
var _target_label: Label
var _paint_toggle: CheckButton
var _confirm_dialog: ConfirmationDialog
var _shadow_toggle: CheckButton

## wind_velocity is stored on the material as a single Vector2 (direction *
## speed combined); the dock splits it back into these two for friendlier
## controls and recombines them on change — see _apply_wind_velocity.
var _wind_direction_deg: float = 0.0
var _wind_speed: float = 1.0
var _wind_direction_spin: SpinBox
var _wind_speed_spin: SpinBox

## The shared grass material (see grass_painter_plugin.gd's set_grass_material) —
## edited live, so an already-painted layer updates immediately when a new
## texture is picked, same as editing the .tres directly in the Inspector would.
var _material: ShaderMaterial = null
var _shape_texture_picker: EditorResourcePicker
## The Gradient resource actually backing shader_parameter/color_gradient's
## GradientTexture1D — edited in place (base at offset 0, top at offset 1) so
## the texture regenerates itself via the Gradient's own "changed" signal.
var _color_gradient: Gradient = null
var _base_color_picker: ColorPickerButton
var _top_color_picker: ColorPickerButton
var _billboard_toggle: CheckButton

func _ready() -> void:
	custom_minimum_size = Vector2(220, 0)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 6)
	add_child(content)

	var title := Label.new()
	title.text = "Grass Painter"
	title.add_theme_font_size_override("font_size", 16)
	content.add_child(title)

	_target_label = Label.new()
	_target_label.text = "Target: (none)"
	_target_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	content.add_child(_target_label)

	var use_selected_button := Button.new()
	use_selected_button.text = "Use Selected MultiMeshInstance3D"
	use_selected_button.pressed.connect(_on_use_selected_pressed)
	content.add_child(use_selected_button)

	var create_button := Button.new()
	create_button.text = "Create New Grass Layer"
	create_button.tooltip_text = "Adds a new MultiMeshInstance3D (with the grass mesh/material already set up) as a child of the currently selected node."
	create_button.pressed.connect(_on_create_pressed)
	content.add_child(create_button)

	_shadow_toggle = CheckButton.new()
	_shadow_toggle.text = "Cast Shadows"
	_shadow_toggle.button_pressed = true
	_shadow_toggle.toggled.connect(_on_shadow_toggled)
	content.add_child(_shadow_toggle)

	content.add_child(HSeparator.new())

	var texture_row := HBoxContainer.new()
	var texture_label := Label.new()
	texture_label.text = "Grass Texture"
	texture_label.custom_minimum_size = Vector2(110, 0)
	texture_row.add_child(texture_label)
	_shape_texture_picker = EditorResourcePicker.new()
	_shape_texture_picker.base_type = "Texture2D"
	_shape_texture_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shape_texture_picker.resource_changed.connect(_on_shape_texture_changed)
	texture_row.add_child(_shape_texture_picker)
	content.add_child(texture_row)

	var texture_hint := Label.new()
	texture_hint.text = "An alpha-masked blade/tuft image — the shape stamped onto every blade quad. Defaults to a plain radial gradient placeholder."
	texture_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	texture_hint.add_theme_font_size_override("font_size", 11)
	content.add_child(texture_hint)

	_billboard_toggle = CheckButton.new()
	_billboard_toggle.text = "Billboard"
	_billboard_toggle.toggled.connect(_on_billboard_toggled)
	content.add_child(_billboard_toggle)

	var billboard_hint := Label.new()
	billboard_hint.text = "Rotates each blade to always face the camera. The mesh is a crossed pair of quads, which already gives angular coverage without this — enabling it collapses both quads to face the same way, so it's best left off unless your texture is a single flat quad."
	billboard_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	billboard_hint.add_theme_font_size_override("font_size", 11)
	content.add_child(billboard_hint)

	var base_color_row := HBoxContainer.new()
	var base_color_label := Label.new()
	base_color_label.text = "Base Color"
	base_color_label.custom_minimum_size = Vector2(110, 0)
	base_color_row.add_child(base_color_label)
	_base_color_picker = ColorPickerButton.new()
	_base_color_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_base_color_picker.color_changed.connect(_on_base_color_changed)
	base_color_row.add_child(_base_color_picker)
	content.add_child(base_color_row)

	var top_color_row := HBoxContainer.new()
	var top_color_label := Label.new()
	top_color_label.text = "Top Color"
	top_color_label.custom_minimum_size = Vector2(110, 0)
	top_color_row.add_child(top_color_label)
	_top_color_picker = ColorPickerButton.new()
	_top_color_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_top_color_picker.color_changed.connect(_on_top_color_changed)
	top_color_row.add_child(_top_color_picker)
	content.add_child(top_color_row)

	var color_hint := Label.new()
	color_hint.text = "Recolors your imported texture: each blade is tinted somewhere between these two, chosen per-instance by the noise texture — not a root-to-tip gradient on a single blade."
	color_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	color_hint.add_theme_font_size_override("font_size", 11)
	content.add_child(color_hint)

	content.add_child(HSeparator.new())

	var wind_title := Label.new()
	wind_title.text = "Wind"
	content.add_child(wind_title)

	var direction_row := _make_spin_row("Direction (deg)", 0.0, 360.0, 1.0, _wind_direction_deg, _on_wind_direction_changed)
	_wind_direction_spin = direction_row.get_child(1)
	content.add_child(direction_row)
	var speed_row := _make_spin_row("Speed", 0.0, 5.0, 0.05, _wind_speed, _on_wind_speed_changed)
	_wind_speed_spin = speed_row.get_child(1)
	content.add_child(speed_row)

	var wind_hint := Label.new()
	wind_hint.text = "The wind noise texture sweeps across world space rather than each blade swaying independently."
	wind_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	wind_hint.add_theme_font_size_override("font_size", 11)
	content.add_child(wind_hint)

	content.add_child(HSeparator.new())

	_paint_toggle = CheckButton.new()
	_paint_toggle.text = "Painting Enabled"
	_paint_toggle.toggled.connect(func(value): paint_mode_active = value)
	content.add_child(_paint_toggle)

	var erase_check := CheckButton.new()
	erase_check.text = "Erase Mode"
	erase_check.toggled.connect(func(value): erase_mode = value)
	content.add_child(erase_check)

	content.add_child(_make_spin_row("Brush Radius", 0.25, 30.0, 0.25, brush_radius, func(v): brush_radius = v))
	content.add_child(_make_spin_row("Density (per dab)", 1, 50, 1, density, func(v): density = int(v)))
	content.add_child(_make_spin_row("Min Scale", 0.1, 5.0, 0.05, min_scale, func(v): min_scale = v))
	content.add_child(_make_spin_row("Max Scale", 0.1, 5.0, 0.05, max_scale, func(v): max_scale = v))

	content.add_child(HSeparator.new())

	var clear_button := Button.new()
	clear_button.text = "Clear Target"
	clear_button.pressed.connect(_on_clear_pressed)
	content.add_child(clear_button)

	var hint := Label.new()
	hint.text = "Hold left click in the 3D viewport (while Painting Enabled) to paint or erase."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint.add_theme_font_size_override("font_size", 11)
	content.add_child(hint)

	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.dialog_text = "Remove every grass instance on this target?"
	_confirm_dialog.confirmed.connect(func(): clear_requested.emit())
	content.add_child(_confirm_dialog)

func _make_spin_row(label_text: String, min_v: float, max_v: float, step: float, initial: float, on_change: Callable) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(110, 0)
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = step
	spin.value = initial
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(on_change)
	row.add_child(spin)
	return row

func _on_use_selected_pressed() -> void:
	var selection := EditorInterface.get_selection().get_selected_nodes()
	if selection.is_empty() or not (selection[0] is MultiMeshInstance3D):
		push_warning("Grass Painter: select a MultiMeshInstance3D node in the scene tree first.")
		return
	set_target(selection[0])

func _on_create_pressed() -> void:
	var selection := EditorInterface.get_selection().get_selected_nodes()
	var parent: Node = selection[0] if not selection.is_empty() else EditorInterface.get_edited_scene_root()
	if parent == null:
		push_warning("Grass Painter: open/select a scene first.")
		return
	var instance := MultiMeshInstance3D.new()
	instance.name = "GrassMultiMesh"
	parent.add_child(instance)
	instance.owner = EditorInterface.get_edited_scene_root()
	set_target(instance)

func _on_clear_pressed() -> void:
	if _target == null:
		return
	_confirm_dialog.popup_centered()

func set_target(node: MultiMeshInstance3D) -> void:
	_target = node
	_target_label.text = "Target: %s" % (node.get_path() if node else "(none)")
	if not node:
		return
	_shadow_toggle.set_pressed_no_signal(node.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	## Ensures this specific layer has its own (not shared) material set up
	## immediately — even before anything's been painted on it yet — then
	## switches every control below to editing that material instead of
	## whatever the previously-selected layer (or the template) was using.
	var material: ShaderMaterial = plugin.ensure_target_ready(node)
	set_grass_material(material)

func get_target() -> MultiMeshInstance3D:
	if _target != null and not is_instance_valid(_target):
		_target = null
		_target_label.text = "Target: (none)"
	return _target

## Called once by grass_painter_plugin.gd right after creating this dock, so
## the texture/color pickers above have something to read/write from the start.
func set_grass_material(material: ShaderMaterial) -> void:
	_material = material
	if not _material:
		return
	_shape_texture_picker.edited_resource = _material.get_shader_parameter("shape_texture")
	_billboard_toggle.set_pressed_no_signal(_material.get_shader_parameter("billboard"))

	var velocity: Vector2 = _material.get_shader_parameter("wind_velocity")
	_wind_direction_deg = rad_to_deg(velocity.angle())
	if _wind_direction_deg < 0.0:
		_wind_direction_deg += 360.0
	_wind_speed = velocity.length()
	_wind_direction_spin.set_value_no_signal(_wind_direction_deg)
	_wind_speed_spin.set_value_no_signal(_wind_speed)

	## Whatever Gradient the material's color_gradient texture already wraps
	## is adopted (and normalized down to exactly 2 stops) rather than
	## replaced outright, so a hand-picked initial look in the .tres survives
	## as the starting Base/Top colors instead of always resetting to some
	## hardcoded default.
	var gradient_texture: GradientTexture1D = _material.get_shader_parameter("color_gradient")
	if gradient_texture == null:
		return
	_color_gradient = gradient_texture.gradient
	if _color_gradient == null:
		_color_gradient = Gradient.new()
		gradient_texture.gradient = _color_gradient
	var colors := _color_gradient.colors
	var base_color: Color = colors[0] if colors.size() > 0 else Color(0.16, 0.32, 0.1)
	var top_color: Color = colors[-1] if colors.size() > 0 else Color(0.55, 0.62, 0.25)
	_color_gradient.offsets = PackedFloat32Array([0.0, 1.0])
	_color_gradient.colors = PackedColorArray([base_color, top_color])
	_base_color_picker.color = base_color
	_top_color_picker.color = top_color

func _on_shape_texture_changed(resource: Resource) -> void:
	if _material:
		_material.set_shader_parameter("shape_texture", resource)

func _on_billboard_toggled(pressed: bool) -> void:
	if _material:
		_material.set_shader_parameter("billboard", pressed)

func _on_base_color_changed(color: Color) -> void:
	if _color_gradient:
		_color_gradient.set_color(0, color)

func _on_top_color_changed(color: Color) -> void:
	if _color_gradient:
		_color_gradient.set_color(1, color)

func _on_shadow_toggled(pressed: bool) -> void:
	if _target:
		_target.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if pressed \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## --- Wind ---
## wind_velocity is one Vector2 on the shader (direction and speed baked
## together); recombined here from the two friendlier dock controls so the
## Inspector-facing uniform doesn't need to change shape.
func _apply_wind_velocity() -> void:
	if not _material:
		return
	var rad := deg_to_rad(_wind_direction_deg)
	_material.set_shader_parameter("wind_velocity", Vector2(cos(rad), sin(rad)) * _wind_speed)

func _on_wind_direction_changed(degrees: float) -> void:
	_wind_direction_deg = degrees
	_apply_wind_velocity()

func _on_wind_speed_changed(speed: float) -> void:
	_wind_speed = speed
	_apply_wind_velocity()
