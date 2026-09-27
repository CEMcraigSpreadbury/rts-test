class_name GameClock
extends RefCounted
## Match time, in the game's own seconds: it stands still while the game is
## paused and runs faster when it is sped up (Engine.time_scale), unlike
## Time.get_ticks_msec(), which is the wall clock. Everything that times
## gameplay — cooldowns, swings, charges, regeneration — reads this instead,
## so a single-player pause or speed change moves them all together.
##
## Advanced by Main every frame with its (already scaled) delta, and reset
## when a match starts. Each peer keeps its own; only single player ever
## changes the speed, so in multiplayer they run together anyway.

static var _seconds: float = 0.0

static func reset() -> void:
	_seconds = 0.0

static func advance(delta: float) -> void:
	_seconds += delta

static func seconds() -> float:
	return _seconds

static func msec() -> int:
	return int(_seconds * 1000.0)
