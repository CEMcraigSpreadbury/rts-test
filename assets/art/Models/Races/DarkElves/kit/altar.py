# Builds Altar.glb: a stepped obsidian altar under a great upright silver
# crescent holding a floating magenta crystal, flanked by two blade obelisks
# tipped with crystals and two braziers of venom-green fire.
# See darkelves_common.py.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from darkelves_common import *

new_scene(591)
dais(1.52, 1.3)
octo(1.0, 1.0, 0.16, (0, 0.15, DZ), 'Obsidian', sx=1.15, sy=0.95)
band(1.0, DZ + 0.16, h=0.05, cy=0.15, sx=1.17, sy=0.97)
Z1 = DZ + 0.16
# The altar slab.
box((1.1, 0.6, 0.5), (0, -0.05, Z1 + 0.25), 'ObsidianLight', bevel=0.06, segments=2)
box((1.22, 0.7, 0.1), (0, -0.05, Z1 + 0.52), 'Silver', bevel=0.03, segments=2)
box((1.0, 0.5, 0.06), (0, -0.05, Z1 + 0.58), 'Plum', bevel=0.02, segments=2)
spider(face(0, -0.36, Z1 + 0.25, '-y'), 0.5)
for s in (-1, 1):
	crystal((s * 0.35, -0.05, Z1 + 0.6), 0.3, 0.06, 'Crystal')
# The great crescent behind.
cf = face(0, 0.45, Z1, '-y')
octo(0.24, 0.2, 0.3, (0, 0.45, Z1), 'Obsidian')
crescent(cf @ tr(0, 0, 0.22), 0.72, 0.14, span=215, width=0.32)
crystal((0, 0.45, Z1 + 0.95), 0.75, 0.16, 'Crystal')
# Obelisks and braziers.
for s in (-1, 1):
	x = s * 1.08
	octo(0.2, 0.06, 2.0, (x, 0.3, Z1), 'Obsidian', sides=4)
	band(0.17, Z1 + 0.3, cx=x, cy=0.3, sides=4)
	band(0.11, Z1 + 1.2, cx=x, cy=0.3, sides=4)
	crystal((x, 0.3, Z1 + 2.02), 0.36, 0.08, 'Crystal')
	slit(face(x, 0.3 - 0.13, Z1 + 0.75, '-y'), w=0.08, h=0.3)
	bx, by = s * 0.95, -0.75
	octo(0.12, 0.08, 0.45, (bx, by, DZ), 'ObsidianLight', bevel=0.02)
	octo(0.12, 0.22, 0.14, (bx, by, DZ + 0.45), 'Silver', bevel=0.02)
	ring_solid(0.15, 0.0, 0.32, (bx, by, DZ + 0.57), 'Venom', n=6, amp=0.05, bevel=0.0)
	for k in range(3):
		a = math.radians(120 * k + 20 * s)
		thorn(tr(bx + math.cos(a) * 0.19, by + math.sin(a) * 0.19, DZ + 0.52) @ rz(math.degrees(a) - 90), 0.24, 0.035,
				bend=-30)
export('Altar')
