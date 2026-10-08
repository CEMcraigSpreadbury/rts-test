"""Beastmen parts: animal-headed chibis, each unit its own animal on a body
of its own (see the Body subclasses below). The first is the bear (the Beastman Warrior): a broad round head in brown fur,
round ears, a short tan muzzle with a big dark nose and the shared big dark
eyes; a shaggy furred body, steel bracers and one steel pauldron.

The beastmen palette paints the gnolls' rows (fur, fur_dark, fur_light,
nose, bone) in bear colours, so the gnoll legs, arms, belt and loincloth
are reused as they are. The team's colour is on the loincloth and on a
sash, scarf or strap where the camera sees it. The boar (Raider), the
stag (Druid), the panda (Panda Warrior) and the wolf (Wolf Pathfinder) have
their own Body subclasses and are repainted into their own coat rows
(BOAR, STAG, PANDA, WOLF).

The head pieces are built upright and tipped back by the recipe (see
units._beast_head), as the humans' are.
"""
import math

from mathutils import Vector

import geo
from geo import FLAT, SMOOTH
import gnoll
from palette import row
import parts
from parts import seg, _limb, _on_torso


## Species repaints: parts are built in the bear's fur rows and these swap
## them for another animal's coat (see palette.BEASTMEN).
BOAR = (("fur", "coat"), ("fur_dark", "coat_dark"), ("fur_light", "coat_grey"))
STAG = (("fur", "fur_red"), ("fur_dark", "hair_dark"), ("fur_light", "cream"))
PANDA = (("fur", "beard"), ("fur_dark", "beard_dark"), ("fur_light", "beard"))
WOLF = (("fur", "hood"), ("fur_dark", "hoof"), ("fur_light", "pebble"))


def species(bm, swaps):
	for src, dst in swaps:
		gnoll.recolour(bm, src, dst)
	return bm


# --- head -------------------------------------------------------------------

def head(b, lod):
	"""A broad, round head in brown fur, fuller in the cheeks than a
	human's."""
	bm = geo.box(1.0, 1.0, 1.0, row("fur"), SMOOTH)
	bm = geo.subdivided(bm, seg(lod, 2, 1))
	size = Vector((b.head_size.x * 1.08, b.head_size.y * 1.02, b.head_size.z * 0.95))
	geo.fit(bm, size, b.head_centre)
	c = b.head_centre
	half_h = size.z * 0.5
	for v in bm.verts:
		below = (c.z - v.co.z) / half_h
		if below > 0.0:
			v.co.x = c.x + (v.co.x - c.x) * (1.0 - 0.06 * below * below)
	return geo.paint(bm, row("fur"), SMOOTH)


def _muzzle_z(b):
	return b.head_centre.z - 0.070


def muzzle(b, lod):
	"""A short, broad tan bear muzzle, a big dark nose on top of its tip and
	a small mouth under it."""
	c, mz = b.head_centre, _muzzle_z(b)
	pts = [(0.0, c.y - 0.07, mz + 0.010), (0.0, c.y - 0.15, mz + 0.004), (0.0, c.y - 0.196, mz - 0.002),
			(0.0, c.y - 0.212, mz - 0.006)]
	bm = geo.tube(pts, [0.082, 0.074, 0.058, 0.036], seg(lod, 10, 6), row("fur_light"), sharp=SMOOTH,
			cap_end=row("fur_light"), flatten=0.70)
	nose = geo.ellipsoid(0.038, 0.024, 0.024, seg(lod, 8, 5), 3, row("nose"), sharp=SMOOTH)
	geo.translate(nose, (0.0, c.y - 0.204, mz + 0.026))
	geo.merge(bm, nose)
	if lod == 0:
		tree = geo.bvh(bm)
		pts, nrms = [], []
		for i in range(5):
			t = (i / 4.0) * 2.0 - 1.0
			loc, nrm = geo.project(tree, (t * 0.026, c.y - 0.5, mz - 0.018 + 0.008 * t * t), (0.0, 1.0, 0.0))
			if loc is not None:
				pts.append(loc)
				nrms.append(nrm)
		if len(pts) > 1:
			geo.merge(bm, geo.ribbon(pts, nrms, 0.0, 0.0022, row("mouth"), sharp=SMOOTH, embed=0.002,
					widths=[0.004, 0.0068, 0.0076, 0.0068, 0.004][:len(pts)]))
	return bm


def face(b, lod, head_bm, eye_x=0.076, eye_dz=0.016, blush_x=0.126):
	"""The humans' big dark eyes and glints, set wide over the muzzle, and a
	touch of blush."""
	tree = geo.bvh(head_bm)
	bm = geo.new_bm()

	def place(x, z, part, lift=0.0):
		loc, nrm = geo.project(tree, (x, -1.0, z), (0.0, 1.0, 0.0))
		if loc is None:
			return
		geo.merge(bm, part, geo.frame(loc + nrm * lift, nrm, (0.0, 0.0, 1.0)))

	eye_z = b.head_centre.z + eye_dz
	for side in (-1.0, 1.0):
		place(side * eye_x, eye_z, geo.disc(0.021, 0.029, seg(lod, 10, 6), row("eye"), dome=0.004))
		if lod == 0:
			place(side * eye_x + 0.008, eye_z + 0.011, geo.disc(0.0068, 0.0068, 5, row("glint"), dome=0.0015,
					depth=0.0015, simple=True), lift=0.0045)
			place(side * blush_x, eye_z - 0.050, geo.disc(0.016, 0.009, 7, row("blush"), dome=0.001, depth=0.002,
					simple=True))
	return bm


def ears(b, lod):
	"""Round bear ears high on the head, dark inside."""
	bm = geo.new_bm()
	c = b.head_centre
	for side in (-1.0, 1.0):
		ear = geo.ellipsoid(0.054, 0.024, 0.050, seg(lod, 10, 7), seg(lod, 5, 4), row("fur"), sharp=SMOOTH)
		inner = geo.disc(0.032, 0.030, seg(lod, 8, 6), row("fur_dark"), dome=0.003, depth=0.004)
		geo.merge(ear, inner, geo.frame((0.0, -0.020, -0.004), (0.0, -1.0, 0.0), (0.0, 0.0, 1.0)))
		geo.rotate(ear, side * 34.0, 'Y')
		geo.rotate(ear, side * 10.0, 'Z')
		geo.translate(ear, (side * 0.132, c.y + 0.012, c.z + 0.118))
		geo.merge(bm, ear)
	return bm


# --- body -------------------------------------------------------------------

def torso(b, lod):
	"""A barrel of brown fur flaring to a shaggy dark hem."""
	prof = b.torso_profile()
	prof = [(r * 1.04, z) for r, z in prof]
	bands = [row("fur_dark")] * 2 + [row("fur")] * (len(prof) - 3)
	if lod > 0:
		keep = (0, 1, 2, 4, 6, 8, 9, 10)
		prof = [prof[i] for i in keep]
		bands = [row("fur_dark")] * 2 + [row("fur")] * 5
	bm = geo.lathe(prof, seg(lod, 12, 8), sharp=SMOOTH, sy=b.torso_depth, ring_swatches=bands,
			cap_start=row("fur_dark"))
	if lod == 0:
		ring = sorted((v for v in bm.verts if abs(v.co.z - b.hem_z) < 1e-5), key=lambda v: math.atan2(v.co.y, v.co.x))
		for i, v in enumerate(ring):
			if i % 2:
				v.co.z -= 0.024
	return bm


def bandolier(b, lod, torso_bm):
	"""A broad dark leather strap from the left shoulder to the right hip,
	front and back, a steel buckle and studs on the chest."""
	bm = geo.new_bm()
	tree = geo.bvh(torso_bm)
	steps = seg(lod, 7, 4)
	for start, end in (((-0.85, b.shoulder_z + 0.005), (-2.45, b.waist_z + 0.01)),
			((0.85, b.shoulder_z + 0.005), (2.45, b.waist_z + 0.01))):
		pts, nrms = [], []
		for i in range(steps):
			t = i / (steps - 1)
			p, n = _on_torso(b, tree, start[0] + (end[0] - start[0]) * t, start[1] + (end[1] - start[1]) * t)
			pts.append(p)
			nrms.append(n)
		geo.merge(bm, geo.ribbon(pts, nrms, 0.040, 0.008, row("leather_dark"), sharp=40, embed=0.003))
	p, n = _on_torso(b, tree, -1.45, b.shoulder_z - 0.060)
	buckle = geo.box(0.044, 0.014, 0.040, row("steel"), 40)
	geo.merge(bm, buckle, geo.frame(p + n * 0.010, n, (0.0, 0.0, 1.0)))
	if lod == 0:
		for theta, z in ((-1.05, b.shoulder_z - 0.012), (-1.95, b.waist_z + 0.075)):
			p, n = _on_torso(b, tree, theta, z)
			stud = geo.ellipsoid(0.010, 0.010, 0.007, 5, 2, row("steel"), sharp=40)
			geo.merge(bm, stud, geo.frame(p + n * 0.009, n, (0.0, 0.0, 1.0)))
	return bm


