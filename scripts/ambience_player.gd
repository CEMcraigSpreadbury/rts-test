extends AudioStreamPlayer
## Background ambience: plays a random track, then another random track once
## it ends, indefinitely. Non-positional and local per-peer, same as
## MusicPlayer — not tied to any game state, just a continuous backdrop.

@export var ambience_sounds: Array[AudioStream] = []

func _ready() -> void:
	## Same caveat as MusicPlayer: relies on `finished` firing, so an assigned
	## track with its own loop flag set in its import settings would just
	## play that one track forever instead of shuffling to another.
	finished.connect(_on_finished)
	AudioUtils.play_random(self, ambience_sounds)

func _on_finished() -> void:
	AudioUtils.play_random(self, ambience_sounds)
