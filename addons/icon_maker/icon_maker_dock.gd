@tool
extends VBoxContainer
## Select a .glb/.tscn/.png in the FileSystem dock, press Use Selected, tweak
## the view, then Save. Drag the saved PNG onto a BuildingType's,
## ProducibleItem's or Ability's `icon` field.

const OUTPUT_DIR: String = "res://assets/ui/icons"
const PREVIEW_SIZE: int = 160

var _source: LineEdit
var _output: LineEdit
var _size: SpinBox
var _yaw: SpinBox
var _pitch: SpinBox
var _zoom: SpinBox
var _outline: CheckBox
var _frame_w: SpinBox
var _frame_h: SpinBox
var _row: SpinBox
var _column: SpinBox
var _preview: TextureRect
var _status: Label
var _save: Button
var _image: Image
## Bumped per render so a slow model render finishing late can't overwrite a
## newer preview.
var _generation: int = 0

func _ready() -> void:
	var source_row := HBoxContainer.new()
	_source = LineEdit.new()
	_source.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_source.placeholder_text = "res://..."
	_source.text_submitted.connect(func(_text: String): _on_source_changed())
	source_row.add_child(_source)
	var use_selected := Button.new()
	use_selected.text = "Use Selected"
	use_selected.pressed.connect(_use_selected)
	source_row.add_child(use_selected)
	add_child(source_row)

	var grid := GridContainer.new()
	grid.columns = 4
	_size = _spin(grid, "Size", 8, 128, 1, IconMaker.DEFAULT_SIZE)
	_zoom = _spin(grid, "Zoom", 0.25, 4.0, 0.05, 1.0)
	_yaw = _spin(grid, "Yaw", -180, 180, 5, 35)
	_pitch = _spin(grid, "Pitch", 0, 90, 5, 35)
	_frame_w = _spin(grid, "Frame W", 0, 1024, 1, 0)
	_frame_h = _spin(grid, "Frame H", 0, 1024, 1, 0)
	_row = _spin(grid, "Row", 0, 256, 1, 0)
	_column = _spin(grid, "Column", 0, 256, 1, 0)
	add_child(grid)

	_outline = CheckBox.new()
	_outline.text = "Outline"
	_outline.button_pressed = true
	_outline.toggled.connect(func(_on: bool): _refresh())
	add_child(_outline)

	var backdrop := PanelContainer.new()
	backdrop.custom_minimum_size = Vector2(PREVIEW_SIZE, PREVIEW_SIZE)
	backdrop.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_preview = TextureRect.new()
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	backdrop.add_child(_preview)
	add_child(backdrop)

	var output_row := HBoxContainer.new()
	_output = LineEdit.new()
	_output.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	output_row.add_child(_output)
	_save = Button.new()
	_save.text = "Save"
	_save.disabled = true
	_save.pressed.connect(_save_icon)
	output_row.add_child(_save)
	add_child(output_row)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)

func _spin(grid: GridContainer, caption: String, low: float, high: float, step: float, value: float) -> SpinBox:
	var label := Label.new()
	label.text = caption
	grid.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = step
	spin.value = value
	spin.value_changed.connect(func(_v: float): _refresh())
	grid.add_child(spin)
	return spin

func _use_selected() -> void:
	var selected: PackedStringArray = EditorInterface.get_selected_paths()
	if selected.is_empty():
		_status.text = "Select a model, scene or image in the FileSystem dock first."
		return
	_source.text = selected[0]
	_on_source_changed()

## A new source gets its own output name and the defaults that suit it: an
## outline for models, none for sprites (the unit art has its own).
func _on_source_changed() -> void:
	var path := _source.text.strip_edges()
	var kind := IconMaker.source_kind(path)
	var base := path.get_file().get_basename().trim_suffix("_building").trim_suffix("_unit")
	_output.text = "%s/%s.png" % [OUTPUT_DIR, base]
	_outline.set_pressed_no_signal(kind == "model")
	var model := kind == "model"
	for spin in [_yaw, _pitch, _zoom]:
		spin.editable = model
	for spin in [_frame_w, _frame_h, _row, _column]:
		spin.editable = kind == "sprite"
	_refresh()

func _refresh() -> void:
	if not is_node_ready():
		return
	_generation += 1
	var generation := _generation
	var path := _source.text.strip_edges()
	if path.is_empty():
		return
	var options := IconMaker.Options.new()
	options.size = int(_size.value)
	options.yaw = _yaw.value
	options.pitch = _pitch.value
	options.zoom = _zoom.value
	options.outline = _outline.button_pressed
	options.frame_size = Vector2i(int(_frame_w.value), int(_frame_h.value))
	options.frame_row = int(_row.value)
	options.frame_column = int(_column.value)
	var image: Image = await IconMaker.make(self, path, options)
	if generation != _generation:
		return
	_image = image
	_preview.texture = ImageTexture.create_from_image(image) if image != null else null
	_save.disabled = image == null
	_status.text = "" if image != null else "Nothing to make an icon from at %s." % path

func _save_icon() -> void:
	if _image == null:
		return
	var path := _output.text.strip_edges()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var error := _image.save_png(path)
	if error != OK:
		_status.text = "Couldn't save %s (%s)." % [path, error_string(error)]
		return
	EditorInterface.get_resource_filesystem().scan()
	_status.text = "Saved %s" % path
