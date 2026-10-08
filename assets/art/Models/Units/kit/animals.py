"""Wild animals (scenes/units/animals): neutral, huntable four-legged
wildlife, drawn as chibi diorama toys. No gear and no team colour: natural
coats only, the shared big dark eyes with a glint, big heads and simple
silhouettes that stand apart from the Beastmen (who stand upright and carry
weapons):

  bear: a heavy dark-chocolate barrel on short thick legs, a shoulder hump,
    a huge round head held low and forward, round ears, a tan muzzle.
  boar: small, wedge-shaped and front-heavy: high bristled shoulders, a
    low rump, a long snout with a pink disc and white tusks curling up, a
    black crest down the spine, thin legs on black trotters.
  deer: a slender russet roe buck on long legs, its neck and big head held
    high, wide level ears, short three-tined antlers, a cream throat, rump
    and muzzle, a dark nose.

Built in a figure's standing space (the ground at Body.base_height, facing
-Y), like horse.py and hyena.py, so units._assemble drops each onto the
ground. Colours are the animals palette (palette.ANIMALS).
"""
import math

from mathutils import Matrix, Vector

import geo
from geo import FLAT, SMOOTH
from palette import row
from parts import seg


def _eyes(lod, skull, H, x, dz, rx=0.026, ry=0.034, cheek=None):
	"""The shared big dark eyes and glints, on the front of the skull."""
	tree = geo.bvh(skull)
	bm = geo.new_bm()
	for side in (-1.0, 1.0):
		loc, nrm = geo.project(tree, (H.x + side * x, H.y - 1.0, H.z + dz), (0.0, 1.0, 0.0))
		if loc is None:
			continue
		geo.merge(bm, geo.disc(rx, ry, seg(lod, 10, 6), row("eye"), dome=0.005),
				geo.frame(loc + nrm * 0.001, nrm, (0.0, 0.0, 1.0)))
		if lod == 0:
			geo.merge(bm, geo.disc(rx * 0.32, rx * 0.32, 5, row("glint"), dome=0.002, depth=0.002, simple=True),
					geo.frame(loc + nrm * 0.007 + Vector((side * rx * 0.30, 0.0, ry * 0.36)), nrm, (0.0, 0.0, 1.0)))
			if cheek is not None:
				loc, nrm = geo.project(tree, (H.x + side * (x + cheek), H.y - 1.0, H.z + dz - ry * 1.7), (0.0, 1.0, 0.0))
				if loc is not None:
					geo.merge(bm, geo.disc(0.020, 0.011, 7, row("blush"), dome=0.001, depth=0.002, simple=True),
							geo.frame(loc, nrm, (0.0, 0.0, 1.0)))
	return bm


def _body(spine, lod, swatch, up=(0.0, 0.0, 1.0), flatten=1.0, g=0.0):
	pts = [Vector((0.0, y, g + z)) for y, z, _r in spine]
	return geo.tube(pts, [r for _y, _z, r in spine], seg(lod, 12, 8), row(swatch), sharp=SMOOTH, up=up,
			flatten=flatten)


def _grow(bm, g, k):
	"""Scales the whole animal round the ground under its middle."""
	geo.transform(bm, Matrix.Translation((0.0, 0.0, g)) @ Matrix.Scale(k, 4) @ Matrix.Translation((0.0, 0.0, -g)))
	return bm


# --- bear --------------------------------------------------------------------

BEAR_SPINE = [(-0.330, 0.350, 0.020), (-0.290, 0.360, 0.150), (-0.170, 0.380, 0.190), (0.000, 0.365, 0.192),
		(0.160, 0.350, 0.180), (0.270, 0.340, 0.140), (0.320, 0.335, 0.0)]
BEAR_HEAD = Vector((0.0, -0.405, 0.470))
BEAR_SCALE = 1.12


