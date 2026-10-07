"""The figure palette: one small texture every unit shares, as data.

A figure's faces are not textured. Each face's UVs are collapsed onto one ROW
of the palette image (its swatch), and across that row the colour runs from the
swatch's shadow tone (left) through its base tone (middle) to its highlight
(right). figure.py sets each corner's U from which way the surface faces
(down = left, sideways = middle, up = right), so every part is painted with a
miniature painter's top-down light baked into it: subtle on cloth and skin,
strong on polished metal.

Rows are named by role ("cloth", "metal_paint"), never by colour, so one mesh
can be repainted for another race by swapping the palette image. New rows are
only ever appended (TEAM_FIRST and later stay put), or older meshes would land
on the wrong colours.

The TEAM rows hold grey shades. The game's shader multiplies them by the
team's colour (any UV below TEAM_V in the image is a team swatch).

    python palette.py      writes palettes/<race>.png for every race below
"""
import struct
import zlib
from pathlib import Path

WIDTH = 32
ROW_PX = 4
ROWS = 64
HEIGHT = ROWS * ROW_PX
TEAM_FIRST = 56
## UV v (from the image's top, as glTF and Godot count it) where team rows start.
TEAM_V = TEAM_FIRST * ROW_PX / HEIGHT

LAYOUT = [
	"skin", "blush", "eye", "glint", "mouth", "hair",
	"cloth", "cloth_dark", "leather", "leather_dark", "boot", "sole",
	"metal_paint", "steel", "mail", "brass", "blade", "wood",
	"cream", "flock", "base_dark", "tuft", "pebble", "lining",
	"trim", "coat", "coat_dark", "mane",
	"hoof", "coat_grey", "beard", "beard_dark", "crystal", "wood_light",
	"robe", "robe_trim", "ermine", "fletch", "string", "fruit",
	"fruit_green", "wicker", "gem", "hair_dark",
	"hood", "fur", "fur_dark", "fur_light", "nose", "bone",
	"ochre", "warpaint", "robe_dark", "fur_red", "plate_dark", "arcane",
	"team", "team_light", "team_dark", "team_paint",
	"team_cloth", "team_cloth_dark", "team_spare_62", "team_spare_63",
]
assert len(LAYOUT) == ROWS and LAYOUT.index("team") == TEAM_FIRST
ROW = {name: i for i, name in enumerate(LAYOUT)}


def row(name):
	return ROW[name]


def uv(name, t):
	"""Blender UV for swatch `name` at `t` (0 shadow .. 0.5 base .. 1 highlight).
	Blender's V runs up the image; the glTF export flips it back."""
	r = ROW[name]
	u = (0.5 + t * (WIDTH - 1)) / WIDTH
	v_image = (r * ROW_PX + ROW_PX * 0.5) / HEIGHT
	return (u, 1.0 - v_image)


