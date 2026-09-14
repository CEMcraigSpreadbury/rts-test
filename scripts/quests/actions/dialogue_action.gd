class_name DialogueAction
extends QuestAction
## A line of dialogue, shown to everyone on the player team. Lines queue up, so
## several of these on one step play in order.

@export var speaker: String = ""
@export_multiline var text: String = ""
## Portrait art, when there is any.
@export var portrait: Texture2D = null
## Otherwise the speaker's head is cropped out of this unit's sprite sheet.
@export var speaker_scene: PackedScene = null
## In single player, hold the game while the line is up. Ignored in
## multiplayer, where one person reading must not freeze everyone else. The
## line waits for the player to press Continue either way.
@export var pause_in_single_player: bool = false

func run(runner) -> void:
	runner.show_to_players({
		kind = "dialogue",
		speaker = speaker,
		text = text,
		## Paths rather than the resources themselves: this travels as an RPC.
		portrait = portrait.resource_path if portrait != null else "",
		speaker_scene = speaker_scene.resource_path if speaker_scene != null else "",
		pause = pause_in_single_player,
	})
