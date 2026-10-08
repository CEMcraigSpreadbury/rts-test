"""Star Wanderers parts: sky-blue celestial chibis come down from the night.

The race reads apart from every other by three things:
- the head: bald and sky-blue (the star_wanderers palette's skin), a taller
  dome than a human's, two tall fins swept up from the crown tipped with
  cyan starlight, a cyan four-pointed star on the brow and white star
  freckles under the shared big dark eyes;
- the materials: pearl-white porcelain plate (the palette's steel) over a
  midnight-indigo suit (plate_dark), edged in bright gold (brass, trim);
- the light: glowing gear in three star colours, cyan (crystal), violet
  moonlight (arcane) and sun gold (fruit, repurposed; see
  palette.STAR_WANDERERS), and things that float: haloes, a hovering robe.

The team's colour is on the cloth: a chunky scarf, a loincloth, a stole, a
robe's hem. Each unit has a Body of its own (see the Body subclasses).
Head pieces are built upright and tipped back by the recipe.
"""
import math

from mathutils import Matrix, Vector

import geo
from geo import FLAT, SMOOTH
from palette import row
import parts
from parts import seg, _limb


# --- head -------------------------------------------------------------------

def head(b, lod):
	"""A bald, rounded head with a taller dome than a human's, the jaw a
	little narrower than the cheeks."""
	bm = geo.box(1.0, 1.0, 1.0, row("skin"), SMOOTH)
	bm = geo.subdivided(bm, seg(lod, 2, 1))
	geo.fit(bm, b.head_size, b.head_centre)
	c = b.head_centre
	half_h = b.head_size.z * 0.5
	for v in bm.verts:
		d = (v.co.z - c.z) / half_h
		if d < 0.0:
			v.co.x = c.x + (v.co.x - c.x) * (1.0 - 0.15 * d * d)
			v.co.y = c.y + (v.co.y - c.y) * (1.0 + 0.05 * d)
		else:
			v.co.z += 0.034 * d * d
			v.co.x = c.x + (v.co.x - c.x) * (1.0 - 0.07 * d * d)
	return geo.paint(bm, row("skin"), SMOOTH)


def fins(b, lod, height=1.0, spread=1.0):
	"""Two tall fins swept up and a little back from the crown, flat to the
	camera, their tips cyan starlight. spread > 1 sweeps them out sideways
	like horns."""
	bm = geo.new_bm()
	c = b.head_centre
	k = height
	q = spread
	for side in (-1.0, 1.0):
		root = Vector((side * 0.100, c.y + 0.012, c.z + 0.112))
		pts = [root, root + Vector((side * 0.034 * q, 0.018, 0.070 * k)),
				root + Vector((side * 0.058 * q, 0.040, 0.150 * k)), root + Vector((side * 0.066 * q, 0.068, 0.222 * k))]
		geo.merge(bm, geo.tube(pts, [0.046, 0.038, 0.024, 0.0], seg(lod, 7, 5), sharp=SMOOTH, cap_start=row("skin"),
				flatten=0.42, up=(0.0, 1.0, 0.0), ring_swatches=[row("skin"), row("skin"), row("crystal")]))
	return bm


def _star(r_long, r_wide, inner, points=4):
	"""A star outline in local XZ, its first point straight up."""
	out = []
	for i in range(points * 2):
		a = math.pi / 2.0 + i * math.pi / points
		if i % 2:
			r = inner
			out.append((math.cos(a) * r, math.sin(a) * r))
		else:
			r = r_long if i % 4 == 0 else r_wide
			if points != 4:
				r = r_long
			out.append((math.cos(a) * r, math.sin(a) * r))
	return out


def star_face(b, lod, head_bm):
	"""The shared big dark eyes and glints (parts.face), a cyan four-pointed
	star on the brow, and (near) white star freckles under the eyes."""
	bm = parts.face(b, lod, head_bm)
	tree = geo.bvh(head_bm)
	c = b.head_centre

	def place(x, z, part, lift=0.0):
		loc, nrm = geo.project(tree, (x, -1.0, z), (0.0, 1.0, 0.0))
		if loc is None:
			return
		geo.merge(bm, part, geo.orient(loc + nrm * lift, nrm, (0.0, 0.0, 1.0)))

	place(0.0, c.z + 0.074, geo.plate(_star(0.036, 0.026, 0.010), 0.012, row("crystal"), sharp=FLAT), lift=0.001)
	if lod == 0:
		eye_z = c.z - 0.014
		for side in (-1.0, 1.0):
			for dx, dz, r in ((0.086, -0.050, 0.0055), (0.104, -0.040, 0.0045), (0.098, -0.062, 0.0040)):
				loc, nrm = geo.project(tree, (side * dx, -1.0, eye_z + dz), (0.0, 1.0, 0.0))
				if loc is not None:
					geo.merge(bm, geo.disc(r, r, 5, row("glint"), dome=0.0012, depth=0.0015, simple=True),
							geo.frame(loc + nrm * 0.001, nrm, (0.0, 0.0, 1.0)))
	return bm


# --- shared body ------------------------------------------------------------

def arms(b, lod, sleeve="plate_dark", bracer="steel", cuff="brass", k=1.0):
	"""Midnight sleeves, porcelain bracers with a gold cuff, sky-blue hands."""
	bm = geo.new_bm()
	segs = seg(lod, 7, 5)
	for shoulder, elbow, wrist, fist in ((b.r_shoulder, b.r_elbow, b.r_wrist, b.r_fist),
			(b.l_shoulder, b.l_elbow, b.l_wrist, b.l_fist)):
		upper = (elbow - shoulder).length
		geo.merge(bm, _limb(shoulder, elbow, [(0.046 * k, -0.01), (0.052 * k, 0.006), (0.046 * k, upper),
				(0.034 * k, upper + 0.022), (0.0, upper + 0.030)], segs, row(sleeve)))
		lower = (wrist - elbow).length
		if lod == 0:
			prof = [(0.040 * k, -0.010), (0.046 * k, 0.004), (0.046 * k, lower - 0.024), (0.054 * k, lower - 0.018),
					(0.054 * k, lower + 0.002), (0.0, lower + 0.008)]
			bands = [row(bracer)] * 2 + [row(cuff)] * 3
		else:
			prof = [(0.046 * k, 0.0), (0.046 * k, lower), (0.0, lower + 0.006)]
			bands = [row(bracer), row(cuff)]
		geo.merge(bm, _limb(elbow, wrist, prof, segs, sharp=40, bands=bands))
		hand = geo.box(1.0, 1.0, 1.0, row("skin"), SMOOTH)
		if lod == 0:
			hand = geo.subdivided(hand, 1)
		geo.fit(hand, (0.062 * k, 0.066 * k, 0.068 * k))
		geo.paint(hand, row("skin"), SMOOTH)
		geo.merge(bm, hand, geo.frame(fist, wrist - elbow, (0.0, 0.0, 1.0)))
	return bm


# === the Star Warrior =======================================================

class WarriorBody(parts.Body):
	"""Athletic and top-heavy: a broad porcelain chest over a pinched waist,
	short legs set wide, both arms held low and out to the sides with a
	crescent blade in each fist."""
	foot_x = 0.080
	hem_z = 0.185
	waist_z = 0.292
	shoulder_z = 0.468
	neck_z = 0.530
	torso_depth = 0.78
	r_shoulder = Vector((-0.168, 0.0, 0.448))
	r_elbow = Vector((-0.236, 0.010, 0.372))
	r_wrist = Vector((-0.268, -0.040, 0.318))
	r_fist = Vector((-0.274, -0.066, 0.300))
	l_shoulder = Vector((0.168, 0.0, 0.448))
	l_elbow = Vector((0.236, 0.010, 0.372))
	l_wrist = Vector((0.268, -0.040, 0.318))
	l_fist = Vector((0.274, -0.066, 0.300))

	def torso_profile(self):
		h, w, s, n = self.hem_z, self.waist_z, self.shoulder_z, self.neck_z
		return [
			(0.136, h), (0.142, h + 0.010), (0.136, h + 0.030), (0.118, h + 0.068),
			(0.108, w), (0.138, w + 0.060), (0.170, w + 0.120),
			(0.174, s - 0.012), (0.142, s + 0.022), (0.080, n), (0.0, n + 0.004),
		]


def warrior_legs(b, lod):
	"""Midnight legs in porcelain greaves with gold cuffs."""
	bm = geo.new_bm()
	for side in (-1.0, 1.0):
		leg = geo.lathe([(0.042, b.base_height + 0.085), (0.048, b.hem_z + 0.06)], seg(lod, 8, 5), row("plate_dark"))
		geo.translate(leg, (side * b.foot_x, 0.0, 0.0))
		geo.merge(bm, leg)
	boots = parts.boots(b, lod)
	for src, dst in (("boot", "steel"), ("leather", "brass"), ("sole", "plate_dark")):
		_recolour(boots, src, dst)
	geo.merge(bm, boots)
	return bm


def _recolour(bm, src, dst):
	sw = bm.faces.layers.int.get(geo.SWATCH)
	for f in bm.faces:
		if f[sw] == row(src):
			f[sw] = row(dst)
	return bm


def warrior_torso(b, lod):
	"""The midnight suit, and over its chest a pearl porcelain cuirass edged
	in gold with a cyan star set in its middle."""
	prof = b.torso_profile()
	segs = seg(lod, 14, 9)
	if lod > 0:
		keep = (0, 1, 2, 4, 6, 8, 9, 10)
		prof = [prof[i] for i in keep]
	bm = geo.lathe(prof, segs, row("plate_dark"), sharp=SMOOTH, sy=b.torso_depth, cap_start=row("plate_dark"))
	w, s, n = b.waist_z, b.shoulder_z, b.neck_z
	zs = [w + 0.040, w + 0.050, w + 0.080, w + 0.120, s - 0.012, s + 0.020, n - 0.012]
	cprof = [(b.torso_radius(z) + (0.016 if i < 2 or i == len(zs) - 1 else 0.012), z) for i, z in enumerate(zs)]
	bands = [row("brass")] + [row("steel")] * (len(cprof) - 3) + [row("brass")]
	geo.merge(bm, geo.lathe(cprof, segs, sharp=50, sy=b.torso_depth, ring_swatches=bands))
	zg = w + 0.110
	front = Vector((0.0, -(b.torso_radius(zg) + 0.014) * b.torso_depth, zg))
	geo.merge(bm, geo.plate(_star(0.054, 0.040, 0.014), 0.020, row("crystal"), side=row("brass"), sharp=FLAT),
			geo.orient(front, (0.0, -1.0, 0.25)))
	return bm


def warrior_belt(b, lod):
	"""A gold belt with a round crystal clasp."""
	w = b.waist_z
	r = b.torso_radius(w)
	bm = geo.lathe([(r - 0.004, w - 0.018), (r + 0.010, w - 0.014), (r + 0.010, w + 0.014), (r - 0.004, w + 0.018)],
			seg(lod, 12, 8), row("brass"), sharp=40, sy=b.torso_depth)
	clasp = geo.disc(0.026, 0.026, seg(lod, 8, 6), row("crystal"), dome=0.010, depth=0.004)
	geo.merge(bm, clasp, geo.frame((0.0, -(r + 0.010) * b.torso_depth - 0.002, w), (0.0, -1.0, 0.0), (0.0, 0.0, 1.0)))
	return bm


