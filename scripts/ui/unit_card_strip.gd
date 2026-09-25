class_name UiUnitCardStrip
extends UiPanel
## The army at a glance, Total War style: one card per regiment and one per kind
## of loose soldier, in the open band between the selection panel and the tools
## column. A card is the unit's figure on its team colour, the number of men,
## a health bar and a morale bar (see Morale); the diamond is the regiment's
## officer, filled while he lives. Click a card to select that body, Shift-click
## to add it, double-click to look at it.
##
## A Lord (see Lords) leads his group: his card, with his level in the corner
## and his experience where morale would be, then the cards of every body
## within his command, joined by a brass bracket above them.
##
## A fixed box with a fixed pool of cards: a change in the army restyles,
## moves and shows or hides cards in place, it never resizes the strip. Past
## what fits, the last card becomes a "+N" count, as the unit tray does.

const STRIP_LEFT: float = 694.0
const STRIP_WIDTH: float = 870.0
const STRIP_BOTTOM: float = 24.0
## Room above the cards for the bracket a Lord will draw over his regiments.
const PAD_TOP: float = 20.0
const PAD_SIDE: float = 12.0
const PAD_BOTTOM: float = 12.0
const CARD_SIZE := Vector2(68, 110)
const CARD_GAP: float = 4.0
## Between one Lord's group and the next, or the loose bodies after them.
const GROUP_GAP: float = 14.0
const MAX_BRACKETS: int = 4
const BRACKET_RISE: float = 10.0
const BRACKET_THICKNESS: float = 2.0
const XP_COLOUR := Color(0.9412, 0.8980, 0.8196, 0.55)
const WELL_HEIGHT: float = 72.0
const FIGURE_SIZE: float = 64.0
const BAR_WIDTH: float = 56.0
const BAR_HEIGHT: float = 4.0
const REFRESH_SECONDS: float = 0.25
## How much of the team colour the top and foot of the well show.
const WELL_TOP_WHITE: float = 0.18
const WELL_FOOT_DARKEN: float = 0.6
const ROUTED_WELL := Color(0.55, 0.55, 0.55)

var main: Main
var _cards: Array[Dictionary] = []
var _timer: float = 0.0
## Card index -> the units it stands for, as last drawn.
var _groups: Array = []
## Per bracket: [bar, left tick, right tick].
var _brackets: Array = []
static var _well_textures: Dictionary = {}

func _init() -> void:
	super()
	name = "UnitCardStrip"
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func setup(p_main: Main) -> void:
	main = p_main
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	var height: float = PAD_TOP + CARD_SIZE.y + PAD_BOTTOM
	offset_left = STRIP_LEFT
	offset_right = STRIP_LEFT + STRIP_WIDTH
	offset_bottom = -STRIP_BOTTOM
	offset_top = -STRIP_BOTTOM - height
	var fits: int = int((STRIP_WIDTH - PAD_SIDE * 2 + CARD_GAP) / (CARD_SIZE.x + CARD_GAP))
	for i in fits:
		var card := _make_card(i)
		card["root"].position = Vector2(PAD_SIDE + i * (CARD_SIZE.x + CARD_GAP), PAD_TOP)
		_cards.append(card)
	for i in MAX_BRACKETS:
		var parts: Array = []
		for j in 3:
			var part := ColorRect.new()
			part.color = UiStyle.LINE_STRONG
			part.mouse_filter = Control.MOUSE_FILTER_IGNORE
			part.visible = false
			add_child(part)
			parts.append(part)
		_brackets.append(parts)
	visible = false

func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = REFRESH_SECONDS
	_refresh()

## --- Building ---

