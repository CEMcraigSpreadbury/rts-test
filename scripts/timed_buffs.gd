class_name TimedBuffs
extends RefCounted
## Short-lived Ruler power effects on one unit or building (see
## ResearchNode.Buff), timed on Research.now() so they hold while single player
## is paused. Host-only, like the combat and production they change. A second
## hit of the same buff refreshes it, keeping whichever amount is stronger.

## Buff -> [amount: float, until: float]
var _entries: Dictionary = {}

func add(buff: int, amount: float, duration: float) -> void:
	var now := Research.now()
	var entry: Array = _entries.get(buff, [0.0, 0.0])
	if entry[1] > now and absf(entry[0]) > absf(amount):
		amount = entry[0]
	_entries[buff] = [amount, maxf(now + duration, entry[1])]

## 0.0 once it has worn off.
func amount(buff: int) -> float:
	var entry = _entries.get(buff)
	if entry == null:
		return 0.0
	if entry[1] <= Research.now():
		_entries.erase(buff)
		return 0.0
	return entry[0]

## Everything wears off at once — what a Dark Elf Spellstealer does on hit.
## Curse and the other hostile powers live in here too, so this strips the
## bad with the good rather than picking sides.
func clear() -> void:
	_entries.clear()
