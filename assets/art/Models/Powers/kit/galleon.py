# Builds Galleon.glb: the Dread Galleon, a black-sailed pirate warship some
# 18 m long, its bow at -Y (game +Z), keel at z 0. A planked hull with two
# decks of guns either side, railed decks with barrels, crates, hatches and a
# ship's wheel, a carved stern castle with a lit gallery and lanterns, a skull
# figurehead, anchors, three masts of billowing torn black sails on their
# yards with shrouds and stays, crow's nests, team pennants and a Jolly Roger.
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _kit import *

new_scene(331)
L = 17.0
DECK = 3.1


def rope(a, b, r=0.035, mat_name='WoodDark'):
	"""A straight line of rigging from `a` to `b`."""
	a, b = Vector(a), Vector(b)
	d = b - a
	bpy.ops.mesh.primitive_cylinder_add(vertices=5, radius=r, depth=d.length)
	obj = bpy.context.active_object
	obj.matrix_world = Matrix.Translation((a + b) / 2) @ Vector((0, 0, 1)).rotation_difference(d).to_matrix().to_4x4()
	return common._finish(obj, mat_name, 0.0, 0)


def sail(y, z, w, h, billow=0.6, torn=False):
	"""A square sail hung from its yard at height z + h/2, bellied forward
	(toward -Y) in three panels."""
	panels = 5
	for i in range(panels):
		t = (i + 0.5) / panels - 0.5
		x = t * w
		bulge = billow * (1.0 - (2.0 * t) ** 2)
		ang = math.degrees(math.atan2(-billow * 8.0 * t / panels, 1.0)) * 0.0
		box((w / panels + 0.04, 0.12, h), (x, y - 0.3 - bulge, z), 'SailBlack', rot=(0, 0, -t * 28), bevel=0.04)
	# A hem and a torn ragged corner.
	box((w * 0.98, 0.16, 0.14), (0, y - 0.3 - billow * 0.5, z - h / 2), 'SailTorn', bevel=0.04)
	if torn:
		box((w * 0.22, 0.14, h * 0.28), (w * 0.3, y - 0.32 - billow * 0.6, z - h * 0.3), 'SailTorn', rot=(0, 18, 0), bevel=0.04)


# --- hull -------------------------------------------------------------------
box((4.4, L * 0.78, 1.2), (0, 0.6, 0.6), 'HullDark', bevel=0.45, segments=4)
box((5.4, L * 0.74, 2.2), (0, 0.9, 2.0), 'Hull', bevel=0.5, segments=4)
for side in (-1, 1):
	# The bow: planked flanks swept in to the stem.
	box((0.5, 3.4, 2.6), (side * 1.75, -L * 0.33, 1.9), 'Hull', rot=(0, 0, side * -16), bevel=0.2)
	box((0.5, 3.0, 2.4), (side * 0.95, -L * 0.42, 2.0), 'Hull', rot=(0, 0, side * -34), bevel=0.2)
	# Planking seams, two gold wales and the rail cap.
	for z in (0.7, 1.2, 2.25, 2.85):
		box((0.06, L * 0.7, 0.05), (side * 2.71, 0.9, z), 'HullDark', bevel=0.0)
	box((0.14, L * 0.74, 0.22), (side * 2.72, 0.9, 3.05), 'Gold', bevel=0.06)
	box((0.12, L * 0.7, 0.16), (side * 2.73, 0.9, 1.55), 'Gold', bevel=0.05)
	# Gun ports, two rows, a cannon out of each with a muzzle ring.
	for row, z in enumerate((1.95, 2.6)):
		for i in range(5):
			y = -3.2 + i * 2.2 + row * 0.6
			box((0.12, 0.66, 0.52), (side * 2.72, y, z), 'IronDark', bevel=0.04)
			box((0.1, 0.72, 0.08), (side * 2.74, y, z + 0.3), 'Red', bevel=0.02)
			cylinder(0.17, 0.8, (side * 3.0, y, z), 'IronDark', verts=10, rot=(0, 90, 0), bevel=0.03)
			cylinder(0.22, 0.1, (side * 3.36, y, z), 'Iron', verts=10, rot=(0, 90, 0), bevel=0.02)
	# An anchor hung at each bow.
	cylinder(0.08, 1.6, (side * 2.3, -L * 0.34, 2.0), 'Iron', verts=8, bevel=0.0)
	box((1.2, 0.12, 0.14), (side * 2.3, -L * 0.34, 1.25), 'Iron', rot=(0, 0, 90), bevel=0.04)
	torus(0.18, 0.05, (side * 2.3, -L * 0.34, 2.85), 'Iron', rot=(90, 0, 90))
	for k in (-1, 1):
		pyramid(0.25, 0.4, (side * 2.3, -L * 0.34 + k * 0.6, 1.2), 'Iron')
