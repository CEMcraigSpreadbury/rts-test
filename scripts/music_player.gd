extends AudioStreamPlayer
## Match background music: one random early-game track to start, then
## alternates mid/end-game tracks forever once the early track ends
## (Early -> Mid -> End -> Mid -> End -> ...), with a few minutes of nothing
## but the ambience between tracks. Purely a local, per-peer experience — not
## synced across the network, same as other cosmetic-only systems in this
## project.

enum Phase { EARLY, MID, END }

@export var early_game_music: Array[AudioStream] = []
@export var mid_game_music: Array[AudioStream] = []
@export var end_game_music: Array[AudioStream] = []
## Replaces the cycling once the local player has won (see play_outcome).
@export var victory_music: AudioStream = preload("res://assets/sfx/Music/End/Triumphant March.mp3")

## How long the match music takes to fade out when the result comes in.
const OUTCOME_FADE_SECONDS: float = 1.5
## Silence between tracks, in real seconds whatever the game speed: the same
## few tracks back to back wore thin over an hour, and a track that comes back
## after a stretch of ambience lands as an event rather than wallpaper.
const GAP_SECONDS_MIN: float = 120.0
const GAP_SECONDS_MAX: float = 240.0

var _phase: Phase = Phase.EARLY
var _gap_timer: Timer

func _ready() -> void:
	## Plays on through the pause menu and quest dialogue (both pause the tree).
	process_mode = Node.PROCESS_MODE_ALWAYS
	## SceneLoader fades this out on the way out of the match.
	add_to_group(&"music")
	## Relies on `finished` actually firing to advance phases — an imported
	## stream with its own loop flag set (common for .ogg/.wav) never fires
	## this and would play that one track forever instead of progressing.
	## Make sure loop is off on every assigned track's import settings.
	finished.connect(_on_finished)
	_gap_timer = Timer.new()
	_gap_timer.one_shot = true
	_gap_timer.ignore_time_scale = true
	_gap_timer.timeout.connect(_play_next)
	add_child(_gap_timer)
	AudioUtils.play_random(self, early_game_music)

func _on_finished() -> void:
	_gap_timer.start(randf_range(GAP_SECONDS_MIN, GAP_SECONDS_MAX))

func _play_next() -> void:
	match _phase:
		Phase.EARLY:
			_phase = Phase.MID
			AudioUtils.play_random(self, mid_game_music)
		Phase.MID:
			_phase = Phase.END
			AudioUtils.play_random(self, end_game_music)
		Phase.END:
			_phase = Phase.MID
			AudioUtils.play_random(self, mid_game_music)

## The match is decided: fade whatever is playing out for good and, if given,
## play `stream` once in its place (null leaves silence, e.g. on defeat).
func play_outcome(stream: AudioStream) -> void:
	if finished.is_connected(_on_finished):
		finished.disconnect(_on_finished)
	_gap_timer.stop()
	var match_volume := volume_db
	var fade := create_tween()
	fade.tween_property(self, "volume_db", -40.0, OUTCOME_FADE_SECONDS)
	fade.tween_callback(func():
		stop()
		volume_db = match_volume
		if stream != null:
			self.stream = stream
			play())
