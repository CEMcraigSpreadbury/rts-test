# Builds Bestiary.glb: a spired keeper's tower beside a great domed cage of
# curved silver bars rising to a crescent crown, webs strung in its top, on an
# obsidian ring floor. The BeastSpot empty marks the cage floor (centre,
# scaled to its width) where ProductionBuilding stands the beast's sprite.
# See darkelves_common.py.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from darkelves_common import *

new_scene(581)
dais(2.15, 1.42)
# The keeper's tower.
TX, TY, R, TT = -1.25, 0.15, 0.62, DZ + 2.2
rt = tower(R, DZ, TT, cx=TX, cy=TY, taper=0.84, bands=(0.06, 0.5))
for a in (45, 135, 225, 315):
	ar = math.radians(a)
	blade_fin(tr(TX + math.cos(ar) * R * 0.8, TY + math.sin(ar) * R * 0.8, DZ) @ rz(a + 90), h=1.5, depth=0.36, thick=0.09)
arch_door(face(TX, TY - apothem(R) + 0.02, DZ, '-y'), w=0.44, h=0.66, thorns=False)
slit(face(TX, TY - apothem(R + (rt - R) * 0.75), DZ + 1.6, '-y'), w=0.13, h=0.38)
slit(face(TX - apothem(R + (rt - R) * 0.6), TY, DZ + 1.3, '-x'), w=0.13, h=0.38)
octo(rt + 0.05, rt + 0.13, 0.12, (TX, TY, TT - 0.02), 'Plum')
swoop_spire(0.74, 2.0, TT + 0.08, cx=TX, cy=TY, flare=0.32, lift=0.28)
pennant(0.34, 0.62, face(TX + apothem(rt) + 0.05, TY, TT - 0.15, '+x'))
# The cage.
CX, CY, CR, CH = 0.95, 0.0, 0.88, 2.0
FZ = DZ + 0.1
octo(CR + 0.08, CR + 0.05, 0.12, (CX, CY, DZ - 0.02), 'ObsidianLight')
band(CR + 0.06, FZ, h=0.05)
BARS = 10
prof = [(CR * math.cos(math.radians(80 * t)) ** 0.7, CH * math.sin(math.radians(90 * t))) for t in
		[k / 6 for k in range(7)]]
for b in range(BARS):
	a = 2 * math.pi * b / BARS + math.pi / BARS
	for k in range(6):
		r0, z0 = prof[k]
		r1, z1 = prof[k + 1]
		p0 = Vector((CX + math.cos(a) * r0, CY + math.sin(a) * r0, FZ + z0))
		p1 = Vector((CX + math.cos(a) * r1, CY + math.sin(a) * r1, FZ + z1))
		d = p1 - p0
		m = Matrix.Translation((p0 + p1) / 2) @ d.to_track_quat('Z', 'Y').to_matrix().to_4x4()
		cylinder(0.035, d.length + 0.03, (0, 0, 0), 'Silver', verts=6, bevel=0.0, matrix=m)
for f in (0.32, 0.68):
	r, z = prof[2][0] if f < 0.5 else prof[4][0], prof[2][1] if f < 0.5 else prof[4][1]
	torus(r, 0.035, (CX, CY, FZ + z), 'Silver')
cylinder(0.14, 0.14, (CX, CY, FZ + CH + 0.03), 'Silver', verts=8, bevel=0.02)
crescent(face(CX, CY, FZ + CH + 0.1, '-y'), 0.28, 0.07)
crystal((CX, CY, FZ + CH + 0.3), 0.42, 0.1, 'Crystal', matrix=None)
for a in (60, 200, 320):
	ar = math.radians(a)
	r, z = prof[4]
	web(face(CX + math.cos(ar) * r * 0.82, CY + math.sin(ar) * r * 0.82, FZ + z + 0.12, '-y') @ rz(a + 90), r=0.34,
			spokes=5, rings=(0.5, 0.9), arc=(20, 160), thick=0.02)
for s in (-1, 1):
	lantern(face(CX + s * 0.75, CY - 0.95, DZ + 1.0, '-y'), drop=0.1, s=0.8, arm=0.02)
	blade_post(CX + s * 0.75, CY - 0.95, DZ, 1.0, r=0.05, s=0.55)
crystal_cluster(-0.25, -1.0, DZ - 0.02, 0.5, 'Venom')
# Where the beast stands.
spot = bpy.data.objects.new('BeastSpot', None)
bpy.context.scene.collection.objects.link(spot)
spot.location = (CX, CY, FZ)
spot.scale = (1.77, 1.77, 1.77)
export('Bestiary', extras=(spot,))