def pauldron(b, lod):
	"""One big layered steel pauldron on the left shoulder, a leather strap
	under it and a steel spike on top."""
	side = 1.0
	shoulder = b.l_shoulder
	axis = Vector((side * 0.62, 0.0, 1.0)).normalized()
	segs = seg(lod, 9, 6)
	piece = geo.lathe([(0.102, -0.004), (0.098, 0.026), (0.070, 0.056), (0.0, 0.068)], segs, row("steel"),
			sharp=50, sy=0.96, phase=0.0)
	lame = geo.lathe([(0.088, -0.024), (0.110, -0.036), (0.114, -0.014), (0.096, 0.004)], segs, row("trim"),
			sharp=40, sy=0.96, phase=0.0)
	geo.merge(piece, lame)
	if lod == 0:
		lame2 = geo.lathe([(0.098, -0.046), (0.116, -0.060), (0.118, -0.040), (0.104, -0.026)], segs, row("steel"),
				sharp=40, sy=0.96, phase=0.0)
		geo.merge(piece, lame2)
	spike = geo.lathe([(0.022, 0.0), (0.0, 0.050)], seg(lod, 6, 4), row("steel"), sharp=40, phase=0.0,
			cap_start=row("steel"))
	geo.translate(spike, (0.0, 0.0, 0.060))
	geo.merge(piece, spike)
	bm = geo.new_bm()
	geo.merge(bm, piece, geo.frame(shoulder + Vector((side * 0.016, 0.0, 0.034)), axis, (0.0, -1.0, 0.0)))
	return bm


def shoulder(b, lod):
	"""A round furred cap over the bare (axe) shoulder."""
	cap = geo.ellipsoid(0.060, 0.058, 0.052, seg(lod, 8, 6), seg(lod, 4, 3), row("fur"), sharp=SMOOTH)
	geo.translate(cap, b.r_shoulder + Vector((-0.006, 0.0, 0.006)))
	return cap


def stub_tail(b, lod):
	"""A round stub of a bear's tail behind, over the loincloth."""
	tail = geo.ellipsoid(0.034, 0.030, 0.030, seg(lod, 7, 5), seg(lod, 4, 3), row("fur_dark"), sharp=SMOOTH)
	geo.translate(tail, (0.0, b.torso_radius(b.waist_z - 0.03) * b.torso_depth + 0.030, b.waist_z - 0.030))
	return tail


# --- arms in hand -----------------------------------------------------------

def bear_axe(b, lod):
	"""A huge bearded war axe raised in the right fist: one broad crescent
	of bright steel, a back spike, a dark haft wrapped in leather at the
	grip and lashed under the head, a steel butt cap."""
	segs = seg(lod, 6, 4)
	bm = geo.lathe([(0.0, -0.160), (0.026, -0.156), (0.026, 0.600), (0.0, 0.612)], segs, row("wood"), sharp=40,
			phase=0.0)
	geo.merge(bm, geo.lathe([(0.031, -0.055), (0.031, 0.060)], segs, row("leather_dark"), sharp=40, phase=0.0))
	geo.merge(bm, geo.lathe([(0.0, -0.186), (0.034, -0.176), (0.034, -0.150), (0.026, -0.140)], segs, row("steel"),
			sharp=40, phase=0.0))
	geo.merge(bm, geo.lathe([(0.032, 0.360), (0.032, 0.396)], segs, row("leather_dark"), sharp=40, phase=0.0))
	# The bit: a narrow neck off the haft swelling to a tall crescent edge.
	edge = [(0.0, 0.420), (0.060, 0.430), (0.120, 0.360), (0.196, 0.330), (0.230, 0.440), (0.226, 0.560),
			(0.196, 0.660), (0.120, 0.610), (0.060, 0.560), (0.0, 0.570)]
	if lod > 0:
		edge = [edge[i] for i in (0, 2, 3, 4, 5, 6, 7, 9)]
	geo.merge(bm, geo.plate(edge, 0.034, row("blade"), side=row("steel"), sharp=FLAT))
	spike = [(0.0, 0.452), (-0.090, 0.488), (-0.104, 0.495), (-0.090, 0.502), (0.0, 0.540)]
	geo.merge(bm, geo.plate(spike, 0.030, row("steel"), side=row("steel"), sharp=FLAT))
	cap = geo.box(0.050, 0.054, 0.160, row("steel"), 40)
	geo.translate(cap, (0.0, 0.0, 0.495))
	geo.merge(bm, cap)
	geo.transform(bm, geo.frame(b.r_fist, b.sword_axis, parts.edge_down(b.sword_axis)))
	return bm


def sash(b, lod, z0=None, z1=None, knot_side=1.0, grow=1.0):
	"""A broad sash of the team's colour wound round the belly, its knot and
	two short tails at one hip: team colour where the camera sees it."""
	z0 = b.waist_z + 0.012 if z0 is None else z0
	z1 = b.waist_z + 0.070 if z1 is None else z1
	prof = []
	for k in range(4):
		z = z0 + (z1 - z0) * k / 3.0
		prof.append((b.torso_radius(z) * grow + (0.012 if k in (1, 2) else 0.004), z))
	bm = geo.lathe(prof, seg(lod, 14, 8), row("team_cloth"), sharp=SMOOTH, sy=b.torso_depth)
	a = math.radians(-90.0 + knot_side * 58.0)
	zm = (z0 + z1) * 0.5
	r = b.torso_radius(zm) * grow + 0.012
	at = Vector((math.cos(a) * r, math.sin(a) * r * b.torso_depth, zm))
	out = Vector((math.cos(a), math.sin(a), 0.0))
	knot = geo.ellipsoid(0.026, 0.020, 0.024, seg(lod, 7, 5), seg(lod, 4, 3), row("team_cloth"), sharp=SMOOTH)
	geo.translate(knot, at + out * 0.006)
	geo.merge(bm, knot)
	for k, length in enumerate((0.120, 0.096)):
		tail = [(-0.020, 0.0), (0.020, 0.0), (0.024, -length), (0.0, -length + 0.016), (-0.024, -length)]
		flap = geo.plate(tail, 0.007, row("team_cloth"), row("team_cloth_dark"), row("team_cloth_dark"), sharp=SMOOTH)
		geo.rotate(flap, 10.0 - 20.0 * k, 'Y')
		geo.rotate(flap, -12.0, 'X')
		geo.merge(bm, flap, geo.orient(at + out * 0.016 + Vector((0.0, 0.0, -0.008)), out))
	return bm


def strap(b, lod, torso_bm, swatch="team_cloth", width=0.048, flip=False):
	"""A broad strap or sash over one shoulder (the left; flip: the right) to
	the other hip, front and back."""
	bm = geo.new_bm()
	tree = geo.bvh(torso_bm)
	steps = seg(lod, 7, 4)
	s = -1.0 if flip else 1.0
	runs = (((-math.pi / 2.0 + s * 0.72, b.shoulder_z + 0.005), (-math.pi / 2.0 - s * 0.88, b.waist_z + 0.01)),
			((math.pi / 2.0 - s * 0.72, b.shoulder_z + 0.005), (math.pi / 2.0 + s * 0.88, b.waist_z + 0.01)))
	for start, end in runs:
		pts, nrms = [], []
		for i in range(steps):
			t = i / (steps - 1)
			p, n = _on_torso(b, tree, start[0] + (end[0] - start[0]) * t, start[1] + (end[1] - start[1]) * t)
			pts.append(p)
			nrms.append(n)
		geo.merge(bm, geo.ribbon(pts, nrms, width, 0.008, row(swatch), sharp=SMOOTH, embed=0.003))
	return bm


def arms(b, lod, k=1.0, bracer="leather"):
	"""The gnolls' furred arms at `k` times their girth: hide or steel
	bracers, dark-furred fists."""
	bm = geo.new_bm()
	segs = seg(lod, 7, 5)
	for shoulder, elbow, wrist, fist in ((b.r_shoulder, b.r_elbow, b.r_wrist, b.r_fist),
			(b.l_shoulder, b.l_elbow, b.l_wrist, b.l_fist)):
		upper = (elbow - shoulder).length
		geo.merge(bm, _limb(shoulder, elbow, [(0.048 * k, -0.01), (0.054 * k, 0.006), (0.047 * k, upper),
				(0.034 * k, upper + 0.022), (0.0, upper + 0.030)], segs, row("fur")))
		lower = (wrist - elbow).length
		if lod == 0:
			prof = [(0.040 * k, -0.010), (0.045 * k, 0.004), (0.044 * k, lower * 0.45), (0.048 * k, lower * 0.5),
					(0.047 * k, lower - 0.010), (0.040 * k, lower + 0.002), (0.0, lower + 0.008)]
			bands = [row("fur"), row("fur"), row(bracer), row(bracer), row(bracer), row(bracer)]
		else:
			prof = [(0.044 * k, 0.0), (0.042 * k, lower), (0.0, lower + 0.006)]
			bands = [row(bracer), row(bracer)]
		geo.merge(bm, _limb(elbow, wrist, prof, segs, sharp=50, bands=bands))
		hand = geo.box(1.0, 1.0, 1.0, row("fur_dark"), SMOOTH)
		if lod == 0:
			hand = geo.subdivided(hand, 1)
		geo.fit(hand, (0.066 * k, 0.070 * k, 0.072 * k))
		geo.paint(hand, row("fur_dark"), SMOOTH)
		geo.merge(bm, hand, geo.frame(fist, wrist - elbow, (0.0, 0.0, 1.0)))
	return bm


