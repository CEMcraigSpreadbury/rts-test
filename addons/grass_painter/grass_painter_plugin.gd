@tool
extends EditorPlugin
## Paints grass instances (crossed-quad billboards using shaders/grass_wind.gdshader)
## onto a MultiMeshInstance3D by raycasting the 3D viewport's mouse position
## against whatever collidable geometry is under it — this project's terrain
## (NavigationRegion3D/TileMapLayer3D's baked StaticBody3D collision) works
## out of the box since it's a normal static collider, same as any other.
##
## Painting/erasing edits the target's MultiMesh directly and only touches
## the undo/redo stack once per stroke (mouse down -> up), not per dab.

const GrassPaintDock = preload("res://addons/grass_painter/grass_paint_dock.gd")
const GRASS_MATERIAL = preload("res://shaders/grass_wind_material.tres")

const GRASS_BLADE_HALF_WIDTH: float = 0.22
const GRASS_BLADE_HEIGHT: float = 0.55
## How far above/below a candidate point to search for the real ground height
## — must comfortably exceed any plausible terrain height difference within
## one brush radius.
const HEIGHT_PROBE_DISTANCE: float = 15.0
## Two dabs closer together than this (relative to brush_radius) are treated
## as the same dab while dragging slowly, so holding the mouse still doesn't
## keep stacking new instances every frame.
const MIN_DAB_SPACING_FRACTION: float = 0.3

## Typed as the preloaded script itself (not just Control) so every access to
## its custom members below has a real static type — a plain Control-typed
## var here makes dock.get_target()/.brush_radius/etc. resolve as untyped
## Variant, which breaks := type inference at every call site.
var dock: GrassPaintDock
var _stroke_active: bool = false
var _stroke_target: MultiMeshInstance3D = null
var _stroke_start_transforms: Array = []
var _last_dab_pos: Vector3 = Vector3.INF
## target -> Array[Transform3D], the working copy edited during a stroke and
## flushed to the real MultiMesh after every dab (kept per-target so switching
## targets mid-session doesn't lose in-progress state).
var _transforms_cache: Dictionary = {}

func _enter_tree() -> void:
	dock = GrassPaintDock.new()
	## The dock tab's label is just this node's name — left unset it defaults
	## to "@VBoxContainer@<id>" instead of anything recognizable.
	dock.name = "Grass Painter"
	dock.plugin = self
	dock.clear_requested.connect(_on_clear_requested)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)
	## Before any real layer is picked, the dock edits this template directly
	## — harmless now that it's only ever duplicated (never assigned as-is)
	## into an actual layer, so tweaking it here just changes what NEW layers
	## start out looking like.
	dock.set_grass_material(GRASS_MATERIAL)

## Required for _forward_3d_gui_input to ever be called at all — without a
## _handles() override the editor never routes 3D viewport input to this
## plugin, regardless of what's selected (this is what let every click fall
## straight through to the default box-select behavior).
func _handles(_object: Object) -> bool:
	return true

func _exit_tree() -> void:
	remove_control_from_docks(dock)
	dock.queue_free()

func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if not dock.paint_mode_active:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	var target := dock.get_target()
	if target == null or camera == null:
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_stroke(target)
			_paint_at(camera, event.position, target)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		elif _stroke_active:
			_end_stroke()
			return EditorPlugin.AFTER_GUI_INPUT_STOP

	elif event is InputEventMouseMotion and _stroke_active:
		_paint_at(camera, event.position, target)
		return EditorPlugin.AFTER_GUI_INPUT_STOP

	return EditorPlugin.AFTER_GUI_INPUT_PASS

## --- Stroke lifecycle (one undo/redo action per mouse-down .. mouse-up) ---

func _begin_stroke(target: MultiMeshInstance3D) -> void:
	_stroke_active = true
	_stroke_target = target
	_last_dab_pos = Vector3.INF
	_stroke_start_transforms = _get_transforms(target).duplicate()

func _end_stroke() -> void:
	_stroke_active = false
	if _stroke_target == null:
		return
	var before := _stroke_start_transforms
	var after: Array = _get_transforms(_stroke_target).duplicate()
	if before.size() == after.size():
		var unchanged := true
		for i in before.size():
			if before[i] != after[i]:
				unchanged = false
				break
		if unchanged:
			return

	var ur := get_undo_redo()
	ur.create_action("Paint Grass")
	ur.add_do_method(self, "_restore_transforms", _stroke_target, after)
	ur.add_undo_method(self, "_restore_transforms", _stroke_target, before)
	ur.commit_action(false)
	_stroke_target = null

## Also the do/undo callback pushed onto the UndoRedo stack above.
func _restore_transforms(target: MultiMeshInstance3D, transforms: Array) -> void:
	_apply_transforms(target, transforms)

## --- Painting ---

func _paint_at(camera: Camera3D, mouse_pos: Vector2, target: MultiMeshInstance3D) -> void:
	var hit := _raycast(camera, mouse_pos)
	if hit.is_empty():
		return
	var center: Vector3 = hit.position
	if _last_dab_pos != Vector3.INF and center.distance_to(_last_dab_pos) < dock.brush_radius * MIN_DAB_SPACING_FRACTION:
		return
	_last_dab_pos = center

	if dock.erase_mode:
		_erase_within(target, center)
	else:
		_scatter_paint(target, center, camera.get_world_3d())

