# Builds WallSegment.glb: 2 m of pearl wall on a moonstone footing, ribbed
# in lavender every 0.5 m, a pale gold coping and a crown of four round moon
# merlons, the middle two set with gold stars, one starlit porthole.
# Segments tile end to end, so everything stays inside x = +-1 and the ribs
# and merlons keep a 0.5 m rhythm across joins. See starwanderers_common.py.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from starwanderers_common import *

new_scene(811)
L = 2.0
box((L, 0.44, 0.2), (0, 0, 0.1), 'Moonstone', bevel=0.05, segments=2)
box((L, 0.34, 1.2), (0, 0, 0.2 + 0.6), 'Pearl', bevel=0.06, segments=2)
box((L, 0.42, 0.1), (0, 0, 1.43), 'PaleGold', bevel=0.03, segments=2)
for i in range(4):
	x = -0.75 + i * 0.5
	cylinder(0.19, 0.28, (x, 0, 1.56), 'Pearl', verts=16, rot=(90, 0, 0), bevel=0.04)
	box((0.38, 0.28, 0.1), (x, 0, 1.52), 'Pearl', bevel=0.03, segments=2)
	if i in (1, 2):
		star4(face(x, -0.15, 1.6, '-y'), 0.11, 0.04, 'PaleGold')
for x in (-0.5, 0.0, 0.5):
	box((0.1, 0.4, 1.12), (x, 0, 0.8), 'Lavender', bevel=0.03, segments=2)
porthole(face(-0.25, -0.17, 0.85, '-y'), 0.1)
porthole(face(0.25, -0.17, 0.85, '-y'), 0.1, 'Rose')
export('WallSegment')
