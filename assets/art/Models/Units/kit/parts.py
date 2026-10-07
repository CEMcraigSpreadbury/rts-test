"""Figure parts: each function builds one piece of a figure as a bmesh in
figure space (origin under the base's centre, Z up, facing -Y), painted
with palette rows. `b` is a Body (proportions and pose); `lod` 0 is the full
figure, 1 the far one (fewer segments, the small details left off).

Only what the Soldier wears exists so far. A new unit adds the parts it
needs here, written the same way, and composes them in units.py.
"""
import math
import random

from mathutils import Matrix, Vector

import geo
from geo import HARD, SMOOTH, FLAT
from palette import row


def seg(lod, near, far):
	return near if lod == 0 else far


## Where the team's colour sits on the body (build.py --team-body):
## "tunic" dyes the tunic, skirt and sleeves; "tabard" keeps them undyed and
## hangs a team-coloured tabard over them (clothes.tabard).
TEAM_BODY = "tabard"


def body_cloth():
	"""The tunic's row: the team's colour, or undyed under a tabard."""
	return "team_cloth" if TEAM_BODY == "tunic" else "cloth"


class Body:
	"""Proportions and pose of a chibi infantry figure, in metres.

	Built standing on a base_height base: about 0.93 m from the base's
	underside to the helmet's top, head and helmet ~40% of the figure above
	the base, as the reference's chibi soldiers are. A recipe built without
	its base (the default, see units.py) is dropped by base_height, so the
	figure itself is the same size either way, its feet at the origin.
	"""
	base_radius = 0.30
	base_height = 0.05
	foot_x = 0.066
	hem_z = 0.175
	waist_z = 0.31
	shoulder_z = 0.47
	neck_z = 0.535
	torso_depth = 0.80
	head_centre = Vector((0.0, 0.0, 0.706))
	head_size = Vector((0.330, 0.290, 0.300))
	## The head (with its face, hair and helmet) is tipped back this much
	## round the neck, so the face still shows to a camera looking down.
	head_tilt_deg = 9.0
	neck_pivot = Vector((0.0, 0.0, 0.563))
	## Where the helmet's brim meets the dome, all round the head.
	brow_z = 0.754

	# Pose: joints of the right (sword) and left (shield) arms. The figure's
	# right is -X (it faces -Y).
	r_shoulder = Vector((-0.150, 0.0, 0.452))
	r_elbow = Vector((-0.202, 0.022, 0.360))
	r_wrist = Vector((-0.216, -0.066, 0.318))
	r_fist = Vector((-0.219, -0.098, 0.310))
	## Up the grip, from the fist toward the blade's tip.
	sword_axis = Vector((-0.22, -0.30, 1.0)).normalized()
	l_shoulder = Vector((0.150, 0.0, 0.452))
	l_elbow = Vector((0.206, 0.016, 0.360))
	l_wrist = Vector((0.216, -0.068, 0.322))
	l_fist = Vector((0.216, -0.098, 0.316))
	## Which way the shield's face looks: forward and 40 degrees out.
	shield_normal = Vector((0.643, -0.766, 0.10)).normalized()

	def torso_profile(self):
		h, w, s, n = self.hem_z, self.waist_z, self.shoulder_z, self.neck_z
		return [
			(0.157, h), (0.168, h + 0.010), (0.167, h + 0.030), (0.155, h + 0.075),
			(0.141, w), (0.149, w + 0.055), (0.153, w + 0.105),
			(0.144, s - 0.012), (0.120, s + 0.022), (0.076, n), (0.0, n + 0.004),
		]

	def torso_radius(self, z):
		prof = self.torso_profile()
		for (r0, z0), (r1, z1) in zip(prof, prof[1:]):
			if z0 <= z <= z1:
				t = (z - z0) / max(z1 - z0, 1e-9)
				return r0 + (r1 - r0) * t
		return prof[-1][0] if z > prof[-1][1] else prof[0][0]

	def head_matrix(self):
		"""Tips what is built on the head back round the neck."""
		p = self.neck_pivot
		return Matrix.Translation(p) @ Matrix.Rotation(math.radians(-self.head_tilt_deg), 4, 'X') \
				@ Matrix.Translation(-p)


# --- base -------------------------------------------------------------------

