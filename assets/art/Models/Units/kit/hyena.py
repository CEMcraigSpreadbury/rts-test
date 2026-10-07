"""The Hyena: a chibi spotted hyena on four legs, no rider. The gnolls' own
head (gnoll.py: muzzle, eyes, big ears, mane ridge, spots) on a sloped,
long body: high shoulders, low rump, the mane ridge running on down the
back, a short bushy tail. The team's colour is on a hide collar.

Built in a figure's standing space (the ground at Body.base_height, facing
-Y), like horse.py, so units._assemble drops it onto the ground.
"""
import math

from mathutils import Matrix, Vector

import geo
import gnoll
from geo import SMOOTH
from palette import row
from parts import seg

## Where the head's centre sits above the ground and ahead of the middle,
## and how big it is against a gnoll's.
HEAD_AT = Vector((0.0, -0.335, 0.510))
HEAD_SCALE = 0.92
## The spine's line, chest to rump: (y, z above the ground, radius).
SPINE = [(-0.285, 0.360, 0.020), (-0.245, 0.372, 0.110), (-0.130, 0.372, 0.140), (0.010, 0.338, 0.130),
		(0.135, 0.302, 0.114), (0.225, 0.278, 0.094), (0.272, 0.272, 0.0)]


def _head(b, lod):
	"""The gnoll head, tipped back as theirs is, shrunk a touch and moved
	to the end of the neck."""
	head = gnoll.head(b, lod)
	pieces = [head, gnoll.face(b, lod, head), gnoll.muzzle(b, lod), gnoll.ears(b, lod),
			gnoll.mane(b, lod, head), gnoll.head_spots(b, lod, head)]
	g = b.base_height
	move = Matrix.Translation(HEAD_AT + Vector((0.0, 0.0, g))) @ Matrix.Scale(HEAD_SCALE, 4) \
			@ Matrix.Translation(-b.head_centre) @ b.head_matrix()
	bm = geo.new_bm()
	for piece in pieces:
		geo.merge(bm, piece, move)
	return bm


def _body(b, lod):
	g = b.base_height
	pts = [Vector((0.0, y, g + z)) for y, z, _r in SPINE]
	body = geo.tube(pts, [r for _y, _z, r in SPINE], seg(lod, 12, 8), row("fur"), sharp=SMOOTH)
	# The neck, up from the chest into the back of the head.
	neck = geo.tube([Vector((0.0, -0.170, g + 0.380)), Vector((0.0, -0.250, g + 0.440)),
			Vector((0.0, -0.300, g + 0.480))], [0.105, 0.100, 0.090], seg(lod, 10, 7), row("fur"), sharp=SMOOTH)
	geo.merge(body, neck)
	# A pale bib down the front of the chest.
	bib = geo.ellipsoid(0.085, 0.060, 0.105, seg(lod, 9, 6), 4, row("fur_light"), sharp=SMOOTH)
	geo.rotate(bib, -20.0, 'X')
	geo.translate(bib, (0.0, -0.262, g + 0.335))
	geo.merge(body, bib)
	return body


def _legs(b, lod):
	"""Long front legs, short bent hind ones, dark paws with bone claws."""
	g = b.base_height
	bm = geo.new_bm()
	segs = seg(lod, 8, 5)
	for side in (-1.0, 1.0):
		front = [Vector((side * 0.078, -0.170, g + 0.330)), Vector((side * 0.080, -0.190, g + 0.170)),
				Vector((side * 0.082, -0.205, g + 0.040))]
		hind = [Vector((side * 0.082, 0.165, g + 0.280)), Vector((side * 0.088, 0.235, g + 0.140)),
				Vector((side * 0.086, 0.215, g + 0.040))]
		for pts, radii in ((front, [0.056, 0.042, 0.036]), (hind, [0.068, 0.040, 0.034])):
			geo.merge(bm, geo.tube(pts, radii, segs, row("fur"), sharp=SMOOTH))
			foot = pts[-1]
			paw = geo.ellipsoid(0.046, 0.060, 0.036, seg(lod, 9, 6), seg(lod, 4, 3), row("fur_dark"), sharp=SMOOTH,
					squash_bottom=0.3)
			geo.translate(paw, (foot.x, foot.y - 0.018, g + 0.012))
			geo.merge(bm, paw)
			if lod == 0:
				for k in (-1.0, 0.0, 1.0):
					claw = geo.lathe([(0.008, 0.0), (0.0, 0.020)], 4, row("bone"), sharp=40, phase=0.0,
							cap_start=row("bone"))
					geo.merge(bm, claw, geo.frame((foot.x + k * 0.020, foot.y - 0.070, g + 0.010),
							(0.0, -1.0, -0.3), (0.0, 0.0, 1.0)))
	return bm


