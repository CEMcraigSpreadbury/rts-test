class_name Weather
extends Node
## Rain that comes and goes on its own. The host rolls when it starts and stops
## and broadcasts each change, so every peer sees the same weather; the drops
## themselves are purely local visuals.
##
## Created by Main._enter_tree() under a fixed name, so its RPCs resolve to
## the same node path on every peer. Every peer swaps into the match at the
## same moment (see SceneLoader.start_match) and starts dry, so there's no
## state to catch a late joiner up on.
##
## Kept cheap: one GPUParticles3D riding along under the camera instead of
## covering the whole map, drawn as flat unshaded streaks with no collision or
## shadows, and switched off entirely (not just emitting nothing) while dry.

var main: Main

## Seconds between showers / how long one lasts, rolled fresh each time.
const DRY_DURATION_MIN: float = 240.0
const DRY_DURATION_MAX: float = 600.0
const RAIN_DURATION_MIN: float = 90.0
const RAIN_DURATION_MAX: float = 240.0
## How long the drops take to thicken up or thin out, rather than switching.
const FADE_DURATION: float = 4.0
## The sun is dimmed to this fraction of its authored energy at full rain.
const SUN_ENERGY_IN_RAIN: float = 0.6

## Covers the ground the camera can see at max zoom (see RtsCamera.max_zoom).
const AREA_HALF_EXTENT: float = 30.0
## Drops spawn anywhere in a band this tall, centred this far above the
## camera's ground pivot — not in a thin sheet at the top. The band is what
## follows the camera, so panning moves into air that is already full of rain
## instead of into a dry gap waiting for the first drops to fall down into it.
const EMIT_CENTER_HEIGHT: float = 10.0
const EMIT_BAND_HALF_HEIGHT: float = 5.0
## Higher than the drops actually on screen: ones spawned low in the band spend
## most of their life below the ground, hidden behind the terrain.
const DROP_COUNT: int = 1400
const DROP_SPEED: float = 20.0
## Long enough that a drop born at the top of the band still reaches the
## ground rather than stopping in mid-air.
const DROP_LIFETIME: float = 0.8
## How far each shower can lean off vertical, as a fraction of its fall speed
## (0.35 is about 19 degrees). The heading it leans towards is rolled fresh
## every time, so no two showers blow the same way.
const WIND_TILT_MIN: float = 0.1
const WIND_TILT_MAX: float = 0.35
const DROP_SIZE: Vector2 = Vector2(0.025, 0.7)
const DROP_COLOR: Color = Color(0.78, 0.84, 0.92, 0.35)
const DROP_SHADER: Shader = preload("res://shaders/rain_drop.gdshader")

## Looped in its import settings, so it plays for as long as the shower does.
const RAIN_SOUND: AudioStream = preload("res://assets/sfx/Ambient Sounds/rain.wav")
## Volume at full rain; it fades up from silence alongside the drops.
const RAIN_VOLUME_DB: float = -6.0
const SILENT_DB: float = -60.0

var is_raining: bool = false
## Host only: counts down to the next start/stop.
var _time_to_change: float = 0.0

var _particles: GPUParticles3D
var _sound: AudioStreamPlayer
var _sun: DirectionalLight3D
var _sun_energy: float = 1.0
var _intensity: float = 0.0
var _fade_tween: Tween

## Called from Main._ready(), once the camera rig and lights exist.
func setup() -> void:
	_sun = main.get_node_or_null(^"DirectionalLight3D") as DirectionalLight3D
	if _sun:
		_sun_energy = _sun.light_energy
	_particles = _build_particles()
	main.add_child(_particles)
	## Same bus as AmbiencePlayer, so the ambience volume slider covers it.
	_sound = AudioStreamPlayer.new()
	_sound.name = "RainSound"
	_sound.stream = RAIN_SOUND
	_sound.bus = &"Ambience"
	_sound.volume_db = SILENT_DB
	main.add_child(_sound)
	if multiplayer.is_server():
		_time_to_change = randf_range(DRY_DURATION_MIN, DRY_DURATION_MAX)

