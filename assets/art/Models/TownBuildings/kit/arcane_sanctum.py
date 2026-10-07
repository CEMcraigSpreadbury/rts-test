# Builds ArcaneSanctum.glb: a round wizard's tower of chunky stone with violet
# glowing windows and a tall team-blue cone topped by a crystal, a small
# study hall beside it, and runestones round a floating crystal out front.
# See common.py for the kit.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *

new_scene(101)
plinth(1.65, 1.15, cx=0.25, cy=-0.1)
TX, TY, TR, TTOP = -0.45, 0.0, 0.72, 3.55
cylinder(TR, TTOP - PZ, (TX, TY, (TTOP + PZ) / 2), 'Stone', verts=16, bevel=0.04)
cylinder(TR + 0.1, 0.36, (TX, TY, PZ + 0.18), 'StoneDark', verts=16, bevel=0.05)
# Courses of proud stones round the drum, staggered.
for k in range(7):
	z = PZ + 0.5 + k * 0.42
	for i in range(8):
		a = math.radians(i * 45 + (22.5 if k % 2 else 0) + random.uniform(-6, 6))
		f = Matrix.Translation((TX + math.cos(a) * TR, TY + math.sin(a) * TR, z)) @ Matrix.Rotation(a + math.pi / 2, 4, 'Z')
		box((0.36 + random.uniform(-0.05, 0.05), 0.14, 0.3), (0, 0, 0), 'StoneDark' if (i + k) % 4 == 0 else 'Stone',
				bevel=0.05, matrix=f)
# Violet windows, spiralling up.
for k, a_deg in enumerate((-90, -30, -150, -70)):
	a = math.radians(a_deg)
	f = Matrix.Translation((TX + math.cos(a) * (TR + 0.04), TY + math.sin(a) * (TR + 0.04), 1.2 + k * 0.6)) \
		@ Matrix.Rotation(a + math.pi / 2, 4, 'Z')
	box((0.2, 0.08, 0.36), (0, 0, 0), 'Arcane', bevel=0.03, matrix=f)
	box((0.32, 0.12, 0.08), (0, 0.0, 0.22), 'StoneDark', bevel=0.03, matrix=f)
	box((0.32, 0.12, 0.08), (0, 0.0, -0.22), 'StoneDark', bevel=0.03, matrix=f)
# A corbelled ring, then the cone.
cylinder(TR + 0.16, 0.16, (TX, TY, TTOP + 0.02), 'StoneDark', verts=16, bevel=0.05)
cylinder(TR + 0.3, 0.12, (TX, TY, TTOP + 0.14), 'TeamColorDark', verts=16, bevel=0.04)
pyramid(2 * (TR + 0.26), 1.5, (TX, TY, TTOP + 0.18), 'TeamColor', sides=16)
cylinder(0.08, 0.3, (TX, TY, TTOP + 1.72), 'Gold', verts=8, bevel=0.02)
for h, s in ((0.2, 1), (0.2, -1)):
	cylinder(0.14, h, (TX, TY, TTOP + 2.0 + s * h / 2), 'Arcane', verts=6, bevel=0.0, radius2=0.0, rot=(0 if s > 0 else 180, 0, 0))
door(face(TX, TY - TR - 0.06, PZ + 0.04, '-y'), w=0.48, h=0.86, arch='stone')

# The study hall, right.
HX, HY, WALL_TOP, CX = 0.62, 0.62, 1.55, 0.95
mid = hall(HX, HY, WALL_TOP, cx=CX, braces=False, mid_z=1.18)
gable_roof(1.55, HY, WALL_TOP, cx=CX, pitch=45.0, over=0.26, hx=HX, tile_rows=4)
window(face(CX, -HY - 0.03, 0.85, '-y'), w=0.34, h=0.34)
box((0.34, 0.07, 0.36), (CX, -HY - 0.02, 0.85), 'Arcane', bevel=0.02)
window(face(CX + HX + 0.03, 0, 0.88, '+x'), w=0.3, h=0.32)
banner(0.36, 0.5, face(CX, -HY - 0.12, WALL_TOP - 0.05, '-y'), swallow=False)

# Runestones round a floating crystal, front left.
RX, RY = 0.45, -1.15
for i in range(3):
	a = math.radians(200 + i * 70)
	x, y = RX + math.cos(a) * 0.45, RY + math.sin(a) * 0.35
	box((0.18, 0.12, 0.42 + i * 0.06), (x, y, (0.42 + i * 0.06) / 2), 'Stone', rot=(0, 0, math.degrees(a)), bevel=0.05)
	box((0.08, 0.13, 0.12), (x, y, 0.3), 'Arcane', rot=(0, 0, math.degrees(a)), bevel=0.02)
cylinder(0.16, 0.22, (RX, RY, 0.11), 'StoneDark', verts=8, bevel=0.04)
for s in (1, -1):
	cylinder(0.13, 0.22, (RX, RY, 0.62 + s * 0.11), 'Arcane', verts=6, bevel=0.0, radius2=0.0, rot=(0 if s > 0 else 180, 0, 0))
export('ArcaneSanctum')