box((1.0, 3.0, 2.2), (0, -L * 0.45, 2.2), 'Hull', bevel=0.35)

# --- decks ------------------------------------------------------------------
box((5.0, L * 0.7, 0.16), (0, 0.9, DECK + 0.02), 'Wood', bevel=0.05)
for i in range(9):
	box((0.04, L * 0.68, 0.02), (-2.0 + i * 0.5, 0.9, DECK + 0.11), 'WoodDark', bevel=0.0)
# Rails: a cap on posts down both sides.
for side in (-1, 1):
	box((0.12, L * 0.6, 0.1), (side * 2.55, 0.4, DECK + 0.75), 'WoodDark', bevel=0.03)
	for i in range(14):
		box((0.08, 0.08, 0.65), (side * 2.55, -4.6 + i * 0.75, DECK + 0.42), 'Wood', bevel=0.0)
# Forecastle with its own rail.
box((4.2, 2.6, 0.9), (0, -4.6, DECK + 0.5), 'Hull', bevel=0.2)
box((4.4, 0.16, 0.5), (0, -5.9, DECK + 1.15), 'Gold', bevel=0.05)
# Hatches, barrels, crates and a coil of rope.
box((1.4, 1.2, 0.2), (0, -1.2, DECK + 0.2), 'WoodDark', bevel=0.05)
box((1.2, 1.0, 0.08), (0, -1.2, DECK + 0.32), 'Iron', bevel=0.02)
box((1.4, 1.2, 0.2), (0, 3.6, DECK + 0.2), 'WoodDark', bevel=0.05)
for x, y in ((-1.7, -2.6), (-1.5, -2.0), (1.8, 0.4), (1.6, 4.4)):
	barrel(x, y, DECK + 0.1, r=0.3, h=0.7)
for x, y, s, r in ((1.6, -2.6, 0.6, 15), (1.7, -1.9, 0.45, -10), (-1.7, 4.3, 0.6, 30)):
	crate(x, y, DECK + 0.1, s, r)
torus(0.35, 0.12, (-1.6, 1.0, DECK + 0.2), 'Sack')
# Cannons on the open deck too.
for side in (-1, 1):
	for y in (-0.4, 2.2):
		box((0.6, 0.8, 0.3), (side * 1.9, y, DECK + 0.25), 'WoodDark', bevel=0.05)
		cylinder(0.16, 1.2, (side * 2.15, y, DECK + 0.55), 'IronDark', verts=10, rot=(0, 90, 0), bevel=0.03)

# --- stern castle -----------------------------------------------------------
box((5.4, 4.2, 2.4), (0, 6.6, 4.3), 'Hull', bevel=0.3)
box((5.0, 3.6, 1.4), (0, 6.9, 6.2), 'HullDark', bevel=0.25)
# Gold mouldings round the castle's two storeys (edges only, not the roof).
for (hx, hy, cy, z) in ((2.8, 2.2, 6.6, 5.55), (2.6, 1.9, 6.9, 6.95)):
	for side in (-1, 1):
		box((0.16, hy * 2, 0.18), (side * hx, cy, z), 'Gold', bevel=0.05)
		box((hx * 2, 0.16, 0.18), (0, cy + side * hy, z), 'Gold', bevel=0.05)
