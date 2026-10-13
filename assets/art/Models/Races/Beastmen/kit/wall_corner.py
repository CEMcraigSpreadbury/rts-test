# Builds WallCorner.glb: where palisade runs turn, a fat carved post of a bear
# under a wolf with a team band, an antler crown and a boulder collar at its
# foot. Kept light, as there are many. See beastmen_common.py.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from beastmen_common import *

new_scene(411)
ring_solid(0.42, 0.36, 0.2, (0, 0, 0), 'Dirt', n=10, bevel=0.06, angle=35)
for k in range(5):
	a = 2 * math.pi * (k + 0.3) / 5
	boulder(math.cos(a) * 0.34, math.sin(a) * 0.34, -0.02, (0.24, 0.2, 0.18), 'Stone' if k % 2 else 'StoneDark', tilt=False)
top = totem(0, 0, 0.12, ('bear', 'wolf'), s=0.5, top='antlers')
export('WallCorner')
