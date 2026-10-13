# Builds Range.glb: a shooting yard behind a long obsidian wall crowned with
# silver blade teeth, a slim spired turret at one end, two spider-web targets
# in plum rings on blade stands, and a rack of crescent-bowed crossbows.
# See darkelves_common.py.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from darkelves_common import *


def web_target(x, y, z, r=0.36):
	for s in (-1, 1):
		octo(0.05, 0.04, r + 0.32, (x + s * (r + 0.02), y + 0.02, z), 'ObsidianLight', bevel=0.012)
	hub = z + r + 0.36
	torus(r, 0.05, (x, y, hub), 'Plum', rot=(90, 0, 0))
	web(face(x, y + 0.02, hub, '-y'), r=r - 0.02, spokes=8, rings=(0.35, 0.7), thick=0.022)
	sphere(0.07, (x, y - 0.05, hub), 'Crystal')
	for a in (35, -20):
		box((0.03, 0.3, 0.03), (x + 0.08, y - 0.12, hub + 0.06), 'DarkWood', rot=(a, 0, 20), bevel=0.0)


def crossbow(frame):
	box((0.07, 0.07, 0.5), (0, 0, 0), 'Plum', bevel=0.02, segments=2, matrix=frame)
	crescent(frame @ tr(0, -0.02, 0.12), 0.17, 0.04, span=130, width=0.6)


new_scene(541)
dais(1.82, 1.12)
# The back wall.
WY, WH = 0.62, 1.15
box((2.5, 0.34, WH), (-0.25, WY, DZ + WH / 2), 'Obsidian', bevel=0.08, segments=2)
box((2.58, 0.4, 0.1), (-0.25, WY, DZ + WH - 0.02), 'Silver', bevel=0.03, segments=2)
box((2.56, 0.4, 0.14), (-0.25, WY, DZ + 0.07), 'PlumDark', bevel=0.04, segments=2)
for k in range(7):
	x = -1.4 + k * 0.38
	box((0.1, 0.12, 0.3), (x, WY, DZ + WH + 0.16), 'Silver', rot=(0, 45, 0), bevel=0.02, segments=2)
	if k % 2 == 0:
		slit(face(x + 0.19, WY - 0.17, DZ + 0.6, '-y'), w=0.11, h=0.32)
pennant(0.34, 0.6, face(-0.25 + 0.19 * 3 - 0.19, WY - 0.2, DZ + WH - 0.1, '-y'))
# The turret.
TX, TY, R, TT = 1.28, 0.42, 0.42, DZ + 1.9
rr = tower(R, DZ, TT, cx=TX, cy=TY, taper=0.86, bands=(0.08, 0.6))
arch_door(face(TX, TY - apothem(R) + 0.02, DZ, '-y'), w=0.34, h=0.5, thorns=False)
slit(face(TX, TY - apothem(R + (rr - R) * 0.7), DZ + 1.35, '-y'), w=0.11, h=0.3)
octo(rr + 0.04, rr + 0.1, 0.1, (TX, TY, TT - 0.02), 'Plum')
swoop_spire(0.5, 1.5, TT + 0.06, cx=TX, cy=TY, flare=0.32, lift=0.2, finial_h=0.35)
lantern(face(TX - 0.3, TY - apothem(R) + 0.06, DZ + 0.95, '-y') @ rz(20), drop=0.12, s=0.8, arm=0.2)
# Targets and the rack.
web_target(-1.15, -0.4, DZ)
web_target(-0.3, -0.5, DZ, r=0.3)
for x in (0.45, 1.05):
	blade_post(x, -0.62, DZ, 0.75, r=0.05, s=0.6)
box((0.75, 0.08, 0.08), (0.75, -0.62, DZ + 0.62), 'Plum', bevel=0.02, segments=2)
for k in range(3):
	crossbow(face(0.58 + k * 0.17, -0.67, DZ + 0.36, '-y'))
crystal_cluster(1.55, -0.7, DZ - 0.02, 0.5, 'Venom')
export('Range')
