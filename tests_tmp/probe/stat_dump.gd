extends Node
## Throwaway: every Human/Pirate/Robot unit's resolved combat stats.
const DT = ["none","spear","cav","pierce","magic","blade"]
const AC = ["none","soldier","spear","archer","cav","siege","monster"]
func _ready() -> void:
	for race in ["Human", "Pirates", "Robots"]:
		var paths: Array = []
		for k in RealmRoster.RACES[race].units:
			paths.append_array(k)
		paths.append_array(RealmRoster.RACES[race].get("others", []))
		if race == "Human":
			paths.append_array(["res://scenes/units/unit.tscn", "res://scenes/units/lord_unit.tscn", "res://scenes/units/magic_cannon_unit.tscn", "res://scenes/units/officer_unit.tscn"])
		print("== ", race)
		for p in paths:
			var u = load(p).instantiate()
			var cost := ""
			for c in u.costs:
				cost += "%s%d " % [c.resource_type.resource_name.substr(0,1) if c.resource_type.resource_name != "" else c.resource_type.resource_path.get_file().substr(0,1), c.amount]
			var ab := ""
			for a in u.abilities:
				ab += a.ability_name + ","
			print("%-18s hp%4d dmg%3d cd%4.1f dps%5.1f rng%5.1f spd%4.1f %-6s/%-7s cleave%.1f bld%.1f chg%s br%s pop%d aura%d onhit%s strip%s cost[%s] ab[%s] %s" % [u.display_name, u.max_health, u.attack_damage, u.attack_cooldown, u.attack_damage / max(u.attack_cooldown, 0.01), u.attack_range, u.move_speed, DT[u.damage_type], AC[u.armor_class], u.cleave, u.building_damage_multiplier, u.can_charge, u.can_brace, u.population_cost, u.heal_aura_amount, u.on_hit_ability != null, u.strips_buffs, cost, ab, p.get_file()])
			u.free()
	get_tree().quit()
