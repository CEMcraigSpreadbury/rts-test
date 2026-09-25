class_name CloudShadows
extends Decal
## Slow-drifting cloud shadows. These used to be a noise plane high above the
## map that cast real shadows through the sun, but the sun's shadow cascades
## cut a plane that large off in hard lines that moved with the camera. This
## decal darkens whatever sits under it instead: terrain, grass, trees,
## buildings and unit sprites alike.
##
## Emission-baked models (see baked_emission.gdshader, team_color.gdshaderinc)
## ignore albedo, so they read the same texture through the cloud_shadow_*
## shader globals and darken themselves by the same amount
## (see util/cloud_shade.gdshaderinc).

## Width of the square of ground the clouds must always cover, centered on
## this node.
@export var cover_size: float = 320.0
## How far the decal drifts either side of its start before fading out and
## starting over. The decal is this much bigger on every side than cover_size.
@export var drift_margin: float = 240.0
## World-space noise frequency: bigger = smaller clouds.
@export var cloud_frequency: float = 0.06
## Noise value (0-1) where ground turns from clear to shadowed: higher means
## less of the map under cloud.
@export_range(0.0, 1.0) var cloud_threshold: float = 0.6
## Half-width of the noise band over which a shadow's edge fades in.
@export_range(0.0, 0.5) var edge_softness: float = 0.06
## How much a fully shadowed surface is darkened. Baked into the texture's
## alpha rather than albedo_mix, whose falloff is so steep below 1.0 that
## 0.5 barely shows at all.
@export_range(0.0, 1.0) var strength: float = 0.8
## World units/second the clouds drift along world X/Z.
@export var scroll_speed: Vector2 = Vector2(0.55, -0.1)
@export var texture_size: int = 2048

const FADE_TIME: float = 3.0
const BOX_HEIGHT: float = 400.0

var _origin: Vector3
var _drift: Vector2
var _fading: bool = false


func _ready() -> void:
	var extent: float = cover_size + drift_margin * 2.0
	size = Vector3(extent, BOX_HEIGHT, extent)
	upper_fade = 0.0
	lower_fade = 0.0
	normal_fade = 0.0
	albedo_mix = 1.0
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
	## Generated on a thread; assigned once it's done so the decal atlas picks
	## up the finished image rather than the empty placeholder.
	await tex.changed
	texture_albedo = tex


func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set(&"cloud_shadow_strength", 0.0)


func _process(delta: float) -> void:
	_drift += scroll_speed * delta
	if not _fading and _drift.length() > drift_margin:
		_restart_drift()
	position = _origin + Vector3(_drift.x, 0.0, _drift.y)

	var shown: bool = is_visible_in_tree() and texture_albedo != null
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
