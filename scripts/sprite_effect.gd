class_name SpriteEffect
extends Resource
## One flipbook visual cut from a single row of a sprite sheet — an ability's
## cast flash, its projectile or its impact (see Ability). Played by
## WorldFeedback as a purely local billboard, so nothing here is networked.

@export var sheet: Texture2D
@export var frame_size: Vector2i = Vector2i(32, 32)
@export var row: int = 0
## Lets one row hold several effects side by side (e.g. the Phoenix sheet's
## last row), or skip the tiny opening frames of a breath plume.
@export var first_frame: int = 0
@export var frame_count: int = 1
@export var fps: float = 12.0
## Multiplier on top of the unit sprites' own pixel size, so scale 1.0 matches
## a unit drawn from a sheet of the same resolution.
@export var scale: float = 1.0
## Multiplied over the sheet's own colours, so one sheet can serve several
## abilities (ice spikes tinted brown read as earth spikes).
@export var tint: Color = Color.WHITE
## Sheets are drawn facing right. When true the effect is turned on screen to
## point along its direction of travel (breath, fireballs); false keeps it
## upright (explosions, ice spikes, ground bursts).
@export var orient_to_direction: bool = false
## Lifts the effect off its anchor point in world units — ground bursts want
## their base on the ground, not their centre.
@export var height_offset: float = 0.0
## Emissive-looking effects (fire, acid, magic) read better unshaded than
## sitting in the scene's own lighting like the unit sprites do.
@export var unshaded: bool = true

## Must match unit.tscn's Sprite.pixel_size.
const BASE_PIXEL_SIZE: float = 0.05

## Built once on first use and shared by every copy of this effect on screen.
var _frames: SpriteFrames = null

func duration() -> float:
	return frame_count / maxf(fps, 0.01)

func get_frames() -> SpriteFrames:
	if _frames == null:
		_frames = _build_frames()
	return _frames

## Two copies of the same clip: LOOP for something with no natural end (a
## projectile in flight), ONCE for everything else, which frees itself when
## the clip finishes.
const LOOP: StringName = &"loop"
const ONCE: StringName = &"once"

func _build_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	for anim in [LOOP, ONCE]:
		frames.add_animation(anim)
		frames.set_animation_speed(anim, fps)
		frames.set_animation_loop(anim, anim == LOOP)
		for i in frame_count:
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet
			atlas.region = Rect2((first_frame + i) * frame_size.x, row * frame_size.y, frame_size.x, frame_size.y)
			frames.add_frame(anim, atlas)
	return frames

## Size of one frame in world units at `extra_scale`.
func world_height(extra_scale: float = 1.0) -> float:
	return frame_size.y * BASE_PIXEL_SIZE * scale * extra_scale

func world_width(extra_scale: float = 1.0) -> float:
	return frame_size.x * BASE_PIXEL_SIZE * scale * extra_scale
