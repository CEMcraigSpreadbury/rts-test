# Builds Bestiary.glb: a keeper's hall beside a big barred cage with an arched
# iron roof; bones, meat on a hook and hay about. The cage floor sits where
# ProductionBuilding puts the beast sprite when a model has no BeastSpot
# (BEAST_CAGE_FLOOR 0.36 high, 1.02 to the right, about BEAST_CAGE_WIDTH 1.8
# wide), so the beast stands inside it. See common.py for the kit.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *

new_scene(91)
plinth(2.2, 1.1, cx=-0.05)
# The keeper's hall, left.
HX, HY, WALL_TOP, CX = 0.72, 0.85, 1.8, -1.35
mid = hall(HX, HY, WALL_TOP, cx=CX, braces=False, mid_z=1.3)
ridge = gable_roof(1.75, HY, WALL_TOP, cx=CX, pitch=44.0, over=0.28, hx=HX, tile_rows=4)
door(face(CX, -HY - 0.07, PZ, '-y'), w=0.5, h=0.9)
window(face(CX - HX - 0.03, 0, 1.05, '-x'), w=0.3, h=0.34)
for y in (-HY, HY):
	for x in (CX - HX, CX + HX):
		quoins(x, y, PZ + 0.3, mid - 0.1, size=0.22)
banner(0.42, 0.55, face(CX, -HY - 0.12, mid + 0.42, '-y'), swallow=False)
flag(CX, 0, ridge + 0.1, 0.8)

# The cage, right.
GX, FLOOR, GW, GD, GH = 1.02, 0.36, 2.0, 1.7, 1.45
box((GW + 0.2, GD + 0.2, FLOOR), (GX, 0, FLOOR / 2), 'StoneDark', bevel=0.06)
box((GW, GD, 0.06), (GX, 0, FLOOR - 0.02), 'Hay', bevel=0.02)
TOP = FLOOR + GH
for cx in (-1, 1):
	for cy in (-1, 1):
		box((0.16, 0.16, GH), (GX + cx * GW / 2, cy * GD / 2, FLOOR + GH / 2), 'IronDark', bevel=0.04)
for cy in (-1, 1):
	box((GW + 0.16, 0.12, 0.12), (GX, cy * GD / 2, TOP), 'IronDark', bevel=0.04)
	box((GW + 0.16, 0.1, 0.1), (GX, cy * GD / 2, FLOOR + 0.08), 'IronDark', bevel=0.03)
for cx in (-1, 1):
	box((0.12, GD + 0.16, 0.12), (GX + cx * GW / 2, 0, TOP), 'IronDark', bevel=0.04)
	box((0.1, GD + 0.16, 0.1), (GX + cx * GW / 2, 0, FLOOR + 0.08), 'IronDark', bevel=0.03)
# Bars: thin, so the beast shows between them.
for cy in (-1, 1):
	for i in range(1, 8):
		x = GX - GW / 2 + GW * i / 8
		cylinder(0.025, GH, (x, cy * GD / 2, FLOOR + GH / 2), 'IronDark', verts=6, bevel=0.0)
for cx in (-1, 1):
	for i in range(1, 6):
		y = -GD / 2 + GD * i / 6
		cylinder(0.025, GH, (GX + cx * GW / 2, y, FLOOR + GH / 2), 'IronDark', verts=6, bevel=0.0)
# Arched roof straps over the top, front to back, and a team plate on the front.
for i in range(5):
	x = GX - GW / 2 + GW * i / 4
	for k in range(7):
		a = math.radians(180 * (k + 0.5) / 7)
		# Along the arch's tangent: (y, z) = (-cos a * GD/2, sin a * 0.45) turns
		# by atan2(dz, dy) about X.
		tilt = math.degrees(math.atan2(0.45 * math.cos(a), GD / 2 * math.sin(a)))
		box((0.08, GD / 7 * 1.3, 0.07), (x, -math.cos(a) * GD / 2, TOP + math.sin(a) * 0.45), 'IronDark',
				rot=(tilt, 0, 0), bevel=0.02, segments=2)
cylinder(0.04, GW + 0.1, (GX, 0, TOP + 0.45), 'IronDark', verts=8, bevel=0.0, rot=(0, 90, 0))
torus(0.12, 0.03, (GX, 0, TOP + 0.6), 'Iron', rot=(90, 0, 0))
shield(0.42, face(GX, -GD / 2 - 0.09, TOP - 0.2, '-y'))

# Bones, a hanging haunch, a bucket, hay.
for i, (x, y, a) in enumerate(((0.3, -1.25, 20), (0.6, -1.35, -35), (-0.4, -1.3, 70))):
	f = Matrix.Translation((x, y, 0.06)) @ Matrix.Rotation(math.radians(a), 4, 'Z')
	box((0.45, 0.07, 0.07), (0, 0, 0), 'Bone', bevel=0.03, matrix=f)
	for e in (-1, 1):
		sphere(0.06, (e * 0.24, 0.03, 0), 'Bone', matrix=f)
		sphere(0.06, (e * 0.24, -0.03, 0), 'Bone', matrix=f)
box((0.08, 0.08, 1.3), (-0.45, -1.0, 0.65), 'Wood')
box((0.5, 0.08, 0.08), (-0.25, -1.0, 1.26), 'Wood')
cylinder(0.012, 0.3, (-0.08, -1.0, 1.08), 'Iron', verts=5, bevel=0.0)
box((0.2, 0.16, 0.3), (-0.08, -1.0, 0.82), 'Meat', bevel=0.07, segments=3)
box((0.06, 0.06, 0.14), (-0.08, -1.0, 1.0), 'Bone', bevel=0.02)
cylinder(0.15, 0.24, (2.25, -0.95, 0.12), 'Wood', verts=10, bevel=0.02, radius2=0.18)
hay_bale(-2.2, -0.95, 0.0, 70)
export('Bestiary')
