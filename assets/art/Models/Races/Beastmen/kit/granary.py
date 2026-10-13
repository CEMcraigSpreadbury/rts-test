# Builds Granary.glb: a woven basket store raised on log stilts under a shaggy
# thatch cone, with a ladder, a smaller lidded basket, berry baskets and sacks
# round its foot and a claw-marked hide on a skull pole. See beastmen_common.py.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from beastmen_common import *

new_scene(331)
CY = 0.08
mound(1.38, 1.2, cy=CY - 0.02)
STILT, R = 0.52, 0.62
for k in range(6):
	a = math.radians(30 + 60 * k)
	post(math.cos(a) * 0.5, CY + math.sin(a) * 0.5, MZ - 0.02, STILT + 0.04, r=0.08, mat_name='Log' if k % 2 else 'LogB')
Z = MZ + STILT
ring_solid(0.74, 0.74, 0.1, (0, CY, Z), 'Log', n=12, bevel=0.035, angle=35)
# The woven drum: bands that swell and shift, like a basket's weave.
for k in range(4):
	ring_solid(R, R, 0.21, (0, CY, Z + 0.1 + k * 0.2), 'Wattle' if k % 2 == 0 else 'LogB', n=9, amp=0.03,
			bevel=0.03, angle=40, rot_z=20 * k)
rope_band(R + 0.04, 0, CY, Z + 0.52, h=0.05, n=12)
apex = thatch_cone(0.94, 1.0, Z + 0.86, cy=CY, tiers=2, n=11, rot=10)
# The hatch and the ladder up to it.
f = face(0, CY - R - 0.02, Z + 0.14, '-y')
box((0.34, 0.06, 0.42), (0, 0, 0.21), 'Window', bevel=0.03, matrix=f)
box((0.42, 0.08, 0.07), (0, -0.03, 0.45), 'Log', bevel=0.025, matrix=f)
lad = Matrix.Translation((0, CY - 1.0, MZ - 0.02)) @ Matrix.Rotation(math.radians(-24), 4, 'X')
for x in (-0.16, 0.16):
	box((0.06, 0.06, 0.86), (x, 0, 0.43), 'Log', bevel=0.02, matrix=lad)
for k in range(4):
	box((0.36, 0.05, 0.05), (0, -0.01, 0.12 + 0.2 * k), 'LogB', bevel=0.015, matrix=lad)
# A small lidded basket store behind on the right.
ring_solid(0.3, 0.33, 0.58, (0.92, CY + 0.5, MZ - 0.02), 'Wattle', n=8, amp=0.025, bevel=0.03, angle=40)
rope_band(0.34, 0.92, CY + 0.5, MZ + 0.3, h=0.045)
thatch_cone(0.44, 0.44, MZ + 0.52, cx=0.92, cy=CY + 0.5, tiers=1, n=7, collar=False, sticks=False)
# Berry baskets and sacks in front.
basket(-0.78, CY - 0.62, MZ - 0.02)
basket(-0.42, CY - 0.88, MZ - 0.02, r=0.15, h=0.2)
basket(-1.02, CY - 0.2, MZ - 0.02, r=0.15, h=0.18)
sack(0.62, CY - 0.72, MZ - 0.02, rot=20)
sack(0.9, CY - 0.45, MZ - 0.02, rot=-15)
# A skull pole flying a claw-marked team hide.
post(-0.95, CY + 0.6, MZ - 0.02, 1.85, r=0.06)
hide_banner(0.42, 0.52, face(-0.95, CY + 0.6, MZ + 1.6, '-y') @ Matrix.Translation((0, -0.08, 0)))
skull(face(-0.95, CY + 0.6, MZ + 1.95, '-y'), 0.34)
export('Granary')
