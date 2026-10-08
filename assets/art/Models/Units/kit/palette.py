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

## The Beastmen (kit/beastmen.py). Each unit is its own animal, so the
## species coats repaint rows no beastman wears in their own role (the
## horses' coat rows, the gnoll leader's russet, the wizard's robe): every
## row keeps its index, only this palette's colours change.
##   bear (Warrior): fur, fur_dark, fur_light (the gnolls' rows), nose
##   boar (Raider): coat, coat_dark (crest, trotters), coat_grey (snout disc)
##   stag (Druid): fur_red (fawn coat), hair_dark (dark points), cream
##     (muzzle, spots), wood_light (antlers); robe and robe_trim (moss and
##     leaf green), crystal (the jade spirit light)
##   panda (Panda Warrior): beard (white fur), beard_dark (black fur)
##   wolf (Wolf Pathfinder): hood (grey coat), hoof (dark grey points),
##     pebble (cream muzzle, ruff and tail tip)
## Steel is a neutral grey (a blue one read as blue team colour in game) and
## the haft wood near-black.
BEASTMEN = dict(GNOLLS)
BEASTMEN.update({
	"fur": ((110, 70, 42), (168, 108, 62), (210, 150, 96)),
	"fur_dark": ((56, 36, 26), (92, 60, 40), (128, 90, 62)),
	"fur_light": ((196, 140, 100), (240, 186, 138), (255, 220, 180)),
	"nose": ((18, 16, 18), (36, 32, 32), (74, 68, 66)),
	"blush": ((214, 130, 110), (232, 150, 126), (244, 174, 150)),
	"steel": ((74, 74, 78), (146, 146, 148), (214, 212, 208)),
	"trim": ((62, 62, 66), (112, 112, 114), (160, 158, 156)),
	"blade": ((132, 132, 136), (204, 204, 202), (252, 252, 248)),
	"wood": ((26, 22, 22), (48, 42, 40), (80, 72, 68)),
	# Boar: slate-grey bristle, a near-black crest and trotters, a pink snout.
	"coat": ((70, 66, 72), (116, 108, 110), (162, 152, 148)),
	"coat_dark": ((26, 22, 26), (46, 40, 42), (74, 66, 66)),
	"coat_grey": ((176, 112, 108), (222, 156, 146), (246, 196, 184)),
	# Stag: a golden fawn coat, dark-brown points, cream spots and muzzle,
	# pale antlers.
	"fur_red": ((150, 98, 52), (212, 150, 86), (240, 194, 132)),
	"hair_dark": ((54, 34, 26), (88, 58, 40), (124, 90, 64)),
	"cream": ((196, 180, 150), (240, 230, 206), (255, 252, 238)),
	"wood_light": ((150, 128, 100), (214, 196, 164), (246, 236, 212)),
	# A narrow shadow-to-highlight range, so the robe's rings read as one
	# green rather than stripes (the leaf-green trim is its own row).
	"robe": ((52, 84, 46), (70, 108, 58), (88, 126, 70)),
	"robe_trim": ((64, 120, 40), (110, 174, 64), (176, 220, 112)),
	"crystal": ((30, 140, 100), (70, 224, 164), (200, 255, 228)),
	# Panda: warm white fur and soft black fur.
	"beard": ((168, 166, 166), (232, 228, 220), (252, 250, 244)),
	"beard_dark": ((20, 18, 22), (40, 38, 42), (74, 72, 76)),
	# Wolf: a warm grey coat, charcoal points, a cream muzzle and ruff.
	"hood": ((86, 82, 82), (140, 134, 128), (190, 184, 174)),
	"hoof": ((34, 32, 34), (60, 56, 56), (94, 90, 88)),
	"pebble": ((176, 166, 150), (226, 218, 200), (250, 246, 234)),
})