def base(b, lod):
	"""The round tabletop base: a dark foot, a team-coloured rim under a
	lighter bevel, flocked ground with (near) a pebble and two grass tufts."""
	r, h = b.base_radius, b.base_height
	prof = [(r - 0.012, 0.0), (r, 0.011), (r, h - 0.011), (r - 0.010, h)]
	bm = geo.lathe(prof, seg(lod, 26, 16), sharp=40,
			ring_swatches=[row("base_dark"), row("team"), row("team_light")], cap_end=row("flock"))
	if lod > 0:
		return bm
	rng = random.Random(7)
	peb = geo.ellipsoid(0.032, 0.026, 0.018, 5, 3, row("pebble"), sharp=40, squash_bottom=0.3)
	geo.rotate(peb, 30.0, 'Z')
	geo.translate(peb, (0.172, 0.135, h + 0.004))
	geo.merge(bm, peb)
	for (x, y), blades in (((-0.212, -0.120), 5), ((0.120, 0.215), 4)):
		geo.merge(bm, tuft(x, y, h, blades, rng))
	return bm


def tuft(x, y, z, blades, rng):
	"""A static grass tuft, as glued onto a miniature's base."""
	bm = geo.new_bm()
	for i in range(blades):
		ang = 2.0 * math.pi * i / blades + rng.uniform(-0.3, 0.3)
		lean = Vector((math.cos(ang), math.sin(ang), 0.0)) * rng.uniform(0.014, 0.024)
		root = Vector((x, y, z - 0.002)) + lean * 0.4
		tip = root + lean + Vector((0.0, 0.0, rng.uniform(0.036, 0.056)))
		w = 0.007
		corners = [root + Vector((math.cos(ang + k * 2.0944) * w, math.sin(ang + k * 2.0944) * w, 0.0)) for k in range(3)]
		vs = [bm.verts.new(c) for c in corners]
		apex = bm.verts.new(tip)
		for k in range(3):
			bm.faces.new([vs[k], vs[(k + 1) % 3], apex])
	return geo.paint(bm, row("tuft"), SMOOTH)


# --- legs and feet ----------------------------------------------------------

def boots(b, lod):
	"""Leather boots, toes a little apart, each with a sole and a turned-down cuff."""
	bm = geo.new_bm()
	z0 = b.base_height
	for side in (-1.0, 1.0):
		sections = [
			((0.0, -0.026, z0), 0.040, 0.071),
			((0.0, -0.028, z0 + 0.015), 0.046, 0.080),
			((0.0, -0.013, z0 + 0.056), 0.043, 0.061),
			((0.0, 0.000, z0 + 0.074), 0.040, 0.042),
			((0.0, 0.000, z0 + 0.074), 0.049, 0.049),
			((0.0, 0.000, z0 + 0.093), 0.049, 0.049),
			((0.0, 0.000, z0 + 0.096), 0.038, 0.038),
		]
		bands = [row("sole"), row("boot"), row("boot"), row("leather"), row("leather"), row("leather")]
		if lod > 0:
			sections = [sections[i] for i in (0, 1, 2, 4, 5, 6)]
			bands = [row("sole"), row("boot"), row("boot"), row("leather"), row("leather")]
		boot = geo.loft(sections, seg(lod, 8, 6), sharp=48, ring_swatches=bands)
		geo.rotate(boot, side * 9.0, 'Z')
		geo.translate(boot, (side * b.foot_x, 0.0, 0.0))
		geo.merge(bm, boot)
	return bm


def legs(b, lod):
	bm = geo.new_bm()
	for side in (-1.0, 1.0):
		leg = geo.lathe([(0.040, b.base_height + 0.085), (0.046, b.hem_z + 0.06)], seg(lod, 8, 5), row("cloth_dark"))
		geo.translate(leg, (side * b.foot_x, 0.0, 0.0))
		geo.merge(bm, leg)
	return bm


# --- body -------------------------------------------------------------------

def tunic(b, lod):
	"""A padded gambeson flaring into a skirt, its hem trimmed in team colour."""
	prof = b.torso_profile()
	bands = [row("team_dark"), row("team_dark")] + [row(body_cloth())] * (len(prof) - 3)
	if lod > 0:
		keep = (0, 1, 2, 4, 6, 8, 9, 10)
		prof = [prof[i] for i in keep]
		bands = [bands[i] for i in keep[:-1]]
	return geo.lathe(prof, seg(lod, 12, 8), sharp=SMOOTH, sy=b.torso_depth, ring_swatches=bands,
			cap_start=row("cloth_dark"))