def cowl_scarf(b, lod):
	"""A chunky scarf in the team's colour wound high round the neck, its two
	long tails streaming back over the shoulders (the sprite's flying red
	mane): team colour seen from the front and from above."""
	n = b.neck_z
	bm = geo.lathe([(0.118, n - 0.050), (0.138, n - 0.030), (0.136, n - 0.004), (0.112, n + 0.018),
			(0.090, n + 0.022)], seg(lod, 14, 9), row("team_cloth"), sharp=SMOOTH, sy=0.92,
			cap_start=row("team_cloth_dark"))
	for k, side in enumerate((-1.0, 1.0)):
		root = Vector((side * 0.060, 0.090, n - 0.010))
		pts = [root, root + Vector((side * 0.040, 0.080, -0.010)), root + Vector((side * 0.070, 0.160, -0.060)),
				root + Vector((side * 0.080, 0.215, -0.140 - 0.030 * k)),
				root + Vector((side * 0.070, 0.240, -0.220 - 0.040 * k))]
		geo.merge(bm, geo.tube(pts, [0.040, 0.046, 0.044, 0.036, 0.0], seg(lod, 7, 5), sharp=SMOOTH, flatten=0.30,
				up=(0.0, 0.0, 1.0), ring_swatches=[row("team_cloth"), row("team_cloth"), row("team_cloth_dark"),
				row("team_cloth_dark")]))
	return bm


def crescent_blade(b, lod, fist, side, body, edge, sun=False, size=1.0):
	"""A huge crescent blade held by a gold bar across its hollow, its
	convex cutting edge to the ground (parts.edge_down's rule) and its horns
	up, flat to the camera. sun: a sun crescent with rays along its edge;
	otherwise a moon crescent with a star gem at its belly."""
	bm = geo.new_bm()
	R = 0.215 * size
	cz = 0.070 * size
	wmax = 0.078 * size
	t0, t1 = math.pi - 0.26, 2.0 * math.pi + 0.26
	steps = seg(lod, 15, 9)
	outer, inner = [], []
	for i in range(steps):
		u = i / (steps - 1)
		a = t0 + (t1 - t0) * u
		w = wmax * math.sin(math.pi * u) ** 0.75
		outer.append((math.cos(a) * R, cz + math.sin(a) * R))
		if 0 < i < steps - 1:
			inner.append((math.cos(a) * (R - w), cz + math.sin(a) * (R - w)))
	geo.merge(bm, geo.plate(outer + list(reversed(inner)), 0.026, row(body), side=row(edge), sharp=FLAT))
	# A raised inner band down the crescent's middle, in the edge's colour.
	core_o, core_i = [], []
	for i in range(1, steps - 1):
		u = i / (steps - 1)
		a = t0 + (t1 - t0) * u
		w = wmax * math.sin(math.pi * u) ** 0.75
		core_o.append((math.cos(a) * (R - w * 0.30), cz + math.sin(a) * (R - w * 0.30)))
		core_i.append((math.cos(a) * (R - w * 0.55), cz + math.sin(a) * (R - w * 0.55)))
	if lod == 0:
		geo.merge(bm, geo.plate(core_o + list(reversed(core_i)), 0.032, row(edge), sharp=FLAT))
	if sun:
		for i in range(2, steps - 2, 2 if lod == 0 else 3):
			u = i / (steps - 1)
			a = t0 + (t1 - t0) * u
			d = Vector((math.cos(a), 0.0, math.sin(a)))
			t = Vector((-math.sin(a), 0.0, math.cos(a)))
			base = Vector((math.cos(a) * R, 0.0, cz + math.sin(a) * R)) - d * 0.006
			ray = [(base - t * 0.020).xz, (base + d * 0.050 * size).xz, (base + t * 0.020).xz]
			geo.merge(bm, geo.plate([(p[0], p[1]) for p in ray], 0.018, row(body), side=row(edge), sharp=FLAT))
	else:
		gem = geo.plate(_star(0.040, 0.030, 0.012), 0.034, row("crystal"), side=row(edge), sharp=FLAT)
		geo.translate(gem, (0.0, 0.0, cz - R + wmax * 0.5))
		geo.merge(bm, gem)
	# Gripped near its inner horn, so the blade sweeps out from the body.
	geo.translate(bm, (-side * 0.100 * size, 0.0, 0.0))
	grip = geo.lathe([(0.0, -0.070), (0.016, -0.066), (0.016, 0.040), (0.0, 0.046)], seg(lod, 6, 4), row("brass"),
			sharp=40, phase=0.0)
	geo.merge(bm, grip)
	axis = Vector((side * 0.30, -0.12, 1.0)).normalized()
	geo.transform(bm, geo.frame(fist, axis, (0.0, -1.0, 0.0)))
	return bm


# === the Star Priestess =====================================================

class PriestessBody(parts.Body):
	"""Tall and slender, floating: a long narrow robe hovering clear of the
	ground over a point of starlight, narrow shoulders, a slightly smaller
	head carried higher."""
	foot_x = 0.050
	hem_z = 0.200
	waist_z = 0.360
	shoulder_z = 0.525
	neck_z = 0.585
	torso_depth = 0.82
	head_centre = Vector((0.0, 0.0, 0.752))
	head_size = Vector((0.312, 0.276, 0.288))
	head_tilt_deg = 9.0
	neck_pivot = Vector((0.0, 0.0, 0.610))
	brow_z = 0.798
	## The robe's hem floats this far above the ground.
	hover = 0.075
	r_shoulder = Vector((-0.124, 0.0, 0.508))
	r_elbow = Vector((-0.182, 0.012, 0.428))
	r_wrist = Vector((-0.204, -0.064, 0.430))
	r_fist = Vector((-0.208, -0.094, 0.430))
	pole_axis = Vector((0.0, -0.05, 1.0)).normalized()
	l_shoulder = Vector((0.124, 0.0, 0.508))
	l_elbow = Vector((0.188, -0.040, 0.432))
	l_wrist = Vector((0.160, -0.124, 0.468))
	l_fist = Vector((0.140, -0.148, 0.484))

	def torso_profile(self):
		h, w, s, n = self.hem_z, self.waist_z, self.shoulder_z, self.neck_z
		return [
			(0.130, h), (0.124, h + 0.060), (0.116, w), (0.122, w + 0.060), (0.126, w + 0.110),
			(0.118, s - 0.012), (0.098, s + 0.020), (0.064, n), (0.0, n + 0.004),
		]


def floating_robe(b, lod):
	"""A long white robe, narrow at the waist and belled at the foot, its
	hem floating clear of the ground in a wide band of the team's colour
	under a gold ring; cyan starlight underneath, and a crystal point
	hanging below it."""
	g, w, s, n = b.base_height, b.waist_z, b.shoulder_z, b.neck_z
	z0 = g + b.hover
	prof = [(0.150, z0 - 0.006), (0.192, z0 + 0.004), (0.196, z0 + 0.030), (0.188, z0 + 0.074), (0.185, z0 + 0.078),
			(0.182, z0 + 0.090), (0.152, z0 + 0.170), (0.116, w), (0.122, w + 0.060), (0.126, w + 0.110),
			(0.118, s - 0.012), (0.098, s + 0.020), (0.064, n), (0.0, n + 0.004)]
	bands = [row("team_cloth_dark"), row("team_cloth"), row("team_cloth"), row("brass"), row("brass")] \
			+ [row("robe")] * (len(prof) - 6)
	if lod > 0:
		keep = (0, 1, 3, 5, 6, 7, 9, 10, 11, 12, 13)
		prof = [prof[i] for i in keep]
		bands = [row("team_cloth_dark"), row("team_cloth"), row("brass")] + [row("robe")] * (len(prof) - 4)
	bm = geo.lathe(prof, seg(lod, 16, 10), sharp=SMOOTH, sy=0.86, ring_swatches=bands, cap_start=row("crystal"))
	r = 0.118
	geo.merge(bm, geo.lathe([(r - 0.004, w - 0.014), (r + 0.010, w - 0.010), (r + 0.010, w + 0.010),
			(r - 0.004, w + 0.014)], seg(lod, 12, 8), row("brass"), sharp=40, sy=0.86))
	point = geo.lathe([(0.0, g + 0.006), (0.040, z0 - 0.030), (0.030, z0 + 0.010), (0.0, z0 + 0.020)], seg(lod, 6, 4),
			row("crystal"), sharp=FLAT, phase=0.0)
	geo.merge(bm, point)
	return bm


def stole(b, lod, robe_bm):
	"""A priest's stole in the team's colour: two broad bands from the neck
	down the robe's front to the gold ring above its hem, each ending in a
	gold star."""
	tree = geo.bvh(robe_bm)
	bm = geo.new_bm()
	top = b.neck_z - 0.020
	bottom = b.base_height + b.hover + 0.100
	steps = seg(lod, 9, 5)
	for side in (-1.0, 1.0):
		pts, nrms = [], []
		for i in range(steps):
			t = i / (steps - 1)
			z = top + (bottom - top) * t
			x = side * (0.040 + 0.030 * t)
			loc, nrm = geo.project(tree, (x, -1.0, z), (0.0, 1.0, 0.0))
			if loc is not None:
				pts.append(loc)
				nrms.append(nrm)
		geo.merge(bm, geo.ribbon(pts, nrms, 0.050, 0.008, row("team_cloth"), sharp=SMOOTH, embed=0.003))
		if lod == 0 and pts:
			geo.merge(bm, geo.plate(_star(0.030, 0.030, 0.012, 5), 0.010, row("brass"), sharp=FLAT),
					geo.orient(pts[-1] + nrms[-1] * 0.010, nrms[-1]))
	return bm


def star_mantle(b, lod):
	"""A short porcelain mantle on the shoulders, its edge cut in gold
	star points."""
	s, n = b.shoulder_z, b.neck_z
	bm = geo.lathe([(0.160, s - 0.050), (0.164, s - 0.032), (0.146, s + 0.008), (0.108, n - 0.012),
			(0.082, n + 0.020)], seg(lod, 14, 9), row("steel"), sharp=50, sy=0.86, cap_start=row("plate_dark"))
	count = seg(lod, 10, 6)
	for k in range(count):
		theta = -math.pi / 2.0 + (k + 0.5) * 2.0 * math.pi / count
		out = Vector((math.cos(theta) * 0.161, math.sin(theta) * 0.161 * 0.86, s - 0.046))
		flat = Vector((out.x, out.y, 0.0)).normalized()
		dag = geo.plate([(-0.030, 0.0), (0.030, 0.0), (0.0, -0.046)], 0.008, row("brass"), sharp=FLAT)
		geo.transform(dag, geo.orient(out + flat * 0.002, flat, (0.0, 0.0, 1.0)))
		geo.merge(bm, dag)
	return bm


