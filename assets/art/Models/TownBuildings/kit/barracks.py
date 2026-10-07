# Builds Barracks.glb: a long stone-cornered hall with a double door, the team
# shield on its gables, a spear rack and a training dummy out front. See
# common.py for the kit.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *

new_scene(21)
HX, HY, WALL_TOP, CY = 1.55, 0.92, 1.95, 0.15
plinth(1.85, 1.15, cy=CY)
mid = hall(HX, HY, WALL_TOP, cy=CY, braces=False, mid_z=1.35)
ridge = gable_roof(3.5, HY, WALL_TOP, cy=CY, pitch=40.0, over=0.32, hx=HX)
flag(1.5, CY, ridge + 0.1, 0.9)
# Crossed swords on the front slope, the barracks' mark.
PITCH, OVER = 40.0, 0.32
half_span = HY + OVER
rise = half_span * math.tan(math.radians(PITCH))
slope = Matrix.Translation((0, CY - half_span / 2, WALL_TOP - roof_drop(OVER, PITCH) + rise / 2 + 0.08)) \
	@ Matrix.Rotation(math.radians(PITCH), 4, 'X')
for a in (38, -38):
	sword = slope @ Matrix.Translation((0, 0.05, 0.26)) @ Matrix.Rotation(math.radians(a), 4, 'Z')
	box((0.13, 1.15, 0.06), (0, 0.18, 0), 'Iron', bevel=0.025, matrix=sword)
	box((0.42, 0.09, 0.08), (0, -0.42, 0), 'Gold', bevel=0.03, matrix=sword)
	box((0.08, 0.26, 0.07), (0, -0.58, 0), 'WoodDark', bevel=0.025, matrix=sword)
	sphere(0.06, (0, -0.73, 0), 'Gold', matrix=sword)
left, centre, right = bay_centres(HX)
fy = CY - HY
door(face(centre, fy - 0.07, PZ, '-y'), w=0.78, h=0.98, arch='stone')
box((1.2, 0.34, 0.1), (centre, fy - 0.3, PZ - 0.05), 'Stone', bevel=0.04)
for x in (left, right):
	window(face(x, fy - 0.03, 1.65, '-y'), w=0.36, h=0.42)
	window(face(x, fy - 0.03, 0.85, '-y'), w=0.3, h=0.3, shutters=False)
for x in bay_centres(HX):
	window(face(x, CY + HY + 0.03, 1.65, '+y'), w=0.34, h=0.38)
for y in (CY - HY, CY + HY):
	for x in (-HX, HX):
		quoins(x, y, PZ + 0.3, WALL_TOP - 0.1, size=0.26)
for side, x in (('-x', -HX - 0.12), ('+x', HX + 0.12)):
	shield(0.48, face(x, CY, WALL_TOP + 0.38, side))
	window(face(-HX - 0.03 if side == '-x' else HX + 0.03, CY, 1.1, side), w=0.32, h=0.36)
banner(0.5, 0.7, face(left - 0.62, fy - 0.12, mid - 0.04, '-y'))

# Spear rack, front left.
RX, RY = -1.25, -1.35
for x in (RX - 0.38, RX + 0.38):
	box((0.1, 0.1, 0.8), (x, RY, 0.4), 'Wood')
box((0.9, 0.1, 0.1), (RX, RY, 0.66), 'Wood')
box((0.9, 0.1, 0.08), (RX, RY, 0.24), 'WoodDark')
for i in range(4):
	x = RX - 0.27 + i * 0.18
	cylinder(0.025, 1.15, (x, RY - 0.06, 0.58), 'Wood', verts=6, bevel=0.0, rot=(-8, 0, 0))
	cylinder(0.05, 0.16, (x, RY - 0.14, 1.2), 'Iron', verts=4, bevel=0.0, radius2=0.0, rot=(-8, 0, 0))

# Training dummy, front right.
DX, DY = 1.3, -1.3
box((0.1, 0.1, 1.0), (DX, DY, 0.5), 'Wood')
box((0.62, 0.08, 0.08), (DX, DY, 0.82), 'Wood')
box((0.32, 0.22, 0.42), (DX, DY, 0.68), 'Sack', bevel=0.09, segments=3)
sphere(0.13, (DX, DY, 1.03), 'Sack')
box((0.2, 0.05, 0.28), (DX, DY - 0.13, 0.68), 'Red', bevel=0.02)
barrel(1.75, -0.95, z=0.0, r=0.17, h=0.4)
export('Barracks')
