# Builds Granary.glb: a round plaster grain silo under a team-blue cone, with
# a small timber-framed barn beside it and sacks piled at the door. See
# common.py for the kit.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *

new_scene(131)
plinth(1.55, 0.95, cx=-0.2)
# The barn, left.
HX, HY, WALL_TOP, CX = 0.6, 0.68, 1.5, -0.95
mid = hall(HX, HY, WALL_TOP, cx=CX, braces=False, mid_z=1.18)
gable_roof(1.5, HY, WALL_TOP, cx=CX, pitch=45.0, over=0.26, hx=HX, tile_rows=4)
door(face(CX, -HY - 0.07, PZ, '-y'), w=0.5, h=0.84)
window(face(CX - HX - 0.03, 0, 0.9, '-x'), w=0.3, h=0.32)
for y in (-HY, HY):
	for x in (CX - HX, CX + HX):
		quoins(x, y, PZ + 0.3, mid - 0.08, size=0.22)
# The silo, right.
SX, SY, SR, STOP = 0.5, 0.05, 0.66, 2.15
cylinder(SR + 0.08, 0.4, (SX, SY, PZ + 0.2), 'Stone', verts=14, bevel=0.05)
for i in range(14):
	a = math.radians(i * 360 / 14 + 12)
	f = Matrix.Translation((SX + math.cos(a) * (SR + 0.08), SY + math.sin(a) * (SR + 0.08), PZ + 0.2)) \
		@ Matrix.Rotation(a + math.pi / 2, 4, 'Z')
	box((0.3, 0.12, 0.3 + random.uniform(-0.04, 0.04)), (0, 0, 0), 'StoneDark' if i % 3 == 0 else 'Stone', bevel=0.05, matrix=f)
cylinder(SR, STOP - PZ - 0.4, (SX, SY, (STOP + PZ + 0.4) / 2), 'Plaster', verts=14, bevel=0.04)
for z in (1.15, 1.75):
	cylinder(SR + 0.03, 0.12, (SX, SY, z), 'Wood', verts=14, bevel=0.03)
for i in range(4):
	a = math.radians(i * 90 + 45)
	f = Matrix.Translation((SX + math.cos(a) * (SR + 0.02), SY + math.sin(a) * (SR + 0.02), (STOP + PZ + 0.4) / 2)) \
		@ Matrix.Rotation(a + math.pi / 2, 4, 'Z')
	box((0.12, 0.1, STOP - PZ - 0.4), (0, 0, 0), 'Wood', bevel=0.03, matrix=f)
# Hay hatch, high on the front.
f = Matrix.Translation((SX, SY - SR - 0.02, 1.45))
box((0.36, 0.06, 0.34), (0, 0.02, 0), 'Window', bevel=0.02, matrix=f)
box((0.3, 0.1, 0.12), (0, -0.04, -0.12), 'Hay', bevel=0.04, matrix=f)
box((0.46, 0.1, 0.07), (0, -0.04, 0.21), 'Wood', matrix=f)
cylinder(SR + 0.16, 0.14, (SX, SY, STOP + 0.04), 'TeamColorDark', verts=14, bevel=0.04)
pyramid(2 * (SR + 0.14), 1.0, (SX, SY, STOP + 0.1), 'TeamColor', sides=14)
sphere(0.08, (SX, SY, STOP + 1.14), 'Gold')
# Sacks and a weighing beam out front.
sack(-0.35, -0.95, 0.0, 15)
sack(-0.05, -1.0, 0.0, -20)
sack(-0.2, -0.95, 0.32, 5)
sack(1.2, -0.65, 0.0, 30)
box((0.08, 0.08, 0.9), (0.85, -0.95, 0.45), 'Wood')
box((0.6, 0.06, 0.06), (0.85, -0.95, 0.88), 'Wood')
for x in (0.6, 1.1):
	cylinder(0.01, 0.3, (x, -0.95, 0.72), 'Sack', verts=4, bevel=0.0)
	cylinder(0.11, 0.04, (x, -0.95, 0.56), 'Iron', verts=10, bevel=0.01)
export('Granary')
