"""Robots parts: clockwork tin toys, wound with a key.

The race reads apart by its tin: rounded box heads of lithographed silver
tin with the shared big dark eyes on the front and a grille for a mouth,
ear bolts and an antenna; can bodies banded in rivets; ribbed accordion
arms; stubby piston legs on chunky rubber-soled feet; and on every back a
big brass wind-up key. Accents are cream and orange enamel, glowing amber
lamps, brass gears.

The team's colour is enamel paint (team_paint) on what a toy robot would
have painted: the chest panel, the shako, the antenna ball, the Hound's
saddle plate. Head pieces are built upright and tipped back by the recipe.
"""
import math

from mathutils import Matrix, Vector

import geo
from geo import FLAT, HARD, SMOOTH
from palette import row
import parts
from parts import seg, _limb
import gear


def _over_head(b, bm):
	geo.translate(bm, (b.head_centre.x, b.head_centre.y, 0.0))
	return bm


# --- head -------------------------------------------------------------------

def tin_head(b, lod, k=1.0):
	"""A rounded tin box head, a little wider than tall, its corners soft."""
	bm = geo.box(1.0, 1.0, 1.0, row("skin"), SMOOTH)
	bm = geo.subdivided(bm, seg(lod, 2, 1))
	size = Vector((b.head_size.x * 1.04 * k, b.head_size.y * 0.98 * k, b.head_size.z * 0.92 * k))
	geo.fit(bm, size, b.head_centre)
	# Squarer than a human's: push the rounded box out toward its corners.
	c = b.head_centre
	for v in bm.verts:
		d = v.co - c
		for i, half in enumerate((size.x * 0.5, size.y * 0.5, size.z * 0.5)):
			t = d[i] / half
			d[i] = half * math.copysign(min(1.0, abs(t) ** 0.78), t)
		v.co = c + d
	return geo.paint(bm, row("skin"), SMOOTH)


def tin_face(b, lod, head_bm):
	"""The shared big dark eyes with glints and blush, set in brass rims like
	lamp lenses, and a slotted grille for a mouth."""
	tree = geo.bvh(head_bm)
	bm = geo.new_bm()

	def place(x, z, part, lift=0.0):
		loc, nrm = geo.project(tree, (x, -1.0, z), (0.0, 1.0, 0.0))
		if loc is None:
			return
		geo.merge(bm, part, geo.frame(loc + nrm * lift, nrm, (0.0, 0.0, 1.0)))

	eye_z = b.head_centre.z - 0.006
	for side in (-1.0, 1.0):
		place(side * 0.068, eye_z, geo.disc(0.034, 0.040, seg(lod, 12, 8), row("brass"), dome=0.004, depth=0.003))
		place(side * 0.068, eye_z, geo.disc(0.024, 0.031, seg(lod, 10, 6), row("eye"), dome=0.006), lift=0.003)
		if lod == 0:
			place(side * 0.068 + 0.009, eye_z + 0.012, geo.disc(0.0075, 0.0075, 5, row("glint"), dome=0.0015,
					depth=0.0015, simple=True), lift=0.0095)
			place(side * 0.112, eye_z - 0.050, geo.disc(0.018, 0.010, 7, row("blush"), dome=0.001, depth=0.002,
					simple=True))
	grille = geo.box(0.100, 0.010, 0.036, row("mouth"), HARD, bevel=0.004 if lod == 0 else 0.0)
	place(0.0, eye_z - 0.068, grille)
	if lod == 0:
		for x in (-0.026, 0.0, 0.026):
			slot = geo.box(0.008, 0.010, 0.022, row("steel"), HARD)
			place(x, eye_z - 0.068, slot, lift=0.003)
	return bm


def ear_bolts(b, lod):
	"""A round brass-capped bolt on each side of the head, like ears."""
	bm = geo.new_bm()
	c = b.head_centre
	half = b.head_size.x * 0.52
	for side in (-1.0, 1.0):
		geo.merge(bm, geo.tube([Vector((side * (half - 0.010), c.y, c.z)), Vector((side * (half + 0.026), c.y, c.z))],
				[0.040, 0.040], seg(lod, 10, 7), row("plate_dark"), sharp=SMOOTH, cap_end=row("plate_dark")))
		cap = geo.ellipsoid(0.014, 0.030, 0.030, seg(lod, 8, 6), 4, row("brass"), sharp=SMOOTH)
		geo.translate(cap, (side * (half + 0.030), c.y, c.z))
		geo.merge(bm, cap)
	return bm


def antenna(b, lod, ball="team_paint", height=0.16, top=None):
	"""A thin antenna on a brass collar, a ball (or a lamp) on its tip."""
	z = b.head_centre.z + b.head_size.z * 0.44
	bm = geo.lathe([(0.030, z - 0.010), (0.032, z + 0.010), (0.016, z + 0.022)], seg(lod, 8, 6), row("brass"),
			sharp=40, phase=0.0)
	geo.merge(bm, geo.tube([Vector((0.0, 0.0, z + 0.016)), Vector((0.0, 0.004, z + height))], [0.007, 0.006],
			seg(lod, 5, 4), row("steel"), sharp=SMOOTH))
	knob = geo.ellipsoid(0.030, 0.030, 0.030, seg(lod, 9, 6), seg(lod, 5, 4), row(ball), sharp=SMOOTH)
	geo.translate(knob, (0.0, 0.004, z + height + 0.020))
	geo.merge(bm, knob)
	return _over_head(b, bm)


