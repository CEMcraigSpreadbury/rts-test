# Builds Watchtower.glb: four leaning log legs lashed with rope cross braces
# up to a staked lookout under a thatch cone, an antlered skull on its front,
# a war horn and a claw-marked team hide hanging below, and a long ladder.
# See beastmen_common.py.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from beastmen_common import *

new_scene(391)
mound(0.88, 0.88, gap=(250, 290))
FOOT, TOP_HALF, PZ2 = 0.56, 0.44, MZ + 2.35
LEG_H = PZ2 - MZ + 0.04
ang = math.degrees(math.atan2(FOOT - TOP_HALF, LEG_H))
for sx in (-1, 1):
	for sy in (-1, 1):
		post(sx * FOOT, sy * FOOT, MZ - 0.04, LEG_H, r=0.09, mat_name='Log' if sx * sy > 0 else 'LogB',
				lean=(sy * ang, -sx * ang))
		boulder(sx * FOOT, sy * FOOT, MZ - 0.06, (0.26, 0.26, 0.16), 'StoneDark', tilt=False)
# Cross braces on each face, lashed where they cross.
for side in ('-y', '+y', '-x', '+x'):
	ox = {'-x': -1, '+x': 1}.get(side, 0)
	oy = {'-y': -1, '+y': 1}.get(side, 0)
	for z0, z1 in ((MZ + 0.25, MZ + 1.2), (MZ + 1.2, PZ2 - 0.1)):
		half = FOOT - (FOOT - TOP_HALF) * ((z0 + z1) / 2 - MZ) / LEG_H
		f = face(ox * half, oy * half, (z0 + z1) / 2, side)
		ln = math.hypot(half * 2, z1 - z0)
		a = math.degrees(math.atan2(half * 2, z1 - z0))
		for s in (-1, 1):
			box((0.07, 0.07, ln), (0, -0.04 - 0.03 * s, 0), 'LogB' if s > 0 else 'Log', rot=(0, s * a, 0), bevel=0.025,
					segments=2, matrix=f)
		box((0.12, 0.16, 0.12), (0, -0.04, 0), 'Rope', bevel=0.03, segments=2, matrix=f)
	h = FOOT - (FOOT - TOP_HALF) * (1.2 / LEG_H)
	box((2 * h + 0.2, 0.1, 0.1), (ox * h, oy * h, MZ + 1.2), 'Log', rot=(0, 0, 90 if ox else 0), bevel=0.03, segments=2)
# The lookout.
PW = 1.3
box((PW + 0.1, PW + 0.1, 0.14), (0, 0, PZ2), 'Log', bevel=0.05)
for k in range(5):
	box((PW, 0.24, 0.05), (0, -PW / 2 + 0.13 + k * 0.26, PZ2 + 0.09), 'LogB' if k % 2 else 'Log', bevel=0.02, segments=2)
E = PW / 2 - 0.04
stakes(-E, -E, E, -E, PZ2 + 0.05, 0.62, spacing=0.22, r=0.06)
stakes(-E, E, E, E, PZ2 + 0.05, 0.62, spacing=0.22, r=0.06)
stakes(-E, -E + 0.22, -E, E - 0.22, PZ2 + 0.05, 0.62, spacing=0.22, r=0.06)
stakes(E, -E + 0.22, E, E - 0.22, PZ2 + 0.05, 0.62, spacing=0.22, r=0.06)
RZ = PZ2 + 1.05
for sx in (-1, 1):
	for sy in (-1, 1):
		post(sx * (E - 0.02), sy * (E - 0.02), PZ2 + 0.05, RZ - PZ2, r=0.07)
apex = thatch_cone(0.98, 1.0, RZ - 0.06, tiers=2, n=11, rot=12)
skull(face(0, -E - 0.12, PZ2 + 0.62, '-y'), 0.44)
hide_banner(0.42, 0.6, face(-0.26, -PW / 2 - 0.1, PZ2 - 0.12, '-y'))
# A war horn hung on the right.
horn = Matrix.Translation((E + 0.12, -0.15, PZ2 + 0.32)) @ Matrix.Rotation(math.radians(90), 4, 'X')
tusk(horn, 1.6, 1, 'Horn')
box((0.04, 0.04, 0.3), (E + 0.12, -0.05, PZ2 + 0.5), 'Rope', bevel=0.01, segments=1)
# Ladder up the front.
lad = Matrix.Translation((0.36, -0.95, MZ - 0.02)) @ Matrix.Rotation(math.radians(-6), 4, 'X')
LL = (PZ2 - MZ) / math.cos(math.radians(6)) + 0.2
for x in (-0.16, 0.16):
	box((0.06, 0.06, LL), (x, 0, LL / 2), 'Log', bevel=0.02, segments=2, matrix=lad)
for k in range(int(LL / 0.3)):
	box((0.36, 0.05, 0.05), (0, -0.01, 0.2 + 0.3 * k), 'LogB', bevel=0.015, segments=2, matrix=lad)
export('Watchtower')