def _bear_head(lod, g):
	H = BEAR_HEAD + Vector((0.0, 0.0, g))
	bm = geo.new_bm()
	skull = geo.ellipsoid(0.172, 0.150, 0.150, seg(lod, 14, 9), seg(lod, 7, 5), row("fur"), sharp=SMOOTH)
	geo.translate(skull, H)
	geo.merge(bm, skull)
	# Full cheeks, a little wider than the crown.
	for side in (-1.0, 1.0):
		cheek = geo.ellipsoid(0.080, 0.080, 0.072, seg(lod, 9, 6), 4, row("fur"), sharp=SMOOTH)
		geo.translate(cheek, H + Vector((side * 0.112, 0.010, -0.058)))
		geo.merge(bm, cheek)
	muzzle = geo.tube([H + Vector((0.0, -0.080, -0.048)), H + Vector((0.0, -0.170, -0.056)),
			H + Vector((0.0, -0.212, -0.062))], [0.082, 0.066, 0.040], seg(lod, 10, 7), row("fur_light"),
			sharp=SMOOTH, flatten=0.74, cap_end=row("fur_light"))
	geo.merge(bm, muzzle)
	nose = geo.ellipsoid(0.040, 0.026, 0.026, seg(lod, 8, 5), 3, row("nose"), sharp=SMOOTH)
	geo.translate(nose, H + Vector((0.0, -0.212, -0.030)))
	geo.merge(bm, nose)
	for side in (-1.0, 1.0):
		ear = geo.ellipsoid(0.056, 0.026, 0.052, seg(lod, 10, 7), seg(lod, 5, 4), row("fur"), sharp=SMOOTH)
		inner = geo.disc(0.032, 0.030, seg(lod, 8, 6), row("fur_dark"), dome=0.003, depth=0.004)
		geo.merge(ear, inner, geo.frame((0.0, -0.022, -0.004), (0.0, -1.0, 0.0), (0.0, 0.0, 1.0)))
		geo.rotate(ear, side * 30.0, 'Y')
		geo.translate(ear, H + Vector((side * 0.122, 0.020, 0.112)))
		geo.merge(bm, ear)
	geo.merge(bm, _eyes(lod, skull, H, 0.072, 0.034, rx=0.026, ry=0.033, cheek=0.040))
	if lod == 0:
		tree = geo.bvh(muzzle)
		pts, nrms = [], []
		for i in range(5):
			t = (i / 4.0) * 2.0 - 1.0
			loc, nrm = geo.project(tree, (t * 0.026, H.y - 1.0, H.z - 0.082 + 0.008 * t * t), (0.0, 1.0, 0.0))
			if loc is not None:
				pts.append(loc)
				nrms.append(nrm)
		if len(pts) > 1:
			geo.merge(bm, geo.ribbon(pts, nrms, 0.0, 0.0022, row("mouth"), sharp=SMOOTH, embed=0.002,
					widths=[0.004, 0.0068, 0.0076, 0.0068, 0.004][:len(pts)]))
	return bm


def bear(b, lod):
	g = b.base_height
	bm = _body(BEAR_SPINE, lod, "fur", g=g)
	# The shoulder hump and a shaggy chest.
	hump = geo.ellipsoid(0.150, 0.150, 0.110, seg(lod, 10, 7), seg(lod, 5, 4), row("fur"), sharp=SMOOTH)
	geo.translate(hump, (0.0, -0.130, g + 0.500))
	geo.merge(bm, hump)
	chest = geo.ellipsoid(0.150, 0.110, 0.150, seg(lod, 10, 7), seg(lod, 5, 4), row("fur"), sharp=SMOOTH)
	geo.translate(chest, (0.0, -0.280, g + 0.330))
	geo.merge(bm, chest)
	# Short, thick pillar legs, dark paws with bone claws.
	segs = seg(lod, 9, 6)
	for side in (-1.0, 1.0):
		x = side * 0.112
		for y, top in ((-0.210, 0.330), (0.205, 0.320)):
			leg = geo.tube([Vector((x, y, g + top)), Vector((x * 1.04, y - 0.006, g + 0.150)),
					Vector((x * 1.05, y - 0.012, g + 0.050))], [0.088, 0.072, 0.066], segs, row("fur"), sharp=SMOOTH)
			geo.merge(bm, leg)
			paw = geo.ellipsoid(0.070, 0.084, 0.044, seg(lod, 9, 6), seg(lod, 4, 3), row("fur_dark"), sharp=SMOOTH,
					squash_bottom=0.3)
			geo.translate(paw, (x * 1.05, y - 0.030, g + 0.020))
			geo.merge(bm, paw)
			if lod == 0:
				for k in (-1.0, 0.0, 1.0):
					claw = geo.lathe([(0.010, 0.0), (0.0, 0.026)], 4, row("bone"), sharp=40, phase=0.0,
							cap_start=row("bone"))
					geo.merge(bm, claw, geo.frame((x * 1.05 + k * 0.028, y - 0.110, g + 0.014),
							(0.0, -1.0, -0.3), (0.0, 0.0, 1.0)))
	tail = geo.ellipsoid(0.044, 0.040, 0.040, seg(lod, 7, 5), 3, row("fur_dark"), sharp=SMOOTH)
	geo.translate(tail, (0.0, 0.330, g + 0.400))
	geo.merge(bm, tail)
	geo.merge(bm, _bear_head(lod, g))
	return _grow(bm, g, BEAR_SCALE)