def shako(b, lod):
	"""A toy soldier's tall shako in the team's enamel: a flat-topped drum,
	a brass plate, a peaked visor and a cream pom."""
	z = b.head_centre.z + b.head_size.z * 0.40
	bm = geo.lathe([(0.150, z - 0.020), (0.156, z + 0.000), (0.168, z + 0.150), (0.170, z + 0.160), (0.0, z + 0.164)],
			seg(lod, 14, 10), row("team_paint"), sharp=40, sy=0.92, cap_start=row("lining"))
	band = geo.lathe([(0.158, z - 0.024), (0.164, z - 0.016), (0.164, z + 0.016), (0.156, z + 0.024)],
			seg(lod, 14, 10), row("plate_dark"), sharp=40, sy=0.92)
	geo.merge(bm, band)
	top = geo.lathe([(0.172, z + 0.150), (0.178, z + 0.158), (0.172, z + 0.170)], seg(lod, 14, 10), row("brass"),
			sharp=40, sy=0.92)
	geo.merge(bm, top)
	visor = geo.ellipsoid(0.130, 0.070, 0.012, seg(lod, 12, 8), 3, row("plate_dark"), sharp=40)
	geo.delete_faces(visor, lambda f: f.calc_center_median().y > 0.0)
	geo.rotate(visor, -12.0, 'X')
	geo.translate(visor, (0.0, -0.130, z - 0.016))
	geo.merge(bm, visor)
	plate = geo.plate([(-0.044, 0.0), (0.044, 0.0), (0.050, 0.060), (0.0, 0.090), (-0.050, 0.060)], 0.010,
			row("brass"), sharp=40)
	geo.transform(plate, geo.orient(Vector((0.0, -0.156, z + 0.040)), (0.0, -1.0, 0.05)))
	geo.merge(bm, plate)
	pom = geo.ellipsoid(0.034, 0.034, 0.044, seg(lod, 8, 6), 4, row("cloth"), sharp=SMOOTH)
	geo.translate(pom, (0.0, -0.090, z + 0.200))
	geo.merge(bm, pom)
	return _over_head(b, bm)


def top_hat(b, lod):
	"""A tall chrome top hat with the team's enamel band and a curled brim."""
	z = b.head_centre.z + b.head_size.z * 0.42
	sy = 0.94
	bm = geo.lathe([(0.130, z), (0.134, z + 0.200), (0.150, z + 0.250), (0.0, z + 0.254)], seg(lod, 14, 10),
			row("plate_dark"), sharp=40, sy=sy, cap_start=row("lining"))
	band = geo.lathe([(0.134, z + 0.010), (0.140, z + 0.016), (0.140, z + 0.060), (0.134, z + 0.066)],
			seg(lod, 14, 10), row("team_paint"), sharp=40, sy=sy)
	geo.merge(bm, band)

	def curl(theta, r, zz):
		side = abs(math.cos(theta))
		return (r * math.cos(theta), r * math.sin(theta) * sy, zz + 0.040 * side * max(0.0, (r - 0.150) / 0.08))

	brim = geo.lathe([(0.120, z - 0.006), (0.240, z - 0.012), (0.240, z + 0.004), (0.120, z + 0.010)],
			seg(lod, 20, 12), row("plate_dark"), sharp=40, warp=curl)
	geo.merge(bm, brim)
	return _over_head(b, bm)


def monocle(b, lod, head_bm, side=1.0):
	"""A brass monocle ring over one eye, an amber lens, a little chain."""
	tree = geo.bvh(head_bm)
	eye_z = b.head_centre.z - 0.006
	loc, nrm = geo.project(tree, (side * 0.068, -1.0, eye_z), (0.0, 1.0, 0.0))
	bm = geo.new_bm()
	if loc is None:
		return bm
	ring = geo.lathe([(0.040, -0.004), (0.046, 0.0), (0.040, 0.008)], seg(lod, 12, 8), row("brass"), sharp=40,
			phase=0.0)
	geo.merge(bm, ring, geo.frame(loc + nrm * 0.012, nrm, (0.0, 0.0, 1.0)))
	if lod == 0:
		pts = [loc + nrm * 0.012 + Vector((side * 0.030, 0.0, -0.030)), loc + Vector((side * 0.060, 0.020, -0.090)),
				loc + Vector((side * 0.070, 0.040, -0.150))]
		geo.merge(bm, geo.tube(pts, [0.004] * 3, 4, row("brass"), sharp=SMOOTH))
	return bm


def tesla_crown(b, lod):
	"""A tesla coil standing from the crown: brass rings tapering up a
	ceramic post to a crackling violet ball."""
	z = b.head_centre.z + b.head_size.z * 0.44
	bm = geo.lathe([(0.050, z - 0.010), (0.052, z + 0.020), (0.020, z + 0.040), (0.018, z + 0.180), (0.0, z + 0.184)],
			seg(lod, 8, 6), row("cloth"), sharp=40, phase=0.0)
	for k in range(4):
		zz = z + 0.050 + k * 0.034
		r = 0.060 - k * 0.010
		ring = geo.lathe([(r - 0.014, zz - 0.008), (r, zz), (r - 0.014, zz + 0.008)], seg(lod, 10, 7), row("brass"),
				sharp=SMOOTH, phase=0.0)
		geo.merge(bm, ring)
	ball = geo.ellipsoid(0.044, 0.044, 0.044, seg(lod, 10, 7), seg(lod, 5, 4), row("arcane"), sharp=SMOOTH)
	geo.translate(ball, (0.0, 0.0, z + 0.220))
	geo.merge(bm, ball)
	if lod == 0:
		for k in range(4):
			a = k * math.pi / 2.0 + 0.4
			pts = [Vector((math.cos(a) * 0.040, math.sin(a) * 0.040, z + 0.220)),
					Vector((math.cos(a) * 0.080, math.sin(a) * 0.080, z + 0.250)),
					Vector((math.cos(a) * 0.100, math.sin(a) * 0.100, z + 0.210)),
					Vector((math.cos(a) * 0.130, math.sin(a) * 0.130, z + 0.240))]
			geo.merge(bm, geo.tube(pts, [0.008, 0.007, 0.006, 0.0], 4, row("arcane"), sharp=FLAT))
	return _over_head(b, bm)


def radar_dish(b, lod):
	"""A little radar dish on a stalk, tilted up and forward, an amber
	lamp at its centre."""
	z = b.head_centre.z + b.head_size.z * 0.44
	bm = geo.tube([Vector((0.0, 0.020, z)), Vector((0.0, 0.020, z + 0.080))], [0.012, 0.010], seg(lod, 6, 4),
			row("steel"), sharp=SMOOTH)
	dish = geo.lathe([(0.0, 0.0), (0.050, 0.010), (0.090, 0.040), (0.096, 0.048), (0.084, 0.044), (0.0, 0.008)],
			seg(lod, 14, 9), row("cloth"), sharp=50, phase=0.0)
	lamp = geo.ellipsoid(0.018, 0.018, 0.018, 6, 4, row("crystal"), sharp=SMOOTH)
	geo.translate(lamp, (0.0, 0.0, 0.030))
	geo.merge(dish, lamp)
	geo.transform(dish, geo.frame(Vector((0.0, 0.020, z + 0.090)), Vector((0.0, -0.6, 1.0)), (0.0, 0.0, 1.0)))
	geo.merge(bm, dish)
	return _over_head(b, bm)