func _scatter_paint(target: MultiMeshInstance3D, center: Vector3, world: World3D) -> void:
	_ensure_multimesh(target)
	var transforms := _get_transforms(target)
	var to_local := target.global_transform.affine_inverse()

	for i in dock.density:
		var angle := randf() * TAU
		var dist := sqrt(randf()) * dock.brush_radius
		var candidate := center + Vector3(cos(angle), 0.0, sin(angle)) * dist
		var ground := _probe_height(candidate, world)
		if ground.is_empty():
			continue

		var basis := Basis(Vector3.UP, randf() * TAU)
		var scale_factor := randf_range(dock.min_scale, dock.max_scale)
		basis = basis.scaled(Vector3.ONE * scale_factor)
		transforms.append(to_local * Transform3D(basis, ground.position))

	_apply_transforms(target, transforms)

func _erase_within(target: MultiMeshInstance3D, center: Vector3) -> void:
	if target.multimesh == null:
		return
	var transforms := _get_transforms(target)
	var kept: Array = []
	for t in transforms:
		var world_pos: Vector3 = target.global_transform * t.origin
		if world_pos.distance_to(center) > dock.brush_radius:
			kept.append(t)
	_apply_transforms(target, kept)

func _on_clear_requested() -> void:
	var target := dock.get_target()
	if target == null:
		return
	_begin_stroke(target)
	_apply_transforms(target, [])
	_end_stroke()

## --- Raycasting ---

func _raycast(camera: Camera3D, mouse_pos: Vector2) -> Dictionary:
	var world := camera.get_world_3d()
	if world == null:
		return {}
	var from := camera.project_ray_origin(mouse_pos)
	var to := from + camera.project_ray_normal(mouse_pos) * 4000.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return world.direct_space_state.intersect_ray(query)

## Straight down-then-up probe so scattered points within a brush dab land on
## the terrain's actual height at that XZ, not just the height of whatever
## the cursor itself was hovering.
func _probe_height(xz_point: Vector3, world: World3D) -> Dictionary:
	var from := xz_point + Vector3(0, HEIGHT_PROBE_DISTANCE, 0)
	var to := xz_point - Vector3(0, HEIGHT_PROBE_DISTANCE, 0)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return world.direct_space_state.intersect_ray(query)

## --- MultiMesh data helpers ---

func _get_transforms(target: MultiMeshInstance3D) -> Array:
	if not _transforms_cache.has(target):
		var arr: Array = []
		if target.multimesh:
			for i in target.multimesh.instance_count:
				arr.append(target.multimesh.get_instance_transform(i))
		_transforms_cache[target] = arr
	return _transforms_cache[target]

func _apply_transforms(target: MultiMeshInstance3D, transforms: Array) -> void:
	_ensure_multimesh(target)
	target.multimesh.instance_count = transforms.size()
	for i in transforms.size():
		target.multimesh.set_instance_transform(i, transforms[i])
	_transforms_cache[target] = transforms

## Public wrapper — grass_paint_dock.gd calls this right when a layer is
## created/selected (not just lazily on first paint) so its texture/color/
## wind controls always have this target's own material to edit immediately,
## before anything has actually been painted yet.
func ensure_target_ready(target: MultiMeshInstance3D) -> ShaderMaterial:
	_ensure_multimesh(target)
	return target.material_override

func _ensure_multimesh(target: MultiMeshInstance3D) -> void:
	if target.multimesh == null:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _make_grass_mesh()
		target.multimesh = mm
	if target.material_override == null:
		## A full (deep) duplicate, not the shared GRASS_MATERIAL constant
		## directly — each layer gets its own texture/colors/wind settings
		## this way. Without this, every layer pointed at the exact same
		## resource, so editing one changed every other layer too.
		target.material_override = GRASS_MATERIAL.duplicate(true)

## A simple crossed-quad ("X" of two quads) grass blade cluster — the
## standard cheap alternative to per-blade billboarding; two intersecting
## planes give reasonable coverage from every horizontal angle without the
## per-instance camera-facing math a true billboard mesh would need.
func _make_grass_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_blade_quad(st, 0.0)
	_add_blade_quad(st, PI * 0.5)
	return st.commit()

func _add_blade_quad(st: SurfaceTool, y_rotation: float) -> void:
	var basis := Basis(Vector3.UP, y_rotation)
	var bl := basis * Vector3(-GRASS_BLADE_HALF_WIDTH, 0.0, 0.0)
	var br := basis * Vector3(GRASS_BLADE_HALF_WIDTH, 0.0, 0.0)
	var tl := basis * Vector3(-GRASS_BLADE_HALF_WIDTH, GRASS_BLADE_HEIGHT, 0.0)
	var tr := basis * Vector3(GRASS_BLADE_HALF_WIDTH, GRASS_BLADE_HEIGHT, 0.0)
	st.set_normal(Vector3.UP)
	## UV.y = 0 at the tip, 1 at the root — matches grass_wind.gdshader's
	## wind_affect (pow(1.0 - uv.y, 2.0)), which sways the tip and keeps the
	## root planted.
	st.set_uv(Vector2(0, 1)); st.add_vertex(bl)
	st.set_uv(Vector2(1, 1)); st.add_vertex(br)
	st.set_uv(Vector2(1, 0)); st.add_vertex(tr)
	st.set_uv(Vector2(0, 1)); st.add_vertex(bl)
	st.set_uv(Vector2(1, 0)); st.add_vertex(tr)
	st.set_uv(Vector2(0, 0)); st.add_vertex(tl)
