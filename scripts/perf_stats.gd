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

const _MONITORS: Array[String] = [
	"rts/unit_ms", "rts/unit_ms_peak", "rts/slide_ms", "rts/slides_per_frame",
	"rts/paths_per_frame", "rts/paths_peak", "rts/command_ms",
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
	var values: Array[Callable] = [
		func(): return _unit_ms, func(): return _unit_ms_peak, func(): return _slide_ms,
		func(): return _slides, func(): return _paths, func(): return _paths_peak,
		func(): return _last_command_msec,
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
	panel.position = Vector2(12, 60)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.6)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 14)
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
	_refresh_timer -= delta
	if _refresh_timer > 0.0:
		return
	_refresh_timer = REFRESH_INTERVAL
	var frames := maxi(_window_frames, 1)
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
		"navmesh polys %d   agents %d" % [
			NavigationServer3D.get_process_info(NavigationServer3D.INFO_POLYGON_COUNT),
			NavigationServer3D.get_process_info(NavigationServer3D.INFO_AGENT_COUNT)],
	]
	## Frame-side sections, slowest first, as ms per rendered frame.
	var names: Array = sections.keys()
	names.sort_custom(func(a, b): return sections[a] > sections[b])
	var frames := maxi(_section_frames, 1)
	for section in names:
		lines.append("frame: %s %.2f ms" % [section, sections[section] / 1000.0 / frames])
	sections.clear()
	_section_frames = 0
	_label.text = "\n".join(lines)

static func _reset_frame() -> void:
	_frame_unit_usec = 0
	_frame_slide_usec = 0
	_frame_slide_count = 0
	_frame_path_count = 0
