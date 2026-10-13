# Builds Market.glb: an open oval pavilion, a gored team bell canopy on slim
# pearl posts over lavender-fronted stalls of silk bolts, star-fruit and
# amphorae, a starfire orb over the crown, on the star plinth.
# See starwanderers_common.py.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from starwanderers_common import *

new_scene(751)
plinth_star(1.12, 0.86)
SX, SY, PR, PT = 1.3, 1.0, 0.72, SZ + 1.05
for i in range(8):
	a = math.pi * 2 * i / 8 + math.pi / 8
	x, y = math.cos(a) * PR * SX, math.sin(a) * PR * SY
	cylinder(0.1, 0.1, (x, y, SZ + 0.05), 'Moonstone', verts=10, bevel=0.02)
	cylinder(0.055, PT - SZ, (x, y, SZ + (PT - SZ) / 2), 'Pearl', verts=8, bevel=0.01)
	cylinder(0.085, 0.08, (x, y, PT - 0.04), 'PaleGold', verts=10, bevel=0.015)
top, _ = canopy(0.84, 0.95, PT - 0.03, gores=8, shape='bell', sx=SX, sy=SY, sag=0.1, hem=0.13, rot=22.5)
orb_crown(0, 0, top - 0.04, 0.85, 'Starfire')
# Stalls.
for x, goods in ((-0.42, 'silk'), (0.42, 'fruit')):
	box((0.62, 0.36, 0.42), (x, -0.12, SZ + 0.21), 'Pearl', bevel=0.04)
	box((0.64, 0.05, 0.3), (x, -0.31, SZ + 0.22), 'Lavender', bevel=0.02)
	star4(face(x, -0.34, SZ + 0.22, '-y'), 0.09, 0.03, 'PaleGold')
	if goods == 'silk':
		for k, m in enumerate(('Rose', 'Silk', 'MoonGlow')):
			cylinder(0.07, 0.5, (x, -0.24 + k * 0.12, SZ + 0.49), m, verts=10, rot=(0, 90, 0), bevel=0.02)
	else:
		for k in range(5):
			sphere(0.08, (x - 0.2 + k * 0.1, -0.12 + 0.05 * (k % 2), SZ + 0.49), 'StarFruit')
box((0.5, 0.34, 0.36), (0, 0.32, SZ + 0.18), 'Pearl', bevel=0.04)
for k in range(3):
	amphora(-0.2 + k * 0.2, 0.36, SZ + 0.36, 0.7, 'Amphora' if k != 1 else 'Rose')
amphora(1.0, -0.35, SZ, 0.9)
amphora(-1.05, -0.3, SZ, 0.8, 'Lavender')
crate(0.95, 0.38, SZ, 0.3, rot=15)
export('Market')
