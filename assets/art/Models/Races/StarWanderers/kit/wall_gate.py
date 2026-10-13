# Builds WallGate.glb: two round lavender-ribbed pearl pillars under small
# gored team tents, carrying a pale gold lintel with a great horns-up gold
# crescent moon cradling a starfire orb, team streamers on the pillars. The
# opening stays inside wall_gate.tscn's walk-through gap (clear between
# x = +-0.7, under the lintel at 1.7). See starwanderers_common.py.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from starwanderers_common import *

new_scene(831)
PX, PR, PH = 0.95, 0.17, 2.05
for s in (-1, 1):
	x = s * PX
	drum(PR, 0.0, PH, cx=x, ribs=4, taper=0.94, rib_rot=45)
	top, _ = canopy(0.28, 0.42, PH - 0.02, cx=x, gores=6, shape='tent', sag=0.1, hem=0.05, knobs=False)
	star_finial(x, 0, top - 0.02, 0.6, 'Rose')
	streamer(face(x, -PR - 0.06, 1.45, '-y'), 0.2, 0.42)
# The lintel and crescent.
box((1.66, 0.3, 0.2), (0, 0, 1.72 + 0.1), 'Pearl', bevel=0.05, segments=2)
box((1.7, 0.34, 0.06), (0, 0, 1.95), 'PaleGold', bevel=0.02, segments=2)
star4(face(0, -0.16, 1.82, '-y'), 0.1, 0.04, 'PaleGold')
crescent(face(0, 0, 1.96, '-y'), 0.36, 0.09, 'PaleGold', span=160, width=0.4)
sphere(0.15, (0, 0, 2.3), 'Starfire')
export('WallGate')