def _crest_blade(root, d, height, radius, lod, swatch="fur_dark"):
	"""One bristle blade of a crest: a cone squeezed thin across X."""
	pts = [root, root + d * height * 0.55, root + d * height]
	return geo.tube(pts, [radius, radius * 0.70, 0.0], seg(lod, 6, 4), row(swatch), sharp=SMOOTH, flatten=0.42,
			up=(1.0, 0.0, 0.0))


# === boar (the Raider) ======================================================

class BoarBody(parts.Body):
	"""Squat, wide and hunched: short thick legs, a broad barrel leaning
	forward, the head carried low and out in front of the shoulders."""
	foot_x = 0.094
	hem_z = 0.150
	waist_z = 0.280
	shoulder_z = 0.420
	neck_z = 0.470
	torso_depth = 0.86
	head_centre = Vector((0.0, -0.072, 0.580))
	head_size = Vector((0.350, 0.300, 0.272))
	head_tilt_deg = 7.0
	neck_pivot = Vector((0.0, -0.045, 0.490))
	brow_z = 0.650
	## How far the chest leans forward per metre above the waist.
	hunch = 0.30
	r_shoulder = Vector((-0.190, -0.034, 0.402))
	l_shoulder = Vector((0.190, -0.034, 0.402))
	r_elbow = Vector((-0.252, -0.020, 0.318))
	r_wrist = Vector((-0.262, -0.104, 0.296))
	r_fist = Vector((-0.262, -0.134, 0.292))
	sword_axis = Vector((-0.24, -0.48, 1.0)).normalized()
	l_elbow = Vector((0.252, -0.020, 0.316))
	l_wrist = Vector((0.250, -0.100, 0.286))
	l_fist = Vector((0.248, -0.130, 0.280))

	def torso_profile(self):
		h, w, s, n = self.hem_z, self.waist_z, self.shoulder_z, self.neck_z
		return [
			(0.200, h), (0.212, h + 0.010), (0.214, h + 0.030), (0.204, h + 0.065),
			(0.192, w), (0.204, w + 0.050), (0.206, w + 0.092),
			(0.194, s - 0.012), (0.160, s + 0.020), (0.100, n), (0.0, n + 0.004),
		]


def _hunch(b, bm):
	for v in bm.verts:
		if v.co.z > b.waist_z:
			v.co.y -= b.hunch * (v.co.z - b.waist_z)
	return bm


def boar_torso(b, lod):
	"""A wide bristly barrel leaning forward over a ragged hide kilt."""
	prof = b.torso_profile()
	bands = [row("leather")] * 4 + [row("fur")] * (len(prof) - 5)
	if lod > 0:
		keep = (0, 1, 2, 4, 6, 8, 9, 10)
		prof = [prof[i] for i in keep]
		bands = [row("leather")] * 3 + [row("fur")] * 4
	bm = geo.lathe(prof, seg(lod, 14, 8), sharp=SMOOTH, sy=b.torso_depth, ring_swatches=bands,
			cap_start=row("fur_dark"))
	if lod == 0:
		ring = sorted((v for v in bm.verts if abs(v.co.z - b.hem_z) < 1e-5), key=lambda v: math.atan2(v.co.y, v.co.x))
		for i, v in enumerate(ring):
			if i % 2:
				v.co.z -= 0.024
	return _hunch(b, bm)


def boar_legs(b, lod):
	"""Short thick legs on dark cloven trotters."""
	bm = geo.new_bm()
	g = b.base_height
	for side in (-1.0, 1.0):
		leg = geo.lathe([(0.052, g + 0.030), (0.060, b.hem_z + 0.040)], seg(lod, 8, 5), row("fur"))
		geo.translate(leg, (side * b.foot_x, 0.0, 0.0))
		geo.merge(bm, leg)
		for toe in (-1.0, 1.0):
			hoof = geo.ellipsoid(0.031, 0.056, 0.040, seg(lod, 8, 5), seg(lod, 4, 3), row("fur_dark"), sharp=SMOOTH,
					squash_bottom=0.3)
			geo.translate(hoof, (side * b.foot_x + toe * 0.026, -0.024, g + 0.016))
			geo.merge(bm, hoof)
	return bm


def boar_head(b, lod):
	"""A broad head, deep in the jowls, tapering up to a low brow."""
	bm = geo.box(1.0, 1.0, 1.0, row("fur"), SMOOTH)
	bm = geo.subdivided(bm, seg(lod, 2, 1))
	geo.fit(bm, b.head_size, b.head_centre)
	c = b.head_centre
	half_h = b.head_size.z * 0.5
	for v in bm.verts:
		up = (v.co.z - c.z) / half_h
		if up > 0.0:
			v.co.x = c.x + (v.co.x - c.x) * (1.0 - 0.14 * up * up)
		else:
			v.co.x = c.x + (v.co.x - c.x) * (1.0 + 0.05 * up * up)
	return geo.paint(bm, row("fur"), SMOOTH)


def boar_snout(b, lod):
	"""A fat round snout out in front, its flat pink disc with two dark
	nostrils, curling bone tusks and a brass ring through it."""
	c = b.head_centre
	mz = c.z - 0.052
	tip = c.y - 0.252
	pts = [(0.0, c.y - 0.08, mz + 0.006), (0.0, c.y - 0.17, mz), (0.0, c.y - 0.226, mz - 0.004), (0.0, tip, mz - 0.006)]
	bm = geo.tube(pts, [0.082, 0.074, 0.068, 0.066], seg(lod, 12, 7), row("fur"), sharp=SMOOTH,
			cap_end=row("fur_light"), flatten=0.80)
	for side in (-1.0, 1.0):
		nostril = geo.disc(0.013, 0.018, seg(lod, 7, 5), row("nose"), dome=0.001, depth=0.003)
		geo.merge(bm, nostril, geo.frame((side * 0.024, tip - 0.001, mz - 0.004), (0.0, -1.0, 0.0), (0.0, 0.0, 1.0)))
		root = Vector((side * 0.058, c.y - 0.190, mz - 0.030))
		tusk = [root, root + Vector((side * 0.026, -0.012, 0.030)), root + Vector((side * 0.040, -0.006, 0.072)),
				root + Vector((side * 0.030, 0.010, 0.100))]
		geo.merge(bm, geo.tube(tusk, [0.019, 0.016, 0.010, 0.0], seg(lod, 7, 5), row("bone"), sharp=SMOOTH,
				cap_start=row("bone")))
	if lod == 0:
		ring = geo.lathe([(0.017, -0.006), (0.021, 0.0), (0.017, 0.006)], 10, row("brass"), sharp=SMOOTH)
		geo.merge(bm, ring, geo.frame(Vector((0.0, tip - 0.002, mz - 0.060)), (0.0, -1.0, 0.0), (0.0, 0.0, 1.0)))
	return bm


def boar_ears(b, lod):
	"""Pointed ears flopping out and forward, dark inside."""
	bm = geo.new_bm()
	c = b.head_centre
	outline = [(-0.046, 0.0), (0.046, 0.0), (0.030, 0.050), (0.0, 0.098), (-0.030, 0.050)]
	for side in (-1.0, 1.0):
		ear = geo.plate(outline, 0.016, row("fur_dark"), row("fur"), row("fur"), sharp=SMOOTH, bend=3.0)
		geo.rotate(ear, 28.0, 'X')
		geo.rotate(ear, side * 64.0, 'Y')
		geo.translate(ear, (side * 0.130, c.y + 0.010, c.z + 0.078))
		geo.merge(bm, ear)
	return bm


def boar_head_crest(b, lod):
	"""Black bristles standing up along the top of the head."""
	bm = geo.new_bm()
	c, half = b.head_centre, b.head_size * 0.5
	count = seg(lod, 5, 3)
	for i in range(count):
		t = i / (count - 1)
		y = c.y - half.y * 0.55 + t * half.y * 1.45
		root = Vector((0.0, y, c.z + half.z - 0.030 - 0.020 * (2.0 * t - 1.0) ** 2))
		d = Vector((0.0, 0.25 + 0.55 * t, 1.0)).normalized()
		geo.merge(bm, _crest_blade(root, d, 0.060 + 0.030 * t, 0.030, lod))
	return bm


def boar_back_crest(b, lod, torso_bm):
	"""The bristle ridge down the spine, tallest at the hump of the
	shoulders."""
	bm = geo.new_bm()
	tree = geo.bvh(torso_bm)
	count = seg(lod, 5, 3)
	for i in range(count):
		t = i / (count - 1)
		z = b.neck_z - 0.020 - t * (b.neck_z - b.waist_z - 0.040)
		p, n = _on_torso(b, tree, math.pi / 2.0, z)
		d = (n + Vector((0.0, 0.0, 0.9 - 0.7 * t))).normalized()
		geo.merge(bm, _crest_blade(p - n * 0.010, d, 0.100 - 0.050 * t, 0.034 - 0.010 * t, lod))
	return bm


