# Builds Library.glb: a scholar's hall where villagers read for research. A
# tall two-storey timber hall with big study windows, an open-book sign over
# the door, a round stone reading tower with a team cone roof at the back
# corner, and a lectern with an open book and stacks of books out front.
# See common.py for the kit.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *

COLOURS.update({
	'Page': (0.85, 0.80, 0.66), 'Ink': (0.03, 0.025, 0.02),
	'BookGreen': (0.06, 0.2, 0.05), 'BookBrown': (0.3, 0.12, 0.04),
})


def book(x, y, z, w, d, h, cover, rot=0.0):
	"""One closed book lying flat: a cover with paper showing at three edges."""
	box((w, d, h), (x, y, z + h / 2), cover, rot=(0, 0, rot), bevel=0.012, segments=2)
	box((w - 0.03, d + 0.005, h * 0.6), (x + 0.012, y, z + h / 2), 'Page', rot=(0, 0, rot), bevel=0.006, segments=1)


def book_stack(x, y, z, n, rot=0.0):
	covers = ('Red', 'TeamColorDark', 'BookGreen', 'BookBrown', 'Red')
	for i in range(n):
		w = 0.26 + random.uniform(-0.03, 0.03)
		d = 0.2 + random.uniform(-0.02, 0.02)
		book(x, y, z + i * 0.065, w, d, 0.06, covers[i % len(covers)], rot + random.uniform(-12, 12))


def open_book(frame, w=0.42, h=0.3):
	"""An open book standing on `frame` (spine at the origin), pages up."""
	for side in (-1, 1):
		box((w / 2, h, 0.04), (side * w / 4, 0, 0.02), 'Red', rot=(0, side * -8, 0), bevel=0.015, matrix=frame)
		box((w / 2 - 0.04, h - 0.04, 0.03), (side * (w / 4 - 0.005), 0, 0.05), 'Page', rot=(0, side * -8, 0), bevel=0.01, matrix=frame)
		for k in range(3):
			box((w / 2 - 0.12, 0.012, 0.005), (side * w / 4, -h / 2 + 0.08 + k * 0.07, 0.068), 'Ink', rot=(0, side * -8, 0), bevel=0.0, matrix=frame)


new_scene(83)
HX, HY, WALL_TOP, CX = 1.05, 0.85, 2.35, -0.2
plinth(1.75, 1.15, cx=0.05)
mid = hall(HX, HY, WALL_TOP, cx=CX, mid_z=1.35)
ridge = gable_roof(2.5, HY, WALL_TOP, cx=CX, pitch=46.0, over=0.3, hx=HX, tile_rows=5)
for y in (-HY, HY):
	for x in (CX - HX, CX + HX):
		quoins(x, y, PZ + 0.3, mid - 0.1, size=0.24)

# Front: the door under an open-book sign, tall study windows either side.
door(face(CX, -HY - 0.07, PZ, '-y'), w=0.56, h=0.98, arch='stone')
for x in (CX - 0.68, CX + 0.68):
	window(face(x, -HY - 0.03, 0.95, '-y'), w=0.3, h=0.5)
	window(face(x, -HY - 0.03, 1.8, '-y'), w=0.28, h=0.44, shutters=False)
# Above the door arch, leaning back against the wall with the pages out.
sign = face(CX, -HY - 0.2, 1.78, '-y') @ Matrix.Rotation(math.radians(70), 4, 'X')
box((0.56, 0.4, 0.05), (0, 0, -0.02), 'Wood', bevel=0.02, matrix=sign)
open_book(sign, w=0.46, h=0.32)
window(face(CX - HX - 0.03, 0, 1.0, '-x'), w=0.3, h=0.44)
window(face(CX - HX - 0.03, 0, 1.85, '-x'), w=0.28, h=0.4, shutters=False)
chimney(CX - 0.55, 0.25, WALL_TOP - 0.3, ridge + 0.25)

# The reading tower: round stone drum at the back right with a team cone.
TX, TY, TR = CX + HX + 0.25, 0.45, 0.58
TOP = 3.05
cylinder(TR, TOP - PZ, (TX, TY, (TOP + PZ) / 2), 'Stone', verts=14, bevel=0.05)
cylinder(TR + 0.06, 0.3, (TX, TY, PZ + 0.15), 'StoneDark', verts=14, bevel=0.04)
cylinder(TR + 0.08, 0.16, (TX, TY, TOP), 'StoneDark', verts=14, bevel=0.04)
for k in range(8):
	a = math.radians(k * 45 + 22.5)
	box((0.2, 0.2, 0.2), (TX + math.cos(a) * (TR + 0.02), TY + math.sin(a) * (TR + 0.02), TOP + 0.16), 'Stone', bevel=0.04)
pyramid(TR * 2.2, 1.15, (TX, TY, TOP + 0.08), 'TeamColor', sides=8)
sphere(0.08, (TX, TY, TOP + 1.25), 'Gold')
for z, ang in ((1.2, -60), (2.2, -30)):
	a = math.radians(ang)
	# Turned to face straight out from the drum, just proud of its surface.
	frame = Matrix.Translation((TX + math.cos(a) * (TR + 0.03), TY + math.sin(a) * (TR + 0.03), z)) @ Matrix.Rotation(a + math.pi / 2, 4, 'Z')
	window(frame, w=0.18, h=0.36, shutters=False)
for z in (1.0, 1.9):
	cylinder(TR + 0.03, 0.08, (TX, TY, z), 'StoneDark', verts=14, bevel=0.02)

# Out front: a lectern with the great book, stacks of books, a scroll basket.
LX, LY = CX + 1.45, -0.95
box((0.12, 0.12, 0.62), (LX, LY, PZ + 0.31), 'Wood', bevel=0.03)
box((0.32, 0.22, 0.06), (LX, LY, PZ + 0.03), 'WoodDark', bevel=0.02)
top = Matrix.Translation((LX, LY, PZ + 0.68)) @ Matrix.Rotation(math.radians(-25), 4, 'X')
box((0.44, 0.34, 0.05), (0, 0, 0), 'Wood', bevel=0.02, matrix=top)
open_book(top @ Matrix.Translation((0, 0, 0.03)), w=0.38, h=0.26)
book_stack(CX - 0.75, -1.05, PZ, 4, rot=8)
book_stack(CX - 1.3, -0.95, PZ, 2, rot=-20)
cylinder(0.17, 0.3, (CX + 1.75, -0.6, PZ + 0.15), 'Hay', verts=10, bevel=0.03)
for k in range(4):
	a = k * 1.6
	cylinder(0.035, 0.36, (CX + 1.75 + math.cos(a) * 0.07, -0.6 + math.sin(a) * 0.07, PZ + 0.42), 'Page', verts=8, rot=(8, 0, 0), bevel=0.01)
flag(CX - HX + 0.12, 0.0, ridge - 0.15, 0.85)
export('Library')