# sRGB 0-255, (shadow, base, highlight) per swatch. Shadows lean cool and a
# little purple, highlights warm, as a painted miniature's would.
ALDMERE = {
	"skin": ((196, 140, 122), (240, 198, 164), (255, 226, 196)),
	"blush": ((222, 150, 134), (238, 166, 146), (246, 184, 164)),
	"eye": ((22, 20, 34), (38, 34, 54), (60, 56, 84)),
	"glint": ((236, 240, 250), (255, 255, 255), (255, 255, 255)),
	"mouth": ((96, 40, 40), (128, 58, 52), (150, 76, 66)),
	"hair": ((168, 128, 74), (226, 196, 128), (252, 236, 180)),
	# Undyed wool (the tunic when a tabard carries the team colour).
	"cloth": ((112, 98, 86), (172, 156, 130), (210, 198, 172)),
	"cloth_dark": ((34, 30, 40), (56, 52, 62), (80, 76, 86)),
	"leather": ((84, 50, 34), (128, 84, 52), (170, 124, 80)),
	"leather_dark": ((52, 30, 24), (88, 54, 34), (120, 80, 52)),
	"boot": ((42, 28, 24), (82, 52, 34), (118, 80, 54)),
	"sole": ((26, 20, 18), (40, 30, 26), (58, 46, 40)),
	"metal_paint": ((32, 58, 112), (60, 104, 172), (112, 158, 214)),
	"steel": ((62, 70, 86), (132, 142, 158), (196, 204, 218)),
	"mail": ((40, 44, 54), (78, 84, 98), (128, 136, 150)),
	"brass": ((120, 72, 28), (204, 150, 60), (255, 226, 140)),
	"blade": ((120, 130, 146), (196, 204, 216), (250, 252, 255)),
	"wood": ((80, 50, 30), (128, 86, 52), (168, 120, 76)),
	"cream": ((190, 168, 130), (236, 222, 186), (255, 248, 222)),
	"flock": ((54, 58, 34), (80, 86, 48), (106, 112, 64)),
	"base_dark": ((30, 26, 24), (44, 38, 34), (60, 54, 48)),
	"tuft": ((112, 126, 52), (156, 166, 72), (198, 200, 104)),
	"pebble": ((96, 90, 84), (140, 132, 122), (186, 178, 166)),
	"lining": ((36, 28, 26), (52, 42, 38), (66, 54, 48)),
	# Steel edging on painted armour, kept below the paint's own highlight.
	"trim": ((58, 68, 88), (112, 124, 144), (156, 168, 186)),
	# Horses: a bay coat, a dapple grey, black mane and hooves.
	"coat": ((92, 50, 30), (150, 92, 54), (196, 136, 88)),
	"coat_dark": ((48, 28, 20), (86, 52, 34), (122, 80, 54)),
	"mane": ((26, 20, 18), (46, 36, 32), (72, 60, 52)),
	"hoof": ((30, 26, 24), (52, 46, 42), (80, 72, 66)),
	"coat_grey": ((130, 128, 132), (196, 194, 196), (238, 236, 232)),
	"beard": ((168, 164, 160), (226, 222, 214), (250, 248, 242)),
	"beard_dark": ((84, 50, 30), (132, 84, 48), (172, 122, 76)),
	"crystal": ((60, 140, 190), (120, 210, 240), (220, 250, 255)),
	"wood_light": ((128, 92, 58), (182, 140, 92), (220, 184, 132)),
	"robe": ((176, 170, 160), (226, 222, 210), (250, 248, 240)),
	"robe_trim": ((140, 98, 30), (214, 168, 70), (255, 230, 150)),
	"ermine": ((200, 196, 188), (244, 242, 236), (255, 255, 252)),
	"fletch": ((150, 146, 140), (220, 216, 206), (248, 246, 240)),
	"string": ((170, 160, 140), (214, 204, 182), (240, 232, 214)),
	"fruit": ((150, 30, 30), (210, 56, 44), (250, 120, 90)),
	"fruit_green": ((80, 120, 30), (130, 170, 50), (190, 214, 100)),
	"wicker": ((120, 84, 40), (184, 140, 76), (224, 190, 124)),
	"gem": ((120, 20, 40), (196, 40, 70), (250, 120, 150)),
	"hair_dark": ((60, 36, 24), (104, 66, 40), (148, 102, 66)),
	# Undyed russet wool: the archer's hood, the villager's cap.
	"hood": ((86, 58, 40), (138, 98, 64), (180, 140, 100)),
	# Grey shades the game multiplies by the team colour.
	"team": ((100, 100, 100), (168, 168, 168), (208, 208, 208)),
	"team_light": ((150, 150, 150), (206, 206, 206), (236, 236, 236)),
	"team_dark": ((70, 70, 70), (112, 112, 112), (142, 142, 142)),
	# Painted armour (the helmet): about the depth of the building roofs.
	"team_paint": ((74, 74, 74), (118, 118, 118), (146, 146, 146)),
	# Dyed cloth (hoods, capes, hats, pennants, the cavalier's caparison).
	"team_cloth": ((80, 80, 80), (128, 128, 128), (160, 160, 160)),
	"team_cloth_dark": ((58, 58, 58), (92, 92, 92), (118, 118, 118)),
}