def neckerchief(b, lod):
	"""A scarf of the team's colour knotted at the nape, its two tails
	streaming back over the hump."""
	bm = geo.new_bm()
	n = b.neck_z
	lean = b.hunch * (n - b.waist_z)
	zs = (n - 0.040, n - 0.026, n - 0.010)
	prof = [(b.torso_radius(z) + 0.014, z) for z in zs] + [(0.084, n + 0.004)]
	ring = geo.lathe(prof, seg(lod, 12, 8), row("team_cloth"), sharp=SMOOTH, sy=b.torso_depth)
	geo.translate(ring, (0.0, -lean, 0.0))
	geo.merge(bm, ring)
	back = Vector((0.0, -lean + (b.torso_radius(n - 0.026) + 0.020) * b.torso_depth, n - 0.026))
	knot = geo.ellipsoid(0.028, 0.022, 0.026, seg(lod, 7, 5), seg(lod, 4, 3), row("team_cloth"), sharp=SMOOTH)
	geo.translate(knot, back)
	geo.merge(bm, knot)
	for k, side in enumerate((-1.0, 1.0)):
		pts = [back, back + Vector((side * 0.030, 0.050, 0.004)),
				back + Vector((side * 0.050, 0.110, -0.010 - 0.012 * k)),
				back + Vector((side * 0.064, 0.150, -0.030 - 0.010 * k))]
		geo.merge(bm, geo.tube(pts, [0.024, 0.026, 0.024, 0.0], seg(lod, 6, 4), sharp=SMOOTH, flatten=0.30,
				up=(0.0, 0.0, 1.0), ring_swatches=[row("team_cloth"), row("team_cloth_dark"), row("team_cloth_dark")]))
	return bm


def scimitar(b, lod, size=1.0):
	"""A huge broad scimitar swelling toward a back-swept tip: bright
	steel, a brass guard with curled ends, a dark wrapped grip and a brass
	pommel."""
	k = size
	segs = seg(lod, 6, 4)
	bm = geo.lathe([(0.0, -0.080), (0.019, -0.074), (0.019, 0.052), (0.0, 0.056)], segs, row("leather_dark"), sharp=40,
			phase=0.0)
	pommel = geo.ellipsoid(0.028, 0.028, 0.024, segs, 3, row("brass"), sharp=SMOOTH)
	geo.translate(pommel, (0.0, 0.0, -0.090))
	geo.merge(bm, pommel)
	guard = geo.tube([(-0.070, 0.0, 0.080), (-0.060, 0.0, 0.056), (0.0, 0.0, 0.060), (0.060, 0.0, 0.056),
			(0.070, 0.0, 0.032)], [0.014, 0.018, 0.022, 0.018, 0.012], segs, row("brass"), sharp=40,
			cap_start=row("brass"), cap_end=row("brass"))
	geo.merge(bm, guard)
	edge = [(0.030, 0.064), (0.044, 0.18), (0.064, 0.31), (0.086, 0.43), (0.098, 0.52), (0.088, 0.60), (0.056, 0.655),
			(0.004, 0.682), (-0.044, 0.676), (-0.022, 0.606), (-0.008, 0.50), (-0.016, 0.36), (-0.026, 0.20),
			(-0.030, 0.064)]
	if lod > 0:
		edge = [edge[i] for i in (0, 2, 4, 6, 8, 10, 12, 13)]
	edge = [(x * k, 0.064 + (z - 0.064) * k) for x, z in edge]
	geo.merge(bm, geo.plate(edge, 0.026 * k, row("blade"), side=row("steel"), sharp=FLAT))
	geo.transform(bm, geo.frame(b.r_fist, b.sword_axis, parts.edge_down(b.sword_axis)))
	return bm


# === stag (the Druid) =======================================================

class StagBody(parts.Body):
	"""Tall and slender: long thin legs under a knee-length robe, a narrow
	chest, a long neck and a small head under great antlers."""
	foot_x = 0.054
	hem_z = 0.250
	waist_z = 0.390
	shoulder_z = 0.540
	neck_z = 0.600
	torso_depth = 0.80
	head_centre = Vector((0.0, -0.012, 0.776))
	head_size = Vector((0.272, 0.262, 0.268))
	head_tilt_deg = 9.0
	neck_pivot = Vector((0.0, 0.0, 0.640))
	brow_z = 0.836
	r_shoulder = Vector((-0.120, 0.0, 0.522))
	l_shoulder = Vector((0.120, 0.0, 0.522))
	r_elbow = Vector((-0.172, 0.012, 0.430))
	r_wrist = Vector((-0.188, -0.068, 0.440))
	r_fist = Vector((-0.190, -0.098, 0.442))
	pole_axis = Vector((0.0, -0.05, 1.0)).normalized()
	l_elbow = Vector((0.172, -0.030, 0.436))
	l_wrist = Vector((0.140, -0.120, 0.470))
	l_fist = Vector((0.124, -0.146, 0.482))

	def torso_profile(self):
		h, w, s, n = self.hem_z, self.waist_z, self.shoulder_z, self.neck_z
		return [
			(0.150, h), (0.156, h + 0.010), (0.150, h + 0.040), (0.140, h + 0.090),
			(0.130, w), (0.127, w + 0.050), (0.124, w + 0.098),
			(0.116, s - 0.012), (0.094, s + 0.022), (0.056, n), (0.0, n + 0.004),
		]


def stag_robe(b, lod):
	"""A moss-green robe to the knee, a deep band of the team's colour at
	the leaf-cut hem under a narrow ring of leaf green."""
	prof = b.torso_profile()
	# A thin trim ring just over the hem; the rest of the robe one green.
	h = b.hem_z
	prof = prof[:3] + [(0.147, h + 0.072), (0.144, h + 0.084)] + prof[3:]
	bands = [row("team_cloth")] * 3 + [row("robe_trim")] + [row("robe")] * (len(prof) - 5)
	if lod > 0:
		keep = (0, 3, 4, 6, 8, 10, 11, 12)
		prof = [prof[i] for i in keep]
		bands = [row("team_cloth"), row("robe_trim")] + [row("robe")] * 5
	bm = geo.lathe(prof, seg(lod, 14, 8), sharp=SMOOTH, sy=b.torso_depth, ring_swatches=bands,
			cap_start=row("lining"))
	if lod == 0:
		ring = sorted((v for v in bm.verts if abs(v.co.z - b.hem_z) < 1e-5), key=lambda v: math.atan2(v.co.y, v.co.x))
		for i, v in enumerate(ring):
			if i % 2:
				v.co.z -= 0.034
	return bm


def leaf_collar(b, lod):
	"""A mantle of big leaves fanned round the shoulders, in two greens."""
	bm = geo.new_bm()
	count = seg(lod, 12, 8)
	z = b.shoulder_z + 0.016
	leaf = [(-0.034, 0.0), (0.0, 0.006), (0.034, 0.0), (0.040, -0.050), (0.020, -0.096), (0.0, -0.118),
			(-0.020, -0.096), (-0.040, -0.050)]
	if lod > 0:
		leaf = [leaf[i] for i in (0, 2, 3, 5, 7)]
	for i in range(count):
		a = -math.pi / 2.0 + 2.0 * math.pi * i / count
		out = Vector((math.cos(a), math.sin(a), 0.0))
		r = b.torso_radius(z) - 0.004
		at = Vector((math.cos(a) * r, math.sin(a) * r * b.torso_depth, z))
		swatch = row("robe_trim") if i % 2 == 0 else row("robe")
		p = geo.plate(leaf, 0.008, swatch, sharp=SMOOTH, bend=2.0)
		geo.rotate(p, -42.0, 'X')
		geo.merge(bm, p, geo.orient(at, out))
	return bm


def stag_legs(b, lod):
	"""Long thin legs, bent back at the hock, on small dark cloven hooves."""
	bm = geo.new_bm()
	g = b.base_height
	for side in (-1.0, 1.0):
		x = side * b.foot_x
		pts = [(x, -0.006, g + 0.030), (x, 0.010, g + 0.090), (x, 0.016, g + 0.130), (x, -0.004, b.hem_z + 0.030)]
		leg = geo.tube(pts, [0.024, 0.026, 0.030, 0.040], seg(lod, 7, 5), sharp=SMOOTH,
				ring_swatches=[row("fur_dark"), row("fur"), row("fur")])
		geo.merge(bm, leg)
		for toe in (-1.0, 1.0):
			hoof = geo.ellipsoid(0.018, 0.034, 0.026, seg(lod, 7, 5), seg(lod, 4, 3), row("nose"), sharp=SMOOTH,
					squash_bottom=0.3)
			geo.translate(hoof, (x + toe * 0.014, -0.018, g + 0.012))
			geo.merge(bm, hoof)
	return bm