func _make_card(index: int) -> Dictionary:
	var root := Panel.new()
	root.size = CARD_SIZE
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.gui_input.connect(_on_card_input.bind(index))
	add_child(root)

	var well := TextureRect.new()
	well.position = Vector2(1, 1)
	well.size = Vector2(CARD_SIZE.x - 2, WELL_HEIGHT)
	well.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	well.stretch_mode = TextureRect.STRETCH_SCALE
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(well)

	var figure := TextureRect.new()
	figure.size = Vector2(FIGURE_SIZE, FIGURE_SIZE)
	figure.position = Vector2((CARD_SIZE.x - FIGURE_SIZE) / 2.0, WELL_HEIGHT - FIGURE_SIZE + 1)
	figure.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	figure.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	figure.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	figure.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(figure)

	var pip := Panel.new()
	pip.size = Vector2(7, 7)
	pip.pivot_offset = pip.size / 2.0
	pip.position = Vector2(6, 6)
	pip.rotation = PI / 4.0
	pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(pip)

	var count := UiTextLine.make("", &"ValueLabel", UiStyle.SIZE_BODY, UiStyle.INK)
	count.position = Vector2(6, WELL_HEIGHT + 4)
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(count)

	var more := UiTextLine.make("", &"ValueLabel", UiStyle.SIZE_TOOLTIP_NAME, UiStyle.DIM)
	more.position = Vector2(0, CARD_SIZE.y / 2.0 - 12)
	more.custom_minimum_size = Vector2(CARD_SIZE.x, 24)
	more.label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	more.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(more)

	var level := UiTextLine.make("", &"ValueLabel", UiStyle.SIZE_TOOLTIP_NAME, UiStyle.ACCENT)
	level.position = Vector2(CARD_SIZE.x - 18, 3)
	level.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level.visible = false
	root.add_child(level)

	var health := _make_bar(root, CARD_SIZE.y - 14)
	var spirit := _make_bar(root, CARD_SIZE.y - 8)
	return {"root": root, "well": well, "figure": figure, "pip": pip, "count": count,
			"more": more, "level": level, "health": health, "morale": spirit, "state": -1}

func _make_bar(parent: Control, y: float) -> ColorRect:
	var back := ColorRect.new()
	back.color = Color(0, 0, 0, 0.6)
	back.position = Vector2(6, y)
	back.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(back)
	var fill := ColorRect.new()
	fill.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(fill)
	return fill

static func _well_texture(team: Color) -> Texture2D:
	var key := team.to_html()
	if not _well_textures.has(key):
		var gradient := Gradient.new()
		gradient.set_color(0, team.lerp(Color.WHITE, WELL_TOP_WHITE))
		gradient.set_color(1, team.darkened(WELL_FOOT_DARKEN))
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.width = 4
		texture.height = 64
		texture.fill_from = Vector2(0, 0)
		texture.fill_to = Vector2(0, 1)
		_well_textures[key] = texture
	return _well_textures[key]

## --- Refresh ---

func _refresh() -> void:
	var groups := _army_groups()
	visible = not groups.is_empty()
	if not visible:
		return
	_groups.clear()
	## Where each card goes: a wider gap wherever the bracket changes.
	var xs: Array[float] = []
	var x: float = PAD_SIDE
	for i in groups.size():
		if i > 0:
			x += CARD_GAP if groups[i]["bracket"] == groups[i - 1]["bracket"] and groups[i]["bracket"] >= 0 else GROUP_GAP
		if x + CARD_SIZE.x > STRIP_WIDTH - PAD_SIDE or xs.size() >= _cards.size():
			break
		xs.append(x)
		x += CARD_SIZE.x
	var overflow: bool = xs.size() < groups.size()
	var shown: int = xs.size()
	var well := _well_texture(main.get_team_tint(main.my_peer_id()))
	for i in _cards.size():
		var card: Dictionary = _cards[i]
		var root: Panel = card["root"]
		if i >= shown:
			root.visible = false
			_groups.append([])
			continue
		root.visible = true
		root.position.x = xs[i]
		if overflow and i == shown - 1:
			_show_more(card, groups.size() - i)
			var rest: Array = []
			for g in range(i, groups.size()):
				rest.append_array(groups[g]["units"])
			_groups.append(rest)
			continue
		_show_group(card, groups[i], well)
		_groups.append(groups[i]["units"])
	_place_brackets(groups, xs, shown - 1 if overflow else shown)

## A brass bracket over each Lord's run of cards.
func _place_brackets(groups: Array, xs: Array[float], drawn: int) -> void:
	var spans: Dictionary = {}
	for i in drawn:
		var b: int = groups[i]["bracket"]
		if b < 0 or b >= MAX_BRACKETS:
			continue
		var span: Array = spans.get(b, [xs[i], xs[i] + CARD_SIZE.x])
		span[1] = xs[i] + CARD_SIZE.x
		spans[b] = span
	for b in MAX_BRACKETS:
		var parts: Array = _brackets[b]
		var on: bool = spans.has(b)
		for part in parts:
			(part as ColorRect).visible = on
		if not on:
			continue
		var left: float = spans[b][0]
		var right: float = spans[b][1]
		var top: float = PAD_TOP - BRACKET_RISE
		(parts[0] as ColorRect).position = Vector2(left, top)
		(parts[0] as ColorRect).size = Vector2(right - left, BRACKET_THICKNESS)
		(parts[1] as ColorRect).position = Vector2(left, top)
		(parts[1] as ColorRect).size = Vector2(BRACKET_THICKNESS, BRACKET_RISE)
		(parts[2] as ColorRect).position = Vector2(right - BRACKET_THICKNESS, top)
		(parts[2] as ColorRect).size = Vector2(BRACKET_THICKNESS, BRACKET_RISE)