def skirt(b, lod):
	"""An outer skirt from under the belt, flaring over the gambeson to just
	above its team-coloured hem: the second layer of the tunic."""
	w, h = b.waist_z, b.hem_z
	prof = [(0.138, w - 0.010), (0.150, w - 0.060), (0.174, h + 0.044), (0.162, h + 0.034)]
	return geo.lathe(prof, seg(lod, 12, 8), row(body_cloth()), sharp=50, sy=b.torso_depth)


def belt(b, lod):
	"""A belt round the waist with a brass buckle: a frame round the dark strap."""
	w = b.waist_z
	r = b.torso_radius(w)
	prof = [(r - 0.006, w - 0.017), (r + 0.008, w - 0.013), (r + 0.008, w + 0.013), (r - 0.006, w + 0.017)]
	bm = geo.lathe(prof, seg(lod, 12, 8), row("leather_dark"), sharp=40, sy=b.torso_depth)
	front = -(r + 0.008) * b.torso_depth
	buckle = geo.box(0.048, 0.012, 0.042, row("brass"), HARD, bevel=0.0035 if lod == 0 else 0.0)
	geo.translate(buckle, (0.0, front - 0.004, w))
	geo.merge(bm, buckle)
	if lod == 0:
		inner = geo.box(0.026, 0.006, 0.022, row("leather_dark"), HARD)
		geo.translate(inner, (0.0, front - 0.0105, w))
		geo.merge(bm, inner)
	return bm


def _on_torso(b, tree, theta, z):
	"""The point on the tunic at angle `theta` and height `z`, and its normal."""
	far = Vector((math.cos(theta) * 0.6, math.sin(theta) * 0.6, z))
	loc, nrm = geo.project(tree, far, Vector((-far.x, -far.y, 0.0)))
	if loc is None:
		r = b.torso_radius(z)
		loc = Vector((math.cos(theta) * r, math.sin(theta) * r * b.torso_depth, z))
		nrm = Vector((math.cos(theta), math.sin(theta), 0.0))
	return loc, nrm


def baldric(b, lod, torso_bm):
	"""The sword belt: over the right shoulder and down to the left hip, front
	and back."""
	tree = geo.bvh(torso_bm)
	bm = geo.new_bm()
	steps = seg(lod, 7, 4)
	for start, end in (((-2.30, b.shoulder_z + 0.005), (-0.70, b.waist_z - 0.005)),
			((2.30, b.shoulder_z + 0.005), (0.70, b.waist_z - 0.005))):
		pts, nrms = [], []
		for i in range(steps):
			t = i / (steps - 1)
			p, n = _on_torso(b, tree, start[0] + (end[0] - start[0]) * t, start[1] + (end[1] - start[1]) * t)
			pts.append(p)
			nrms.append(n)
		geo.merge(bm, geo.ribbon(pts, nrms, 0.032, 0.007, row("leather"), sharp=40, embed=0.003))
	return bm


def scabbard(b, lod):
	"""The empty scabbard hanging at the left hip, steel at mouth and tip."""
	top = Vector((0.150, 0.050, b.waist_z - 0.008))
	tip = Vector((0.208, 0.168, b.hem_z - 0.060))
	length = (top - tip).length
	prof = [(0.0, 0.0), (1.0, 0.035), (1.0, length - 0.035), (1.1, length - 0.032), (1.1, length)]
	bands = [row("steel"), row("leather_dark"), row("steel"), row("steel")]
	bm = geo.lathe(prof, 6, sharp=40, sx=0.021, sy=0.011, ring_swatches=bands, phase=0.0, cap_end=row("lining"))
	geo.transform(bm, geo.frame(tip, top - tip, (1.0, 0.0, 0.0)))
	return bm


def pouch(b, lod):
	"""A small leather pouch on the right hip, behind."""
	bm = geo.box(0.058, 0.034, 0.048, row("leather"), 40, bevel=0.008)
	flap = geo.box(0.062, 0.038, 0.016, row("leather_dark"), 40)
	geo.translate(flap, (0.0, 0.0, 0.020))
	geo.merge(bm, flap)
	geo.rotate(bm, -48.0, 'Z')
	geo.translate(bm, (-0.124, 0.080, b.waist_z - 0.045))
	return bm


