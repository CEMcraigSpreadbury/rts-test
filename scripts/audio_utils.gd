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
static func play_random(player, sounds: Array[AudioStream]) -> void:
	if player and not sounds.is_empty():
		player.stream = sounds[randi() % sounds.size()]
		player.play()
