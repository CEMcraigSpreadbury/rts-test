# Builds Granary.glb: a tall round pearl store under a gored team dome with a
# smaller tented drum beside it, star-fruit baskets and amphorae at the door,
# on the star plinth. See starwanderers_common.py.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from starwanderers_common import *

new_scene(711)
plinth_star(1.12, 0.92)
# The great store.
X, R, WT = -0.3, 0.68, SZ + 1.3
drum(R, SZ, WT, cx=X, ribs=8)
moon_door(face(X, -R * 0.96 + 0.02, SZ, '-y'), w=0.42, h=0.72, glow='Starfire')
porthole(face(X - 0.35, -R * 0.82, SZ + 1.0, '-y') @ rz(-30), 0.1)
top, _ = canopy(0.88, 0.9, WT - 0.04, cx=X, gores=8, shape='dome', sag=0.09, hem=0.1)
orb_crown(X, 0, top - 0.03, 0.8, 'Starfire')
# The small store.
X2, R2, WT2 = 0.62, 0.42, SZ + 0.85
drum(R2, SZ, WT2, cx=X2, cy=0.12, ribs=6)
porthole(face(X2 + R2 * 0.95, 0.12, SZ + 0.55, '+x'), 0.1, 'Rose')
top2, _ = canopy(0.56, 0.7, WT2 - 0.04, cx=X2, cy=0.12, gores=6, shape='tent', sag=0.1, hem=0.08)
star_finial(X2, 0.12, top2 - 0.02, 0.8, 'Rose')
# Harvest at the door.
for i, (x, y) in enumerate(((0.35, -0.62), (0.62, -0.5))):
	cylinder(0.17, 0.2, (x, y, SZ + 0.1), 'Silk', verts=10, bevel=0.03)
	for k in range(3):
		sphere(0.08, (x + 0.07 * math.cos(k * 2.1), y + 0.07 * math.sin(k * 2.1), SZ + 0.23), 'StarFruit')
amphora(0.95, -0.25, SZ, 1.0)
amphora(-1.05, -0.45, SZ, 0.85)
export('Granary')
