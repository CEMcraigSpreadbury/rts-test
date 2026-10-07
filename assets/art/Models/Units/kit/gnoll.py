"""Gnoll parts: a hyena-headed chibi on the human Body's proportions, in
fur, hide and bone (the gnolls palette's fur, fur_dark, fur_light, nose,
bone and ochre rows). The team's colour is on the loincloth (the gnolls'
tabard) and the shield's face, as the humans' rule has it.

The head pieces are built upright and tipped back by the recipe (see
units._head's use of Body.head_matrix), as the humans' are.
"""
import math

from mathutils import Matrix, Vector

import geo
from geo import FLAT, HARD, SMOOTH
from palette import row
import parts
from parts import seg, _limb, _on_torso


# --- head -------------------------------------------------------------------

def head(b, lod):
	"""A rounded-box head in tawny fur, its top kept (no helmet hides it)."""
	bm = geo.box(1.0, 1.0, 1.0, row("fur"), SMOOTH)
	bm = geo.subdivided(bm, seg(lod, 2, 1))
	size = Vector((b.head_size.x * 1.03, b.head_size.y, b.head_size.z * 0.97))
	geo.fit(bm, size, b.head_centre)
	c = b.head_centre
	half_h = size.z * 0.5
	for v in bm.verts:
		below = (c.z - v.co.z) / half_h
		if below > 0.0:
			v.co.x = c.x + (v.co.x - c.x) * (1.0 - 0.15 * below * below)
			v.co.y = c.y + (v.co.y - c.y) * (1.0 - 0.05 * below)
	return geo.paint(bm, row("fur"), SMOOTH)


def _muzzle_z(b):
	return b.head_centre.z - 0.064


def muzzle(b, lod):
	"""A short, pale hyena muzzle out of the lower face, a dark button nose
	on its tip and a small smile under it."""
	c, mz = b.head_centre, _muzzle_z(b)
	pts = [(0.0, c.y - 0.06, mz + 0.006), (0.0, c.y - 0.15, mz + 0.002), (0.0, c.y - 0.200, mz - 0.004),
			(0.0, c.y - 0.236, mz - 0.010), (0.0, c.y - 0.250, mz - 0.014)]
	bm = geo.tube(pts, [0.062, 0.058, 0.050, 0.040, 0.026], seg(lod, 9, 6), sharp=SMOOTH,
			ring_swatches=[row("fur_light"), row("fur_light"), row("fur_dark"), row("fur_dark")],
			cap_end=row("fur_dark"), flatten=0.78)
	tree = geo.bvh(bm)
	nose = geo.ellipsoid(0.026, 0.018, 0.018, seg(lod, 7, 5), 3, row("nose"), sharp=SMOOTH)
	geo.translate(nose, (0.0, c.y - 0.246, mz + 0.012))
	geo.merge(bm, nose)
	if lod == 0:
		pts, nrms = [], []
		for i in range(5):
			t = (i / 4.0) * 2.0 - 1.0
			loc, nrm = geo.project(tree, (t * 0.024, c.y - 0.5, mz - 0.020 + 0.007 * t * t), (0.0, 1.0, 0.0))
			if loc is not None:
				pts.append(loc)
				nrms.append(nrm)
		if len(pts) > 1:
			geo.merge(bm, geo.ribbon(pts, nrms, 0.0, 0.0022, row("mouth"), sharp=SMOOTH, embed=0.002,
					widths=[0.004, 0.0068, 0.0076, 0.0068, 0.004][:len(pts)]))
	return bm


def face(b, lod, head_bm):
	"""The humans' big dark eyes and glints, set a little higher and wider
	to clear the muzzle, and a touch of blush."""
	tree = geo.bvh(head_bm)
	bm = geo.new_bm()

	def place(x, z, part, lift=0.0):
		loc, nrm = geo.project(tree, (x, -1.0, z), (0.0, 1.0, 0.0))
		if loc is None:
			return
		geo.merge(bm, part, geo.frame(loc + nrm * lift, nrm, (0.0, 0.0, 1.0)))

	eye_z = b.head_centre.z + 0.004
	for side in (-1.0, 1.0):
		place(side * 0.070, eye_z, geo.disc(0.021, 0.029, seg(lod, 10, 6), row("eye"), dome=0.004))
		if lod == 0:
			place(side * 0.070 + 0.008, eye_z + 0.011, geo.disc(0.0068, 0.0068, 5, row("glint"), dome=0.0015,
					depth=0.0015, simple=True), lift=0.0045)
			place(side * 0.112, eye_z - 0.044, geo.disc(0.016, 0.009, 7, row("blush"), dome=0.001, depth=0.002,
					simple=True))
	return bm