# --- body -------------------------------------------------------------------

def tin_torso(b, lod, panel=True, gauge=True):
	"""A tin can body, rounded at the shoulders, rings of rivets at its hem
	and chest, a cream enamel collar ring; on the front a panel in the
	team's enamel with a pressure gauge."""
	h, w, s, n = b.hem_z, b.waist_z, b.shoulder_z, b.neck_z
	prof = b.torso_profile()
	segs = seg(lod, 12, 8)
	bm = geo.lathe(prof, segs, row("skin"), sharp=SMOOTH, sy=b.torso_depth, cap_start=row("plate_dark"))
	hem = geo.lathe([(b.torso_radius(h + 0.004) + 0.010, h - 0.004), (b.torso_radius(h + 0.004) + 0.016, h + 0.010),
			(b.torso_radius(h + 0.020) + 0.010, h + 0.026)], segs, row("plate_dark"), sharp=40, sy=b.torso_depth)
	geo.merge(bm, hem)
	collar = geo.lathe([(0.096, n - 0.034), (0.104, n - 0.020), (0.100, n + 0.004), (0.088, n + 0.014)],
			seg(lod, 10, 7), row("cloth"), sharp=40, sy=0.92)
	geo.merge(bm, collar)
	if lod == 0:
		for z in (h + 0.044, w + 0.120):
			r = b.torso_radius(z)
			for k in range(10):
				a = -math.pi / 2.0 + (k + 0.5) * 2.0 * math.pi / 10.0
				rivet = geo.ellipsoid(0.010, 0.010, 0.010, 5, 3, row("brass"), sharp=40)
				geo.translate(rivet, (math.cos(a) * (r + 0.004), math.sin(a) * (r + 0.004) * b.torso_depth, z))
				geo.merge(bm, rivet)
	if panel:
		zp = (w + s) * 0.5 - 0.010
		front = Vector((0.0, -(b.torso_radius(zp) + 0.006) * b.torso_depth, zp))
		outline = []
		for k in range(16):
			a = 2.0 * math.pi * k / 16
			x, z = math.cos(a), math.sin(a)
			outline.append((math.copysign(abs(x) ** 0.6, x) * 0.080, math.copysign(abs(z) ** 0.6, z) * 0.070))
		plate = geo.plate(outline, 0.018, row("team_paint"), side=row("brass"), sharp=50, bend=1.2)
		geo.merge(bm, plate, geo.orient(front, (0.0, -1.0, 0.10)))
		if gauge:
			dial = geo.lathe([(0.0, 0.0), (0.034, 0.0), (0.036, 0.008), (0.030, 0.012), (0.0, 0.012)], seg(lod, 12, 8),
					sharp=40, phase=0.0, ring_swatches=[row("brass"), row("brass"), row("cloth"), row("cloth")])
			geo.merge(bm, dial, geo.frame(front + Vector((0.0, -0.014, 0.010)), (0.0, -1.0, 0.10), (0.0, 0.0, 1.0)))
			if lod == 0:
				needle = geo.box(0.004, 0.004, 0.026, row("boot"), HARD)
				geo.rotate(needle, 35.0, 'Y')
				geo.translate(needle, (0.006, 0.0, 0.010))
				geo.merge(bm, needle, geo.orient(front + Vector((0.0, -0.028, 0.012)), (0.0, -1.0, 0.10)))
	return bm


def wind_key(b, lod, size=1.0, z=None):
	"""The big brass wind-up key out of the back: a shaft, a collar, and a
	bow of two round lobes standing upright."""
	z = (b.waist_z + b.shoulder_z) * 0.5 if z is None else z
	back = b.torso_radius(z) * b.torso_depth
	k = size
	bm = geo.tube([Vector((0.0, back - 0.010, z)), Vector((0.0, back + 0.090 * k, z))], [0.014 * k, 0.014 * k],
			seg(lod, 6, 5), row("brass"), sharp=SMOOTH)
	collar = geo.tube([Vector((0.0, back - 0.006, z)), Vector((0.0, back + 0.020 * k, z))], [0.030 * k, 0.030 * k],
			seg(lod, 10, 7), row("brass"), sharp=SMOOTH, cap_end=row("brass"))
	geo.merge(bm, collar)
	for side in (-1.0, 1.0):
		lobe = geo.lathe([(0.0, -0.012 * k), (0.054 * k, -0.012 * k), (0.060 * k, 0.0), (0.054 * k, 0.012 * k),
				(0.0, 0.012 * k)], seg(lod, 12, 8), row("brass"), sharp=50, phase=0.0, sx=0.80, sy=1.0)
		geo.rotate(lobe, 90.0, 'X')
		geo.translate(lobe, (side * 0.050 * k, back + 0.110 * k, z))
		geo.merge(bm, lobe)
		if lod == 0:
			hole = geo.lathe([(0.0, -0.014 * k), (0.022 * k, -0.014 * k), (0.022 * k, 0.014 * k), (0.0, 0.014 * k)],
					seg(lod, 10, 7), row("brass_dark" if False else "plate_dark"), sharp=40, phase=0.0)
			geo.rotate(hole, 90.0, 'X')
			geo.translate(hole, (side * 0.056 * k, back + 0.110 * k, z))
			geo.merge(bm, hole)
	return bm


