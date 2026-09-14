class_name ResearchPanel
extends PanelContainer
## The Research overlay (Tab, or the Research button on the PowerBar):
## the local player's Ruler tree as four tier rows, with a line from each node
## up to every node it requires. A live overlay — the match keeps running
## behind it, even in single player. Buying goes through Research.request_buy;
## the host decides, and the tree redraws once it's told (owned_changed).

const COLUMN_WIDTH: float = 156.0
const ROW_HEIGHT: float = 84.0
const NODE_SIZE: Vector2 = Vector2(144.0, 56.0)
const COLUMNS: int = 4
const TIERS: int = 4
const TITLE_FONT_SIZE: int = 20
const LINE_WIDTH: float = 2.0
const LINE_OWNED_COLOR: Color = Color(0.95, 0.78, 0.35)
const LINE_LOCKED_COLOR: Color = Color(0.45, 0.45, 0.5, 0.6)
const UNAFFORDABLE_FONT_COLOR: Color = Color(1.0, 0.45, 0.4)
## An owned node keeps the gold (hover) frame with light gold text.
const OWNED_FONT_COLOR: Color = Color(1.0, 0.88, 0.55)
const LOCKED_MODULATE: Color = Color(1.0, 1.0, 1.0, 0.6)
const DETAIL_MIN_HEIGHT: float = 40.0
## Nudged up from dead centre so the bottom bar doesn't cover the last row.
const VERTICAL_OFFSET: float = -60.0
## Node buttons use the command card's SquareButton frames, but nine-patched
## so a wide button doesn't stretch the border. The frame is first shrunk to
## the command card's own 40px button size, so its border comes out the same
## thickness on screen as it does there.
const FRAME_SIZE: Vector2i = Vector2i(40, 40)
const FRAME_MARGIN: float = 10.0
const NODE_STYLE_STATES: Array[StringName] = [&"normal", &"hover", &"pressed", &"disabled", &"focus"]

var main: Main

var _ruler: Ruler
var _canvas: TreeCanvas
var _detail: Label
## Parallel to _ruler.nodes.
var _buttons: Array[Button] = []
## State name -> nine-patched SquareButton style.
var _node_styles: Dictionary = {}

## Draws the requirement lines underneath the node buttons (its children).
class TreeCanvas extends Control:
	## Each entry: [from: Vector2, to: Vector2, color: Color].
	var lines: Array = []

	func _draw() -> void:
		for line in lines:
			draw_line(line[0], line[1], line[2], LINE_WIDTH, true)

func _ready() -> void:
	name = "ResearchPanel"
	visible = false
	_ruler = Research.ruler_for(main.my_peer_id())
	for state in NODE_STYLE_STATES:
		var source := get_theme_stylebox(state, &"SquareButton") as StyleBoxTexture
		if source != null and source.texture != null:
			_node_styles[state] = _nine_patch(source)

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = _ruler.ruler_name if _ruler != null else ""
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	vbox.add_child(title)

	_canvas = TreeCanvas.new()
	_canvas.custom_minimum_size = Vector2(COLUMN_WIDTH * COLUMNS, ROW_HEIGHT * TIERS)
	vbox.add_child(_canvas)

	_detail = Label.new()
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail.custom_minimum_size = Vector2(0.0, DETAIL_MIN_HEIGHT)
	vbox.add_child(_detail)

	if _ruler != null:
		for i in _ruler.nodes.size():
			_buttons.append(_make_node_button(i))

	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	offset_top += VERTICAL_OFFSET
	offset_bottom += VERTICAL_OFFSET

	main.research.owned_changed.connect(_refresh)
	ResourceStockpile.changed.connect(func(_resource_name: String, _amount: int):
		if visible:
			_refresh())

func _nine_patch(source: StyleBoxTexture) -> StyleBoxTexture:
	var image := source.texture.get_image()
	if image.is_compressed():
		image.decompress()
	image.resize(FRAME_SIZE.x, FRAME_SIZE.y, Image.INTERPOLATE_LANCZOS)
	var style := source.duplicate() as StyleBoxTexture
	style.texture = ImageTexture.create_from_image(image)
	style.set_texture_margin_all(FRAME_MARGIN)
	return style