def stag_neck(b, lod):
	"""A long slender neck."""
	c = b.head_centre
	pts = [(0.0, 0.004, b.neck_z - 0.030), (0.0, -0.004, b.neck_z + 0.030), (0.0, c.y + 0.004, c.z - 0.080)]
	return geo.tube(pts, [0.050, 0.044, 0.046], seg(lod, 8, 6), row("fur"), sharp=SMOOTH)


def stag_head(b, lod):
	"""A small rounded head, narrowing to the cheeks."""
	bm = geo.box(1.0, 1.0, 1.0, row("fur"), SMOOTH)
	bm = geo.subdivided(bm, seg(lod, 2, 1))
	geo.fit(bm, b.head_size, b.head_centre)
	c = b.head_centre
	half_h = b.head_size.z * 0.5
	for v in bm.verts:
		below = (c.z - v.co.z) / half_h
		if below > 0.0:
			v.co.x = c.x + (v.co.x - c.x) * (1.0 - 0.14 * below * below)
	return geo.paint(bm, row("fur"), SMOOTH)


def stag_muzzle(b, lod):
	"""A long tapering cream muzzle, a big dark nose at its tip."""
	c = b.head_centre
	mz = c.z - 0.056
	pts = [(0.0, c.y - 0.070, mz + 0.012), (0.0, c.y - 0.150, mz), (0.0, c.y - 0.208, mz - 0.012),
			(0.0, c.y - 0.236, mz - 0.018)]
	bm = geo.tube(pts, [0.064, 0.054, 0.040, 0.026], seg(lod, 10, 6), row("fur_light"), sharp=SMOOTH,
			cap_end=row("fur_light"), flatten=0.80)
	nose = geo.ellipsoid(0.030, 0.022, 0.022, seg(lod, 8, 5), 3, row("nose"), sharp=SMOOTH)
	geo.translate(nose, (0.0, c.y - 0.230, mz - 0.004))
	geo.merge(bm, nose)
	return bm


def stag_ears(b, lod):
	"""Big leaf-shaped ears held out level to the sides, cream inside."""
	bm = geo.new_bm()
	c = b.head_centre
	for side in (-1.0, 1.0):
		ear = geo.ellipsoid(0.036, 0.016, 0.074, seg(lod, 10, 7), seg(lod, 5, 4), row("fur"), sharp=SMOOTH)
		inner = geo.disc(0.022, 0.050, seg(lod, 8, 6), row("fur_light"), dome=0.003, depth=0.004)
		geo.merge(ear, inner, geo.frame((0.0, -0.012, 0.004), (0.0, -1.0, 0.0), (0.0, 0.0, 1.0)))
		geo.translate(ear, (0.0, 0.0, 0.060))
		geo.rotate(ear, 12.0, 'X')
		geo.rotate(ear, side * 74.0, 'Y')
		geo.translate(ear, (side * 0.108, c.y + 0.018, c.z + 0.040))
		geo.merge(bm, ear)
	return bm


def antlers(b, lod):
	"""Great pale antlers: a beam each side sweeping up and out, three tines
	off each turning forward and up."""
	bm = geo.new_bm()
	c = b.head_centre
	segs = seg(lod, 6, 4)
	for side in (-1.0, 1.0):
		root = Vector((side * 0.066, c.y + 0.010, c.z + 0.118))
		beam = [root, root + Vector((side * 0.050, 0.014, 0.080)), root + Vector((side * 0.112, 0.036, 0.160)),
				root + Vector((side * 0.150, 0.040, 0.250)), root + Vector((side * 0.160, 0.020, 0.316))]
		geo.merge(bm, geo.tube(beam, [0.022, 0.019, 0.016, 0.012, 0.0], segs, row("wood_light"), sharp=SMOOTH))
		burr = geo.lathe([(0.026, -0.008), (0.030, 0.004), (0.020, 0.014)], segs, row("wood_light"), sharp=SMOOTH,
				phase=0.0)
		geo.merge(bm, burr, geo.frame(root + Vector((side * 0.006, 0.0, 0.008)), (side * 0.5, 0.15, 1.0)))
		tines = ((0.30, (side * 0.15, -0.95, 0.55), 0.090), (0.55, (side * 0.05, -0.55, 1.0), 0.100),
				(0.78, (side * 0.55, -0.35, 1.0), 0.080))
		if lod > 0:
			tines = tines[:2]
		for t, d, length in tines:
			k = t * (len(beam) - 1)
			i = min(int(k), len(beam) - 2)
			p = beam[i].lerp(beam[i + 1], k - i)
			d = Vector(d).normalized()
			pts = [p, p + d * length * 0.55 + Vector((0.0, 0.0, 0.010)), p + d * length + Vector((0.0, 0.0, 0.026))]
			geo.merge(bm, geo.tube(pts, [0.014, 0.011, 0.0], segs, row("wood_light"), sharp=SMOOTH))
	return bm


def fawn_spots(b, lod, head_bm):
	"""A few cream spots on the crown, between the antlers."""
	bm = geo.new_bm()
	if lod > 0:
		return bm
	tree = geo.bvh(head_bm)
	c = b.head_centre
	for x, y, r in ((-0.040, 0.030, 0.014), (0.036, 0.040, 0.013), (0.0, 0.080, 0.015), (-0.060, 0.090, 0.011),
			(0.066, 0.096, 0.012)):
		loc, nrm = geo.project(tree, (c.x + x, c.y + y, c.z + 1.0), (0.0, 0.0, -1.0))
		if loc is not None:
			geo.merge(bm, geo.disc(r, r, 6, row("fur_light"), dome=0.002, depth=0.002, simple=True),
					geo.frame(loc, nrm, (0.0, 1.0, 0.0)))
	return bm


def druid_staff(b, lod, below=0.39):
	"""A gnarled staff in a leafy vine, its head a crook curling over a
	glowing jade orb, three leaves sprouting under it."""
	axis = Vector(b.pole_axis).normalized()
	fist = b.r_fist
	segs = seg(lod, 6, 5)
	side = Vector((1.0, 0.0, 0.0))
	fwd = axis.cross(side).normalized()
	if fwd.y > 0.0:
		fwd = -fwd
	top = fist + axis * 0.60
	pts = [fist - axis * below, fist, fist + axis * 0.24 + side * 0.010, fist + axis * 0.44 - side * 0.010, top,
			top + axis * 0.070 + fwd * 0.020, top + axis * 0.090 + fwd * 0.080, top + axis * 0.050 + fwd * 0.124,
			top + axis * -0.004 + fwd * 0.118]
	radii = [0.020, 0.024, 0.024, 0.026, 0.026, 0.024, 0.022, 0.018, 0.010]
	bm = geo.tube(pts, radii, segs, row("leather"), sharp=40, cap_start=row("leather"), cap_end=row("leather"))
	if lod == 0:
		vine = []
		for i in range(19):
			t = i / 18.0
			a = t * 6.0 * math.pi
			p = fist + axis * (-0.06 + t * 0.64)
			vine.append(p + side * math.cos(a) * 0.027 + fwd * math.sin(a) * 0.027)
		geo.merge(bm, geo.tube(vine, [0.007] * len(vine), 4, row("robe_trim"), sharp=SMOOTH))
	orb = geo.ellipsoid(0.064, 0.064, 0.064, seg(lod, 10, 6), seg(lod, 6, 4), row("crystal"), sharp=SMOOTH)
	geo.translate(orb, top + axis * 0.024 + fwd * 0.066)
	geo.merge(bm, orb)
	leaf = [(-0.024, 0.0), (0.024, 0.0), (0.030, 0.040), (0.0, 0.086), (-0.030, 0.040)]
	for dx, dy in ((-1.0, 0.4), (1.0, 0.2), (0.2, -1.0)):
		d = (side * dx + fwd * dy + axis * 0.7).normalized()
		p = geo.plate(leaf, 0.006, row("robe_trim"), sharp=SMOOTH, bend=3.0)
		geo.merge(bm, p, geo.frame(top - axis * 0.05, d, axis))
	# Ribbons of the team's colour tied under the leaves, streaming out:
	# the team colour the camera sees high over the leaf mantle.
	knot_at = top - axis * 0.110
	geo.merge(bm, geo.lathe([(0.030, -0.018), (0.036, 0.0), (0.030, 0.018)], segs, row("team_cloth"), sharp=SMOOTH,
			phase=0.0), geo.frame(knot_at, axis))
	for k, (dx, length) in enumerate(((0.7, 0.170), (-0.7, 0.140))):
		out = (fwd + side * dx).normalized()
		tail = [(-0.026, 0.0), (0.026, 0.0), (0.030, -length), (0.0, -length + 0.022), (-0.030, -length)]
		flap = geo.plate(tail, 0.007, row("team_cloth"), row("team_cloth_dark"), row("team_cloth_dark"), sharp=SMOOTH)
		geo.rotate(flap, 14.0 - 28.0 * k, 'Y')
		geo.rotate(flap, -20.0, 'X')
		geo.merge(bm, flap, geo.orient(knot_at + out * 0.030, out))
	return bm


# === panda (the Panda Warrior) ==============================================

