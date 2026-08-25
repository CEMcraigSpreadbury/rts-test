class_name SpriteSheetFrames
extends RefCounted
## Builds a SpriteFrames resource from a single grid-based sprite sheet texture.
## `animations` maps animation name -> {row, frames, fps, loop}.

static func build(sheet: Texture2D, cell_size: Vector2i, animations: Dictionary) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for anim_name in animations.keys():
		var config: Dictionary = animations[anim_name]
		var row: int = config.get("row", 0)
		var frame_count: int = config.get("frames", 1)
		var fps: float = config.get("fps", 6.0)
		var loop: bool = config.get("loop", true)
		frames.add_animation(anim_name)
		frames.set_animation_speed(anim_name, fps)
		frames.set_animation_loop(anim_name, loop)
		for i in frame_count:
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet
			atlas.region = Rect2(i * cell_size.x, row * cell_size.y, cell_size.x, cell_size.y)
			frames.add_frame(anim_name, atlas)
	return frames