def _ridge(b, lod, body):
	"""The dark mane ridge on down the neck and the back to the rump."""
	g = b.base_height
	tree = geo.bvh(body)
	steps = seg(lod, 11, 6)
	pts, radii = [], []
	for i in range(steps):
		y = -0.215 + 0.300 * i / (steps - 1)
		loc, nrm = geo.project(tree, (0.0, y, g + 1.0), (0.0, 0.0, -1.0))
		if loc is None:
			continue
		r = (0.042 if i % 2 == 0 else 0.026) if lod == 0 else 0.034
		r *= 1.0 - 0.45 * i / (steps - 1)
		pts.append(loc + nrm * (r * 0.4))
		radii.append(r)
	radii[0] = radii[-1] = 0.010
	return geo.tube(pts, radii, seg(lod, 6, 4), row("fur_dark"), sharp=SMOOTH, up=(1.0, 0.0, 0.0), flatten=0.42,
			cap_start=row("fur_dark"), cap_end=row("fur_dark"))


def _spots(b, lod, body):
	g = b.base_height
	tree = geo.bvh(body)
	bm = geo.new_bm()
	for x, y, z, r in ((-1.0, -0.140, 0.10, 0.030), (-1.0, -0.040, 0.45, 0.026), (-1.0, 0.040, -0.05, 0.030),
			(-1.0, 0.130, 0.35, 0.026), (-1.0, 0.190, -0.10, 0.022), (-0.5, -0.080, 1.0, 0.024),
			(1.0, -0.120, 0.30, 0.028), (1.0, -0.020, -0.08, 0.030), (1.0, 0.070, 0.42, 0.027),
			(1.0, 0.160, 0.05, 0.024), (0.5, 0.020, 1.0, 0.024), (0.4, 0.190, 1.0, 0.020)):
		z_at = next(sz for sy, sz, _r in SPINE if sy >= y)
		geo.merge(bm, gnoll._spots(tree, (0.0, y, g + z_at), [((x, 0.0, z), r)], lod))
	return bm


def _tail(b, lod):
	g = b.base_height
	pts = [(0.0, 0.250, g + 0.300), (0.0, 0.320, g + 0.300), (0.0, 0.372, g + 0.250), (0.0, 0.392, g + 0.190),
			(0.0, 0.390, g + 0.150)]
	return geo.tube(pts, [0.026, 0.044, 0.050, 0.036, 0.0], seg(lod, 7, 5), sharp=SMOOTH,
			ring_swatches=[row("fur"), row("fur"), row("fur_dark"), row("fur_dark")])


def _collar(b, lod):
	"""A hide collar in the team's colour round the base of the neck, a bone
	tooth hung at the throat."""
	g = b.base_height
	at = Vector((0.0, -0.180, g + 0.385))
	axis = Vector((0.0, -0.90, 0.44))
	collar = geo.lathe([(0.118, -0.036), (0.130, -0.024), (0.132, 0.0), (0.130, 0.024), (0.118, 0.036)],
			seg(lod, 14, 9), sharp=50, ring_swatches=[row("team_cloth_dark"), row("team_cloth"), row("team_cloth"),
			row("team_cloth_dark")])
	bm = geo.new_bm()
	geo.merge(bm, collar, geo.frame(at, axis, (0.0, 0.0, 1.0)))
	# A girth band behind the front legs, the harness's other half.
	girth = geo.lathe([(0.136, -0.024), (0.146, -0.016), (0.148, 0.0), (0.146, 0.016), (0.136, 0.024)],
			seg(lod, 14, 9), sharp=50, ring_swatches=[row("team_cloth_dark"), row("team_cloth"), row("team_cloth"),
			row("team_cloth_dark")])
	geo.merge(bm, girth, geo.frame(Vector((0.0, -0.060, g + 0.362)), (0.0, -1.0, 0.18), (0.0, 0.0, 1.0)))
	if lod == 0:
		throat = at + Vector((0.0, -0.090, -0.100))
		tooth = geo.lathe([(0.011, 0.0), (0.008, 0.018), (0.0, 0.042)], 5, row("bone"), sharp=40, phase=0.0,
				cap_start=row("bone"))
		geo.merge(bm, tooth, geo.frame(throat, (0.0, -0.3, -1.0), (0.0, -1.0, 0.0)))
		for side in (-1.0, 1.0):
			bead = geo.ellipsoid(0.011, 0.011, 0.010, 5, 3, row("ochre"), sharp=SMOOTH)
			geo.translate(bead, throat + Vector((side * 0.024, 0.010, 0.008)))
			geo.merge(bm, bead)
	return bm


def hyena(b, lod):
	body = _body(b, lod)
	bm = geo.new_bm()
	for piece in (body, _ridge(b, lod, body), _spots(b, lod, body), _legs(b, lod), _tail(b, lod), _collar(b, lod),
			_head(b, lod)):
		geo.merge(bm, piece)
	return bm