## The Star Wanderers (kit/star_wanderers.py): sky-blue skin, pearl
## porcelain plate over a midnight-indigo suit, bright gold, and gear that
## glows in three star colours. Rows keep their roles where they can:
##   steel = pearl porcelain, blade = pearl edges, plate_dark = the midnight
##   suit, brass and trim = gold, robe = white robe cloth, crystal = cyan
##   starlight, arcane = violet moonlight, gem = rose.
## One row is repurposed, as the beastmen do with theirs (no free rows):
##   fruit = sun-gold glow (the Warrior's sun crescent; no star wanderer
##   carries fruit).
## Glow rows keep their shadow end light, so they read as lit from within.
STAR_WANDERERS = dict(ALDMERE)
STAR_WANDERERS.update({
	"skin": ((62, 104, 188), (110, 162, 236), (170, 210, 255)),
	"blush": ((120, 126, 214), (144, 146, 234), (172, 172, 248)),
	"eye": ((14, 16, 40), (26, 30, 64), (48, 56, 100)),
	"mouth": ((34, 36, 92), (52, 56, 124), (78, 82, 152)),
	"hair": ((150, 156, 200), (214, 220, 244), (248, 250, 255)),
	"cloth": ((150, 150, 176), (220, 218, 230), (248, 248, 252)),
	"cloth_dark": ((14, 16, 40), (28, 32, 70), (50, 58, 106)),
	"leather": ((26, 30, 66), (44, 52, 100), (70, 82, 138)),
	"leather_dark": ((18, 20, 46), (32, 36, 76), (54, 60, 110)),
	"boot": ((20, 22, 52), (36, 42, 86), (60, 70, 126)),
	"sole": ((10, 10, 24), (20, 22, 42), (34, 36, 62)),
	"plate_dark": ((14, 16, 44), (30, 36, 88), (72, 84, 156)),
	"metal_paint": ((30, 36, 92), (54, 66, 150), (100, 118, 204)),
	"steel": ((140, 142, 184), (222, 224, 242), (255, 255, 255)),
	"mail": ((40, 44, 84), (76, 84, 130), (120, 130, 176)),
	"trim": ((150, 100, 34), (218, 170, 66), (252, 228, 140)),
	"brass": ((156, 96, 26), (232, 178, 56), (255, 240, 156)),
	"blade": ((168, 174, 214), (228, 234, 252), (255, 255, 255)),
	"robe": ((168, 166, 200), (234, 232, 244), (255, 255, 252)),
	"robe_trim": ((156, 96, 26), (232, 178, 56), (255, 240, 156)),
	"lining": ((10, 12, 30), (20, 24, 52), (34, 40, 74)),
	"crystal": ((70, 186, 232), (122, 234, 255), (224, 255, 255)),
	"arcane": ((132, 84, 220), (182, 128, 255), (236, 208, 255)),
	"gem": ((196, 70, 150), (238, 112, 190), (255, 190, 230)),
	"fruit": ((236, 150, 40), (255, 204, 66), (255, 246, 176)),
	# The Rider's comet fox: a pale silver-lavender coat (coat; a royal-blue
	# one hid the blue team's saddle cloth), deep violet (coat_dark) and a
	# pearl-white ruff, mane and tail (mane).
	"coat": ((122, 110, 170), (184, 172, 226), (232, 226, 255)),
	"coat_dark": ((48, 38, 96), (78, 64, 138), (116, 102, 178)),
	"mane": ((168, 170, 212), (234, 236, 252), (255, 255, 255)),
})

## Wild animals (kit/animals.py): neutral wildlife in natural coats, no
## team rows worn. This palette is theirs alone, so rows are repainted
## freely (each keeps its index):
##   bear: fur (dark chocolate), fur_dark (paws, inner ears, tail),
##     fur_light (tan muzzle), nose, bone (claws)
##   boar: coat (brown bristle), coat_dark (crest, trotters, tail tuft),
##     coat_grey (pink snout disc, inner ears), bone (tusks)
##   deer: fur_red (russet coat), hair_dark (ear rims, burrs, tail),
##     cream (muzzle, throat, belly, rump), wood_light (antlers), hoof
ANIMALS = dict(GNOLLS)
ANIMALS.update({
	"fur": ((62, 40, 30), (104, 68, 44), (150, 106, 70)),
	"fur_dark": ((30, 22, 20), (52, 38, 32), (80, 62, 50)),
	"fur_light": ((160, 120, 86), (206, 166, 120), (236, 204, 158)),
	"blush": ((190, 110, 96), (210, 128, 110), (228, 152, 132)),
	"coat": ((86, 60, 44), (134, 96, 66), (178, 138, 100)),
	"coat_dark": ((26, 22, 22), (46, 40, 38), (74, 66, 62)),
	"coat_grey": ((176, 112, 108), (222, 156, 146), (246, 196, 184)),
	"fur_red": ((128, 60, 32), (184, 98, 52), (224, 148, 94)),
	"hair_dark": ((48, 30, 22), (80, 52, 36), (116, 84, 60)),
	"cream": ((196, 182, 156), (240, 232, 212), (255, 252, 240)),
	"wood_light": ((150, 128, 100), (214, 196, 164), (246, 236, 212)),
	"hoof": ((26, 22, 22), (46, 40, 38), (74, 66, 62)),
})

