# Builds Cottage.glb: a round pearl tent-house ribbed in lavender under a
# gored team bell canopy, a rose orb floating over its crown, on the star
# plinth. See starwanderers_common.py.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from starwanderers_common import *

new_scene(701)
plinth_star(0.66)
R, WT = 0.52, SZ + 0.78
rt = drum(R, SZ, WT, ribs=6)
moon_door(face(0, -R + 0.03, SZ, '-y'), w=0.36, h=0.6)
for s in ('-x', '+x'):
	x = -R * 0.97 if s == '-x' else R * 0.97
	porthole(face(x, 0, SZ + 0.5, s), 0.12, 'Rose')
top, tr_ = canopy(0.78, 0.95, WT - 0.04, gores=6, shape='bell', sag=0.1, hem=0.1)
orb_crown(0, 0, top - 0.04, 0.7, 'Rose')
export('Cottage')
