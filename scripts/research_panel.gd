class_name ResearchPanel
extends PanelContainer
## The Research overlay (Tab, or the Research button in the tool column):
## the local player's three faction powers as cards in a row, joined by a line
## from each to the next, since they are bought in that order. A live overlay
## — the match keeps running behind it, even in single player. Buying goes
## through Research.request_buy; the host decides, and the cards redraw once
## it's told (owned_changed).

const NODE_SIZE: Vector2 = Vector2(260.0, 190.0)
const CARD_GAP: float = 56.0
const TITLE_FONT_SIZE: int = 33
const LINE_WIDTH: float = 3.3
const LINE_OWNED_COLOR: Color = UiStyle.ACCENT
const LINE_LOCKED_COLOR: Color = Color(1.0, 1.0, 1.0, 0.18)
const UNAFFORDABLE_FONT_COLOR: Color = UiStyle.BAD
## An owned node keeps the gold (hover) frame with light gold text.
const OWNED_FONT_COLOR: Color = UiStyle.ACCENT
const LOCKED_MODULATE: Color = Color(1.0, 1.0, 1.0, 0.55)
const DETAIL_MIN_HEIGHT: float = 66.7
## Nudged up from dead centre so the bottom bar doesn't cover the last row.
const VERTICAL_OFFSET: float = -100.0
## Inside a card: its glyph, then its name, then its cost, centred.
const NODE_INSET: float = 16.0
const NODE_GAP: float = 10.0
const NODE_NAME_SIZE: int = 22
const NODE_COST_SIZE: int = 18
## so a wide button doesn't stretch the border. The frame is first shrunk to
## the command card's own 40px button size, so its border comes out the same
## thickness on screen as it does there.

var main: Main

var _powers: Array[ResearchNode] = []
var _canvas: CardRow
var _detail: Label
## Parallel to _powers.
var _buttons: Array[Button] = []
## Parallel to _powers: {glyph: TextureRect or null, title: Label,
## cost_row: Control, cost: Label} -- what _refresh recolours.
var _parts: Array[Dictionary] = []
var _node_styles: Dictionary = {}
var _owned_style: StyleBox

## Draws the lines between the cards (its children).
class CardRow extends Control:
	## Each entry: [from: Vector2, to: Vector2, color: Color].
	var lines: Array = []

	func _draw() -> void:
		for line in lines:
			draw_line(line[0], line[1], line[2], LINE_WIDTH, true)

func _ready() -> void:
	name = "ResearchPanel"
	visible = false
	_powers = Research.powers_for(main.my_peer_id())
	## Straight from the tokens. These used to be derived from the theme's
	## SquareButton StyleBoxTexture, which no longer exists now that the theme is
	## all StyleBoxFlat -- the lookup returned null and every node quietly fell
	## back to the plain button look.
	_node_styles = {
		&"normal": UiStyle.slot_box(),
		&"hover": UiStyle.slot_box(UiStyle.LINE_STRONG),
		&"pressed": UiStyle.slot_box(UiStyle.ACCENT),
		&"focus": UiStyle.slot_box(UiStyle.LINE_STRONG),
		&"disabled": UiStyle.slot_box(Color(UiStyle.LINE, 0.22)),
	}
	## An owned node reads as bought: accent border, accent text.
	_owned_style = UiStyle.slot_box(UiStyle.ACCENT)

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	add_child(margin)
	var body := UiPlasticBody.new()
	body.fresh_backdrop = true
	add_child(body)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 13)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = main.my_faction().faction_name
	title.theme_type_variation = &"TitleLabel"
	title.add_theme_font_size_override("font_size", UiStyle.SIZE_MODAL_TITLE)
	vbox.add_child(title)

	var rule := SectionRule.new()
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(rule)

	_canvas = CardRow.new()
	_canvas.custom_minimum_size = Vector2(NODE_SIZE.x * _powers.size() + CARD_GAP * maxi(_powers.size() - 1, 0), NODE_SIZE.y)
	vbox.add_child(_canvas)

	_detail = Label.new()
	_detail.theme_type_variation = &"ProseLabel"
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail.max_lines_visible = 2
	_detail.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	## In a plain Control of a fixed height, which doesn't take its child's
	## size: two lines of description or none, the overlay stays the same size.
	var detail_box := Control.new()
	detail_box.clip_contents = true
	detail_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(detail_box)
	detail_box.add_child(_detail)
	_detail.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var font: Font = _detail.get_theme_font(&"font")
	var line: float = font.get_height(_detail.get_theme_font_size(&"font_size")) + _detail.get_theme_constant(&"line_spacing")
	detail_box.custom_minimum_size = Vector2(0.0, maxf(DETAIL_MIN_HEIGHT, line * 2.0 + 8.0))

	for i in _powers.size():
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