## Bestiary beasts (kit/beasts.py), on their race's palette. Applied last,
## after every other palette has copied its base, so only these change.
## The rows repainted are ones the race never otherwise wears:
##   Aldmere griffin: fur (tawny lion body, coverts; the gnoll row as is),
##     fur_light (cream belly, paws), fur_dark (tail tuft), fletch (white
##     head, neck and chest ruff; the arrows' white as is), fur_red (brown
##     flight feathers, crest, brows), ochre (golden beak and shins),
##     nose (dark talons)
##   Aldmere manticore: beard_dark (russet-orange lion; only the beastmen's
##     panda wears it), warpaint (dark amber mane; a gnoll row), tuft (dusky
##     violet wing membranes; only the unused base wears it), robe_dark
##     (charcoal wing bones, scorpion tail, brows; a gnoll row), bone (horns,
##     fangs, claws, stinger) as the gnolls'. Neither mane nor wings may be
##     red: from the game camera they read as the red team.
##   Dark Elf kitsune: fur (silver-white coat), fur_light (white ruff, tail
##     tips), fur_dark (black-violet socks and ear linings); arcane (violet
##     markings and foxfire) and brass (silver) as the race's own
##   Gnoll sand worm: coat (sandy hide), coat_dark (segment creases, brow),
##     coat_grey (pink lip): horse rows no gnoll wears (the hyena is fur);
##     bone (teeth, spikes) as the gnolls' own
##   Dark Elf wind tiger: beard (ivory-white coat), beard_dark (black
##     stripes, tail rings), tuft (mint wind; only the unused base wears it):
##     rows no dark elf wears; fur_light (belly, muzzle, paws) as the kitsune's
##   Gnoll skeleton dragon: bone as the gnolls' own, mane (grey hide wing
##     membranes; no gnoll rides a horse), crystal (green soul fire and eye
##     sparks; only the human mages wear it)
##   Star Wanderer sun dragon: fur (saffron-gold scales), fur_dark (amber
##     cheek fins, nostrils), fur_light (ivory belly, jaw, neck scutes), bone
##     (porcelain-ivory claws and fangs): rows no Star Wanderer wears;
##     plate_dark (midnight wing membranes), steel (porcelain horns, spikes,
##     saddle), brass and crystal as the race's own
##   Star Wanderer lightning dragon: beard (pale storm blue, kept greyer
##     than the blue team), beard_dark (navy brow, fins, paws): rows no Star
##     Wanderer wears; fur_light (belly) as the sun dragon's, mane (pearl
##     whiskers, manes, tail plume) as the comet fox's, crystal (lightning)
ALDMERE.update({
	"fur_red": ((92, 52, 30), (140, 86, 50), (184, 128, 82)),
	"ochre": ((176, 110, 24), (236, 176, 48), (255, 222, 120)),
	"beard_dark": ((150, 72, 34), (212, 122, 60), (246, 174, 106)),
	"warpaint": ((50, 30, 18), (96, 58, 26), (146, 98, 46)),
	"tuft": ((40, 32, 52), (74, 60, 92), (112, 98, 132)),
	"robe_dark": ((22, 20, 26), (44, 40, 48), (84, 78, 92)),
})
DARK_ELVES.update({
	"fur": ((140, 134, 172), (214, 212, 232), (248, 248, 255)),
	"fur_light": ((196, 192, 214), (244, 242, 252), (255, 255, 255)),
	"fur_dark": ((20, 16, 30), (42, 34, 58), (76, 64, 98)),
	"beard": ((178, 170, 158), (234, 228, 214), (254, 252, 244)),
	"beard_dark": ((14, 12, 20), (30, 26, 38), (58, 52, 70)),
	"tuft": ((86, 184, 168), (140, 232, 208), (214, 255, 242)),
})
GNOLLS.update({
	"coat": ((150, 100, 60), (206, 152, 96), (238, 198, 140)),
	"coat_dark": ((96, 56, 36), (136, 86, 54), (170, 118, 80)),
	"coat_grey": ((176, 100, 100), (220, 140, 132), (244, 186, 174)),
	"mane": ((52, 46, 44), (86, 78, 72), (128, 118, 106)),
	"crystal": ((70, 170, 70), (120, 232, 100), (206, 255, 180)),
})

