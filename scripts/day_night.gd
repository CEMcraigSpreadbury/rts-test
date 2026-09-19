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
## Nothing here animates per frame: a single tween drives one 0..1 value and
## everything the time of day touches is re-derived from it (see refresh_lighting).
## Rain dims the sun on top of that, so both go through refresh_lighting rather than
## writing to the light themselves.

var main: Main

## How long each phase lasts. Night is the shorter half of the cycle.
const DAY_DURATION: float = 360.0
const NIGHT_DURATION: float = 150.0
## How long the sky takes to turn over, rather than switching.
const FADE_DURATION: float = 25.0

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
	if _sun:
		_day_sun_color = _sun.light_color
		_day_sun_energy = _sun.light_energy
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
	if not multiplayer.is_server():
		return
	_time_to_change -= delta
	if _time_to_change <= 0.0:
		set_night(not is_night)

## Host only. Also restarts the clock, so a night started by "cmd day" runs a
## normal length before the sun comes back up.
func set_night(night: bool) -> void:
	if not multiplayer.is_server():
		return
	_time_to_change = NIGHT_DURATION if night else DAY_DURATION
	if night != is_night:
		_rpc_set_night.rpc(night)

@rpc("authority", "call_local", "reliable")
func _rpc_set_night(night: bool) -> void:
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

## Re-derives everything the time of day drives. Called again by Weather when
## a shower comes or goes, since rain dims the same sun.
func refresh_lighting() -> void:
	var t: float = night_amount
	if _sun:
		_sun.light_color = _day_sun_color.lerp(MOON_COLOR, t)
		var rain_scale: float = main.weather.sun_energy_scale if main and main.weather else 1.0
		_sun.light_energy = _day_sun_energy * lerpf(1.0, NIGHT_SUN_ENERGY_SCALE, t) * rain_scale
	if _fill:
		_fill.light_energy = _day_fill_energy * lerpf(1.0, NIGHT_FILL_ENERGY_SCALE, t)
	if _environment:
		_environment.ambient_light_energy = _day_ambient_energy * lerpf(1.0, NIGHT_AMBIENT_ENERGY_SCALE, t)
		_environment.background_energy_multiplier = _day_sky_energy * lerpf(1.0, NIGHT_SKY_ENERGY_SCALE, t)
		_environment.volumetric_fog_albedo = _day_fog_albedo.lerp(NIGHT_FOG_ALBEDO, t)
		_environment.adjustment_saturation = _day_saturation * lerpf(1.0, NIGHT_SATURATION_SCALE, t)
	if _sky_material:
		_sky_material.sky_top_color = _day_sky_top.lerp(NIGHT_SKY_TOP, t)
		_sky_material.sky_horizon_color = _day_sky_horizon.lerp(NIGHT_SKY_HORIZON, t)
		_sky_material.ground_bottom_color = _day_ground_bottom.lerp(NIGHT_GROUND_BOTTOM, t)
		_sky_material.ground_horizon_color = _day_ground_horizon.lerp(NIGHT_GROUND_HORIZON, t)
	## One write for every unit on the map, however many there are.
	RenderingServer.global_shader_parameter_set(UNIT_NIGHT_LIFT, t)
