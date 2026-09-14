@tool
extends EditorPlugin
## Scenario Editor: a dock for building campaign and tutorial scenarios, plus
## the viewport gizmo that draws a quest zone's radius.

const ScenarioDock = preload("res://addons/scenario_editor/scenario_dock.gd")
const ZoneGizmo = preload("res://addons/scenario_editor/zone_gizmo.gd")

var dock: ScenarioDock
var _gizmo: EditorNode3DGizmoPlugin

func _enter_tree() -> void:
	dock = ScenarioDock.new()
	## The dock tab's label is just the node's name; left unset it shows up as
	## "@VBoxContainer@12".
	dock.name = "Scenario"
	dock.plugin = self
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)
	_gizmo = ZoneGizmo.new()
	add_node_3d_gizmo_plugin(_gizmo)
	scene_changed.connect(_on_scene_changed)

func _exit_tree() -> void:
	scene_changed.disconnect(_on_scene_changed)
	remove_node_3d_gizmo_plugin(_gizmo)
	remove_control_from_docks(dock)
	dock.queue_free()

## Opening another scene changes what the dock is looking at.
func _on_scene_changed(_scene_root: Node) -> void:
	if dock != null:
		dock.refresh()
