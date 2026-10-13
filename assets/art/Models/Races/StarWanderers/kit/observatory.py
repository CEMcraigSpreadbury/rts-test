# Builds Observatory.glb: a round pearl drum under a gored team dome with a
# great gold-banded telescope pushing out of it at the stars, an orrery on
# the plinth beside it, on the star plinth. See starwanderers_common.py.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from starwanderers_common import *

new_scene(741)
plinth_star(1.12)
R, WT = 0.88, SZ + 1.15
drum(R, SZ, WT, ribs=8)
moon_door(face(0, -R * 0.96 + 0.02, SZ, '-y'), w=0.46, h=0.74, glow='Starfire')
porthole(face(-R * 0.96, 0, SZ + 0.7, '-x'), 0.13)
top, _ = canopy(1.02, 1.0, WT - 0.04, gores=8, shape='dome', sag=0.08, hem=0.1)
# The great telescope.
f = tr(0.05, 0.1, WT + 0.7) @ rz(-30) @ rx(52)
cylinder(0.17, 1.1, (0, 0, 0.45), 'Pearl', verts=12, bevel=0.02, matrix=f, radius2=0.2)
cylinder(0.23, 0.5, (0, 0, 1.15), 'Lavender', verts=12, bevel=0.02, matrix=f, radius2=0.26)
for zz in (0.2, 0.9, 1.42):
	cylinder(0.27 if zz > 1 else 0.22, 0.07, (0, 0, zz), 'PaleGold', verts=12, bevel=0.015, matrix=f)
cylinder(0.2, 0.04, (0, 0, 1.44), 'Starfire', verts=12, bevel=0.0, matrix=f)
star_finial(0, 0, top - 0.02, 1.0, 'Starfire')
orrery(0.95, -0.8, SZ - 0.02, 0.85, 'Starfire')
star_pole(-0.95, -0.8, SZ - 0.02, 1.0, 0.85, 'Rose')
export('Observatory')
