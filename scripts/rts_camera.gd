extends Node3D
## RTS camera rig: WASD/edge pan, middle-mouse-drag or Q/E rotate, scroll-wheel zoom.

@export var pan_speed: float = 24.0
@export var edge_pan_margin: int = 14
## Off by default: with two windows open side-by-side for multiplayer testing,
## the mouse sitting near a window's edge would otherwise pan that camera unintentionally.
@export var edge_pan_enabled: bool = false
@export var rotate_speed: float = 2.0
@export var mouse_rotate_sensitivity: float = 0.005
@export var zoom_speed: float = 2.0
@export var min_zoom: float = 8.0
@export var max_zoom: float = 32.0
@export var pitch_degrees: float = 55.0
@export var min_pitch_degrees: float = 20.0
@export var max_pitch_degrees: float = 85.0
@export var mouse_pitch_sensitivity: float = 0.15

@onready var yaw: Node3D = $Yaw
@onready var pitch: Node3D = $Yaw/Pitch
@onready var camera: Camera3D = $Yaw/Pitch/Camera3D

var zoom_distance: float = 18.0
var rotating: bool = false
var current_pitch: float = 55.0

func _ready() -> void:
	current_pitch = pitch_degrees
	pitch.rotation_degrees.x = -current_pitch
	_update_zoom()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_distance = clamp(zoom_distance - zoom_speed, min_zoom, max_zoom)
			_update_zoom()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_distance = clamp(zoom_distance + zoom_speed, min_zoom, max_zoom)
			_update_zoom()
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			rotating = event.pressed
	elif event is InputEventMouseMotion and rotating:
		yaw.rotation.y -= event.relative.x * mouse_rotate_sensitivity
		current_pitch = clamp(current_pitch + event.relative.y * mouse_pitch_sensitivity, min_pitch_degrees, max_pitch_degrees)
		pitch.rotation_degrees.x = -current_pitch

func _process(delta: float) -> void:
	## Input.is_key_pressed() polls raw OS key state and ignores whatever has UI
	## focus, so without this a focused text field (e.g. chat) wouldn't stop WASD/Q/E.
	## Specifically checking for a LineEdit (not "any focused Control") matters:
	## clicking a Button (construction/production panels) leaves it focused too,
	## and Buttons don't release focus on their own, which was blocking WASD
	## panning after any button click until something else happened to steal focus.
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner is LineEdit:
		return

	var input_dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W):
		input_dir.y -= 1
	if Input.is_key_pressed(KEY_S):
		input_dir.y += 1
	if Input.is_key_pressed(KEY_A):
		input_dir.x -= 1
	if Input.is_key_pressed(KEY_D):
		input_dir.x += 1
	if Input.is_key_pressed(KEY_Q):
		yaw.rotation.y += rotate_speed * delta
	if Input.is_key_pressed(KEY_E):
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

	if input_dir.length_squared() > 0.0:
		input_dir = input_dir.normalized()
		var forward := -yaw.transform.basis.z
		var right := yaw.transform.basis.x
		forward.y = 0.0
		right.y = 0.0
		forward = forward.normalized()
		right = right.normalized()
		global_position += (right * input_dir.x + forward * -input_dir.y) * pan_speed * delta

func _update_zoom() -> void:
	camera.position.z = zoom_distance
