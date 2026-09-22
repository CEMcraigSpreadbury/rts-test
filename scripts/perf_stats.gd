class_name PerfStats
extends CanvasLayer
## Debug-only movement profiling, toggled with "cmd perf" (see ChatConsole).
## Host-side counters bumped by Unit, GroupMovement and Main while this node
## exists, shown as an overlay and as custom monitors in the editor debugger's
## Monitors tab. Everything a caller does is gated on `enabled`, so with the
## overlay off the only cost left behind is that one static bool check.

## How often the overlay text is rebuilt, and the window its averages and
## peaks cover.
const REFRESH_INTERVAL: float = 0.5

## Sections cheaper than this are left out: a phase that never ran or a
## section that costs nothing says nothing, and there are enough of them
## between the frame, unit and AI groups to run the overlay off the bottom of
## the screen. Whatever is hidden is still counted, on a tail line.
const SECTION_MIN_MS: float = 0.05
## Most lines each group of sections may take, slowest first. The unit group
## gets the most because it is the one being broken down; between them and the
## fixed header these have to stay under a screen's worth.
const MAX_FRAME_LINES: int = 4
const MAX_UNIT_LINES: int = 7
const MAX_AI_LINES: int = 4
const MAX_EVENT_LINES: int = 3
## Thinks are counted over at least this long: an AI thinks about once a
## second, so a REFRESH_INTERVAL window would only ever read 0/s or 2/s.
const THINK_RATE_WINDOW: float = 2.0

static var enabled: bool = false

## Accumulated during the current physics frame, rolled into the window at the
## start of the next one (this node's physics tick runs before everyone else's).
static var _frame_unit_usec: int = 0
static var _frame_slide_usec: int = 0
static var _frame_slide_count: int = 0
static var _frame_path_count: int = 0

## Named per-frame (_process side) costs, section -> usec accumulated since the
## last overlay refresh. See add_section.
static var sections: Dictionary = {}
static var _section_frames: int = 0

static var _last_command_msec: float = 0.0
static var _peak_command_msec: float = 0.0
static var _last_command_units: int = 0

## Per-unit-tick costs, section -> usec accumulated since the last overlay
## refresh and summed over every unit that ticked. Shown per physics frame,
## breaking down the "unit script" line above. Sections nest (an enemy scan
## run from _tick_attacking is counted in both), so they are not meant to add
## up to it — each one answers "how much is the army spending here".
static var _unit_sections: Dictionary = {}

## AI think profiling. An AI thinks at most a few times a second, so a whole
## think's cost lands on one physics frame: averaged over a refresh window it
## would look like nothing, while that single spike is exactly what the player
## feels. So, like the command timings above, this keeps the last and the
## worst rather than a per-frame average.
static var _ai_phase_usec: Dictionary = {}
static var _ai_phase_peak_usec: Dictionary = {}
static var _last_ai_think_msec: float = 0.0
static var _peak_ai_think_msec: float = 0.0
static var _ai_thinks: int = 0

## Rare but expensive one-off work (a navmesh swap, a mass repath), name ->
## the worst one seen. Averaging these per frame the way sections are
## averaged would divide a 60 ms hitch that happens once every few seconds
## down to nothing, which is the opposite of what makes it worth finding.
static var _event_peak_usec: Dictionary = {}

var _window_frames: int = 0
var _window_unit_usec: int = 0
var _window_slide_usec: int = 0
var _window_slide_count: int = 0
var _window_path_count: int = 0
var _window_peak_unit_usec: int = 0
var _window_peak_path_count: int = 0
var _refresh_timer: float = 0.0

## Last window's results, in the units the overlay and monitors show.
var _unit_ms: float = 0.0
var _unit_ms_peak: float = 0.0
var _slide_ms: float = 0.0
var _slides: float = 0.0
var _paths: float = 0.0
var _paths_peak: int = 0

var _label: Label
var _unit_section_ms: Dictionary = {}
var _frame_section_ms: Dictionary = {}
var _thinks_per_second: float = 0.0
var _think_rate_seconds: float = 0.0
var _think_rate_count: int = 0
var _window_seconds: float = 0.0

const _MONITORS: Array[String] = [
	"rts/unit_ms", "rts/unit_ms_peak", "rts/slide_ms", "rts/slides_per_frame",
	"rts/paths_per_frame", "rts/paths_peak", "rts/command_ms",
	"rts/ai_think_ms", "rts/ai_think_peak_ms",
]

static func add_unit_time(usec: int) -> void:
	_frame_unit_usec += usec

static func add_slide(usec: int) -> void:
	_frame_slide_usec += usec
	_frame_slide_count += 1

## Adds `usec` to a named section of the frame (_process) time, e.g. "march".
static func add_section(section: StringName, usec: int) -> void:
	sections[section] = int(sections.get(section, 0)) + usec

static func count_path() -> void:
	_frame_path_count += 1