def star_crown(b, lod):
	"""A gold circlet with three star-tipped points over the brow (the tall
	middle one holding a violet gem), and a gold halo standing behind the
	head, studded with star points."""
	bm = geo.new_bm()
	c = b.head_centre
	z = b.brow_z - 0.006
	sy = 0.94
	geo.merge(bm, geo.lathe([(0.160, z - 0.014), (0.166, z), (0.164, z + 0.018), (0.156, z + 0.024)], seg(lod, 16, 10),
			row("brass"), sharp=40, sy=sy))
	for k, h in ((-1, 0.070), (0, 0.112), (1, 0.070)):
		theta = -math.pi / 2.0 + k * 0.48
		out = Vector((math.cos(theta), math.sin(theta) * sy, 0.0))
		w = 0.030 if k == 0 else 0.024
		spike = geo.plate([(-w, 0.0), (w, 0.0), (w * 0.35, h * 0.6), (0.0, h), (-w * 0.35, h * 0.6)], 0.014,
				row("brass"), sharp=FLAT)
		geo.transform(spike, geo.orient(Vector((0.0, 0.0, z + 0.010)) + out * 0.164, out,
				Vector((0.0, 0.0, 1.0)) + out * 0.25))
		geo.merge(bm, spike)
		if k == 0:
			gem = geo.disc(0.020, 0.024, seg(lod, 8, 5), row("arcane"), dome=0.010, depth=0.004)
			geo.merge(bm, gem, geo.frame(Vector((0.0, 0.0, z + 0.030)) + out * 0.172, out, (0.0, 0.0, 1.0)))
	# The halo, standing behind the head and leaning back with it.
	centre = Vector((0.0, c.y + 0.150, c.z + 0.060))
	normal = Vector((0.0, 1.0, 0.18)).normalized()
	ring = geo.lathe([(0.205, -0.012), (0.218, 0.0), (0.205, 0.012), (0.192, 0.0)], seg(lod, 20, 12), row("brass"),
			sharp=40)
	ring_m = geo.frame(centre, normal, (0.0, 0.0, 1.0))
	geo.merge(bm, ring, ring_m)
	count = seg(lod, 8, 4)
	for k in range(count):
		a = math.pi / 2.0 + k * 2.0 * math.pi / count
		local_out = Vector((math.cos(a), math.sin(a), 0.0))
		root = ring_m @ (local_out * 0.214)
		d = (ring_m.to_3x3() @ local_out).normalized()
		ln = 0.060 if k % 2 == 0 else 0.036
		geo.merge(bm, geo.tube([root, root + d * ln * 0.5, root + d * ln], [0.018, 0.010, 0.0], seg(lod, 5, 4),
				row("brass") if k % 2 else row("crystal"), sharp=40, cap_start=row("brass"), flatten=0.5,
				up=tuple(normal)))
	geo.translate(bm, (c.x, 0.004, 0.0))
	return bm


def star_staff(b, lod, below=0.33):
	"""A tall gold staff whose head is a gold ring round a big violet orb,
	four gold star points flaring from the ring and a cyan crystal at the
	top, flat to the camera."""
	axis = Vector(b.pole_axis).normalized()
	fist = b.r_fist
	foot = fist - axis * below
	top = fist + axis * 0.52
	bm = geo.tube([foot, top], [0.018, 0.022], seg(lod, 6, 5), row("brass"), sharp=40, cap_start=row("brass"))
	for t in (0.06, 0.45):
		p = fist + axis * t
		geo.merge(bm, geo.lathe([(0.028, -0.018), (0.032, 0.0), (0.028, 0.018)], seg(lod, 6, 5), row("arcane"),
				sharp=40, phase=0.0), geo.frame(p, axis))
	centre = top + axis * 0.100
	m = geo.frame(centre, (0.0, -1.0, 0.0), axis)
	head = geo.new_bm()
	geo.merge(head, geo.lathe([(0.088, -0.014), (0.098, 0.0), (0.088, 0.014), (0.076, 0.0)], seg(lod, 16, 10),
			row("brass"), sharp=40))
	geo.merge(head, geo.ellipsoid(0.062, 0.062, 0.062, seg(lod, 10, 6), seg(lod, 6, 4), row("arcane"), sharp=SMOOTH))
	for k in range(4):
		a = math.pi / 2.0 + k * math.pi / 2.0
		d = Vector((math.cos(a), math.sin(a), 0.0))
		t = Vector((-d.y, d.x, 0.0))
		ln = 0.110 if k == 0 else 0.080
		root = d * 0.090
		pts = [root - t * 0.030, root + d * ln, root + t * 0.030]
		pts += [root - d * 0.006]
		ray = geo.plate([(p.x, p.y) for p in pts], 0.020, row("brass"), sharp=FLAT)
		geo.rotate(ray, -90.0, 'X')
		geo.merge(head, ray)
	tip = geo.lathe([(0.0, 0.0), (0.024, 0.030), (0.0, 0.080)], seg(lod, 6, 4), row("crystal"), sharp=FLAT,
			phase=0.0)
	geo.transform(head, m)
	geo.merge(bm, head)
	geo.merge(bm, tip, geo.frame(centre + axis * 0.190, axis))
	return bm


def _crescent(R, wmax, t0, t1, steps, cz=0.0):
	"""A crescent outline in local XZ round (0, cz): its outer edge on a
	circle of radius R from angle t0 to t1, its width swelling to wmax in
	the middle and tapering to the horns."""
	outer, inner = [], []
	for i in range(steps):
		u = i / (steps - 1)
		a = t0 + (t1 - t0) * u
		w = wmax * math.sin(math.pi * u) ** 0.75
		outer.append((math.cos(a) * R, cz + math.sin(a) * R))
		if 0 < i < steps - 1:
			inner.append((math.cos(a) * (R - w), cz + math.sin(a) * (R - w)))
	return outer + list(reversed(inner))


def _lean(b, bm):
	"""Leans what is above the waist forward (-Y) by b.hunch per metre."""
	for v in bm.verts:
		if v.co.z > b.waist_z:
			v.co.y -= b.hunch * (v.co.z - b.waist_z)
	return bm


# === the Star Hunter ========================================================

class HunterBody(parts.Body):
	"""Light, low and crouched forward: short bent legs set wide, a slim
	body leaning in over them, the head carried low and forward, a
	crossbow levelled at the chest."""
	foot_x = 0.094
	hem_z = 0.160
	waist_z = 0.250
	shoulder_z = 0.404
	neck_z = 0.458
	torso_depth = 0.80
	## How far the body leans forward per metre above the waist.
	hunch = 0.26
	head_centre = Vector((0.0, 0.0, 0.628))
	head_size = Vector((0.322, 0.284, 0.294))
	head_tilt_deg = 7.0
	neck_pivot = Vector((0.0, 0.0, 0.484))
	brow_z = 0.676
	r_shoulder = Vector((-0.124, -0.036, 0.390))
	r_elbow = Vector((-0.180, -0.020, 0.316))
	r_wrist = Vector((-0.110, -0.112, 0.322))
	r_fist = Vector((-0.080, -0.140, 0.326))
	l_shoulder = Vector((0.124, -0.036, 0.390))
	l_elbow = Vector((0.168, -0.120, 0.338))
	l_wrist = Vector((0.084, -0.212, 0.336))
	l_fist = Vector((0.056, -0.238, 0.338))
	stock_rear = Vector((-0.086, -0.080, 0.330))
	stock_front = Vector((0.010, -0.440, 0.350))

	def torso_profile(self):
		h, w, s, n = self.hem_z, self.waist_z, self.shoulder_z, self.neck_z
		return [
			(0.126, h), (0.132, h + 0.010), (0.126, h + 0.030), (0.108, h + 0.062),
			(0.098, w), (0.114, w + 0.050), (0.124, w + 0.098),
			(0.118, s - 0.012), (0.094, s + 0.020), (0.062, n), (0.0, n + 0.004),
		]

	def head_shift(self):
		"""How far the lean carries the head forward."""
		return Vector((0.0, -self.hunch * (self.neck_z - self.waist_z), 0.0))


def hunter_legs(b, lod):
	"""Short legs bent at the knee in a crouch, set wide: midnight, with
	porcelain knee guards and porcelain boots with gold cuffs."""
	bm = geo.new_bm()
	g = b.base_height
	for side in (-1.0, 1.0):
		x = side * b.foot_x
		knee = Vector((x * 1.06, -0.050, g + 0.118))
		pts = [Vector((x, -0.004, g + 0.070)), knee, Vector((x * 0.84, 0.006, b.hem_z + 0.040))]
		geo.merge(bm, geo.tube(pts, [0.036, 0.042, 0.050], seg(lod, 8, 5), row("plate_dark"), sharp=SMOOTH))
		pad = geo.ellipsoid(0.034, 0.024, 0.036, seg(lod, 8, 5), seg(lod, 4, 3), row("steel"), sharp=SMOOTH)
		geo.translate(pad, knee + Vector((0.0, -0.030, 0.006)))
		geo.merge(bm, pad)
	boots = parts.boots(b, lod)
	for src, dst in (("boot", "steel"), ("leather", "brass"), ("sole", "plate_dark")):
		_recolour(boots, src, dst)
	geo.merge(bm, boots)
	return bm


def hunter_torso(b, lod):
	"""A slim midnight suit with a porcelain breastplate, leaning in."""
	prof = b.torso_profile()
	segs = seg(lod, 14, 9)
	if lod > 0:
		keep = (0, 1, 2, 4, 6, 8, 9, 10)
		prof = [prof[i] for i in keep]
	bm = geo.lathe(prof, segs, row("plate_dark"), sharp=SMOOTH, sy=b.torso_depth, cap_start=row("plate_dark"))
	w, s = b.waist_z, b.shoulder_z
	zs = [w + 0.030, w + 0.040, w + 0.090, s - 0.030, s - 0.012]
	cprof = [(b.torso_radius(z) + 0.012, z) for z in zs]
	plate = geo.lathe(cprof, segs, sharp=50, sy=b.torso_depth,
			ring_swatches=[row("brass"), row("steel"), row("steel"), row("brass")])
	geo.delete_faces(plate, lambda f: f.calc_center_median().y > -0.030)
	geo.merge(bm, plate)
	return _lean(b, bm)


def hunter_hood(b, lod):
	"""A deep hood-scarf in the team's colour drawn up over the head, the
	fins standing up through it, over a broad dagged capelet: the team's
	colour from the front and from above. Its opening shows the whole face;
	the scarf wound under the chin fills the neck."""
	c = b.head_centre
	shell = geo.ellipsoid(0.194, 0.182, 0.194, seg(lod, 12, 9), seg(lod, 8, 6), row("team_cloth"), sharp=SMOOTH)
	for v in shell.verts:
		up = max(0.0, v.co.z / 0.194)
		back = max(0.0, v.co.y / 0.182)
		v.co.y += 0.085 * up * up * (0.4 + back)
		v.co.z += 0.030 * up * up * back
	geo.translate(shell, (c.x, c.y + 0.012, c.z + 0.014))

	def opening(f):
		m = f.calc_center_median()
		return (m.y < c.y - 0.04 and abs(m.x - c.x) < 0.170 and m.z < b.brow_z + 0.040) or m.z < c.z - 0.150

	geo.delete_faces(shell, opening)
	bm = geo.new_bm()
	geo.merge(bm, shell)
	geo.merge(bm, geo.flipped(shell, row("team_cloth_dark"), inset=0.007))
	return bm


