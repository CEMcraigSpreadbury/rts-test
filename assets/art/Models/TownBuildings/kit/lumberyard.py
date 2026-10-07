# Builds Lumberyard.glb: an open timber drying shed of sawn planks under a
# tiled roof, a big log pile, and a chopping block with an axe. Kept low, as
# the old one was. See common.py for the kit.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *

new_scene(141)
plinth(1.0, 0.85, cx=0.45, cy=0.15, pz=0.2)
HX, HY, POST_TOP, CX, CY = 0.85, 0.66, 1.25, 0.45, 0.15
for x in (CX - HX, CX + HX):
	for y in (CY - HY, CY + HY):
		box((0.18, 0.18, POST_TOP - 0.2), (x, y, (POST_TOP + 0.2) / 2), 'Wood', bevel=0.05)
		box((0.28, 0.28, 0.1), (x, y, 0.25), 'StoneDark', bevel=0.04)
for y in (CY - HY, CY + HY):
	box((HX * 2 + 0.2, 0.16, 0.16), (CX, y, POST_TOP - 0.06), 'Wood')
	for x, a in ((CX - HX + 0.2, 45), (CX + HX - 0.2, -45)):
		box((0.1, 0.12, 0.42), (x, y, POST_TOP - 0.22), 'Wood', rot=(0, a, 0))
gable_roof(HX * 2 + 0.45, HY, POST_TOP, cx=CX, cy=CY, pitch=34.0, over=0.28, gables=False, tile_rows=3)
# Planks stacked to dry under the roof, on bearers.
for y in (CY - 0.35, CY + 0.35):
	box((1.3, 0.1, 0.08), (CX, y, 0.28), 'WoodDark', bevel=0.02)
for k in range(5):
	for j in range(3):
		box((1.35 - (k % 2) * 0.06, 0.24, 0.07), (CX + (k % 2) * 0.03, CY - 0.28 + j * 0.28, 0.36 + k * 0.08),
				'LogEnd' if (k + j) % 3 == 0 else 'Wood', bevel=0.02, segments=2)
banner(0.36, 0.42, face(CX, CY - HY - 0.1, POST_TOP - 0.15, '-y'), swallow=False)

# A log pile, left, chocked by stakes.
def log(x, y, z, length=1.25, r=0.15):
	cylinder(r, length, (x, y, z), 'Log', verts=9, bevel=0.03, rot=(90, 0, 0))
	for e in (-1, 1):
		cylinder(r * 0.8, 0.02, (x, y + e * (length / 2 + 0.005), z), 'LogEnd', verts=9, bevel=0.0, rot=(90, 0, 0))
LX, LY = -0.85, 0.05
for i in range(4):
	log(LX - 0.45 + i * 0.3, LY, 0.15)
for i in range(3):
	log(LX - 0.3 + i * 0.3, LY + 0.04, 0.42)
log(LX - 0.15, LY - 0.02, 0.68)
log(LX + 0.15, LY + 0.03, 0.68)
for x in (LX - 0.66, LX + 0.66):
	box((0.07, 0.07, 0.7), (x, LY - 0.5, 0.35), 'WoodDark', rot=(0, 10 if x > LX else -10, 0))
	box((0.07, 0.07, 0.7), (x, LY + 0.5, 0.35), 'WoodDark', rot=(0, 10 if x > LX else -10, 0))
# Chopping block with an axe.
BX, BY = 0.3, -0.85
cylinder(0.24, 0.36, (BX, BY, 0.18), 'Log', verts=12, bevel=0.03)
cylinder(0.2, 0.02, (BX, BY, 0.36), 'LogEnd', verts=12, bevel=0.0)
# The handle leans up to -x; the head hangs off its foot on the -x (downhill)
# side, its edge sunk into the block's top.
f = Matrix.Translation((BX + 0.1, BY, 0.49)) @ Matrix.Rotation(math.radians(-35), 4, 'Y')
box((0.06, 0.06, 0.6), (0, 0, 0.28), 'Wood', bevel=0.02, matrix=f)
box((0.22, 0.05, 0.14), (-0.08, 0, 0.0), 'Iron', bevel=0.02, matrix=f)
box((0.25, 0.25, 0.06), (BX - 0.45, BY + 0.1, 0.03), 'LogEnd', rot=(0, 0, 25), bevel=0.02)
export('Lumberyard')