func _show_more(card: Dictionary, hidden_count: int) -> void:
	for key in ["well", "figure", "pip", "count", "level"]:
		(card[key] as CanvasItem).visible = false
	(card["health"] as ColorRect).get_parent().visible = false
	(card["morale"] as ColorRect).get_parent().visible = false
	(card["more"] as UiTextLine).visible = true
	(card["more"] as UiTextLine).set_text("+%d" % hidden_count)
	(card["root"] as Panel).add_theme_stylebox_override("panel", UiStyle.slot_box())

func _show_group(card: Dictionary, group: Dictionary, well: Texture2D) -> void:
	(card["more"] as UiTextLine).visible = false
	for key in ["well", "figure", "count"]:
		(card[key] as CanvasItem).visible = true
	(card["health"] as ColorRect).get_parent().visible = true
	(card["morale"] as ColorRect).get_parent().visible = true
	var well_rect: TextureRect = card["well"]
	well_rect.texture = well
	var sample: Unit = group["sample"]
	(card["figure"] as TextureRect).texture = UnitPortrait.of_unit(sample)
	var pip: Panel = card["pip"]
	pip.visible = group["regiment"]
	if pip.visible:
		pip.add_theme_stylebox_override("panel", UiStyle.flat(
				UiStyle.LINE_STRONG if group["officer"] else UiStyle.SLOT, UiStyle.LINE_STRONG, 0))
	var count: UiTextLine = card["count"]
	count.set_text(str(group["count"]))
	var health: ColorRect = card["health"]
	health.size.x = BAR_WIDTH * clampf(group["health"], 0.0, 1.0)
	health.color = UiStyle.GOOD
	var spirit: ColorRect = card["morale"]
	spirit.size.x = BAR_WIDTH * clampf(group["morale"], 0.0, 1.0)

	var level: UiTextLine = card["level"]
	level.visible = group["lord"]
	count.visible = not group["lord"]
	if group["lord"]:
		level.set_text(str(group["level"]))
		pip.visible = false

	var state: int = group["state"]
	var border: Color = UiStyle.ACCENT if group["selected"] else (UiStyle.LINE_STRONG if group["lord"] else UiStyle.LINE)
	var width: int = 2 if group["selected"] else UiStyle.BORDER
	var morale_colour: Color = UiStyle.ACCENT
	var count_colour: Color = UiStyle.INK
	well_rect.modulate = Color.WHITE
	(card["figure"] as TextureRect).modulate = Color.WHITE
	match state:
		Morale.State.WAVERING:
			morale_colour = UiStyle.WAVER
		Morale.State.ROUTING:
			morale_colour = UiStyle.BAD
			count_colour = UiStyle.BAD
			if not group["selected"]:
				border = UiStyle.BAD
			well_rect.modulate = ROUTED_WELL
			(card["figure"] as TextureRect).modulate = ROUTED_WELL
	spirit.color = XP_COLOUR if group["lord"] else morale_colour
	count.label.add_theme_color_override("font_color", count_colour)
	(card["root"] as Panel).add_theme_stylebox_override("panel", UiStyle.flat(UiStyle.SLOT, border, 1, width))
	_pulse(card, state)

## Wavering breathes slowly, routing flashes: on the morale bar only.
func _pulse(card: Dictionary, state: int) -> void:
	if card["state"] == state:
		return
	card["state"] = state
	var bar: ColorRect = card["morale"]
	var old: Tween = card.get("tween")
	if old != null and old.is_valid():
		old.kill()
	bar.modulate.a = 1.0
	if state != Morale.State.WAVERING and state != Morale.State.ROUTING:
		return
	var half: float = 0.7 if state == Morale.State.WAVERING else 0.35
	var tween := create_tween().set_loops()
	tween.tween_property(bar, "modulate:a", 0.35, half)
	tween.tween_property(bar, "modulate:a", 1.0, half)
	card["tween"] = tween

