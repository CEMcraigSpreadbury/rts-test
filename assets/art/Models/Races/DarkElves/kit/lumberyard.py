# Builds Lumberyard.glb: a black-timber yard. A lean saw shed of blade posts
# under a swooping team canopy, a great silver crescent saw biting a log on its
# trestle, stacks of black logs with pale bone-white cut ends, and a stump with
# a crescent axe. See darkelves_common.py.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from darkelves_common import *


def black_logs(x, y, z, length, rows=3, r=0.11):
	for row in range(rows):
		cnt = rows - row
		for i in range(cnt):
			o = (i - (cnt - 1) / 2) * r * 2.02
			zz = z + r + row * r * 1.75
			cylinder(r, length, (x, y + o, zz), 'DarkWood' if (i + row) % 2 else 'ObsidianDark', verts=8, rot=(0, 90, 0),
					bevel=0.02)
			for e in (-1, 1):
				cylinder(r * 0.8, 0.02, (x + e * (length / 2 + 0.004), y + o, zz), 'Bone', verts=8, rot=(0, 90, 0), bevel=0.0)


new_scene(571)
dais(1.48, 1.18)
# The shed at the back.
SX0, SX1, SY, SH = -1.2, 0.5, 0.55, 1.3
for x in (SX0, SX1):
	for y in (SY - 0.42, SY + 0.42):
		octo(0.075, 0.06, SH, (x, y, DZ), 'ObsidianLight', bevel=0.02)
box((SX1 - SX0 + 0.16, 0.1, 0.1), ((SX0 + SX1) / 2, SY - 0.42, DZ + SH), 'Plum', bevel=0.03, segments=2)
box((SX1 - SX0 + 0.16, 0.1, 0.1), ((SX0 + SX1) / 2, SY + 0.42, DZ + SH), 'Plum', bevel=0.03, segments=2)
swoop_gable(SX1 - SX0, 0.42, DZ + SH + 0.04, cx=(SX0 + SX1) / 2, cy=SY, over=0.22, end_lift=0.35, rise=0.6, crest=False)
black_logs((SX0 + SX1) / 2, SY, DZ - 0.01, 1.5, rows=3, r=0.12)
lantern(face(SX1 + 0.04, SY - 0.42, DZ + SH - 0.05, '-y') @ rz(-30), drop=0.18, s=0.8, arm=0.18)
# The saw trestle.
TX, TY = -0.2, -0.55
for x in (TX - 0.45, TX + 0.45):
	for s in (-1, 1):
		box((0.07, 0.07, 0.6), (x, TY + s * 0.12, DZ + 0.27), 'DarkWood', rot=(s * 18, 0, 0), bevel=0.02, segments=2)
cylinder(0.14, 1.3, (TX, TY, DZ + 0.62), 'DarkWood', verts=8, rot=(0, 90, 0), bevel=0.02)
for e in (-1, 1):
	cylinder(0.11, 0.02, (TX + e * 0.655, TY, DZ + 0.62), 'Bone', verts=8, rot=(0, 90, 0), bevel=0.0)
sf = face(TX + 0.1, TY, DZ + 0.62, '-y') @ ry(180)
crescent(sf @ tr(0, 0, -0.6), 0.5, 0.05, span=140, width=0.35)
for s in (-1, 1):
	box((0.06, 0.06, 0.5), (TX + 0.1 + s * 0.5, TY, DZ + 1.05), 'Plum', bevel=0.02, segments=2)
# The stump and axe, and more logs.
cylinder(0.24, 0.3, (1.0, -0.55, DZ + 0.15), 'DarkWood', verts=10, bevel=0.03)
cylinder(0.2, 0.02, (1.0, -0.55, DZ + 0.305), 'Bone', verts=10, bevel=0.0)
ax = tr(1.02, -0.55, DZ + 0.3) @ ry(-25)
box((0.05, 0.05, 0.7), (0, 0, 0.3), 'Plum', bevel=0.015, segments=2, matrix=ax)
crescent(ax @ tr(0.0, 0, 0.62) @ ry(-90) @ tr(0, 0, -0.2), 0.2, 0.04, width=0.5)
black_logs(1.05, 0.55, DZ - 0.01, 0.8, rows=2, r=0.11)
crystal_cluster(-1.25, -0.8, DZ - 0.02, 0.45, 'Venom')
export('Lumberyard')