def hunter_scarf(b, lod):
	"""The hood's scarf wound thick round the neck under the chin, one long
	tail streaming back over the shoulder."""
	n = b.neck_z
	bm = geo.lathe([(0.106, n - 0.040), (0.134, n - 0.020), (0.134, n + 0.006), (0.110, n + 0.026),
			(0.086, n + 0.030)], seg(lod, 14, 9), row("team_cloth"), sharp=SMOOTH, sy=0.92,
			cap_start=row("team_cloth_dark"))
	root = Vector((0.070, 0.080, n - 0.004))
	pts = [root, root + Vector((0.040, 0.070, -0.020)), root + Vector((0.070, 0.140, -0.080)),
			root + Vector((0.080, 0.180, -0.170)), root + Vector((0.070, 0.190, -0.240))]
	geo.merge(bm, geo.tube(pts, [0.044, 0.050, 0.046, 0.038, 0.0], seg(lod, 7, 5), sharp=SMOOTH, flatten=0.32,
			up=(0.0, 0.0, 1.0), ring_swatches=[row("team_cloth"), row("team_cloth"), row("team_cloth_dark"),
			row("team_cloth_dark")]))
	return _lean(b, bm)


def crystal_visor(b, lod, head_bm):
	"""A band of cyan crystal across the eyes, wrapped round the face in a
	gold frame. Built on the head before it is tipped back."""
	tree = geo.bvh(head_bm)
	c = b.head_centre
	z = c.z - 0.010
	bm = geo.new_bm()
	steps = seg(lod, 9, 5)
	pts, nrms = [], []
	for i in range(steps):
		t = -1.0 + 2.0 * i / (steps - 1)
		loc, nrm = geo.project(tree, (c.x + t * 0.146, -1.0, z), (0.0, 1.0, 0.0))
		if loc is not None:
			pts.append(loc + nrm * 0.014)
			nrms.append(nrm)
	widths = [0.050 + 0.024 * (1.0 - abs(-1.0 + 2.0 * i / (len(pts) - 1))) for i in range(len(pts))]
	geo.merge(bm, geo.ribbon(pts, nrms, 0.0, 0.014, row("crystal"), sharp=SMOOTH, embed=0.0, widths=widths))
	for dz_k in (0.5, -0.5):
		rim = [p + Vector((0.0, 0.0, wd * dz_k)) for p, wd in zip(pts, widths)]
		geo.merge(bm, geo.ribbon(rim, nrms, 0.010, 0.020, row("brass"), sharp=40, embed=0.0))
	return bm


def star_crossbow(b, lod):
	"""A crystal crossbow levelled forward: a midnight stock banded in gold,
	a violet moon crescent for its prod bowed forward, a cyan string and a
	glowing cyan bolt laid in the groove with a star at its tip."""
	import gear
	rear, front = b.stock_rear, b.stock_front
	forward = (front - rear).normalized()
	length = (front - rear).length
	mid = (front + rear) * 0.5
	bev = 0.006 if lod == 0 else 0.0
	bm = geo.box(0.036, length, 0.040, row("plate_dark"), 40, bevel=bev)
	butt = geo.box(0.044, 0.090, 0.064, row("plate_dark"), 40, bevel=bev)
	geo.translate(butt, (0.0, length * 0.5 - 0.02, -0.014))
	geo.merge(bm, butt)
	for y in (length * 0.5 - 0.075, -length * 0.5 + 0.075):
		band = geo.box(0.044, 0.016, 0.048, row("brass"), 40)
		geo.translate(band, (0.0, y, 0.0))
		geo.merge(bm, band)
	tip = -length * 0.5 + 0.03
	# The prod: a thick violet crescent lying flat, bowed forward, horns back.
	R = 0.170
	prod = geo.plate(_crescent(R, 0.062, 0.20, math.pi - 0.20, seg(lod, 13, 7)), 0.026, row("arcane"),
			side=row("brass"), sharp=FLAT)
	geo.rotate(prod, 90.0, 'X')
	cy = tip + R - 0.020
	geo.translate(prod, (0.0, cy, 0.012))
	geo.merge(bm, prod)
	horn_y = cy - math.sin(0.20) * R
	nut = Vector((0.0, tip + 0.150, 0.026))
	for sx in (-1.0, 1.0):
		end = Vector((sx * math.cos(0.20) * R * 0.97, horn_y, 0.012))
		geo.merge(bm, geo.tube([end, nut], [0.0055, 0.0055], 3, row("crystal"), sharp=SMOOTH))
	bolt = geo.lathe([(0.009, 0.0), (0.009, 0.20)], seg(lod, 5, 4), row("crystal"), sharp=SMOOTH, phase=0.0,
			cap_start=row("crystal"))
	geo.rotate(bolt, 90.0, 'X')
	geo.translate(bolt, (0.0, tip + 0.150, 0.030))
	geo.merge(bm, bolt)
	star = geo.plate(_star(0.036, 0.030, 0.012), 0.012, row("crystal"), side=row("brass"), sharp=FLAT)
	geo.translate(star, (0.0, tip - 0.070, 0.030))
	geo.merge(bm, star)
	geo.transform(bm, geo.orient(mid, forward))
	pivot = rear + forward * (b.r_fist - rear).dot(forward)
	return gear.grow(bm, pivot, 1.25)


def star_quiver(b, lod):
	"""A gold-rimmed midnight quiver on the right hip, cyan bolts in it."""
	import beastmen
	bm = beastmen.bolt_quiver(b, lod)
	_recolour(bm, "leather_dark", "brass")
	_recolour(bm, "leather", "plate_dark")
	_recolour(bm, "fletch", "crystal")
	return bm


# === the Star Spearman ======================================================

class SpearmanBody(parts.Body):
	"""Lanky and long-limbed: long thin legs, a narrow chest, a slightly
	smaller head carried high, the spear stood upright in the right fist
	and a small star buckler on the left forearm."""
	foot_x = 0.058
	hem_z = 0.262
	waist_z = 0.358
	shoulder_z = 0.512
	neck_z = 0.570
	torso_depth = 0.78
	head_centre = Vector((0.0, 0.0, 0.736))
	head_size = Vector((0.300, 0.268, 0.282))
	head_tilt_deg = 9.0
	neck_pivot = Vector((0.0, 0.0, 0.596))
	brow_z = 0.780
	r_shoulder = Vector((-0.118, 0.0, 0.496))
	r_elbow = Vector((-0.186, 0.022, 0.404))
	r_wrist = Vector((-0.206, -0.050, 0.370))
	r_fist = Vector((-0.208, -0.080, 0.366))
	pole_axis = Vector((0.0, -0.08, 1.0)).normalized()
	l_shoulder = Vector((0.118, 0.0, 0.496))
	l_elbow = Vector((0.184, -0.020, 0.406))
	l_wrist = Vector((0.172, -0.100, 0.392))
	l_fist = Vector((0.160, -0.128, 0.392))
	buckler_centre = Vector((0.196, -0.130, 0.384))
	buckler_normal = Vector((0.50, -0.86, 0.08)).normalized()

	def torso_profile(self):
		h, w, s, n = self.hem_z, self.waist_z, self.shoulder_z, self.neck_z
		return [
			(0.108, h), (0.112, h + 0.010), (0.106, h + 0.030), (0.094, h + 0.060),
			(0.088, w), (0.102, w + 0.050), (0.114, w + 0.100),
			(0.110, s - 0.012), (0.088, s + 0.020), (0.058, n), (0.0, n + 0.004),
		]


def spearman_legs(b, lod):
	"""Long thin midnight legs with porcelain knee guards, porcelain boots
	with gold cuffs."""
	bm = geo.new_bm()
	g = b.base_height
	for side in (-1.0, 1.0):
		x = side * b.foot_x
		leg = geo.lathe([(0.032, g + 0.080), (0.036, g + 0.140), (0.042, b.hem_z + 0.050)], seg(lod, 8, 5),
				row("plate_dark"))
		geo.translate(leg, (x, 0.0, 0.0))
		geo.merge(bm, leg)
		pad = geo.ellipsoid(0.030, 0.022, 0.034, seg(lod, 8, 5), seg(lod, 4, 3), row("steel"), sharp=SMOOTH)
		geo.translate(pad, (x, -0.030, g + 0.150))
		geo.merge(bm, pad)
	boots = parts.boots(b, lod)
	for src, dst in (("boot", "steel"), ("leather", "brass"), ("sole", "plate_dark")):
		_recolour(boots, src, dst)
	geo.merge(bm, boots)
	return bm


def spearman_torso(b, lod):
	"""A narrow midnight suit under a porcelain gorget edged in gold."""
	prof = b.torso_profile()
	segs = seg(lod, 14, 9)
	if lod > 0:
		keep = (0, 1, 2, 4, 6, 8, 9, 10)
		prof = [prof[i] for i in keep]
	bm = geo.lathe(prof, segs, row("plate_dark"), sharp=SMOOTH, sy=b.torso_depth, cap_start=row("plate_dark"))
	s, n = b.shoulder_z, b.neck_z
	zs = [s - 0.060, s - 0.050, s - 0.012, s + 0.020, n - 0.010]
	cprof = [(b.torso_radius(z) + (0.016 if i in (0, len(zs) - 1) else 0.012), z) for i, z in enumerate(zs)]
	geo.merge(bm, geo.lathe(cprof, segs, sharp=50, sy=b.torso_depth,
			ring_swatches=[row("brass"), row("steel"), row("steel"), row("brass")]))
	return bm


def spearman_tabard(b, lod, half_width=0.074, out=0.012):
	"""A long tabard in the team's colour down the front, from under the
	gorget to the knees, its hem darker; lined."""
	h, w, s = b.hem_z, b.waist_z, b.shoulder_z
	zs = [h - 0.110, h - 0.096, h - 0.040, h + 0.010, h + 0.060, w, w + 0.050, w + 0.100, s - 0.050]
	prof = []
	for z in zs:
		r = b.torso_radius(max(z, h + 0.010)) + out
		if z < h:
			r += (h - z) * 0.20
		prof.append((r, z))
	bands = [row("team_cloth_dark")] + [row("team_cloth")] * (len(prof) - 2)
	shell = geo.lathe(prof, seg(lod, 24, 16), sharp=SMOOTH, sy=b.torso_depth, ring_swatches=bands)
	geo.delete_faces(shell, lambda f: abs(f.calc_center_median().x) > half_width or f.calc_center_median().y > 0.0)
	bm = geo.new_bm()
	geo.merge(bm, shell)
	geo.merge(bm, geo.flipped(shell, row("team_cloth_dark"), inset=0.004))
	return bm