## Gnoll rows (kit/gnoll.py). Aldmere carries them too, so no row is ever
## left unpainted, but only the gnolls wear them.
_GNOLL_ROWS = {
	# Tawny hyena fur, its dark spots and mane, the pale muzzle and throat.
	"fur": ((150, 104, 64), (200, 154, 98), (232, 196, 140)),
	"fur_dark": ((46, 32, 30), (76, 52, 40), (108, 78, 58)),
	"fur_light": ((190, 162, 124), (234, 214, 172), (252, 238, 206)),
	"nose": ((20, 16, 20), (40, 32, 34), (78, 66, 66)),
	# Bone and teeth, and the ochre the race paints its gear with.
	"bone": ((176, 162, 132), (232, 222, 194), (252, 248, 232)),
	"ochre": ((150, 72, 30), (204, 118, 46), (238, 168, 84)),
	# The berserk's blood-red war paint.
	"warpaint": ((96, 20, 22), (152, 34, 30), (196, 62, 50)),
	# The shaman's dark indigo robe and sleeves.
	"robe_dark": ((30, 28, 54), (52, 50, 92), (84, 82, 132)),
	# The leader's russet fur.
	"fur_red": ((118, 58, 34), (166, 88, 52), (206, 132, 86)),
}
ALDMERE.update(_GNOLL_ROWS)
## The Gnolls: Aldmere's rows with rawer hide and darker, rougher wood.
GNOLLS = dict(ALDMERE)
GNOLLS.update({
	"leather": ((92, 60, 38), (146, 104, 64), (186, 146, 98)),
	"leather_dark": ((56, 36, 28), (96, 64, 42), (132, 96, 64)),
	"wood": ((70, 44, 28), (112, 76, 46), (150, 108, 70)),
	"blush": ((206, 128, 116), (226, 146, 128), (240, 170, 150)),
})

## Dark elf rows (kit/dark_elf.py), carried by every palette as the gnolls' are.
_DARK_ELF_ROWS = {
	# Black-violet lacquered plate, the colour of the race's dark stone.
	"plate_dark": ((22, 18, 32), (50, 40, 70), (100, 86, 132)),
	# The violet glow of their arcane inlays (the buildings' Arcane).
	"arcane": ((96, 36, 160), (158, 80, 224), (220, 170, 255)),
}
ALDMERE.update(_DARK_ELF_ROWS)
GNOLLS.update(_DARK_ELF_ROWS)
## The Dark Elves: lilac-grey skin, white hair, black and violet cloth and
## leather, silver for steel and for the brass of the human kit.
DARK_ELVES = dict(ALDMERE)
DARK_ELVES.update({
	"skin": ((118, 108, 150), (172, 164, 200), (212, 206, 232)),
	"blush": ((150, 120, 170), (166, 134, 186), (184, 152, 204)),
	"eye": ((30, 14, 40), (52, 22, 66), (84, 44, 104)),
	"mouth": ((70, 40, 72), (96, 56, 96), (120, 76, 120)),
	"hair": ((160, 160, 178), (226, 226, 236), (252, 252, 255)),
	"cloth": ((26, 22, 34), (48, 40, 60), (76, 66, 92)),
	"cloth_dark": ((16, 14, 22), (30, 26, 38), (50, 44, 60)),
	"leather": ((36, 26, 40), (62, 44, 66), (92, 70, 96)),
	"leather_dark": ((22, 16, 26), (40, 30, 44), (64, 50, 70)),
	"boot": ((20, 16, 24), (38, 30, 44), (62, 52, 72)),
	"sole": ((12, 10, 14), (22, 18, 26), (36, 30, 40)),
	"metal_paint": ((44, 24, 70), (82, 46, 124), (132, 92, 182)),
	"steel": ((78, 78, 104), (160, 162, 188), (228, 230, 246)),
	"mail": ((32, 28, 44), (62, 56, 80), (104, 98, 128)),
	"brass": ((92, 90, 120), (176, 176, 204), (240, 240, 255)),
	"blade": ((112, 118, 146), (192, 198, 220), (248, 250, 255)),
	"trim": ((80, 82, 108), (142, 144, 172), (190, 192, 216)),
	"wood": ((28, 20, 26), (50, 38, 46), (76, 62, 72)),
	"lining": ((20, 14, 24), (32, 24, 36), (46, 36, 50)),
	"gem": ((96, 36, 160), (158, 80, 224), (220, 170, 255)),
	# The venom on the archers' arrowheads and the assassins' blades.
	"crystal": ((40, 130, 70), (80, 210, 110), (190, 255, 200)),
	# The riders' dark horses: charcoal-violet coats, silver-blue manes.
	"coat": ((26, 24, 34), (54, 50, 66), (88, 84, 104)),
	"coat_dark": ((16, 14, 22), (34, 30, 42), (56, 52, 66)),
	"mane": ((90, 110, 140), (150, 176, 206), (210, 228, 246)),
	"hoof": ((40, 46, 62), (78, 88, 112), (120, 132, 160)),
})