func _make_node_button(index: int) -> Button:
	var node: ResearchNode = _powers[index]
	var button := Button.new()
	button.theme_type_variation = &"SquareButton"
	for state in _node_styles:
		button.add_theme_stylebox_override(state, _node_styles[state])
	button.focus_mode = Control.FOCUS_NONE
	button.size = NODE_SIZE
	button.pressed.connect(_on_node_pressed.bind(index))
	button.pressed.connect(main.hud._punch_control.bind(button))
	button.mouse_entered.connect(func(): _detail.text = node.description)
	button.mouse_exited.connect(func(): _detail.text = "")

	## Placed by hand rather than in containers that fill the button: a Button
	## is not a container, so nothing inside it can make it grow.
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", NODE_GAP)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.position = Vector2(NODE_INSET, 0.0)
	column.size = Vector2(NODE_SIZE.x - NODE_INSET * 2.0, NODE_SIZE.y)
	button.add_child(column)
	var glyph: TextureRect = null
	if node.glyph != &"":
		glyph = UiGlyphs.rect(node.glyph, UiStyle.GLYPH_PORTRAIT, CommandSlot.GLYPH_TINT)
		glyph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(glyph)
	var title := Label.new()
	title.text = node.node_name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.max_lines_visible = 2
	title.add_theme_font_override("font", UiStyle.font_data_bold())
	title.add_theme_font_size_override("font_size", NODE_NAME_SIZE)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title)
	var cost_row := HBoxContainer.new()
	cost_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cost_row.add_theme_constant_override("separation", 5)
	cost_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(cost_row)
	var cost_glyph := UiGlyphs.rect(Research.RESOURCE.glyph, UiStyle.GLYPH_TIP, Research.RESOURCE.display_color)
	cost_glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cost_row.add_child(cost_glyph)
	var cost := Label.new()
	cost.text = str(node.cost)
	cost.add_theme_font_override("font", UiStyle.font_data_bold())
	cost.add_theme_font_size_override("font_size", NODE_COST_SIZE)
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost_row.add_child(cost)
	_parts.append({"glyph": glyph, "title": title, "cost_row": cost_row, "cost": cost})

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
	## A tutorial can keep research out of the way until it has been taught.
	if not visible and not MatchRules.active().hud_allowed(main.my_peer_id(), "research"):
		return
	if visible:
		close()
	else:
		visible = true
		_refresh()
		main.report_tutorial_input(&"research_panel")

func close() -> void:
	visible = false
	_detail.text = ""

func _on_node_pressed(index: int) -> void:
	var costs := Research.node_costs(_powers[index])
	if not main.hud.can_afford_locally(costs):
		main.hud.flash_missing_resources(costs)
		return
	main.research.request_buy(index)
	main.play_command_sound()

func _refresh() -> void:
	var owned: Array[int] = main.research.my_owned
	for i in _powers.size():
		var node: ResearchNode = _powers[i]
		var button: Button = _buttons[i]
		button.position = Vector2((NODE_SIZE.x + CARD_GAP) * i, 0.0)
		var is_owned := owned.has(i)
		## A tier a scenario has put out of reach reads as locked, the same way
		## the one before it still to buy does.
		var unlocked := Research.requirements_met(i, owned) 				and MatchRules.active().research_allowed(main.my_peer_id(), node)
		button.disabled = is_owned or not unlocked
		button.modulate = Color.WHITE if is_owned or unlocked else LOCKED_MODULATE
		button.add_theme_stylebox_override(&"disabled", _owned_style if is_owned else _node_styles.get(&"disabled"))
		## Bought: glyph and name go accent and the cost leaves. Otherwise only
		## the cost turns red when there are not the points for it.
		var short := unlocked and not is_owned and not main.hud.can_afford_locally(Research.node_costs(node))
		var parts: Dictionary = _parts[i]
		if parts.glyph != null:
			(parts.glyph as TextureRect).self_modulate = OWNED_FONT_COLOR if is_owned else CommandSlot.GLYPH_TINT
		(parts.title as Label).add_theme_color_override(&"font_color", OWNED_FONT_COLOR if is_owned else UiStyle.INK)
		(parts.cost_row as Control).visible = not is_owned
		(parts.cost as Label).add_theme_color_override(&"font_color", UNAFFORDABLE_FONT_COLOR if short else UiStyle.INK)

	## After every card is placed, so each line meets the real edges.
	var lines: Array = []
	for i in range(1, _powers.size()):
		var from_rect := _buttons[i - 1].get_rect()
		var to_rect := _buttons[i].get_rect()
		var from := Vector2(from_rect.end.x, from_rect.get_center().y)
		var to := Vector2(to_rect.position.x, to_rect.get_center().y)
		lines.append([from, to, LINE_OWNED_COLOR if owned.has(i - 1) else LINE_LOCKED_COLOR])
	_canvas.lines = lines
	_canvas.queue_redraw()
