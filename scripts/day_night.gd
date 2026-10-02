class_name DayNight
extends Node
## A day that slowly turns to night and back. The host rolls the clock and
## broadcasts each change, so every peer sees the same time of day; the
## lighting itself is purely local.
##
## Created by Main._enter_tree() under a fixed name, so its RPCs resolve to
## the same node path on every peer. Every peer swaps into the match at the
## same moment (see SceneLoader.start_match) and starts at midday, so there's
## no state to catch a late joiner up on.
##
## Nothing here animates per frame: a single tween drives one 0..1 value, the
## sun's height and warmth follow the clock in half-second steps, and everything
## the time of day touches is re-derived from those (see refresh_lighting).
## Rain dims the sun on top of that, so both go through refresh_lighting rather than
## writing to the light themselves.

var main: Main

## How long each phase lasts. Night is the shorter half of the cycle.
const DAY_DURATION: float = 240.0
const NIGHT_DURATION: float = 150.0
## How long the sky takes to turn over, rather than switching.
const FADE_DURATION: float = 25.0

## The sun climbs through the morning, holds, then sinks and warms toward
## sunset, so the day can be seen passing; it used to sit still all day and
## change only in the fade. Only its height moves: its bearing follows the
## camera (light_follow_camera_yaw.gd) so sprites stay lit from the front.
## Degrees above the horizon; noon is the map's own authored height.
const MORNING_SUN_HEIGHT: float = 40.0
const EVENING_SUN_HEIGHT: float = 30.0
## Shares of the day spent climbing, and where it starts to sink.
const MORNING_END: float = 0.3
const AFTERNOON_END: float = 0.6
## A lower sun lights the ground more weakly; this much of that is made up in
## energy, so evening dims a little without the map going dark.
const SUN_HEIGHT_COMPENSATION: float = 0.6
## What the sun and the horizon lean toward at sunset, and how far (dawn gets
## a lighter touch of the same).
const EVENING_SUN_COLOR: Color = Color(1.0, 0.68, 0.45, 1.0)
const EVENING_SKY_HORIZON: Color = Color(1.0, 0.72, 0.52, 1.0)
const EVENING_WARMTH: float = 0.7
const MORNING_WARMTH: float = 0.25
const EVENING_SKY_WARMTH: float = 0.6
## Game seconds between time-of-day lighting updates. Not every frame: a
## changed sky re-renders its radiance.
const TIME_OF_DAY_STEP: float = 0.5

## Moonlight: the sun keeps its direction and picks up a cool cast instead.
const MOON_COLOR: Color = Color(0.5, 0.63, 1.0)
const NIGHT_SUN_ENERGY_SCALE: float = 0.34
const NIGHT_FILL_ENERGY_SCALE: float = 0.7
const NIGHT_AMBIENT_ENERGY_SCALE: float = 0.55
## The sky is the brightest thing on screen by far, so it has to come down
## much harder than the lights for night to read as night.
const NIGHT_SKY_ENERGY_SCALE: float = 0.25
const NIGHT_SKY_TOP: Color = Color(0.03, 0.05, 0.14, 1.0)
const NIGHT_SKY_HORIZON: Color = Color(0.1, 0.14, 0.26, 1.0)
const NIGHT_GROUND_BOTTOM: Color = Color(0.02, 0.03, 0.06, 1.0)
const NIGHT_GROUND_HORIZON: Color = Color(0.08, 0.11, 0.2, 1.0)
## The god rays go from warm dust to cold haze.
const NIGHT_FOG_ALBEDO: Color = Color(0.6, 0.7, 1.0, 1.0)
## Colour drains out of what little there is to see at night.
const NIGHT_SATURATION_SCALE: float = 0.85

## Unit sprites get their own moonlight added back on top, so they stay
## readable against dark ground without a real light per unit. Read by
## shaders/unit_night_lift.gdshader; see unit_silhouette_material.gd.
const UNIT_NIGHT_LIFT: StringName = &"unit_night_lift"

var is_night: bool = false
## 0 = full day, 1 = full night; everything else is derived from it.
var night_amount: float = 0.0
## Host only: counts down to the next sunset/sunrise.
var _time_to_change: float = 0.0
## Days begun, the first included. Each peer counts its own sunrises.
var day_number: int = 1
## Game seconds into the current day or night, kept on every peer: each one
## restarts it on the same RPC, which is what lets the clock run everywhere.
var _phase_elapsed: float = 0.0
var _time_of_day_timer: float = 0.0
var _noon_sun_height: float = 50.0

