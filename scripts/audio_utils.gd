class_name SelectAudio
extends RefCounted
## Shared by Unit, ProductionBuilding, and Gatherable (no common node base
## between a CharacterBody3D, a StaticBody3D "building", and a StaticBody3D
## "resource" beyond Node3D), so this lives as a static helper — same
## reasoning as CombatUtils.

static func play_random(player: AudioStreamPlayer3D, sounds: Array[AudioStream]) -> void:
	if player and not sounds.is_empty():
		player.stream = sounds[randi() % sounds.size()]
		player.play()
