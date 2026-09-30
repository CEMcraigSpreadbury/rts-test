extends Control
## Studio logo splash: the wordmark pops in, a giant keep crashes down on top of
## it (squash, dust, shake), then shrinks with a wobble to its "little" size and
## does a small hop before the logo fades out and we swap to the main menu. The
## menu loads on a background thread while the logo is up so the hand-off
## doesn't hitch. Any key or click skips straight to the fade-out.

const MAIN_MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"
const LEAD_IN: float = 0.4
const TEXT_POP: float = 0.45
const PRE_DROP: float = 0.3
const DROP: float = 0.42
const DROP_TILT: float = -0.12
const BIG: float = 2.0
const SETTLE: float = 0.4
const SHRINK: float = 0.75
const HOP_HEIGHT: float = 28.0
const HOLD: float = 1.3
const FADE_OUT: float = 1.0
const TAIL: float = 0.3

const SHAKE_START: float = 14.0
const SHAKE_DECAY: float = 45.0
const DUST_COUNT: int = 16
const DUST_COLOR: Color = Color(0.96, 0.93, 0.85)

@onready var _content: Control = $Content
@onready var _castle: TextureRect = $Content/Castle
@onready var _text: TextureRect = $Content/Text
@onready var _dust: Control = $Content/Dust

var _tween: Tween
var _skipping: bool = false
var _shake: float = 0.0
## Each puff: [position, velocity, start_radius, age, life]
var _puffs: Array = []

func _ready() -> void:
	ResourceLoader.load_threaded_request(MAIN_MENU_SCENE_PATH)
	_castle.pivot_offset = Vector2(_castle.size.x * 0.5, _castle.size.y)
	_text.pivot_offset = _text.size * 0.5
	_dust.draw.connect(_draw_dust)

	var rest_y: float = _castle.position.y
	_castle.scale = Vector2.ONE * BIG
	_castle.position.y = rest_y - get_viewport_rect().size.y
	_castle.rotation = DROP_TILT
	_text.modulate.a = 0.0
	_text.scale = Vector2.ONE * 0.6

	_tween = create_tween()
	_tween.tween_interval(LEAD_IN)
	# Wordmark pops in.
	_tween.tween_property(_text, "modulate:a", 1.0, TEXT_POP * 0.5)
	_tween.parallel().tween_property(_text, "scale", Vector2.ONE, TEXT_POP) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_interval(PRE_DROP)
	# Giant keep drops in from above, straightening as it falls.
	_tween.tween_property(_castle, "position:y", rest_y, DROP) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_property(_castle, "rotation", 0.0, DROP) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tween.tween_callback(_on_land)
	# Squash on impact, stretch, settle.
	_tween.tween_property(_castle, "scale", Vector2(BIG * 1.3, BIG * 0.7), 0.07) \
			.set_ease(Tween.EASE_OUT)
	_tween.tween_property(_castle, "scale", Vector2(BIG * 0.9, BIG * 1.12), 0.12) \
			.set_trans(Tween.TRANS_SINE)
	_tween.tween_property(_castle, "scale", Vector2.ONE * BIG, 0.18) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_interval(SETTLE)
	# A proud little swell... then it shrinks down to size with a wobble.
	_tween.tween_property(_castle, "scale", Vector2.ONE * BIG * 1.08, 0.18) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_castle, "scale", Vector2.ONE, SHRINK) \
			.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	# Tiny hop to say "ta-da".
	_tween.tween_property(_castle, "position:y", rest_y - HOP_HEIGHT, 0.16) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_castle, "position:y", rest_y, 0.14) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_property(_castle, "scale", Vector2(1.15, 0.85), 0.06) \
			.set_ease(Tween.EASE_OUT)
	_tween.tween_property(_castle, "scale", Vector2.ONE, 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_interval(HOLD)
	_tween.tween_property(_content, "modulate:a", 0.0, FADE_OUT)
	_tween.tween_interval(TAIL)
	_tween.finished.connect(_go_to_menu)

func _process(delta: float) -> void:
	if _shake > 0.0:
		_shake = maxf(_shake - SHAKE_DECAY * delta, 0.0)
		_content.position = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake
	if _puffs.is_empty():
		return
	for i in range(_puffs.size() - 1, -1, -1):
		var p: Array = _puffs[i]
		p[3] += delta
		if p[3] >= p[4]:
			_puffs.remove_at(i)
			continue
		p[0] += p[1] * delta
		p[1] *= exp(-3.0 * delta)
	_dust.queue_redraw()

func _on_land() -> void:
	_shake = SHAKE_START
	# Wordmark gets bumped by the impact.
	var bump := create_tween()
	bump.tween_property(_text, "scale", Vector2(1.06, 0.88), 0.06).set_ease(Tween.EASE_OUT)
	bump.tween_property(_text, "scale", Vector2.ONE, 0.35) \
			.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	# Dust kicks out from both sides of the base.
	var base := Vector2(_castle.position.x + _castle.size.x * 0.5, _castle.position.y + _castle.size.y)
	var half_width: float = _castle.size.x * 0.5 * BIG
	for i in DUST_COUNT:
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var pos := base + Vector2(side * half_width * randf_range(0.6, 1.0), randf_range(-12.0, 4.0))
		var vel := Vector2(side * randf_range(250.0, 700.0), randf_range(-160.0, -20.0))
		_puffs.append([pos, vel, randf_range(12.0, 30.0), 0.0, randf_range(0.5, 0.9)])

func _draw_dust() -> void:
	for p: Array in _puffs:
		var t: float = p[3] / p[4]
		var radius: float = p[2] * (1.0 + t * 1.5)
		var alpha: float = 0.22 * (1.0 - t) * (1.0 - t)
		# Stacked circles fake a soft falloff.
		for k in 3:
			_dust.draw_circle(p[0], radius * (1.0 - k * 0.3), Color(DUST_COLOR, alpha))

func _unhandled_input(event: InputEvent) -> void:
	if _skipping:
		return
	var pressed: bool = (event is InputEventKey or event is InputEventMouseButton \
			or event is InputEventJoypadButton) and event.is_pressed()
	if not pressed:
		return
	_skipping = true
	get_viewport().set_input_as_handled()
	_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_content, "modulate:a", 0.0, FADE_OUT * 0.4 * _content.modulate.a)
	_tween.finished.connect(_go_to_menu)

func _go_to_menu() -> void:
	var scene := ResourceLoader.load_threaded_get(MAIN_MENU_SCENE_PATH) as PackedScene
	SceneLoader.change_scene_from_black(scene)
