# Builds Stables.glb: a long oval pearl stable for the comet foxes with
# three moon-arched stall doors, under a long gored team bell canopy with a
# rose orb, hay and a gold trough before it, on a long star plinth.
# See starwanderers_common.py.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from starwanderers_common import *

new_scene(771)
plinth_star(1.62, 1.05)
R, SX, SY, WT = 0.86, 1.6, 0.95, SZ + 0.85
drum(R, SZ, WT, sx=SX, sy=SY, ribs=10, taper=0.97)
for a in (240, 270, 300):
	x, y, n = ell(0, 0, R * 0.985, SX, SY, math.radians(a))
	moon_door(tr(x, y, SZ) @ rz(n + 90), w=0.34, h=0.6)
for s in (-1, 1):
	porthole(face(s * R * SX * 0.985, 0, SZ + 0.5, '+x' if s > 0 else '-x'), 0.11, 'Rose')
top, _ = canopy(1.0, 0.95, WT - 0.04, gores=10, shape='bell', sx=SX, sy=SY, sag=0.09, hem=0.11, rot=18)
orb_crown(0, 0, top - 0.04, 0.85, 'Rose')
# Hay and a trough.
hay_bale(-1.3, -0.72, SZ - 0.02, rot=20)
box((0.7, 0.22, 0.2), (1.15, -0.95, SZ + 0.1), 'PaleGold', bevel=0.04)
box((0.6, 0.14, 0.06), (1.15, -0.95, SZ + 0.18), 'Hay', bevel=0.02)
star_pole(-1.5, 0.75, SZ - 0.02, 1.1, 0.85, 'Starfire', streamer_w=0.2)
export('Stables')
