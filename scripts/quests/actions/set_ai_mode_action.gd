class_name SetAiModeAction
extends QuestAction
## Changes what an AI side is doing: the camp that has been sitting quietly
## finally marches, or an attacker is called home to defend.

## Index of the slot in the scenario's Slots list.
@export var slot_index: int = 1
## Normal plays the whole game, Defend never sends a wave out, Attack throws
## its waves at one place (see AiPlayer.Mode).
@export_enum("Normal", "Defend", "Attack") var mode: int = 0
## Attack mode: the zone or marker to send them at. Left empty, they keep
## whatever target they had.
@export var attack_at: StringName = &""

func run(runner) -> void:
	runner.set_ai_mode(slot_index, mode, attack_at)
