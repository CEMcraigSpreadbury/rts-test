# Builds ArcheryRange.glb: an open-fronted shooting shed under a tiled roof,
# with two straw targets on stands out front. See common.py for the kit.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *

new_scene(31)
HX, HY, WALL_TOP, CY = 1.65, 0.8, 1.85, 0.5
plinth(1.9, 1.0, cy=CY)
# Back and side walls only; the front stands open on posts.
box((HX * 2, 0.16, WALL_TOP - PZ), (0, CY + HY - 0.08, (WALL_TOP + PZ) / 2), 'Plaster', bevel=0.04)
for x in (-HX + 0.08, HX - 0.08):
	box((0.16, HY * 2, WALL_TOP - PZ), (x, CY, (WALL_TOP + PZ) / 2), 'Plaster', bevel=0.04)
box((HX * 2 + 0.08, HY * 2 + 0.08, 0.3), (0, CY, PZ + 0.15), 'Stone', bevel=0.05)
for x in (-HX, -0.55, 0.55, HX):
	box((0.2, 0.2, WALL_TOP - PZ), (x, CY - HY, (WALL_TOP + PZ) / 2), 'Wood', bevel=0.05)
	box((0.3, 0.3, 0.14), (x, CY - HY, PZ + 0.07), 'StoneDark', bevel=0.04)
box((HX * 2 + 0.1, 0.2, 0.2), (0, CY - HY, WALL_TOP - 0.08), 'Wood', bevel=0.05)
for x in (-1.1, 0.0, 1.1):
	for a in (40, -40):
		box((0.1, 0.12, 0.42), (x + (0.14 if a > 0 else -0.14), CY - HY, WALL_TOP - 0.3), 'Wood', rot=(0, a, 0))
# Timber on the outside of the side walls.
for side, x in (('-x', -HX), ('+x', HX)):
	f = face(x, CY, 0, side)
	box((HY * 2 + 0.1, 0.16, 0.16), (0, -0.04, 1.2), 'Wood', matrix=f)
	box((0.15, 0.14, WALL_TOP - PZ), (0, -0.04, (WALL_TOP + PZ) / 2), 'Wood', matrix=f)
	shield(0.42, face(x + (-0.12 if side == '-x' else 0.12), CY, 1.55, side))
ridge = gable_roof(3.65, HY, WALL_TOP, cy=CY, pitch=38.0, over=0.32, hx=HX)
# Inside: a bow rack on the back wall and a bench of hay.
for i in range(4):
	x = -0.9 + i * 0.6
	box((0.06, 0.08, 0.7), (x, CY + HY - 0.2, 1.15), 'WoodDark', rot=(0, 0, 0))
	torus(0.24, 0.025, (x + 0.06, CY + HY - 0.22, 1.15), 'Wood', rot=(90, 0, 0))
hay_bale(-0.9, CY + 0.1, PZ + 0.06, 8)
hay_bale(0.95, CY + 0.15, PZ + 0.06, -6)
barrel(0.15, CY + 0.25, z=PZ + 0.06, r=0.16, h=0.4)
for i in range(5):
	cylinder(0.015, 0.5, (0.08 + (i % 3) * 0.06, CY + 0.22 + (i // 3) * 0.06, PZ + 0.62), 'Wood', verts=5, bevel=0.0)

# Targets on A-frame stands, facing the front.
def target(x, y, tilt):
	frame = Matrix.Translation((x, y, 0.0)) @ Matrix.Rotation(math.radians(tilt), 4, 'Z')
	for lx in (-0.22, 0.22):
		box((0.08, 0.08, 1.0), (lx, 0.16, 0.48), 'Wood', rot=(-14, 0, 0), matrix=frame)
	box((0.08, 0.08, 0.8), (0, 0.32, 0.4), 'Wood', rot=(30, 0, 0), matrix=frame)
	centre = frame @ Matrix.Translation((0, 0.08, 0.82)) @ Matrix.Rotation(math.radians(76), 4, 'X')
	cylinder(0.36, 0.14, (0, 0, 0), 'Hay', verts=20, bevel=0.04, matrix=centre)
	for r, c, d in ((0.28, 'Cloth', 0.16), (0.2, 'Red', 0.18), (0.12, 'Cloth', 0.2), (0.05, 'Red', 0.22)):
		cylinder(r, 0.02, (0, 0, d / 2), c, verts=20, bevel=0.0, matrix=centre)
	cylinder(0.012, 0.36, (0.05, -0.04, 0.2), 'Wood', verts=5, bevel=0.0, matrix=centre, rot=(10, 8, 0))
target(-1.0, -1.65, 10)
target(1.05, -1.75, -12)
export('ArcheryRange')
