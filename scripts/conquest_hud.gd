class_name ConquestHud
extends Control
## Conquest bar, top-centre of the screen, kept to two slim rows so it never
## eats into the battlefield: one slot per capture point (gold frame for points
## your team holds) showing its letter over the owner's colour, with a strip
## for a flag that's moving and a pulse while contested; and under that every
## team's score bar side by side, filling toward the target in that team's
## colour. Allies share one bar, because they win together (see Main.scores). The leader's bar shakes once they're past NEAR_VICTORY_FRACTION.
##
## Also the Conquest alerts — played locally on every peer off the synced
## objective state (Objective.owner_peer_id/flag_*) and Main.scores, so the
## host never has to send anything extra for them.
##
## Only created in Conquest mode (see Main._ready). Laid out by hand each
## frame rather than with containers, since the shake is a per-bar offset.

const SLOT_TEXTURE: Texture2D = preload("res://assets/ui/HUD/elements/square_frame_dark.png")
const SLOT_OWNED_TEXTURE: Texture2D = preload("res://assets/ui/HUD/elements/square_frame_gold_2.png")

const PANEL_BG_COLOR: Color = Color(0.05, 0.05, 0.07, 0.82)
const PANEL_BORDER_COLOR: Color = Color(0.72, 0.56, 0.28)
const PANEL_PADDING: Vector2 = Vector2(8.0, 6.0)
const SLOT_SIZE: float = 28.0
const SLOT_GAP: float = 3.0
## How far the owner-colour fill sits inside the slot's frame.
const SLOT_INSET: float = 4.5
const SLOT_STRIP_HEIGHT: float = 3.0
const SLOT_FONT_SIZE: int = 14
## Bars share the slot row's width between them, but never shrink below this
## (the panel widens instead) so a score still fits inside.
const BAR_MIN_WIDTH: float = 64.0
const BAR_HEIGHT: float = 14.0
const BAR_GAP: float = 4.0
const BAR_FONT_SIZE: int = 11
const BAR_BG_COLOR: Color = Color(0.03, 0.04, 0.08, 0.95)
const SECTION_GAP: float = 4.0
const TOP_MARGIN: float = 4.0
const NEAR_VICTORY_FRACTION: float = 0.85
## Shake amplitude in pixels, ramping from the first to the second as the
## leader goes from NEAR_VICTORY_FRACTION to the target itself.
const SHAKE_MIN: float = 0.5
const SHAKE_MAX: float = 2.0
const NEUTRAL_FILL_COLOR: Color = Color(0.0, 0.0, 0.0, 0.0)
const OWNER_FILL_ALPHA: float = 0.7
const INACTIVE_DARKEN: float = 0.6
## A drain on one point sounds once, then stays quiet this long unless it
## stops and starts again.
const UNDER_ATTACK_ALERT_COOLDOWN_MS: int = 8000

var main: Main

var _panel: Panel
## Objective -> {frame: TextureRect, fill: ColorRect, strip_bg, strip, label}
var _slots: Dictionary = {}
## team -> {bar: ProgressBar, fill: StyleBoxFlat, label: Label}
var _bars: Dictionary = {}

## Objective -> last seen owner / flag height, for spotting changes.
var _last_owner: Dictionary = {}
var _last_control: Dictionary = {}
## Objective -> Time.get_ticks_msec() of its last under-attack alert.
var _last_attack_alert_ms: Dictionary = {}
## Enemy teams already announced as near victory (once each).
var _near_victory_warned: Dictionary = {}

func _ready() -> void:
	name = "ConquestHud"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG_COLOR
	style.border_color = PANEL_BORDER_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	_panel = Panel.new()
	_panel.add_theme_stylebox_override("panel", style)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

func _process(_delta: float) -> void:
	var objectives := _sorted_objectives()
	var teams := _sorted_teams() if main.favour_target > 0 else []
	_sync_nodes(objectives, teams)
	_layout(objectives, teams)
	_check_alerts(objectives)

func _sorted_objectives() -> Array:
	var objectives: Array = get_tree().get_nodes_in_group(&"objectives")
	objectives.sort_custom(func(a, b): return a.letter < b.letter)
	return objectives

## Your own team first, then the rest by team id — same order on each screen
## apart from yours leading.
func _sorted_teams() -> Array:
	var mine := Teams.team_of(main.my_peer_id())
	var teams: Array = main.scores.keys()
	teams.sort_custom(func(a, b):
		if a == mine or b == mine:
			return a == mine
		return a < b)
	return teams