def ribbed_arms(b, lod, hand="mitt", sleeve="steel", ring="plate_dark", k=1.0, hands=(True, True)):
	"""Accordion arms of alternating chrome and gunmetal rings, a ball at
	each elbow, round mitt hands (or pincers). `hand` is one kind for both,
	or (right, left); `hands` leaves a side's hand off (a drill goes there)."""
	kinds = (hand, hand) if isinstance(hand, str) else hand
	bm = geo.new_bm()
	segs = seg(lod, 7, 5)
	for i, (shoulder, elbow, wrist, fist) in enumerate(((b.r_shoulder, b.r_elbow, b.r_wrist, b.r_fist),
			(b.l_shoulder, b.l_elbow, b.l_wrist, b.l_fist))):
		for p0, p1 in ((shoulder, elbow), (elbow, wrist)):
			n = seg(lod, 5, 3)
			pts = [p0.lerp(p1, t / n) for t in range(n + 1)]
			radii = [(0.040 if t % 2 == 0 else 0.034) * k for t in range(n + 1)]
			geo.merge(bm, geo.tube(pts, radii, segs, sharp=SMOOTH,
					ring_swatches=[row(sleeve) if t % 2 == 0 else row(ring) for t in range(n)]))
		ball = geo.ellipsoid(0.044 * k, 0.044 * k, 0.044 * k, seg(lod, 8, 6), seg(lod, 4, 3), row("plate_dark"),
				sharp=SMOOTH)
		geo.translate(ball, elbow)
		geo.merge(bm, ball)
		side = 1.0 if shoulder.x > 0.0 else -1.0
		sh = geo.ellipsoid(0.064 * k, 0.060 * k, 0.058 * k, seg(lod, 8, 6), seg(lod, 4, 3), row("skin"), sharp=SMOOTH)
		geo.translate(sh, shoulder + Vector((-side * 0.016, 0.0, 0.006)))
		geo.merge(bm, sh)
		if not hands[i]:
			continue
		axis = (wrist - elbow).normalized()
		if kinds[i] == "pincer":
			for s in (-1.0, 1.0):
				pts = [Vector((0.0, 0.0, 0.0)), Vector((s * 0.030, 0.0, 0.040)), Vector((s * 0.012, 0.0, 0.078))]
				claw = geo.tube(pts, [0.016 * k, 0.014 * k, 0.0], seg(lod, 6, 4), row("steel"), sharp=SMOOTH)
				geo.merge(bm, claw, geo.frame(wrist, axis, (0.0, 0.0, 1.0)))
		else:
			mitt = geo.ellipsoid(0.040 * k, 0.040 * k, 0.040 * k, seg(lod, 9, 6), seg(lod, 5, 4), row("cloth"),
					sharp=SMOOTH)
			geo.translate(mitt, fist)
			geo.merge(bm, mitt)
			cuff = geo.lathe([(0.038 * k, -0.010), (0.044 * k, 0.0), (0.038 * k, 0.012)], segs, row("brass"),
					sharp=40, phase=0.0)
			geo.merge(bm, cuff, geo.frame(wrist, axis, (0.0, 0.0, 1.0)))
	return bm


def piston_legs(b, lod, k=1.0):
	"""Stubby piston legs: a chrome rod in a gunmetal sleeve, a brass knee
	ring, and a chunky enamel boot on a black rubber sole."""
	bm = geo.new_bm()
	g = b.base_height
	for side in (-1.0, 1.0):
		x = side * b.foot_x
		geo.merge(bm, geo.tube([Vector((x, 0.0, g + 0.060)), Vector((x, 0.0, b.hem_z + 0.040))], [0.034 * k, 0.034 * k],
				seg(lod, 8, 6), row("steel"), sharp=SMOOTH))
		geo.merge(bm, geo.tube([Vector((x, 0.0, g + 0.090)), Vector((x, 0.0, g + 0.120))], [0.046 * k, 0.046 * k],
				seg(lod, 8, 6), row("brass"), sharp=SMOOTH, cap_start=row("brass"), cap_end=row("brass")))
		boot = geo.box(0.090 * k, 0.130 * k, 0.070, row("cloth"), HARD, bevel=0.022 if lod == 0 else 0.010)
		geo.translate(boot, (x, -0.020, g + 0.046))
		geo.merge(bm, boot)
		sole = geo.box(0.096 * k, 0.136 * k, 0.020, row("sole"), HARD, bevel=0.006 if lod == 0 else 0.0)
		geo.translate(sole, (x, -0.020, g + 0.010))
		geo.merge(bm, sole)
	return bm


def wheel_base(b, lod):
	"""In place of legs: one fat rubber wheel in a gunmetal fork."""
	g = b.base_height
	bm = geo.tube([Vector((-0.050, 0.0, g + 0.080)), Vector((0.050, 0.0, g + 0.080))], [0.080, 0.080], seg(lod, 14, 9),
			row("leather"), sharp=SMOOTH, cap_start=row("brass"), cap_end=row("brass"))
	for side in (-1.0, 1.0):
		fork = geo.box(0.020, 0.040, 0.120, row("plate_dark"), HARD, bevel=0.006)
		geo.translate(fork, (side * 0.064, 0.0, g + 0.120))
		geo.merge(bm, fork)
	return bm


# --- weapons ----------------------------------------------------------------

def saber(b, lod):
	"""A toy soldier's tin saber: a straight chrome blade, a brass bow guard."""
	bm = parts.arming_sword(b, lod)
	return gear.grow(bm, b.r_fist, 1.45)


def tin_shield(b, lod):
	"""A round tin shield painted in the team's enamel with a cream ring
	pattern and a brass boss."""
	shield = parts.round_shield(b, lod)
	for src, dst in (("wood", "steel"), ("cream", "cloth")):
		sw = shield.faces.layers.int.get(geo.SWATCH)
		for f in shield.faces:
			if f[sw] == row(src):
				f[sw] = row(dst)
	return shield


def drill(b, lod, fist, axis, size=1.0):
	"""A huge drill bit in place of a right hand: a gunmetal motor drum with
	brass bands, then a long chrome cone with a spiral flute."""
	k = size
	bm = geo.lathe([(0.0, -0.020), (0.062 * k, -0.020), (0.066 * k, 0.000), (0.066 * k, 0.090 * k),
			(0.054 * k, 0.100 * k), (0.0, 0.102 * k)], seg(lod, 12, 8), row("plate_dark"), sharp=40, phase=0.0)
	for z in (0.012, 0.074):
		band = geo.lathe([(0.064 * k, z * k - 0.008), (0.070 * k, z * k), (0.064 * k, z * k + 0.008)], seg(lod, 12, 8),
				row("brass"), sharp=40, phase=0.0)
		geo.merge(bm, band)
	cone = geo.lathe([(0.052 * k, 0.100 * k), (0.0, 0.420 * k)], seg(lod, 12, 8), row("steel"), sharp=SMOOTH,
			phase=0.0, cap_start=row("steel"))
	geo.merge(bm, cone)
	tree = geo.bvh(cone)
	steps = seg(lod, 22, 10)
	pts, nrms = [], []
	for i in range(steps):
		t = i / (steps - 1)
		z = (0.110 + 0.290 * t) * k
		a = t * math.pi * 6.0
		r = 0.052 * k * (1.0 - (z / k - 0.100) / 0.320)
		loc, nrm = geo.project(tree, (math.cos(a) * 0.5, math.sin(a) * 0.5, z), (-math.cos(a), -math.sin(a), 0.0))
		if loc is not None:
			pts.append(loc)
			nrms.append(nrm)
	if len(pts) > 1:
		geo.merge(bm, geo.ribbon(pts, nrms, 0.014 * k, 0.010 * k, row("trim"), sharp=40, embed=0.003))
	geo.transform(bm, geo.frame(fist, axis, (0.0, 0.0, 1.0)))
	return bm


