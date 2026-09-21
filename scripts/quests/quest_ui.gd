class_name QuestUi
extends Control
## Everything a scenario shows the player: the objective tracker, the dialogue
## box, the briefing screen, and the world markers/pings/reveals a quest asks
## for.
##
## Draws only what the host has already decided (QuestRunner.states /
## .presentation), so every player sees the same quest and nothing here is
## authoritative. Built by Main when the match is a scenario.

const PANEL_BG: Color = UiStyle.SURFACE
const PANEL_BORDER: Color = UiStyle.LINE_STRONG
const TRACKER_WIDTH: float = 282.0
const TRACKER_MARGIN: float = 24.0
const DIALOGUE_WIDTH: float = 1020.0
## The dialogue band's distance up from the bottom of the screen. The UI is
## laid out in the project's stretch space (648 tall, whatever the window is),
## where the command bar and its frame take roughly the bottom 200.
## Above the selection panel, whose top edge is 248 up from the bottom (224
## tall plus its 24 margin). The open centre of the HUD is exactly the space
## this box was meant to land in -- at bottom 104 it sat on top of the
## command grid instead.
## The band must be TALLER than the box it centres, or the box overflows it at
## both ends and reaches the command panel anyway -- a CenterContainer does
## not clip. 220 clears the box (about 200 with its portrait) and the bottom
## sits 268 up, leaving the selection panel at 248 a clear margin.
const DIALOGUE_BAND_TOP: float = 488.0
const DIALOGUE_BAND_BOTTOM: float = 268.0
const BRIEFING_WIDTH: float = 720.0
## How long a finished objective stays on the tracker before dropping off.
const COMPLETED_LINGER: float = 6.0
const ACTIVE_COLOR: Color = UiStyle.INK
const COMPLETE_COLOR: Color = UiStyle.GOOD
const FAILED_COLOR: Color = UiStyle.BAD
const OPTIONAL_COLOR: Color = UiStyle.DIM
const HIGHLIGHT_COLOR: Color = UiStyle.ACCENT
## How far a highlight's outline sits outside what it is pointing at.
const HIGHLIGHT_PADDING: float = 6.7
## The crop itself (how much of the figure) is UnitPortrait.HEAD_FRACTION.
const PORTRAIT_SIZE: float = 96.0

## The last line has been read and no briefing is up — the screen is the
## player's again. Main holds the end-of-match panel back until this.
signal presentation_finished

var main: Main
var runner: QuestRunner

var _tracker_panel: PanelContainer
var _tracker_box: VBoxContainer
## step index -> the time it finished, for the linger before it drops off.
var _completed_at: Dictionary = {}

var _dialogue_panel: PanelContainer
var _dialogue_portrait: TextureRect
var _dialogue_speaker: Label
var _dialogue_text: Label
var _queue: Array[Dictionary] = []
## A line is on show (or waiting behind a briefing). The panel's own visibility
## follows this, minus whatever a briefing is covering up. Lines never time
## out: they stay until the player presses Continue, so nothing is missed while
## you are looking at the battlefield.
var _showing_line: bool = false
## Dims the battlefield behind an open briefing and swallows clicks, so a
## briefing in multiplayer (where nothing pauses) can't be played through.
var _briefing_shade: ColorRect

var _briefing_panel: PanelContainer
var _briefing_title: Label
var _briefing_text: Label

## marker id -> the ring in the world.
var _markers: Dictionary = {}
## element name -> {frame: Panel, target: Control} for the HUD highlights.
var _highlights: Dictionary = {}
## Set while this UI is the reason the game is paused, so closing it doesn't
## un-pause a pause menu the player opened themselves.
var _paused_by_us: bool = false

## Cropped heads, keyed by unit scene path.

func _ready() -> void:
	name = "QuestUi"
	## Dialogue and briefings can hold a single-player game, so this has to keep
	## running (and keep taking input) while the tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_tracker()
	_build_dialogue()
	_build_briefing()
	runner.changed.connect(_refresh_tracker)
	runner.presentation.connect(_on_presentation)
	_refresh_tracker()
	## The mission's own briefing, before anything else happens.
	if main.scenario != null and main.scenario.briefing_text.strip_edges() != "":
		_show_briefing(main.scenario.briefing_title, main.scenario.briefing_text)