def ears(b, lod):
	"""Big rounded hyena ears, dark-backed, pale inside, set high and
	leaning out."""
	bm = geo.new_bm()
	c = b.head_centre
	for side in (-1.0, 1.0):
		ear = geo.ellipsoid(0.056, 0.018, 0.070, seg(lod, 10, 7), seg(lod, 5, 4), row("fur_dark"), sharp=SMOOTH)
		for v in ear.verts:
			# Broad, rounded tips over a narrower root.
			if v.co.z < 0.0:
				v.co.x *= 1.0 + 0.40 * v.co.z / 0.070
		inner = geo.disc(0.034, 0.044, seg(lod, 8, 6), row("blush"), dome=0.003, depth=0.004)
		geo.merge(ear, inner, geo.frame((0.0, -0.012, 0.010), (0.0, -1.0, 0.0), (0.0, 0.0, 1.0)))
		geo.rotate(ear, side * 30.0, 'Y')
		geo.rotate(ear, side * 12.0, 'Z')
		geo.translate(ear, (side * 0.126, c.y + 0.024, c.z + 0.162))
		geo.merge(bm, ear)
	return bm


def mane(b, lod, head_bm, swatch="fur_dark"):
	"""A scalloped dark mane ridge from the brow back over the crown and down
	the back of the head (the berserk's daubed in war paint)."""
	tree = geo.bvh(head_bm)
	c = b.head_centre
	steps = seg(lod, 13, 7)
	pts, radii = [], []
	for i in range(steps):
		a = math.pi * (0.30 + 0.95 * i / (steps - 1))
		out = Vector((0.0, -math.cos(a), math.sin(a)))
		loc, nrm = geo.project(tree, c + out * 0.6, -out)
		if loc is None:
			continue
		r = (0.046 if i % 2 == 0 else 0.026) if lod == 0 else 0.038
		pts.append(loc + nrm * (r * 0.45))
		radii.append(r)
	radii[0] = radii[-1] = 0.012
	return geo.tube(pts, radii, seg(lod, 6, 4), row(swatch), sharp=SMOOTH, up=(1.0, 0.0, 0.0), flatten=0.42,
			cap_start=row(swatch), cap_end=row(swatch))


def _spots(tree, centre, dirs, lod):
	bm = geo.new_bm()
	if lod > 0:
		return bm
	for d, r in dirs:
		d = Vector(d).normalized()
		loc, nrm = geo.project(tree, Vector(centre) + d * 0.6, -d)
		if loc is None:
			continue
		geo.merge(bm, geo.disc(r * 1.45, r * 1.2, 7, row("fur_dark"), dome=0.003, depth=0.004),
				geo.frame(loc + nrm * 0.0015, nrm, (0.0, 0.0, 1.0)))
	return bm


def head_spots(b, lod, head_bm):
	"""Hyena spots over the cheeks, temples and the back of the head."""
	dirs = [((-1.0, -0.55, 0.30), 0.024), ((-1.0, -0.05, -0.20), 0.030), ((-0.9, 0.45, 0.40), 0.026),
			((-0.75, -0.9, 0.55), 0.020), ((0.75, -0.9, 0.58), 0.019), ((-0.55, -1.0, -0.38), 0.016),
			((0.58, -1.0, -0.36), 0.017), ((1.0, -0.50, 0.25), 0.025), ((1.0, 0.05, -0.25), 0.029),
			((0.85, 0.55, 0.40), 0.026), ((-0.35, 1.0, 0.0), 0.030), ((0.40, 1.0, -0.25), 0.028),
			((0.10, 1.0, 0.50), 0.022), ((0.0, 0.4, 1.0), 0.020)]
	return _spots(geo.bvh(head_bm), b.head_centre, dirs, lod)


# --- body -------------------------------------------------------------------

def torso(b, lod):
	"""A furred chest over a ragged hide kilt flaring to the hem."""
	prof = b.torso_profile()
	bands = [row("leather")] * 4 + [row("fur")] * (len(prof) - 5)
	if lod > 0:
		keep = (0, 1, 2, 4, 6, 8, 9, 10)
		prof = [prof[i] for i in keep]
		bands = [row("leather")] * 3 + [row("fur")] * 4
	bm = geo.lathe(prof, seg(lod, 12, 8), sharp=SMOOTH, sy=b.torso_depth, ring_swatches=bands,
			cap_start=row("fur_dark"))
	if lod == 0:
		# A ragged hem: every other vertex of the bottom ring dropped.
		ring = sorted((v for v in bm.verts if abs(v.co.z - b.hem_z) < 1e-5), key=lambda v: math.atan2(v.co.y, v.co.x))
		for i, v in enumerate(ring):
			if i % 2:
				v.co.z -= 0.022
	return bm


def body_spots(b, lod, torso_bm):
	dirs = [((-1.0, 0.2, 0.0), 0.028), ((1.0, 0.1, 0.0), 0.027), ((-0.6, 1.0, 0.0), 0.030), ((0.5, 1.0, 0.0), 0.028),
			((0.0, 1.0, 0.0), 0.024), ((-0.8, -0.5, 0.0), 0.024), ((0.8, -0.45, 0.0), 0.025), ((-0.25, -1.0, 0.0), 0.022),
			((0.30, -1.0, 0.0), 0.020), ((-1.0, 0.6, 0.0), 0.022)]
	bm = geo.new_bm()
	tree = geo.bvh(torso_bm)
	for (d, r), dz in zip(dirs, (0.40, 0.375, 0.43, 0.38, 0.47, 0.45, 0.41, 0.36, 0.42, 0.36)):
		geo.merge(bm, _spots(tree, (0.0, 0.0, dz), [(d, r)], lod))
	return bm


