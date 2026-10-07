# Builds Field.glb: a raised bed of soil ridged into furrows, a row of chunky
# wheat sheaves along each, a low fence on two sides and a scarecrow in the
# corner. FarmField squashes the whole model flat and tints it from soil to
# green to ripe as the crop grows, so the shapes read at any height. Farms are
# many, so it stays light. See common.py for the kit.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *

new_scene(201)
box((3.0, 3.0, 0.16), (0, 0, 0.08), 'Soil', bevel=0.06, segments=2)
ROWS = (-1.08, -0.54, 0.0, 0.54, 1.08)
for x in ROWS:
	box((0.36, 2.7, 0.14), (x, 0, 0.2), 'Soil', bevel=0.06, segments=2)
	for j in range(5):
		y = -1.04 + j * 0.52 + random.uniform(-0.04, 0.04)
		lean = (random.uniform(-6, 6), random.uniform(-6, 6), random.uniform(0, 90))
		f = Matrix.Translation((x + random.uniform(-0.03, 0.03), y, 0.25)) @ Matrix.Rotation(math.radians(lean[0]), 4, 'X') \
			@ Matrix.Rotation(math.radians(lean[1]), 4, 'Y')
		# A bunch of three stalks splayed from a tied base, each topped with a
		# fat rounded ear.
		h = random.uniform(0.85, 1.0)
		cylinder(0.1, 0.16, (0, 0, 0.08), 'WheatDark', verts=6, bevel=0.0, matrix=f)
		for e in range(3):
			a = math.radians(lean[2] + e * 120)
			stalk = f @ Matrix.Rotation(a, 4, 'Z') @ Matrix.Rotation(math.radians(14), 4, 'X')
			cylinder(0.03, 0.5 * h, (0, 0, 0.25 * h), 'WheatDark', verts=5, bevel=0.0, matrix=stalk)
			box((0.12, 0.12, 0.3 * h), (0, 0, 0.62 * h), 'Wheat', bevel=0.05, segments=2, matrix=stalk)
# A low rail fence along the front and left edges.
fence(-1.45, -1.45, 1.45, -1.45, h=0.42)
fence(-1.45, -1.45, -1.45, 1.45, h=0.42)
# The scarecrow, back right.
SX, SY = 1.25, 1.2
box((0.07, 0.07, 1.25), (SX, SY, 0.62), 'Wood', bevel=0.02)
box((0.7, 0.06, 0.06), (SX, SY, 1.0), 'Wood', bevel=0.02)
box((0.3, 0.2, 0.42), (SX, SY, 0.92), 'Sack', bevel=0.08, segments=2)
for s in (-1, 1):
	box((0.16, 0.1, 0.1), (SX + s * 0.3, SY, 1.0), 'Sack', bevel=0.04, segments=2)
sphere(0.14, (SX, SY, 1.3), 'Sack')
cylinder(0.2, 0.04, (SX, SY, 1.4), 'Red', verts=10, bevel=0.0)
cylinder(0.11, 0.18, (SX, SY, 1.5), 'Red', verts=10, bevel=0.02, radius2=0.05)
export('Field')
