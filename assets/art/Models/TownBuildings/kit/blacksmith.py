# Builds Blacksmith.glb: a smithy cottage with an open forge under a lean-to
# on its right: glowing hearth, tall stone stack, anvil on a stump, quench
# barrel and a tool rack. See common.py for the kit.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *

new_scene(51)
HX, HY, WALL_TOP, CX = 0.95, 0.85, 1.75, -0.4
plinth(1.9, 1.05, cx=0.45)
mid = hall(HX, HY, WALL_TOP, cx=CX, braces=False, mid_z=1.3)
gable_roof(2.2, HY, WALL_TOP, cx=CX, pitch=44.0, over=0.28, hx=HX, tile_rows=4)
door_x, window_x = bay_centres(HX)
door(face(CX + door_x, -HY - 0.07, PZ, '-y'), w=0.52, h=0.92)
window(face(CX + window_x, -HY - 0.03, 0.9, '-y'), w=0.34, h=0.34)
window(face(CX + window_x, -HY - 0.03, 1.55, '-y'), w=0.3, h=0.3, shutters=False)
window(face(CX - HX - 0.03, 0, 1.0, '-x'), w=0.32, h=0.34)
for y in (-HY, HY):
	for x in (CX - HX, CX + HX):
		quoins(x, y, PZ + 0.3, mid - 0.1, size=0.24)
# A sign: crossed hammers would be fussy at this size; an anvil board.
f = face(CX + door_x - 0.55, -HY - 0.3, mid + 0.05, '-y')
box((0.06, 0.06, 0.3), (0.0, 0.0, 0.12), 'IronDark', matrix=f)
box((0.42, 0.06, 0.3), (0, -0.02, -0.12), 'Wood', bevel=0.03, matrix=f)
box((0.26, 0.07, 0.08), (0, -0.05, -0.08), 'IronDark', bevel=0.02, matrix=f)
box((0.14, 0.07, 0.1), (0, -0.05, -0.17), 'IronDark', bevel=0.02, matrix=f)

# The forge: a lean-to off the right wall, open to the front.
FX0 = CX + HX
FX1 = 2.25
low = shed_roof(FX0, 0.0, WALL_TOP - 0.1, 2.0, FX1 - FX0 + 0.2, '+x', pitch=22.0)
for y in (-0.82, 0.82):
	box((0.18, 0.18, low - PZ), (FX1 - 0.05, y, (low + PZ) / 2), 'Wood', bevel=0.05)
	box((0.28, 0.28, 0.12), (FX1 - 0.05, y, PZ + 0.06), 'StoneDark', bevel=0.04)
box((0.16, 1.82, 0.16), (FX1 - 0.05, 0, low - 0.04), 'Wood')
# Back wall of the forge, stone.
box((FX1 - FX0, 0.22, low - PZ + 0.1), ((FX0 + FX1) / 2, 0.82, (low + PZ) / 2), 'Stone', bevel=0.05)
# Hearth with glowing coals, and its stack up through the roof.
HXF, HYF = FX0 + 0.55, 0.35
box((0.8, 0.7, 0.55), (HXF, HYF, PZ + 0.275), 'Stone', bevel=0.06)
box((0.62, 0.52, 0.08), (HXF, HYF, PZ + 0.56), 'IronDark', bevel=0.02)
for i in range(6):
	sphere(0.07 + random.uniform(0, 0.03), (HXF - 0.18 + (i % 3) * 0.18, HYF - 0.1 + (i // 3) * 0.2, PZ + 0.62), 'Ember')
box((0.62, 0.55, 0.5), (HXF, HYF + 0.12, PZ + 0.95), 'Stone', bevel=0.05)
chimney(HXF, HYF + 0.2, PZ + 1.2, 3.0)
# Anvil on a stump, quench barrel, a rack of tools.
AX, AY = FX0 + 0.75, -0.45
cylinder(0.2, 0.38, (AX, AY, PZ + 0.19), 'Log', verts=10, bevel=0.03)
box((0.18, 0.14, 0.14), (AX, AY, PZ + 0.45), 'IronDark', bevel=0.03)
box((0.42, 0.2, 0.1), (AX, AY, PZ + 0.57), 'IronDark', bevel=0.03)
box((0.16, 0.12, 0.06), (AX + 0.26, AY, PZ + 0.59), 'IronDark', bevel=0.02, rot=(0, 15, 0))
box((0.06, 0.06, 0.22), (AX - 0.05, AY - 0.04, PZ + 0.68), 'Wood', rot=(0, 70, 0), bevel=0.015)
box((0.1, 0.12, 0.1), (AX + 0.03, AY - 0.04, PZ + 0.66), 'Iron', bevel=0.02)
barrel(FX1 - 0.25, -0.75, z=0.0, r=0.2, h=0.44)
cylinder(0.17, 0.02, (FX1 - 0.25, -0.75, 0.45), 'TeamColorDark', verts=12, bevel=0.0)
for i, ang in enumerate((0, 8, -6)):
	box((0.05, 0.05, 0.6), (FX0 + 0.25 + i * 0.16, 0.66, PZ + 0.85), 'Wood', rot=(0, ang, 0), bevel=0.015)
	box((0.14, 0.08, 0.1), (FX0 + 0.25 + i * 0.16, 0.64, PZ + 1.15), 'IronDark', bevel=0.02)
crate(-1.45, -1.0, 0.0, 0.3, 10)
export('Blacksmith')