def legs(b, lod):
	"""Furred legs and big dark paws with bone claws."""
	bm = geo.new_bm()
	g = b.base_height
	for side in (-1.0, 1.0):
		leg = geo.lathe([(0.040, g + 0.040), (0.046, b.hem_z + 0.06)], seg(lod, 8, 5), row("fur"))
		geo.translate(leg, (side * b.foot_x, 0.0, 0.0))
		geo.merge(bm, leg)
		paw = geo.ellipsoid(0.050, 0.070, 0.046, seg(lod, 9, 6), seg(lod, 4, 3), row("fur_dark"), sharp=SMOOTH,
				squash_bottom=0.3)
		geo.translate(paw, (0.0, -0.022, g + 0.014))
		if lod == 0:
			for k in (-1.0, 0.0, 1.0):
				claw = geo.lathe([(0.008, 0.0), (0.0, 0.020)], 4, row("bone"), sharp=40, phase=0.0, cap_start=row("bone"))
				geo.merge(paw, claw, geo.frame((k * 0.024, -0.082 + abs(k) * 0.012, g + 0.010),
						(0.0, -1.0, -0.35), (0.0, 0.0, 1.0)))
		geo.rotate(paw, side * 9.0, 'Z')
		geo.translate(paw, (side * b.foot_x, 0.0, 0.0))
		geo.merge(bm, paw)
	return bm


def belt(b, lod):
	"""A hide thong round the waist, a bone toggle at the front."""
	w = b.waist_z
	r = b.torso_radius(w)
	prof = [(r - 0.006, w - 0.016), (r + 0.008, w - 0.012), (r + 0.008, w + 0.012), (r - 0.006, w + 0.016)]
	bm = geo.lathe(prof, seg(lod, 12, 8), row("leather_dark"), sharp=40, sy=b.torso_depth)
	toggle = geo.tube([(-0.030, 0.0, 0.0), (0.0, 0.0, 0.004), (0.030, 0.0, 0.0)], [0.009, 0.012, 0.009], seg(lod, 6, 4),
			row("bone"), sharp=50, cap_start=row("bone"), cap_end=row("bone"))
	geo.translate(toggle, (0.0, -(r + 0.010) * b.torso_depth - 0.004, w))
	geo.merge(bm, toggle)
	return bm


def loincloth(b, lod, back=True, out=0.0):
	"""Cloth flaps in the team's colour hanging from the belt over the kilt,
	front (and back), ragged at the foot: the gnolls' tabard."""
	bm = geo.new_bm()
	w, h = b.waist_z, b.hem_z
	top, bottom = w + 0.008, h - 0.075
	length = top - bottom
	outline = [(-0.086, 0.0), (0.086, 0.0), (0.078, -length)]
	if lod == 0:
		outline += [(0.040, -length + 0.030), (0.004, -length - 0.006), (-0.036, -length + 0.026)]
	outline.append((-0.078, -length))
	r_top = b.torso_radius(top) * b.torso_depth + 0.010 + out
	r_hem = b.torso_radius(h + 0.03) * b.torso_depth + 0.024 + out
	lean = math.degrees(math.atan2(r_hem - r_top, length))
	for side in ((-1.0, 1.0) if back else (-1.0,)):
		flap = geo.plate(outline, 0.008, row("team_cloth"), row("team_cloth_dark"), row("team_cloth_dark"), sharp=SMOOTH,
				bend=1.6)
		geo.rotate(flap, -lean, 'X')
		geo.translate(flap, (0.0, -r_top, top))
		if side > 0:
			geo.rotate(flap, 180.0, 'Z')
		geo.merge(bm, flap)
	return bm


def necklace(b, lod):
	"""Teeth and ochre beads on a thong round the neck."""
	bm = geo.new_bm()
	if lod > 0:
		return bm
	z = b.neck_z - 0.032
	r = b.torso_radius(z) + 0.004
	count = 9
	for i in range(count):
		theta = math.radians(-160.0 + 140.0 * i / (count - 1))
		at = Vector((math.cos(theta) * r, math.sin(theta) * r * 0.86, z))
		out = Vector((math.cos(theta), math.sin(theta), 0.0))
		if i % 2 == 0:
			tooth = geo.lathe([(0.008, 0.0), (0.006, 0.014), (0.0, 0.032)], 5, row("bone"), sharp=40, phase=0.0,
					cap_start=row("bone"))
			geo.merge(bm, tooth, geo.frame(at + out * 0.006, (out * 0.35 + Vector((0.0, 0.0, -1.0))), out))
		else:
			bead = geo.ellipsoid(0.010, 0.010, 0.009, 5, 3, row("ochre"), sharp=SMOOTH)
			geo.translate(bead, at + out * 0.004)
			geo.merge(bm, bead)
	return bm