box((4.9, 3.5, 0.12), (0, 6.9, 6.95), 'Wood', bevel=0.04)
# The quarterdeck: its rail and the ship's wheel.
for side in (-1, 1):
	box((0.1, 3.4, 0.1), (side * 2.4, 6.9, 7.65), 'WoodDark', bevel=0.03)
	for i in range(6):
		box((0.07, 0.07, 0.6), (side * 2.4, 5.4 + i * 0.6, 7.35), 'Wood', bevel=0.0)
box((0.6, 0.4, 1.0), (0, 5.6, 7.5), 'WoodDark', bevel=0.06)
torus(0.55, 0.06, (0, 5.35, 8.0), 'Wood', rot=(90, 0, 0))
for k in range(8):
	a = math.radians(k * 45)
	cylinder(0.04, 1.4, (0, 5.35, 8.0), 'Wood', verts=5, rot=(0, k * 45, 0), bevel=0.0)
cylinder(0.12, 0.2, (0, 5.35, 8.0), 'Gold', verts=8, rot=(90, 0, 0), bevel=0.02)
# The lit stern gallery, a balcony rail under it and carved gold trim.
for i in range(4):
	x = -1.8 + i * 1.2
	box((0.62, 0.1, 0.8), (x, 8.72, 4.4), 'Ember', bevel=0.03)
	box((0.5, 0.1, 0.55), (x, 8.62, 6.25), 'Ember', bevel=0.03)
	box((0.74, 0.14, 0.12), (x, 8.75, 4.86), 'Gold', bevel=0.03)
	box((0.08, 0.14, 0.95), (x + 0.6, 8.76, 4.4), 'Gold', bevel=0.02)
box((5.2, 0.7, 0.12), (0, 9.0, 3.45), 'WoodDark', bevel=0.03)
box((5.2, 0.08, 0.08), (0, 9.32, 3.95), 'Gold', bevel=0.02)
for i in range(9):
	box((0.06, 0.06, 0.45), (-2.4 + i * 0.6, 9.32, 3.7), 'Gold', bevel=0.0)
sphere(0.55, (0, 8.9, 5.55), 'Gold')
sphere(0.32, (0, 9.25, 5.55), 'Bone')
for side in (-1, 1):
	# Quarter galleries bulging out of each side of the stern.
	box((0.8, 2.4, 1.8), (side * 2.9, 6.6, 4.6), 'Hull', bevel=0.3)
	box((0.12, 1.6, 0.6), (side * 3.32, 6.6, 4.7), 'Ember', bevel=0.03)
	sphere(0.28, (side * 2.4, 8.9, 7.4), 'Ember')
	cylinder(0.06, 0.6, (side * 2.4, 8.9, 7.0), 'IronDark', verts=6, bevel=0.0)
	box((0.3, 0.3, 0.06), (side * 2.4, 8.9, 7.7), 'IronDark', bevel=0.02)

# --- bow: figurehead, bowsprit and jib ---------------------------------------
sphere(0.62, (0, -L * 0.53, 2.6), 'Bone')
box((0.7, 0.5, 0.45), (0, -L * 0.53 - 0.1, 2.15), 'Bone', bevel=0.15)
for side in (-1, 1):
	sphere(0.17, (side * 0.24, -L * 0.53 - 0.48, 2.72), 'IronDark')
	box((0.12, 0.1, 0.32), (side * 0.12, -L * 0.53 - 0.42, 2.0), 'Bone', bevel=0.03)
cylinder(0.16, 6.5, (0, -L * 0.6, 4.2), 'WoodDark', verts=8, rot=(-62, 0, 0), bevel=0.0)
pyramid(0.3, 0.6, (0, -L * 0.6 - 2.9, 5.7), 'Gold')
bow_tip = Vector((0, -L * 0.6 - 2.85, 5.75))