# --- boar --------------------------------------------------------------------

BOAR_SPINE = [(-0.230, 0.300, 0.020), (-0.205, 0.312, 0.118), (-0.120, 0.322, 0.142), (0.000, 0.296, 0.130),
		(0.115, 0.268, 0.114), (0.195, 0.250, 0.090), (0.235, 0.246, 0.0)]
BOAR_HEAD = Vector((0.0, -0.300, 0.300))
## The crest's tufts, crown to mid-back: (y, z of the surface under them).
BOAR_CREST = [(-0.320, 0.424), (-0.270, 0.438), (-0.215, 0.452), (-0.160, 0.462), (-0.100, 0.462),
		(-0.040, 0.448), (0.020, 0.428), (0.080, 0.404), (0.130, 0.382)]


def _boar_head(lod, g):
	H = BOAR_HEAD + Vector((0.0, 0.0, g))
	bm = geo.new_bm()
	skull = geo.ellipsoid(0.124, 0.140, 0.128, seg(lod, 12, 8), seg(lod, 6, 4), row("coat"), sharp=SMOOTH)
	geo.translate(skull, H)
	geo.merge(bm, skull)
	# A long snout sloping down to a pink disc, two dark nostrils.
	tip = H + Vector((0.0, -0.236, -0.076))
	snout = geo.tube([H + Vector((0.0, -0.070, -0.030)), H + Vector((0.0, -0.170, -0.060)), tip],
			[0.074, 0.058, 0.050], seg(lod, 10, 7), row("coat"), sharp=SMOOTH, flatten=0.86)
	geo.merge(bm, snout)
	disc = geo.lathe([(0.050, 0.0), (0.050, 0.014), (0.0, 0.018)], seg(lod, 10, 7), row("coat_grey"), sharp=40,
			phase=0.0, sy=0.86)
	axis = (tip - (H + Vector((0.0, -0.170, -0.060)))).normalized()
	geo.merge(bm, disc, geo.frame(tip, axis, (0.0, 0.0, 1.0)))
	if lod == 0:
		for side in (-1.0, 1.0):
			hole = geo.disc(0.010, 0.013, 6, row("nose"), dome=0.001, depth=0.002, simple=True)
			geo.merge(bm, hole, geo.frame(tip + axis * 0.018 + Vector((side * 0.018, 0.0, 0.0)), axis,
					(0.0, 0.0, 1.0)))
	# White tusks curling up and out from the sides of the snout.
	for side in (-1.0, 1.0):
		root = H + Vector((side * 0.052, -0.168, -0.082))
		pts = [root, root + Vector((side * 0.026, -0.016, 0.034)), root + Vector((side * 0.032, -0.004, 0.072))]
		geo.merge(bm, geo.tube(pts, [0.017, 0.012, 0.0], seg(lod, 6, 4), row("bone"), sharp=SMOOTH,
				cap_start=row("bone")))
	# Small pointed ears, tipped out and forward.
	for side in (-1.0, 1.0):
		ear = geo.lathe([(0.044, 0.0), (0.034, 0.040), (0.0, 0.092)], seg(lod, 7, 5), row("coat"), sharp=40,
				phase=0.0, sy=0.40)
		inner = geo.lathe([(0.028, 0.004), (0.020, 0.034), (0.0, 0.070)], 5, row("coat_grey"), sharp=40,
				phase=0.0, sy=0.28)
		geo.translate(inner, (0.0, -0.010, 0.004))
		geo.merge(ear, inner)
		geo.rotate(ear, side * 40.0, 'Y')
		geo.rotate(ear, -18.0, 'X')
		geo.translate(ear, H + Vector((side * 0.074, 0.030, 0.088)))
		geo.merge(bm, ear)
	geo.merge(bm, _eyes(lod, skull, H, 0.060, 0.022, rx=0.022, ry=0.029))
	return bm


