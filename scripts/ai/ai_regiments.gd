class_name AiRegiments
extends RefCounted
## AiPlayer's regiments: raises them from the loose soldiers it has trained,
## keeps them up to strength, and buys the officers to lead them.
##
## Nothing here issues an order. An order to any part of a regiment already
## applies to the whole body (Main.expand_to_regiments), so AiCombat's waves
## and defences command blocks without knowing regiments exist at all — which
## is the point. The last attempt at squads failed because it rewrote how the
## AI moved; this changes only what its army is made of.

var ai: AiPlayer

func _init(p_ai: AiPlayer) -> void:
	ai = p_ai

func think() -> void:
	if ai.profile.regiment_size <= 0:
		return
	_reinforce()
	_raise()
	_train_officer()

## This player's army, minus anyone already spoken for.
func _loose() -> Array[Unit]:
	var out: Array[Unit] = []
	for unit in ai.army:
		if unit.regiment_id < 0:
			out.append(unit)
	return out

func _split(units: Array[Unit], men: Array[Unit], officers: Array[Unit]) -> void:
	for unit in units:
		if unit.is_officer:
			officers.append(unit)
		else:
			men.append(unit)

func _mine() -> Array[Regiment]:
	var out: Array[Regiment] = []
	for id in ai.main.regiments:
		var regiment: Regiment = ai.main.regiments[id]
		if regiment.owner_peer_id == ai.peer_id:
			out.append(regiment)
	return out

## Tops up one body per think, from the loose men it has. Under-strength bodies
## and leaderless ones both count — a regiment whose officer fell is still
## fighting, it is just fighting worse.
func _reinforce() -> void:
	var men: Array[Unit] = []
	var officers: Array[Unit] = []
	_split(_loose(), men, officers)
	if men.is_empty() and officers.is_empty():
		return
	for regiment in _mine():
		regiment.prune()
		if not regiment.is_under_strength() and regiment.has_officer():
			continue
		if ai.main.reinforce_regiment(regiment, men, officers) > 0:
			return

## Raises at most one body per think. Forming is cheap, but the men then walk
## into their places, and raising three at once would set the whole army
## marching about instead of fighting.
func _raise() -> void:
	var men: Array[Unit] = []
	var officers: Array[Unit] = []
	_split(_loose(), men, officers)
	if officers.is_empty():
		return
	## One kind of soldier to a body, same rule the player forms under.
	var pick: Array[Unit] = Main.largest_same_type(men)
	if pick.size() < ai.profile.regiment_size:
		return
	var body: Array[Unit] = [officers[0]] as Array[Unit]
	for i in mini(pick.size(), ai.profile.regiment_size):
		body.append(pick[i])
	ai.main.form_regiment(ai.peer_id, body)

## Buys an officer once there are enough loose men of one kind to be worth
## leading and nobody spare to lead them. One at a time, and never ahead of the
## men: an officer with no body is a soldier who cost twice as much.
func _train_officer() -> void:
	var men: Array[Unit] = []
	var officers: Array[Unit] = []
	_split(_loose(), men, officers)
	if not officers.is_empty():
		return
	if Main.largest_same_type(men).size() < ai.profile.regiment_size:
		return
	for building in ai.my_buildings:
		for queued in building.queue:
			if ai.trains_officer(queued):
				return
	for building in ai.my_buildings:
		if building.is_under_construction or building.queue.size() >= ai.profile.military_queue:
			continue
		for i in building.producibles.size():
			var item: ProducibleItem = building.producibles[i]
			if not ai.trains_officer(item):
				continue
			if ai.can_afford(ai.item_costs(item)) and ai.main.enqueue_as(ai.peer_id, building.get_path(), i):
				return