class PandaBody(parts.Body):
	"""A huge round heavyweight: a ball of a body on short pillar legs set
	wide, the belly out, a broad round head sunk on the shoulders."""
	foot_x = 0.112
	hem_z = 0.140
	waist_z = 0.270
	shoulder_z = 0.430
	neck_z = 0.475
	torso_depth = 0.92
	head_centre = Vector((0.0, -0.010, 0.612))
	head_size = Vector((0.372, 0.320, 0.304))
	head_tilt_deg = 8.0
	neck_pivot = Vector((0.0, 0.0, 0.500))
	brow_z = 0.680
	r_shoulder = Vector((-0.240, 0.0, 0.400))
	l_shoulder = Vector((0.240, 0.0, 0.400))
	r_elbow = Vector((-0.336, 0.010, 0.318))
	r_wrist = Vector((-0.344, -0.070, 0.304))
	r_fist = Vector((-0.344, -0.104, 0.302))
	pole_axis = Vector((0.0, -0.08, 1.0)).normalized()
	l_elbow = Vector((0.338, 0.000, 0.320))
	l_wrist = Vector((0.342, -0.086, 0.296))
	l_fist = Vector((0.340, -0.118, 0.290))
	shield_normal = Vector((0.70, -0.70, 0.10)).normalized()

	def torso_profile(self):
		h, w, s, n = self.hem_z, self.waist_z, self.shoulder_z, self.neck_z
		return [
			(0.200, h), (0.226, h + 0.020), (0.246, h + 0.060), (0.258, w - 0.020),
			(0.260, w + 0.020), (0.252, w + 0.070), (0.234, w + 0.112),
			(0.206, s - 0.012), (0.164, s + 0.020), (0.100, n), (0.0, n + 0.004),
		]


def panda_torso(b, lod):
	"""The great round white barrel, painted as a panda's coat: a black
	band over the shoulders and across the upper back (running on down the
	black arms), a white chest, throat and belly."""
	prof = b.torso_profile()
	if lod > 0:
		keep = (0, 2, 3, 5, 6, 7, 8, 9, 10)
		prof = [prof[i] for i in keep]
	bm = geo.lathe(prof, seg(lod, 16, 10), row("fur"), sharp=SMOOTH, sy=b.torso_depth, cap_start=row("fur_dark"))
	sw = bm.faces.layers.int.get(geo.SWATCH)
	band = b.shoulder_z - 0.090
	saddle = b.waist_z + 0.060
	for f in bm.faces:
		if f[sw] != row("fur"):
			continue
		c = f.calc_center_median()
		r = max(b.torso_radius(c.z), 1e-4)
		xn, yn = c.x / r, c.y / (r * b.torso_depth)
		if (c.z > band and (yn > -0.30 or abs(xn) > 0.62)) or (c.z > saddle and yn > 0.30):
			f[sw] = row("fur_dark")
	return bm


def panda_legs(b, lod):
	"""Short black pillar legs on broad round paws."""
	bm = geo.new_bm()
	g = b.base_height
	for side in (-1.0, 1.0):
		leg = geo.lathe([(0.066, g + 0.030), (0.074, b.hem_z + 0.040)], seg(lod, 9, 6), row("fur_dark"))
		geo.translate(leg, (side * b.foot_x, 0.0, 0.0))
		geo.merge(bm, leg)
		paw = geo.ellipsoid(0.074, 0.090, 0.050, seg(lod, 10, 6), seg(lod, 4, 3), row("fur_dark"), sharp=SMOOTH,
				squash_bottom=0.3)
		geo.rotate(paw, side * 14.0, 'Z')
		geo.translate(paw, (side * (b.foot_x + 0.008), -0.026, g + 0.016))
		geo.merge(bm, paw)
	return bm


def panda_head(b, lod):
	"""A broad, round white head, full and low in the cheeks."""
	bm = geo.box(1.0, 1.0, 1.0, row("fur"), SMOOTH)
	bm = geo.subdivided(bm, seg(lod, 2, 1))
	geo.fit(bm, b.head_size, b.head_centre)
	c = b.head_centre
	half_h = b.head_size.z * 0.5
	for v in bm.verts:
		up = (v.co.z - c.z) / half_h
		if up > 0.0:
			v.co.x = c.x + (v.co.x - c.x) * (1.0 - 0.10 * up * up)
		else:
			v.co.x = c.x + (v.co.x - c.x) * (1.0 + 0.06 * up * up)
	return geo.paint(bm, row("fur"), SMOOTH)


def panda_face(b, lod, head_bm):
	"""Big black teardrop patches slanting down and out, the shared dark
	eyes set in them under a bigger glint, a touch of blush under each."""
	tree = geo.bvh(head_bm)
	bm = geo.new_bm()
	c = b.head_centre

	def place(x, z, part, lift=0.0, up=(0.0, 0.0, 1.0)):
		loc, nrm = geo.project(tree, (x, -1.0, z), (0.0, 1.0, 0.0))
		if loc is None:
			return
		geo.merge(bm, part, geo.frame(loc + nrm * lift, nrm, up))

	eye_z = c.z + 0.010
	for side in (-1.0, 1.0):
		place(side * 0.086, eye_z - 0.012, geo.disc(0.040, 0.056, seg(lod, 12, 8), row("fur_dark"), dome=0.004,
				depth=0.004), lift=0.001, up=(side * -0.48, 0.0, 0.88))
		place(side * 0.080, eye_z, geo.disc(0.022, 0.030, seg(lod, 10, 6), row("eye"), dome=0.004), lift=0.006)
		if lod == 0:
			place(side * 0.080 + 0.009, eye_z + 0.012, geo.disc(0.0095, 0.0095, 6, row("glint"), dome=0.0015,
					depth=0.0015, simple=True), lift=0.011)
			place(side * 0.140, eye_z - 0.066, geo.disc(0.016, 0.009, 7, row("blush"), dome=0.001, depth=0.002,
					simple=True))
	return bm


def panda_muzzle(b, lod):
	"""A short, round white muzzle, a broad black nose and a small mouth."""
	c = b.head_centre
	mz = c.z - 0.074
	pts = [(0.0, c.y - 0.08, mz + 0.008), (0.0, c.y - 0.150, mz + 0.002), (0.0, c.y - 0.184, mz - 0.004)]
	bm = geo.tube(pts, [0.076, 0.066, 0.040], seg(lod, 10, 6), row("fur"), sharp=SMOOTH, cap_end=row("fur"),
			flatten=0.72)
	nose = geo.ellipsoid(0.040, 0.024, 0.024, seg(lod, 8, 5), 3, row("nose"), sharp=SMOOTH)
	geo.translate(nose, (0.0, c.y - 0.180, mz + 0.022))
	geo.merge(bm, nose)
	return bm


def panda_ears(b, lod):
	"""Round black ears set out to the sides, under the hat's brim."""
	bm = geo.new_bm()
	c = b.head_centre
	for side in (-1.0, 1.0):
		ear = geo.ellipsoid(0.056, 0.030, 0.052, seg(lod, 10, 7), seg(lod, 5, 4), row("fur_dark"), sharp=SMOOTH)
		geo.rotate(ear, side * 52.0, 'Y')
		geo.translate(ear, (side * 0.168, c.y + 0.020, c.z + 0.090))
		geo.merge(bm, ear)
	return bm


def jingasa(b, lod):
	"""A broad, shallow woven-straw war hat: a wide sloping brim bound in
	dark leather, a low peaked crown, a dark ridge ring and a dark knob on
	top (straw reads against the white head; steel looked like a pot lid)."""
	c = b.head_centre
	z = c.z + b.head_size.z * 0.5 - 0.050
	segs = seg(lod, 18, 10)
	prof = [(0.250, z - 0.010), (0.256, z - 0.002), (0.214, z + 0.030), (0.130, z + 0.070), (0.050, z + 0.098),
			(0.0, z + 0.104)]
	bm = geo.lathe(prof, segs, sharp=40, ring_swatches=[row("leather_dark"), row("wicker"), row("wicker"), row("wicker"),
			row("wicker")], cap_start=row("leather_dark"), sy=0.94)
	ring = geo.lathe([(0.138, z + 0.062), (0.146, z + 0.070), (0.124, z + 0.082)], segs, row("leather_dark"), sharp=40,
			sy=0.94)
	geo.merge(bm, ring)
	knob = geo.ellipsoid(0.022, 0.022, 0.020, seg(lod, 7, 5), 3, row("leather_dark"), sharp=40)
	geo.translate(knob, (0.0, 0.0, z + 0.112))
	geo.merge(bm, knob)
	geo.translate(bm, (c.x, c.y + 0.012, 0.0))
	return bm


def panda_tail(b, lod):
	"""A round white tuft of a tail behind."""
	tail = geo.ellipsoid(0.040, 0.034, 0.036, seg(lod, 7, 5), seg(lod, 4, 3), row("fur"), sharp=SMOOTH)
	geo.translate(tail, (0.0, b.torso_radius(b.hem_z + 0.03) * b.torso_depth + 0.020, b.hem_z + 0.020))
	return tail


