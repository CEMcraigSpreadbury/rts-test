# Builds Market.glb: two hide trading tents on forked poles, one team-dyed and
# one tan striped with team colour, over plank counters of berries, furs and
# tusks, with a rack of drying pelts between them under an antler sign.
# See beastmen_common.py.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from beastmen_common import *

new_scene(351)
mound(1.5, 1.1)


def frame_from(xv, yv, origin):
	zv = xv.cross(yv)
	return Matrix(((xv.x, yv.x, zv.x, origin[0]), (xv.y, yv.y, zv.y, origin[1]), (xv.z, yv.z, zv.z, origin[2]), (0, 0, 0, 1)))


def tent(cx, cy, w, length, ridge_z, eave_z, cloth, stripes=None):
	"""An A-frame hide tent, ridge along Y (open gable to the front)."""
	for y in (cy - length / 2, cy + length / 2):
		post(cx, y, MZ - 0.02, ridge_z - MZ + 0.06, r=0.06)
		for a in (-30, 30):
			box((0.05, 0.05, 0.24), (cx + math.sin(math.radians(a)) * 0.08, y, ridge_z + 0.12), 'Log', rot=(0, a, 0),
					bevel=0.015, segments=2)
	cylinder(0.055, length + 0.3, (cx, cy, ridge_z + 0.02), 'Log', verts=8, rot=(90, 0, 0), bevel=0.02)
	for s in (-1, 1):
		d = Vector((s * w, 0, eave_z - ridge_z))
		slope = d.length
		d.normalize()
		mid = (cx + s * w / 2, cy, (ridge_z + eave_z) / 2 + 0.05)
		f = frame_from(Vector((0, s, 0)), -d, mid)
		scallop_slab(length + 0.1, slope + 0.1, 0.05, cloth, f, n=4, amp=0.09)
		if stripes:
			for x in (-length * 0.28, length * 0.28):
				scallop_slab(0.16, slope + 0.1, 0.05, stripes, f @ Matrix.Translation((x, 0, 0.03)), n=1, amp=0.09)
		# Guy ropes pegged out at the corners.
		for y in (cy - length / 2, cy + length / 2):
			px = cx + s * (w + 0.12)
			box((0.05, 0.05, 0.16), (px, y, MZ + 0.04), 'LogB', bevel=0.015, segments=2)


def counter(cx, cy, w):
	for x in (cx - w / 2 + 0.08, cx + w / 2 - 0.08):
		box((0.1, 0.36, 0.4), (x, cy, MZ + 0.2), 'LogB', bevel=0.03)
	box((w, 0.44, 0.08), (cx, cy, MZ + 0.43), 'Log', bevel=0.03)


# The team tent, left, with berries and sacks.
tent(-0.78, 0.05, 0.62, 1.3, MZ + 1.3, MZ + 0.45, 'TeamColor')
counter(-0.78, -0.62, 0.86)
basket(-1.0, -0.62, MZ + 0.47, r=0.14, h=0.16)
basket(-0.6, -0.62, MZ + 0.47, r=0.14, h=0.16)
sack(-1.3, -0.45, MZ - 0.02, rot=25)
# The tan tent, right, with furs, tusks and a skull.
tent(0.72, 0.15, 0.5, 1.1, MZ + 1.15, MZ + 0.4, 'Hide', stripes='TeamColor')
counter(0.72, -0.5, 0.74)
for i, (x, mtl) in enumerate(((0.5, 'Fur'), (0.68, 'Hide'), (0.86, 'Fur'))):
	box((0.2, 0.3, 0.06 + 0.03 * i), (x, -0.5, MZ + 0.5 + 0.015 * i), mtl, bevel=0.025, segments=2)
for sx in (-1, 1):
	tusk(Matrix.Translation((0.98, -0.5, MZ + 0.5)) @ Matrix.Rotation(math.radians(90), 4, 'Z'), 1.1, sx)
skull(face(0.45, -0.52, MZ + 0.6, '-y'), 0.26, horns='tusks')
# Pelt rack between the tents, under an antler sign.
for x in (-0.12, 0.2):
	post(x, 0.75, MZ - 0.02, 1.25, r=0.05)
cylinder(0.04, 0.5, (0.04, 0.75, MZ + 1.12), 'Log', verts=8, rot=(0, 90, 0), bevel=0.02)
for x, mtl in ((-0.04, 'Fur'), (0.13, 'Hide')):
	box((0.14, 0.04, 0.42), (x, 0.73, MZ + 0.88), mtl, bevel=0.02, segments=2)
antlers(face(0.04, 0.75, MZ + 1.2, '-y'), 0.55)
basket(0.05, -0.9, MZ - 0.02, r=0.16, h=0.2, fill='Apple')
export('Market')
