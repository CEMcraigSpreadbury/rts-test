class_name QuestAction
extends Resource
## Something a quest step does — when it starts, when it is completed, or when
## it fails. Subclasses live in scripts/quests/actions/; adding a kind of
## action means adding one script there.
##
## Actions run on the host only. Anything the other players need to see is sent
## by the runner (QuestRunner.show_to_players), never by an action reaching
## into another peer's UI itself.

func run(_runner) -> void:
	pass
