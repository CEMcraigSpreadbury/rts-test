# Builds Coven.glb: the sorceresses' circle. Six tall curved thorn stones lean
# in round a venom-green scrying pool with a magenta crystal floating over it
# in a silver crescent; a spired coven tower stands at the back, a web is
# strung between two stones and pennants hang at the tower door.
# See darkelves_common.py.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from darkelves_common import *

new_scene(601)
dais(1.6, 1.6)
# The coven tower at the back.
TX, TY, R, TT = 0.0, 0.85, 0.58, DZ + 2.0
rt = tower(R, DZ, TT, cx=TX, cy=TY, taper=0.84, bands=(0.06, 0.55))
arch_door(face(TX, TY - apothem(R) + 0.02, DZ, '-y'), w=0.42, h=0.64, thorns=False)
slit(face(TX, TY - apothem(R + (rt - R) * 0.75), DZ + 1.5, '-y'), w=0.13, h=0.36)
for s in (-1, 1):
	slit(face(TX + s * apothem(R + (rt - R) * 0.6), TY, DZ + 1.2, '+x' if s > 0 else '-x'), w=0.13, h=0.36)
	pennant(0.26, 0.5, face(TX + s * 0.42, TY - apothem(R) - 0.04, DZ + 1.05, '-y'), spider_mark=False)
octo(rt + 0.05, rt + 0.13, 0.12, (TX, TY, TT - 0.02), 'Plum')
swoop_spire(0.7, 1.9, TT + 0.08, cx=TX, cy=TY, flare=0.32, lift=0.28)
# The scrying pool.
PY = -0.3
octo(0.62, 0.6, 0.18, (0, PY, DZ - 0.02), 'ObsidianLight')
band(0.62, DZ + 0.16, h=0.05, cy=PY)
octo(0.5, 0.5, 0.04, (0, PY, DZ + 0.13), 'Venom', bevel=0.01)
crescent(face(0, PY, DZ + 0.5, '-y'), 0.3, 0.07)
crystal((0, PY, DZ + 0.7), 0.6, 0.13, 'Crystal')
# The thorn stones, a gap at the front and at the tower.
stones = []
for a in (-150, -30, 15, 165, 200, 340):
	ar = math.radians(a)
	x, y = math.cos(ar) * 1.18, PY + 0.15 + math.sin(ar) * 1.05
	stones.append((x, y))
	f = tr(x, y, DZ - 0.02) @ rz(a + 90)
	octo(0.16, 0.13, 0.3, (0, 0, 0), 'Obsidian', matrix=f, sides=6)
	thorn(f @ tr(0, 0, 0.25), 1.55, 0.14, bend=34, segs=4, mat_name='ObsidianLight')
	box((0.2, 0.05, 0.2), (0, -0.14, 0.55), 'Crystal', rot=(0, 45, 0), bevel=0.02, segments=2, matrix=f)
web(face(-1.18, PY - 0.25, DZ + 1.05, '-x') @ rz(-20), r=0.42, spokes=6, rings=(0.4, 0.8), arc=(180, 360))
for s in (-1, 1):
	lantern(face(s * 0.75, -1.3, DZ + 0.9, '-y'), drop=0.1, s=0.8, arm=0.02)
	blade_post(s * 0.75, -1.3, DZ, 0.9, r=0.05, s=0.55)
export('Coven')
