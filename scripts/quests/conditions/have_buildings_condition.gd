class_name HaveBuildingsCondition
extends QuestCondition
## "Build 2 houses" — standing buildings the team owns. Building sites only
## count once they are finished unless `include_unfinished` says otherwise.

## ProductionBuilding.building_name, e.g. "House". Empty counts every building.
@export var building_name: String = ""
@export var count: int = 1
@export var include_unfinished: bool = false

func progress(runner) -> Vector2i:
	var have := 0
	for building in runner.team_buildings():
		if building_name != "" and building.building_name != building_name:
			continue
		if building.is_under_construction and not include_unfinished:
			continue
		have += 1
	return Vector2i(have, maxi(count, 1))
