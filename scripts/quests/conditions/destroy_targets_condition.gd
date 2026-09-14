class_name DestroyTargetsCondition
extends QuestCondition
## "Burn the raiders' camp" — every named thing the scenario placed must be
## dead or destroyed. As a fail condition it reads the other way round: the
## step fails the moment the thing it names is gone ("protect the envoy").
##
## Names are the ones authored under the slot (see Main.scenario_entities), not
## node paths — adopting a placed unit renames and reparents it.

@export var target_names: Array[String] = []

func progress(runner) -> Vector2i:
	var gone := 0
	for target_name in target_names:
		## A name the scenario never placed is never counted as destroyed. The
		## other way round, a typo would satisfy the step the moment the
		## mission started — and win it, if this is what ends the mission.
		if not runner.main.scenario_entities.has(target_name):
			continue
		var entity = runner.main.scenario_entities.get(target_name, null)
		if not is_instance_valid(entity):
			gone += 1
		elif entity is Unit and entity.status_activity == Unit.Activity.DEAD:
			gone += 1
		elif entity is ProductionBuilding and entity.is_destroyed:
			gone += 1
	return Vector2i(gone, maxi(target_names.size(), 1))