def wrench(b, lod):
	"""A huge spanner held up like a club: a long flat chrome shaft and an
	open jaw at the top, a rubber grip."""
	bm = geo.new_bm()
	shaft = geo.box(0.040, 0.020, 0.420, row("steel"), HARD, bevel=0.008 if lod == 0 else 0.0)
	geo.translate(shaft, (0.0, 0.0, 0.170))
	geo.merge(bm, shaft)
	grip = geo.box(0.052, 0.030, 0.140, row("leather"), HARD, bevel=0.010 if lod == 0 else 0.0)
	geo.translate(grip, (0.0, 0.0, -0.010))
	geo.merge(bm, grip)
	steps = seg(lod, 12, 7)
	outer, inner = [], []
	for i in range(steps):
		a = math.radians(-60 + 300 * i / (steps - 1))
		outer.append((math.sin(a) * 0.090, 0.420 + math.cos(a) * 0.090))
		inner.append((math.sin(a) * 0.046, 0.430 + math.cos(a) * 0.050))
	jaw = geo.plate(outer + list(reversed(inner)), 0.030, row("steel"), side=row("trim"), sharp=40)
	geo.merge(bm, jaw)
	geo.transform(bm, geo.frame(b.r_fist, b.sword_axis, (0.0, -1.0, 0.0)))
	return gear.grow(bm, b.r_fist, 1.35)


def ray_gun(b, lod):
	"""A toy ray gun levelled at the waist: a fat cream body with orange
	fins, chrome rings up a tapering barrel to an amber emitter dish."""
	rear, front = b.stock_rear, b.stock_front
	forward = (front - rear).normalized()
	bm = geo.new_bm()
	body = geo.lathe([(0.0, -0.10), (0.040, -0.094), (0.050, -0.040), (0.046, 0.040), (0.026, 0.080),
			(0.020, 0.200), (0.0, 0.202)], seg(lod, 12, 8), row("cloth"), sharp=SMOOTH, phase=0.0)
	for z in (0.100, 0.140, 0.180):
		ring = geo.lathe([(0.020, z - 0.008), (0.032, z), (0.020, z + 0.008)], seg(lod, 10, 7), row("steel"),
				sharp=40, phase=0.0)
		geo.merge(body, ring)
	dish = geo.lathe([(0.012, 0.0), (0.046, 0.030), (0.050, 0.040), (0.040, 0.036), (0.0, 0.020)], seg(lod, 12, 8),
			row("brass"), sharp=50, phase=0.0)
	lamp = geo.ellipsoid(0.020, 0.020, 0.020, 7, 4, row("crystal"), sharp=SMOOTH)
	geo.translate(lamp, (0.0, 0.0, 0.030))
	geo.merge(dish, lamp)
	geo.translate(dish, (0.0, 0.0, 0.200))
	geo.merge(body, dish)
	for k in range(3):
		a = math.radians(90 + 120 * k)
		fin = geo.plate([(0.0, 0.0), (0.050, -0.030), (0.050, 0.030), (0.0, 0.060)], 0.010, row("fruit"), sharp=40)
		geo.rotate(fin, 90.0, 'Z')
		geo.translate(fin, (0.040, 0.0, -0.080))
		geo.rotate(fin, math.degrees(a), 'Z')
		geo.merge(body, fin)
	geo.transform(body, geo.frame(Vector((0.0, 0.0, 0.0)), (0.0, -1.0, 0.0), (0.0, 0.0, 1.0)))
	geo.merge(bm, body)
	grip = geo.box(0.030, 0.040, 0.080, row("plate_dark"), 40, bevel=0.008 if lod == 0 else 0.0)
	geo.rotate(grip, 15.0, 'X')
	geo.translate(grip, (0.0, 0.050, -0.060))
	geo.merge(bm, grip)
	geo.transform(bm, geo.orient(rear + forward * 0.12, forward))
	pivot = rear + forward * (b.r_fist - rear).dot(forward)
	return gear.grow(bm, pivot, 1.55)


def coil_staff(b, lod, below=0.30):
	"""A rod tipped with a little tesla coil and its violet spark ball."""
	axis = b.pole_axis
	fist = b.r_fist
	top = fist + axis * 0.58
	bm = geo.tube([fist - axis * below, top], [0.016, 0.016], seg(lod, 6, 5), row("plate_dark"), sharp=40,
			cap_start=row("plate_dark"))
	for k in range(3):
		ring = geo.lathe([(0.026, -0.008), (0.044 - k * 0.008, 0.0), (0.026, 0.008)], seg(lod, 10, 7), row("brass"),
				sharp=SMOOTH, phase=0.0)
		geo.merge(bm, ring, geo.frame(top - axis * (0.10 - k * 0.032), axis, (0.0, 1.0, 0.0)))
	ball = geo.ellipsoid(0.040, 0.040, 0.040, seg(lod, 10, 7), seg(lod, 5, 4), row("arcane"), sharp=SMOOTH)
	geo.translate(ball, top + axis * 0.020)
	geo.merge(bm, ball)
	return bm


def boiler_stack(b, lod):
	"""A boiler chimney stack up the back, banded in brass, a flared top."""
	z0 = b.waist_z
	back = b.torso_radius(b.shoulder_z) * b.torso_depth
	bm = geo.lathe([(0.044, z0), (0.044, b.shoulder_z + 0.260), (0.062, b.shoulder_z + 0.300),
			(0.060, b.shoulder_z + 0.310), (0.036, b.shoulder_z + 0.300)], seg(lod, 10, 7), row("plate_dark"),
			sharp=40, phase=0.0, cap_end=row("boot"))
	for z in (b.shoulder_z + 0.060, b.shoulder_z + 0.200):
		geo.merge(bm, geo.lathe([(0.044, z - 0.010), (0.052, z), (0.044, z + 0.010)], seg(lod, 10, 7), row("brass"),
				sharp=40, phase=0.0))
	geo.translate(bm, (0.090, back + 0.010, 0.0))
	return bm


