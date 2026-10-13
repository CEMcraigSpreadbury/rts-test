# Builds StarGate.glb: a great upright gold ring portal filled with a
# lavender moonglow veil and a rose star, cradled by two pearl crescent
# supports and circled by a tilted orbit hoop, a starfire orb over its crown,
# star poles with team streamers either side, on the star plinth.
# See starwanderers_common.py.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from starwanderers_common import *

new_scene(801)
plinth_star(1.45, 1.2)
RR, RZ = 0.95, SZ + 1.2
# The cradle: a stepped pearl dais and two curved supports.
ring_solid(0.9, 0.82, 0.14, (0, 0, SZ - 0.02), 'Moonstone', n=16, sy=0.45, bevel=0.03)
for s in (-1, 1):
	f = tr(s * 1.15, 0, SZ + 0.04) @ ry(-s * 15)
	box((0.24, 0.36, 0.9), (0, 0, 0.42), 'Pearl', bevel=0.06, matrix=f)
	box((0.28, 0.4, 0.08), (0, 0, 0.1), 'PaleGold', bevel=0.02, matrix=f)
	box((0.08, 0.38, 0.7), (-s * 0.0, 0, 0.45), 'Lavender', bevel=0.02, matrix=f)
# The ring and its veil.
torus(RR, 0.13, (0, 0, RZ), 'PaleGold', rot=(90, 0, 0))
torus(RR - 0.16, 0.05, (0, 0, RZ), 'Pearl', rot=(90, 0, 0))
cylinder(RR - 0.16, 0.05, (0, 0, RZ), 'MoonGlow', verts=24, rot=(90, 0, 0), bevel=0.0)
star4(face(0, -0.06, RZ, '-y'), 0.42, 0.06, 'Rose')
star4(face(0, 0.06, RZ, '+y'), 0.42, 0.06, 'Rose')
for k in range(8):
	a = 2 * math.pi * k / 8
	sphere(0.08, (math.cos(a) * RR, -0.12, RZ + math.sin(a) * RR), 'Starfire')
torus(RR + 0.32, 0.035, (0, 0, RZ), 'PaleGold', rot=(70, 0, 28))
orb_crown(0, 0, RZ + RR + 0.1, 0.9, 'Starfire', ring=False)
for s in (-1, 1):
	star_pole(s * 1.3, -0.55, SZ - 0.02, 1.4, 0.9, 'Rose', streamer_w=0.22)
	amphora(s * 1.05, 0.65, SZ, 0.8, 'Lavender')
export('StarGate')
