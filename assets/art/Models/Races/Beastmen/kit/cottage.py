# Builds Cottage.glb: a round daub hut on log posts under a shaggy two-tier
# thatch cone with a team hide tied round its crown, a hide-flap door with an
# antlered skull over it, and a woodpile. See beastmen_common.py.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from beastmen_common import *

new_scene(301)
mound(0.86, 0.86, gap=(250, 290))
R, WALL_H = 0.6, 0.7
ring_solid(R, R - 0.04, WALL_H + 0.08, (0, 0, MZ - 0.02), 'Daub', n=14, bevel=0.04, angle=35)
for k in range(8):
	a = math.radians(-90 + 22.5 + 45 * k)
	if k in (3,):
		pass
	post(math.cos(a) * (R + 0.01), math.sin(a) * (R + 0.01), MZ - 0.02, WALL_H + 0.05, r=0.065, mat_name='Log' if k % 2 else 'LogB')
rope_band(R + 0.035, 0, 0, MZ + WALL_H * 0.72, h=0.05, n=14)
apex = thatch_cone(0.94, 1.02, MZ + WALL_H - 0.08, tiers=2, n=11)
doorway(face(0, -R - 0.02, MZ, "-y"), w=0.36, h=0.56)
skull(face(0, -0.8, MZ + WALL_H + 0.1, '-y') @ Matrix.Rotation(math.radians(-20), 4, 'X'), 0.36)
# Woodpile against the right side, a drying hide on the left.
log_pile(0.55, 0.3, MZ, 0.42, rows=2, r=0.07, axis='y')
box((0.06, 0.06, 0.6), (-0.66, -0.36, MZ + 0.3), 'Log')
box((0.06, 0.06, 0.6), (-0.66, 0.0, MZ + 0.3), 'Log')
box((0.05, 0.44, 0.06), (-0.66, -0.18, MZ + 0.58), 'Log')
box((0.04, 0.34, 0.36), (-0.68, -0.18, MZ + 0.38), 'Hide', bevel=0.02, segments=2)
export('Cottage')
