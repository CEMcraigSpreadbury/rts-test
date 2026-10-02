class_name CompatLighting
## The web build renders with the Compatibility renderer, which lights the same
## Environment far brighter than Forward+: it has no volumetric fog or SSAO to
## take light away, and it tonemaps the sun's shadowed pass separately from the
## rest, so ACES and glow bloom stack up and wash the scene out. apply() swaps
## in settings matched by eye against Forward+ captures of the shared map
## environment (scenes/map_base.tscn, which the menu diorama copies). A no-op
## on Forward+.

## The stand-in fog's colour at full day; DayNight dims it toward night.
const FOG_COLOR: Color = Color(0.45, 0.5, 0.45)

static func is_active() -> bool:
	return RenderingServer.get_current_rendering_method() == "gl_compatibility"

static func apply(env: Environment) -> void:
	if env == null or not is_active():
		return
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 0.6
	env.glow_bloom = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.55
	env.adjustment_contrast = 1.1
	## Stands in for the volumetric fog, which reaches its full density within
	## its own few metres and so reads as one flat haze over the whole view.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_density = 0.35
	env.fog_depth_begin = 0.0
	env.fog_depth_end = env.volumetric_fog_length
	env.fog_depth_curve = 1.0
	env.fog_light_color = FOG_COLOR
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.0
	env.fog_sky_affect = 0.0