# --- the Hound ---------------------------------------------------------------

HOUND_SEAT = 0.56


def hound(b, lod):
	"""A clockwork hound to ride: a riveted gunmetal barrel body, four
	stubby piston legs on chrome paws, a square head held high with the
	shared eyes, brass floppy ears, a spring tail and its own wind-up key."""
	g = b.base_height
	bm = geo.new_bm()
	body = geo.box(0.300, 0.620, 0.240, row("coat"), SMOOTH, bevel=0.080 if lod == 0 else 0.050, bevel_segments=2)
	geo.translate(body, (0.0, 0.020, g + 0.380))
	geo.merge(bm, body)
	belly = geo.box(0.260, 0.520, 0.060, row("coat_dark"), SMOOTH, bevel=0.024)
	geo.translate(belly, (0.0, 0.020, g + 0.270))
	geo.merge(bm, belly)
	if lod == 0:
		for x in (-0.152, 0.152):
			for y in (-0.200, -0.060, 0.080, 0.220):
				for z in (0.320, 0.440):
					rivet = geo.ellipsoid(0.010, 0.010, 0.010, 5, 3, row("brass"), sharp=40)
					geo.translate(rivet, (x, y, g + z))
					geo.merge(bm, rivet)
	for x in (-0.105, 0.105):
		for y in (-0.200, 0.230):
			hip = Vector((x, y, g + 0.330))
			foot = Vector((x * 1.10, y + (0.020 if y > 0 else -0.020), g + 0.040))
			geo.merge(bm, geo.tube([hip, foot], [0.046, 0.038], seg(lod, 8, 6), row("steel"), sharp=SMOOTH))
			knee = geo.ellipsoid(0.048, 0.048, 0.048, seg(lod, 8, 6), 4, row("brass"), sharp=SMOOTH)
			geo.translate(knee, hip.lerp(foot, 0.45))
			geo.merge(bm, knee)
			paw = geo.ellipsoid(0.056, 0.070, 0.040, seg(lod, 9, 6), 4, row("coat_dark"), sharp=SMOOTH,
					squash_bottom=0.3)
			geo.translate(paw, foot + Vector((0.0, -0.016, -0.008)))
			geo.merge(bm, paw)
	neck = geo.tube([Vector((0.0, -0.230, g + 0.440)), Vector((0.0, -0.300, g + 0.580))], [0.070, 0.060],
			seg(lod, 8, 6), row("plate_dark"), sharp=SMOOTH)
	geo.merge(bm, neck)
	head = geo.box(1.0, 1.0, 1.0, row("coat"), SMOOTH)
	head = geo.subdivided(head, seg(lod, 2, 1))
	geo.fit(head, (0.210, 0.200, 0.180), (0.0, -0.360, g + 0.650))
	geo.merge(bm, head)
	snout = geo.box(0.130, 0.120, 0.090, row("coat"), SMOOTH, bevel=0.030 if lod == 0 else 0.015)
	geo.translate(snout, (0.0, -0.480, g + 0.610))
	geo.merge(bm, snout)
	nose = geo.ellipsoid(0.034, 0.024, 0.026, 7, 4, row("boot"), sharp=SMOOTH)
	geo.translate(nose, (0.0, -0.546, g + 0.640))
	geo.merge(bm, nose)
	tree = geo.bvh(head)
	for side in (-1.0, 1.0):
		loc, nrm = geo.project(tree, (side * 0.050, -1.0, g + 0.680), (0.0, 1.0, 0.0))
		if loc is not None:
			geo.merge(bm, geo.disc(0.028, 0.034, seg(lod, 10, 6), row("brass"), dome=0.004, depth=0.003),
					geo.frame(loc, nrm, (0.0, 0.0, 1.0)))
			geo.merge(bm, geo.disc(0.020, 0.026, seg(lod, 9, 6), row("eye"), dome=0.006),
					geo.frame(loc + nrm * 0.003, nrm, (0.0, 0.0, 1.0)))
			if lod == 0:
				geo.merge(bm, geo.disc(0.007, 0.007, 5, row("glint"), dome=0.0015, depth=0.0015, simple=True),
						geo.frame(loc + nrm * 0.009 + Vector((0.008, 0.0, 0.010)), nrm, (0.0, 0.0, 1.0)))
		ear = geo.plate([(-0.030, 0.0), (0.030, 0.0), (0.040, -0.120), (0.0, -0.140), (-0.040, -0.120)], 0.016,
				row("mane"), sharp=50, bend=1.0)
		geo.rotate(ear, side * 20.0, 'Y')
		geo.rotate(ear, 90.0, 'Z')
		geo.translate(ear, (side * 0.110, -0.340, g + 0.720))
		geo.merge(bm, ear)
	steps = seg(lod, 12, 6)
	pts = []
	for i in range(steps):
		t = i / (steps - 1)
		a = t * math.pi * 6.0
		pts.append(Vector((math.cos(a) * 0.020, 0.340 + 0.100 * t + math.sin(a) * 0.020, g + 0.440 + 0.180 * t)))
	geo.merge(bm, geo.tube(pts, [0.010] * (steps - 1) + [0.0], 4, row("steel"), sharp=SMOOTH))
	tip = geo.ellipsoid(0.026, 0.026, 0.026, 7, 4, row("brass"), sharp=SMOOTH)
	geo.translate(tip, pts[-1])
	geo.merge(bm, tip)
	# Its own wind-up key, standing out of its flank behind the saddle.
	key = geo.new_bm()
	geo.merge(key, geo.tube([Vector((0.0, 0.0, 0.0)), Vector((0.0, 0.0, 0.100))], [0.016, 0.016], seg(lod, 6, 5),
			row("brass"), sharp=SMOOTH))
	for side in (-1.0, 1.0):
		lobe = geo.lathe([(0.0, -0.012), (0.056, -0.012), (0.062, 0.0), (0.056, 0.012), (0.0, 0.012)], seg(lod, 12, 8),
				row("brass"), sharp=50, phase=0.0, sx=0.8)
		geo.rotate(lobe, 90.0, 'Y')
		geo.translate(lobe, (0.0, side * 0.052, 0.120))
		geo.merge(key, lobe)
	geo.translate(key, (0.0, 0.230, g + 0.500))
	geo.merge(bm, key)
	return bm


