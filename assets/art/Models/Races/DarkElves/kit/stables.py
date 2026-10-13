# Builds Stables.glb: a long obsidian stable hall under a swooping team saddle
# roof whose ridge and eaves curl up into crescent-tipped horns, three tall
# pointed stall arches along the front, a slim spired corner turret, and a
# paddock of crescent-topped blade posts round a trough and hay.
# See darkelves_common.py.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from darkelves_common import *

new_scene(551)
dais(1.92, 1.5)
HX, HY, CY = 1.45, 0.62, 0.55
top = hall_box(HX, HY, DZ, DZ + 1.2, cy=CY)
swoop_gable(HX * 2, HY, top - 0.02, cy=CY, over=0.28, end_lift=0.5, rise=0.95)
for x in (-0.9, 0.0, 0.9):
	arch_door(face(x, CY - HY - 0.01, DZ, '-y'), w=0.46, h=0.66, thorns=False, leaves=False)
	box((0.3, 0.04, 0.22), (x, CY - HY + 0.06, DZ + 0.42), 'Hay', bevel=0.03, segments=2)
for x in (-0.45, 0.45):
	lantern(face(x, CY - HY - 0.02, DZ + 0.98, '-y'), drop=0.12, s=0.75, arm=0.2)
pennant(0.34, 0.55, face(-HX - 0.06, CY, DZ + 1.08, '-x'))
# The corner turret.
TX, TY, R, TT = 1.55, 1.05, 0.38, DZ + 2.05
rr = tower(R, DZ, TT, cx=TX, cy=TY, taper=0.86, bands=(0.08, 0.62))
slit(face(TX, TY - apothem(R + (rr - R) * 0.75), DZ + 1.55, '-y'), w=0.11, h=0.3)
octo(rr + 0.04, rr + 0.1, 0.1, (TX, TY, TT - 0.02), 'Plum')
swoop_spire(0.46, 1.4, TT + 0.06, cx=TX, cy=TY, flare=0.32, lift=0.2, finial_h=0.3, gem='Venom')
# The paddock.
for x, y in ((-1.7, -0.35), (-1.7, -1.25), (-0.6, -1.3), (0.5, -1.3), (1.6, -1.3), (1.75, -0.35)):
	blade_post(x, y, DZ, 0.62, r=0.05, s=0.55)
for (x0, y0), (x1, y1) in (((-1.7, -0.35), (-1.7, -1.25)), ((-1.7, -1.25), (-0.6, -1.3)), ((0.5, -1.3), (1.6, -1.3)),
		((1.6, -1.3), (1.75, -0.35))):
	ln = math.hypot(x1 - x0, y1 - y0)
	ang = math.degrees(math.atan2(y1 - y0, x1 - x0))
	for z in (0.25, 0.5):
		box((ln, 0.05, 0.05), ((x0 + x1) / 2, (y0 + y1) / 2, DZ + z), 'Silver', rot=(0, 0, ang), bevel=0.0)
box((0.7, 0.28, 0.2), (0.95, -0.75, DZ + 0.1), 'Obsidian', bevel=0.05, segments=2)
box((0.6, 0.18, 0.04), (0.95, -0.75, DZ + 0.19), 'Venom', bevel=0.015, segments=2)
for x, y in ((-1.15, -0.8), (-0.9, -0.95)):
	box((0.42, 0.28, 0.24), (x, y, DZ + 0.12), 'Hay', rot=(0, 0, 20), bevel=0.06, segments=2)
	box((0.44, 0.04, 0.26), (x, y, DZ + 0.12), 'Web', rot=(0, 0, 20), bevel=0.0)
crystal_cluster(-1.5, 1.15, DZ - 0.02, 0.5)
export('Stables')
