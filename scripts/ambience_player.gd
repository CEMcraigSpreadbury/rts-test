extends AudioStreamPlayer
## Background ambience: a forest by day, a forest by night, and the rainy take
## on each while a shower lasts (Main.day_night / Main.weather, both already
## the same on every peer), crossfading when either changes. Non-positional
## and local per-peer, same as MusicPlayer.
##
## `ambience_sounds` is only the fallback for a scene without a day/night
## clock (a menu backdrop, say): a random track, then another once it ends.

@export var ambience_sounds: Array[AudioStream] = []
@export var day_loop: AudioStream = preload("res://assets/sfx/Fantasy SFX/BGS Loops/Forest Day/Forest Day.wav")
@export var night_loop: AudioStream = preload("res://assets/sfx/Fantasy SFX/BGS Loops/Forest Night/Forest Night.wav")
@export var day_rain_loop: AudioStream = preload("res://assets/sfx/Fantasy SFX/BGS Loops/Forest Day/Forest Day Rain.wav")
@export var night_rain_loop: AudioStream = preload("res://assets/sfx/Fantasy SFX/BGS Loops/Forest Night/Forest Night Rain.wav")
@export var crossfade_seconds: float = 4.0

const SILENT_DB: float = -60.0
const CHECK_SECONDS: float = 0.5

## The second voice of the crossfade; this node is the first.
var _other: AudioStreamPlayer
## Whichever of the two is (or is fading in as) the current loop.
var _active: AudioStreamPlayer = null
var _full_db: float = 0.0
var _check_timer: float = 0.0
var _fade: Tween

func _ready() -> void:
	_full_db = volume_db
	var main := get_parent() as Main
	if main == null:
		finished.connect(func(): AudioUtils.play_random(self, ambience_sounds))
		AudioUtils.play_random(self, ambience_sounds)
		set_process(false)
		return
	_other = AudioStreamPlayer.new()
	_other.bus = bus
	_other.volume_db = SILENT_DB
	add_child(_other)

func _process(delta: float) -> void:
	_check_timer -= delta
	if _check_timer > 0.0:
		return
	_check_timer = CHECK_SECONDS
	var main := get_parent() as Main
	var night: bool = main.day_night != null and main.day_night.is_night
	var rain: bool = main.weather != null and main.weather.is_raining
	var wanted: AudioStream = (night_rain_loop if rain else night_loop) if night else (day_rain_loop if rain else day_loop)
	if _active != null and _active.stream == wanted:
		return
	var incoming: AudioStreamPlayer = _other if _active == self else self
	var outgoing: AudioStreamPlayer = _active
	_active = incoming
	incoming.stream = wanted
	## Picks up the new loop partway in, so two weathers never line up on the
	## same bar of birdsong.
	var start: float = randf() * maxf(wanted.get_length() - 1.0, 0.0)
	if outgoing == null:
		incoming.volume_db = _full_db
		incoming.play(start)
		return
	incoming.volume_db = SILENT_DB
	incoming.play(start)
	if _fade:
		_fade.kill()
	_fade = create_tween().set_parallel(true)
	_fade.tween_property(incoming, "volume_db", _full_db, crossfade_seconds).set_trans(Tween.TRANS_SINE)
	_fade.tween_property(outgoing, "volume_db", SILENT_DB, crossfade_seconds).set_trans(Tween.TRANS_SINE)
	_fade.chain().tween_callback(outgoing.stop)
