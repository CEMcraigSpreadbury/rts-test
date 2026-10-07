# Builds Mine.glb: a heavy timber adit set into a heap of boulders, rails
# running out to an ore cart full of gold, a lantern and a team flag. It sits
# in front of the gold deposit it works (the model's origin), facing out, and
# stays low so the deposit still shows behind it. See common.py for the kit.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *

new_scene(121)
EY = -0.95
# Boulders heaped round the entrance.
for x, y, s, h in ((-0.75, EY + 0.05, 0.5, 0.75), (0.7, EY + 0.08, 0.48, 0.7), (-0.95, EY - 0.25, 0.38, 0.4),
		(0.9, EY - 0.22, 0.36, 0.42), (-0.5, EY + 0.25, 0.55, 1.15), (0.45, EY + 0.28, 0.55, 1.1), (0.0, EY + 0.35, 0.7, 1.4)):
	box((s, s * 0.9, h), (x, y, h / 2), 'Stone' if random.random() < 0.6 else 'StoneDark',
			rot=(0, 0, random.uniform(-20, 20)), bevel=min(0.12, s * 0.25), segments=3)
# The dark mouth and its timber frame.
box((0.8, 0.12, 0.95), (0, EY - 0.1, 0.48), 'Window', bevel=0.02)
for x in (-0.48, 0.48):
	box((0.18, 0.2, 1.1), (x, EY - 0.18, 0.55), 'Wood', bevel=0.05)
box((1.25, 0.24, 0.2), (0, EY - 0.18, 1.18), 'Wood', bevel=0.06)
for x, a in ((-0.3, 45), (0.3, -45)):
	box((0.1, 0.12, 0.36), (x, EY - 0.22, 0.98), 'WoodDark', rot=(0, a, 0))
box((0.5, 0.06, 0.2), (0, EY - 0.33, 1.18), 'Gold', bevel=0.03)
box((0.42, 0.07, 0.13), (0, EY - 0.35, 1.18), 'WoodDark', bevel=0.02)
# Rails out to the cart.
for x in (-0.22, 0.22):
	box((0.05, 1.65, 0.05), (x, EY - 0.9, 0.08), 'Iron', bevel=0.015, segments=2)
for i in range(6):
	box((0.62, 0.12, 0.05), (0, EY - 0.2 - i * 0.29, 0.03), 'Wood', bevel=0.02, segments=2)
# The ore cart, heaped with gold.
CY = EY - 1.3
box((0.55, 0.7, 0.32), (0, CY, 0.38), 'Wood', bevel=0.05)
for z in (0.28, 0.48):
	box((0.58, 0.73, 0.05), (0, CY, z), 'IronDark', bevel=0.02, segments=2)
for x in (-0.24, 0.24):
	for y in (-0.22, 0.22):
		cylinder(0.11, 0.06, (x * 1.12, CY + y, 0.16), 'IronDark', verts=10, bevel=0.02, rot=(0, 90, 0))
for i in range(7):
	sphere(0.08 + random.uniform(0, 0.04), (random.uniform(-0.18, 0.18), CY + random.uniform(-0.25, 0.25), 0.56), 'Gold')
# A lantern on a post, a pick, a barrel, a flag.
box((0.08, 0.08, 1.05), (-0.75, EY - 0.65, 0.52), 'Wood')
box((0.3, 0.06, 0.06), (-0.65, EY - 0.65, 1.02), 'Wood')
box((0.14, 0.14, 0.18), (-0.55, EY - 0.65, 0.86), 'IronDark', bevel=0.03)
box((0.1, 0.1, 0.12), (-0.55, EY - 0.65, 0.86), 'Ember', bevel=0.03)
f = Matrix.Translation((0.62, EY - 0.62, 0.05)) @ Matrix.Rotation(math.radians(30), 4, 'Z')
box((0.06, 0.6, 0.06), (0, 0, 0), 'Wood', bevel=0.02, matrix=f)
box((0.42, 0.07, 0.07), (0, 0.28, 0.02), 'Iron', rot=(0, 0, 0), bevel=0.025, matrix=f)
barrel(0.75, EY - 1.15, z=0.0, r=0.15, h=0.36)
flag(0.85, EY - 0.3, 0.6, 0.75)
export('Mine')
