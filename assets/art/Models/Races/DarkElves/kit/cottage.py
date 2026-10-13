# Builds Cottage.glb: a slim octagonal obsidian tower-house on its dais under
# a swooping team spire, a pointed-arch door watched by a silver spider, glowing
# slit windows, a venom lantern by the door and crystals at its foot.
# See darkelves_common.py.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from darkelves_common import *

new_scene(501)
dais(0.78, 0.88)
R, TOP = 0.6, DZ + 1.3
rt = tower(R, DZ, TOP, taper=0.88, bands=(0.06, 0.62))
ap = apothem(R)
arch_door(face(0, -ap + 0.02, DZ, '-y'), w=0.42, h=0.62, thorns=False)
spider(face(0, -apothem(R + (rt - R) * 0.8) - 0.02, DZ + 1.08, '-y'), 0.55)
for side in ('+x', '-x', '+y'):
	ox = {'-x': -1, '+x': 1}.get(side, 0)
	oy = {'+y': 1}.get(side, 0)
	a = apothem(R + (rt - R) * 0.5)
	slit(face(ox * a, oy * a, DZ + 0.66, side), w=0.13, h=0.36)
octo(rt + 0.06, rt + 0.14, 0.12, (0, 0, TOP - 0.02), 'Plum')
swoop_spire(0.72, 1.75, TOP + 0.08, flare=0.32, lift=0.26)
lantern(face(0.3, -ap + 0.03, DZ + 0.82, '-y'), drop=0.12, s=0.8, arm=0.24)
crystal_cluster(-0.52, -0.52, DZ - 0.02, 0.6)
crystal_cluster(0.5, 0.56, DZ - 0.02, 0.45, 'Venom')
export('Cottage')