## The same brass panel every other module uses, with the inset the quest
## panels want. Corner caps are added per panel by _add_caps().
func _panel_style() -> StyleBoxFlat:
	var style := UiStyle.panel_box()
	style.content_margin_left = UiStyle.SPACE_L
	style.content_margin_right = UiStyle.SPACE_L
	style.content_margin_top = UiStyle.SPACE_M
	style.content_margin_bottom = UiStyle.SPACE_M
	return style

func _add_caps(panel: Control) -> void:
	panel.add_child(UiCaps.new())

## --- Tracker ---

func _build_tracker() -> void:
	_tracker_panel = PanelContainer.new()
	_tracker_panel.add_theme_stylebox_override("panel", _panel_style())
	_tracker_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tracker_panel.custom_minimum_size = Vector2(TRACKER_WIDTH, 0.0)
	add_child(_tracker_panel)
	## Pinned to the top-right corner by hand rather than through a preset:
	## PRESET_MODE_MINSIZE measures the panel before it has any content and
	## leaves it hanging off the edge of the screen. Anchors both sides to the
	## right so it stays there at any window size; the height grows with the
	## objectives, since a Control never shrinks below its content.
	_tracker_panel.anchor_left = 1.0
	_tracker_panel.anchor_right = 1.0
	_tracker_panel.anchor_top = 0.0
	_tracker_panel.anchor_bottom = 0.0
	_tracker_panel.offset_left = -(TRACKER_WIDTH + TRACKER_MARGIN)
	_tracker_panel.offset_right = -TRACKER_MARGIN
	_tracker_panel.offset_top = TRACKER_MARGIN
	_tracker_panel.offset_bottom = TRACKER_MARGIN
	_add_caps(_tracker_panel)
	_tracker_box = VBoxContainer.new()
	_tracker_box.add_theme_constant_override("separation", 7)
	_tracker_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tracker_panel.add_child(_tracker_box)

func _refresh_tracker() -> void:
	for child in _tracker_box.get_children():
		_tracker_box.remove_child(child)
		child.queue_free()
	var shown := 0
	for i in runner.steps.size():
		var step: QuestStep = runner.steps[i]
		var state: int = runner.states.get(i, QuestStep.State.LOCKED)
		if step.hidden or state == QuestStep.State.LOCKED:
			continue
		if state == QuestStep.State.COMPLETE or state == QuestStep.State.FAILED:
			if not _completed_at.has(i):
				_completed_at[i] = runner.time
			if runner.time - float(_completed_at[i]) > COMPLETED_LINGER:
				continue
		_tracker_box.add_child(_make_tracker_line(step, state, runner.progress.get(i, PackedInt32Array())))
		shown += 1
	_tracker_panel.visible = shown > 0

