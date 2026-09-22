extends Node
## Repeatable performance benchmark, for telling a real optimisation from
## run-to-run noise — which playing a match and screenshotting the "cmd perf"
## overlay cannot do.
##
##   godot --headless --path . res://scenes/tools/benchmark.tscn
##   godot --headless --path . res://scenes/tools/benchmark.tscn -- --units=160 --ticks=900
##   godot --headless --path . res://scenes/tools/benchmark.tscn -- --mode=match --ai=2
##
## Two modes. `battle` (the default) is the perf harness: two equal armies
## spawned nose to nose and sent into each other, for comparing two builds of
## the same scenario. `match` is the behaviour gate: a whole game played out
## with nobody interfering, reporting what each AI has managed — because a
## change to how the AI fights can leave every perf number healthy while its
## waves sit at home, which is exactly how regiments broke it last time.
##
## Starts a single-player match against one AI on a fixed map with a fixed RNG
## seed, spawns two equal armies at fixed positions either side of the midpoint
## between the first two spawn points, sends them into each other, and prints
## the same figures the overlay shows — averaged over the measured stretch
## rather than read off one half-second window.
##
## Not bit-for-bit deterministic: Jolt, the threaded navmesh walkability build
## and the AI reacting to what it sees all move between runs. Repeatable enough
## to compare two builds of the same scenario, which is the point. Headless
## measures script and physics only — there is no renderer, so it says nothing
## about draw cost.

## --- Defaults. Each is overridable on the command line after a bare "--" ---
const DEFAULT_UNITS_PER_SIDE: int = 120
const DEFAULT_MEASURE_TICKS: int = 600
const DEFAULT_SEED: int = 20260922
const DEFAULT_MAP_INDEX: int = 0
const DEFAULT_DIFFICULTY: int = 1
## AI opponents. The first one gets the opposing army; any beyond that just
## play their own game, which is what a 4-player map actually costs — more
## thinks, more bases, more units on the map.
const DEFAULT_AI_COUNT: int = 1
## Ticks between re-issuing each side's attack-move. A player pushes, retreats
## and re-pushes constantly, and the group order path is expensive enough to
## be worth measuring — off more than the one sample a single opening order
## would give.
const DEFAULT_REORDER_TICKS: int = 150
## A match is long enough for an AI to get a base up, train an army and push
## it out — the short battle run says nothing about any of that. Five minutes
## at 30 Hz.
const DEFAULT_MATCH_TICKS: int = 9000
## How often a match prints where everyone has got to.
const MATCH_REPORT_TICKS: int = 900

## The match spawns its bases and starts the first navmesh bake as it loads,
## and that bake finishes on a worker thread — an army dropped in before it
## lands has nothing to path over.
const WARMUP_TICKS: int = 120
## Between spawning the armies and sending them in: long enough to settle onto
## the ground and push apart, so none of that counts toward the measurement.
const SETTLE_TICKS: int = 60

## Repeated in order — a melee line, an anti-cavalry line and a ranged line, so
## the counter matrix, the chase logic and the projectile path all get walked
## rather than one unit type's hot path.
const ARMY_SCENES: Array[String] = [
	"res://scenes/units/soldier_unit.tscn",
	"res://scenes/units/spearman_unit.tscn",
	"res://scenes/units/archer_unit.tscn",
]

const ROW_LENGTH: int = 12
const UNIT_SPACING: float = 1.6
## How far each army starts from the midpoint between the two spawn points.
const ARMY_SEPARATION: float = 14.0

var units_per_side: int = DEFAULT_UNITS_PER_SIDE
var measure_ticks: int = DEFAULT_MEASURE_TICKS
var run_seed: int = DEFAULT_SEED
var map_index: int = DEFAULT_MAP_INDEX
var difficulty: int = DEFAULT_DIFFICULTY
var reorder_ticks: int = DEFAULT_REORDER_TICKS
var ai_count: int = DEFAULT_AI_COUNT
var mode: String = "battle"
var _ticks_set: bool = false
var _ai_set: bool = false

