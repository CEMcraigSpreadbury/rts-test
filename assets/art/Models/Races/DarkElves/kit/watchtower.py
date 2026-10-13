# Builds Watchtower.glb: a slender tapering obsidian tower ribbed with plum
# blade fins, its slits glowing, up to an overhanging octagonal gallery with a
# crown of silver blade teeth, under a tall swooping team spire; a team pennant
# and a venom lantern hang from the gallery. See darkelves_common.py.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from darkelves_common import *

new_scene(511)
dais(0.86, 0.86)
R, TZ = 0.5, DZ + 3.05
rt = tower(R, DZ, TZ, taper=0.82, bands=(0.05, 0.5))
for a in (45, 135, 225, 315):
	ar = math.radians(a)
	f = tr(math.cos(ar) * R * 0.78, math.sin(ar) * R * 0.78, DZ) @ rz(a + 90)
	blade_fin(f, h=2.1, depth=0.36, thick=0.09)
arch_door(face(0, -apothem(R) + 0.02, DZ, '-y'), w=0.4, h=0.62, thorns=False)
for i, z in enumerate((1.25, 2.1)):
	for side in ('-y', '+x', '-x', '+y'):
		if side == '-y' and i == 0:
			continue
		ox = {'-x': -1, '+x': 1}.get(side, 0)
		oy = {'-y': -1, '+y': 1}.get(side, 0)
		a = apothem(R + (rt - R) * (z / 3.05))
		slit(face(ox * a, oy * a, DZ + z, side), w=0.12, h=0.38)
# Corbel and gallery.
GZ = TZ + 0.3
octo(rt, 0.74, 0.3, (0, 0, TZ), 'ObsidianLight')
octo(0.8, 0.8, 0.16, (0, 0, GZ), 'Obsidian')
band(0.82, GZ + 0.16, h=0.06)
for k in range(8):
	a = math.radians(22.5 + 45 * k)
	x, y = math.cos(a) * 0.74, math.sin(a) * 0.74
	f = face(x, y, GZ + 0.18, '-y') @ rz(math.degrees(a) + 90)
	box((0.24, 0.1, 0.26), (0, 0, 0.13), 'Obsidian', bevel=0.04, segments=2, matrix=f)
	box((0.1, 0.1, 0.3), (0, 0, 0.36), 'Silver', rot=(0, 45, 0), bevel=0.02, segments=2, matrix=f)
# Pillars and spire.
SZ = GZ + 0.95
for k in range(4):
	a = math.radians(45 + 90 * k)
	octo(0.06, 0.05, SZ - GZ - 0.1, (math.cos(a) * 0.5, math.sin(a) * 0.5, GZ + 0.12), 'ObsidianLight', bevel=0.015)
octo(0.3, 0.3, SZ - GZ - 0.1, (0, 0, GZ + 0.12), 'ObsidianDark')
crystal((0, 0, GZ + 0.25), 0.5, 0.12, 'Crystal')
swoop_spire(0.82, 2.1, SZ, flare=0.3, lift=0.3, rot=0)
pennant(0.36, 0.7, face(-0.18, -0.86, GZ - 0.05, '-y'))
lantern(face(0.62, -0.62, GZ, '-y') @ rz(-45), drop=0.22, s=0.9, arm=0.2)
export('Watchtower')
