# Builds Watchtower.glb: a slim tapering pearl tower ribbed in lavender, a
# gold-railed lookout gallery with a telescope under a tented team canopy on
# slim posts, a starfire orb in an orbit ring over it, on the star plinth.
# See starwanderers_common.py.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from starwanderers_common import *

new_scene(721)
plinth_star(0.6)
R, GT = 0.44, SZ + 3.4
rt = drum(R, SZ, GT, ribs=6, taper=0.78)
moon_door(face(0, -R + 0.03, SZ, '-y'), w=0.32, h=0.56)
for z, s in ((SZ + 1.45, '-y'), (SZ + 2.4, '-y')):
	k = (z - SZ) / (GT - SZ)
	porthole(face(0, -(R + (rt - R) * k) + 0.02, z, s), 0.1)
# The gallery.
ring_solid(rt + 0.1, 0.66, 0.18, (0, 0, GT - 0.06), 'Moonstone', n=16, bevel=0.03)
ring_solid(0.68, 0.68, 0.06, (0, 0, GT + 0.1), 'PaleGold', n=16, bevel=0.02)
ring_solid(0.6, 0.6, 0.06, (0, 0, GT + 0.13), 'Pearl', n=16, bevel=0.02)
for i in range(6):
	a = math.pi * 2 * i / 6 + math.pi / 6
	cylinder(0.04, 0.72, (math.cos(a) * 0.6, math.sin(a) * 0.6, GT + 0.5), 'Pearl', verts=8, bevel=0.01)
torus(0.6, 0.03, (0, 0, GT + 0.42), 'PaleGold')
telescope(0.2, -0.25, GT + 0.12, 0.8, 0.7, yaw=-25, pitch=20)
top, _ = canopy(0.78, 0.75, GT + 0.86, gores=6, shape='tent', sag=0.1, hem=0.08, rot=30)
orb_crown(0, 0, top - 0.03, 0.85, 'Starfire')
streamer(face(0, -rt - 0.06, GT - 0.3, '-y'), 0.24, 0.5)
export('Watchtower')