var _main: Main
var _ai_peer: int = 0
var _ai_peers: Array[int] = []
var _tick: int = 0
var _perf: PerfStats
var _samples: Array[Dictionary] = []
var _sample_timer: float = 0.0
var _armies: Dictionary = {}
var _measuring: bool = false
var _wall_start_usec: int = 0

func _ready() -> void:
	_parse_args()
	## A match wants a longer run and somebody to fight, unless told otherwise.
	if mode == "match":
		if not _ticks_set:
			measure_ticks = DEFAULT_MATCH_TICKS
		if not _ai_set:
			ai_count = 2
	seed(run_seed)
	var maps: Array[MapInfo] = MapInfo.list_all()
	if maps.is_empty():
		_abort("no MapInfo resources in res://resources/maps/")
		return
	var info: MapInfo = maps[clampi(map_index, 0, maps.size() - 1)]
	var scene: PackedScene = load(info.scene_path)
	if scene == null:
		_abort("could not load map scene " + info.scene_path)
		return
	Network.start_offline()
	Network.map_index = map_index
	for i in ai_count:
		var id: int = Network.add_ai_player(difficulty)
		if id != 0:
			_ai_peers.append(id)
	if _ai_peers.is_empty():
		_abort("could not add an AI player")
		return
	_ai_peer = _ai_peers[0]
	if mode == "match":
		print("benchmark: match on %s, %d AI, %d ticks, seed %d" % [
			info.map_name, _ai_peers.size(), measure_ticks, run_seed])
	else:
		print("benchmark: %s, %d units/side, %d AI, %d ticks, seed %d" % [
			info.map_name, units_per_side, _ai_peers.size(), measure_ticks, run_seed])
	## Deferred: the root is still setting up this scene, so it refuses a
	## sibling until that has finished. Nothing starts counting ticks until
	## _main is set anyway (see _physics_process).
	_start_match.call_deferred(scene)

## Added under the root rather than swapped in as the scene, so this node
## survives to drive the run. The match still has to be current_scene: parts
## of it find their way around from there.
func _start_match(scene: PackedScene) -> void:
	var match_scene: Node = scene.instantiate()
	get_tree().root.add_child(match_scene)
	get_tree().current_scene = match_scene
	_main = match_scene as Main
	if _main == null:
		_abort("map scene root is not a Main")

func _physics_process(_delta: float) -> void:
	if _main == null:
		return
	_tick += 1
	if mode == "match":
		_match_tick()
		return
	if _tick == WARMUP_TICKS:
		_spawn_armies()
		return
	if _tick == WARMUP_TICKS + SETTLE_TICKS:
		_begin_measuring()
		_push()
		return
	if not _measuring:
		return
	var measured: int = _tick - WARMUP_TICKS - SETTLE_TICKS
	if measured >= measure_ticks:
		_finish()
	elif measured % reorder_ticks == 0:
		_push()

func _process(delta: float) -> void:
	if not _measuring or _perf == null:
		return
	_sample_timer -= delta
	if _sample_timer > 0.0:
		return
	_sample_timer = PerfStats.REFRESH_INTERVAL
	_samples.append(_perf.snapshot())

func _spawn_armies() -> void:
	var spawns: Node3D = _main.player_spawn_points
	if spawns.get_child_count() < 2:
		_abort("map needs at least two PlayerSpawnPoints")
		return
	var a: Vector3 = (spawns.get_child(0) as Node3D).global_position
	var b: Vector3 = (spawns.get_child(1) as Node3D).global_position
	var mid: Vector3 = (a + b) * 0.5
	var forward: Vector3 = b - a
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD
	_armies[1] = _spawn_army(1, mid - forward * ARMY_SEPARATION, forward)
	_armies[_ai_peer] = _spawn_army(_ai_peer, mid + forward * ARMY_SEPARATION, -forward)
	print("benchmark: spawned %d + %d units" % [
		(_armies[1] as Array).size(), (_armies[_ai_peer] as Array).size()])

