@tool
class_name MapHeightmapImport
extends RefCounted
## Reads a heightmap for MapGenerator's import mode: a Beyond All Reason /
## Recoil (Spring) map, either the .sd7 archive or its extracted .smf, or a
## plain greyscale heightmap (.png, .exr, or raw 16-bit .r16/.raw).
##
## Spring maps also give start positions (mapinfo.lua, next to the maps/
## folder) and metal spots (the .smf's metal map), which the generator uses for
## bases and gold. All positions come back as 0..1 UVs across the map.

const SMF_MAGIC: String = "spring map file"
## Spring maps measure the heightmap in elmos with the sea at 0.
const SPRING_SEA_LEVEL: float = 0.0
## Metal map cells at least this bright (0..255) count as part of a spot.
const METAL_THRESHOLD: int = 16
const EXTRACT_DIR: String = "user://heightmap_import"

## Returns {width, height (samples), values: PackedFloat32Array (row-major,
## source units), water, low, high, start_positions: Array[Vector2],
## metal_spots: Array[Vector2]} or {error: String}.
static func load_source(path: String, image_water_height: float) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {error = "Heightmap file not found: %s" % path}
	match path.get_extension().to_lower():
		"sd7":
			return _load_sd7(path)
		"smf":
			return _load_smf(path)
		"png", "exr", "jpg", "jpeg", "webp", "tga", "bmp":
			return _load_image(path, image_water_height)
		"r16", "raw":
			return _load_raw16(path, image_water_height)
	return {error = "Unsupported heightmap type: %s" % path.get_extension()}

## Bilinear sample of the source at UV (0..1 each way).
static func sample(source: Dictionary, uv: Vector2) -> float:
	var w: int = source.width
	var h: int = source.height
	var x: float = clampf(uv.x, 0.0, 1.0) * (w - 1)
	var y: float = clampf(uv.y, 0.0, 1.0) * (h - 1)
	var i: int = mini(floori(x), w - 2)
	var j: int = mini(floori(y), h - 2)
	var fx: float = x - i
	var fy: float = y - j
	var values: PackedFloat32Array = source.values
	var top: float = lerpf(values[j * w + i], values[j * w + i + 1], fx)
	var bottom: float = lerpf(values[(j + 1) * w + i], values[(j + 1) * w + i + 1], fx)
	return lerpf(top, bottom, fy)

## Unpacks with Windows' own tar (libarchive reads 7z) into user://, once per
## archive, then loads the .smf inside.
static func _load_sd7(path: String) -> Dictionary:
	var out_dir: String = ProjectSettings.globalize_path(EXTRACT_DIR.path_join(path.get_file().get_basename()))
	if _find_file(out_dir, "smf").is_empty():
		DirAccess.make_dir_recursive_absolute(out_dir)
		var tar: String = "tar"
		var windows_tar: String = OS.get_environment("WINDIR").path_join("System32/tar.exe")
		if OS.get_name() == "Windows" and FileAccess.file_exists(windows_tar):
			tar = windows_tar
		var output: Array = []
		var code: int = OS.execute(tar, ["-xf", ProjectSettings.globalize_path(path), "-C", out_dir], output, true)
		if code != 0:
			return {error = "Could not unpack %s (tar exit %d): %s" % [path.get_file(), code, "".join(output)]}
	var smf: String = _find_file(out_dir, "smf")
	if smf.is_empty():
		return {error = "No .smf map found inside %s" % path.get_file()}
	return _load_smf(smf)

static func _find_file(dir_path: String, extension: String) -> String:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return ""
	for file in dir.get_files():
		if file.get_extension().to_lower() == extension:
			return dir_path.path_join(file)
	for sub in dir.get_directories():
		var found: String = _find_file(dir_path.path_join(sub), extension)
		if not found.is_empty():
			return found
	return ""