def collar(b, lod):
	"""A low mail collar tucked under the chin, so the head sits down on the
	shoulders; its facets hard so it reads as rings rather than cloth."""
	n = b.neck_z
	prof = [(0.126, n - 0.030), (0.118, n - 0.010), (0.100, n + 0.008), (0.088, n + 0.026)]
	return geo.lathe(prof, seg(lod, 10, 7), row("mail"), sharp=24, sy=0.92)


def pauldrons(b, lod, main="leather", lame_row="leather_dark"):
	"""Layered leather shoulder guards, a brass rivet on each (or steel ones,
	given steel rows)."""
	bm = geo.new_bm()
	segs = seg(lod, 8, 6)
	for side, shoulder in ((-1.0, b.r_shoulder), (1.0, b.l_shoulder)):
		axis = Vector((side * 0.62, 0.0, 1.0)).normalized()
		dome_prof = [(0.084, 0.0), (0.078, 0.026), (0.052, 0.050), (0.0, 0.060)]
		piece = geo.lathe(dome_prof, segs, row(main), sharp=50, sy=0.94, phase=0.0)
		if lod == 0:
			lame = geo.lathe([(0.072, -0.016), (0.090, -0.026), (0.093, -0.008), (0.078, 0.006)], segs,
					row(lame_row), sharp=40, sy=0.94, phase=0.0)
			geo.merge(piece, lame)
			rivet = geo.ellipsoid(0.011, 0.011, 0.008, 5, 2, row("brass"), sharp=40)
			geo.translate(rivet, (0.0, 0.0, 0.058))
			geo.merge(piece, rivet)
		## Up on the shoulder, its top about level with the collar.
		at = shoulder + Vector((side * 0.012, 0.0, 0.034))
		geo.merge(bm, piece, geo.frame(at, axis, (0.0, -1.0, 0.0)))
	return bm


def _limb(p0, p1, prof, segments, swatch=0, sharp=SMOOTH, bands=None):
	"""A tube from p0 toward p1 turned from `prof` [(r, distance along)]."""
	bm = geo.lathe(prof, segments, swatch, sharp, phase=0.0, ring_swatches=bands)
	geo.transform(bm, geo.frame(p0, p1 - p0, (0.0, -1.0, 0.0)))
	return bm


def arms(b, lod):
	"""Padded sleeves, leather bracers flaring at the wrist, gloved fists."""
	bm = geo.new_bm()
	segs = seg(lod, 7, 5)
	for shoulder, elbow, wrist, fist in ((b.r_shoulder, b.r_elbow, b.r_wrist, b.r_fist),
			(b.l_shoulder, b.l_elbow, b.l_wrist, b.l_fist)):
		upper = (elbow - shoulder).length
		geo.merge(bm, _limb(shoulder, elbow, [(0.048, -0.01), (0.054, 0.006), (0.047, upper),
				(0.034, upper + 0.022), (0.0, upper + 0.030)], segs, row(body_cloth())))
		lower = (wrist - elbow).length
		if lod == 0:
			prof = [(0.038, -0.010), (0.044, 0.004), (0.040, lower - 0.022), (0.049, lower - 0.016),
					(0.049, lower + 0.004), (0.0, lower + 0.008)]
			bands = [row("leather")] * 2 + [row("leather_dark")] * 3
		else:
			prof = [(0.044, 0.0), (0.042, lower), (0.0, lower + 0.006)]
			bands = [row("leather"), row("leather_dark")]
		geo.merge(bm, _limb(elbow, wrist, prof, segs, sharp=40, bands=bands))
		hand = geo.box(1.0, 1.0, 1.0, row("leather_dark"), 40)
		if lod == 0:
			hand = geo.subdivided(hand, 1)
		geo.fit(hand, (0.064, 0.068, 0.070))
		geo.paint(hand, row("leather_dark"), 50)
		geo.merge(bm, hand, geo.frame(fist, wrist - elbow, (0.0, 0.0, 1.0)))
	return bm


# --- head -------------------------------------------------------------------

