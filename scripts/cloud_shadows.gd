class_name CloudShadows
extends Decal
## Slow-drifting cloud shadows: a noise texture laid over the map and drifted
## with the wind. Nothing draws it; every lit surface reads it through the
## cloud_shadow_* shader globals and takes the sun away where a cloud covers it
## (see util/cloud_shade.gdshaderinc) -- the ground, buildings, trees and
## figures alike, so a unit walking into a cloud's shade darkens with the
## grass under it.
##
## A real shadow-casting plane can't give this: the sun's shadow map makes its
## shade all-or-nothing, and a moving edge steps a shadow texel at a time.
## The Decal is only a node to hang this on; it is given no texture.

## Width of the square of ground the clouds must always cover, centered on
## this node.
@export var cover_size: float = 320.0
## How far the decal drifts either side of its start before fading out and
## starting over. The decal is this much bigger on every side than cover_size.
@export var drift_margin: float = 240.0
## World-space noise frequency: bigger = smaller clouds.
@export var cloud_frequency: float = 0.04
## Noise value (0-1) where ground turns from clear to shadowed: higher means
## less of the map under cloud. 0.7 leaves a few clouds in any view, never
## blotches all over the field.
@export_range(0.0, 1.0) var cloud_threshold: float = 0.7
## Half-width of the noise band over which a shadow's edge fades in.
@export_range(0.0, 0.5) var edge_softness: float = 0.06
## The texture's alpha under a full cloud. Kept in step with CLOUD_STRENGTH
## in util/cloud_shade.gdshaderinc, which divides it back out.
@export_range(0.0, 1.0) var strength: float = 0.35
## World units/second the clouds drift along world X/Z.
@export var scroll_speed: Vector2 = Vector2(0.55, -0.1)
@export var texture_size: int = 2048

const FADE_TIME: float = 3.0
const BOX_HEIGHT: float = 400.0

var _origin: Vector3
var _drift: Vector2
var _fading: bool = false
var _ready_tex: bool = false
var _sun: DirectionalLight3D


func _ready() -> void:
	var extent: float = cover_size + drift_margin * 2.0
	size = Vector3(extent, BOX_HEIGHT, extent)
	upper_fade = 0.0
	lower_fade = 0.0
	normal_fade = 0.0
	_sun = get_parent().get_node_or_null(^"DirectionalLight3D") as DirectionalLight3D
	_origin = position
	_drift = _drift_start()

	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_octaves = 3
	noise.seed = 1337
	## FastNoiseLite's frequency is per texel, so it scales with how much
	## ground each texel covers to keep cloud sizes fixed in world space.
	noise.frequency = cloud_frequency * extent / texture_size

	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([cloud_threshold - edge_softness, cloud_threshold + edge_softness])
	ramp.colors = PackedColorArray([Color(0.03, 0.05, 0.1, 0), Color(0.03, 0.05, 0.1, strength)])

	var tex := NoiseTexture2D.new()
	tex.width = texture_size
	tex.height = texture_size
	tex.noise = noise
	tex.color_ramp = ramp
	RenderingServer.global_shader_parameter_set(&"cloud_shadow_tex", tex)
	## Generated on a thread; the shade waits for the finished image.
	await tex.changed
	_ready_tex = true


func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set(&"cloud_shadow_strength", 0.0)


func _process(delta: float) -> void:
	_drift += scroll_speed * delta
	if not _fading and _drift.length() > drift_margin:
		_restart_drift()
	position = _origin + Vector3(_drift.x, 0.0, _drift.y)

	if _sun:
		RenderingServer.global_shader_parameter_set(&"cloud_sun_dir", _sun.global_basis.z)
	var shown: bool = is_visible_in_tree() and _ready_tex
	RenderingServer.global_shader_parameter_set(&"cloud_shadow_rect",
			Vector4(position.x - size.x * 0.5, position.z - size.z * 0.5, size.x, size.z))
	RenderingServer.global_shader_parameter_set(&"cloud_shadow_strength",
			modulate.a if shown else 0.0)


## Starts upwind so the whole margin gets used before the first restart.
func _drift_start() -> Vector2:
	return -scroll_speed.normalized() * drift_margin


func _restart_drift() -> void:
	_fading = true
	var tween := create_tween()
	tween.tween_property(self, ^"modulate:a", 0.0, FADE_TIME)
	tween.tween_callback(func() -> void: _drift = _drift_start())
	tween.tween_property(self, ^"modulate:a", 1.0, FADE_TIME)
	tween.tween_callback(func() -> void: _fading = false)
