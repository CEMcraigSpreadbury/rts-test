# Builds WallGate.glb: two spired octagonal pillars carrying an obsidian
# lintel under a pointed silver arch, a crescent and crystal at its point, a
# silver spider on the lintel, a web in the arch and team pennants on the
# pillars. The opening stays inside wall_gate.tscn's walk-through gap (posts
# at x = +-0.85, clear between +-0.7, under the lintel at 1.7). Kept light.
# See darkelves_common.py.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from darkelves_common import *

new_scene(631)
PX, PR, PH = 0.92, 0.18, 2.25
for s in (-1, 1):
	x = s * PX
	octo(0.21, 0.2, 0.2, (x, 0, 0), 'PlumDark', bevel=0.03)
	rt = tower(PR, 0.18, PH, cx=x, taper=0.9, bands=(0.1, 0.8))
	octo(rt + 0.03, rt + 0.07, 0.08, (x, 0, PH - 0.02), 'Plum', bevel=0.02)
	swoop_spire(0.3, 0.8, PH + 0.04, cx=x, flare=0.3, lift=0.12, finial_h=0.15, gem='Venom')
	pennant(0.24, 0.5, face(x + s * 0.02, -apothem(PR) - 0.04, 1.55, '-y'), spider_mark=False)
# The lintel and pointed arch.
box((1.56, 0.34, 0.26), (0, 0, 1.72 + 0.13), 'Obsidian', bevel=0.05, segments=2)
box((1.6, 0.38, 0.06), (0, 0, 2.0), 'Silver', bevel=0.02, segments=2)
for s in (-1, 1):
	box((0.9, 0.12, 0.12), (s * 0.36, 0, 2.2), 'Silver', rot=(0, s * 28, 0), bevel=0.03, segments=2)
web(face(0, 0.02, 2.04, '-y'), r=0.42, spokes=5, rings=(0.45, 0.85), arc=(30, 150), thick=0.02)
crescent(face(0, -0.02, 2.36, '-y'), 0.2, 0.06)
crystal((0, -0.02, 2.5), 0.36, 0.08, 'Crystal')
spider(face(0, -0.17, 1.85, '-y'), 0.5)
export('WallGate')
