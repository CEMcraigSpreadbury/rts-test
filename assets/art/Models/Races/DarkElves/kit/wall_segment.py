# Builds WallSegment.glb: 2 m of obsidian curtain wall on a plum footing, a
# silver cornice and a crown of four pointed blade merlons tipped in silver,
# one glowing slit. Segments tile end to end, so everything stays inside
# x = +-1 and the merlons keep a 0.5 m rhythm across joins. Kept light.
# See darkelves_common.py.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from darkelves_common import *

new_scene(611)
L = 2.0
box((L, 0.42, 0.22), (0, 0, 0.11), 'PlumDark', bevel=0.05, segments=2)
box((L, 0.34, 1.32), (0, 0, 0.22 + 0.66), 'Obsidian', bevel=0.06, segments=2)
box((L, 0.4, 0.09), (0, 0, 1.55), 'Silver', bevel=0.03, segments=2)
for i in range(4):
	x = -0.75 + i * 0.5
	box((0.3, 0.3, 0.3), (x, 0, 1.6), 'Obsidian', rot=(0, 45, 0), bevel=0.05, segments=2)
	box((0.12, 0.32, 0.12), (x, 0, 1.79), 'Silver', rot=(0, 45, 0), bevel=0.02, segments=2)
for x in (-0.5, 0.5):
	box((0.06, 0.36, 1.2), (x, 0, 0.84), 'ObsidianLight', bevel=0.02, segments=2)
slit(face(0, -0.17, 0.9, '-y'), w=0.1, h=0.34)
export('WallSegment')