## Each Lord with every body in his command after him, then everyone else:
## regiments in the order they were raised, then loose soldiers by kind.
func _army_groups() -> Array:
	var me: int = main.my_peer_id()
	var regiments: Dictionary = {}
	var loose: Dictionary = {}
	var lords: Array[Unit] = []
	for node in get_tree().get_nodes_in_group(&"units"):
		var unit := node as Unit
		if unit == null or unit.owner_peer_id != me or unit.can_gather or not unit.can_fight \
				or unit.status_activity == Unit.Activity.DEAD:
			continue
		if unit.is_lord:
			lords.append(unit)
			continue
		var bucket: Dictionary = regiments if unit.regiment_id >= 0 else loose
		var key = unit.regiment_id if unit.regiment_id >= 0 else unit.scene_file_path
		if not bucket.has(key):
			bucket[key] = [] as Array[Unit]
		(bucket[key] as Array[Unit]).append(unit)
	var groups: Array = []
	var ids: Array = regiments.keys()
	ids.sort()
	for id in ids:
		groups.append(_summarise(regiments[id], true))
	var kinds: Array = loose.keys()
	kinds.sort()
	for kind in kinds:
		groups.append(_summarise(loose[kind], false))
	if lords.is_empty():
		return groups
	lords.sort_custom(func(a: Unit, b: Unit) -> bool: return a.get_instance_id() < b.get_instance_id())
	## Each body goes to the nearest Lord it is within command of.
	var led: Array = []
	for i in lords.size():
		led.append([])
	var rest: Array = []
	for group in groups:
		var centre := Vector3.ZERO
		for unit in group["units"]:
			centre += unit.global_position
		centre /= float(maxi((group["units"] as Array).size(), 1))
		var best: int = -1
		var best_distance: float = Lords.COMMAND_RADIUS
		for i in lords.size():
			var d: float = lords[i].global_position.distance_to(centre)
			if d <= best_distance:
				best_distance = d
				best = i
		if best >= 0:
			led[best].append(group)
		else:
			rest.append(group)
	var ordered: Array = []
	for i in lords.size():
		ordered.append(_summarise_lord(lords[i], i))
		for group in led[i]:
			group["bracket"] = i
			ordered.append(group)
	ordered.append_array(rest)
	return ordered

func _summarise_lord(lord: Unit, bracket: int) -> Dictionary:
	return {"units": [lord] as Array[Unit], "sample": lord, "count": 1,
			"health": float(lord.status_current_health) / float(maxi(lord.max_health, 1)),
			"morale": float(lord.lord_progress) / 10.0, "state": Morale.State.STEADY, "officer": false,
			"regiment": false, "selected": lord.selected, "lord": true, "level": lord.lord_level, "bracket": bracket}

func _summarise(units: Array[Unit], regiment: bool) -> Dictionary:
	var men := 0
	var health := 0.0
	var spirit := 0.0
	var wavering := 0
	var running := 0
	var officer := false
	var selected := false
	var sample: Unit = units[0]
	for unit in units:
		selected = selected or unit.selected
		if unit.is_officer:
			officer = true
			continue
		sample = unit
		men += 1
		health += float(unit.status_current_health) / float(maxi(unit.max_health, 1))
		spirit += float(unit.morale_level) / float(Morale.LEVELS)
		if unit.is_routing():
			running += 1
		elif unit.morale_state == Morale.State.WAVERING:
			wavering += 1
	var n: float = float(maxi(men, 1))
	var state: int = Morale.State.STEADY
	if running * 2 > men:
		state = Morale.State.ROUTING
	elif (running + wavering) * 2 > men:
		state = Morale.State.WAVERING
	return {"units": units, "sample": sample, "count": men, "health": health / n, "morale": spirit / n,
			"state": state, "officer": officer, "regiment": regiment, "selected": selected, "lord": false,
			"level": 0, "bracket": -1}

## --- Input ---

func _on_card_input(event: InputEvent, index: int) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if index >= _groups.size() or (_groups[index] as Array).is_empty():
		return
	var units: Array[Unit] = []
	for unit in _groups[index]:
		if is_instance_valid(unit):
			units.append(unit)
	if click.double_click:
		main.center_camera_on(units)
	else:
		main.select_units_from_hud(units, click.shift_pressed)
	accept_event()
	_timer = 0.0
