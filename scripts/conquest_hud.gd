class_name ConquestHud
extends Control
## Battlefield-style Conquest bar, top-centre of the screen, built from the
## same HUD kit as the bottom bar: a panel_gold backing plate; one stone slot
## per capture point (gold for points you hold) showing its letter over the
## owner's colour, with a strip for a flag that's moving and a pulse while
## contested; and under that one score bar per player — the same
## TextureProgressBar art as the command panel's queue bar (Hud), with a
## neutral fill tinted to the player's colour. The leader's bar shakes once
## they're past NEAR_VICTORY_FRACTION.
##
## Also the Conquest alerts — played locally on every peer off the synced
## objective state (Objective.owner_peer_id/flag_*) and Main.scores, so the
## host never has to send anything extra for them.
##
## Only created in Conquest mode (see Main._ready). Laid out by hand each
## frame rather than with containers, since the shake is a per-bar offset.

const PANEL_TEXTURE: Texture2D = preload("res://assets/ui/HUD/scaled/panel_gold.png")
const SLOT_TEXTURE: Texture2D = preload("res://assets/ui/HUD/elements/square_frame_dark.png")
const SLOT_OWNED_TEXTURE: Texture2D = preload("res://assets/ui/HUD/elements/square_frame_gold_2.png")
const BAR_FRAME_TEXTURE: Texture2D = preload("res://assets/ui/HUD/scaled/bar_frame.png")
## Greyscale copy of bar_fill_green, so tint_progress can make it any team's
## colour.
const BAR_FILL_TEXTURE: Texture2D = preload("res://assets/ui/HUD/scaled/bar_fill_neutral.png")

## Same margins as the bottom bar's panel_gold NinePatchRects.
const PANEL_PATCH_MARGINS: Vector4i = Vector4i(36, 26, 34, 26)
## Content inset from the panel's outer edge — inside the stone pillars.
const PANEL_PADDING: Vector2 = Vector2(30.0, 18.0)
const SLOT_SIZE: float = 36.0
const SLOT_GAP: float = 4.0
## How far the owner-colour fill sits inside the slot's frame.
const SLOT_INSET: float = 6.0
const SLOT_STRIP_HEIGHT: float = 4.0
const SLOT_FONT_SIZE: int = 18
const BAR_WIDTH: float = 280.0
const BAR_HEIGHT: float = 20.0
const BAR_GAP: float = 3.0
const BAR_FONT_SIZE: int = 13
const SECTION_GAP: float = 8.0
const TOP_MARGIN: float = 4.0
const NEAR_VICTORY_FRACTION: float = 0.85
## Shake amplitude in pixels, ramping from the first to the second as the
## leader goes from NEAR_VICTORY_FRACTION to the target itself.
const SHAKE_MIN: float = 1.0
const SHAKE_MAX: float = 4.0
const NEUTRAL_FILL_COLOR: Color = Color(0.0, 0.0, 0.0, 0.0)
const OWNER_FILL_ALPHA: float = 0.7
const INACTIVE_DARKEN: float = 0.6
## A drain on one point sounds once, then stays quiet this long unless it
## stops and starts again.
const UNDER_ATTACK_ALERT_COOLDOWN_MS: int = 8000

var main: Main

var _panel: NinePatchRect
## Objective -> {frame: TextureRect, fill: ColorRect, strip_bg, strip, label}
var _slots: Dictionary = {}
## peer_id -> TextureProgressBar (its Overlay label is a child).
var _bars: Dictionary = {}

## Objective -> last seen owner / flag height, for spotting changes.
var _last_owner: Dictionary = {}
var _last_control: Dictionary = {}
## Objective -> Time.get_ticks_msec() of its last under-attack alert.
var _last_attack_alert_ms: Dictionary = {}
## Enemies already announced as near victory (once each).
var _near_victory_warned: Dictionary = {}
## peer_id -> colour, remembered while they're connected: Main.get_team_tint
## can't resolve a player who has since disconnected on a client.
var _tint_cache: Dictionary = {}

func _ready() -> void:
	name = "ConquestHud"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = NinePatchRect.new()
	_panel.texture = PANEL_TEXTURE
	_panel.patch_margin_left = PANEL_PATCH_MARGINS.x
	_panel.patch_margin_top = PANEL_PATCH_MARGINS.y
	_panel.patch_margin_right = PANEL_PATCH_MARGINS.z
	_panel.patch_margin_bottom = PANEL_PATCH_MARGINS.w
	_panel.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE_FIT
	_panel.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE_FIT
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

func _process(_delta: float) -> void:
	var objectives := _sorted_objectives()
	var peers := _sorted_peers() if main.favour_target > 0 else []
	_sync_nodes(objectives, peers)
	_layout(objectives, peers)
	_check_alerts(objectives)

func _sorted_objectives() -> Array:
	var objectives: Array = get_tree().get_nodes_in_group(&"objectives")
	objectives.sort_custom(func(a, b): return a.letter < b.letter)
	return objectives

## Local player first, then everyone else by peer id — same order on each
## screen apart from "you" leading.
func _sorted_peers() -> Array:
	var me := main.my_peer_id()
	var peers: Array = main.scores.keys()
	peers.sort_custom(func(a, b):
		if a == me or b == me:
			return a == me
		return a < b)
	return peers

