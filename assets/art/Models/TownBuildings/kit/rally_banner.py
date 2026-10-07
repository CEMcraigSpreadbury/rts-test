# Builds RallyBanner.glb: the team's rally standard, a pole on a stone base
# with a crossbar flying a swallow-tailed team banner out to the right. See
# common.py for the kit.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *

new_scene(221)
box((0.44, 0.4, 0.18), (0, 0, 0.09), 'StoneDark', bevel=0.06, segments=2)
box((0.32, 0.3, 0.14), (0, 0, 0.25), 'Stone', bevel=0.05, segments=2)
cylinder(0.05, 1.95, (0, 0, 0.3 + 0.975), 'WoodDark', verts=8, bevel=0.0)
sphere(0.08, (0, 0, 2.3), 'Gold')
# The banner hangs from a crossbar reaching out to the right.
banner(0.5, 0.78, face(0.33, 0, 2.08, '-y'))
box((0.06, 0.06, 0.12), (0.62, 0, 2.08), 'Gold', bevel=0.02, segments=2)
export('RallyBanner')