## A block `units_per_side` strong, centred on `centre` and facing `facing`.
func _spawn_army(peer_id: int, centre: Vector3, facing: Vector3) -> Array[Unit]:
	var right := Vector3(facing.z, 0.0, -facing.x)
	var tint: Color = _main.get_team_tint(peer_id)
	var army: Array[Unit] = []
	for i in units_per_side:
		var row: int = i / ROW_LENGTH
		var column: int = i % ROW_LENGTH
		var across: float = (column - (ROW_LENGTH - 1) * 0.5) * UNIT_SPACING
		var offset: Vector3 = right * across - facing * (row * UNIT_SPACING)
		var unit: Unit = _main.unit_spawner.spawn({
			"scene_path": ARMY_SCENES[i % ARMY_SCENES.size()],
			"peer_id": peer_id,
			"tint": tint,
			"position": centre + offset,
		})
		if unit == null:
			continue
		Population.reserve(peer_id, unit.population_cost)
		army.append(unit)
	return army

func _begin_measuring() -> void:
	## Added now rather than at startup: entering the tree is what clears its
	## peaks, so nothing from the spawn or the settle counts against the run.
	_perf = PerfStats.new()
	get_tree().root.add_child(_perf)
	_measuring = true
	_wall_start_usec = Time.get_ticks_usec()
	print("benchmark: measuring %d ticks" % measure_ticks)

## A whole game, with nobody interfering. The perf figures still come out of
## it, but what it is really for is whether each AI is still playing: building,
## raising bodies and pushing them away from home. Every one of those can stop
## while the frame times stay perfectly healthy.
func _match_tick() -> void:
	if _tick == WARMUP_TICKS:
		_begin_measuring()
		print("")
		print("  time    who        villagers army bodies  buildings points reach")
		_match_report()
		return
	if not _measuring:
		return
	var measured: int = _tick - WARMUP_TICKS
	if measured >= measure_ticks:
		_match_report()
		_finish()
	elif measured % MATCH_REPORT_TICKS == 0:
		_match_report()

func _match_report() -> void:
	var minutes: float = float(_tick - WARMUP_TICKS) / 30.0 / 60.0
	for peer in _main.ai_players:
		var ai: AiPlayer = _main.ai_players[peer]
		var bodies := 0
		var in_bodies := 0
		for id in _main.regiments:
			var regiment: Regiment = _main.regiments[id]
			if regiment.owner_peer_id == peer:
				bodies += 1
				in_bodies += regiment.strength()
		## How far its army has got from its own base. A wave that never
		## leaves home is the failure this mode exists to catch.
		var reach := 0.0
		for unit in ai.army:
			if is_instance_valid(unit):
				reach = maxf(reach, ai.home.distance_to(unit.global_position))
		print("  %4.1fm   ai %-6d %7d %6d %3d (%3d) %7d %6d %6.0f" % [
			minutes, peer, ai.villagers.size(), ai.army.size(),
			bodies, in_bodies, ai.my_buildings.size(), _points_held(peer), reach])

func _points_held(peer: int) -> int:
	var held := 0
	for node in get_tree().get_nodes_in_group(&"objectives"):
		if node.owner_peer_id == peer:
			held += 1
	return held

## Sends each side at the other, as a group attack-move. Deliberately the full
## group order path — formation solve, slot assignment, march — since that is
## what both an AI wave and a player push go through, and it is re-issued
## through the run rather than once at the start.
func _push() -> void:
	var mine: Array[Unit] = _living(1)
	var theirs: Array[Unit] = _living(_ai_peer)
	if mine.is_empty() or theirs.is_empty():
		return
	_order_side(1, mine, theirs)
	_order_side(_ai_peer, theirs, mine)

func _order_side(peer_id: int, army: Array[Unit], enemy: Array[Unit]) -> void:
	var paths: Array[NodePath] = []
	for unit in army:
		paths.append(unit.get_path())
	var centroid := Vector3.ZERO
	for unit in enemy:
		centroid += unit.global_position
	centroid /= enemy.size()
	_main.issue_command_as(peer_id, paths, NodePath(), centroid, true, false)