def crescent_spear(b, lod, length=1.34, below=0.30):
	"""A tall spear: a porcelain shaft banded in gold, a gold moon crescent
	at its head, horns up, and a long violet crystal point rising from the
	crescent's belly, flat to the camera."""
	import gear
	top = length - below
	bm = geo.lathe([(0.016, -below), (0.016, top - 0.10)], seg(lod, 6, 5), row("steel"), sharp=40, phase=0.0,
			cap_start=row("brass"), cap_end=row("brass"))
	for z in (-below + 0.02, 0.06, 0.20, top - 0.12):
		geo.merge(bm, geo.lathe([(0.022, z - 0.014), (0.024, z), (0.022, z + 0.014)], seg(lod, 6, 5), row("brass"),
				sharp=40, phase=0.0))
	R = 0.110
	cz = top - 0.040 + R
	moon = geo.plate(_crescent(R, 0.044, math.pi + 0.30, 2.0 * math.pi - 0.30, seg(lod, 13, 7), cz), 0.022,
			row("brass"), side=row("trim"), sharp=FLAT)
	geo.merge(bm, moon)
	point = geo.plate([(0.0, top - 0.060), (0.040, top + 0.030), (0.026, top + 0.140), (0.0, top + 0.260),
			(-0.026, top + 0.140), (-0.040, top + 0.030)], 0.024, row("arcane"), side=row("crystal"), sharp=FLAT)
	geo.merge(bm, point)
	if lod == 0:
		gem = geo.plate(_star(0.026, 0.020, 0.009), 0.030, row("crystal"), side=row("brass"), sharp=FLAT)
		geo.translate(gem, (0.0, 0.0, cz - R + 0.022))
		geo.merge(bm, gem)
	return gear._place(bm, b, b.r_fist, b.pole_axis)


def star_buckler(b, lod):
	"""A small round gold buckler on the left forearm, a big violet
	four-pointed star over its face reaching past the rim."""
	bm = geo.lathe([(0.0, -0.010), (0.072, -0.010), (0.078, 0.006), (0.064, 0.016), (0.0, 0.024)], seg(lod, 14, 9),
			row("brass"), sharp=40, phase=0.0)
	star = geo.plate(_star(0.112, 0.112, 0.034), 0.016, row("arcane"), side=row("brass"), sharp=FLAT)
	geo.rotate(star, -90.0, 'X')
	geo.translate(star, (0.0, 0.0, 0.026))
	geo.merge(bm, star)
	geo.merge(bm, geo.disc(0.020, 0.020, seg(lod, 8, 5), row("crystal"), dome=0.012, depth=0.004),
			Matrix.Translation((0.0, 0.0, 0.034)))
	geo.transform(bm, geo.frame(b.buckler_centre, b.buckler_normal, (0.0, 0.0, 1.0)))
	return bm


def _big_boots(b, lod, k):
	"""Porcelain boots with gold cuffs, scaled up by k round the ground
	(their feet still at b.foot_x)."""
	import types
	import gear
	proxy = types.SimpleNamespace(base_height=b.base_height, foot_x=b.foot_x / k)
	boots = parts.boots(proxy, lod)
	for src, dst in (("boot", "steel"), ("leather", "brass"), ("sole", "plate_dark")):
		_recolour(boots, src, dst)
	return gear.grow(boots, (0.0, 0.0, b.base_height), k)


# === the Star Knight ========================================================

class KnightBody(parts.Body):
	"""Tall and straight-sided, armoured head to toe: long porcelain legs,
	a deep porcelain chest on a high waist, a crested helm, a long crystal
	sword raised out to the right and a tall kite shield on the left."""
	foot_x = 0.072
	hem_z = 0.236
	waist_z = 0.338
	shoulder_z = 0.506
	neck_z = 0.566
	torso_depth = 0.82
	head_centre = Vector((0.0, 0.0, 0.734))
	head_size = Vector((0.322, 0.284, 0.294))
	head_tilt_deg = 9.0
	neck_pivot = Vector((0.0, 0.0, 0.592))
	brow_z = 0.780
	r_shoulder = Vector((-0.158, 0.0, 0.486))
	r_elbow = Vector((-0.234, 0.010, 0.418))
	r_wrist = Vector((-0.262, -0.052, 0.398))
	r_fist = Vector((-0.266, -0.082, 0.396))
	sword_axis = Vector((-0.34, -0.22, 1.0)).normalized()
	l_shoulder = Vector((0.158, 0.0, 0.486))
	l_elbow = Vector((0.222, -0.006, 0.404))
	l_wrist = Vector((0.204, -0.088, 0.392))
	l_fist = Vector((0.186, -0.116, 0.392))
	shield_centre = Vector((0.214, -0.170, 0.370))
	shield_normal = Vector((0.40, -0.91, 0.06)).normalized()

	def torso_profile(self):
		h, w, s, n = self.hem_z, self.waist_z, self.shoulder_z, self.neck_z
		return [
			(0.124, h), (0.130, h + 0.010), (0.126, h + 0.030), (0.116, h + 0.060),
			(0.114, w), (0.142, w + 0.060), (0.158, w + 0.118),
			(0.158, s - 0.012), (0.132, s + 0.022), (0.080, n), (0.0, n + 0.004),
		]


def knight_legs(b, lod):
	"""Long porcelain legs: greaves with gold knee rings and round knee
	cops, porcelain sabatons with gold cuffs."""
	bm = geo.new_bm()
	g = b.base_height
	for side in (-1.0, 1.0):
		x = side * b.foot_x
		leg = geo.lathe([(0.046, g + 0.090), (0.052, g + 0.130), (0.050, g + 0.150), (0.056, b.hem_z + 0.040)],
				seg(lod, 8, 5), row("steel"), sharp=40)
		geo.translate(leg, (x, 0.0, 0.0))
		geo.merge(bm, leg)
		ring = geo.lathe([(0.054, -0.010), (0.060, 0.0), (0.054, 0.010)], seg(lod, 8, 5), row("brass"), sharp=40)
		geo.translate(ring, (x, 0.0, g + 0.150))
		geo.merge(bm, ring)
		cop = geo.ellipsoid(0.036, 0.024, 0.038, seg(lod, 8, 5), seg(lod, 4, 3), row("steel"), sharp=40)
		geo.translate(cop, (x, -0.044, g + 0.154))
		geo.merge(bm, cop)
	geo.merge(bm, _big_boots(b, lod, 1.12))
	return bm


def knight_torso(b, lod):
	"""Porcelain plate over the whole body: a deep cuirass with a gold rim
	at the neck and a gold keel down its front, a cyan star at its top."""
	prof = b.torso_profile()
	segs = seg(lod, 14, 9)
	bands = [row("steel")] * 7 + [row("brass"), row("brass"), row("steel")]
	if lod > 0:
		keep = (0, 1, 2, 4, 6, 8, 9, 10)
		prof = [prof[i] for i in keep]
		bands = [row("steel")] * 5 + [row("brass"), row("steel")]
	bm = geo.lathe(prof, segs, sharp=50, sy=b.torso_depth, ring_swatches=bands, cap_start=row("plate_dark"))
	w, s = b.waist_z, b.shoulder_z
	tree = geo.bvh(bm)
	pts, nrms = [], []
	n_pts = seg(lod, 6, 3)
	for i in range(n_pts):
		z = w + 0.010 + (s - 0.040 - w - 0.010) * i / (n_pts - 1)
		loc, nrm = geo.project(tree, (0.0, -1.0, z), (0.0, 1.0, 0.0))
		if loc is not None:
			pts.append(loc)
			nrms.append(nrm)
	geo.merge(bm, geo.ribbon(pts, nrms, 0.030, 0.012, row("brass"), sharp=40, embed=0.002))
	if pts:
		geo.merge(bm, geo.plate(_star(0.040, 0.030, 0.012), 0.016, row("crystal"), side=row("brass"), sharp=FLAT),
				geo.orient(pts[-1] + nrms[-1] * 0.012, nrms[-1]))
	return bm


def knight_skirt(b, lod):
	"""A full surcoat skirt in the team's colour from the waist to the
	knees, flared and lined, its hem darker: the team's colour all round,
	under a gold belt."""
	h, w = b.hem_z, b.waist_z
	rw = b.torso_radius(w)
	prof = [(rw + 0.050, h - 0.090), (rw + 0.052, h - 0.074), (rw + 0.040, h - 0.020), (rw + 0.024, h + 0.040),
			(rw + 0.012, w - 0.010), (rw + 0.006, w + 0.016)]
	bands = [row("team_cloth_dark"), row("team_cloth_dark")] + [row("team_cloth")] * (len(prof) - 3)
	shell = geo.lathe(prof, seg(lod, 18, 12), sharp=SMOOTH, sy=b.torso_depth, ring_swatches=bands)
	bm = geo.new_bm()
	geo.merge(bm, shell)
	geo.merge(bm, geo.flipped(shell, row("team_cloth_dark"), inset=0.004))
	r = rw + 0.010
	geo.merge(bm, geo.lathe([(r - 0.004, w - 0.020), (r + 0.010, w - 0.016), (r + 0.010, w + 0.012),
			(r - 0.004, w + 0.016)], seg(lod, 12, 8), row("brass"), sharp=40, sy=b.torso_depth))
	return bm


def crested_helm(b, lod):
	"""A porcelain helm closed over the skull, the cheeks and the back of
	the neck, open over the face, a gold rim and a cyan star over the brow,
	and a tall arched crest in the team's colour from brow to nape. The fins
	stand up through it."""
	c = b.head_centre
	z = b.brow_z
	sy = 0.95
	segs = seg(lod, 16, 10)
	prof = [(0.196, z - 0.150), (0.192, z - 0.080), (0.188, z + 0.000), (0.182, z + 0.056), (0.160, z + 0.116),
			(0.112, z + 0.160), (0.052, z + 0.178), (0.0, z + 0.182)]
	if lod > 0:
		prof = [prof[i] for i in (0, 2, 4, 5, 7)]

	def cheeks(theta, r, zz):
		front = max(0.0, -math.sin(theta)) ** 3
		if zz < z + 0.022:
			zz = z + 0.022 - (z + 0.022 - zz) * (1.0 - 0.97 * front)
		return (r * math.cos(theta), r * math.sin(theta) * sy, zz)

	bands = [row("brass")] + [row("steel")] * (len(prof) - 2)
	shell = geo.lathe(prof, segs, sharp=50, warp=cheeks, ring_swatches=bands)
	bm = geo.new_bm()
	geo.merge(bm, shell)
	geo.merge(bm, geo.flipped(shell, row("lining"), inset=0.006))
	geo.merge(bm, geo.lathe([(0.188, z + 0.012), (0.194, z + 0.022), (0.194, z + 0.036), (0.188, z + 0.044)], segs,
			row("brass"), sharp=40, sy=sy))
	geo.merge(bm, geo.plate(_star(0.044, 0.034, 0.012), 0.016, row("crystal"), side=row("brass"), sharp=FLAT),
			geo.orient(Vector((0.0, -0.190 * sy - 0.004, z + 0.066)), (0.0, -1.0, 0.30)))
	# The crest: an arched slab across the crown, front to back.
	cz = z - 0.020
	steps = seg(lod, 13, 7)
	outer, inner = [], []
	for i in range(steps):
		u = i / (steps - 1)
		a = math.radians(42.0 + 128.0 * u)
		hgt = 0.050 + 0.070 * math.sin(math.pi * min(1.0, u * 1.25)) ** 0.8
		r_in = 0.170
		outer.append((-math.cos(a) * (r_in + hgt), cz + math.sin(a) * (r_in + hgt)))
		inner.append((-math.cos(a) * r_in, cz + math.sin(a) * r_in))
	crest = geo.plate(outer + list(reversed(inner)), 0.060, row("team_cloth"), side=row("team_cloth_dark"),
			sharp=SMOOTH)
	geo.rotate(crest, 90.0, 'Z')
	geo.merge(bm, crest)
	geo.translate(bm, (c.x, c.y + 0.004, 0.0))
	return bm