def head(b, lod):
	"""A soft rounded-box chibi head, the jaw a little narrower than the
	cheeks. What the helmet hides is left out."""
	bm = geo.box(1.0, 1.0, 1.0, row("skin"), SMOOTH)
	bm = geo.subdivided(bm, seg(lod, 2, 1))
	geo.fit(bm, b.head_size, b.head_centre)
	c = b.head_centre
	half_h = b.head_size.z * 0.5
	for v in bm.verts:
		below = (c.z - v.co.z) / half_h
		if below > 0.0:
			v.co.x = c.x + (v.co.x - c.x) * (1.0 - 0.15 * below * below)
			v.co.y = c.y + (v.co.y - c.y) * (1.0 - 0.05 * below)
	geo.paint(bm, row("skin"), SMOOTH)
	return geo.delete_faces(bm, lambda f: all(v.co.z > b.brow_z + 0.02 for v in f.verts))


def face(b, lod, head_bm):
	"""Big dark eyes with a glint, a small smile, a button nose and a touch
	of blush, each laid onto the head's own surface."""
	tree = geo.bvh(head_bm)
	bm = geo.new_bm()

	def place(x, z, part, lift=0.0):
		loc, nrm = geo.project(tree, (x, -1.0, z), (0.0, 1.0, 0.0))
		if loc is None:
			return
		geo.merge(bm, part, geo.frame(loc + nrm * lift, nrm, (0.0, 0.0, 1.0)))

	eye_z = b.head_centre.z - 0.014
	for side in (-1.0, 1.0):
		place(side * 0.066, eye_z, geo.disc(0.021, 0.029, seg(lod, 10, 6), row("eye"), dome=0.004))
		if lod == 0:
			place(side * 0.066 + 0.008, eye_z + 0.011, geo.disc(0.0068, 0.0068, 5, row("glint"), dome=0.0015,
					depth=0.0015, simple=True), lift=0.0045)
			place(side * 0.104, eye_z - 0.046, geo.disc(0.017, 0.009, 7, row("blush"), dome=0.001, depth=0.002,
					simple=True))
	if lod == 0:
		place(0.0, eye_z - 0.036, geo.ellipsoid(0.010, 0.007, 0.006, 5, 2, row("skin")), lift=0.001)
		pts, nrms = [], []
		for i in range(5):
			t = (i / 4.0) * 2.0 - 1.0
			loc, nrm = geo.project(tree, (t * 0.019, -1.0, eye_z - 0.064 + 0.0065 * t * t), (0.0, 1.0, 0.0))
			pts.append(loc)
			nrms.append(nrm)
		geo.merge(bm, geo.ribbon(pts, nrms, 0.0, 0.0022, row("mouth"), sharp=SMOOTH, embed=0.002,
				widths=[0.004, 0.0068, 0.0076, 0.0068, 0.004]))
	return bm


def hair(b, lod, row_name="hair"):
	"""Pale hair falling from under the helmet over the ears to the jaw, and
	a short mass of it at the back."""
	bm = geo.new_bm()
	c = b.head_centre
	half_w = b.head_size.x * 0.5
	for side in (-1.0, 1.0):
		prof = [(0.0, 0.0), (0.55, 0.028), (0.95, 0.075), (1.0, 0.115), (0.7, 0.150), (0.0, 0.158)]
		if lod > 0:
			prof = [prof[i] for i in (0, 2, 3, 5)]
		mass = geo.lathe(prof, seg(lod, 7, 5), row(row_name), sharp=SMOOTH, sx=0.022, sy=0.070, phase=0.0)
		geo.rotate(mass, side * -6.0, 'Y')
		geo.translate(mass, (side * (half_w - 0.006), 0.006, b.brow_z - 0.172))
		geo.merge(bm, mass)
	back = geo.ellipsoid(0.150, 0.070, 0.085, seg(lod, 9, 6), seg(lod, 4, 3), row(row_name), sharp=SMOOTH)
	geo.translate(back, (0.0, c.y + 0.092, c.z - 0.004))
	geo.merge(bm, back)
	return bm