static func record_command(msec: float, unit_count: int) -> void:
	_last_command_msec = msec
	_last_command_units = unit_count
	_peak_command_msec = maxf(_peak_command_msec, msec)

## Adds one section of a unit's physics tick (e.g. "separation"), summed over
## every unit that runs it this frame.
static func add_unit_section(section: StringName, usec: int) -> void:
	_unit_sections[section] = int(_unit_sections.get(section, 0)) + usec

## Adds one phase of the AI think currently being timed. record_ai_think()
## closes that think off and rolls its phases into the peaks.
static func add_ai_phase(phase: StringName, usec: int) -> void:
	_ai_phase_usec[phase] = int(_ai_phase_usec.get(phase, 0)) + usec

## Records one occurrence of a named one-off event, keeping the worst.
static func record_event(event: StringName, usec: int) -> void:
	_event_peak_usec[event] = maxi(int(_event_peak_usec.get(event, 0)), usec)

## Closes off one AI's think; `usec` is the whole think, its phases included.
static func record_ai_think(usec: int) -> void:
	_ai_thinks += 1
	_last_ai_think_msec = usec / 1000.0
	_peak_ai_think_msec = maxf(_peak_ai_think_msec, _last_ai_think_msec)
	for phase in _ai_phase_usec:
		_ai_phase_peak_usec[phase] = maxi(int(_ai_phase_peak_usec.get(phase, 0)), int(_ai_phase_usec[phase]))
	_ai_phase_usec.clear()

func _enter_tree() -> void:
	enabled = true
	sections.clear()
	_section_frames = 0
	layer = 100
	process_physics_priority = -1000
	_reset_frame()
	_peak_command_msec = 0.0
	_last_command_msec = 0.0
	_last_command_units = 0
	_unit_sections.clear()
	_ai_phase_usec.clear()
	_ai_phase_peak_usec.clear()
	_last_ai_think_msec = 0.0
	_peak_ai_think_msec = 0.0
	_ai_thinks = 0
	_event_peak_usec.clear()
	var values: Array[Callable] = [
		func(): return _unit_ms, func(): return _unit_ms_peak, func(): return _slide_ms,
		func(): return _slides, func(): return _paths, func(): return _paths_peak,
		func(): return _last_command_msec,
		func(): return _last_ai_think_msec, func(): return _peak_ai_think_msec,
	]
	for i in _MONITORS.size():
		if not Performance.has_custom_monitor(_MONITORS[i]):
			Performance.add_custom_monitor(_MONITORS[i], values[i])

func _exit_tree() -> void:
	enabled = false
	for id in _MONITORS:
		if Performance.has_custom_monitor(id):
			Performance.remove_custom_monitor(id)

func _ready() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(20.0, 100.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.6)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 23)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_label)
	_refresh()

func _physics_process(_delta: float) -> void:
	_window_frames += 1
	_window_unit_usec += _frame_unit_usec
	_window_slide_usec += _frame_slide_usec
	_window_slide_count += _frame_slide_count
	_window_path_count += _frame_path_count
	_window_peak_unit_usec = maxi(_window_peak_unit_usec, _frame_unit_usec)
	_window_peak_path_count = maxi(_window_peak_path_count, _frame_path_count)
	_reset_frame()

func _process(delta: float) -> void:
	_section_frames += 1
	_window_seconds += delta
	_refresh_timer -= delta
	if _refresh_timer > 0.0:
		return
	_refresh_timer = REFRESH_INTERVAL
	## Measured rather than assumed to be REFRESH_INTERVAL: the overshoot is a
	## whole frame, and at the frame rates this overlay exists to diagnose that
	## one frame can be most of the window again.
	var elapsed := maxf(_window_seconds, 0.001)
	_window_seconds = 0.0
	_think_rate_seconds += elapsed
	_think_rate_count += _ai_thinks
	_ai_thinks = 0
	if _think_rate_seconds >= THINK_RATE_WINDOW:
		_thinks_per_second = _think_rate_count / _think_rate_seconds
		_think_rate_seconds = 0.0
		_think_rate_count = 0
	var frames := maxi(_window_frames, 1)
	_unit_section_ms.clear()
	for section in _unit_sections:
		_unit_section_ms[section] = float(_unit_sections[section]) / 1000.0 / frames
	_unit_sections.clear()
	_unit_ms = _window_unit_usec / 1000.0 / frames
	_unit_ms_peak = _window_peak_unit_usec / 1000.0
	_slide_ms = _window_slide_usec / 1000.0 / frames
	_slides = float(_window_slide_count) / frames
	_paths = float(_window_path_count) / frames
	_paths_peak = _window_peak_path_count
	_window_frames = 0
	_window_unit_usec = 0
	_window_slide_usec = 0
	_window_slide_count = 0
	_window_path_count = 0
	_window_peak_unit_usec = 0
	_window_peak_path_count = 0
	_refresh()

