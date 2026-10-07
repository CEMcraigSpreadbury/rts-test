# Builds SiegeWorkshop.glb: a big open-fronted timber workshop with a catapult
# half-built inside, a crane beam, and logs, a spare wheel and a sawhorse out
# front. See common.py for the kit.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *

new_scene(71)
HX, HY, WALL_TOP, CY = 1.75, 0.95, 2.05, 0.45
plinth(1.95, 1.1, cy=CY)
# Back and side walls; the front stands open on heavy posts.
box((HX * 2, 0.18, WALL_TOP - PZ), (0, CY + HY - 0.09, (WALL_TOP + PZ) / 2), 'Plaster', bevel=0.04)
for x in (-HX + 0.09, HX - 0.09):
	box((0.18, HY * 2, WALL_TOP - PZ), (x, CY, (WALL_TOP + PZ) / 2), 'Plaster', bevel=0.04)
box((HX * 2 + 0.08, HY * 2 + 0.08, 0.3), (0, CY, PZ + 0.15), 'Stone', bevel=0.05)
for x in (-HX, -0.6, 0.6, HX):
	box((0.24, 0.24, WALL_TOP - PZ), (x, CY - HY, (WALL_TOP + PZ) / 2), 'Wood', bevel=0.06)
	box((0.34, 0.34, 0.14), (x, CY - HY, PZ + 0.07), 'StoneDark', bevel=0.04)
box((HX * 2 + 0.12, 0.24, 0.24), (0, CY - HY, WALL_TOP - 0.1), 'Wood', bevel=0.06)
for x in (-1.18, 0.0, 1.18):
	for a in (40, -40):
		box((0.12, 0.14, 0.5), (x + (0.17 if a > 0 else -0.17), CY - HY, WALL_TOP - 0.36), 'Wood', rot=(0, a, 0))
for side, x in (('-x', -HX), ('+x', HX)):
	f = face(x, CY, 0, side)
	box((HY * 2 + 0.1, 0.16, 0.16), (0, -0.04, 1.3), 'Wood', matrix=f)
	for y in (-0.5, 0.5):
		box((0.15, 0.14, WALL_TOP - PZ), (y, -0.04, (WALL_TOP + PZ) / 2), 'Wood', matrix=f)
	window(face(x + (-0.04 if side == '-x' else 0.04), CY, 1.65, side), w=0.32, h=0.32)
ridge = gable_roof(3.8, HY, WALL_TOP, cy=CY, pitch=38.0, over=0.32, hx=HX)
shield(0.5, face(HX + 0.14, CY, WALL_TOP + 0.4, '+x'))
shield(0.5, face(-HX - 0.14, CY, WALL_TOP + 0.4, '-x'))
# Crane: a beam out over the front with a hook and a hanging stone.
box((0.16, 1.1, 0.16), (1.2, CY - HY - 0.45, WALL_TOP - 0.05), 'Wood')
cylinder(0.018, 0.55, (1.2, CY - HY - 0.9, WALL_TOP - 0.38), 'Sack', verts=5, bevel=0.0)
box((0.3, 0.3, 0.26), (1.2, CY - HY - 0.9, WALL_TOP - 0.8), 'Stone', bevel=0.07)

# A catapult on the floor inside, half-built.
def wheel(x, y, z, r, rot=(0, 0, 90)):
	cylinder(r, 0.1, (x, y, z), 'Wood', verts=14, bevel=0.03, rot=rot)
	cylinder(r * 0.3, 0.14, (x, y, z), 'IronDark', verts=8, bevel=0.02, rot=rot)
	for k in range(4):
		box((0.06, 0.05, r * 1.7), (x, y, z), 'WoodDark', rot=(rot[0] + k * 45, 0, rot[2] - 90) if rot[2] == 90 else rot,
				bevel=0.01)
CYC = CY + 0.05
for x in (-0.55, 0.55):
	box((0.16, 1.2, 0.14), (x * 0.9, CYC, PZ + 0.38), 'Wood')
for y in (-0.4, 0.4):
	box((1.05, 0.14, 0.14), (0, CYC + y, PZ + 0.38), 'Wood')
	for x in (-0.55, 0.55):
		wheel(x, CYC + y, PZ + 0.24, 0.24)
for x in (-0.3, 0.3):
	box((0.12, 0.12, 0.9), (x, CYC + 0.05, PZ + 0.85), 'Wood', rot=(-12, 0, 0))
box((0.75, 0.14, 0.14), (0, CYC + 0.12, PZ + 1.25), 'Wood')
box((0.1, 0.1, 1.2), (0, CYC - 0.1, PZ + 0.85), 'WoodDark', rot=(55, 0, 0))
box((0.3, 0.26, 0.12), (0, CYC - 0.6, PZ + 0.5), 'Sack', bevel=0.05, rot=(55, 0, 0))

# Out front: a log pile, a spare wheel leaning on a post, a sawhorse.
for i, (x, z) in enumerate(((-1.55, 0.14), (-1.3, 0.14), (-1.05, 0.14), (-1.42, 0.38), (-1.17, 0.38))):
	cylinder(0.13, 0.9, (x, -1.2, z), 'Log', verts=9, bevel=0.03, rot=(90, 0, 0))
	for e in (-1, 1):
		cylinder(0.105, 0.02, (x, -1.2 + e * 0.455, z), 'LogEnd', verts=9, bevel=0.0, rot=(90, 0, 0))
wheel(1.75, -1.0, 0.36, 0.34, rot=(0, 18, 90))
for x in (0.55, 1.15):
	for a in (20, -20):
		box((0.06, 0.06, 0.5), (x, -1.45, 0.22), 'Wood', rot=(a, 0, 0), bevel=0.015)
box((0.75, 0.08, 0.08), (0.85, -1.45, 0.45), 'Wood')
box((0.9, 0.24, 0.05), (0.85, -1.45, 0.52), 'Log', rot=(0, 0, 8), bevel=0.015)
export('SiegeWorkshop')
