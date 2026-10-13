# Builds Market.glb: an open pavilion of four crescent-topped blade posts under
# a swooping team saddle canopy hung with venom lanterns; on the counter,
# crystals, potions and bolts of spider silk; a web-hung sign post and silk
# bundles beside it. See darkelves_common.py.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from darkelves_common import *


def potion(x, y, z, glow, s=1.0):
	sphere(0.07 * s, (x, y, z + 0.07 * s), glow)
	cylinder(0.025 * s, 0.08 * s, (x, y, z + 0.16 * s), 'Silver', verts=6, bevel=0.0)


def silk_bolt(x, y, z, length=0.5, r=0.09, rot=0.0):
	cylinder(r, length, (x, y, z + r), 'Silk', verts=10, rot=(0, 90, rot), bevel=0.02)
	cylinder(r * 0.4, length + 0.06, (x, y, z + r), 'DarkWood', verts=6, rot=(0, 90, rot), bevel=0.0)


new_scene(561)
dais(1.45, 1.15)
PX, PY, PH = 1.0, 0.62, 1.25
for sx in (-1, 1):
	for sy in (-1, 1):
		octo(0.08, 0.065, PH, (sx * PX, sy * PY, DZ), 'ObsidianLight', bevel=0.02)
		band(0.1, DZ + 0.1, cx=sx * PX, cy=sy * PY, h=0.06)
for sy in (-1, 1):
	box((PX * 2 + 0.2, 0.1, 0.1), (0, sy * PY, DZ + PH), 'Plum', bevel=0.03, segments=2)
swoop_gable(PX * 2, PY, DZ + PH + 0.04, over=0.25, end_lift=0.4, rise=0.65, crest=False)
for x in (-0.55, 0.55):
	lantern(face(x, -PY - 0.04, DZ + PH - 0.02, '-y') @ tr(0, 0.2, 0), drop=0.2, s=0.8, arm=0.02)
# The counter and wares.
box((1.7, 0.42, 0.5), (0, -0.25, DZ + 0.25), 'Obsidian', bevel=0.06, segments=2)
box((1.78, 0.5, 0.06), (0, -0.25, DZ + 0.52), 'Silver', bevel=0.02, segments=2)
box((1.6, 0.04, 0.3), (0, -0.48, DZ + 0.25), 'TeamColor', bevel=0.012, segments=2)
spider(face(0, -0.5, DZ + 0.26, '-y'), 0.45)
crystal_cluster(-0.6, -0.25, DZ + 0.54, 0.45)
crystal_cluster(-0.25, -0.2, DZ + 0.54, 0.35, 'Venom')
for k, g in enumerate(('Venom', 'Crystal', 'Venom', 'Crystal')):
	potion(0.08 + k * 0.13, -0.32, DZ + 0.55, g, 0.9)
silk_bolt(0.55, -0.15, DZ + 0.55, 0.42, 0.08)
silk_bolt(0.55, -0.15, DZ + 0.71, 0.36, 0.07, 10)
# Goods behind and beside.
for x, y in ((-0.7, 0.4), (-0.35, 0.45)):
	silk_bolt(x, y, DZ - 0.01, 0.5, 0.1, 80)
box((0.4, 0.34, 0.34), (0.55, 0.4, DZ + 0.17), 'DarkWood', rot=(0, 0, 8), bevel=0.05, segments=2)
box((0.42, 0.36, 0.06), (0.55, 0.4, DZ + 0.31), 'Silver', rot=(0, 0, 8), bevel=0.02, segments=2)
crystal((0.55, 0.4, DZ + 0.38), 0.4, 0.09, 'Crystal')
# The sign post.
SX, SY = 1.3, -0.85
blade_post(SX, SY, DZ, 1.3, r=0.06, s=0.8)
box((0.5, 0.06, 0.06), (SX - 0.22, SY, DZ + 1.15), 'Silver', bevel=0.0)
pennant(0.3, 0.42, face(SX - 0.28, SY, DZ + 1.12, '-y'))
export('Market')
