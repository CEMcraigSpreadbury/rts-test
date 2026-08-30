extends Node
## Host-authoritative per-player Blacksmith bonuses, applying to every unit
## of the matching category a player owns (present and future). Not synced —
## combat resolution (Unit.take_damage/_tick_attacking) only ever runs on the
## host, same reasoning as CombatUtils' Monarch aura helpers.

enum Stat { WEAPON, ARMOR }

## peer_id -> { Unit.UnitCategory: { Stat: int } }
var _bonuses: Dictionary = {}

func add_bonus(peer_id: int, category: Unit.UnitCategory, stat: Stat, amount: int) -> void:
	if not _bonuses.has(peer_id):
		_bonuses[peer_id] = {}
	if not _bonuses[peer_id].has(category):
		_bonuses[peer_id][category] = {Stat.WEAPON: 0, Stat.ARMOR: 0}
	_bonuses[peer_id][category][stat] += amount

func get_weapon_bonus(peer_id: int, category: Unit.UnitCategory) -> int:
	return _bonuses.get(peer_id, {}).get(category, {}).get(Stat.WEAPON, 0)

func get_armor_bonus(peer_id: int, category: Unit.UnitCategory) -> int:
	return _bonuses.get(peer_id, {}).get(category, {}).get(Stat.ARMOR, 0)