func _process(delta: float) -> void:
	if _particles.visible:
		## Only the emission band is moved; the drops themselves are in world
		## space (see local_coords), so the camera travels through the rain.
		_particles.global_position = main.camera_rig.global_position + Vector3(0.0, EMIT_CENTER_HEIGHT, 0.0)
	if not multiplayer.is_server():
		return
	_time_to_change -= delta
	if _time_to_change <= 0.0:
		set_raining(not is_raining)

## Host only. Also restarts the countdown, so a shower started by "cmd rain"
## runs a normal length before clearing up by itself.
func set_raining(raining: bool) -> void:
	if not multiplayer.is_server():
		return
	_time_to_change = randf_range(RAIN_DURATION_MIN, RAIN_DURATION_MAX) if raining \
			else randf_range(DRY_DURATION_MIN, DRY_DURATION_MAX)
	if raining != is_raining:
		## Rolled here, on the host, and sent with the change so every peer's
		## rain leans the same way for the whole shower.
		_rpc_set_raining.rpc(raining, randf_range(0.0, TAU), randf_range(WIND_TILT_MIN, WIND_TILT_MAX))

@rpc("authority", "call_local", "reliable")
func _rpc_set_raining(raining: bool, wind_heading: float, wind_tilt: float) -> void:
	is_raining = raining
	if _fade_tween:
		_fade_tween.kill()
	if raining:
		var wind := Vector3(sin(wind_heading) * wind_tilt, -1.0, cos(wind_heading) * wind_tilt)
		(_particles.process_material as ParticleProcessMaterial).direction = wind.normalized()
		_particles.visible = true
		_particles.emitting = true
		if not _sound.playing:
			_sound.play()
	_fade_tween = create_tween()
	_fade_tween.tween_method(_set_intensity, _intensity, 1.0 if raining else 0.0, FADE_DURATION)
	if not raining:
		## Let the last drops land before switching the system off.
		_fade_tween.tween_interval(DROP_LIFETIME)
		_fade_tween.tween_callback(func() -> void:
			_particles.emitting = false
			_particles.visible = false
			_sound.stop()
		)

func _set_intensity(value: float) -> void:
	_intensity = value
	_particles.amount_ratio = value
	_sound.volume_db = lerpf(SILENT_DB, RAIN_VOLUME_DB, sqrt(value))
	if _sun:
		_sun.light_energy = _sun_energy * lerpf(1.0, SUN_ENERGY_IN_RAIN, value)

func _build_particles() -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(AREA_HALF_EXTENT, EMIT_BAND_HALF_HEIGHT, AREA_HALF_EXTENT)
	## Replaced with the shower's own wind direction each time it starts.
	process.direction = Vector3.DOWN
	process.spread = 0.0
	process.initial_velocity_min = DROP_SPEED * 0.9
	process.initial_velocity_max = DROP_SPEED * 1.1
	process.gravity = Vector3.ZERO
	## Points each drop's own Y down its velocity, which rain_drop.gdshader
	## then builds the streak along.
	process.particle_flag_align_y = true

	var material := ShaderMaterial.new()
	material.shader = DROP_SHADER
	material.set_shader_parameter(&"drop_color", DROP_COLOR)

	var quad := QuadMesh.new()
	quad.size = DROP_SIZE
	quad.material = material

	var particles := GPUParticles3D.new()
	particles.name = "Rain"
	particles.amount = DROP_COUNT
	particles.amount_ratio = 0.0
	particles.lifetime = DROP_LIFETIME
	particles.randomness = 0.3
	## Drops fall in world space and are left behind as the camera moves,
	## rather than being dragged along with it.
	particles.local_coords = false
	particles.process_material = process
	particles.draw_pass_1 = quad
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	## Generous on all sides: with world-space drops this box has to hold
	## everything still falling behind the camera as it pans away.
	var margin: float = AREA_HALF_EXTENT + DROP_SPEED * DROP_LIFETIME
	particles.visibility_aabb = AABB(
			Vector3(-margin, -EMIT_CENTER_HEIGHT - DROP_SPEED * DROP_LIFETIME, -margin),
			Vector3(margin * 2.0, EMIT_CENTER_HEIGHT + EMIT_BAND_HALF_HEIGHT + DROP_SPEED * DROP_LIFETIME, margin * 2.0))
	particles.emitting = false
	particles.visible = false
	return particles