func _make_tracker_line(step: QuestStep, state: int, pairs: PackedInt32Array) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(TRACKER_WIDTH - 40.0, 0.0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mark := "-"
	var color := ACTIVE_COLOR if not step.optional else OPTIONAL_COLOR
	match state:
		QuestStep.State.COMPLETE:
			mark = "x"
			color = COMPLETE_COLOR
		QuestStep.State.FAILED:
			mark = "!"
			color = FAILED_COLOR
	var text := "%s %s" % [mark, step.title]
	## Counts only while the objective is still open, and only where counting
	## means anything (a one-of-one condition just reads as done or not).
	if state == QuestStep.State.ACTIVE:
		var counts: Array[String] = []
		for i in range(0, pairs.size() - 1, 2):
			if pairs[i + 1] > 1:
				counts.append("%d/%d" % [pairs[i], pairs[i + 1]])
		if not counts.is_empty():
			text += "  " + " ".join(counts)
	label.text = text
	label.add_theme_color_override("font_color", color)
	return label

## --- Dialogue ---

func _build_dialogue() -> void:
	## A band across the bottom of the screen, sitting above the command bar,
	## with the box centred in it — so it stays put at any window size.
	var band := CenterContainer.new()
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(band)
	band.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	band.offset_top = -DIALOGUE_BAND_TOP
	band.offset_bottom = -DIALOGUE_BAND_BOTTOM

	_dialogue_panel = PanelContainer.new()
	_dialogue_panel.add_theme_stylebox_override("panel", _panel_style())
	_dialogue_panel.visible = false
	## Stops clicks rather than ignoring them: the Continue button has to be
	## clickable, and a click on the box must not also order units about.
	_dialogue_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_dialogue_panel.custom_minimum_size = Vector2(DIALOGUE_WIDTH, 0.0)
	band.add_child(_dialogue_panel)
	_add_caps(_dialogue_panel)

	## The portrait and words sit in a row; the button goes under the whole box
	## rather than inside that row, or it centres on the words alone and reads
	## as off-centre by half the portrait's width.
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 13)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialogue_panel.add_child(box)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)

	## A recessed well with the face in it, like every other portrait in the UI.
	var portrait_frame := Panel.new()
	portrait_frame.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	portrait_frame.add_theme_stylebox_override("panel",
			UiStyle.slot_box(UiStyle.LINE_STRONG))
	portrait_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(portrait_frame)

	_dialogue_portrait = TextureRect.new()
	_dialogue_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_dialogue_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	## Pixel art at an integer multiple of its 32px source, nearest-neighbour.
	_dialogue_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_dialogue_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialogue_portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait_frame.add_child(_dialogue_portrait)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(column)

	_dialogue_speaker = Label.new()
	_dialogue_speaker.theme_type_variation = &"TitleLabel"
	_dialogue_speaker.add_theme_font_size_override("font_size", UiStyle.SIZE_VALUE)
	_dialogue_speaker.add_theme_color_override("font_color", UiStyle.ACCENT)
	_dialogue_speaker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_dialogue_speaker)

	var speaker_rule := SectionRule.new()
	speaker_rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(speaker_rule)

	## Dialogue is the only prose in the game, so it is the only place Spectral
	## is used.
	_dialogue_text = Label.new()
	_dialogue_text.theme_type_variation = &"ProseLabel"
	_dialogue_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	## Autowrap measures at its narrowest width, so it needs an explicit one.
	_dialogue_text.custom_minimum_size = Vector2(820.0, 0.0)
	_dialogue_text.max_lines_visible = 3
	_dialogue_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_dialogue_text)

	## Bottom-right rather than centred under the whole box: it is an
	## affordance to move on, not the point of the panel.
	var continue_row := HBoxContainer.new()
	continue_row.alignment = BoxContainer.ALIGNMENT_END
	continue_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(continue_row)
	var continue_button := UiButton.new()
	continue_button.text = "Continue"
	continue_button.pressed.connect(_next_line)
	continue_row.add_child(continue_button)

func _queue_line(payload: Dictionary) -> void:
	_queue.append(payload)
	## A briefing owns the screen while it is up; its lines wait their turn
	## rather than being read out underneath it.
	if not _showing_line and not _briefing_panel.visible:
		_next_line()

func _next_line() -> void:
	if _queue.is_empty():
		_showing_line = false
		_dialogue_panel.visible = false
		_set_paused(false)
		_update_hold()
		if not _briefing_panel.visible:
			presentation_finished.emit()
		return
	_showing_line = true
	var line: Dictionary = _queue.pop_front()
	_dialogue_speaker.text = String(line.get("speaker", ""))
	_dialogue_speaker.visible = _dialogue_speaker.text != ""
	_dialogue_text.text = String(line.get("text", ""))
	_dialogue_portrait.texture = _portrait_for(line)
	_dialogue_portrait.visible = _dialogue_portrait.texture != null
	_dialogue_panel.visible = not _briefing_panel.visible
	## Holding the whole game for a line is a single-player thing: in
	## multiplayer one player reading must not stop everyone else's match. The
	## line itself waits for Continue either way.
	_set_paused(bool(line.get("pause", false)) and Network.is_single_player())
	_update_hold()

## The quest stops advancing while the host is reading, so the step a line
## announces cannot complete and start talking over it. Only the host's own
## screen counts — in co-op the mission must not stall on each player's
## reading speed.
func _update_hold() -> void:
	if multiplayer.is_server():
		runner.presentation_hold = _showing_line or _briefing_panel.visible

func _portrait_for(line: Dictionary) -> Texture2D:
	var art_path := String(line.get("portrait", ""))
	if art_path != "" and ResourceLoader.exists(art_path):
		return load(art_path) as Texture2D
	var scene_path := String(line.get("speaker_scene", ""))
	if scene_path != "":
		return UnitPortrait.of_scene(scene_path)
	return null

