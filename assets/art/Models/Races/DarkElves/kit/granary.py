# Builds Granary.glb: an octagonal silk-store tower under a swooping team
# spire, beside a blade-post frame hung with fat silk-wrapped cocoons (the
# spiders' larder), a web strung in the frame, and a patch of plum toadstools
# with venom-green spots. See darkelves_common.py.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from darkelves_common import *


def cocoon(x, y, z, h=0.5, r=0.16):
	ring_solid(r * 0.4, r, h * 0.45, (x, y, z), 'Silk', n=8, bevel=0.03, angle=40)
	ring_solid(r, r * 0.35, h * 0.55, (x, y, z + h * 0.45), 'Silk', n=8, bevel=0.03, angle=40)
	for f in (0.3, 0.6):
		band(r * (0.85 if f < 0.5 else 0.8) + 0.01, z + h * f, h=0.035, cx=x, cy=y, mat_name='Web')


def toadstool(x, y, z, s=1.0):
	cylinder(0.07 * s, 0.32 * s, (x, y, z + 0.16 * s), 'Bone', verts=8, bevel=0.015, radius2=0.055 * s)
	ring_solid(0.24 * s, 0.05 * s, 0.17 * s, (x, y, z + 0.28 * s), 'Plum', n=10, bevel=0.04, angle=35)
	for k in range(3):
		a = math.radians(120 * k + 30)
		sphere(0.035 * s, (x + math.cos(a) * 0.14 * s, y + math.sin(a) * 0.14 * s, z + 0.36 * s), 'Venom')


new_scene(521)
dais(1.42, 1.12)
CX = -0.6
R, TOP = 0.66, DZ + 1.55
rt = tower(R, DZ, TOP, cx=CX, taper=0.9, bands=(0.06, 0.55))
arch_door(face(CX, -apothem(R) + 0.02, DZ, '-y'), w=0.46, h=0.66, thorns=False)
slit(face(CX - apothem(R + (rt - R) * 0.6), 0, DZ + 0.95, '-x'), w=0.13, h=0.4)
slit(face(CX, apothem(R + (rt - R) * 0.6), DZ + 0.95, '+y'), w=0.13, h=0.4)
octo(rt + 0.05, rt + 0.13, 0.12, (CX, 0, TOP - 0.02), 'Plum')
swoop_spire(0.78, 1.9, TOP + 0.08, cx=CX, flare=0.32, lift=0.28)
# The cocoon frame: two blade posts and a plum beam.
FX0, FX1, FY, FH = 0.15, 1.2, -0.05, 1.55
for x in (FX0, FX1):
	octo(0.08, 0.065, FH, (x, FY, DZ), 'ObsidianLight', bevel=0.02)
	crescent(face(x, FY, DZ + FH + 0.05, '-y'), 0.18, 0.05)
box((FX1 - FX0 + 0.2, 0.12, 0.12), ((FX0 + FX1) / 2, FY, DZ + FH), 'Plum', bevel=0.03, segments=2)
for x, ln in ((0.42, 0.34), (0.68, 0.18), (0.94, 0.4)):
	cylinder(0.015, ln, (x, FY, DZ + FH - ln / 2), 'Web', verts=4, bevel=0.0)
	cocoon(x, FY, DZ + FH - ln - 0.5, h=0.5, r=0.13)
web(face((FX0 + FX1) / 2, FY + 0.08, DZ + FH - 0.06, '+y'), r=0.52, spokes=6, rings=(0.45, 0.85), arc=(180, 360))
# Cocoons stacked on the dais behind, and toadstools at the front.
for x, y, s in ((0.45, 0.6, 1.0), (0.85, 0.55, 0.85), (0.65, 0.82, 0.8), (1.1, 0.25, 0.7)):
	cocoon(x, y, DZ - 0.01, h=0.55 * s, r=0.17 * s)
toadstool(0.55, -0.78, DZ - 0.02, 1.0)
toadstool(0.85, -0.7, DZ - 0.02, 0.7)
toadstool(0.3, -0.62, DZ - 0.02, 0.55)
lantern(face(CX + 0.32, -apothem(R) + 0.02, DZ + 0.9, '-y'), drop=0.14, s=0.8, arm=0.24)
crystal_cluster(-1.2, 0.75, DZ - 0.02, 0.55, 'Venom')
export('Granary')