## SMF layout: 16-byte magic, then little-endian ints version, mapid, mapx,
## mapy, squareSize, texelPerSquare, tileSize, floats minHeight, maxHeight, and
## ints heightmapPtr, typeMapPtr, tilesPtr, minimapPtr, metalmapPtr, featurePtr.
## Heights are (mapx+1)*(mapy+1) uint16 scaled between min and max height; the
## metal map is (mapx/2)*(mapy/2) bytes.
static func _load_smf(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {error = "Cannot open %s" % path}
	var magic: String = file.get_buffer(16).get_string_from_ascii()
	if not magic.begins_with(SMF_MAGIC):
		return {error = "%s is not a Spring map file" % path.get_file()}
	file.get_32()
	file.get_32()
	var map_x: int = file.get_32()
	var map_y: int = file.get_32()
	var square_size: int = file.get_32()
	file.get_32()
	file.get_32()
	var min_height: float = file.get_float()
	var max_height: float = file.get_float()
	var heightmap_ptr: int = file.get_32()
	file.get_32()
	file.get_32()
	file.get_32()
	var metal_ptr: int = file.get_32()

	var width: int = map_x + 1
	var height: int = map_y + 1
	file.seek(heightmap_ptr)
	var raw: PackedByteArray = file.get_buffer(width * height * 2)
	var values := PackedFloat32Array()
	values.resize(width * height)
	var step: float = (max_height - min_height) / 65536.0
	var low: float = INF
	var high: float = -INF
	for i in width * height:
		var v: float = min_height + raw.decode_u16(i * 2) * step
		values[i] = v
		low = minf(low, v)
		high = maxf(high, v)

	var metal_w: int = map_x / 2
	var metal_h: int = map_y / 2
	file.seek(metal_ptr)
	var metal: PackedByteArray = file.get_buffer(metal_w * metal_h)

	var map_info: String = path.get_base_dir().get_base_dir().path_join("mapinfo.lua")
	return {
		width = width, height = height, values = values, water = SPRING_SEA_LEVEL, low = low, high = high,
		start_positions = _spring_start_positions(map_info, map_x * square_size, map_y * square_size),
		metal_spots = _metal_spots(metal, metal_w, metal_h),
	}

## teams = { [0] = {startPos = {x = 886, z = 7347}}, ... } in elmos, in team order.
static func _spring_start_positions(map_info: String, width_elmos: float, height_elmos: float) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	if not FileAccess.file_exists(map_info):
		return positions
	var text: String = FileAccess.get_file_as_string(map_info)
	var pattern := RegEx.create_from_string("(?i)startpos\\s*=\\s*\\{\\s*x\\s*=\\s*(-?[\\d.]+)\\s*,\\s*z\\s*=\\s*(-?[\\d.]+)")
	for m in pattern.search_all(text):
		positions.append(Vector2(float(m.get_string(1)) / width_elmos, float(m.get_string(2)) / height_elmos))
	return positions

## Centroid of each connected blob of metal, weighted by amount.
static func _metal_spots(metal: PackedByteArray, w: int, h: int) -> Array[Vector2]:
	var spots: Array[Vector2] = []
	if metal.size() < w * h:
		return spots
	var seen := PackedByteArray()
	seen.resize(w * h)
	for start in w * h:
		if seen[start] == 1 or metal[start] < METAL_THRESHOLD:
			continue
		var frontier: Array[int] = [start]
		seen[start] = 1
		var total: float = 0.0
		var centre := Vector2.ZERO
		var head: int = 0
		while head < frontier.size():
			var i: int = frontier[head]
			head += 1
			var x: int = i % w
			var y: int = i / w
			centre += Vector2(x + 0.5, y + 0.5) * metal[i]
			total += metal[i]
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var n: int = ny * w + nx
				if seen[n] == 0 and metal[n] >= METAL_THRESHOLD:
					seen[n] = 1
					frontier.append(n)
		spots.append(Vector2(centre.x / total / w, centre.y / total / h))
	return spots

static func _load_image(path: String, water: float) -> Dictionary:
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		return {error = "Cannot read image %s" % path}
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RF)
	var width: int = image.get_width()
	var height: int = image.get_height()
	var values := PackedFloat32Array()
	values.resize(width * height)
	var low: float = INF
	var high: float = -INF
	for y in height:
		for x in width:
			var v: float = image.get_pixel(x, y).r
			values[y * width + x] = v
			low = minf(low, v)
			high = maxf(high, v)
	return {width = width, height = height, values = values, water = lerpf(low, high, water), low = low, high = high, start_positions = [] as Array[Vector2], metal_spots = [] as Array[Vector2]}

## Square little-endian 16-bit, as exported by most terrain tools.
static func _load_raw16(path: String, water: float) -> Dictionary:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var count: int = bytes.size() / 2
	var side: int = int(round(sqrt(count)))
	if side * side != count:
		return {error = "%s is not a square 16-bit raw heightmap (%d samples)" % [path.get_file(), count]}
	var values := PackedFloat32Array()
	values.resize(count)
	var low: float = INF
	var high: float = -INF
	for i in count:
		var v: float = bytes.decode_u16(i * 2) / 65535.0
		values[i] = v
		low = minf(low, v)
		high = maxf(high, v)
	return {width = side, height = side, values = values, water = lerpf(low, high, water), low = low, high = high, start_positions = [] as Array[Vector2], metal_spots = [] as Array[Vector2]}