def shoulder_pad(b, lod, side=-1.0):
	"""A hide pad on the weapon shoulder (side=1: the left), two bone horns
	standing out of it."""
	shoulder = b.r_shoulder if side < 0 else b.l_shoulder
	axis = Vector((0.62 * side, 0.0, 1.0)).normalized()
	segs = seg(lod, 8, 6)
	pad = geo.lathe([(0.088, -0.012), (0.090, 0.004), (0.080, 0.028), (0.052, 0.052), (0.0, 0.062)], segs,
			ring_swatches=[row("fur_dark"), row("leather"), row("leather"), row("leather")], sharp=50, sy=0.94,
			phase=0.0)
	for k, (dx, dy) in enumerate(((-0.020, -0.028), (0.006, 0.030))):
		horn = geo.lathe([(0.016, 0.0), (0.011, 0.030), (0.0, 0.058 - 0.012 * k)], seg(lod, 6, 4), row("bone"), sharp=40,
				phase=0.0)
		geo.merge(pad, horn, geo.frame((dx, dy, 0.040), (-0.25, 0.0, 1.0), (0.0, 1.0, 0.0)))
	at = shoulder + Vector((0.012 * side, 0.0, 0.034))
	bm = geo.new_bm()
	geo.merge(bm, pad, geo.frame(at, axis, (0.0, -1.0, 0.0)))
	return bm


def arms(b, lod):
	"""Furred arms, hide-wrapped forearms, dark-furred fists."""
	bm = geo.new_bm()
	segs = seg(lod, 7, 5)
	for shoulder, elbow, wrist, fist in ((b.r_shoulder, b.r_elbow, b.r_wrist, b.r_fist),
			(b.l_shoulder, b.l_elbow, b.l_wrist, b.l_fist)):
		upper = (elbow - shoulder).length
		geo.merge(bm, _limb(shoulder, elbow, [(0.048, -0.01), (0.054, 0.006), (0.047, upper),
				(0.034, upper + 0.022), (0.0, upper + 0.030)], segs, row("fur")))
		lower = (wrist - elbow).length
		if lod == 0:
			prof = [(0.040, -0.010), (0.045, 0.004), (0.044, lower * 0.45), (0.047, lower * 0.5), (0.046, lower - 0.010),
					(0.040, lower + 0.002), (0.0, lower + 0.008)]
			bands = [row("fur"), row("leather"), row("leather_dark"), row("leather"), row("leather"), row("leather")]
		else:
			prof = [(0.044, 0.0), (0.042, lower), (0.0, lower + 0.006)]
			bands = [row("leather"), row("leather")]
		geo.merge(bm, _limb(elbow, wrist, prof, segs, sharp=50, bands=bands))
		hand = geo.box(1.0, 1.0, 1.0, row("fur_dark"), SMOOTH)
		if lod == 0:
			hand = geo.subdivided(hand, 1)
		geo.fit(hand, (0.066, 0.070, 0.072))
		geo.paint(hand, row("fur_dark"), SMOOTH)
		geo.merge(bm, hand, geo.frame(fist, wrist - elbow, (0.0, 0.0, 1.0)))
	return bm


def tail(b, lod):
	"""A short bushy tail, dark at the tip, out from under the kilt behind."""
	w = b.waist_z
	pts = [(0.0, 0.100, w - 0.040), (0.0, 0.160, w - 0.070), (0.0, 0.196, w - 0.125), (0.0, 0.205, w - 0.175),
			(0.0, 0.200, w - 0.200)]
	return geo.tube(pts, [0.020, 0.036, 0.040, 0.030, 0.0], seg(lod, 7, 5), sharp=SMOOTH,
			ring_swatches=[row("fur"), row("fur"), row("fur_dark"), row("fur_dark")])


def strap(b, lod, torso_bm):
	"""A hide strap over the left shoulder to the right hip, a bone tooth
	tied on at the chest."""
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
		geo.merge(bm, geo.ribbon(pts, nrms, 0.030, 0.007, row("leather_dark"), sharp=40, embed=0.003))
	if lod == 0:
		p, n = _on_torso(b, tree, -1.25, b.shoulder_z - 0.050)
		tooth = geo.lathe([(0.012, 0.0), (0.009, 0.020), (0.0, 0.046)], 5, row("bone"), sharp=40, phase=0.0,
				cap_start=row("bone"))
		geo.merge(bm, tooth, geo.frame(p + n * 0.012, (n * 0.3 + Vector((0.0, 0.0, -1.0))), n))
	return bm


# --- arms in hand -----------------------------------------------------------