STAR_WANDERERS.update({
	"fur": ((196, 128, 24), (246, 188, 44), (255, 234, 132)),
	"fur_dark": ((150, 76, 22), (204, 118, 36), (238, 168, 78)),
	"fur_light": ((206, 194, 170), (248, 242, 226), (255, 255, 250)),
	"bone": ((180, 176, 196), (236, 234, 244), (255, 255, 255)),
	"beard": ((84, 104, 150), (138, 164, 210), (204, 222, 250)),
	"beard_dark": ((22, 28, 58), (40, 50, 94), (72, 86, 140)),
})

## Monsters (kit/monsters.py, scenes/units/monsters): trained at the
## neutral Shrine by any race, so they have one palette of their own (with
## the team rows: each carries its owner's colour on a harness). Built on
## the Gnolls' rows; the palette is theirs alone, so rows are repainted
## freely (each keeps its index). Per monster:
##   black dragon: coat (charcoal scales), coat_dark (near-black brows,
##     spikes, nostrils, tail spade), coat_grey (dark oxblood wing membranes, kept
##     deep so they never read as the red team), fur_red (molten ember belly
##     and throat scutes, the glow in its maw), bone (horns, fangs, claws)
##     as the gnolls', steel (dark iron saddle and collar ring)
##   hydra: fur (sea-teal scales), fur_dark (brows, ridge plates), fur_light
##     (tan belly, jaws, throat scutes), brass (gold crests, band rims),
##     mouth, bone (fangs, claws)
##   skeleton dragon: bone, crystal (jade soul fire, sockets, maw), mane
##     (torn wing hide), coat_dark (sockets, claws), steel (finial, ring)
##   giant bear: beard (chestnut fur), beard_dark (paws, brows, ear
##     linings), cream (muzzle, jaw), warpaint (rust claw stripes, kept dark
##     so it never reads as the red team), nose, steel (iron cap, plates,
##     chain), wood (howdah)
##   yeti: hair (white fur, cool blue shadows), skin (blue-grey face, hands,
##     feet; slate, kept greyer than the blue team), hair_dark (brows, nose,
##     nails), arcane (pale glacier ice), bone (tusks, club)
##   orc mutant: hood (olive-grey hide, kept dull and grey so it never reads
##     as the green team), hoof (dark hide: brows, nose, nails), ochre (raw
##     mauve mutated flesh, kept off the red team), fruit (sickly bile
##     pustules), string (stitches), steel, blade (cleaver edge), warpaint
##     (rust stains), bone (horn, tusks, spikes)
##   phoenix: robe (flame-orange plumage), robe_trim (amber flame tips,
##     breast, crest), ermine (white-hot coverts, embers), robe_dark (deep
##     ember feather undersides), fletch (bronze beak), coat (charcoal
##     legs), coat_dark (brows), bone (talons), steel (collar boss, bar)
##   dark lord: plate_dark (black-violet plate), brass (gold trim, crown,
##     brows), gem (glowing violet runes, eyes, sorcery), coat_dark (visor,
##     horns, pauldron spikes), blade (sword edges)
MONSTERS = dict(GNOLLS)
MONSTERS.update({
	"coat": ((24, 22, 30), (54, 50, 60), (102, 96, 108)),
	"coat_dark": ((12, 10, 14), (26, 22, 28), (48, 42, 50)),
	"coat_grey": ((30, 16, 24), (60, 28, 38), (96, 50, 60)),
	"fur_red": ((206, 78, 18), (250, 138, 36), (255, 220, 120)),
	"bone": ((150, 140, 126), (214, 204, 184), (246, 240, 226)),
	"steel": ((40, 40, 46), (84, 84, 92), (140, 140, 150)),
	# Hydra: sea-teal scales (bluer and deeper than the green team), a
	# near-black teal for brows, ridge plates and nostrils, a warm tan belly.
	"fur": ((22, 92, 88), (44, 148, 132), (120, 210, 182)),
	"fur_dark": ((10, 36, 38), (20, 62, 62), (40, 96, 92)),
	"fur_light": ((170, 128, 82), (222, 182, 124), (248, 222, 170)),
	# Skeleton dragon: a spectral jade soul fire (kept off the green team's
	# lime) and slate-grey torn wing hide.
	"crystal": ((30, 150, 130), (70, 228, 190), (200, 255, 236)),
	"mane": ((26, 28, 36), (48, 52, 64), (86, 92, 106)),
	# Giant bear: chestnut fur, near-black brown paws and brows, a cream
	# muzzle, a dark rust war paint.
	"beard": ((92, 52, 30), (146, 88, 50), (192, 136, 88)),
	"beard_dark": ((34, 22, 18), (60, 40, 30), (92, 66, 50)),
	"cream": ((172, 140, 104), (222, 194, 150), (246, 228, 192)),
	"warpaint": ((84, 26, 18), (124, 42, 28), (160, 70, 50)),
	# Yeti: white fur with cool shadows, a slate blue-grey face and hands,
	# deep slate brows and nails, pale glacier ice.
	"hair": ((150, 162, 186), (226, 232, 242), (255, 255, 255)),
	"skin": ((70, 84, 112), (112, 130, 162), (160, 176, 202)),
	"hair_dark": ((22, 26, 40), (40, 46, 64), (70, 78, 98)),
	"arcane": ((110, 170, 210), (176, 222, 246), (236, 252, 255)),
	# Orc mutant: olive-grey hide, a near-black olive, raw mauve mutated
	# flesh, sickly bile pustules, black stitch thread.
	"hood": ((62, 76, 56), (106, 124, 90), (156, 172, 128)),
	"hoof": ((24, 30, 22), (44, 52, 38), (72, 82, 60)),
	"ochre": ((70, 48, 54), (112, 82, 86), (158, 128, 126)),
	"fruit": ((150, 158, 46), (204, 210, 90), (240, 246, 168)),
	"string": ((16, 12, 12), (34, 28, 24), (62, 52, 44)),
	# Dark lord: black-violet plate and a bright violet rune glow.
	"plate_dark": ((14, 10, 22), (40, 32, 58), (92, 80, 124)),
	"gem": ((120, 48, 200), (186, 108, 255), (236, 206, 255)),
	# Phoenix: flame-orange plumage, amber flame tips, white-hot cores, a
	# deep ember brown under the feathers and a bronze beak. Kept on orange
	# and amber so it never reads as the red or the yellow team.
	"robe": ((186, 66, 16), (240, 116, 26), (255, 162, 62)),
	"robe_trim": ((212, 108, 14), (252, 158, 30), (255, 210, 104)),
	"ermine": ((255, 176, 92), (255, 228, 176), (255, 252, 238)),
	"robe_dark": ((64, 30, 20), (110, 52, 28), (156, 90, 48)),
	"fletch": ((104, 64, 30), (164, 108, 46), (218, 168, 96)),
})

## Siege engines (kit/siege.py, Ballista and Magic Cannon from the Siege
## Workshop): Aldmere's rows (wood, steel, brass, string, team_paint and the
## crewman's skin, cloth and kettle hat), plus two rows Aldmere leaves
## unpainted: plate_dark (blackened iron: wheel tyres, axles, bands, the
## bolt's socket) and arcane (the cannon's glowing mint-cyan rune rings,
## runes and bore, after the sprite's magic). crystal is pushed brighter
## for the cannon's core and shards.
SIEGE = dict(ALDMERE)
SIEGE.update({
	"plate_dark": ((22, 22, 28), (46, 46, 54), (92, 92, 104)),
	"arcane": ((40, 190, 170), (110, 246, 214), (226, 255, 246)),
	"crystal": ((50, 150, 220), (120, 222, 255), (236, 252, 255)),
})

PALETTES = {"aldmere": ALDMERE, "gnolls": GNOLLS, "dark_elves": DARK_ELVES, "beastmen": BEASTMEN,
		"star_wanderers": STAR_WANDERERS, "animals": ANIMALS, "monsters": MONSTERS,
		"siege": SIEGE}
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
