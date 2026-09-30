extends AudioStreamPlayer
## The main menu's music: fades in from silence, then plays `tracks` one after
## another, first to last and round again. SceneLoader fades it out (via the
## "music" group) when the menu gives way to a match or the lobby.

@export var tracks: Array[AudioStream] = []

const FADE_IN_SECONDS: float = 4.0
const SILENT_DB: float = -40.0

var _next: int = 0

func _ready() -> void:
	add_to_group(&"music")
	if tracks.is_empty():
		return
	finished.connect(_play_next)
	var full_db := volume_db
	volume_db = SILENT_DB
	_play_next()
	create_tween().tween_property(self, "volume_db", full_db, FADE_IN_SECONDS) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _play_next() -> void:
	stream = tracks[_next]
	_next = (_next + 1) % tracks.size()
	play()
