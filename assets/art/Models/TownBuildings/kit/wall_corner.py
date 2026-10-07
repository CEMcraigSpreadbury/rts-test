# Builds WallCorner.glb: a squat battlemented tower where wall runs turn, with
# a team band and a flag. Kept light, as there are many. See common.py.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *

new_scene(181)
W, TOP = 0.72, 2.2
box((W + 0.16, W + 0.16, 0.3), (0, 0, 0.15), 'StoneDark', bevel=0.06, segments=2)
box((W, W, TOP - 0.3), (0, 0, (TOP + 0.3) / 2), 'Stone', bevel=0.05, segments=2)
for k, z in enumerate((0.75, 1.45)):
	for cx in (-1, 1):
		for cy in (-1, 1):
			if (cx + cy + k) % 2 == 0:
				box((0.28, 0.28, 0.3), (cx * (W / 2 - 0.1), cy * (W / 2 - 0.1), z), 'StoneDark', bevel=0.05, segments=2)
box((W + 0.08, W + 0.08, 0.14), (0, 0, TOP - 0.22), 'TeamColor', bevel=0.04, segments=2)
box((W + 0.2, W + 0.2, 0.14), (0, 0, TOP + 0.02), 'StoneDark', bevel=0.05, segments=2)
for cx in (-1, 1):
	for cy in (-1, 1):
		box((0.26, 0.26, 0.3), (cx * (W / 2 - 0.02), cy * (W / 2 - 0.02), TOP + 0.24), 'Stone', bevel=0.06, segments=2)
flag(0, 0, TOP + 0.09, 0.7)
export('WallCorner')
