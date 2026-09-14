class_name UnitsInZoneCondition
extends QuestCondition
## "Get 5 soldiers to the bridge", or "get the envoy to the grove" when
## `entity_name` names one particular placed unit.

## A ScenarioZone's node name.
@export var zone_name: StringName = &""
## How many of the team's units have to be standing in it.
@export var count: int = 1
## Unit.display_name to require, or empty for any of them.
@export var unit_name: String = ""
## When set, only this scenario-placed unit counts (see Main.scenario_entities)
## and `count` is ignored.
@export var entity_name: String = ""

func progress(runner) -> Vector2i:
	var area: ScenarioZone = runner.zone(zone_name)
	if area == null:
		return Vector2i(0, 1)
	if entity_name != "":
		var entity = runner.main.scenario_entities.get(entity_name, null)
		var there: bool = is_instance_valid(entity) and entity is Unit \
				and entity.status_activity != Unit.Activity.DEAD \
				and area.contains(entity.global_position)
		return Vector2i(1 if there else 0, 1)
	var inside := 0
	for unit in runner.team_units():
		if unit_name != "" and unit.display_name != unit_name:
			continue
		if area.contains(unit.global_position):
			inside += 1
	return Vector2i(inside, maxi(count, 1))