def bone_club(b, lod):
	"""A crude knotted club held up in the right fist, studded with bone
	spikes, an ochre band and a hide-wrapped grip."""
	bm = geo.new_bm()
	grip = geo.lathe([(0.0, -0.060), (0.016, -0.056), (0.017, 0.050), (0.0, 0.054)], seg(lod, 6, 4),
			row("leather_dark"), sharp=40, phase=0.0)
	geo.merge(bm, grip)
	head_prof = [(0.016, 0.040), (0.020, 0.110), (0.028, 0.170), (0.040, 0.240), (0.044, 0.290), (0.034, 0.330),
			(0.0, 0.345)]
	bands = [row("wood"), row("ochre"), row("wood"), row("wood"), row("wood"), row("wood")]
	if lod > 0:
		head_prof = [head_prof[i] for i in (0, 2, 4, 5, 6)]
		bands = [row("wood")] * 4
	club = geo.lathe(head_prof, seg(lod, 7, 5), sharp=HARD, ring_swatches=bands, phase=0.0)
	geo.merge(bm, club)
	studs = ((0.215, 5, 0.0), (0.280, 5, 0.6)) if lod == 0 else ((0.260, 4, 0.0),)
	for z, count, phase in studs:
		r = 0.040 if z > 0.25 else 0.036
		for k in range(count):
			a = phase + 2.0 * math.pi * k / count
			out = Vector((math.cos(a), math.sin(a), 0.25))
			spike = geo.lathe([(0.011, -0.006), (0.0, 0.034)], 4, row("bone"), sharp=40, phase=0.0,
					cap_start=row("bone"))
			geo.merge(bm, spike, geo.frame(Vector((math.cos(a) * r, math.sin(a) * r, z)), out, (0.0, 0.0, 1.0)))
	geo.transform(bm, geo.frame(b.r_fist, b.sword_axis, (0.2, 1.0, 0.0)))
	return bm


def hide_shield(b, lod):
	"""A crude round hide shield on the left forearm: a face in the team's
	colour scored with three bone-white claw marks, a lashed rim, a bone boss."""
	bm = geo.new_bm()
	segs = seg(lod, 11, 8)
	radius = 0.128
	dome = 0.018
	prof = [(0.0, -0.012), (radius - 0.010, -0.012), (radius, -0.004), (radius * 0.62, dome * 0.62), (0.0, dome)]
	body = geo.lathe(prof, segs, sharp=40, ring_swatches=[row("wood"), row("leather"), row("team"), row("team")],
			phase=0.0)
	geo.merge(bm, body)
	if lod == 0:
		rim = geo.lathe([(radius + 0.006, -0.010), (radius + 0.006, 0.002), (radius - 0.012, 0.006)], segs,
				row("leather"), sharp=40, phase=0.0)
		geo.merge(bm, rim)
		for k in range(4):
			a = math.pi * 0.25 + k * math.pi * 0.5
			tie = geo.box(0.016, 0.030, 0.026, row("leather_dark"), HARD)
			geo.merge(bm, tie, geo.frame(Vector((math.cos(a), math.sin(a), 0.0)) * (radius + 0.002),
					(0.0, 0.0, 1.0), (math.cos(a), math.sin(a), 0.0)))
		tree = geo.bvh(body)
		for k in (-1.0, 0.0, 1.0):
			pts, nrms = [], []
			for i in range(4):
				t = i / 3.0
				x = 0.062 + k * 0.026 - 0.030 * t
				y = 0.074 - 0.150 * t - abs(k) * 0.010
				loc, nrm = geo.project(tree, (x, y, 0.2), (0.0, 0.0, -1.0))
				pts.append(loc)
				nrms.append(nrm)
			geo.merge(bm, geo.ribbon(pts, nrms, 0.0, 0.0026, row("bone"), sharp=40, embed=0.0015,
					widths=[0.004, 0.013, 0.012, 0.003]))
	boss = geo.lathe([(0.032, dome - 0.004), (0.034, dome + 0.004), (0.020, dome + 0.018), (0.0, dome + 0.024)],
			seg(lod, 7, 5), row("bone"), sharp=40, phase=0.0)
	geo.merge(bm, boss)
	forearm_mid = (b.l_elbow + b.l_wrist) * 0.5
	centre = forearm_mid + b.shield_normal * 0.066
	geo.transform(bm, geo.frame(centre, b.shield_normal, (0.0, 0.0, 1.0)))
	return bm


# --- archer -----------------------------------------------------------------