PALETTES = {"aldmere": ALDMERE, "gnolls": GNOLLS, "dark_elves": DARK_ELVES}
## The team colours a palette is previewed with outside the game (Blender
## renders): Network.TEAM_COLORS[0] and [1], blue and red.
PREVIEW_TEAM = (0.25, 0.55, 1.0)
PREVIEW_TEAM_2 = (1.0, 0.35, 0.3)
## shaders/unit_figure.gdshader's team_grey_ref and team_saturation, so a
## preview's team rows come out as the game's do.
TEAM_GREY_REF = 0.42
TEAM_SATURATION = 0.88


def _lerp(a, b, t):
	return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def _row_colour(entry, t):
	shadow, base, light = entry
	return _lerp(shadow, base, t * 2.0) if t < 0.5 else _lerp(base, light, (t - 0.5) * 2.0)


def pixels(race, team=None):
	"""HEIGHT rows of WIDTH (r, g, b) 0-255. With `team` (sRGB 0-1, as the
	game's Network.TEAM_COLORS) the team rows come tinted the way the game's
	shader tints them, for previews outside the game."""
	pal = PALETTES[race]
	out = []
	for r in range(ROWS):
		name = LAYOUT[r]
		entry = pal.get(name, ((255, 0, 255),) * 3)
		line = []
		for x in range(WIDTH):
			t = x / (WIDTH - 1)
			c = _row_colour(entry, t)
			if team is not None and r >= TEAM_FIRST:
				c = tuple(v * 255.0 for v in _team_tint(c[0] / 255.0, team))
			line.append(tuple(max(0, min(255, int(round(v)))) for v in c))
		for _ in range(ROW_PX):
			out.append(line)
	return out


def _team_tint(grey, team):
	"""unit_figure.gdshader's team colouring, as sRGB 0-1."""
	lin = [_to_linear(v) for v in team]
	luma = 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]
	lin = [luma + (v - luma) * TEAM_SATURATION for v in lin]
	k = _to_linear(grey) / TEAM_GREY_REF
	return tuple(_to_srgb(min(1.0, v * k)) for v in lin)


def _to_linear(c):
	return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _to_srgb(c):
	return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1.0 / 2.4) - 0.055


def write_png(path, race, team=None):
	rows = pixels(race, team)
	raw = b"".join(b"\x00" + bytes(v for px in line for v in px) for line in rows)

	def chunk(tag, data):
		body = tag + data
		return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

	png = b"\x89PNG\r\n\x1a\n"
	png += chunk(b"IHDR", struct.pack(">IIBBBBB", WIDTH, HEIGHT, 8, 2, 0, 0, 0))
	png += chunk(b"IDAT", zlib.compress(raw, 9))
	png += chunk(b"IEND", b"")
	Path(path).write_bytes(png)


def write_mask_png(path):
	"""White where a row is a team row, black elsewhere: for masks."""
	rows = []
	for r in range(ROWS):
		value = 255 if r >= TEAM_FIRST else 0
		line = [(value, value, value)] * WIDTH
		for _ in range(ROW_PX):
			rows.append(line)
	_write_rows(path, rows)


def _write_rows(path, rows):
	raw = b"".join(b"\x00" + bytes(v for px in line for v in px) for line in rows)

	def chunk(tag, data):
		body = tag + data
		return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

	png = b"\x89PNG\r\n\x1a\n"
	png += chunk(b"IHDR", struct.pack(">IIBBBBB", WIDTH, len(rows), 8, 2, 0, 0, 0))
	png += chunk(b"IDAT", zlib.compress(raw, 9))
	png += chunk(b"IEND", b"")
	Path(path).write_bytes(png)


if __name__ == "__main__":
	here = Path(__file__).resolve().parent.parent / "palettes"
	here.mkdir(exist_ok=True)
	for race in PALETTES:
		write_png(here / ("%s.png" % race), race)
		print("wrote", here / ("%s.png" % race))
