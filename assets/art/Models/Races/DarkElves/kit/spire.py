# Builds Spire.glb: the Dark Elves' great spire. A tall obsidian tower ribbed
# with plum blade fins rises to a swooping team spire; two slimmer turrets
# flank it, joined by bridges with webs strung beneath; a huge magenta crystal
# stands in a silver crescent cradle before the door and pennants hang from
# the turrets. See darkelves_common.py.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from darkelves_common import *

new_scene(531)
dais(1.75, 1.42)
octo(1.0, 1.0, 0.14, (0, 0.1, DZ), 'Obsidian', sx=1.05, sy=1.05)
Z0 = DZ + 0.12
R, TZ = 0.8, Z0 + 3.2
rt = tower(R, Z0, TZ, cy=0.1, taper=0.72, bands=(0.04, 0.42, 0.78))
for a in (45, 135, 225, 315):
	ar = math.radians(a)
	f = tr(math.cos(ar) * R * 0.8, 0.1 + math.sin(ar) * R * 0.8, Z0) @ rz(a + 90)
	blade_fin(f, h=2.4, depth=0.5, thick=0.11)
arch_door(face(0, 0.1 - apothem(R) + 0.02, Z0, '-y'), w=0.6, h=0.95)
for z in (1.75, 2.75):
	for side in ('-y', '+x', '-x', '+y'):
		ox = {'-x': -1, '+x': 1}.get(side, 0)
		oy = {'-y': -1, '+y': 1}.get(side, 0)
		a = apothem(R + (rt - R) * (z / 3.2))
		slit(face(ox * a, 0.1 + oy * a, Z0 + z, side), w=0.15, h=0.46)
octo(rt + 0.06, rt + 0.2, 0.16, (0, 0.1, TZ - 0.02), 'Plum')
swoop_spire(0.74, 2.7, TZ + 0.12, cy=0.1, flare=0.34, lift=0.36, finial_h=0.6)
# Flanking turrets.
for s in (-1, 1):
	x, y = s * 1.22, 0.25
	r2, t2 = 0.42, Z0 + 2.3
	rr = tower(r2, Z0 - 0.12, t2, cx=x, cy=y, taper=0.85, bands=(0.08, 0.6))
	slit(face(x, y - apothem(r2 + (rr - r2) * 0.45), Z0 + 0.8, '-y'), w=0.12, h=0.36)
	octo(rr + 0.04, rr + 0.1, 0.1, (x, y, t2 - 0.02), 'Plum')
	swoop_spire(0.48, 1.55, t2 + 0.06, cx=x, cy=y, flare=0.32, lift=0.2, finial_h=0.35, gem='Venom')
	# A bridge to the main tower, a web strung under it.
	bx = s * 0.85
	box((0.62, 0.36, 0.22), (bx, y - 0.05, Z0 + 1.9), 'Obsidian', bevel=0.05, segments=2)
	box((0.66, 0.4, 0.06), (bx, y - 0.05, Z0 + 2.04), 'Silver', bevel=0.02, segments=2)
	web(face(bx, y - 0.15, Z0 + 1.77, '-y'), r=0.26, spokes=5, rings=(0.5, 0.9), arc=(180, 360), thick=0.02)
	pennant(0.3, 0.62, face(x, y - apothem(rr) - 0.07, t2 - 0.12, '-y'))
# The crystal before the door.
CY = -1.12
octo(0.26, 0.2, 0.3, (0, CY, DZ - 0.04), 'ObsidianLight')
band(0.24, DZ + 0.22, h=0.05)
crescent(face(0, CY, DZ + 0.3, '-y'), 0.34, 0.08)
crystal((0, CY, DZ + 0.5), 0.9, 0.17, 'Crystal')
for s in (-1, 1):
	lantern(face(s * 0.46, 0.1 - apothem(R) + 0.04, Z0 + 0.95, '-y'), drop=0.16, s=0.85, arm=0.22)
	crystal_cluster(s * 1.45, -0.95, DZ - 0.02, 0.6, 'Venom' if s > 0 else 'Crystal')
export('Spire')