func _make_node_button(index: int) -> Button:
	var node: ResearchNode = _ruler.nodes[index]
	var button := Button.new()
	button.theme_type_variation = &"SquareButton"
	for state in _node_styles:
		button.add_theme_stylebox_override(state, _node_styles[state])
	button.focus_mode = Control.FOCUS_NONE
	button.text = "%s\n%d" % [node.node_name, node.cost]
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.size = NODE_SIZE
	button.pressed.connect(_on_node_pressed.bind(index))
	button.pressed.connect(main.hud._punch_control.bind(button))
	button.mouse_entered.connect(func(): _detail.text = node.description)
	button.mouse_exited.connect(func(): _detail.text = "")
	_canvas.add_child(button)
	return button

## Tab from anywhere a hotkey would work. In _input rather than Main's
## _unhandled_input because a focused Control would otherwise take Tab for
## focus navigation before it ever got there.
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo and event.keycode == Main.RESEARCH_PANEL_KEY):
		return
	if main.game_over or main.local_player_out or main.chat.is_input_open() or main._is_pause_menu_open():
		return
	toggle()
	get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if visible and (main.game_over or main.local_player_out):
		close()

func toggle() -> void:
	if visible:
		close()
	else:
		visible = true
		_refresh()

func close() -> void:
	visible = false
	_detail.text = ""

func _on_node_pressed(index: int) -> void:
	var costs := Research.node_costs(_ruler.nodes[index])
	if not main.hud.can_afford_locally(costs):
		main.hud.flash_missing_resources(costs)
		return
	main.research.request_buy(index)
	main.play_command_sound()

## Centre of a node's slot: tier picks the row, column the (fractional) slot
## across.
func _slot_centre(node: ResearchNode) -> Vector2:
	return Vector2((node.column + 0.5) * COLUMN_WIDTH, (node.tier - 0.5) * ROW_HEIGHT)

func _refresh() -> void:
	if _ruler == null:
		return
	var owned: Array[int] = main.research.my_owned
	for i in _ruler.nodes.size():
		var node: ResearchNode = _ruler.nodes[i]
		var button: Button = _buttons[i]
		## Centred on its real size, which can outgrow NODE_SIZE when a long
		## name wraps onto a third line.
		button.position = _slot_centre(node) - button.size * 0.5
		var is_owned := owned.has(i)
		var unlocked := Research.requirements_met(_ruler, node, owned)
		button.disabled = is_owned or not unlocked
		button.modulate = Color.WHITE if is_owned or unlocked else LOCKED_MODULATE
		if is_owned:
			button.add_theme_stylebox_override(&"disabled", _node_styles.get(&"hover"))
			button.add_theme_color_override(&"font_disabled_color", OWNED_FONT_COLOR)
		else:
			button.add_theme_stylebox_override(&"disabled", _node_styles.get(&"disabled"))
			button.remove_theme_color_override(&"font_disabled_color")
		var short := unlocked and not is_owned and not main.hud.can_afford_locally(Research.node_costs(node))
		for color_name in [&"font_color", &"font_hover_color", &"font_pressed_color"]:
			if short:
				button.add_theme_color_override(color_name, UNAFFORDABLE_FONT_COLOR)
			else:
				button.remove_theme_color_override(color_name)

	## After every button is placed, so each line meets the real edges.
	var lines: Array = []
	for i in _ruler.nodes.size():
		var rect := _buttons[i].get_rect()
		var top := Vector2(rect.get_center().x, rect.position.y)
		for required in _ruler.nodes[i].requires:
			var parent_index := _ruler.nodes.find(required)
			var parent_rect := _buttons[parent_index].get_rect()
			var bottom := Vector2(parent_rect.get_center().x, parent_rect.end.y)
			lines.append([bottom, top, LINE_OWNED_COLOR if owned.has(parent_index) else LINE_LOCKED_COLOR])
	_canvas.lines = lines
	_canvas.queue_redraw()