func _living(peer_id: int) -> Array[Unit]:
	var out: Array[Unit] = []
	for entry in _armies[peer_id]:
		var unit := entry as Unit
		if is_instance_valid(unit) and unit.status_activity != Unit.Activity.DEAD:
			out.append(unit)
	return out

func _finish() -> void:
	_measuring = false
	var wall_seconds: float = (Time.get_ticks_usec() - _wall_start_usec) / 1000000.0
	var alive := 0
	for node in get_tree().get_nodes_in_group(&"units"):
		var unit := node as Unit
		if unit != null and unit.status_activity != Unit.Activity.DEAD:
			alive += 1
	print("")
	print("=== benchmark result ===")
	print("map %d   seed %d   %d units/side   %d ticks   %.1f s wall" % [
		map_index, run_seed, units_per_side, measure_ticks, wall_seconds])
	print("units alive at end %d   samples %d" % [alive, _samples.size()])
	print("")
	print("unit script      %7.2f ms/tick   peak %7.2f" % [_avg("unit_ms"), _peak("unit_ms_peak")])
	print("  of which slide %7.2f ms/tick" % _avg("slide_ms"))
	print("path queries     %7.2f /frame" % _avg("paths"))
	print("order dispatch   %7.2f ms peak" % _peak("command_peak_ms"))
	print("ai think         %7.2f ms peak" % _peak("ai_think_peak_ms"))
	_print_group("unit", "unit_sections", true)
	_print_group("frame", "frame_sections", true)
	_print_group("ai", "ai_phase_peak_ms", false)
	_print_group("peak", "event_peak_ms", false)
	## Taken out of the tree, and deliberately not freed, before quitting:
	## tearing a live match down at exit crashes in the engine's shutdown
	## (see the note in the class docs). The process is ending anyway, so
	## what this orphans costs nothing.
	get_tree().current_scene = null
	get_tree().root.remove_child(_perf)
	get_tree().root.remove_child(_main)
	await get_tree().process_frame
	get_tree().quit()

func _avg(key: String) -> float:
	if _samples.is_empty():
		return 0.0
	var total := 0.0
	for sample in _samples:
		total += float(sample[key])
	return total / _samples.size()

func _peak(key: String) -> float:
	var best := 0.0
	for sample in _samples:
		best = maxf(best, float(sample[key]))
	return best

## `averaged` groups are per-tick costs worth a mean over the run; the others
## are already running peaks, where the worst sample is the run's worst.
func _print_group(label: String, key: String, averaged: bool) -> void:
	var totals: Dictionary = {}
	for sample in _samples:
		var group: Dictionary = sample[key]
		for section in group:
			var value: float = float(group[section])
			if averaged:
				totals[section] = float(totals.get(section, 0.0)) + value
			else:
				totals[section] = maxf(float(totals.get(section, 0.0)), value)
	if totals.is_empty() or _samples.is_empty():
		return
	var sections: Array = totals.keys()
	if averaged:
		for section in sections:
			totals[section] = float(totals[section]) / _samples.size()
	sections.sort_custom(func(x, y): return totals[x] > totals[y])
	print("")
	for section in sections:
		if float(totals[section]) < 0.01:
			continue
		print("%-6s %-22s %7.2f ms" % [label + ":", section, totals[section]])

func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts: PackedStringArray = arg.lstrip("-").split("=")
		if parts.size() != 2:
			continue
		var key: String = parts[0]
		var value: String = parts[1]
		if key == "units":
			units_per_side = maxi(1, int(value))
		elif key == "ticks":
			measure_ticks = maxi(1, int(value))
			_ticks_set = true
		elif key == "seed":
			run_seed = int(value)
		elif key == "map":
			map_index = maxi(0, int(value))
		elif key == "difficulty":
			difficulty = clampi(int(value), 0, 2)
		elif key == "reorder":
			reorder_ticks = maxi(1, int(value))
		elif key == "ai":
			ai_count = maxi(1, int(value))
			_ai_set = true
		elif key == "mode":
			mode = value

func _abort(reason: String) -> void:
	push_error("benchmark: " + reason)
	print("benchmark: FAILED - " + reason)
	get_tree().quit(1)
