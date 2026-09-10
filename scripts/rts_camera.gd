extends Node3D
## RTS camera rig: WASD/edge pan, middle-mouse-drag pan, Q/E rotate, scroll-wheel zoom.

@export var pan_speed: float = 24.0
@export var edge_pan_margin: int = 14
## Off by default: with two windows open side-by-side for multiplayer testing,
## the mouse sitting near a window's edge would otherwise pan that camera unintentionally.
@export var edge_pan_enabled: bool = false
@export var rotate_speed: float = 2.0
## How quickly panning ramps up to speed and coasts back down, as a fraction of
## the remaining gap closed per second. Also drains middle-drag movement, so a
## flick of the mouse glides to a stop instead of ending dead.
@export var pan_smoothing: float = 12.0
@export var mouse_pan_sensitivity: float = 0.05
@export var zoom_speed: float = 2.0
## How quickly zoom_distance chases the wheel's target, as a fraction of the
## remaining gap closed per second. Higher is snappier, lower is floatier.
@export var zoom_smoothing: float = 12.0
@export var min_zoom: float = 8.0
@export var max_zoom: float = 22.0
@export var pitch_degrees: float = 30.0
@export var field_of_view: float = 45.0
## Depth-of-field focus band in screen space, as fractions of the screen height
## measured from the top edge (0 = top, 1 = bottom). Ground between these two
## lines stays sharp; blur ramps in above/below over focus_ramp more of the
## screen. Converted to depths from the actual pitch/FOV/zoom (see
## _ground_depth_at), so the band keeps the same on-screen size at any zoom.
@export_range(0.0, 1.0) var focus_band_top: float = 0.2
@export_range(0.0, 1.0) var focus_band_bottom: float = 0.8
@export_range(0.01, 1.0) var focus_ramp: float = 0.15

@onready var yaw: Node3D = $Yaw
@onready var pitch: Node3D = $Yaw/Pitch
@onready var camera: Camera3D = $Yaw/Pitch/Camera3D

## Screen shake is deliberately brief — a quick jolt, not a rumble. Trauma
## decays linearly over SHAKE_DURATION and the offset falls off as its square,
## so it lands hard and settles almost immediately.
const SHAKE_DURATION: float = 0.15
const SHAKE_MAX_OFFSET: float = 0.22

var zoom_distance: float = 18.0
var _zoom_target: float = 18.0
var panning: bool = false
var _pan_velocity: Vector3 = Vector3.ZERO
var _pan_drag_pending: Vector3 = Vector3.ZERO
var _shake_trauma: float = 0.0

func _ready() -> void:
	_zoom_target = zoom_distance
	pitch.rotation_degrees.x = -pitch_degrees
	camera.fov = field_of_view
	_apply_settings(&"")
	Settings.changed.connect(_apply_settings)
	_update_zoom()

## The player's options menu choices override the exported defaults above.
func _apply_settings(_key: StringName) -> void:
	edge_pan_enabled = Settings.get_value(&"edge_pan")
	pan_speed = Settings.get_value(&"pan_speed")
	zoom_speed = Settings.get_value(&"zoom_speed")
	var attributes := camera.attributes as CameraAttributesPractical
	if attributes:
		var dof: bool = Settings.get_value(&"depth_of_field")
		attributes.dof_blur_near_enabled = dof
		attributes.dof_blur_far_enabled = dof

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_target = clamp(_zoom_target - zoom_speed, min_zoom, max_zoom)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_target = clamp(_zoom_target + zoom_speed, min_zoom, max_zoom)
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			panning = event.pressed
	elif event is InputEventMouseMotion and panning:
		## Scaled by zoom_distance so a drag covers roughly the same amount of
		## visible ground per pixel whether zoomed in or fully out.
		var forward := -yaw.transform.basis.z
		var right := yaw.transform.basis.x
		forward.y = 0.0
		right.y = 0.0
		forward = forward.normalized()
		right = right.normalized()
		var pan_amount := mouse_pan_sensitivity * zoom_distance
		_pan_drag_pending += (right * event.relative.x - forward * event.relative.y) * pan_amount

## Jolts the camera for something happening at world_pos — ignored outright if
## that point isn't in frame, so a base collapsing across the map never shakes
## a camera the player has pointed somewhere else.
func shake_at(world_pos: Vector3, amount: float) -> void:
	if not camera.is_position_in_frustum(world_pos):
		return
	_shake_trauma = clampf(maxf(_shake_trauma, amount), 0.0, 1.0)

## Offsets the camera on its own local X/Y only — Z belongs to _update_zoom(),
## and shaking the rig itself would fight panning.
func _update_shake(delta: float) -> void:
	if _shake_trauma <= 0.0:
		return
	_shake_trauma = maxf(_shake_trauma - delta / SHAKE_DURATION, 0.0)
	var strength: float = _shake_trauma * _shake_trauma * SHAKE_MAX_OFFSET
	camera.position.x = randf_range(-strength, strength)
	camera.position.y = randf_range(-strength, strength)

