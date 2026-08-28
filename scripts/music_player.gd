extends AudioStreamPlayer
## Match background music: one random early-game track to start, then
## alternates mid/end-game tracks forever once the early track ends
## (Early -> Mid -> End -> Mid -> End -> ...). Purely a local, per-peer
## experience — not synced across the network, same as other cosmetic-only
## systems in this project.

enum Phase { EARLY, MID, END }

@export var early_game_music: Array[AudioStream] = []
@export var mid_game_music: Array[AudioStream] = []
@export var end_game_music: Array[AudioStream] = []

var _phase: Phase = Phase.EARLY

func _ready() -> void:
	## Relies on `finished` actually firing to advance phases — an imported
	## stream with its own loop flag set (common for .ogg/.wav) never fires
	## this and would play that one track forever instead of progressing.
	## Make sure loop is off on every assigned track's import settings.
	finished.connect(_on_finished)
	AudioUtils.play_random(self, early_game_music)

func _on_finished() -> void:
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