def guandao(b, lod):
	"""A long guandao stood upright: a dark haft, a huge curved blade swept
	back to a point, a brass collar, a tassel in the team's colour under the
	blade and a steel butt spike."""
	axis = Vector(b.pole_axis).normalized()
	segs = seg(lod, 6, 4)
	below, top = 0.30, 0.72
	bm = geo.lathe([(0.0, -below - 0.07), (0.026, -below), (0.024, top), (0.0, top + 0.01)], segs, row("wood"),
			sharp=40, phase=0.0)
	geo.merge(bm, geo.lathe([(0.030, -0.040), (0.030, 0.070)], segs, row("leather_dark"), sharp=40, phase=0.0))
	geo.merge(bm, geo.lathe([(0.0, -below - 0.090), (0.024, -below - 0.040), (0.030, -below + 0.010)], segs,
			row("steel"), sharp=40, phase=0.0))
	geo.merge(bm, geo.lathe([(0.032, top - 0.030), (0.040, top - 0.010), (0.040, top + 0.020), (0.030, top + 0.034)],
			segs, row("brass"), sharp=40, phase=0.0))
	# The blade: its edge out on -X (turned to the ground by edge_down), a
	# broad belly sweeping up and back to a point over the haft.
	edge = [(0.020, top + 0.020), (-0.060, top + 0.030), (-0.130, top + 0.080), (-0.158, top + 0.160),
			(-0.150, top + 0.250), (-0.108, top + 0.330), (-0.040, top + 0.390), (0.020, top + 0.410),
			(0.010, top + 0.360), (0.044, top + 0.300), (0.030, top + 0.240), (0.052, top + 0.180),
			(0.030, top + 0.110), (0.034, top + 0.040)]
	if lod > 0:
		edge = [edge[i] for i in (0, 2, 3, 4, 5, 6, 7, 9, 11, 13)]
	geo.merge(bm, geo.plate(edge, 0.030, row("blade"), side=row("steel"), sharp=FLAT))
	# The team's tassel: a short cord and a fat tuft hanging from the collar.
	cord = [Vector((0.040, 0.0, top - 0.010)), Vector((0.060, 0.0, top - 0.050))]
	geo.merge(bm, geo.tube(cord, [0.008, 0.008], 4, row("team_cloth_dark"), sharp=SMOOTH))
	tuft = [Vector((0.060, 0.0, top - 0.050)), Vector((0.068, 0.0, top - 0.090)), Vector((0.074, 0.0, top - 0.150)),
			Vector((0.076, 0.0, top - 0.180))]
	geo.merge(bm, geo.tube(tuft, [0.018, 0.034, 0.030, 0.0], seg(lod, 7, 5), sharp=SMOOTH, cap_start=row("team_cloth"),
			ring_swatches=[row("team_cloth"), row("team_cloth"), row("team_cloth_dark")]))
	geo.transform(bm, geo.frame(b.r_fist, axis, parts.edge_down(axis, (-1.0, 0.0))))
	return bm


def gong_shield(b, lod):
	"""A big round shield like a gong on the left forearm: a brass rim, a
	face in the team's colour, a steel boss and (near) a brass swirl."""
	bm = geo.new_bm()
	segs = seg(lod, 18, 10)
	radius = 0.150
	dome = 0.026
	face = geo.lathe([(0.0, -0.014), (radius - 0.010, -0.014), (radius, -0.004), (radius * 0.62, dome * 0.62),
			(0.0, dome)], segs, sharp=40, phase=0.0,
			ring_swatches=[row("wood"), row("brass"), row("team"), row("team")])
	geo.merge(bm, face)
	rim = geo.lathe([(radius + 0.008, -0.012), (radius + 0.008, 0.004), (radius - 0.020, 0.010)], segs, row("brass"),
			sharp=40, phase=0.0)
	geo.merge(bm, rim)
	boss = geo.lathe([(0.046, dome - 0.004), (0.048, dome + 0.004), (0.030, dome + 0.020), (0.0, dome + 0.028)],
			seg(lod, 8, 6), row("steel"), sharp=40, phase=0.0)
	geo.merge(bm, boss)
	if lod == 0:
		tree = geo.bvh(face)
		pts, nrms = [], []
		for i in range(14):
			t = i / 13.0
			a = t * 1.6 * math.pi
			r = 0.056 + 0.070 * t
			loc, nrm = geo.project(tree, (math.cos(a) * r, math.sin(a) * r, 0.3), (0.0, 0.0, -1.0))
			if loc is not None:
				pts.append(loc)
				nrms.append(nrm)
		if len(pts) > 1:
			geo.merge(bm, geo.ribbon(pts, nrms, 0.016, 0.003, row("brass"), sharp=40, embed=0.0015))
	forearm_mid = (b.l_elbow + b.l_wrist) * 0.5
	centre = forearm_mid + b.shield_normal * 0.074
	geo.transform(bm, geo.frame(centre, b.shield_normal, (0.0, 0.0, 1.0)))
	return bm


# === wolf (the Wolf Pathfinder) =============================================

class WolfBody(parts.Body):
	"""Lean and rangy: long digitigrade legs, a narrow waist under a deep
	chest leaning forward, the head carried out in front."""
	foot_x = 0.066
	hem_z = 0.250
	waist_z = 0.360
	shoulder_z = 0.500
	neck_z = 0.552
	torso_depth = 0.82
	head_centre = Vector((0.0, -0.126, 0.668))
	head_size = Vector((0.284, 0.262, 0.226))
	head_tilt_deg = 4.0
	neck_pivot = Vector((0.0, -0.080, 0.572))
	brow_z = 0.718
	## How far the chest leans forward per metre above the waist.
	hunch = 0.34
	r_shoulder = Vector((-0.132, -0.044, 0.484))
	l_shoulder = Vector((0.132, -0.044, 0.484))
	r_elbow = Vector((-0.176, -0.020, 0.388))
	r_wrist = Vector((-0.110, -0.110, 0.392))
	r_fist = Vector((-0.080, -0.136, 0.396))
	l_elbow = Vector((0.160, -0.110, 0.420))
	l_wrist = Vector((0.080, -0.200, 0.410))
	l_fist = Vector((0.052, -0.226, 0.412))
	stock_rear = Vector((-0.086, -0.080, 0.398))
	stock_front = Vector((0.016, -0.420, 0.424))

	def torso_profile(self):
		h, w, s, n = self.hem_z, self.waist_z, self.shoulder_z, self.neck_z
		return [
			(0.128, h), (0.134, h + 0.010), (0.130, h + 0.030), (0.116, h + 0.070),
			(0.104, w), (0.120, w + 0.050), (0.132, w + 0.096),
			(0.124, s - 0.012), (0.100, s + 0.020), (0.064, n), (0.0, n + 0.004),
		]


def wolf_torso(b, lod):
	"""A deep chest in a leather jerkin over a short hide kilt, pinched at
	the waist, leaning forward."""
	prof = b.torso_profile()
	bands = [row("leather_dark")] * 4 + [row("leather")] * (len(prof) - 5)
	if lod > 0:
		keep = (0, 1, 2, 4, 6, 8, 9, 10)
		prof = [prof[i] for i in keep]
		bands = [row("leather_dark")] * 3 + [row("leather")] * 4
	bm = geo.lathe(prof, seg(lod, 12, 8), sharp=SMOOTH, sy=b.torso_depth, ring_swatches=bands,
			cap_start=row("fur_dark"))
	if lod == 0:
		ring = sorted((v for v in bm.verts if abs(v.co.z - b.hem_z) < 1e-5), key=lambda v: math.atan2(v.co.y, v.co.x))
		for i, v in enumerate(ring):
			if i % 2:
				v.co.z -= 0.026
	return _hunch(b, bm)


def wolf_legs(b, lod):
	"""Long digitigrade legs: a thigh, a long shin bent back at the hock,
	dark socks and long pawed feet."""
	bm = geo.new_bm()
	g = b.base_height
	for side in (-1.0, 1.0):
		x = side * b.foot_x
		pts = [(x, -0.030, g + 0.036), (x, 0.018, g + 0.092), (x, 0.026, g + 0.120), (x, -0.020, g + 0.170),
				(x, -0.010, b.hem_z + 0.030)]
		leg = geo.tube(pts, [0.026, 0.028, 0.032, 0.040, 0.050], seg(lod, 7, 5), sharp=SMOOTH,
				ring_swatches=[row("fur_dark"), row("fur_dark"), row("fur"), row("fur")])
		geo.merge(bm, leg)
		paw = geo.ellipsoid(0.034, 0.064, 0.030, seg(lod, 8, 5), seg(lod, 4, 3), row("fur_dark"), sharp=SMOOTH,
				squash_bottom=0.3)
		geo.rotate(paw, side * 8.0, 'Z')
		geo.translate(paw, (x, -0.058, g + 0.014))
		geo.merge(bm, paw)
	return bm