def boar(b, lod):
	g = b.base_height
	bm = _body(BOAR_SPINE, lod, "coat", up=(1.0, 0.0, 0.0), flatten=0.88, g=g)
	# Thin legs on black trotters.
	segs = seg(lod, 7, 5)
	for side in (-1.0, 1.0):
		x = side * 0.074
		for y, top, r in ((-0.150, 0.270, 0.050), (0.150, 0.230, 0.056)):
			leg = geo.tube([Vector((x, y, g + top)), Vector((x * 1.04, y, g + 0.110)), Vector((x * 1.04, y - 0.006,
					g + 0.040))], [r, 0.032, 0.028], segs, row("coat"), sharp=SMOOTH)
			geo.merge(bm, leg)
			trotter = geo.lathe([(0.0, 0.0), (0.034, 0.0), (0.032, 0.026), (0.026, 0.046)], seg(lod, 7, 5),
					row("coat_dark"), sharp=40, phase=0.0, cap_start=row("coat_dark"))
			geo.translate(trotter, (x * 1.04, y - 0.006, g))
			geo.merge(bm, trotter)
	# The black bristle crest from the crown down the spine, in tufts.
	crest = BOAR_CREST if lod == 0 else BOAR_CREST[::2]
	for i, (y, z) in enumerate(crest):
		t = i / (len(crest) - 1)
		r = (0.046 if i % 2 == 0 else 0.036) * (1.0 - 0.45 * t)
		tuft = geo.lathe([(r, 0.0), (r * 0.6, r * 0.9), (0.0, r * 2.0)], 5, row("coat_dark"), sharp=40, phase=0.0,
				sx=0.55)
		geo.rotate(tuft, 20.0 + 20.0 * t, 'X')
		geo.translate(tuft, (0.0, y, g + z - r * 0.6))
		geo.merge(bm, tuft)
	# A thin tail with a dark tuft.
	pts = [Vector((0.0, 0.230, g + 0.290)), Vector((0.0, 0.268, g + 0.280)), Vector((0.0, 0.284, g + 0.236))]
	geo.merge(bm, geo.tube(pts, [0.016, 0.012, 0.008], 5, row("coat"), sharp=SMOOTH))
	end = geo.ellipsoid(0.018, 0.018, 0.030, 6, 3, row("coat_dark"), sharp=SMOOTH)
	geo.translate(end, (0.0, 0.286, g + 0.214))
	geo.merge(bm, end)
	geo.merge(bm, _boar_head(lod, g))
	return bm


# --- deer --------------------------------------------------------------------

DEER_SPINE = [(-0.230, 0.420, 0.020), (-0.200, 0.428, 0.100), (-0.100, 0.432, 0.116), (0.040, 0.424, 0.110),
		(0.160, 0.426, 0.102), (0.220, 0.432, 0.072), (0.248, 0.440, 0.0)]
DEER_HEAD = Vector((0.0, -0.335, 0.790))


def _deer_head(lod, g):
	H = DEER_HEAD + Vector((0.0, 0.0, g))
	bm = geo.new_bm()
	skull = geo.ellipsoid(0.112, 0.110, 0.104, seg(lod, 12, 8), seg(lod, 6, 4), row("fur_red"), sharp=SMOOTH)
	geo.translate(skull, H)
	geo.merge(bm, skull)
	snout = geo.tube([H + Vector((0.0, -0.050, -0.034)), H + Vector((0.0, -0.130, -0.060)),
			H + Vector((0.0, -0.170, -0.070))], [0.060, 0.042, 0.028], seg(lod, 9, 6), sharp=SMOOTH,
			ring_swatches=[row("fur_red"), row("cream")], flatten=0.85, cap_end=row("cream"))
	geo.merge(bm, snout)
	nose = geo.ellipsoid(0.024, 0.018, 0.018, seg(lod, 7, 5), 3, row("nose"), sharp=SMOOTH)
	geo.translate(nose, H + Vector((0.0, -0.180, -0.058)))
	geo.merge(bm, nose)
	chin = geo.ellipsoid(0.036, 0.060, 0.022, seg(lod, 8, 5), 3, row("cream"), sharp=SMOOTH)
	geo.translate(chin, H + Vector((0.0, -0.104, -0.088)))
	geo.merge(bm, chin)
	# Big leaf ears held out level, cream inside, dark at the rim.
	for side in (-1.0, 1.0):
		ear = geo.lathe([(0.050, 0.0), (0.054, 0.050), (0.030, 0.110), (0.0, 0.140)], seg(lod, 8, 5), sharp=SMOOTH,
				phase=0.0, sy=0.36, ring_swatches=[row("fur_red"), row("fur_red"), row("hair_dark")])
		inner = geo.lathe([(0.034, 0.010), (0.038, 0.050), (0.0, 0.112)], 6, row("cream"), sharp=SMOOTH,
				phase=0.0, sy=0.24)
		geo.translate(inner, (0.0, -0.012, 0.0))
		geo.merge(ear, inner)
		geo.rotate(ear, side * 72.0, 'Y')
		geo.rotate(ear, side * 12.0, 'Z')
		geo.translate(ear, H + Vector((side * 0.080, 0.020, 0.048)))
		geo.merge(bm, ear)
	# Short antlers: a beam up from each brow, three short tines.
	segs = seg(lod, 6, 4)
	for side in (-1.0, 1.0):
		base = H + Vector((side * 0.044, 0.012, 0.086))
		beam = [base, base + Vector((side * 0.020, 0.006, 0.070)), base + Vector((side * 0.030, 0.026, 0.150))]
		geo.merge(bm, geo.tube(beam, [0.020, 0.016, 0.0], segs, row("wood_light"), sharp=SMOOTH,
				cap_start=row("wood_light")))
		burr = geo.ellipsoid(0.024, 0.024, 0.012, 6, 3, row("hair_dark"), sharp=SMOOTH)
		geo.translate(burr, base + Vector((0.0, 0.0, 0.004)))
		geo.merge(bm, burr)
		for at, d in ((0.45, (side * 0.004, -0.050, 0.030)), (0.75, (side * 0.034, -0.010, 0.036))):
			p = beam[1].lerp(beam[0], 1.0 - at) if at < 0.5 else beam[1].lerp(beam[2], (at - 0.5) * 2.0)
			geo.merge(bm, geo.tube([p, p + Vector(d)], [0.012, 0.0], 5, row("wood_light"), sharp=SMOOTH))
	geo.merge(bm, _eyes(lod, skull, H, 0.050, 0.016, rx=0.022, ry=0.030))
	return bm