## --- Briefing ---

func _build_briefing() -> void:
	_briefing_shade = ColorRect.new()
	## Warm rather than neutral black, matching the menus' scrim.
	_briefing_shade.color = Color(0.055, 0.042, 0.032, 0.72)
	_briefing_shade.visible = false
	_briefing_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_briefing_shade)
	_briefing_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	## Centred on whatever the window happens to be.
	var centre := CenterContainer.new()
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_briefing_panel = PanelContainer.new()
	_briefing_panel.add_theme_stylebox_override("panel", _panel_style())
	_briefing_panel.visible = false
	_briefing_panel.custom_minimum_size = Vector2(BRIEFING_WIDTH, 0.0)
	_briefing_panel.theme_type_variation = &"ModalPanel"
	centre.add_child(_briefing_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UiStyle.SPACE_M)
	_briefing_panel.add_child(column)
	_add_caps(_briefing_panel)

	_briefing_title = Label.new()
	_briefing_title.theme_type_variation = &"TitleLabel"
	_briefing_title.add_theme_font_size_override("font_size", UiStyle.SIZE_MODAL_TITLE)
	column.add_child(_briefing_title)

	var title_rule := SectionRule.new()
	title_rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(title_rule)

	_briefing_text = Label.new()
	_briefing_text.theme_type_variation = &"ProseLabel"
	_briefing_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_briefing_text.custom_minimum_size = Vector2(BRIEFING_WIDTH - 80.0, 0.0)
	## Capped, so a long brief cannot grow the panel past the screen.
	_briefing_text.max_lines_visible = 10
	column.add_child(_briefing_text)

	## Right-aligned and filled, like the primary action on every other modal.
	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(button_row)
	var button := UiButton.new()
	button.text = "Continue"
	button.primary = true
	button.pressed.connect(_close_briefing)
	button_row.add_child(button)

func _show_briefing(title: String, text: String) -> void:
	_briefing_title.text = title
	_briefing_title.visible = title != ""
	_briefing_text.text = text
	_briefing_panel.visible = true
	_briefing_shade.visible = true
	## Whatever was being said goes quiet behind it and picks up afterwards.
	_dialogue_panel.visible = false
	_set_paused(Network.is_single_player())
	_update_hold()

func _close_briefing() -> void:
	_briefing_panel.visible = false
	_briefing_shade.visible = false
	_set_paused(false)
	## Anything said while the briefing was up has been waiting.
	if not _showing_line and not _queue.is_empty():
		_next_line()
	elif _showing_line:
		_dialogue_panel.visible = true
	_update_hold()
	if not is_presenting():
		presentation_finished.emit()

## A line or a briefing is on screen (or queued behind one).
func is_presenting() -> bool:
	return _showing_line or _briefing_panel.visible or not _queue.is_empty()

## --- Presentation payloads ---

func _on_presentation(payload: Dictionary) -> void:
	match String(payload.get("kind", "")):
		"dialogue":
			_queue_line(payload)
		"briefing":
			_show_briefing(String(payload.get("title", "")), String(payload.get("text", "")))
		"camera":
			main.focus_camera_on(payload.get("position", Vector3.ZERO))
		"ping":
			if bool(payload.get("hostile", false)):
				main.minimap.show_attack_ping(payload.get("position", Vector3.ZERO))
			else:
				main.minimap.show_ping(payload.get("position", Vector3.ZERO))
		"reveal":
			main.fog_of_war.add_reveal(
				payload.get("position", Vector3.ZERO),
				float(payload.get("radius", 12.0)),
				float(payload.get("seconds", 0.0)))
		"marker":
			_set_marker(String(payload.get("id", "default")),
					payload.get("position", Vector3.ZERO),
					float(payload.get("radius", 3.0)),
					bool(payload.get("show", true)))
		"highlight":
			_set_highlight(String(payload.get("element", "")), bool(payload.get("show", true)))

## --- HUD highlights ---

