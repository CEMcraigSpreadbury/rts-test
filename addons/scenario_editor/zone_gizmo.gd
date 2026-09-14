@tool
extends EditorNode3DGizmoPlugin
## Draws a ScenarioZone's radius in the viewport, so "get your army to the
## bridge" can be placed by eye instead of by typing numbers.

const SEGMENTS: int = 48

func _init() -> void:
	create_material("zone", Color(0.95, 0.78, 0.35, 0.9))

func _get_gizmo_name() -> String:
	return "ScenarioZone"

func _has_gizmo(node: Node3D) -> bool:
	return node is ScenarioZone

func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var zone := gizmo.get_node_3d() as ScenarioZone
	if zone == null or zone.radius <= 0.0:
		return
	## A flat ring on the ground plus a short mast, so a zone is still findable
	## when the camera is low and the circle is edge-on.
	var lines := PackedVector3Array()
	for i in SEGMENTS:
		var a: float = TAU * float(i) / float(SEGMENTS)
		var b: float = TAU * float(i + 1) / float(SEGMENTS)
		lines.append(Vector3(cos(a), 0.0, sin(a)) * zone.radius)
		lines.append(Vector3(cos(b), 0.0, sin(b)) * zone.radius)
	lines.append(Vector3.ZERO)
	lines.append(Vector3(0.0, zone.radius * 0.35, 0.0))
	gizmo.add_lines(lines, get_material("zone", gizmo), false)