def feather_band(b, lod):
	"""A hide band round the head under the ears, three long bone-white
	feathers with ochre tips fanned up out of it behind: the archer's mark."""
	c = b.head_centre
	z = c.z + 0.070
	sy = b.head_size.y / b.head_size.x
	r = b.head_size.x * 0.5 * 1.03
	r -= 0.012
	bm = geo.lathe([(r - 0.004, z - 0.022), (r + 0.008, z - 0.016), (r + 0.008, z + 0.016), (r - 0.004, z + 0.022)],
			seg(lod, 12, 8), row("leather_dark"), sharp=40, sy=sy)
	geo.translate(bm, (c.x, c.y, 0.0))
	for k, (lean_x, length) in enumerate(((0.60, 0.26), (0.10, 0.32), (-0.45, 0.27))):
		root = Vector((c.x + 0.040 * (k - 1), c.y + r * sy - 0.012, z + 0.006))
		d = Vector((lean_x, 0.55, 1.0)).normalized()
		steps = seg(lod, 5, 3)
		pts = [root + d * (length * i / (steps - 1)) + Vector((0.0, 0.03, 0.0)) * (i / (steps - 1)) ** 2
				for i in range(steps)]
		radii = [0.014, 0.034, 0.040, 0.032, 0.0][:steps] if lod == 0 else [0.016, 0.038, 0.0]
		swatches = [row("bone")] * (steps - 3) + [row("ochre")] * 2
		geo.merge(bm, geo.tube(pts, radii, seg(lod, 5, 4), sharp=SMOOTH, flatten=0.22, up=(1.0, 0.0, 0.0),
				ring_swatches=swatches))
	return bm


# --- berserk ----------------------------------------------------------------

def war_paint(b, lod, head_bm):
	"""Blood-red war paint: a stripe up the brow into the mane and two
	slashes down each cheek."""
	tree = geo.bvh(head_bm)
	c = b.head_centre
	bm = geo.new_bm()
	strokes = [[(0.0, c.z + 0.040 + 0.030 * i) for i in range(4)]]
	for side in (-1.0, 1.0):
		for dx in (0.0, 0.026):
			strokes.append([(side * (0.098 + dx + 0.010 * i), c.z - 0.010 - 0.026 * i) for i in range(4)])
	for stroke in strokes:
		pts, nrms = [], []
		for x, z in stroke:
			loc, nrm = geo.project(tree, (x, c.y - 1.0, z), (0.0, 1.0, 0.0))
			if loc is not None:
				pts.append(loc)
				nrms.append(nrm)
		if len(pts) > 1:
			geo.merge(bm, geo.ribbon(pts, nrms, 0.0, 0.0024, row("warpaint"), sharp=SMOOTH, embed=0.0015,
					widths=[0.018, 0.022, 0.018, 0.008][:len(pts)]))
	return bm


def beast_skull(lod, horns=True):
	"""A horned beast skull round the origin, its snout to -Y."""
	skull = geo.ellipsoid(0.050, 0.060, 0.044, seg(lod, 8, 6), seg(lod, 5, 4), row("bone"), sharp=SMOOTH)
	snout = geo.ellipsoid(0.030, 0.042, 0.026, seg(lod, 6, 5), 3, row("bone"), sharp=SMOOTH)
	geo.translate(snout, (0.0, -0.058, -0.012))
	geo.merge(skull, snout)
	for side in (-1.0, 1.0):
		geo.merge(skull, geo.disc(0.013, 0.012, seg(lod, 6, 5), row("nose"), dome=-0.002, depth=0.004),
				geo.frame((side * 0.026, -0.046, 0.010), (side * 0.5, -1.0, 0.25), (0.0, 0.0, 1.0)))
		if horns:
			horn = geo.tube([(side * 0.040, 0.0, 0.020), (side * 0.080, 0.010, 0.050), (side * 0.092, -0.020, 0.090)],
					[0.016, 0.011, 0.0], seg(lod, 6, 4), row("bone"), sharp=SMOOTH)
			geo.merge(skull, horn)
	return skull


def skull_pelt(b, lod):
	"""A pale pelt over the left shoulder, a horned beast skull on top."""
	shoulder = b.l_shoulder
	axis = Vector((0.62, 0.0, 1.0)).normalized()
	pelt = geo.lathe([(0.104, -0.030), (0.106, 0.000), (0.094, 0.030), (0.060, 0.056), (0.0, 0.066)], seg(lod, 9, 6),
			ring_swatches=[row("fur_light"), row("fur_light"), row("fur_light"), row("fur_light")], sharp=SMOOTH,
			sy=1.05, phase=0.0)
	skull = beast_skull(lod)
	geo.translate(skull, (0.0, 0.0, 0.090))
	geo.merge(pelt, skull)
	bm = geo.new_bm()
	geo.merge(bm, pelt, geo.frame(shoulder + Vector((0.012, 0.0, 0.030)), axis, (0.0, -1.0, 0.0)))
	return bm


def great_axe(b, lod):
	"""A long-hafted, double-bitted steel axe raised in the right fist,
	bone-lashed at the head."""
	bm = geo.lathe([(0.0, -0.150), (0.026, -0.146), (0.026, 0.560), (0.0, 0.570)], seg(lod, 6, 4), row("wood"),
			sharp=40, phase=0.0)
	grip = geo.lathe([(0.030, -0.050), (0.030, 0.060)], seg(lod, 6, 4), row("leather_dark"), sharp=40, phase=0.0)
	geo.merge(bm, grip)
	lash = geo.lathe([(0.032, 0.380), (0.032, 0.414)], seg(lod, 6, 4), row("bone"), sharp=40, phase=0.0)
	geo.merge(bm, lash)
	edge = [(0.0, 0.430), (0.050, 0.446), (0.140, 0.370), (0.178, 0.460), (0.176, 0.540), (0.140, 0.630),
			(0.050, 0.540), (0.0, 0.540)]
	if lod > 0:
		edge = [edge[i] for i in (0, 2, 3, 4, 5, 7)]
	for side in (-1.0, 1.0):
		blade = geo.plate([(side * x, z) for x, z in edge], 0.030, row("blade"), side=row("steel"), sharp=FLAT)
		geo.merge(bm, blade)
	cap = geo.box(0.044, 0.048, 0.120, row("steel"), 40)
	geo.translate(cap, (0.0, 0.0, 0.485))
	geo.merge(bm, cap)
	geo.transform(bm, geo.frame(b.r_fist, b.sword_axis, parts.edge_down(b.sword_axis)))
	return bm