## The HUD pieces a tutorial can point at. Kept here so a mission names a part
## of the screen rather than a path into main.tscn.
func _highlight_target(element_name: String) -> Control:
	match element_name:
		"minimap":
			return main.get_node_or_null(^"UI/BottomBar/MinimapFrame")
		"action_panel":
			return main.get_node_or_null(^"UI/BottomBar/ActionPanel")
		"info_panel":
			return main.get_node_or_null(^"UI/BottomBar/InfoPanel")
		"idle_button":
			return main.get_node_or_null(^"UI/BottomBar/UtilityButtons/IdleButton")
		"resources":
			return main.get_node_or_null(^"UI/ResourceLabel")
		"research_button":
			return main.power_bar.get_node_or_null(^"ResearchButton") if main.power_bar != null else null
		"quest_tracker":
			return _tracker_panel
	return null

## A pulsing outline laid over the element, following it each frame rather than
## copying its rect once — the bottom bar is laid out at whatever the window
## size is, and panels move as the selection changes.
func _set_highlight(element_name: String, shown: bool) -> void:
	if _highlights.has(element_name):
		var existing: Control = _highlights[element_name].frame
		if is_instance_valid(existing):
			existing.queue_free()
		_highlights.erase(element_name)
	if not shown:
		return
	var target := _highlight_target(element_name)
	if target == null:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = HIGHLIGHT_COLOR
	style.set_border_width_all(3)
	style.set_corner_radius_all(4)
	var frame := Panel.new()
	frame.add_theme_stylebox_override("panel", style)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	_highlights[element_name] = {frame = frame, target = target}

## --- World markers ---

func _set_marker(id: String, world_pos: Vector3, radius: float, shown: bool) -> void:
	if _markers.has(id):
		var existing: Node3D = _markers[id]
		if is_instance_valid(existing):
			existing.queue_free()
		_markers.erase(id)
	if not shown:
		return
	var ring := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = maxf(radius - 0.35, 0.1)
	mesh.outer_radius = radius
	ring.mesh = mesh
	var ring_material := GroundRingMaterial.build(PANEL_BORDER)
	ring.material_override = ring_material
	## Depth-tested (with a grass bias), so buildings and trees stand in front of it — but the
	## ground inside the ring is not flat, so the band is stretched tall rather
	## than lying on it: rises in the terrain sink into it instead of hiding
	## it. From above it reads as the same thin ring.
	ring.scale = Vector3(1.0, 4.0, 1.0)
	var ground: Vector3 = world_pos
	var nav_map: RID = main.get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(nav_map) > 0:
		ground.y = NavigationServer3D.map_get_closest_point(nav_map, world_pos).y
	ring.position = ground + Vector3(0.0, 0.1, 0.0)
	main.add_child(ring)
	_markers[id] = ring

## --- Per-frame ---

func _process(delta: float) -> void:
	## Completed objectives drop off the tracker a few seconds after they
	## finish, which only the tracker itself is watching for.
	if not _completed_at.is_empty():
		for i in _completed_at:
			if runner.time - float(_completed_at[i]) <= COMPLETED_LINGER + delta \
					and runner.time - float(_completed_at[i]) > COMPLETED_LINGER:
				_refresh_tracker()
				break
	var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 1000.0 * TAU)
	for id in _markers:
		var ring: Node3D = _markers[id]
		if is_instance_valid(ring):
			GroundRingMaterial.set_alpha(pulse, (ring as MeshInstance3D).material_override)
	for element_name in _highlights:
		var entry: Dictionary = _highlights[element_name]
		var frame: Control = entry.frame
		var target: Control = entry.target
		if not is_instance_valid(frame) or not is_instance_valid(target):
			continue
		var rect := target.get_global_rect()
		frame.global_position = rect.position - Vector2.ONE * HIGHLIGHT_PADDING
		frame.size = rect.size + Vector2.ONE * HIGHLIGHT_PADDING * 2.0
		frame.visible = target.visible
		frame.modulate = Color(1, 1, 1, pulse)

## Lines are moved on by the Continue button alone. Deliberately not by any
## click or key: those are how the player commands their army, and a line would
## be gone before it was read.

## Single player only, and only ever undoing our own pause.
func _set_paused(paused: bool) -> void:
	if paused == _paused_by_us:
		return
	if paused and not Network.is_single_player():
		return
	_paused_by_us = paused
	get_tree().paused = paused
