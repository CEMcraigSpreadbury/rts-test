extends DirectionalLight3D
## Keeps this light's azimuth locked to the camera's yaw so billboarded
## sprites (which face the camera) also face the light during the shadow
## pass, instead of casting a distorted shadow that rotates independently.

@export var camera_yaw_path: NodePath
@export var yaw_offset_degrees: float = 35.0

@onready var camera_yaw: Node3D = get_node_or_null(camera_yaw_path)

func _process(_delta: float) -> void:
	if camera_yaw:
		rotation_degrees.y = camera_yaw.rotation_degrees.y + yaw_offset_degrees
