class_name AudioUtils
extends RefCounted
## Shared by Unit, ProductionBuilding, Gatherable, and main.gd's own command
## sound effects. No common node base covers all of these (a CharacterBody3D,
## a StaticBody3D "building"/"resource", and Main's flat UI player), so this
## lives as a static helper — same reasoning as CombatUtils.

## Untyped player parameter is deliberate (duck-typed): AudioStreamPlayer and
## AudioStreamPlayer3D both expose .stream/.play() but share no common base
## besides Node, so a statically-typed parameter would only work with one of
## them. See BuildingType.get_costs() for the same untyped-for-duck-typing pattern.
## Never plays the same clip twice in a row while a list has more than one
## entry — with a short list, a plain random pick repeats often enough that it
## reads as "the sound is broken" rather than as chance. The player's own
## current stream *is* the memory of what it last played, so no extra
## bookkeeping is needed; a player shared between several lists (a unit's
## command_audio_player does select *and* order lines) simply finds no match
## to exclude and picks freely.
static func play_random(player, sounds: Array[AudioStream]) -> void:
	if player == null or sounds.is_empty():
		return
	var choices: Array[AudioStream] = sounds
	if sounds.size() > 1:
		choices = []
		for sound in sounds:
			if sound != player.stream:
				choices.append(sound)
		## Every entry being the same stream is the one case that leaves this
		## empty; fall back rather than silently playing nothing.
		if choices.is_empty():
			choices = sounds
	player.stream = choices[randi() % choices.size()]
	player.play()