def hound_saddle(b, lod):
	"""The team's enamel saddle plate over the hound's back, a black leather
	seat on it and a pair of brass reins to its collar."""
	g = b.base_height
	bm = geo.new_bm()
	plate = geo.box(0.330, 0.300, 0.030, row("team_paint"), SMOOTH, bevel=0.012)
	for v in plate.verts:
		v.co.z -= 0.25 * v.co.x * v.co.x
	geo.translate(plate, (0.0, 0.050, g + 0.505))
	geo.merge(bm, plate)
	for side in (-1.0, 1.0):
		flap = geo.box(0.020, 0.260, 0.150, row("team_paint"), SMOOTH, bevel=0.008)
		geo.translate(flap, (side * 0.164, 0.050, g + 0.420))
		geo.merge(bm, flap)
		trim = geo.box(0.024, 0.270, 0.020, row("brass"), SMOOTH, bevel=0.006)
		geo.translate(trim, (side * 0.166, 0.050, g + 0.346))
		geo.merge(bm, trim)
	seat = geo.ellipsoid(0.100, 0.120, 0.036, seg(lod, 10, 7), 4, row("leather"), sharp=SMOOTH, squash_bottom=0.4)
	geo.translate(seat, (0.0, 0.040, g + HOUND_SEAT - 0.024))
	geo.merge(bm, seat)
	collar = geo.lathe([(0.070, -0.016), (0.080, 0.0), (0.070, 0.016)], seg(lod, 10, 7), row("team_paint"),
			sharp=SMOOTH, phase=0.0)
	geo.transform(collar, geo.frame(Vector((0.0, -0.270, g + 0.520)), Vector((0.0, -0.45, 1.0)), (0.0, 1.0, 0.0)))
	geo.merge(bm, collar)
	return bm


# --- the Rocket Wagon -------------------------------------------------------

WAGON_SCALE = 1.7


## The wagon's axles [(y, z), ...] before it is grown, and its wheels' radius.
WAGON_AXLES = [(-0.50, 0.24), (0.42, 0.24)]
WAGON_WHEEL_RADIUS = 0.24


def rocket_wagon(lod, part=None):
	"""A tin wagon on four chunky wheels carrying a tilted rack of four big
	cream rockets with orange fins and team-enamel bands, a brass boiler
	drum at the back."""
	from siege import _wheel, _cyl, _beam
	from beasts import _grow
	bm = geo.new_bm()
	wheels = []
	for y, z in WAGON_AXLES:
		axle = _cyl((-0.52, y, z), (0.52, y, z), 0.05, "plate_dark", lod)
		for x in (-0.44, 0.44):
			geo.merge(axle, _wheel(lod, x, y, z, WAGON_WHEEL_RADIUS, 0.12, 1.0 if x > 0 else -1.0, segs=(16, 10)))
		wheels.append(axle)
	bed = geo.box(0.76, 1.30, 0.20, row("skin"), SMOOTH, bevel=0.05)
	geo.translate(bed, (0.0, -0.04, 0.42))
	geo.merge(bm, bed)
	for side in (-1.0, 1.0):
		stripe = geo.box(0.02, 1.20, 0.08, row("team_paint"), HARD, bevel=0.008)
		geo.translate(stripe, (side * 0.385, -0.04, 0.42))
		geo.merge(bm, stripe)
	pivot = Vector((0.0, 0.05, 0.62))
	rack = geo.new_bm()
	frame = geo.box(0.60, 0.90, 0.06, row("plate_dark"), HARD, bevel=0.015)
	geo.merge(rack, frame)
	for x in (-0.15, 0.15):
		for z in (0.12, 0.34):
			rocket = geo.lathe([(0.0, -0.46), (0.080, -0.44), (0.090, -0.30), (0.090, 0.24), (0.060, 0.38),
					(0.0, 0.46)], seg(lod, 12, 8), sharp=SMOOTH, phase=0.0,
					ring_swatches=[row("plate_dark"), row("cloth"), row("cloth"), row("fruit"), row("fruit")])
			band = geo.lathe([(0.088, -0.06), (0.096, -0.04), (0.096, 0.04), (0.088, 0.06)], seg(lod, 12, 8),
					row("team_paint"), sharp=40, phase=0.0)
			geo.merge(rocket, band)
			for k in range(3):
				fin = geo.plate([(0.0, 0.0), (0.070, -0.050), (0.070, 0.020), (0.0, 0.100)], 0.012, row("fruit"),
						sharp=40)
				geo.rotate(fin, 90.0, 'Z')
				geo.translate(fin, (0.084, 0.0, -0.420))
				geo.rotate(fin, 120.0 * k + 30.0, 'Z')
				geo.merge(rocket, fin)
			geo.transform(rocket, geo.frame(Vector((x, 0.0, z)), Vector((0.0, -1.0, 0.0)), (0.0, 0.0, 1.0)))
			geo.merge(rack, rocket)
	geo.transform(rack, Matrix.Translation(pivot) @ Matrix.Rotation(math.radians(-22.0), 4, 'X'))
	geo.merge(bm, rack)
	for side in (-1.0, 1.0):
		geo.merge(bm, _beam((side * 0.30, 0.05, 0.52), (side * 0.30, 0.05, 0.66), 0.06, 0.06, "plate_dark"))
	drum = geo.lathe([(0.0, 0.0), (0.16, 0.0), (0.18, 0.04), (0.18, 0.30), (0.16, 0.34), (0.0, 0.34)], seg(lod, 12, 8),
			row("brass"), sharp=SMOOTH, phase=0.0)
	geo.translate(drum, (0.0, 0.50, 0.52))
	geo.merge(bm, drum)
	from siege import split_wheels
	return split_wheels(bm, wheels, part, WAGON_SCALE)


# --- the Worker Bot's tools and loads ------------------------------------------

def _handle(lod, length=0.20, below=0.07):
	return geo.lathe([(0.0, -below), (0.016, -below + 0.004), (0.017, 0.0), (0.016, length - below)],
			seg(lod, 6, 5), row("leather"), sharp=40, phase=0.0)