var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
var _environment: Environment
var _sky_material: ProceduralSkyMaterial
var _fade_tween: Tween

## The authored day values, kept so every frame's lighting is a fresh lerp
## from them rather than a drift away from wherever the last one landed.
var _day_sun_color: Color
var _day_sun_energy: float = 1.0
var _day_fill_energy: float = 1.0
var _day_ambient_energy: float = 1.0
var _day_sky_energy: float = 1.0
var _day_sky_top: Color
var _day_sky_horizon: Color
var _day_ground_bottom: Color
var _day_ground_horizon: Color
var _day_fog_albedo: Color
var _day_saturation: float = 1.0

## Called from Main._ready(), once the map's lights and environment exist.
func setup() -> void:
	_sun = main.get_node_or_null(^"DirectionalLight3D") as DirectionalLight3D
	_fill = main.get_node_or_null(^"FillLight") as DirectionalLight3D
	var world_env := main.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	if world_env and world_env.environment:
		## Copied rather than written through: the map scene's Environment is
		## shared by every instance of it, so a match that ended at night would
		## otherwise hand the next one its sky.
		_environment = world_env.environment.duplicate(true)
		world_env.environment = _environment
		_sky_material = _environment.sky.sky_material as ProceduralSkyMaterial if _environment.sky else null
		## Before the day values below are taken, so night scales from these.
		CompatLighting.apply(_environment)
	if _sun:
		_day_sun_color = _sun.light_color
		_day_sun_energy = _sun.light_energy
		_noon_sun_height = -_sun.rotation_degrees.x
	if _fill:
		_day_fill_energy = _fill.light_energy
	if _environment:
		_day_ambient_energy = _environment.ambient_light_energy
		_day_sky_energy = _environment.background_energy_multiplier
		_day_fog_albedo = _environment.volumetric_fog_albedo
		_day_saturation = _environment.adjustment_saturation
	if _sky_material:
		_day_sky_top = _sky_material.sky_top_color
		_day_sky_horizon = _sky_material.sky_horizon_color
		_day_ground_bottom = _sky_material.ground_bottom_color
		_day_ground_horizon = _sky_material.ground_horizon_color
	refresh_lighting()
	if multiplayer.is_server():
		_time_to_change = DAY_DURATION

func _process(delta: float) -> void:
	_phase_elapsed += delta
	_time_of_day_timer -= delta
	if _time_of_day_timer <= 0.0:
		_time_of_day_timer = TIME_OF_DAY_STEP
		refresh_lighting()
	if not multiplayer.is_server():
		return
	_time_to_change -= delta
	if _time_to_change <= 0.0:
		set_night(not is_night)

## Host only. Also restarts the clock, so a night started by "cmd day" runs a
## normal length before the sun comes back up. Sent even when it is already
## that time, so every peer's clock restarts with the host's.
func set_night(night: bool) -> void:
	if not multiplayer.is_server():
		return
	_time_to_change = NIGHT_DURATION if night else DAY_DURATION
	_rpc_set_night.rpc(night)

## 0..1 through the current day, or the current night.
func phase_progress() -> float:
	return clampf(_phase_elapsed / (NIGHT_DURATION if is_night else DAY_DURATION), 0.0, 1.0)

## The day's share of a whole day and night.
static func day_share() -> float:
	return DAY_DURATION / (DAY_DURATION + NIGHT_DURATION)

## 0..1 round a whole day and night, from sunrise: the day fills the first
## day_share() of it.
func cycle_fraction() -> float:
	if is_night:
		return day_share() + phase_progress() * (1.0 - day_share())
	return phase_progress() * day_share()

@rpc("authority", "call_local", "reliable")
func _rpc_set_night(night: bool) -> void:
	_phase_elapsed = 0.0
	if night == is_night:
		refresh_lighting()
		return
	if not night:
		day_number += 1
	is_night = night
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween()
	## Shortened when the sky is already part-way over, so cutting a fade
	## short and turning back doesn't crawl.
	var target: float = 1.0 if night else 0.0
	var remaining: float = FADE_DURATION * absf(target - night_amount)
	_fade_tween.tween_method(_set_night_amount, night_amount, target, remaining)

