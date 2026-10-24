# Builds TreasureChest.glb: Cursed Treasure's chest, 1.6 m wide, heaped with
# gold, iron-banded with gold corners. Its lid is a node of its own, "Lid",
# hinged along the back edge (PowerFx swings it open about its X).
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _kit import *

new_scene(551)
W, D, H = 1.6, 1.0, 0.8
box((W, D, H), (0, 0, H / 2), 'Wood', bevel=0.06)
for x in (-0.5, 0.5):
	box((0.12, D + 0.04, H + 0.02), (x, 0, H / 2), 'IronDark', bevel=0.03)
for sx in (-1, 1):
	for sy in (-1, 1):
		box((0.16, 0.16, H + 0.04), (sx * (W / 2 - 0.05), sy * (D / 2 - 0.05), H / 2), 'Gold', bevel=0.04)
box((0.3, 0.08, 0.34), (0, -D / 2 - 0.02, H - 0.12), 'Gold', bevel=0.04)
# The hoard, heaped up out of it.
for i in range(14):
	x = random.uniform(-0.6, 0.6)
	y = random.uniform(-0.32, 0.32)
	sphere(random.uniform(0.12, 0.2), (x, y, H + random.uniform(-0.02, 0.12)), 'Gold')
sphere(0.12, (0.25, -0.1, H + 0.22), 'Ruby')
# The lid: a stepped dome, iron straps over it.
with moving('Lid', (0, D / 2, H)) as lid:
	for k, (depth, height) in enumerate(((D + 0.04, 0.16), (D * 0.82, 0.14), (D * 0.56, 0.12))):
		z = H + 0.08 + k * 0.13
		box((W + 0.04 - k * 0.02, depth, height), (0, 0, z), 'Wood', bevel=0.05)
		for x in (-0.5, 0.5):
			box((0.13, depth + 0.03, height + 0.02), (x, 0, z), 'IronDark', bevel=0.03)
	box((0.3, 0.08, 0.2), (0, -D / 2 - 0.02, H + 0.08), 'Gold', bevel=0.04)
export('TreasureChest')