def crystal_longsword(b, lod, size=1.2):
	"""A long violet crystal sword raised in the right fist: a tapering
	blade with a cyan core, a gold crescent guard with its horns up, a
	midnight grip and a cyan pommel; edge down."""
	import gear
	bm = geo.new_bm()
	L = 0.420
	base = 0.034
	blade = geo.plate([(-0.036, base), (0.036, base), (0.032, base + L * 0.78), (0.0, base + L),
			(-0.032, base + L * 0.78)], 0.020, row("arcane"), side=row("crystal"), sharp=FLAT)
	geo.merge(bm, blade)
	if lod == 0:
		geo.merge(bm, geo.plate([(-0.010, base + 0.020), (0.010, base + 0.020), (0.008, base + L * 0.74),
				(0.0, base + L * 0.84), (-0.008, base + L * 0.74)], 0.026, row("crystal"), sharp=FLAT))
	R = 0.090
	guard = geo.plate(_crescent(R, 0.034, math.pi + 0.30, 2.0 * math.pi - 0.30, seg(lod, 11, 7), R + 0.004), 0.030,
			row("brass"), side=row("trim"), sharp=FLAT)
	geo.merge(bm, guard)
	geo.merge(bm, geo.lathe([(0.0, -0.090), (0.015, -0.086), (0.015, 0.008), (0.0, 0.012)], seg(lod, 6, 4),
			row("plate_dark"), sharp=40, phase=0.0))
	pommel = geo.ellipsoid(0.024, 0.024, 0.026, seg(lod, 6, 5), 3, row("crystal"), sharp=40)
	geo.translate(pommel, (0.0, 0.0, -0.104))
	geo.merge(bm, pommel)
	geo.transform(bm, geo.frame(b.r_fist, b.sword_axis, parts.edge_down(b.sword_axis)))
	return gear.grow(bm, b.r_fist, size)


def kite_shield(b, lod):
	"""A tall gold kite shield on the left arm: a rounded top tapering to a
	point, a gold rim round a face in the team's colour, a big cyan star
	over its upper half."""
	half, top, tip = 0.140, 0.100, -0.330
	steps = seg(lod, 7, 4)
	outline = []
	for i in range(steps + 1):
		t = math.pi * i / steps
		outline.append((half * math.cos(t), top + 0.082 * math.sin(t)))
	for i in range(1, steps + 1):
		s = i / steps
		outline.append((-half * (1.0 - s ** 1.7), top - (top - tip) * s))
	for i in range(steps - 1, 0, -1):
		s = i / steps
		outline.append((half * (1.0 - s ** 1.7), top - (top - tip) * s))
	bm = geo.plate(outline, 0.028, row("brass"), back=row("plate_dark"), side=row("trim"), sharp=40, bend=0.9)
	face = geo.plate([(x * 0.84, z * 0.86 + 0.002) for x, z in outline], 0.008, row("team"), sharp=40, bend=0.9)
	geo.translate(face, (0.0, -0.014, 0.0))
	geo.merge(bm, face)
	star = geo.plate(_star(0.080, 0.064, 0.022), 0.010, row("crystal"), side=row("brass"), sharp=FLAT)
	geo.translate(star, (0.0, -0.024, 0.040))
	geo.merge(bm, star)
	geo.transform(bm, geo.orient(b.shield_centre, b.shield_normal))
	return bm


# === the Star Paladin =======================================================

class PaladinBody(parts.Body):
	"""The biggest: a huge barrel of porcelain on short thick legs set wide,
	the head sunk low between great gold shoulders, a long white beard, a
	huge gold star hammer stood upright in the right fist."""
	foot_x = 0.112
	hem_z = 0.168
	waist_z = 0.282
	shoulder_z = 0.468
	neck_z = 0.516
	torso_depth = 0.86
	head_centre = Vector((0.0, -0.010, 0.682))
	head_size = Vector((0.310, 0.276, 0.284))
	head_tilt_deg = 9.0
	neck_pivot = Vector((0.0, 0.0, 0.540))
	brow_z = 0.728
	r_shoulder = Vector((-0.212, 0.0, 0.440))
	r_elbow = Vector((-0.284, 0.012, 0.356))
	r_wrist = Vector((-0.296, -0.060, 0.318))
	r_fist = Vector((-0.296, -0.094, 0.310))
	pole_axis = Vector((-0.06, -0.06, 1.0)).normalized()
	l_shoulder = Vector((0.212, 0.0, 0.440))
	l_elbow = Vector((0.286, 0.006, 0.356))
	l_wrist = Vector((0.298, -0.050, 0.300))
	l_fist = Vector((0.294, -0.076, 0.286))

	def torso_profile(self):
		h, w, s, n = self.hem_z, self.waist_z, self.shoulder_z, self.neck_z
		return [
			(0.200, h), (0.208, h + 0.012), (0.212, h + 0.040), (0.214, h + 0.080),
			(0.220, w), (0.226, w + 0.060), (0.222, w + 0.120),
			(0.204, s - 0.012), (0.160, s + 0.022), (0.090, n), (0.0, n + 0.004),
		]


def paladin_legs(b, lod):
	"""Short thick pillar legs set wide, midnight with gold rings, on big
	porcelain boots."""
	bm = geo.new_bm()
	g = b.base_height
	for side in (-1.0, 1.0):
		leg = geo.lathe([(0.064, g + 0.100), (0.070, b.hem_z + 0.040)], seg(lod, 8, 5), row("plate_dark"))
		geo.translate(leg, (side * b.foot_x, 0.0, 0.0))
		geo.merge(bm, leg)
		ring = geo.lathe([(0.068, -0.012), (0.074, 0.0), (0.068, 0.012)], seg(lod, 8, 5), row("brass"), sharp=40)
		geo.translate(ring, (side * b.foot_x, 0.0, g + 0.128))
		geo.merge(bm, ring)
	geo.merge(bm, _big_boots(b, lod, 1.36))
	return bm


def paladin_torso(b, lod):
	"""The barrel body: midnight below, a great porcelain breastplate over
	the chest edged in gold."""
	prof = b.torso_profile()
	segs = seg(lod, 16, 10)
	if lod > 0:
		keep = (0, 1, 2, 4, 6, 8, 9, 10)
		prof = [prof[i] for i in keep]
	bm = geo.lathe(prof, segs, row("plate_dark"), sharp=SMOOTH, sy=b.torso_depth, cap_start=row("plate_dark"))
	w, s, n = b.waist_z, b.shoulder_z, b.neck_z
	zs = [w + 0.010, w + 0.022, w + 0.070, w + 0.120, s - 0.012, s + 0.022, n - 0.012]
	cprof = [(b.torso_radius(z) + (0.016 if i < 2 or i == len(zs) - 1 else 0.012), z) for i, z in enumerate(zs)]
	bands = [row("brass")] + [row("steel")] * (len(cprof) - 3) + [row("brass")]
	geo.merge(bm, geo.lathe(cprof, segs, sharp=50, sy=b.torso_depth, ring_swatches=bands))
	return bm


def star_hammer(b, lod, below=0.12, length=0.50):
	"""A huge gold star hammer stood upright: a midnight haft banded in
	gold, a great gold head across it, a violet star on each striking face,
	a violet band round its middle and a cyan crystal spike on top."""
	axis = Vector(b.pole_axis).normalized()
	fist = b.r_fist
	bm = geo.lathe([(0.022, -below), (0.024, length)], seg(lod, 6, 5), row("plate_dark"), sharp=40, phase=0.0,
			cap_start=row("brass"))
	for t in (-below + 0.02, 0.10, length - 0.06):
		geo.merge(bm, geo.lathe([(0.030, t - 0.016), (0.033, t), (0.030, t + 0.016)], seg(lod, 6, 5), row("brass"),
				sharp=40, phase=0.0))
	hz = length + 0.080
	head = geo.lathe([(0.084, -0.150), (0.094, -0.136), (0.094, -0.060), (0.080, -0.040), (0.080, 0.040),
			(0.094, 0.060), (0.094, 0.136), (0.084, 0.150)], seg(lod, 8, 6), sharp=40, phase=math.pi / 8.0,
			ring_swatches=[row("trim"), row("brass"), row("trim"), row("arcane"), row("trim"), row("brass"),
			row("trim")], cap_start=row("brass"), cap_end=row("brass"))
	geo.rotate(head, 90.0, 'Y')
	for side in (-1.0, 1.0):
		star = geo.plate(_star(0.086, 0.086, 0.030, 5), 0.024, row("arcane"), side=row("crystal"), sharp=FLAT)
		geo.transform(star, geo.orient(Vector((side * 0.156, 0.0, 0.0)), (side, 0.0, 0.0)))
		geo.merge(head, star)
	spike = geo.lathe([(0.0, 0.0), (0.040, 0.020), (0.0, 0.130)], seg(lod, 6, 4), row("crystal"), sharp=FLAT,
			phase=0.0)
	geo.translate(spike, (0.0, 0.0, 0.080))
	geo.merge(head, spike)
	geo.translate(head, (0.0, 0.0, hz))
	geo.merge(bm, head)
	geo.transform(bm, geo.frame(fist, axis, (0.0, -1.0, 0.0)))
	return bm


def star_circlet(b, lod):
	"""A small halo of gold and cyan five-pointed stars floating level in a
	ring over the crown."""
	bm = geo.new_bm()
	c = b.head_centre
	centre = Vector((c.x, c.y + 0.020, c.z + 0.300))
	count = seg(lod, 7, 5)
	for k in range(count):
		a = -math.pi / 2.0 + k * 2.0 * math.pi / count
		out = Vector((math.cos(a), math.sin(a), 0.0))
		r = 0.150 if k % 2 == 0 else 0.136
		sw = row("brass") if k % 2 == 0 else row("crystal")
		star = geo.plate(_star(0.050, 0.050, 0.021, 5), 0.016, sw, side=row("trim"), sharp=FLAT)
		geo.transform(star, geo.orient(centre + out * r, (out.x * 0.35, -1.0, 0.45), (0.0, 0.0, 1.0)))
		geo.merge(bm, star)
	return bm


def _sheet(grid, row_swatches, facing, sharp=SMOOTH):
	"""Quads over `grid` (rows of points, every row as long), the faces
	between rows i and i + 1 painted row_swatches[i], each turned to look
	along `facing(centre)`: cloth draped over a body."""
	import bmesh
	bm = geo.new_bm()
	sw, sh = geo._layers(bm)
	vs = [[bm.verts.new(p) for p in r] for r in grid]
	for i in range(len(vs) - 1):
		for j in range(len(vs[i]) - 1):
			f = bm.faces.new([vs[i][j], vs[i][j + 1], vs[i + 1][j + 1], vs[i + 1][j]])
			f.smooth = True
			f[sw] = row_swatches[i]
			f[sh] = int(sharp)
	bm.normal_update()
	wrong = [f for f in bm.faces if f.normal.dot(facing(f.calc_center_median())) < 0.0]
	if wrong:
		bmesh.ops.reverse_faces(bm, faces=wrong)
	bm.normal_update()
	return bm


