# Builds Lumberyard.glb: a tented pearl woodcutters' hut beside a great gold
# crescent moon-saw on a pearl stand over a log, with stacked logs and a
# chopping block, on the star plinth. See starwanderers_common.py.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from starwanderers_common import *

new_scene(781)
plinth_star(1.12, 0.9)
X, Y, R, WT = -0.55, 0.15, 0.5, SZ + 0.85
drum(R, SZ, WT, cx=X, cy=Y, ribs=6)
moon_door(face(X, Y - R + 0.03, SZ, '-y'), w=0.34, h=0.58)
top, _ = canopy(0.7, 0.8, WT - 0.04, cx=X, cy=Y, gores=6, shape='tent', sag=0.1, hem=0.09)
star_finial(X, Y, top - 0.02, 0.9, 'Starfire')
# The moon-saw: a horns-down crescent blade hung from a gold bar.
SXp = 0.55
for s in (-1, 1):
	box((0.12, 0.3, 0.9), (SXp + s * 0.38, -0.2, SZ + 0.45), 'Pearl', bevel=0.04)
	sphere(0.07, (SXp + s * 0.38, -0.2, SZ + 0.93), 'PaleGold')
cylinder(0.04, 0.82, (SXp, -0.2, SZ + 0.84), 'PaleGold', verts=8, rot=(0, 90, 0), bevel=0.0)
crescent(face(SXp, -0.2, SZ + 0.84, '-y') @ rx(180), 0.28, 0.05, 'PaleGold', span=170, width=0.3)
log_x(SXp - 0.6, SXp + 0.6, -0.2, SZ + 0.12, r=0.12)
# Log stacks and block.
log_pile(0.6, 0.48, SZ, 0.95, rows=3, r=0.1, axis='x')
cylinder(0.18, 0.24, (-0.15, -0.6, SZ + 0.12), 'LogB', verts=10, bevel=0.03)
cylinder(0.15, 0.03, (-0.15, -0.6, SZ + 0.25), 'LogEnd', verts=10, bevel=0.0)
star_pole(-1.05, -0.5, SZ - 0.02, 0.9, 0.8, 'Rose')
export('Lumberyard')