def crude_bow(b, lod):
	"""A short, thick-limbed bow upright in the left fist, bone-tipped, an
	ochre grip wrap and a heavy pale string: chunky so it reads at range."""
	grip = b.l_fist
	steps = seg(lod, 9, 6)
	cant = math.radians(48.0)
	back = Vector((math.sin(cant), math.cos(cant), 0.0))
	pts, radii, swatches = [], [], []
	for i in range(steps):
		t = -1.0 + 2.0 * i / (steps - 1)
		pts.append(grip + back * (0.110 * t * t - 0.030 * t ** 8) + Vector((0.0, 0.0, t * 0.31)))
		radii.append(0.030 * (1.0 - 0.45 * abs(t)))
	swatches = [row("bone")] + [row("wood")] * (steps - 3) + [row("bone")]
	bm = geo.tube(pts, radii, seg(lod, 6, 4), sharp=40, flatten=0.8, up=(1.0, 0.0, 0.0), ring_swatches=swatches)
	wrap = geo.lathe([(0.032, -0.045), (0.034, 0.0), (0.032, 0.045)], seg(lod, 6, 4), row("ochre"), sharp=40, phase=0.0)
	geo.translate(wrap, grip)
	geo.merge(bm, wrap)
	geo.merge(bm, geo.tube([pts[0], pts[-1]], [0.006, 0.006], 4, row("bone"), sharp=SMOOTH))
	return bm


# --- shared -----------------------------------------------------------------

def recolour(bm, src, dst):
	"""Repaints every face of swatch `src` with swatch `dst`."""
	sw = bm.faces.layers.int.get(geo.SWATCH)
	for f in bm.faces:
		if f[sw] == row(src):
			f[sw] = row(dst)
	return bm


# --- leader -----------------------------------------------------------------

def tusk_crown(b, lod):
	"""A brass-studded ochre band round the brow, five great bone tusks
	fanned up out of it (the tallest at the front), and a brass earring."""
	c = b.head_centre
	z = c.z + 0.085
	sy = b.head_size.y / b.head_size.x
	r = b.head_size.x * 0.5 * 1.03 - 0.016
	bm = geo.lathe([(r - 0.004, z - 0.026), (r + 0.012, z - 0.020), (r + 0.012, z + 0.020), (r - 0.004, z + 0.026)],
			seg(lod, 12, 8), row("ochre"), sharp=40, sy=sy)
	geo.translate(bm, (c.x, c.y, 0.0))
	for deg, height in ((-62.0, 0.13), (-30.0, 0.17), (0.0, 0.21), (30.0, 0.17), (62.0, 0.13)):
		a = math.radians(-90.0 + deg)
		out = Vector((math.cos(a), math.sin(a) * sy, 0.0))
		root = Vector((c.x, c.y, z)) + out * (r + 0.006)
		d = (out * 0.35 + Vector((0.0, 0.0, 1.0))).normalized()
		pts = [root, root + d * height * 0.55 + out * 0.010, root + d * height + out * 0.034]
		geo.merge(bm, geo.tube(pts, [0.026, 0.020, 0.0], seg(lod, 6, 4), row("bone"), sharp=40, cap_start=row("bone")))
		if lod == 0:
			stud = geo.ellipsoid(0.012, 0.008, 0.012, 5, 3, row("brass"), sharp=SMOOTH)
			geo.translate(stud, Vector((c.x, c.y, z)) + out * (r + 0.014) + Vector((0.0, 0.0, -0.002)))
			geo.merge(bm, stud)
	ring = geo.lathe([(0.020, -0.006), (0.024, 0.0), (0.020, 0.006)], seg(lod, 8, 5), row("brass"), sharp=SMOOTH)
	geo.merge(bm, ring, geo.frame(Vector((0.150, c.y - 0.020, c.z + 0.090)), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0)))
	return bm