def paladin_tabard(b, lod, half_width=0.140, out=0.030):
	"""The Paladin's broad tabard in the team's colour: hung from under the
	breastplate's rim to below the knees, falling in folds below the belt,
	lined, edged all round in a rolled gold border that gives it its
	thickness, a gold five-pointed star with a cyan heart on its skirt."""
	h, w, s = b.hem_z, b.waist_z, b.shoulder_z
	zs = [s - 0.050, w + 0.100, w + 0.050, w, h + 0.060, h + 0.010, h - 0.040, h - 0.096]
	cols = seg(lod, 11, 6)
	grid = []
	for z in zs:
		r = b.torso_radius(max(z, h + 0.010)) + out
		drop = max(0.0, w - z) / max(w - zs[-1], 1e-6)
		if z < h:
			r += (h - z) * 0.25
		line = []
		for j in range(cols):
			u = -1.0 + 2.0 * j / (cols - 1)
			x = u * half_width * (1.0 + 0.10 * drop)
			y = -b.torso_depth * math.sqrt(max(r * r - x * x, 1e-6))
			# Folds: the cloth hangs in soft pleats below the belt.
			y -= 0.012 * drop * math.cos(u * math.pi * 2.0)
			line.append(Vector((x, y, z)))
		grid.append(line)
	bands = [row("team_cloth")] * (len(zs) - 2) + [row("team_cloth_dark")]
	front = _sheet(grid, bands, lambda c: Vector((0.0, -1.0, 0.0)))
	bm = geo.new_bm()
	geo.merge(bm, front)
	geo.merge(bm, geo.flipped(front, row("team_cloth_dark"), inset=0.006))
	# The rolled gold border down both sides and along the hem.
	segs = seg(lod, 6, 4)
	for j in (0, cols - 1):
		pts = [grid[i][j] + Vector((0.0, 0.003, 0.0)) for i in range(len(zs))]
		geo.merge(bm, geo.tube(pts, [0.011] * len(pts), segs, row("brass"), sharp=40, cap_start=row("brass"),
				cap_end=row("brass")))
	hem = [p + Vector((0.0, 0.003, 0.0)) for p in grid[-1]]
	geo.merge(bm, geo.tube(hem, [0.012] * len(hem), segs, row("brass"), sharp=40, cap_start=row("brass"),
			cap_end=row("brass")))
	# A gold star on the skirt, a cyan heart in it.
	tree = geo.bvh(front)
	loc, nrm = geo.project(tree, (0.0, -1.0, h + 0.030), (0.0, 1.0, 0.0))
	if loc is not None:
		if nrm.y > 0.0:
			nrm = -nrm
		star = geo.plate(_star(0.060, 0.060, 0.026, 5), 0.014, row("brass"), side=row("trim"), sharp=FLAT)
		geo.merge(star, geo.disc(0.018, 0.018, seg(lod, 8, 5), row("crystal"), dome=0.008, depth=0.004),
				geo.frame((0.0, -0.007, 0.0), (0.0, -1.0, 0.0), (0.0, 0.0, 1.0)))
		geo.merge(bm, star, geo.orient(loc + nrm * 0.006, nrm))
	return bm


def star_lantern(b, lod, k=1.35):
	"""A gold star lantern hung from the left fist on a short bail: a hexagonal
	cage of cyan glass between a gold roof and foot, a gold star on the roof."""
	bm = geo.new_bm()
	segs = 6
	ph = math.pi / 6.0
	# Local: the bail's top at the origin, the lantern hanging below it.
	geo.merge(bm, geo.tube([Vector((0.0, 0.0, 0.010)), Vector((0.0, 0.0, -0.050))], [0.006, 0.006], 4, row("brass"),
			sharp=40))
	top = -0.050
	roof = geo.lathe([(0.062, top - 0.018), (0.056, top - 0.008), (0.024, top + 0.014), (0.0, top + 0.020)], segs,
			row("brass"), sharp=40, phase=ph, cap_start=row("trim"))
	geo.merge(bm, roof)
	glass = geo.lathe([(0.042, top - 0.130), (0.052, top - 0.100), (0.052, top - 0.040), (0.044, top - 0.016)], segs,
			row("crystal"), sharp=40, phase=ph)
	geo.merge(bm, glass)
	foot = geo.lathe([(0.050, top - 0.120), (0.060, top - 0.132), (0.048, top - 0.146), (0.0, top - 0.150)], segs,
			row("brass"), sharp=40, phase=ph, cap_start=row("brass"))
	geo.merge(bm, foot)
	drop = geo.lathe([(0.016, 0.0), (0.0, -0.030)], 5, row("brass"), sharp=40, phase=0.0, cap_start=row("brass"))
	geo.translate(drop, (0.0, 0.0, top - 0.148))
	geo.merge(bm, drop)
	if lod == 0:
		for i in range(segs):
			a = ph + i * 2.0 * math.pi / segs
			x, y = math.cos(a) * 0.056, math.sin(a) * 0.056
			geo.merge(bm, geo.tube([Vector((x, y, top - 0.122)), Vector((x, y, top - 0.014))], [0.006, 0.006], 4,
					row("brass"), sharp=40))
	star = geo.plate(_star(0.030, 0.030, 0.012, 5), 0.012, row("brass"), side=row("trim"), sharp=FLAT)
	geo.translate(star, (0.0, 0.0, top + 0.048))
	geo.merge(bm, star)
	geo.scale(bm, k, k, k)
	geo.translate(bm, b.l_fist + Vector((0.0, 0.0, -0.020)))
	return bm


# === the Star Rider =========================================================
# The rider sits on a comet fox: a silver-lavender fox-deer flecked with star
# specks, big level ears lined with cyan, a cyan crystal horn, a white ruff
# and cheeks, crystal hooves, a long comet tail ending in a cyan flame with
# a star floating over it, a porcelain peytral across its chest and the
# team's dagged saddle cloth over each flank. Its head is held high and well
# forward of the rider, so it reads from the front and from the game camera.
# Built in the rider's standing space, as horse.py is (the ground at
# b.base_height, facing -Y); horse.SEAT is still where the rider sits.

STEED_HEAD = Vector((0.0, -0.545, 0.800))
## The head is built at fox size and drawn this much bigger, so it reads.
STEED_HEAD_SCALE = 1.32
STEED_BARREL_Z = 0.382
_BARREL = [(0.0, -0.335), (0.075, -0.328), (0.118, -0.300), (0.136, -0.240), (0.140, -0.120), (0.136, 0.0),
		(0.132, 0.120), (0.126, 0.215), (0.102, 0.275), (0.052, 0.300), (0.0, 0.304)]


def _barrel_r(y):
	"""The steed's barrel's half-width at body position y."""
	lz = 0.015 - y
	for (r0, z0), (r1, z1) in zip(_BARREL, _BARREL[1:]):
		if z0 <= lz <= z1:
			return r0 + (r1 - r0) * (lz - z0) / max(z1 - z0, 1e-9)
	return 0.0


def _steed_head(b, lod, g):
	H = STEED_HEAD + Vector((0.0, 0.0, g))
	bm = geo.new_bm()
	skull = geo.ellipsoid(0.104, 0.100, 0.092, seg(lod, 12, 8), seg(lod, 6, 4), row("coat"), sharp=SMOOTH)
	geo.translate(skull, H)
	geo.merge(bm, skull)
	snout = geo.tube([H + Vector((0.0, -0.050, -0.030)), H + Vector((0.0, -0.140, -0.050)),
			H + Vector((0.0, -0.188, -0.058))], [0.052, 0.034, 0.020], seg(lod, 9, 6), row("coat"), sharp=SMOOTH,
			flatten=0.85, up=(0.0, 0.0, 1.0))
	geo.merge(bm, snout)
	chin = geo.ellipsoid(0.040, 0.075, 0.026, seg(lod, 8, 6), 4, row("mane"), sharp=SMOOTH)
	geo.translate(chin, H + Vector((0.0, -0.110, -0.074)))
	geo.merge(bm, chin)
	nose = geo.ellipsoid(0.022, 0.017, 0.016, seg(lod, 7, 5), 3, row("eye"), sharp=SMOOTH)
	geo.translate(nose, H + Vector((0.0, -0.198, -0.050)))
	geo.merge(bm, nose)
	for side in (-1.0, 1.0):
		cheek = geo.ellipsoid(0.040, 0.050, 0.034, seg(lod, 8, 5), 4, row("mane"), sharp=SMOOTH)
		geo.rotate(cheek, side * -25.0, 'Z')
		geo.translate(cheek, H + Vector((side * 0.084, -0.010, -0.044)))
		geo.merge(bm, cheek)
		ear = geo.lathe([(0.054, 0.0), (0.046, 0.055), (0.0, 0.150)], seg(lod, 7, 5), row("coat"), sharp=40,
				phase=0.0, sy=0.42)
		inner = geo.lathe([(0.036, 0.004), (0.028, 0.050), (0.0, 0.115)], 5, row("crystal"), sharp=40, phase=0.0,
				sy=0.30)
		geo.translate(inner, (0.0, -0.012, 0.006))
		geo.merge(ear, inner)
		geo.rotate(ear, side * 28.0, 'Y')
		geo.rotate(ear, -12.0, 'X')
		geo.translate(ear, H + Vector((side * 0.058, 0.014, 0.058)))
		geo.merge(bm, ear)
	# Big shared-style eyes on the front of the skull, looking out.
	tree = geo.bvh(skull)
	for side in (-1.0, 1.0):
		loc, nrm = geo.project(tree, (side * 0.052, H.y - 1.0, H.z + 0.020), (0.0, 1.0, 0.0))
		if loc is None:
			continue
		geo.merge(bm, geo.disc(0.024, 0.028, seg(lod, 9, 6), row("eye"), dome=0.006),
				geo.frame(loc + nrm * 0.002, nrm, (0.0, 0.0, 1.0)))
		if lod == 0:
			geo.merge(bm, geo.disc(0.008, 0.008, 5, row("glint"), dome=0.002, depth=0.002, simple=True),
					geo.frame(loc + nrm * 0.008 + Vector((side * 0.006, 0.0, 0.012)), nrm, (0.0, 0.0, 1.0)))
	# A cyan crystal horn on the brow over a gold star.
	horn = geo.lathe([(0.024, 0.0), (0.018, 0.050), (0.0, 0.130)], 5, row("crystal"), sharp=FLAT, phase=0.0,
			cap_start=row("crystal"))
	geo.rotate(horn, -28.0, 'X')
	geo.translate(horn, H + Vector((0.0, -0.040, 0.070)))
	geo.merge(bm, horn)
	loc, nrm = geo.project(tree, (0.0, H.y - 1.0, H.z + 0.052), (0.0, 1.0, 0.0))
	if loc is not None:
		geo.merge(bm, geo.plate(_star(0.032, 0.032, 0.013, 5), 0.012, row("brass"), side=row("trim"), sharp=FLAT),
				geo.orient(loc + nrm * 0.004, nrm))
	geo.transform(bm, Matrix.Translation(H) @ Matrix.Scale(STEED_HEAD_SCALE, 4) @ Matrix.Translation(-H))
	return bm


