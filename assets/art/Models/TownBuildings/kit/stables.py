# Builds Stables.glb: a long low stable of split stall doors, a hay loft in the
# gable, the iron horseshoe on its roof, and a little paddock with a trough.
# See common.py for the kit.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *

new_scene(61)
HX, HY, WALL_TOP, CX, CY = 1.6, 0.85, 1.55, -0.15, 0.2
PITCH, OVER = 34.0, 0.32
plinth(1.85, 1.05, cx=CX, cy=CY)
mid = hall(HX, HY, WALL_TOP, cx=CX, cy=CY, braces=False, mid_z=1.3)
ridge = gable_roof(3.45, HY, WALL_TOP, cx=CX, cy=CY, pitch=PITCH, over=OVER, hx=HX, tile_rows=4)
fy = CY - HY
# Split stall doors: the lower half shut, the upper open on the dark stall.
for x in bay_centres(HX):
	f = face(CX + x, fy - 0.07, PZ, '-y')
	box((0.74, 0.08, 0.5), (0, 0.01, 0.25 + 0.02), 'Wood', bevel=0.03, matrix=f)
	for k in range(3):
		box((0.2, 0.06, 0.46), (-0.24 + k * 0.24, -0.03, 0.27), 'WoodDark' if k == 1 else 'Wood', bevel=0.02, matrix=f)
	box((0.72, 0.06, 0.07), (0, -0.06, 0.08), 'WoodDark', rot=(0, 34, 0), bevel=0.02, matrix=f)
	box((0.7, 0.04, 0.42), (0, 0.04, 0.76), 'Window', bevel=0.02, matrix=f)
	box((0.8, 0.12, 0.1), (0, -0.05, 0.53), 'Wood', matrix=f)
	for side in (-1, 1):
		box((0.12, 0.13, 1.0), (side * 0.43, -0.04, 0.5), 'Wood', matrix=f)
# Hay loft door in each gable, hay spilling out.
for side, sx in (('-x', -1), ('+x', 1)):
	gx = CX + sx * (HX + 0.08)
	box((0.08, 0.5, 0.42), (gx, CY, WALL_TOP + 0.28), 'Window', bevel=0.02)
	box((0.12, 0.62, 0.08), (gx + sx * 0.03, CY, WALL_TOP + 0.05), 'Wood')
	box((0.14, 0.42, 0.14), (gx + sx * 0.06, CY, WALL_TOP + 0.12), 'Hay', bevel=0.05)
	window(face(gx - sx * 0.05, CY, 0.95, side), w=0.32, h=0.34)
for y in (CY - HY, CY + HY):
	for x in (CX - HX, CX + HX):
		quoins(x, y, PZ + 0.3, mid - 0.05, size=0.24)
# The horseshoe on the front slope, the stables' mark.
half_span = HY + OVER
rise = half_span * math.tan(math.radians(PITCH))
slope = Matrix.Translation((CX, CY - half_span / 2, WALL_TOP - roof_drop(OVER, PITCH) + rise / 2 + 0.08)) \
	@ Matrix.Rotation(math.radians(PITCH), 4, 'X')
horseshoe(0.95, slope @ Matrix.Translation((0, 0.05, 0.2)) @ Matrix.Rotation(math.radians(-90), 4, 'X'), 'Gold')
flag(CX - 1.5, CY, ridge + 0.1, 0.8)

# Paddock out front right: a fence, a trough, hay.
fence(0.55, -1.15, 2.2, -1.15)
fence(2.2, -1.15, 2.2, -0.2)
box((0.9, 0.34, 0.26), (1.4, -0.75, 0.13), 'Wood', bevel=0.05)
box((0.78, 0.24, 0.04), (1.4, -0.75, 0.25), 'TeamColorDark', bevel=0.01)
hay_bale(-1.45, -1.0, 0.0, 12)
hay_bale(-1.0, -1.1, 0.0, -8)
hay_bale(-1.22, -1.05, 0.32, 4)
cylinder(0.12, 0.2, (0.5, -0.75, 0.1), 'Wood', verts=10, bevel=0.02, radius2=0.15)
export('Stables')
