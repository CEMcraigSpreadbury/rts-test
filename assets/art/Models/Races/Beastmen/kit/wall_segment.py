# Builds WallSegment.glb: 2 m of palisade, eight sharpened logs of uneven
# height on an earth bank, lashed to two rope-bound rails. Segments tile end to
# end, so everything stays inside x = +-1 and the logs keep a 0.25 m rhythm
# across the joins. Kept light, as there are many. See beastmen_common.py.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from beastmen_common import *

new_scene(401)
L = 2.0
box((L, 0.5, 0.2), (0, 0, 0.08), 'Dirt', bevel=0.07, segments=2)
for i in range(8):
	x = -0.875 + i * 0.25
	h = (1.42, 1.58, 1.5, 1.62, 1.45, 1.6, 1.52, 1.56)[i]
	post(x, 0.0, 0.05, h - 0.18, r=0.118, mat_name='Log' if i % 2 else 'LogB', tip=True, verts=8)
# Rails behind, rope bands across the front.
for z in (0.55, 1.12):
	box((L, 0.09, 0.12), (0, 0.13, z), 'Log', bevel=0.03, segments=2)
	box((L, 0.05, 0.07), (0, -0.115, z), 'Rope', bevel=0.02, segments=2)
for x, y, s in ((-0.6, -0.2, 0.9), (0.45, 0.21, 1.0)):
	boulder(x, y, 0.0, (0.3 * s, 0.22 * s, 0.2 * s), 'Stone', tilt=False)
box((0.3, 0.2, 0.06), (0.15, -0.2, 0.17), 'Moss', bevel=0.025, segments=2)
export('WallSegment')