## The colour comes with the score snapshot, so a team whose players have all
## disconnected still draws in its own colour on a client.
func _tint_for(team: int) -> Color:
	return main.scores.get(team, {}).get("tint", Teams.team_color(team))

## --- Building the nodes (only when the set of points/players changes) ---

func _sync_nodes(objectives: Array, teams: Array) -> void:
	for o in objectives:
		if not _slots.has(o):
			_slots[o] = _make_slot(o.letter)
	for team in teams:
		if not _bars.has(team):
			_bars[team] = _make_bar()

func _make_slot(letter: String) -> Dictionary:
	var frame := TextureRect.new()
	frame.texture = SLOT_TEXTURE
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.size = Vector2(SLOT_SIZE, SLOT_SIZE)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	## The slot art is opaque all the way through, so the owner colour goes
	## over its interior, translucent (see OWNER_FILL_ALPHA) so the stone
	## still shows through as a tint.
	var fill := ColorRect.new()
	fill.position = Vector2(SLOT_INSET, SLOT_INSET)
	fill.size = Vector2(SLOT_SIZE - SLOT_INSET * 2.0, SLOT_SIZE - SLOT_INSET * 2.0)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(fill)
	var strip_bg := ColorRect.new()
	strip_bg.color = Color(0, 0, 0, 0.75)
	strip_bg.position = Vector2(SLOT_INSET, SLOT_SIZE - SLOT_INSET - SLOT_STRIP_HEIGHT)
	strip_bg.size = Vector2(SLOT_SIZE - SLOT_INSET * 2.0, SLOT_STRIP_HEIGHT)
	strip_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(strip_bg)
	var strip := ColorRect.new()
	strip.position = strip_bg.position
	strip.size = strip_bg.size
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(strip)
	var label := Label.new()
	label.text = letter
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = Vector2(SLOT_SIZE, SLOT_SIZE - 2.0)
	label.add_theme_font_size_override("font_size", SLOT_FONT_SIZE)
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(label)
	return {frame = frame, fill = fill, strip_bg = strip_bg, strip = strip, label = label}

## Flat styleboxes rather than the bottom bar's framed bar art, whose frame
## is too thick to leave any fill visible at this height.
func _make_bar() -> Dictionary:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.step = 0.0
	bar.size = Vector2(BAR_MIN_WIDTH, BAR_HEIGHT)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := StyleBoxFlat.new()
	background.bg_color = BAR_BG_COLOR
	background.border_color = PANEL_BORDER_COLOR.darkened(0.3)
	background.set_border_width_all(1)
	background.set_corner_radius_all(2)
	var fill := StyleBoxFlat.new()
	fill.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", BAR_FONT_SIZE)
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(label)
	add_child(bar)
	return {bar = bar, fill = fill, label = label}

## --- Per-frame state + layout ---