func _set_night_amount(value: float) -> void:
	night_amount = value
	refresh_lighting()

## Degrees above the horizon. At night the moon rides back up the same arc,
## so dawn begins where the morning sun does.
func _sun_height() -> float:
	var p: float = phase_progress()
	if is_night:
		return lerpf(EVENING_SUN_HEIGHT, MORNING_SUN_HEIGHT, p)
	if p < MORNING_END:
		return lerpf(MORNING_SUN_HEIGHT, _noon_sun_height, smoothstep(0.0, MORNING_END, p))
	if p < AFTERNOON_END:
		return _noon_sun_height
	return lerpf(_noon_sun_height, EVENING_SUN_HEIGHT, smoothstep(AFTERNOON_END, 1.0, p))

## 0 = the authored daylight, 1 = full sunset colour. Fades out with the light
## as night falls, so nothing jumps when the fade starts.
func _warmth() -> float:
	var p: float = phase_progress()
	if is_night:
		return EVENING_WARMTH * (1.0 - night_amount)
	if p < MORNING_END:
		return MORNING_WARMTH * (1.0 - p / MORNING_END)
	if p < AFTERNOON_END:
		return 0.0
	var q: float = (p - AFTERNOON_END) / (1.0 - AFTERNOON_END)
	return EVENING_WARMTH * q * q

## Re-derives everything the time of day drives. Called again by Weather when
## a shower comes or goes, since rain dims the same sun.
func refresh_lighting() -> void:
	var t: float = night_amount
	var warmth: float = _warmth()
	if _sun:
		_sun.light_color = _day_sun_color.lerp(EVENING_SUN_COLOR, warmth).lerp(MOON_COLOR, t)
		var height: float = _sun_height()
		_sun.rotation_degrees.x = -height
		var low_sun: float = sin(deg_to_rad(_noon_sun_height)) / sin(deg_to_rad(height))
		var rain_scale: float = main.weather.sun_energy_scale if main and main.weather else 1.0
		_sun.light_energy = _day_sun_energy * lerpf(1.0, low_sun, SUN_HEIGHT_COMPENSATION) \
				* lerpf(1.0, NIGHT_SUN_ENERGY_SCALE, t) * rain_scale
	if _fill:
		_fill.light_energy = _day_fill_energy * lerpf(1.0, NIGHT_FILL_ENERGY_SCALE, t)
	if _environment:
		_environment.ambient_light_energy = _day_ambient_energy * lerpf(1.0, NIGHT_AMBIENT_ENERGY_SCALE, t)
		var sky_energy: float = _day_sky_energy * lerpf(1.0, NIGHT_SKY_ENERGY_SCALE, t)
		if _environment.background_energy_multiplier != sky_energy:
			_environment.background_energy_multiplier = sky_energy
		_environment.volumetric_fog_albedo = _day_fog_albedo.lerp(NIGHT_FOG_ALBEDO, t)
		if CompatLighting.is_active():
			## Its flat stand-in haze is lit by nothing, so it dims with the sun.
			_environment.fog_light_color = CompatLighting.FOG_COLOR.lerp(NIGHT_FOG_ALBEDO * NIGHT_SUN_ENERGY_SCALE, t)
		_environment.adjustment_saturation = _day_saturation * lerpf(1.0, NIGHT_SATURATION_SCALE, t)
	if _sky_material:
		_set_sky(&"sky_top_color", _day_sky_top.lerp(NIGHT_SKY_TOP, t))
		_set_sky(&"sky_horizon_color", _day_sky_horizon.lerp(EVENING_SKY_HORIZON, warmth * EVENING_SKY_WARMTH).lerp(NIGHT_SKY_HORIZON, t))
		_set_sky(&"ground_bottom_color", _day_ground_bottom.lerp(NIGHT_GROUND_BOTTOM, t))
		_set_sky(&"ground_horizon_color", _day_ground_horizon.lerp(NIGHT_GROUND_HORIZON, t))
	## One write for every unit on the map, however many there are.
	RenderingServer.global_shader_parameter_set(UNIT_NIGHT_LIFT, t)

## Only real changes reach the sky: the lighting is refreshed all day long, and
## a changed sky re-renders its radiance.
func _set_sky(property: StringName, value: Color) -> void:
	if _sky_material.get(property) != value:
		_sky_material.set(property, value)
