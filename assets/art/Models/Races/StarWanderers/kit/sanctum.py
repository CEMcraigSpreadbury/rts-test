# Builds Sanctum.glb: a round pearl shrine ringed by slim gold-capped
# columns carrying a gold orbit ring, under a big gored team onion canopy
# crowned by a rose orb in a double orbit; star poles flank the moon door,
# on the star plinth. See starwanderers_common.py.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from starwanderers_common import *

new_scene(731)
plinth_star(1.2, 1.2)
R, WT = 0.82, SZ + 1.45
drum(R, SZ, WT, ribs=8)
moon_door(face(0, -R * 0.96 + 0.02, SZ, '-y'), w=0.5, h=0.85, glow='Rose')
for s in ('-x', '+x'):
	porthole(face(R * 0.96 * (1 if s == '+x' else -1), 0, SZ + 0.95, s), 0.14, 'Rose')
# The colonnade.
CR = 1.04
for i in range(10):
	a = math.pi * 2 * i / 10 + math.pi / 10
	if abs(math.degrees(a) - 270) < 25:
		continue
	x, y = math.cos(a) * CR, math.sin(a) * CR
	cylinder(0.09, 0.08, (x, y, SZ + 0.04), 'Moonstone', verts=10, bevel=0.015)
	cylinder(0.06, WT - SZ - 0.1, (x, y, SZ + (WT - SZ) / 2), 'Pearl', verts=8, bevel=0.01)
	cylinder(0.09, 0.08, (x, y, WT - 0.08), 'PaleGold', verts=10, bevel=0.015)
torus(CR, 0.05, (0, 0, WT - 0.02), 'PaleGold')
top, _ = canopy(1.18, 1.65, WT - 0.02, gores=10, shape='onion', sag=0.08, hem=0.12)
t2 = orb_crown(0, 0, top - 0.04, 1.15, 'Rose')
torus(0.42, 0.024, (0, 0, t2 - 0.2), 'PaleGold', rot=(-55, 0, 40))
for s in (-1, 1):
	star_pole(s * 0.72, -1.05, SZ - 0.02, 1.3, 0.9, 'Rose', streamer_w=0.22)
export('Sanctum')