def kettle_helmet(b, lod, paint="steel", edge="trim"):
	"""A plain steel kettle helmet: a rounded dome on a darker band, a ridge
	over the crown, a brim narrow over the eyes and swept lower and wider
	behind with a dark edge, a brass finial and a brass stud."""
	bm = geo.new_bm()
	segs = seg(lod, 14, 10)
	z = b.brow_z
	sy = 0.95
	dome_prof = [(0.168, z + 0.004), (0.172, z + 0.036), (0.161, z + 0.080), (0.134, z + 0.118),
			(0.088, z + 0.146), (0.0, z + 0.158)]
	if lod > 0:
		dome_prof = [dome_prof[i] for i in (0, 1, 3, 5)]
	dome = geo.lathe(dome_prof, segs, row(paint), sharp=50, sy=sy, cap_start=row("lining"))
	geo.merge(bm, dome)
	if lod == 0:
		band = geo.lathe([(0.176, z - 0.004), (0.177, z + 0.018), (0.168, z + 0.026)], segs, row(edge), sharp=40,
				sy=sy)
		geo.merge(bm, band)

	def brim_warp(theta, r, zz):
		back = max(0.0, math.sin(theta))
		front = max(0.0, -math.sin(theta))
		if r > 0.18:
			r += 0.026 * back ** 1.5 - 0.010 * front ** 2
			zz -= 0.026 * back ** 1.5
		return (r * math.cos(theta), r * math.sin(theta) * sy, zz)

	brim = geo.lathe([(0.168, z - 0.014), (0.206, z - 0.024), (0.206, z - 0.014), (0.168, z + 0.002)], segs,
			sharp=40, warp=brim_warp, ring_swatches=[row(paint), row(edge), row(paint)])
	geo.merge(bm, brim)

	# One steel ridge over the crown, front to back.
	tree = geo.bvh(dome)
	steps = seg(lod, 15, 7)
	centre = Vector((0.0, 0.0, z + 0.02))
	pts, nrms = [], []
	for i in range(steps):
		a = math.pi * i / (steps - 1)
		out = Vector((0.0, -math.cos(a) * sy, math.sin(a)))
		loc, nrm = geo.project(tree, centre + out * 0.6, -out)
		if loc is None or loc.z < z + 0.024:
			continue
		pts.append(loc)
		nrms.append(nrm)
	geo.merge(bm, geo.ribbon(pts, nrms, 0.024, 0.0075, row("trim"), sharp=40, embed=0.003))
	finial = geo.ellipsoid(0.018, 0.018, 0.015, seg(lod, 6, 5), 3, row("brass"), sharp=40)
	geo.translate(finial, (0.0, 0.0, z + 0.162))
	geo.merge(bm, finial)
	if lod == 0:
		# A brass stud on the band over the brow.
		stud = geo.lathe([(0.013, -0.003), (0.011, 0.004), (0.0, 0.008)], 6, row("brass"), sharp=50, phase=0.0)
		geo.merge(bm, stud, geo.frame((0.0, -0.177 * sy, z + 0.009), (0.0, -1.0, 0.0), (0.0, 0.0, 1.0)))
	geo.translate(bm, (b.head_centre.x, b.head_centre.y + 0.004, 0.0))
	return bm


# --- arms and armour in hand ------------------------------------------------

## RULE: every edged weapon's cutting edge faces the ground. Build the blade
## along local +Z with its edge toward local `edge` (in local XY), then place
## it with geo.frame(fist, axis, edge_down(axis, edge)): the edge turns round
## the grip to point as near straight down as the grip's axis allows.
def edge_down(axis, edge=(1.0, 0.0)):
	"""The y_hint for geo.frame that turns a blade's local `edge` direction
	toward the ground round `axis`."""
	z = Vector(axis).normalized()
	d = Vector((0.0, 0.0, -1.0))
	d = d - z * d.dot(z)
	if d.length < 1e-4:
		d = Vector((0.0, -1.0, 0.0)) + z * z.y
	d.normalize()
	w = z.cross(d)
	t = math.atan2(edge[1], edge[0])
	return w * math.cos(t) + d * math.sin(t)