func _process(delta: float) -> void:
	_update_shake(delta)
	_update_zoom_smoothing(delta)

	var input_dir := Vector2.ZERO

	## Input.is_key_pressed() polls raw OS key state and ignores whatever has UI
	## focus, so without this a focused text field (e.g. chat) wouldn't stop WASD/Q/E.
	## Specifically checking for a LineEdit (not "any focused Control") matters:
	## clicking a Button (construction/production panels) leaves it focused too,
	## and Buttons don't release focus on their own, which was blocking WASD
	## panning after any button click until something else happened to steal focus.
	## An input_dir of zero still falls through to _update_pan() so a pan already
	## under way coasts to a stop rather than cutting out the moment focus moves.
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner is LineEdit:
		_update_pan(input_dir, delta)
		return

	if Settings.is_action_key_pressed(&"camera_up"):
		input_dir.y -= 1
	if Settings.is_action_key_pressed(&"camera_down"):
		input_dir.y += 1
	if Settings.is_action_key_pressed(&"camera_left"):
		input_dir.x -= 1
	if Settings.is_action_key_pressed(&"camera_right"):
		input_dir.x += 1
	if Settings.is_action_key_pressed(&"camera_rotate_left"):
		yaw.rotation.y += rotate_speed * delta
	if Settings.is_action_key_pressed(&"camera_rotate_right"):
		yaw.rotation.y -= rotate_speed * delta

	if edge_pan_enabled and input_dir.length_squared() < 0.0001:
		var mouse_pos := get_viewport().get_mouse_position()
		var vp_size := get_viewport().get_visible_rect().size
		if mouse_pos.x <= edge_pan_margin:
			input_dir.x -= 1
		elif mouse_pos.x >= vp_size.x - edge_pan_margin:
			input_dir.x += 1
		if mouse_pos.y <= edge_pan_margin:
			input_dir.y -= 1
		elif mouse_pos.y >= vp_size.y - edge_pan_margin:
			input_dir.y += 1

	_update_pan(input_dir, delta)

## Eases the rig toward the velocity the current key/edge input asks for rather
## than snapping to it, so pans start and stop with a little weight. Middle-drag
## movement is kept separate: it's already 1:1 with the mouse, so it's drained
## at the same rate instead of being fed through the velocity, which would make
## the camera lag behind the cursor.
func _update_pan(input_dir: Vector2, delta: float) -> void:
	var desired := Vector3.ZERO
	if input_dir.length_squared() > 0.0:
		input_dir = input_dir.normalized()
		var forward := -yaw.transform.basis.z
		var right := yaw.transform.basis.x
		forward.y = 0.0
		right.y = 0.0
		forward = forward.normalized()
		right = right.normalized()
		desired = (right * input_dir.x + forward * -input_dir.y) * pan_speed

	var weight := 1.0 - exp(-pan_smoothing * delta)
	_pan_velocity = _pan_velocity.lerp(desired, weight)
	if _pan_velocity.length_squared() < 0.0001:
		_pan_velocity = desired

	var drag_step := _pan_drag_pending * weight
	_pan_drag_pending -= drag_step
	if _pan_drag_pending.length_squared() < 0.000001:
		_pan_drag_pending = Vector3.ZERO

	global_position += _pan_velocity * delta + drag_step

## View-space depth of the ground (at pivot height) seen through the given
## screen row (0 = top edge, 1 = bottom edge). Rows that look at or above the
## horizon never hit the ground, so they're clamped to the camera's far plane.
func _ground_depth_at(screen_y: float) -> float:
	var pitch_rad := deg_to_rad(pitch_degrees)
	var height := zoom_distance * sin(pitch_rad)
	var ray_offset := atan((screen_y * 2.0 - 1.0) * tan(deg_to_rad(field_of_view) * 0.5))
	var ray_dip := pitch_rad + ray_offset
	if ray_dip <= deg_to_rad(1.0):
		return camera.far
	return minf(height * cos(ray_offset) / sin(ray_dip), camera.far)

## Eases zoom_distance toward the wheel's target. exp() rather than a plain
## lerp so the approach rate is the same regardless of framerate.
func _update_zoom_smoothing(delta: float) -> void:
	if is_equal_approx(zoom_distance, _zoom_target):
		return
	var weight := 1.0 - exp(-zoom_smoothing * delta)
	zoom_distance = lerpf(zoom_distance, _zoom_target, weight)
	## Snap the last sliver so the DOF update (and the early-out above) settle
	## instead of creeping toward the target forever.
	if absf(_zoom_target - zoom_distance) < 0.001:
		zoom_distance = _zoom_target
	_update_zoom()

func _update_zoom() -> void:
	camera.position.z = zoom_distance
	## Re-fits the depth-of-field band to the screen-space focus lines as the
	## player zooms, for a tilt-shift/diorama look at any zoom level. Godot's
	## blur starts at each distance and reaches full strength one transition
	## further out (toward the camera for near, away for far).
	var attributes := camera.attributes as CameraAttributesPractical
	if attributes:
		var far_start := _ground_depth_at(focus_band_top)
		var far_full := _ground_depth_at(maxf(focus_band_top - focus_ramp, 0.0))
		var near_start := _ground_depth_at(focus_band_bottom)
		var near_full := _ground_depth_at(minf(focus_band_bottom + focus_ramp, 1.0))
		attributes.dof_blur_far_distance = far_start
		attributes.dof_blur_far_transition = maxf(far_full - far_start, 0.01)
		attributes.dof_blur_near_distance = near_start
		attributes.dof_blur_near_transition = maxf(near_start - near_full, 0.01)