def chainsaw(b, lod):
	"""A toy chainsaw for felling trees: an orange motor block on the grip,
	a long chrome bar ringed by a dark chain of teeth."""
	bm = _handle(lod, 0.10)
	motor = geo.box(0.090, 0.080, 0.110, row("fruit"), HARD, bevel=0.016 if lod == 0 else 0.008)
	geo.translate(motor, (0.0, 0.0, 0.080))
	geo.merge(bm, motor)
	cap = geo.box(0.070, 0.084, 0.024, row("plate_dark"), HARD, bevel=0.006)
	geo.translate(cap, (0.0, 0.0, 0.140))
	geo.merge(bm, cap)
	bar = geo.box(0.022, 0.060, 0.300, row("steel"), HARD, bevel=0.010 if lod == 0 else 0.0)
	geo.translate(bar, (0.0, 0.0, 0.280))
	geo.merge(bm, bar)
	chain = geo.box(0.014, 0.074, 0.312, row("plate_dark"), HARD, bevel=0.004)
	geo.translate(chain, (0.0, 0.0, 0.282))
	geo.merge(bm, chain)
	if lod == 0:
		for k in range(9):
			for side in (-1.0, 1.0):
				tooth = geo.box(0.016, 0.012, 0.016, row("blade"), HARD)
				geo.translate(tooth, (0.0, side * 0.040, 0.150 + k * 0.032))
				geo.merge(bm, tooth)
	return gear._place(bm, b, b.r_fist, b.sword_axis)


def laser_drill(b, lod):
	"""A handheld mining laser: a cream body with orange fins and an amber
	lens at its nose, a little beam of light out of it."""
	bm = _handle(lod, 0.10)
	body = geo.lathe([(0.0, 0.020), (0.036, 0.026), (0.042, 0.080), (0.030, 0.200), (0.022, 0.240), (0.0, 0.244)],
			seg(lod, 10, 7), row("cloth"), sharp=SMOOTH, phase=0.0)
	geo.merge(bm, body)
	for z in (0.120, 0.170):
		geo.merge(bm, geo.lathe([(0.030, z - 0.008), (0.040, z), (0.030, z + 0.008)], seg(lod, 10, 7), row("brass"),
				sharp=40, phase=0.0))
	lens = geo.ellipsoid(0.026, 0.026, 0.026, seg(lod, 8, 6), 4, row("crystal"), sharp=SMOOTH)
	geo.translate(lens, (0.0, 0.0, 0.250))
	geo.merge(bm, lens)
	beam = geo.lathe([(0.014, 0.260), (0.006, 0.420), (0.0, 0.430)], 6, row("crystal"), sharp=SMOOTH, phase=0.0)
	geo.merge(bm, beam)
	for k in range(2):
		fin = geo.plate([(0.0, 0.0), (0.050, 0.010), (0.040, 0.060), (0.0, 0.070)], 0.010, row("fruit"), sharp=40)
		geo.rotate(fin, 90.0, 'Z')
		geo.translate(fin, (0.034, 0.0, 0.030))
		geo.rotate(fin, 180.0 * k, 'Z')
		geo.merge(bm, fin)
	return gear._place(bm, b, b.r_fist, b.sword_axis)


def spanner(b, lod):
	"""A builder's spanner: a chrome shaft and an open jaw."""
	bm = _handle(lod, 0.12)
	shaft = geo.box(0.028, 0.014, 0.200, row("steel"), HARD, bevel=0.005 if lod == 0 else 0.0)
	geo.translate(shaft, (0.0, 0.0, 0.130))
	geo.merge(bm, shaft)
	steps = seg(lod, 10, 6)
	outer, inner = [], []
	for i in range(steps):
		a = math.radians(-60 + 300 * i / (steps - 1))
		outer.append((math.sin(a) * 0.060, 0.250 + math.cos(a) * 0.060))
		inner.append((math.sin(a) * 0.030, 0.258 + math.cos(a) * 0.034))
	geo.merge(bm, geo.plate(outer + list(reversed(inner)), 0.020, row("steel"), side=row("trim"), sharp=40))
	return gear._place(bm, b, b.r_fist, b.sword_axis)


def _battery(lod, k=1.0):
	"""A fat toy battery cell: a cream body, an orange band, a brass button."""
	bm = geo.lathe([(0.0, 0.0), (0.040 * k, 0.0), (0.042 * k, 0.010 * k), (0.042 * k, 0.110 * k), (0.036 * k, 0.118 * k),
			(0.0, 0.120 * k)], seg(lod, 10, 7), sharp=SMOOTH, phase=0.0,
			ring_swatches=[row("plate_dark"), row("cloth"), row("fruit"), row("plate_dark"), row("plate_dark")])
	band = geo.lathe([(0.043 * k, 0.040 * k), (0.045 * k, 0.050 * k), (0.045 * k, 0.080 * k), (0.043 * k, 0.090 * k)],
			seg(lod, 10, 7), row("fruit"), sharp=40, phase=0.0)
	geo.merge(bm, band)
	button = geo.lathe([(0.016 * k, 0.118 * k), (0.016 * k, 0.136 * k), (0.0, 0.140 * k)], seg(lod, 8, 5), row("brass"),
			sharp=40, phase=0.0)
	geo.merge(bm, button)
	return bm


def battery_pack(b, lod):
	"""A wire crate of three battery cells on the bent left arm, the robot's
	food."""
	bm = geo.box(0.150, 0.070, 0.060, row("plate_dark"), HARD, bevel=0.010 if lod == 0 else 0.0)
	for x in (-0.045, 0.0, 0.045):
		cell = _battery(lod, 0.55)
		geo.translate(cell, (x, 0.0, 0.020))
		geo.merge(bm, cell)
	geo.rotate(bm, 90.0, 'Z')
	geo.translate(bm, b.l_fist + Vector((0.020, -0.005, -0.10)))
	return bm


def battery_crate(b, lod):
	"""A crate of charged battery cells held out in front in both hands."""
	bm = geo.box(0.220, 0.150, 0.070, row("plate_dark"), HARD, bevel=0.012 if lod == 0 else 0.0)
	for x in (-0.070, 0.0, 0.070):
		for y in (-0.035, 0.035):
			if lod > 0 and y > 0:
				continue
			cell = _battery(lod, 0.6)
			geo.translate(cell, (x, y, 0.025))
			geo.merge(bm, cell)
	geo.translate(bm, b.load_centre + Vector((0.0, 0.0, -0.02)))
	return bm