# --- masts, yards, sails and rigging -----------------------------------------
masts = ((-2.6, 13.5, 3), (1.6, 15.5, 3), (5.6, 11.0, 2))
tops = []
for m, (y, h, sails) in enumerate(masts):
	top = DECK + h
	tops.append(Vector((0, y, top)))
	cylinder(0.28, h, (0, y, DECK + h / 2), 'WoodDark', verts=12, bevel=0.0)
	for k in range(4):
		cylinder(0.32, 0.12, (0, y, DECK + 1.0 + k * h * 0.22), 'Iron', verts=12, bevel=0.0)
	for k in range(sails):
		z = DECK + h * (0.34 + k * 0.26)
		w = 6.8 - k * 1.5
		hgt = 2.9 - k * 0.2
		cylinder(0.13, w + 0.8, (0, y, z + hgt / 2 + 0.05), 'WoodDark', verts=8, rot=(0, 90, 0), bevel=0.0)
		for side in (-1, 1):
			sphere(0.12, (side * (w / 2 + 0.4), y, z + hgt / 2 + 0.05), 'Iron')
		sail(y, z, w, hgt, billow=0.7 - k * 0.15, torn=(k == 0))
		# A bone skull and crossbones on the main course.
		if k == 0 and m == 1:
			sphere(0.6, (0, y - 1.15, z + 0.25), 'Bone')
			for side in (-1, 1):
				sphere(0.15, (side * 0.22, y - 1.7, z + 0.33), 'IronDark')
				box((1.6, 0.08, 0.24), (0, y - 1.05, z - 0.6), 'Bone', rot=(0, side * 35, 0), bevel=0.04)
	# The crow's nest.
	cylinder(0.8, 0.55, (0, y, DECK + h * 0.86), 'Wood', verts=12, bevel=0.05)
	torus(0.8, 0.05, (0, y, DECK + h * 0.86 + 0.3), 'WoodDark')
	# Shrouds: three lines each side from the rail up to the nest.
	for side in (-1, 1):
		for k in (-0.6, 0.0, 0.6):
			rope((side * 2.5, y + k, DECK + 0.75), (side * 0.7, y, DECK + h * 0.84))
		rope((side * 2.5, y - 0.6, DECK + 0.75 + 1.4), (side * 2.5, y + 0.6, DECK + 0.75 + 1.4), r=0.025)
	# Team pennant at the masthead.
	box((0.08, 1.8, 0.75), (0, y + 0.9, top + 0.2), 'TeamColor', bevel=0.03)
	box((0.08, 0.9, 0.38), (0, y + 2.1, top + 0.2), 'TeamColorDark', bevel=0.02)
	sphere(0.18, (0, y, top + 0.05), 'Gold')
# Stays between the mastheads, and down to the bowsprit and stern.
rope(bow_tip, tops[0] - Vector((0, 0, 0.6)))
for a, b in zip(tops, tops[1:]):
	rope(a - Vector((0, 0, 0.5)), b - Vector((0, 0, 0.9)))
rope(tops[-1] - Vector((0, 0, 0.5)), (0, 8.6, 7.8))
# A jib sail on the forestay.
box((0.12, 3.6, 2.6), (0, -L * 0.53 - 0.2, 6.4), 'SailBlack', rot=(-38, 0, 0), bevel=0.04)
# The Jolly Roger from the mizzen.
box((0.08, 1.6, 1.1), (0, 5.6 + 0.85, DECK + 11.0 - 1.2), 'SailBlack', bevel=0.03)
sphere(0.26, (-0.07, 5.6 + 0.85, DECK + 11.0 - 1.1), 'Bone')
box((0.06, 0.9, 0.1), (-0.07, 5.6 + 0.85, DECK + 11.0 - 1.45), 'Bone', rot=(30, 0, 0), bevel=0.02)
box((0.06, 0.9, 0.1), (-0.07, 5.6 + 0.85, DECK + 11.0 - 1.45), 'Bone', rot=(-30, 0, 0), bevel=0.02)
export('Galleon')