func _tint_for(peer_id: int) -> Color:
	if Network.players.has(peer_id) or not _tint_cache.has(peer_id):
		_tint_cache[peer_id] = main.get_team_tint(peer_id)
	return _tint_cache[peer_id]

## --- Building the nodes (only when the set of points/players changes) ---

func _sync_nodes(objectives: Array, peers: Array) -> void:
	for o in objectives:
		if not _slots.has(o):
			_slots[o] = _make_slot(o.letter)
	for peer_id in peers:
		if not _bars.has(peer_id):
			_bars[peer_id] = _make_bar()

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
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(label)
	return {frame = frame, fill = fill, strip_bg = strip_bg, strip = strip, label = label}

## Same construction as Hud._make_progress_bar_with_overlay, so the two read
## as one kit.
func _make_bar() -> TextureProgressBar:
	var bar := TextureProgressBar.new()
	bar.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	bar.max_value = 1.0
	bar.step = 0.0
	bar.texture_under = BAR_FRAME_TEXTURE
	bar.texture_progress = BAR_FILL_TEXTURE
	bar.fill_mode = TextureProgressBar.FILL_LEFT_TO_RIGHT
	bar.nine_patch_stretch = true
	bar.stretch_margin_left = 10
	bar.stretch_margin_right = 10
	bar.stretch_margin_top = 6
	bar.stretch_margin_bottom = 6
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var overlay := Label.new()
	overlay.name = "Overlay"
	overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	overlay.size = bar.size
	overlay.add_theme_font_size_override("font_size", BAR_FONT_SIZE)
	overlay.add_theme_constant_override("outline_size", 4)
	overlay.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(overlay)
	add_child(bar)
	return bar

## --- Per-frame state + layout ---

func _layout(objectives: Array, peers: Array) -> void:
	var slots_width: float = objectives.size() * SLOT_SIZE + maxf(objectives.size() - 1, 0) * SLOT_GAP
	var content_width: float = maxf(slots_width, BAR_WIDTH if not peers.is_empty() else 0.0)
	var content_height: float = SLOT_SIZE
	if not peers.is_empty():
		content_height += SECTION_GAP + peers.size() * BAR_HEIGHT + (peers.size() - 1) * BAR_GAP
	size = Vector2(content_width, content_height) + PANEL_PADDING * 2.0
	position = Vector2((get_viewport_rect().size.x - size.x) * 0.5, TOP_MARGIN)
	_panel.size = size

	var me := main.my_peer_id()
	var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU * 1.5)
	var x: float = PANEL_PADDING.x + (content_width - slots_width) * 0.5
	for o in objectives:
		var slot: Dictionary = _slots[o]
		var frame: TextureRect = slot.frame
		frame.position = Vector2(x, PANEL_PADDING.y)
		frame.texture = SLOT_OWNED_TEXTURE if o.owner_peer_id == me and me > 0 else SLOT_TEXTURE
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

	if peers.is_empty():
		return
	var leader_score := _leader_score()
	var y: float = PANEL_PADDING.y + SLOT_SIZE + SECTION_GAP
	var bar_x: float = PANEL_PADDING.x + (content_width - BAR_WIDTH) * 0.5
	for peer_id in peers:
		var entry: Dictionary = main.scores[peer_id]
		var score: int = entry.score
		var fraction: float = clampf(float(score) / main.favour_target, 0.0, 1.0)
		var offset := Vector2.ZERO
		if entry.active and score == leader_score and fraction >= NEAR_VICTORY_FRACTION:
			var amp: float = lerpf(SHAKE_MIN, SHAKE_MAX, inverse_lerp(NEAR_VICTORY_FRACTION, 1.0, fraction))
			offset = Vector2(randf_range(-amp, amp), randf_range(-amp, amp))
		var bar: TextureProgressBar = _bars[peer_id]
		bar.position = Vector2(bar_x, y) + offset
		bar.value = fraction
		var tint := _tint_for(peer_id)
		bar.tint_progress = tint.darkened(INACTIVE_DARKEN) if not entry.active else tint
		(bar.get_node("Overlay") as Label).text = "%d / %d" % [score, main.favour_target]
		y += BAR_HEIGHT + BAR_GAP

func _leader_score() -> int:
	var best := -1
	for peer_id in main.scores:
		var entry: Dictionary = main.scores[peer_id]
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
		if owner != previous_owner:
			if owner == me:
				_alert(main.on_point_captured_sound_effects)
				main.minimap.show_ping(o.global_position)
			elif previous_owner == me:
				_alert(main.on_point_lost_sound_effects)
				main.minimap.show_attack_ping(o.global_position)
		elif owner == me and o.flag_peer_id == me and o.flag_control < previous_control - 0.0001:
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
	for peer_id in main.scores:
		if peer_id == me or _near_victory_warned.has(peer_id):
			continue
		if main.scores[peer_id].score >= main.favour_target * NEAR_VICTORY_FRACTION:
			_near_victory_warned[peer_id] = true
			_alert(main.on_enemy_near_victory_sound_effects)

func _alert(sounds: Array[AudioStream]) -> void:
	if main.game_over:
		return
	AudioUtils.play_random(main.command_audio_player, sounds)