func _layout(objectives: Array, teams: Array) -> void:
	var slots_width: float = objectives.size() * SLOT_SIZE + maxf(objectives.size() - 1, 0) * SLOT_GAP
	var bars_min_width: float = teams.size() * BAR_MIN_WIDTH + maxf(teams.size() - 1, 0) * BAR_GAP
	var content_width: float = maxf(slots_width, bars_min_width)
	var content_height: float = SLOT_SIZE
	if not teams.is_empty():
		content_height += SECTION_GAP + BAR_HEIGHT
	size = Vector2(content_width, content_height) + PANEL_PADDING * 2.0
	position = Vector2((get_viewport_rect().size.x - size.x) * 0.5, TOP_MARGIN)
	_panel.size = size

	var me := main.my_peer_id()
	var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU * 1.5)
	## A point an ally holds counts as held by your side.
	var x: float = PANEL_PADDING.x + (content_width - slots_width) * 0.5
	for o in objectives:
		var slot: Dictionary = _slots[o]
		var frame: TextureRect = slot.frame
		frame.position = Vector2(x, PANEL_PADDING.y)
		frame.texture = SLOT_OWNED_TEXTURE if o.owner_peer_id > 0 and me > 0 and Teams.is_friendly(me, o.owner_peer_id) else SLOT_TEXTURE
		(slot.fill as ColorRect).color = Color(o.owner_tint(), OWNER_FILL_ALPHA) if o.owner_peer_id > 0 else NEUTRAL_FILL_COLOR
		var moving: bool = not o.is_flag_at_rest()
		(slot.strip_bg as ColorRect).visible = moving
		var strip: ColorRect = slot.strip
		strip.visible = moving
		if moving:
			strip.size.x = (SLOT_SIZE - SLOT_INSET * 2.0) * o.flag_control
			strip.color = o.flag_tint().lightened(0.2)
		## Contested: the whole slot throbs brighter.
		frame.modulate = Color.WHITE.lerp(Color(1.8, 1.8, 1.8), pulse) if o.contested else Color.WHITE
		x += SLOT_SIZE + SLOT_GAP

	if teams.is_empty():
		return
	var leader_score := _leader_score()
	var bar_width: float = (content_width - (teams.size() - 1) * BAR_GAP) / teams.size()
	var bar_x: float = PANEL_PADDING.x
	var y: float = PANEL_PADDING.y + SLOT_SIZE + SECTION_GAP
	for team in teams:
		var entry: Dictionary = main.scores[team]
		var score: int = entry.score
		var fraction: float = clampf(float(score) / main.favour_target, 0.0, 1.0)
		var offset := Vector2.ZERO
		if entry.active and score == leader_score and fraction >= NEAR_VICTORY_FRACTION:
			var amp: float = lerpf(SHAKE_MIN, SHAKE_MAX, inverse_lerp(NEAR_VICTORY_FRACTION, 1.0, fraction))
			offset = Vector2(randf_range(-amp, amp), randf_range(-amp, amp))
		var parts: Dictionary = _bars[team]
		var bar: ProgressBar = parts.bar
		bar.size = Vector2(bar_width, BAR_HEIGHT)
		bar.position = Vector2(bar_x, y) + offset
		bar.value = fraction
		var tint := _tint_for(team)
		var fill_color: Color = tint.darkened(INACTIVE_DARKEN) if not entry.active else tint
		var fill: StyleBoxFlat = parts.fill
		if fill.bg_color != fill_color:
			fill.bg_color = fill_color
		var label: Label = parts.label
		label.size = bar.size
		label.text = str(score)
		bar_x += bar_width + BAR_GAP

func _leader_score() -> int:
	var best := -1
	for team in main.scores:
		var entry: Dictionary = main.scores[team]
		if entry.active:
			best = maxi(best, entry.score)
	return best

## --- Alerts ---

func _check_alerts(objectives: Array) -> void:
	var me := main.my_peer_id()
	for o in objectives:
		var owner: int = o.owner_peer_id
		var previous_owner: int = _last_owner.get(o, owner)
		var previous_control: float = _last_control.get(o, o.flag_control)
		## Your side's point, whether you or an ally holds it.
		var ours: bool = owner > 0 and Teams.is_friendly(me, owner)
		var was_ours: bool = previous_owner > 0 and Teams.is_friendly(me, previous_owner)
		if owner != previous_owner:
			if ours and not was_ours:
				_alert(main.on_point_captured_sound_effects)
				main.minimap.show_ping(o.global_position)
			elif was_ours and not ours:
				_alert(main.on_point_lost_sound_effects)
				main.minimap.show_attack_ping(o.global_position)
		elif ours and Teams.is_friendly(me, o.flag_peer_id) and o.flag_control < previous_control - 0.0001:
			var now := Time.get_ticks_msec()
			if now - int(_last_attack_alert_ms.get(o, -UNDER_ATTACK_ALERT_COOLDOWN_MS)) >= UNDER_ATTACK_ALERT_COOLDOWN_MS:
				_alert(main.on_point_under_attack_sound_effects)
				main.minimap.show_attack_ping(o.global_position)
			## Refreshed on every drained frame, so a continuous drain stays
			## at one alert and only a fresh attack after a lull sounds again.
			_last_attack_alert_ms[o] = now
		_last_owner[o] = owner
		_last_control[o] = o.flag_control

	if main.favour_target <= 0:
		return
	var my_team := Teams.team_of(me)
	for team in main.scores:
		if team == my_team or _near_victory_warned.has(team):
			continue
		if main.scores[team].score >= main.favour_target * NEAR_VICTORY_FRACTION:
			_near_victory_warned[team] = true
			_alert(main.on_enemy_near_victory_sound_effects)

func _alert(sounds: Array[AudioStream]) -> void:
	if main.game_over:
		return
	AudioUtils.play_random(main.command_audio_player, sounds)