func _refresh() -> void:
	var total := 0
	var moving := 0
	for node in get_tree().get_nodes_in_group(&"units"):
		var unit := node as Unit
		if unit == null or unit.status_activity == Unit.Activity.DEAD:
			continue
		total += 1
		if Vector2(unit.velocity.x, unit.velocity.z).length_squared() > 0.01:
			moving += 1
	var lines: PackedStringArray = [
		"FPS %d   frame %.1f ms   physics %.1f ms" % [
			Engine.get_frames_per_second(),
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0],
		"units %d   moving %d" % [total, moving],
		"unit script %.2f ms/frame (peak %.2f)" % [_unit_ms, _unit_ms_peak],
		"  of which slide %.2f ms, %.0f slides/frame" % [_slide_ms, _slides],
		"path queries %.1f/frame (peak %d)" % [_paths, _paths_peak],
		"last order %.1f ms for %d units (peak %.1f)" % [_last_command_msec, _last_command_units, _peak_command_msec],
		"ai think %.1f ms last (peak %.1f), %.1f/s" % [_last_ai_think_msec, _peak_ai_think_msec, _thinks_per_second],
		"navmesh polys %d   agents %d" % [
			NavigationServer3D.get_process_info(NavigationServer3D.INFO_POLYGON_COUNT),
			NavigationServer3D.get_process_info(NavigationServer3D.INFO_AGENT_COUNT)],
		## The rest of the frame time: everything above is script, and on a
		## big map the named sections come nowhere near accounting for it.
		## These say whether what is left is the renderer and, if so, whether
		## it is draw-call bound (every unit is its own sprite and its own
		## handful of nodes) or pushing too much geometry.
		"draw calls %d   objects %d   nodes %d" % [
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
			int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))],
	]
	## Frame-side sections, as ms per rendered frame.
	var frames := maxi(_section_frames, 1)
	_frame_section_ms.clear()
	for section in sections:
		_frame_section_ms[section] = sections[section] / 1000.0 / frames
	sections.clear()
	_section_frames = 0
	_append_sections(lines, "frame: ", _frame_section_ms, "", MAX_FRAME_LINES)
	## The breakdown of the "unit script" line above, as ms per physics frame
	## summed over every unit.
	_append_sections(lines, "unit: ", _unit_section_ms, "", MAX_UNIT_LINES)
	## AI phases: the most any one think has cost, which is what lands on a
	## single frame as a stutter (see record_ai_think).
	var ai_ms: Dictionary = {}
	for phase in _ai_phase_peak_usec:
		ai_ms[phase] = _ai_phase_peak_usec[phase] / 1000.0
	_append_sections(lines, "ai: ", ai_ms, "peak ", MAX_AI_LINES)
	## One-off events, worst first — these are hitches, not steady costs.
	var event_ms: Dictionary = {}
	for event in _event_peak_usec:
		event_ms[event] = _event_peak_usec[event] / 1000.0
	_append_sections(lines, "peak: ", event_ms, "", MAX_EVENT_LINES)
	_label.text = "\n".join(lines)

## The last completed window's figures, plus the run's cumulative peaks, in
## the units the overlay prints them. For the headless benchmark
## (scripts/tools/benchmark.gd), which averages these over a whole run rather
## than reading one half-second window off a screenshot.
func snapshot() -> Dictionary:
	return {
		"unit_ms": _unit_ms,
		"unit_ms_peak": _unit_ms_peak,
		"slide_ms": _slide_ms,
		"paths": _paths,
		"unit_sections": _unit_section_ms.duplicate(),
		"frame_sections": _frame_section_ms.duplicate(),
		"ai_phase_peak_ms": _peaks_in_ms(_ai_phase_peak_usec),
		"event_peak_ms": _peaks_in_ms(_event_peak_usec),
		"command_peak_ms": _peak_command_msec,
		"ai_think_peak_ms": _peak_ai_think_msec,
	}

static func _peaks_in_ms(peaks: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in peaks:
		out[key] = peaks[key] / 1000.0
	return out

## Appends the slowest MAX_SECTION_LINES of `values` (name -> ms) to `lines`,
## dropping anything under SECTION_MIN_MS and counting what was dropped on a
## tail line. `label` goes between the name and the number ("peak ").
func _append_sections(lines: PackedStringArray, prefix: String, values: Dictionary, label: String, max_lines: int) -> void:
	var names: Array = []
	for key in values:
		if float(values[key]) >= SECTION_MIN_MS:
			names.append(key)
	names.sort_custom(func(a, b): return values[a] > values[b])
	var shown: int = mini(names.size(), max_lines)
	for i in shown:
		lines.append("%s%s %s%.2f ms" % [prefix, names[i], label, values[names[i]]])
	var hidden: int = values.size() - shown
	if hidden > 0:
		lines.append("%s%d more under %.2f ms" % [prefix, hidden, SECTION_MIN_MS])

static func _reset_frame() -> void:
	_frame_unit_usec = 0
	_frame_slide_usec = 0
	_frame_slide_count = 0
	_frame_path_count = 0