def wolf_head(b, lod):
	"""A broad wedge skull: wide at the cheeks and jaw, a flat broad brow,
	narrowing toward the snout seen from above."""
	bm = geo.box(1.0, 1.0, 1.0, row("fur"), SMOOTH)
	bm = geo.subdivided(bm, seg(lod, 2, 1))
	geo.fit(bm, b.head_size, b.head_centre)
	c = b.head_centre
	half_h = b.head_size.z * 0.5
	half_y = b.head_size.y * 0.5
	for v in bm.verts:
		up = (v.co.z - c.z) / half_h
		if up > 0.0:
			v.co.x = c.x + (v.co.x - c.x) * (1.0 - 0.06 * up * up)
			v.co.z = c.z + (v.co.z - c.z) * (1.0 - 0.10 * up)
		else:
			v.co.x = c.x + (v.co.x - c.x) * (1.0 + 0.12 * up * up)
		front = (c.y - v.co.y) / half_y
		if front > 0.0:
			v.co.x = c.x + (v.co.x - c.x) * (1.0 - 0.16 * front * front)
	return geo.paint(bm, row("fur"), SMOOTH)


def wolf_brow(b, lod):
	"""A heavy dark brow ridge over each eye, slanting down to the bridge of
	the snout: a stern wolf's frown."""
	bm = geo.new_bm()
	c = b.head_centre
	for side in (-1.0, 1.0):
		brow = geo.ellipsoid(0.050, 0.024, 0.017, seg(lod, 8, 6), seg(lod, 4, 3), row("fur_dark"), sharp=SMOOTH)
		geo.rotate(brow, side * -18.0, 'Y')
		geo.translate(brow, (side * 0.058, c.y - b.head_size.y * 0.5 + 0.016, c.z + 0.066))
		geo.merge(bm, brow)
	return bm


def wolf_muzzle(b, lod):
	"""A long tapering snout, cream underneath, a grey bridge over it and a
	black nose at its tip."""
	c = b.head_centre
	mz = c.z - 0.050
	pts = [(0.0, c.y - 0.070, mz + 0.002), (0.0, c.y - 0.160, mz - 0.006), (0.0, c.y - 0.222, mz - 0.012),
			(0.0, c.y - 0.248, mz - 0.014)]
	bm = geo.tube(pts, [0.100, 0.078, 0.060, 0.044], seg(lod, 10, 6), row("fur_light"), sharp=SMOOTH,
			cap_end=row("fur_light"), flatten=0.80)
	bridge = [(0.0, c.y - 0.050, mz + 0.046), (0.0, c.y - 0.150, mz + 0.030), (0.0, c.y - 0.226, mz + 0.016)]
	geo.merge(bm, geo.tube(bridge, [0.076, 0.060, 0.044], seg(lod, 8, 5), row("fur"), sharp=SMOOTH, flatten=0.72,
			up=(1.0, 0.0, 0.0)))
	# A heavy lower jaw under the snout, square at the chin.
	jaw = [(0.0, c.y - 0.060, mz - 0.040), (0.0, c.y - 0.150, mz - 0.042), (0.0, c.y - 0.204, mz - 0.038)]
	geo.merge(bm, geo.tube(jaw, [0.080, 0.062, 0.044], seg(lod, 8, 5), row("fur_light"), sharp=SMOOTH, flatten=0.62,
			cap_end=row("fur_light")))
	nose = geo.ellipsoid(0.040, 0.028, 0.026, seg(lod, 8, 5), 3, row("nose"), sharp=SMOOTH)
	geo.translate(nose, (0.0, c.y - 0.252, mz + 0.006))
	geo.merge(bm, nose)
	return bm


def wolf_ears(b, lod):
	"""Tall pointed ears standing up and a little out, dark at the back,
	cream inside."""
	bm = geo.new_bm()
	c = b.head_centre
	outline = [(-0.044, 0.0), (0.044, 0.0), (0.030, 0.060), (0.0, 0.124), (-0.030, 0.060)]
	inner = [(-0.026, 0.008), (0.026, 0.008), (0.016, 0.054), (0.0, 0.096), (-0.016, 0.054)]
	for side in (-1.0, 1.0):
		ear = geo.plate(outline, 0.020, row("fur"), row("fur_dark"), row("fur"), sharp=SMOOTH)
		lining = geo.plate(inner, 0.006, row("fur_light"), sharp=SMOOTH)
		geo.translate(lining, (0.0, -0.011, 0.0))
		geo.merge(ear, lining)
		geo.rotate(ear, -8.0, 'X')
		geo.rotate(ear, side * -18.0, 'Y')
		geo.translate(ear, (side * 0.092, c.y + 0.030, c.z + 0.088))
		geo.merge(bm, ear)
	return bm


def cheek_ruff(b, lod):
	"""Cream fur tufts flaring from the cheeks."""
	bm = geo.new_bm()
	c = b.head_centre
	for side in (-1.0, 1.0):
		root = Vector((side * 0.126, c.y + 0.004, c.z - 0.050))
		d = Vector((side * 1.0, 0.45, -0.55)).normalized()
		geo.merge(bm, geo.tube([root, root + d * 0.024, root + d * 0.048], [0.036, 0.026, 0.0], seg(lod, 6, 4),
				row("fur_light"), sharp=SMOOTH, flatten=0.40, up=(0.0, 1.0, 0.0)))
	return bm


def wolf_neck(b, lod):
	"""A short thick neck reaching forward to the head, cream at the throat."""
	c = b.head_centre
	lean = b.hunch * (b.neck_z - b.waist_z)
	pts = [(0.0, -lean + 0.004, b.neck_z - 0.040), (0.0, -lean - 0.020, b.neck_z + 0.020), (0.0, c.y + 0.030, c.z - 0.070)]
	return geo.tube(pts, [0.064, 0.058, 0.056], seg(lod, 8, 6), row("fur_light"), sharp=SMOOTH)


def wolf_tail(b, lod):
	"""A long bushy tail sweeping out behind and down, curling up at its
	cream tip."""
	w = b.waist_z
	pts = [(0.0, 0.090, w - 0.050), (0.006, 0.170, w - 0.080), (0.016, 0.250, w - 0.140), (0.026, 0.320, w - 0.180),
			(0.034, 0.380, w - 0.170), (0.038, 0.420, w - 0.130)]
	return geo.tube(pts, [0.026, 0.050, 0.060, 0.052, 0.036, 0.0], seg(lod, 8, 5), sharp=SMOOTH,
			ring_swatches=[row("fur"), row("fur"), row("fur"), row("fur_light"), row("fur_light")])


def ranger_mantle(b, lod):
	"""A ranger's short mantle in the team's colour round the shoulders,
	dagged at its edge, its hood thrown back in folds at the nape."""
	n, s = b.neck_z, b.shoulder_z
	prof = [(0.150, s - 0.046), (0.152, s - 0.026), (0.140, s + 0.006), (0.100, n - 0.012), (0.072, n + 0.018)]
	bm = geo.lathe(prof, seg(lod, 14, 9), row("team_cloth"), sharp=50, sy=0.86, cap_start=row("team_cloth_dark"))
	if lod == 0:
		for k in range(10):
			theta = -math.pi / 2.0 + (k + 0.5) * 2.0 * math.pi / 10.0
			out = Vector((math.cos(theta) * 0.150, math.sin(theta) * 0.150 * 0.86, s - 0.044))
			dag = geo.plate([(-0.024, 0.0), (0.024, 0.0), (0.0, -0.032)], 0.006, row("team_cloth"), sharp=50)
			flat = Vector((out.x, out.y, 0.0)).normalized()
			geo.transform(dag, geo.orient(out + flat * 0.002, flat, (0.0, 0.0, 1.0)))
			geo.merge(bm, dag)
	hood = geo.ellipsoid(0.080, 0.054, 0.058, seg(lod, 10, 7), seg(lod, 5, 4), row("team_cloth"), sharp=SMOOTH)
	geo.translate(hood, (0.0, 0.104, n - 0.010))
	geo.merge(bm, hood)
	fold = geo.ellipsoid(0.060, 0.030, 0.040, seg(lod, 8, 5), seg(lod, 4, 3), row("team_cloth_dark"), sharp=SMOOTH)
	geo.translate(fold, (0.0, 0.140, n - 0.026))
	geo.merge(bm, fold)
	return _hunch(b, bm)


def bolt_quiver(b, lod):
	"""A leather bolt quiver slung on the right hip, the bolts' pale
	fletchings out of its mouth."""
	bm = geo.lathe([(0.030, 0.0), (0.034, 0.140), (0.038, 0.150)], seg(lod, 7, 5), row("leather"), sharp=40,
			cap_start=row("leather_dark"), sy=0.80)
	geo.merge(bm, geo.lathe([(0.036, 0.020), (0.036, 0.034)], seg(lod, 7, 5), row("leather_dark"), sharp=40, sy=0.80))
	if lod == 0:
		for dx, dy in ((-0.012, -0.006), (0.010, -0.004), (0.0, 0.012)):
			end = geo.plate([(-0.012, 0.0), (0.012, 0.0), (0.012, 0.030), (0.0, 0.040), (-0.012, 0.030)], 0.004,
					row("fletch"), sharp=40)
			geo.translate(end, (dx, dy, 0.140))
			geo.merge(bm, end)
	geo.rotate(bm, -24.0, 'Y')
	geo.rotate(bm, 12.0, 'X')
	geo.translate(bm, (-0.128, 0.040, b.waist_z - 0.150))
	return bm