def steed(b, lod):
	"""The comet fox (see above)."""
	g = b.base_height
	bm = geo.new_bm()
	prof = _BARREL if lod == 0 else [_BARREL[i] for i in (0, 2, 3, 5, 7, 8, 10)]
	barrel = geo.lathe(prof, seg(lod, 12, 8), row("coat"), sharp=SMOOTH, sy=1.08)
	geo.rotate(barrel, 90.0, 'X')
	geo.translate(barrel, (0.0, 0.015, g + STEED_BARREL_Z))
	geo.merge(bm, barrel)
	# Slender deer legs: straight in front, the hind ones bent at the hock;
	# white fetlock tufts over glowing crystal hooves.
	segs = seg(lod, 7, 5)
	for side in (-1.0, 1.0):
		x = side * 0.074
		front = [Vector((x, -0.172, g + 0.340)), Vector((x * 1.02, -0.196, g + 0.180)), Vector((x * 1.04, -0.212, g + 0.050))]
		hind = [Vector((x, 0.200, g + 0.350)), Vector((x * 1.06, 0.272, g + 0.170)), Vector((x * 1.06, 0.236, g + 0.050))]
		for pts, radii in ((front, [0.056, 0.034, 0.028]), (hind, [0.074, 0.036, 0.028])):
			geo.merge(bm, geo.tube(pts, radii, segs, row("coat"), sharp=SMOOTH))
			foot = pts[-1]
			hoof = geo.lathe([(0.0, 0.0), (0.040, 0.0), (0.038, 0.024), (0.030, 0.044)], seg(lod, 7, 5),
					row("crystal"), sharp=40, phase=0.0, cap_start=row("crystal"))
			geo.translate(hoof, (foot.x, foot.y, g))
			geo.merge(bm, hoof)
			tuft = geo.ellipsoid(0.040, 0.042, 0.030, seg(lod, 7, 5), 3, row("mane"), sharp=SMOOTH)
			geo.translate(tuft, (foot.x, foot.y, g + 0.056))
			geo.merge(bm, tuft)
	# The neck, held high, and a white ruff down its throat.
	neck = geo.tube([Vector((0.0, -0.190, g + 0.450)), Vector((0.0, -0.320, g + 0.590)),
			Vector((0.0, -0.490, g + 0.745))], [0.092, 0.076, 0.074], seg(lod, 9, 7), row("coat"), sharp=SMOOTH,
			flatten=0.84, up=(0.0, 1.0, 0.3))
	geo.merge(bm, neck)
	ruff = geo.ellipsoid(0.092, 0.066, 0.130, seg(lod, 9, 6), 4, row("mane"), sharp=SMOOTH)
	geo.rotate(ruff, -38.0, 'X')
	geo.translate(ruff, (0.0, -0.400, g + 0.610))
	geo.merge(bm, ruff)
	# A pearl mane in soft locks down the crest of the neck.
	steps = seg(lod, 6, 4)
	for i in range(steps):
		t = i / (steps - 1)
		p = Vector((0.0, -0.470, g + 0.850)).lerp(Vector((0.0, -0.180, g + 0.560)), t)
		lock = geo.ellipsoid(0.028, 0.052, 0.040, 6, 3, row("mane"), sharp=SMOOTH)
		geo.rotate(lock, -40.0 + 15.0 * t, 'X')
		geo.translate(lock, p + Vector((0.012 * (1 if i % 2 else -1), 0.0, 0.0)))
		geo.merge(bm, lock)
	# The comet tail: up and over from the rump, white, ending in a cyan
	# flame with a star floating above it.
	tail = [Vector((0.0, 0.300, g + 0.450)), Vector((0.0, 0.392, g + 0.520)), Vector((0.0, 0.462, g + 0.632)),
			Vector((0.0, 0.474, g + 0.762)), Vector((0.0, 0.430, g + 0.868))]
	geo.merge(bm, geo.tube(tail, [0.032, 0.050, 0.070, 0.070, 0.0], seg(lod, 9, 6), sharp=SMOOTH,
			ring_swatches=[row("coat"), row("mane"), row("mane"), row("crystal")]))
	tip = geo.plate(_star(0.052, 0.040, 0.016), 0.016, row("crystal"), side=row("brass"), sharp=FLAT)
	geo.transform(tip, geo.orient(Vector((0.0, 0.410, g + 0.950)), (0.0, -1.0, 0.35)))
	geo.merge(bm, tip)
	# Star specks across the coat (near only).
	if lod == 0:
		tree = geo.bvh(barrel)
		for x, y, z, r in ((1.0, -0.120, 0.05, 0.010), (1.0, -0.020, -0.04, 0.008), (1.0, 0.090, 0.03, 0.011),
				(1.0, 0.200, -0.02, 0.008), (1.0, 0.250, 0.07, 0.007), (-1.0, -0.100, -0.03, 0.009),
				(-1.0, 0.010, 0.05, 0.011), (-1.0, 0.120, -0.05, 0.008), (-1.0, 0.230, 0.04, 0.010),
				(0.3, 0.260, 1.0, 0.009), (-0.3, 0.300, 1.0, 0.008)):
			loc, nrm = geo.project(tree, (x * 0.6, y, g + STEED_BARREL_Z + z + (0.6 if z == 1.0 else 0.0)),
					(-x, 0.0, -1.0 if z == 1.0 else 0.0))
			if loc is None:
				continue
			geo.merge(bm, geo.disc(r, r, 5, row("glint"), dome=0.002, depth=0.002, simple=True),
					geo.frame(loc + nrm * 0.001, nrm, (0.0, 0.0, 1.0)))
	geo.merge(bm, _steed_head(b, lod, g))
	return bm


def steed_barding(b, lod):
	"""A porcelain peytral across the steed's chest, edged in gold, a cyan
	star in its middle; a midnight saddle with a gold cantle."""
	g = b.base_height
	bm = geo.new_bm()
	outline = [(-0.150, 0.050), (-0.070, 0.074), (0.0, 0.040), (0.070, 0.074), (0.150, 0.050), (0.158, -0.040),
			(0.070, -0.084), (0.0, -0.124), (-0.070, -0.084), (-0.158, -0.040)]
	plate = geo.plate(outline, 0.020, row("steel"), side=row("brass"), sharp=40, bend=3.4)
	star = geo.plate(_star(0.046, 0.034, 0.013), 0.014, row("crystal"), side=row("brass"), sharp=FLAT)
	geo.translate(star, (0.0, -0.014, -0.018))
	geo.merge(plate, star)
	geo.rotate(plate, 8.0, 'X')
	geo.translate(plate, (0.0, -0.300, g + 0.402))
	geo.merge(bm, plate)
	import horse
	seat = geo.ellipsoid(0.105, 0.130, 0.040, seg(lod, 10, 7), 4, row("leather"), sharp=SMOOTH, squash_bottom=0.4)
	for v in seat.verts:
		v.co.z += 0.045 * (v.co.y / 0.13) ** 2 if v.co.z > 0.0 else 0.0
	geo.translate(seat, (0.0, 0.010, g + horse.SEAT - 0.028))
	geo.merge(bm, seat)
	cantle = geo.tube([Vector((-0.080, 0.120, g + horse.SEAT + 0.030)), Vector((0.0, 0.150, g + horse.SEAT + 0.060)),
			Vector((0.080, 0.120, g + horse.SEAT + 0.030))], [0.014] * 3, seg(lod, 6, 4), row("brass"), sharp=40,
			cap_start=row("brass"), cap_end=row("brass"))
	geo.merge(bm, cantle)
	return bm


def steed_cloth(b, lod):
	"""The team's saddle cloth over each flank, from under the saddle down
	past the belly, dagged at the foot in three points edged in gold, a
	gold star on each side."""
	g = b.base_height
	bm = geo.new_bm()
	cols = 7
	ys = [-0.160 + 0.370 * j / (cols - 1) for j in range(cols)]
	off = 0.012
	angles = [22.0, 45.0, 68.0, 90.0]
	for side in (-1.0, 1.0):
		grid = []
		for a in angles:
			t = math.radians(a)
			grid.append([Vector((side * (_barrel_r(y) + off) * math.sin(t), y,
					g + STEED_BARREL_Z + (_barrel_r(y) * 1.08 + off) * math.cos(t))) for y in ys])
		for z, flare in ((0.300, 0.012), ("border", 0.020), ("hem", 0.024)):
			line = []
			for j, y in enumerate(ys):
				dag = 1.0 - abs(((j / (cols - 1)) * 3.0) % 1.0 - 0.5) * 2.0
				hem_z = 0.250 - 0.060 * dag
				zz = z if isinstance(z, float) else (hem_z + 0.026 if z == "border" else hem_z)
				line.append(Vector((side * (_barrel_r(y) + off + flare), y, g + zz)))
			grid.append(line)
		bands = [row("team_cloth")] * (len(grid) - 3) + [row("team_cloth"), row("brass")]
		sheet = _sheet(grid, bands, lambda c, s=side: Vector((s, 0.0, 0.4)))
		geo.merge(bm, sheet)
		geo.merge(bm, geo.flipped(sheet, row("team_cloth_dark"), inset=0.005))
		tree = geo.bvh(sheet)
		loc, nrm = geo.project(tree, (side * 0.6, 0.030, g + 0.335), (-side, 0.0, 0.0))
		if loc is not None:
			star = geo.plate(_star(0.048, 0.048, 0.020, 5), 0.012, row("brass"), side=row("trim"), sharp=FLAT)
			geo.merge(bm, star, geo.orient(loc + nrm * 0.005, nrm))
	return bm


def steed_reins(b, lod):
	"""Gold reins from the steed's snout to the rider's left fist."""
	g = b.base_height
	H = STEED_HEAD + Vector((0.0, 0.0, g))
	bm = geo.new_bm()
	for side in (-1.0, 1.0):
		bit = H + Vector((side * 0.046, -0.120, -0.046)) * STEED_HEAD_SCALE
		mid = bit.lerp(b.l_fist, 0.5) + Vector((0.0, 0.0, -0.030))
		geo.merge(bm, geo.tube([bit, mid, b.l_fist], [0.006] * 3, 4, row("brass"), sharp=40))
	return bm


def rider_spear(b, lod, length=1.22, below=0.30):
	"""The crescent spear stood upright, a swallow-tailed team pennant under
	its moon, flying out to the rider's right."""
	import gear
	bm = crescent_spear(b, lod, length=length, below=below)
	top = length - below
	pennant = geo.plate([(-0.010, top - 0.110), (-0.280, top - 0.150), (-0.200, top - 0.215), (-0.280, top - 0.290),
			(-0.010, top - 0.310)], 0.012, row("team_cloth"), side=row("team_cloth_dark"), sharp=40)
	geo.merge(bm, gear._place(pennant, b, b.r_fist, b.pole_axis))
	return bm
