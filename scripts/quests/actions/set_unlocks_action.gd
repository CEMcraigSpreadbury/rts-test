class_name SetUnlocksAction
extends QuestAction
## Opens up (or takes away) what a side may build, train and research part-way
## through a mission — "you may now build Barracks".
##
## An allowed list that is empty means "everything", so the first unlock a
## scenario hands out has to be an allowed list that already names what the
## side could build before it.

## Which side; -1 means every player on the quest's own team.
@export var slot_index: int = -1
@export var unlock_buildings: Array[String] = []
@export var lock_buildings: Array[String] = []
@export var unlock_items: Array[String] = []
@export var lock_items: Array[String] = []
## New research tier cap; -2 leaves it alone (-1 = no limit, 0 = none at all).
@export var research_tier_cap: int = -2
## Parts of the HUD to hand over or take away — "research", "build",
## "formations", "control_groups". This is how a tutorial introduces the game
## one piece at a time.
@export var unlock_hud: Array[String] = []
@export var lock_hud: Array[String] = []

func run(runner) -> void:
	var peers: Array[int] = []
	if slot_index < 0:
		peers = runner.player_peers()
	else:
		var peer_id: int = runner.peer_for_slot(slot_index)
		if peer_id > 0:
			peers.append(peer_id)
	for peer_id in peers:
		runner.set_unlocks(peer_id, unlock_buildings, lock_buildings, unlock_items, lock_items,
				research_tier_cap, unlock_hud, lock_hud)