def deer(b, lod):
	g = b.base_height
	bm = _body(DEER_SPINE, lod, "fur_red", g=g)
	# Long slender legs, the hind bent at the hock, dark hooves.
	segs = seg(lod, 7, 5)
	for side in (-1.0, 1.0):
		x = side * 0.064
		front = [Vector((x, -0.170, g + 0.400)), Vector((x * 1.04, -0.186, g + 0.220)),
				Vector((x * 1.06, -0.196, g + 0.040))]
		hind = [Vector((x, 0.170, g + 0.410)), Vector((x * 1.06, 0.230, g + 0.220)),
				Vector((x * 1.06, 0.200, g + 0.040))]
		for pts, radii in ((front, [0.048, 0.028, 0.022]), (hind, [0.064, 0.030, 0.022])):
			geo.merge(bm, geo.tube(pts, radii, segs, row("fur_red"), sharp=SMOOTH))
			foot = pts[-1]
			hoof = geo.lathe([(0.0, 0.0), (0.030, 0.0), (0.027, 0.024), (0.021, 0.042)], seg(lod, 7, 5),
					row("hoof"), sharp=40, phase=0.0, cap_start=row("hoof"))
			geo.translate(hoof, (foot.x, foot.y, g))
			geo.merge(bm, hoof)
	# The neck held high, a cream throat patch down its front.
	neck = geo.tube([Vector((0.0, -0.170, g + 0.460)), Vector((0.0, -0.250, g + 0.600)),
			Vector((0.0, -0.315, g + 0.720))], [0.082, 0.062, 0.060], seg(lod, 9, 6), row("fur_red"), sharp=SMOOTH,
			flatten=0.86, up=(1.0, 0.0, 0.0))
	geo.merge(bm, neck)
	throat = geo.ellipsoid(0.046, 0.034, 0.070, seg(lod, 8, 5), 4, row("cream"), sharp=SMOOTH)
	geo.rotate(throat, -30.0, 'X')
	geo.translate(throat, (0.0, -0.318, g + 0.626))
	geo.merge(bm, throat)
	# A pale belly, a cream rump patch and a short tail, dark on top.
	belly = geo.ellipsoid(0.080, 0.170, 0.050, seg(lod, 9, 6), 4, row("cream"), sharp=SMOOTH)
	geo.translate(belly, (0.0, 0.0, g + 0.338))
	geo.merge(bm, belly)
	rump = geo.ellipsoid(0.080, 0.040, 0.076, seg(lod, 9, 6), 4, row("cream"), sharp=SMOOTH)
	geo.translate(rump, (0.0, 0.226, g + 0.430))
	geo.merge(bm, rump)
	tail = geo.ellipsoid(0.028, 0.022, 0.050, 6, 3, row("hair_dark"), sharp=SMOOTH)
	geo.rotate(tail, 24.0, 'X')
	geo.translate(tail, (0.0, 0.262, g + 0.468))
	geo.merge(bm, tail)
	geo.merge(bm, _deer_head(lod, g))
	return bm
