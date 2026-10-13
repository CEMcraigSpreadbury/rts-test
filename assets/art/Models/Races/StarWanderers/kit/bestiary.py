# Builds Bestiary.glb: a tented pearl keeper's drum beside a great open star
# cage of arching gold ribs circled by two tilted orbit hoops, a starfire orb
# floating over its crown, on a long star plinth. The BeastSpot empty marks
# the cage floor (centre, scaled to its width) where ProductionBuilding
# stands the beast. See starwanderers_common.py.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from starwanderers_common import *

new_scene(791)
plinth_star(1.85, 1.0)
# The keeper's drum.
X, R, WT = -1.2, 0.55, SZ + 1.0
drum(R, SZ, WT, cx=X, ribs=6)
moon_door(face(X, -R + 0.03, SZ, '-y'), w=0.36, h=0.64, glow='Starfire')
porthole(face(X - R * 0.97, 0, SZ + 0.6, '-x'), 0.11, 'Rose')
top, _ = canopy(0.76, 0.95, WT - 0.04, cx=X, gores=6, shape='bell', sag=0.1, hem=0.1)
orb_crown(X, 0, top - 0.03, 0.75, 'Rose')
streamer(face(X + R * 0.97, 0, WT - 0.15, '+x'), 0.22, 0.45)
# The star cage.
CX, CR, CH = 0.95, 0.88, 1.9
FZ = SZ + 0.04
ring_solid(CR + 0.06, CR + 0.04, 0.1, (CX, 0, SZ - 0.06), 'Moonstone', n=20, bevel=0.03)
star_prism(CR * 0.9, CR * 0.62, 8, 0.03, (CX, 0, FZ - 0.01), 'Lavender', rot_z=22.5, bevel=0.01)
ctop, _ = canopy(CR, CH, FZ, cx=CX, gores=10, shape='dome', mats=(), hem=0.0, top=0.97, rot=18)
for rad, z, tilt in ((CR * 0.95, FZ + 0.55, (14, 0, 0)), (CR * 0.8, FZ + 1.15, (-12, 8, 0))):
	torus(rad, 0.035, (CX, 0, z), 'PaleGold', rot=tilt)
orb_crown(CX, 0, ctop - 0.02, 0.9, 'Starfire')
for s in (-1, 1):
	star_pole(CX + s * 1.02, -0.62, SZ - 0.02, 0.8, 0.7, 'Starfire')
amphora(-0.2, -0.75, SZ, 0.85)
export('Bestiary', extras=(spot('BeastSpot', (CX, 0, FZ), 1.78),))
