# Builds Sanctum.glb: the druids' grove, a ring of rope-bound standing stones
# round a great toy oak hung with team ribbons, an antlered skull altar and a
# glowing spirit stone at its foot. See beastmen_common.py.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from beastmen_common import *

new_scene(381)
mound(1.62, 1.62, gap=(255, 285))
ring_solid(1.0, 1.0, 0.04, (0, 0, MZ), 'Moss', n=16, amp=0.05, sx=1.12, sy=1.12, bevel=0.02, angle=40)
# The standing stones, gap at the front.
for k in range(8):
	a = math.radians(-90 + 360 * (k + 0.5) / 9 + 20)
	x, y = math.cos(a) * 1.28, math.sin(a) * 1.28
	h = 0.95 + 0.25 * ((k * 7) % 3) / 2
	turn = math.degrees(a) + 90
	box((0.34, 0.24, h), (x, y, MZ + h / 2 - 0.04), 'Stone' if k % 2 else 'StoneDark', rot=(random.uniform(-5, 5), 0, turn),
			bevel=0.1, segments=2)
	box((0.3, 0.22, 0.07), (x, y, MZ + h - 0.06), 'Moss', rot=(0, 0, turn), bevel=0.03, segments=2)
	box((0.37, 0.27, 0.07), (x, y, MZ + h * 0.55), 'TeamColor' if k % 2 == 0 else 'Rope', rot=(0, 0, turn), bevel=0.025, segments=2)
# The great oak.
TX, TY = 0.0, 0.25
cylinder(0.26, 1.35, (TX, TY, MZ + 0.66), 'Log', verts=10, radius2=0.17, bevel=0.03)
for k in range(5):
	a = math.radians(72 * k + 10)
	box((0.34, 0.16, 0.22), (TX + math.cos(a) * 0.26, TY + math.sin(a) * 0.26, MZ + 0.08), 'Log',
			rot=(0, -25, math.degrees(a)), bevel=0.06, segments=2)
for a in (30, 160, 280):
	m = Matrix.Translation((TX, TY, MZ + 1.2)) @ Matrix.Rotation(math.radians(a), 4, 'Z') @ Matrix.Rotation(math.radians(50), 4, 'Y')
	cylinder(0.08, 0.6, (0, 0, 0.3), 'Log', verts=8, radius2=0.05, bevel=0.02, matrix=m)
CZ = MZ + 1.45
ring_solid(1.05, 0.8, 0.42, (TX, TY, CZ), 'Leaf', n=9, amp=0.12, bevel=0.06, angle=35)
ring_solid(0.85, 0.42, 0.5, (TX, TY, CZ + 0.32), 'Leaf2', n=8, amp=0.11, bevel=0.06, angle=35, rot_z=20)
ring_solid(0.5, 0.0, 0.55, (TX, TY, CZ + 0.72), 'Leaf', n=7, amp=0.09, bevel=0.05, angle=35, rot_z=40)
# Team ribbons hanging from under the canopy.
for k in range(6):
	a = math.radians(60 * k + 15)
	rx, ry = TX + math.cos(a) * 0.82, TY + math.sin(a) * 0.82
	box((0.09, 0.03, 0.5), (rx, ry, CZ - 0.2), 'TeamColor', rot=(0, 0, math.degrees(a) + 90), bevel=0.012, segments=2)
	box((0.06, 0.06, 0.06), (rx, ry, CZ + 0.04), 'Rope', bevel=0.015, segments=1)
# The altar: a slab on two boulders, an antlered skull, a glowing spirit stone.
AY = -0.55
for sx in (-1, 1):
	boulder(sx * 0.28, AY, MZ - 0.02, (0.24, 0.26, 0.3), 'StoneDark', tilt=False)
box((0.9, 0.42, 0.12), (0, AY, MZ + 0.32), 'Stone', bevel=0.05)
skull(face(-0.15, AY, MZ + 0.5, '-y'), 0.38)
ring_solid(0.12, 0.0, 0.36, (0.22, AY, MZ + 0.37), 'Spirit', n=5, bevel=0.0)
for sx in (-1, 1):
	ring_solid(0.06, 0.0, 0.18, (0.22 + sx * 0.12, AY + 0.04, MZ + 0.37), 'Spirit', n=5, bevel=0.0)
for sx in (-1, 1):
	post(sx * 0.62, -1.3, MZ - 0.02, 1.0, r=0.06)
	antlers(face(sx * 0.62, -1.3, MZ + 0.98, '-y'), 0.4)
	ring_solid(0.09, 0.0, 0.2, (sx * 0.62, -1.3, MZ + 0.98), 'Spirit', n=5, bevel=0.0)
export('Sanctum')
