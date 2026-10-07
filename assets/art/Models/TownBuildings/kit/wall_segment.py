# Builds WallSegment.glb: 2 m of chunky battlemented wall. Segments tile end to
# end in long runs, so it ends exactly at x = +-1, its merlons keep a 0.5 m
# rhythm across the joins, and it stays light (a dozen blocks). See common.py.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *

new_scene(171)
L = 2.0
box((L, 0.52, 0.26), (0, 0, 0.13), 'StoneDark', bevel=0.05, segments=2)
box((L, 0.4, 1.2), (0, 0, 0.84), 'Stone', bevel=0.05, segments=2)
box((L, 0.5, 0.12), (0, 0, 1.48), 'StoneDark', bevel=0.04, segments=2)
for x in (-0.75, -0.25, 0.25, 0.75):
	box((0.3, 0.42, 0.32), (x, 0, 1.7), 'Stone', bevel=0.06, segments=2)
# A few proud stones on each face, so it reads as built of blocks.
for s in (-1, 1):
	for x, z, w in ((-0.55, 0.62, 0.5), (0.35, 0.95, 0.42), (0.7, 0.48, 0.34)):
		box((w, 0.06, 0.24), (x * s, s * 0.21, z), 'StoneDark' if x < 0 else 'Stone', bevel=0.03, segments=2)
export('WallSegment')
