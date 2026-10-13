# Builds Range.glb: a tented pearl archers' lodge beside a row of round
# pearl star targets ringed in rose and gold, a rack of crescent bows by the
# door, on a long star plinth. See starwanderers_common.py.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from starwanderers_common import *

new_scene(761)
plinth_star(1.5, 0.84)
# The lodge.
X, R, WT = -0.85, 0.5, SZ + 0.9
drum(R, SZ, WT, cx=X, ribs=6)
moon_door(face(X, -R + 0.03, SZ, '-y'), w=0.34, h=0.6)
porthole(face(X - R * 0.97, 0, SZ + 0.55, '-x'), 0.11, 'Rose')
top, _ = canopy(0.7, 0.85, WT - 0.04, cx=X, gores=6, shape='tent', sag=0.1, hem=0.09)
orb_crown(X, 0, top - 0.03, 0.75, 'Rose')
# Targets.
for k, x in enumerate((0.2, 0.75, 1.3)):
	y = 0.12 - 0.05 * k
	for s in (-1, 1):
		cylinder(0.04, 0.9, (x + s * 0.2, y + 0.04, SZ + 0.45), 'LavenderDark', verts=6, bevel=0.0,
				rot=(12, s * 8, 0))
	f = face(x, y, SZ + 0.78, '-y') @ rx(-12)
	cylinder(0.3, 0.1, (0, 0, 0), 'Pearl', verts=18, rot=(90, 0, 0), bevel=0.025, matrix=f)
	torus(0.3, 0.035, (0, -0.02, 0), 'PaleGold', rot=(90, 0, 0), matrix=f)
	torus(0.19, 0.04, (0, -0.05, 0), 'Rose', rot=(90, 0, 0), matrix=f)
	star4(f @ tr(0, -0.06, 0), 0.12, 0.04, 'Rose')
	box((0.04, 0.32, 0.04), (0.05, -0.15, 0.03), 'PaleGold', rot=(0, 0, 10), bevel=0.0, matrix=f)
# Crescent bows on a rack.
box((0.6, 0.1, 0.08), (-0.25, -0.6, SZ + 0.75), 'Pearl', bevel=0.02)
for s in (-1, 1):
	cylinder(0.04, 0.75, (-0.25 + s * 0.28, -0.6, SZ + 0.38), 'Pearl', verts=8, bevel=0.01)
for k in range(2):
	crescent(face(-0.38 + k * 0.26, -0.64, SZ + 0.2, '-y'), 0.22, 0.04, 'PaleGold', span=170, width=0.25)
star_pole(1.55, -0.55, SZ - 0.02, 1.0, 0.8, 'Starfire', streamer_w=0.2)
export('Range')
