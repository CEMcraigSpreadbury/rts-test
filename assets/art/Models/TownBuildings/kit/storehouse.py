# Builds Storehouse.glb: a stout stone-cornered barn with big double doors, a
# hoist beam, and sacks, crates and barrels piled out front. See common.py for
# the kit.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *

new_scene(41)
HX, HY, WALL_TOP, CY = 1.3, 0.92, 1.7, 0.2
plinth(1.5, 1.08, cy=CY)
mid = hall(HX, HY, WALL_TOP, cy=CY, braces=False, mid_z=1.38)
ridge = gable_roof(2.95, HY, WALL_TOP, cy=CY, pitch=38.0, over=0.3, hx=HX)
left, centre, right = bay_centres(HX)
fy = CY - HY
# Barn doors, braced in a Z.
for side in (-1, 1):
	f = face(centre + side * 0.17, fy - 0.07, PZ, '-y')
	box((0.33, 0.08, 1.02), (0, 0.01, 0.51), 'Wood', bevel=0.03, matrix=f)
	for z in (0.16, 0.86):
		box((0.35, 0.05, 0.09), (0, -0.04, z), 'WoodDark', bevel=0.02, matrix=f)
	box((0.07, 0.05, 0.78), (0, -0.04, 0.51), 'WoodDark', rot=(0, side * 22, 0), bevel=0.02, matrix=f)
	sphere(0.04, (-side * 0.12, -0.08, 0.5), 'Iron', matrix=f)
box((0.85, 0.16, 0.14), (centre, fy - 0.08, PZ + 1.08), 'Wood')
box((1.0, 0.34, 0.1), (centre, fy - 0.3, PZ - 0.05), 'Stone', bevel=0.04)
for x in (left, right):
	window(face(x, fy - 0.03, 1.0, '-y'), w=0.3, h=0.34)
for y in (CY - HY, CY + HY):
	for x in (-HX, HX):
		quoins(x, y, PZ + 0.3, WALL_TOP - 0.1, size=0.26)
# Hoist: a beam out of the gable with a rope and hook.
box((0.7, 0.14, 0.14), (HX + 0.3, CY, WALL_TOP + 0.55), 'Wood')
cylinder(0.018, 0.75, (HX + 0.55, CY, WALL_TOP + 0.15), 'Sack', verts=5, bevel=0.0)
torus(0.06, 0.018, (HX + 0.55, CY, WALL_TOP - 0.24), 'Iron', rot=(90, 0, 0))
banner(0.46, 0.6, face(-HX - 0.1, CY, mid - 0.03, '-x'))
# Goods out front.
sack(-1.15, -1.0, 0.0, 10)
sack(-0.85, -1.08, 0.0, -14)
sack(-1.0, -0.98, 0.32, 30)
crate(0.95, -0.95, 0.0, 0.36, 8)
crate(1.3, -0.75, 0.0, 0.32, -10)
crate(1.02, -0.95, 0.36, 0.26, 20)
barrel(-1.55, -0.55, z=0.0, r=0.17, h=0.42)
export('Storehouse')