def falchion(b, lod, fist, axis, size=1.0):
	"""A huge crude cleaver-sword: a broad pale blade swelling to a clipped
	tip, a bone guard, a hide grip, a brass pommel."""
	k = size
	bm = geo.lathe([(0.0, -0.075), (0.018, -0.070), (0.018, 0.050), (0.0, 0.054)], seg(lod, 6, 4), row("leather_dark"),
			sharp=40, phase=0.0)
	pommel = geo.ellipsoid(0.026, 0.026, 0.022, seg(lod, 6, 4), 3, row("brass"), sharp=SMOOTH)
	geo.translate(pommel, (0.0, 0.0, -0.085))
	geo.merge(bm, pommel)
	guard = geo.tube([(-0.075, 0.0, 0.050), (0.0, 0.0, 0.062), (0.075, 0.0, 0.050)], [0.016, 0.022, 0.016],
			seg(lod, 6, 4), row("bone"), sharp=40, cap_start=row("bone"), cap_end=row("bone"))
	geo.merge(bm, guard)
	edge = [(-0.034 * k, 0.060), (0.034 * k, 0.060), (0.052 * k, 0.060 + 0.20 * k), (0.078 * k, 0.060 + 0.40 * k),
			(0.060 * k, 0.060 + 0.50 * k), (-0.034 * k, 0.060 + 0.46 * k)]
	if lod == 0:
		edge.insert(3, (0.066 * k, 0.060 + 0.32 * k))
	geo.merge(bm, geo.plate(edge, 0.026 * k, row("blade"), side=row("steel"), sharp=FLAT))
	geo.transform(bm, geo.frame(fist, axis, parts.edge_down(axis)))
	return bm


def belt_skulls(b, lod):
	"""Two small trophy skulls hung at the hips from the belt."""
	bm = geo.new_bm()
	w = b.waist_z
	for side in (-1.0, 1.0):
		skull = beast_skull(lod, horns=False)
		geo.scale(skull, 0.8, 0.8, 0.8)
		geo.rotate(skull, 90.0, 'X')
		geo.rotate(skull, side * 40.0, 'Z')
		r = b.torso_radius(w - 0.05) + 0.030
		a = math.radians(-90.0 + side * 52.0)
		geo.translate(skull, (math.cos(a) * r, math.sin(a) * r * b.torso_depth, w - 0.060))
		geo.merge(bm, skull)
	return bm


# --- shaman -----------------------------------------------------------------

def skull_staff(b, lod, below=0.32, head_scale=1.45):
	"""A gnarled staff crowned with a horned beast skull, red feathers
	fanned behind it and bone-and-bead charms hung on cords."""
	axis = b.pole_axis
	fist = b.r_fist
	top = fist + axis * 0.66
	pts = [fist - axis * below, fist, fist + axis * 0.30 + Vector((0.012, 0.0, 0.0)),
			fist + axis * 0.48 - Vector((0.010, 0.0, 0.0)), top]
	bm = geo.tube(pts, [0.022, 0.024, 0.024, 0.026, 0.030], seg(lod, 6, 5), row("wood"), sharp=40,
			cap_start=row("wood"), cap_end=row("wood"))
	wrap = geo.lathe([(0.033, -0.022), (0.035, 0.0), (0.033, 0.022)], seg(lod, 6, 4), row("warpaint"), sharp=40, phase=0.0)
	geo.merge(bm, wrap, geo.frame(top - axis * 0.03, axis, (0.0, 1.0, 0.0)))
	hd = geo.new_bm()
	skull = beast_skull(lod)
	geo.translate(skull, top + Vector((0.0, -0.006, 0.050)))
	geo.merge(hd, skull)
	for k, lean in enumerate((-0.55, 0.0, 0.55)):
		root = top + Vector((0.0, 0.040, 0.070))
		d = Vector((lean, 0.45, 1.0)).normalized()
		length = 0.16 if k == 1 else 0.13
		fpts = [root + d * (length * i / 2.0) for i in range(3)]
		geo.merge(hd, geo.tube(fpts, [0.012, 0.030, 0.0], seg(lod, 5, 4), sharp=SMOOTH, flatten=0.25, up=(1.0, 0.0, 0.0),
				ring_swatches=[row("warpaint"), row("warpaint")]))
	for side in (-1.0, 1.0):
		hang = top + Vector((side * 0.050, -0.010, 0.010))
		cord = [hang, hang + Vector((side * 0.012, 0.0, -0.060)), hang + Vector((side * 0.016, 0.0, -0.110))]
		geo.merge(hd, geo.tube(cord, [0.004, 0.004, 0.004], 4, row("leather_dark"), sharp=SMOOTH))
		bead = geo.ellipsoid(0.014, 0.014, 0.012, seg(lod, 6, 4), 3, row("ochre"), sharp=SMOOTH)
		geo.translate(bead, cord[1])
		geo.merge(hd, bead)
		tooth = geo.lathe([(0.012, 0.0), (0.009, 0.018), (0.0, 0.040)], 5, row("bone"), sharp=40, phase=0.0,
				cap_start=row("bone"))
		geo.merge(hd, tooth, geo.frame(cord[2], (0.0, 0.0, -1.0), (0.0, 1.0, 0.0)))
	geo.transform(hd, Matrix.Translation(top) @ Matrix.Scale(head_scale, 4) @ Matrix.Translation(-top))
	geo.merge(bm, hd)
	return bm