def arming_sword(b, lod):
	"""A broad arming sword held up in the right fist: a lozenge blade with a
	dark fuller, brass crossguard, leather grip and a wheel pommel."""
	bm = geo.new_bm()
	blade_len = 0.330
	guard_at = 0.044
	prof = [(1.0, 0.0), (1.0, blade_len * 0.72), (0.86, blade_len * 0.88), (0.0, blade_len)]

	def blade_warp(theta, r, z):
		w = 0.058 if z < 1e-6 else (0.052 if z <= blade_len * 0.73 else 0.044)
		return (math.cos(theta) * w * 0.5 * r, math.sin(theta) * 0.0072 * r, z)

	blade = geo.lathe(prof, 4, row("blade"), sharp=FLAT, warp=blade_warp, phase=0.0, cap_start=row("blade"))
	geo.translate(blade, (0.0, 0.0, guard_at + 0.010))
	geo.merge(bm, blade)
	if lod == 0:
		for side in (-1.0, 1.0):
			pts = [Vector((0.0, side * 0.0068, guard_at + 0.030)), Vector((0.0, side * 0.0068, guard_at + 0.215))]
			geo.merge(bm, geo.ribbon(pts, [Vector((0.0, side, 0.0))] * 2, 0.011, 0.0006, row("steel"), sharp=FLAT,
					embed=0.0012))
	guard = geo.box(0.132, 0.026, 0.022, row("brass"), 40, bevel=0.005 if lod == 0 else 0.0)
	for v in guard.verts:
		v.co.z += 2.4 * v.co.x * v.co.x
	geo.translate(guard, (0.0, 0.0, guard_at))
	geo.merge(bm, guard)
	grip = geo.lathe([(0.0125, -0.050), (0.0140, -0.012), (0.0125, guard_at)], seg(lod, 6, 4), row("leather_dark"),
			sharp=40, phase=0.0)
	geo.merge(bm, grip)
	wheel = geo.lathe([(0.0, -0.009), (0.020, -0.009), (0.023, 0.0), (0.020, 0.009), (0.0, 0.009)],
			seg(lod, 6, 5), row("brass"), sharp=40, phase=0.0)
	geo.rotate(wheel, 90.0, 'X')
	geo.translate(wheel, (0.0, 0.0, -0.068))
	geo.merge(bm, wheel)
	geo.transform(bm, geo.frame(b.r_fist, b.sword_axis, edge_down(b.sword_axis)))
	return bm


def round_shield(b, lod):
	"""A round shield on the left forearm: a gently domed face in team
	colour with a cream cross pattee, a steel rim, a brass boss, wood behind."""
	bm = geo.new_bm()
	segs = seg(lod, 16, 10)
	radius = 0.124
	dome = 0.020
	face_prof = [(0.0, -0.012), (radius - 0.010, -0.012), (radius, -0.006), (radius, 0.001),
			(radius * 0.60, dome * 0.62), (0.0, dome)]
	edge = row("wood") if lod == 0 else row("steel")
	bands = [row("wood"), row("wood"), edge, row("team"), row("team")]
	body = geo.lathe(face_prof, segs, sharp=40, ring_swatches=bands, phase=0.0)
	geo.merge(bm, body)
	if lod == 0:
		rim = geo.lathe([(radius + 0.0045, -0.010), (radius + 0.004, 0.002), (radius - 0.015, 0.0055)], segs,
				row("steel"), sharp=40, phase=0.0)
		geo.merge(bm, rim)
	boss = geo.lathe([(0.044, dome - 0.004), (0.046, dome + 0.002), (0.030, dome + 0.018), (0.0, dome + 0.027)],
			seg(lod, 8, 6), row("brass"), sharp=40, phase=0.0)
	geo.merge(bm, boss)
	if lod == 0:
		tree = geo.bvh(body)
		for k in range(4):
			ang = k * math.pi / 2.0
			pts, nrms, widths = [], [], []
			for i in range(3):
				t = i / 2.0
				r = 0.044 + (radius - 0.020 - 0.044) * t
				loc, nrm = geo.project(tree, (math.cos(ang) * r, math.sin(ang) * r, 0.2), (0.0, 0.0, -1.0))
				pts.append(loc)
				nrms.append(nrm)
				widths.append(0.018 + 0.032 * t * t)
			geo.merge(bm, geo.ribbon(pts, nrms, 0.0, 0.0024, row("cream"), sharp=40, embed=0.0015, widths=widths))
	forearm_mid = (b.l_elbow + b.l_wrist) * 0.5
	centre = forearm_mid + b.shield_normal * 0.066
	geo.transform(bm, geo.frame(centre, b.shield_normal, (0.0, 0.0, 1.0)))
	return bm
