"""Pirates parts: a toy pirate playset come ashore.

The race reads apart by its cloth: cream shirts banded in charcoal stripes,
sun-browned faces under a bandana or a tricorn, eye patches and ginger
beards, brown breeches rolled at the shin, and big bright brass (buckles,
earrings, a cutlass's basket guard, the blunderbuss's bell). Everything
nautical is chunky: a harpoon, a boat anchor swung like a club, a musket
as long as the man.

The team's colour is on the cloth a pirate is known by: the bandana, a
wide sash knotted at the hip, a tricorn's plume, the Captain's long coat,
the Crab's saddle cloth. Head pieces are built upright and tipped back by
the recipe, as every race's are.
"""
import math

from mathutils import Matrix, Vector

import geo
from geo import FLAT, HARD, SMOOTH
from palette import row
import parts
from parts import seg, _limb
import gear


def _recolour(bm, src, dst):
	sw = bm.faces.layers.int.get(geo.SWATCH)
	for f in bm.faces:
		if f[sw] == row(src):
			f[sw] = row(dst)
	return bm


def _over_head(b, bm):
	geo.translate(bm, (b.head_centre.x, b.head_centre.y + 0.004, 0.0))
	return bm


# --- heads ------------------------------------------------------------------

def bandana(b, lod, cloth="team_cloth", dark="team_cloth_dark"):
	"""A cloth knotted tight over the crown, a band low across the brow, the
	knot and two short tails at the back of the head."""
	z = b.brow_z
	bm = geo.lathe([(0.170, z - 0.034), (0.178, z - 0.004), (0.168, z + 0.044), (0.130, z + 0.090), (0.0, z + 0.110)],
			seg(lod, 12, 9), row(cloth), sharp=SMOOTH, sy=0.95, cap_start=row("lining"))
	band = geo.lathe([(0.172, z - 0.040), (0.184, z - 0.032), (0.184, z - 0.006), (0.172, z + 0.002)],
			seg(lod, 12, 9), row(dark), sharp=50, sy=0.95)
	geo.merge(bm, band)
	knot = geo.ellipsoid(0.040, 0.034, 0.036, seg(lod, 8, 6), 4, row(cloth), sharp=SMOOTH)
	geo.translate(knot, (0.0, 0.176, z - 0.012))
	geo.merge(bm, knot)
	for side in (-1.0, 1.0):
		pts = [Vector((side * 0.010, 0.190, z - 0.020)), Vector((side * 0.040, 0.214, z - 0.070)),
				Vector((side * 0.056, 0.222, z - 0.128))]
		geo.merge(bm, geo.tube(pts, [0.026, 0.028, 0.0], seg(lod, 6, 4), sharp=SMOOTH, flatten=0.32,
				up=(0.0, 1.0, 0.0), ring_swatches=[row(cloth), row(dark)]))
	return _over_head(b, bm)


def tricorn(b, lod, felt="plate_dark", trim="brass", plume=True):
	"""A big three-cornered hat: a round crown, its wide brim cocked up into
	three corners (one over the brow), edged in gold braid, a team plume."""
	z = b.brow_z - 0.004
	sy = 0.96
	bm = geo.lathe([(0.168, z - 0.002), (0.172, z + 0.050), (0.150, z + 0.104), (0.096, z + 0.130), (0.0, z + 0.136)],
			seg(lod, 14, 10), row(felt), sharp=SMOOTH, sy=sy, cap_start=row("lining"))

	def cock(theta, r, zz):
		# Three corners: one dead ahead (-Y), two behind at the sides.
		corner = 0.5 + 0.5 * math.cos(3.0 * (theta + math.pi / 2.0))
		out = max(0.0, (r - 0.165) / 0.13)
		rr = r + 0.040 * corner * out
		return (rr * math.cos(theta), rr * math.sin(theta) * sy, zz + out * (0.025 + 0.120 * (1.0 - corner) ** 0.6))

	brim = geo.lathe([(0.160, z - 0.004), (0.300, z - 0.020), (0.304, z + 0.000), (0.160, z + 0.016)],
			seg(lod, 30, 18), sharp=40, warp=cock, ring_swatches=[row(felt), row(trim), row(felt)])
	geo.merge(bm, brim)
	band = geo.lathe([(0.170, z + 0.010), (0.176, z + 0.018), (0.176, z + 0.040), (0.168, z + 0.046)],
			seg(lod, 14, 10), row("team_cloth"), sharp=40, sy=sy)
	geo.merge(bm, band)
	if plume:
		steps = seg(lod, 7, 4)
		pts, radii = [], []
		for i in range(steps):
			t = i / (steps - 1)
			pts.append(Vector((0.120 + 0.050 * t, 0.040 + 0.170 * t * t, z + 0.060 + 0.120 * math.sin(t * 1.5))))
			radii.append(0.010 + 0.040 * math.sin(math.pi * min(1.0, t * 1.05)))
		radii[-1] = 0.0
		geo.merge(bm, geo.tube(pts, radii, seg(lod, 6, 4), row("team_cloth"), sharp=SMOOTH, flatten=0.40,
				up=(1.0, 0.0, 0.3)))
	if lod == 0:
		badge = geo.ellipsoid(0.020, 0.008, 0.020, 6, 3, row("bone"), sharp=40)
		geo.translate(badge, (0.0, -0.176 * sy, z + 0.070))
		geo.merge(bm, badge)
	return _over_head(b, bm)


def watch_cap(b, lod):
	"""A knitted sailor's cap in the team's colour: a deep rolled brim and a
	soft crown slumped back, a bobble on top."""
	z = b.brow_z + 0.010
	bm = geo.lathe([(0.176, z - 0.022), (0.180, z + 0.030), (0.164, z + 0.084), (0.120, z + 0.124), (0.0, z + 0.136)],
			seg(lod, 12, 9), row("team_cloth"), sharp=SMOOTH, sy=0.95, cap_start=row("lining"))
	roll = geo.lathe([(0.176, z - 0.046), (0.192, z - 0.038), (0.194, z + 0.004), (0.178, z + 0.012)],
			seg(lod, 12, 9), row("team_cloth_dark"), sharp=SMOOTH, sy=0.95)
	geo.merge(bm, roll)
	bobble = geo.ellipsoid(0.040, 0.040, 0.038, seg(lod, 8, 6), 4, row("cloth"), sharp=SMOOTH)
	geo.translate(bobble, (0.0, 0.030, z + 0.160))
	geo.merge(bm, bobble)
	return _over_head(b, bm)


def bald_cap(b, lod):
	"""The crown of a bald head, closing the top parts.head leaves open for
	headgear, a little shine on its dome."""
	z = b.brow_z
	cap = geo.lathe([(0.168, z - 0.050), (0.171, z - 0.005), (0.158, z + 0.040), (0.118, z + 0.078), (0.0, z + 0.096)],
			seg(lod, 12, 9), row("skin"), sharp=SMOOTH, sy=0.94)
	return _over_head(b, cap)


def eye_patch(b, lod, head_bm, side=1.0):
	"""A black patch over one eye on a strap slanting up round the head."""
	tree = geo.bvh(head_bm)
	bm = geo.new_bm()
	eye_z = b.head_centre.z - 0.014
	loc, nrm = geo.project(tree, (side * 0.066, -1.0, eye_z), (0.0, 1.0, 0.0))
	if loc is not None:
		geo.merge(bm, geo.disc(0.036, 0.040, seg(lod, 10, 7), row("boot"), dome=0.008, depth=0.002),
				geo.frame(loc + nrm * 0.006, nrm, (0.0, 0.0, 1.0)))
	pts, nrms = [], []
	steps = seg(lod, 9, 5)
	for i in range(steps):
		a = -math.pi / 2.0 + side * (-0.9 + 1.8 * i / (steps - 1))
		zz = eye_z + 0.010 + 0.050 * (i / (steps - 1)) if side > 0 else eye_z + 0.060 - 0.050 * (i / (steps - 1))
		p, n = geo.project(tree, (math.cos(a) * 0.5, math.sin(a) * 0.5, zz), (-math.cos(a), -math.sin(a), 0.0))
		if p is not None:
			pts.append(p)
			nrms.append(n)
	if len(pts) > 1:
		geo.merge(bm, geo.ribbon(pts, nrms, 0.012, 0.004, row("boot"), sharp=40, embed=0.002))
	return bm


def earring(b, lod, side=-1.0):
	"""A big gold hoop at one ear."""
	c = b.head_centre
	ring = geo.lathe([(0.020, -0.004), (0.026, 0.0), (0.020, 0.004)], seg(lod, 10, 6), row("brass"), sharp=SMOOTH,
			phase=0.0)
	geo.rotate(ring, 90.0, 'Y')
	geo.translate(ring, (side * 0.172, c.y + 0.010, c.z - 0.060))
	return ring


def stubble_beard(b, lod, row_name="beard"):
	"""A short pointed beard on the chin and a curled moustache."""
	c = b.head_centre
	bm = geo.ellipsoid(0.086, 0.050, 0.060, seg(lod, 10, 7), seg(lod, 5, 4), row(row_name), sharp=SMOOTH)
	for v in bm.verts:
		low = max(0.0, -v.co.z / 0.06)
		v.co.x *= 1.0 - 0.55 * low
		v.co.z -= 0.025 * low * low
	geo.translate(bm, (c.x, c.y - 0.118, c.z - 0.108))
	for side in (-1.0, 1.0):
		pts = [Vector((side * 0.008, c.y - 0.150, c.z - 0.058)), Vector((side * 0.040, c.y - 0.146, c.z - 0.064)),
				Vector((side * 0.066, c.y - 0.134, c.z - 0.044))]
		geo.merge(bm, geo.tube(pts, [0.014, 0.012, 0.0], seg(lod, 6, 4), row(row_name), sharp=SMOOTH))
	return bm


# --- body -------------------------------------------------------------------

def striped_shirt(b, lod, base="cloth", stripe="plate_dark"):
	"""A loose cream shirt with three bold charcoal stripes standing proud
	of it, one below the sash and two across the chest."""
	h, w, s, n = b.hem_z, b.waist_z, b.shoulder_z, b.neck_z
	prof = b.torso_profile()
	full = [(prof[0][0] + 0.004, h - 0.010)] + [(r + 0.004, z) for r, z in prof]
	bm = geo.lathe(full, seg(lod, 12, 8), row(base), sharp=SMOOTH, sy=b.torso_depth, cap_start=row("cloth_dark"))
	half = 0.022
	for zc in (h + 0.048, w + 0.068, w + 0.132):
		z0, z1 = zc - half, zc + half
		r0, r1 = b.torso_radius(z0) + 0.004, b.torso_radius(z1) + 0.004
		band = geo.lathe([(r0 - 0.002, z0), (r0 + 0.009, z0 + 0.006), (r1 + 0.009, z1 - 0.006), (r1 - 0.002, z1)],
				seg(lod, 12, 8), row(stripe), sharp=50, sy=b.torso_depth)
		geo.merge(bm, band)
	return bm


def sash(b, lod, cloth="team_cloth", dark="team_cloth_dark"):
	"""A wide sash wound round the waist, knotted at the left hip, its two
	tails hanging down the thigh."""
	w = b.waist_z
	r = b.torso_radius(w)
	bm = geo.lathe([(r - 0.002, w - 0.040), (r + 0.016, w - 0.032), (r + 0.020, w), (r + 0.016, w + 0.032),
			(r - 0.002, w + 0.040)], seg(lod, 14, 9), row(cloth), sharp=SMOOTH, sy=b.torso_depth)
	hip = Vector((r * 0.80, -r * b.torso_depth * 0.50, w))
	knot = geo.ellipsoid(0.036, 0.030, 0.034, seg(lod, 8, 6), 4, row(cloth), sharp=SMOOTH)
	geo.translate(knot, hip + Vector((0.012, -0.012, 0.0)))
	geo.merge(bm, knot)
	for k, dx in enumerate((-0.012, 0.020)):
		pts = [hip + Vector((dx, -0.016, -0.010)), hip + Vector((dx + 0.012, -0.024, -0.080)),
				hip + Vector((dx + 0.018, -0.020, -0.150 - 0.020 * k))]
		geo.merge(bm, geo.tube(pts, [0.026, 0.028, 0.0], seg(lod, 6, 4), sharp=SMOOTH, flatten=0.30,
				up=(0.0, -1.0, 0.0), ring_swatches=[row(cloth), row(dark)]))
	return bm


def breeches(b, lod, cloth="cloth_dark"):
	"""Baggy breeches rolled at the shin over bare shins, and chunky black
	boots or bare feet."""
	bm = geo.new_bm()
	g = b.base_height
	for side in (-1.0, 1.0):
		leg = geo.lathe([(0.044, g + 0.070), (0.056, g + 0.090), (0.058, b.hem_z - 0.010), (0.050, b.hem_z + 0.060)],
				seg(lod, 8, 5), row(cloth), sharp=SMOOTH)
		geo.translate(leg, (side * b.foot_x, 0.0, 0.0))
		geo.merge(bm, leg)
		cuff = geo.lathe([(0.050, g + 0.066), (0.060, g + 0.072), (0.060, g + 0.090), (0.052, g + 0.096)],
				seg(lod, 8, 5), row(cloth), sharp=50)
		geo.translate(cuff, (side * b.foot_x, 0.0, 0.0))
		geo.merge(bm, cuff)
	return bm


def boots(b, lod):
	boots = parts.boots(b, lod)
	_recolour(boots, "leather", "boot")
	return boots


def peg_leg(b, lod, side=1.0):
	"""The left leg ends in a turned wooden peg with an iron ferrule (the
	boot on that side is left off by the recipe)."""
	g = b.base_height
	bm = geo.lathe([(0.0, g), (0.020, g + 0.002), (0.022, g + 0.020), (0.026, g + 0.040), (0.034, g + 0.090),
			(0.040, g + 0.096), (0.046, g + 0.110)], seg(lod, 8, 6), sharp=40,
			ring_swatches=[row("steel"), row("steel"), row("wood"), row("wood"), row("wood_light"), row("wood_light")])
	geo.translate(bm, (side * b.foot_x, 0.0, 0.0))
	return bm


def shirt_arms(b, lod, sleeve="cloth", hand="skin", rolled=True):
	"""Loose shirt sleeves rolled to the elbow over bare brown forearms."""
	bm = geo.new_bm()
	segs = seg(lod, 7, 5)
	for shoulder, elbow, wrist, fist in ((b.r_shoulder, b.r_elbow, b.r_wrist, b.r_fist),
			(b.l_shoulder, b.l_elbow, b.l_wrist, b.l_fist)):
		upper = (elbow - shoulder).length
		geo.merge(bm, _limb(shoulder, elbow, [(0.050, -0.01), (0.057, 0.008), (0.054, upper - 0.004),
				(0.060, upper + 0.006), (0.0, upper + 0.020)], segs, row(sleeve)))
		# A round cap over the shoulder joint, bridging the sleeve to the body.
		side = 1.0 if shoulder.x > 0.0 else -1.0
		cap = geo.ellipsoid(0.066, 0.064, 0.060, seg(lod, 9, 6), seg(lod, 5, 4), row(sleeve), sharp=SMOOTH)
		geo.translate(cap, shoulder + Vector((-side * 0.018, 0.0, 0.004)))
		geo.merge(bm, cap)
		if sleeve == "cloth" and lod == 0:
			mid = shoulder.lerp(elbow, 0.55)
			geo.merge(bm, _limb(mid, elbow, [(0.058, -0.014), (0.062, -0.006), (0.062, 0.010), (0.058, 0.018)],
					segs, row("plate_dark"), sharp=50))
		lower = (wrist - elbow).length
		fore = "skin" if rolled else sleeve
		geo.merge(bm, _limb(elbow, wrist, [(0.040, -0.010), (0.042, 0.004), (0.038, lower), (0.0, lower + 0.008)],
				segs, row(fore)))
		fist_bm = geo.box(1.0, 1.0, 1.0, row(hand), SMOOTH)
		if lod == 0:
			fist_bm = geo.subdivided(fist_bm, 1)
		geo.fit(fist_bm, (0.062, 0.066, 0.068))
		geo.paint(fist_bm, row(hand), SMOOTH)
		geo.merge(bm, fist_bm, geo.frame(fist, wrist - elbow, (0.0, 0.0, 1.0)))
	return bm


def open_collar(b, lod):
	"""The shirt's open neck: a soft cream collar turned down over a
	brown V of chest."""
	n = b.neck_z
	bm = geo.lathe([(0.120, n - 0.030), (0.124, n - 0.010), (0.100, n + 0.010), (0.088, n + 0.020)], seg(lod, 10, 7),
			row("cloth"), sharp=SMOOTH, sy=0.9)
	if lod == 0:
		v = geo.plate([(-0.030, 0.0), (0.030, 0.0), (0.0, -0.060)], 0.006, row("skin"), sharp=SMOOTH)
		geo.transform(v, geo.orient(Vector((0.0, -0.100, n - 0.012)), (0.0, -1.0, 0.25)))
		geo.merge(bm, v)
	return bm


def buckle_belt(b, lod):
	"""A broad black belt with a big square brass buckle."""
	w = b.waist_z - 0.044
	r = b.torso_radius(w) + 0.006
	bm = geo.lathe([(r - 0.004, w - 0.020), (r + 0.010, w - 0.016), (r + 0.010, w + 0.016), (r - 0.004, w + 0.020)],
			seg(lod, 12, 8), row("boot"), sharp=40, sy=b.torso_depth)
	front = -(r + 0.010) * b.torso_depth
	buckle = geo.box(0.066, 0.014, 0.054, row("brass"), HARD, bevel=0.004 if lod == 0 else 0.0)
	geo.translate(buckle, (0.0, front - 0.004, w))
	geo.merge(bm, buckle)
	if lod == 0:
		inner = geo.box(0.036, 0.008, 0.026, row("boot"), HARD)
		geo.translate(inner, (0.0, front - 0.011, w))
		geo.merge(bm, inner)
	return bm


# --- weapons ----------------------------------------------------------------

CUTLASS_SCALE = 1.45


def cutlass(b, lod, fist=None, axis=None):
	"""A broad curved cutlass: the blade swelling toward its clipped point,
	a brass basket guard cupping the fist, a dark grip."""
	fist = b.r_fist if fist is None else fist
	axis = b.sword_axis if axis is None else axis
	bm = geo.new_bm()
	length = 0.320
	steps = seg(lod, 8, 5)
	back, edge = [], []
	for i in range(steps):
		t = i / (steps - 1)
		z = 0.040 + length * t
		curve = 0.050 * t * t
		w = 0.036 + 0.030 * math.sin(math.pi * min(t * 1.25, 1.0)) * (1.0 if t < 0.9 else 0.5)
		back.append((-0.012 - curve, z))
		edge.append((w - curve, z - 0.020 * t * t))
	tip = (0.020 - 0.050, 0.040 + length + 0.010)
	outline = back + [tip] + list(reversed(edge))
	geo.merge(bm, geo.plate(outline, 0.010, row("blade"), side=row("steel"), sharp=FLAT))
	guard = geo.ellipsoid(0.058, 0.040, 0.040, seg(lod, 10, 6), seg(lod, 5, 3), row("brass"), sharp=40)
	geo.delete_faces(guard, lambda f: f.calc_center_median().z > 0.004)
	geo.translate(guard, (0.012, 0.0, 0.038))
	geo.merge(bm, guard)
	geo.merge(bm, geo.flipped(guard, row("brass"), inset=0.004))
	bar = geo.box(0.100, 0.020, 0.018, row("brass"), 40, bevel=0.004 if lod == 0 else 0.0)
	geo.translate(bar, (0.004, 0.0, 0.040))
	geo.merge(bm, bar)
	grip = geo.lathe([(0.012, -0.050), (0.014, -0.012), (0.012, 0.036)], seg(lod, 6, 4), row("leather_dark"), sharp=40,
			phase=0.0)
	geo.merge(bm, grip)
	pommel = geo.ellipsoid(0.018, 0.018, 0.016, 6, 3, row("brass"), sharp=40)
	geo.translate(pommel, (0.0, 0.0, -0.060))
	geo.merge(bm, pommel)
	geo.transform(bm, geo.frame(fist, axis, parts.edge_down(axis)))
	return gear.grow(bm, fist, CUTLASS_SCALE)


def buckler(b, lod):
	"""A small round wooden buckler on the left forearm, banded in iron,
	its face painted in the team's colour round a brass boss."""
	shield = parts.round_shield(b, lod)
	_recolour(shield, "cream", "bone")
	return gear.grow(shield, (b.l_elbow + b.l_wrist) * 0.5, 0.85)


def harpoon(b, lod, length=1.40, below=0.32):
	"""A whaling harpoon stood upright: a long ash shaft bound with rope, a
	broad barbed iron head, a coil of rope on the shaft."""
	r = 0.016
	top = length - below
	bm = gear._pole(length - 0.10, r, seg(lod, 6, 5), row("wood"), below)
	head = geo.plate([(0.0, top - 0.12), (0.016, top - 0.10), (0.016, top - 0.04), (0.070, top - 0.10),
			(0.036, top + 0.000), (0.020, top + 0.050), (0.0, top + 0.150), (-0.020, top + 0.050),
			(-0.036, top + 0.000), (-0.070, top - 0.10), (-0.016, top - 0.04), (-0.016, top - 0.10)],
			0.014, row("steel"), side=row("blade"), sharp=FLAT)
	geo.merge(bm, head)
	socket = geo.lathe([(r * 1.1, top - 0.20), (r * 1.6, top - 0.17), (r * 1.4, top - 0.10)], seg(lod, 6, 5),
			row("steel"), sharp=40, phase=0.0)
	geo.merge(bm, socket)
	if lod == 0:
		for k in range(3):
			z = top - 0.40 - k * 0.030
			coil = geo.lathe([(0.026, z - 0.012), (0.040, z), (0.026, z + 0.012)], 8, row("string"), sharp=SMOOTH,
					phase=0.0)
			geo.merge(bm, coil)
	return gear._place(bm, b, b.r_fist, b.pole_axis)


def anchor(b, lod):
	"""A boat anchor swung two-handed like a club: a thick iron shank, a
	ring at its head, curved arms with spade flukes, a rope tied on."""
	bm = geo.new_bm()
	shank = 0.46
	geo.merge(bm, geo.lathe([(0.026, -0.060), (0.030, 0.0), (0.026, shank)], seg(lod, 8, 6), row("plate_dark"),
			sharp=40, phase=0.0, cap_start=row("plate_dark"), cap_end=row("plate_dark")))
	ring = geo.lathe([(0.040, -0.010), (0.054, 0.0), (0.040, 0.010)], seg(lod, 10, 6), row("plate_dark"), sharp=SMOOTH,
			phase=0.0)
	geo.rotate(ring, 90.0, 'Y')
	geo.translate(ring, (0.0, 0.0, -0.100))
	geo.merge(bm, ring)
	stock = geo.box(0.200, 0.030, 0.030, row("wood"), 40, bevel=0.008 if lod == 0 else 0.0)
	geo.translate(stock, (0.0, 0.0, 0.010))
	geo.merge(bm, stock)
	steps = seg(lod, 7, 5)
	arm_r = 0.150
	for side in (-1.0, 1.0):
		# From the crown out and back toward the fist, a quarter circle.
		pts = []
		for i in range(steps):
			ang = math.pi * 0.5 * i / (steps - 1)
			pts.append(Vector((side * arm_r * math.sin(ang), 0.0, shank - arm_r * (1.0 - math.cos(ang)))))
		geo.merge(bm, geo.tube(pts, [0.026] * (steps - 1) + [0.020], seg(lod, 6, 4), row("plate_dark"), sharp=40))
		fluke = geo.plate([(-0.044, 0.0), (0.044, 0.0), (0.0, 0.090)], 0.020, row("plate_dark"), side=row("steel"),
				sharp=40)
		geo.rotate(fluke, 180.0, 'Y')
		geo.rotate(fluke, side * -30.0, 'Y')
		geo.translate(fluke, pts[-1] + Vector((side * 0.010, 0.0, 0.030)))
		geo.merge(bm, fluke)
	crown = geo.ellipsoid(0.040, 0.034, 0.034, seg(lod, 8, 6), 4, row("plate_dark"), sharp=40)
	geo.translate(crown, (0.0, 0.0, shank))
	geo.merge(bm, crown)
	if lod == 0:
		rope = geo.tube([Vector((0.0, 0.0, -0.150)), Vector((0.030, 0.0, -0.110)), Vector((0.020, 0.0, -0.040)),
				Vector((0.030, 0.0, 0.040))], [0.009] * 4, 5, row("string"), sharp=SMOOTH)
		geo.merge(bm, rope)
	axis = b.sword_axis
	# Its arms spread across the body, so the camera sees the anchor's shape.
	geo.transform(bm, geo.frame(b.r_fist, axis, (0.0, -1.0, 0.0)))
	return gear.grow(bm, b.r_fist, 1.35)


def musket(b, lod, length=0.62, bell=False):
	"""A long musket levelled at the waist (the crossbow pose): a dark stock,
	an iron barrel with brass bands, a flintlock. bell: the blunderbuss, short
	and with a flared brass bell at the muzzle."""
	rear, front = b.stock_rear, b.stock_front
	forward = (front - rear).normalized()
	bm = geo.new_bm()
	stock = geo.box(0.036, 0.20, 0.050, row("wood"), 40, bevel=0.008 if lod == 0 else 0.0)
	geo.translate(stock, (0.0, 0.08, -0.010))
	geo.merge(bm, stock)
	butt = geo.box(0.040, 0.10, 0.074, row("wood"), 40, bevel=0.010 if lod == 0 else 0.0)
	geo.translate(butt, (0.0, 0.200, -0.024))
	geo.merge(bm, butt)
	fore = geo.box(0.030, length * 0.55, 0.030, row("wood"), 40, bevel=0.006 if lod == 0 else 0.0)
	geo.translate(fore, (0.0, -length * 0.25, 0.000))
	geo.merge(bm, fore)
	barrel_r = 0.014 if not bell else 0.020
	barrel = geo.tube([Vector((0.0, 0.030, 0.020)), Vector((0.0, -length, 0.020))], [barrel_r, barrel_r],
			seg(lod, 8, 6), row("steel" if not bell else "brass"), sharp=SMOOTH, cap_start=row("steel"))
	geo.merge(bm, barrel)
	if bell:
		mouth = geo.lathe([(barrel_r, 0.0), (0.030, 0.050), (0.052, 0.090), (0.046, 0.096)], seg(lod, 10, 7),
				row("brass"), sharp=SMOOTH, phase=0.0, cap_end=row("boot"))
		geo.transform(mouth, geo.frame(Vector((0.0, -length, 0.020)), (0.0, -1.0, 0.0), (0.0, 0.0, 1.0)))
		geo.merge(bm, mouth)
	for t in (0.30, 0.70):
		band = geo.lathe([(0.022, -0.008), (0.024, 0.0), (0.022, 0.008)], seg(lod, 8, 6), row("brass"), sharp=40,
				phase=0.0)
		geo.transform(band, geo.frame(Vector((0.0, -length * t, 0.012)), (0.0, -1.0, 0.0), (0.0, 0.0, 1.0)))
		geo.merge(bm, band)
	if lod == 0:
		lock = geo.box(0.012, 0.050, 0.030, row("steel"), 40)
		geo.translate(lock, (-0.022, 0.020, 0.012))
		geo.merge(bm, lock)
		hammer = geo.box(0.010, 0.012, 0.030, row("steel"), 40)
		geo.rotate(hammer, -30.0, 'X')
		geo.translate(hammer, (-0.022, 0.040, 0.036))
		geo.merge(bm, hammer)
	mid = rear + forward * 0.04
	geo.transform(bm, geo.orient(mid, forward))
	pivot = rear + forward * (b.r_fist - rear).dot(forward)
	return gear.grow(bm, pivot, 1.25)


def powder_horn(b, lod):
	"""A cream powder horn slung at the right hip on a strap."""
	pts = [Vector((-0.100, 0.060, b.waist_z - 0.010)), Vector((-0.140, 0.030, b.waist_z - 0.060)),
			Vector((-0.150, -0.010, b.waist_z - 0.120))]
	bm = geo.tube(pts, [0.030, 0.026, 0.008], seg(lod, 7, 5), row("bone"), sharp=SMOOTH, cap_start=row("brass"))
	return bm


def hook(b, lod, wrist, elbow):
	"""A steel hook where the left hand would be, on a brass cuff."""
	axis = (wrist - elbow).normalized()
	bm = geo.lathe([(0.044, -0.010), (0.046, 0.020), (0.036, 0.040), (0.0, 0.046)], seg(lod, 8, 6), row("brass"),
			sharp=40, phase=0.0)
	steps = seg(lod, 8, 5)
	pts = [Vector((0.0, 0.0, 0.040))]
	for i in range(steps):
		ang = math.pi * 1.2 * i / (steps - 1)
		pts.append(Vector((0.036 - 0.036 * math.cos(ang), 0.0, 0.090 + 0.036 * math.sin(ang))))
	geo.merge(bm, geo.tube(pts, [0.010] * (len(pts) - 1) + [0.004], seg(lod, 6, 4), row("steel"), sharp=SMOOTH))
	geo.transform(bm, geo.frame(wrist, axis, (0.0, 0.0, 1.0)))
	return bm


def parrot(b, lod, at):
	"""A plump orange-and-gold parrot perched on the right shoulder, a big
	hooked beak and the shared eyes, its long tail hanging down the back."""
	bm = geo.new_bm()
	body = geo.ellipsoid(0.050, 0.046, 0.068, seg(lod, 9, 6), seg(lod, 5, 4), row("fur_red"), sharp=SMOOTH)
	geo.rotate(body, 12.0, 'X')
	geo.merge(bm, body)
	head = geo.ellipsoid(0.040, 0.040, 0.040, seg(lod, 9, 6), seg(lod, 5, 4), row("fur_red"), sharp=SMOOTH)
	geo.translate(head, (0.0, -0.016, 0.080))
	geo.merge(bm, head)
	beak = geo.tube([Vector((0.0, -0.046, 0.090)), Vector((0.0, -0.070, 0.082)), Vector((0.0, -0.074, 0.060))],
			[0.018, 0.012, 0.0], seg(lod, 6, 4), row("fruit_green"), sharp=SMOOTH)
	geo.merge(bm, beak)
	for side in (-1.0, 1.0):
		eye = geo.disc(0.010, 0.012, 6, row("eye"), dome=0.003)
		geo.transform(eye, geo.frame(Vector((side * 0.034, -0.030, 0.092)), Vector((side, -0.5, 0.2)), (0.0, 0.0, 1.0)))
		geo.merge(bm, eye)
		wing = geo.ellipsoid(0.014, 0.036, 0.052, 6, 4, row("fruit_green"), sharp=SMOOTH)
		geo.rotate(wing, -18.0, 'X')
		geo.translate(wing, (side * 0.046, 0.010, 0.000))
		geo.merge(bm, wing)
	tail = geo.tube([Vector((0.0, 0.030, -0.040)), Vector((0.0, 0.060, -0.110)), Vector((0.0, 0.070, -0.180))],
			[0.024, 0.020, 0.0], seg(lod, 6, 4), sharp=SMOOTH, flatten=0.35, up=(0.0, 1.0, 0.0),
			ring_swatches=[row("fur_red"), row("fruit_green")])
	geo.merge(bm, tail)
	geo.translate(bm, at)
	return bm


def coat(b, lod, cloth="team_cloth", lining="team_cloth_dark", trim="brass"):
	"""The Captain's long frock coat in the team's colour, from the shoulders
	to below the knee, open down the front over the shirt, deep gold cuffs of
	braid at its hem and buttons down both edges."""
	g, h, w, s, n = b.base_height, b.hem_z, b.waist_z, b.shoulder_z, b.neck_z
	prof = [(0.206, g + 0.070), (0.200, g + 0.090), (0.186, h), (0.164, w - 0.030), (0.160, w + 0.040),
			(0.166, w + 0.110), (0.160, s - 0.012), (0.132, s + 0.022), (0.092, n)]
	bands = [row(trim)] + [row(cloth)] * (len(prof) - 2)
	shell = geo.lathe(prof, seg(lod, 18, 12), sharp=SMOOTH, sy=b.torso_depth + 0.04, ring_swatches=bands)

	def opening(f):
		m = f.calc_center_median()
		return m.y < 0.0 and abs(m.x) < 0.050 + 0.040 * max(0.0, (w + 0.08 - m.z) / 0.3) and m.z < s - 0.020

	geo.delete_faces(shell, opening)
	bm = geo.new_bm()
	geo.merge(bm, shell)
	geo.merge(bm, geo.flipped(shell, row(lining), inset=0.005))
	if lod == 0:
		for side in (-1.0, 1.0):
			for k in range(4):
				z = w + 0.120 - k * 0.060
				x = side * (0.058 + 0.008 * k)
				r = b.torso_radius(z) if z > h else 0.18
				btn = geo.ellipsoid(0.010, 0.006, 0.010, 6, 3, row(trim), sharp=40)
				geo.translate(btn, (x, -(r + 0.012) * (b.torso_depth + 0.04), z))
				geo.merge(bm, btn)
	return bm


def cravat(b, lod):
	"""A frothy cream cravat at the throat."""
	n = b.neck_z
	bm = geo.ellipsoid(0.050, 0.030, 0.050, seg(lod, 8, 6), 4, row("cloth"), sharp=SMOOTH)
	geo.translate(bm, (0.0, -0.100, n - 0.040))
	return bm


def coat_cuffs(b, lod, trim="brass", cloth="team_cloth"):
	"""Big turned-back cuffs on the coat's sleeves."""
	bm = geo.new_bm()
	for elbow, wrist in ((b.r_elbow, b.r_wrist), (b.l_elbow, b.l_wrist)):
		lower = (wrist - elbow).length
		geo.merge(bm, _limb(elbow, wrist, [(0.050, lower * 0.40), (0.062, lower * 0.55), (0.064, lower - 0.010),
				(0.054, lower)], seg(lod, 8, 6), sharp=50, bands=[row(cloth), row(trim), row(trim)]))
	return bm


# --- the Voodoo Priestess ---------------------------------------------------

def head_wrap(b, lod):
	"""A tall wound head wrap in the team's colour, tilting back, bound with
	a band of bone beads."""
	z = b.brow_z - 0.020
	bm = geo.new_bm()
	steps = seg(lod, 4, 3)
	for k in range(steps):
		t = k / (steps - 1)
		zz = z + 0.020 + 0.150 * t
		r = 0.180 - 0.020 * t
		ring = geo.lathe([(r - 0.010, zz - 0.034), (r + 0.006, zz - 0.020), (r + 0.006, zz + 0.020),
				(r - 0.010, zz + 0.034)], seg(lod, 12, 9), row("team_cloth" if k % 2 == 0 else "team_cloth_dark"),
				sharp=SMOOTH, sy=0.94)
		geo.translate(ring, (0.0, 0.020 * t * t * 3.0, 0.0))
		geo.merge(bm, ring)
	top = geo.ellipsoid(0.150, 0.140, 0.060, seg(lod, 12, 9), 4, row("team_cloth"), sharp=SMOOTH)
	geo.translate(top, (0.0, 0.060, z + 0.190))
	geo.merge(bm, top)
	if lod == 0:
		for k in range(9):
			a = -math.pi / 2.0 + (k - 4) * 0.30
			bead = geo.ellipsoid(0.014, 0.012, 0.014, 5, 3, row("bone"), sharp=SMOOTH)
			geo.translate(bead, (math.cos(a) * 0.190, math.sin(a) * 0.190 * 0.94, z + 0.012))
			geo.merge(bm, bead)
	return _over_head(b, bm)


def bead_necklace(b, lod):
	"""Strings of bone beads and a little skull round the neck."""
	n = b.neck_z
	bm = geo.new_bm()
	count = seg(lod, 11, 7)
	for k in range(count):
		t = k / (count - 1)
		a = math.pi * (0.15 + 0.70 * t) + math.pi
		bead = geo.ellipsoid(0.016, 0.014, 0.016, 5, 3, row("bone" if k % 2 else "arcane"), sharp=SMOOTH)
		geo.translate(bead, (math.cos(a) * 0.118, math.sin(a) * 0.118 * 0.9 - 0.006, n - 0.040 - 0.040 * math.sin(math.pi * t)))
		geo.merge(bm, bead)
	skull = geo.ellipsoid(0.026, 0.022, 0.026, seg(lod, 8, 6), 4, row("bone"), sharp=SMOOTH)
	geo.translate(skull, (0.0, -0.118, n - 0.096))
	geo.merge(bm, skull)
	if lod == 0:
		for side in (-1.0, 1.0):
			hole = geo.disc(0.007, 0.008, 5, row("boot"), dome=0.001, depth=0.002, simple=True)
			geo.transform(hole, geo.frame(Vector((side * 0.010, -0.139, n - 0.092)), (0.0, -1.0, 0.0), (0.0, 0.0, 1.0)))
			geo.merge(bm, hole)
	return bm


def juju_staff(b, lod, below=0.32):
	"""A crooked driftwood staff crowned with a horned skull, a violet juju
	glow in its sockets and a ring of feathers, beads hung on cords."""
	axis = b.pole_axis
	fist = b.r_fist
	top = fist + axis * 0.64
	pts = [fist - axis * below, fist, fist + axis * 0.28 + Vector((0.014, 0.0, 0.0)),
			fist + axis * 0.48 - Vector((0.012, 0.0, 0.0)), top]
	bm = geo.tube(pts, [0.020, 0.022, 0.022, 0.024, 0.030], seg(lod, 6, 5), row("wood_light"), sharp=40,
			cap_start=row("wood_light"), cap_end=row("wood_light"))
	skull = geo.ellipsoid(0.060, 0.056, 0.058, seg(lod, 10, 7), seg(lod, 5, 4), row("bone"), sharp=SMOOTH)
	jaw = geo.ellipsoid(0.040, 0.040, 0.024, seg(lod, 8, 6), 3, row("bone"), sharp=SMOOTH)
	geo.translate(jaw, (0.0, -0.016, -0.048))
	geo.merge(skull, jaw)
	for side in (-1.0, 1.0):
		socket = geo.disc(0.016, 0.018, 6, row("arcane"), dome=0.004, depth=0.003)
		geo.transform(socket, geo.frame(Vector((side * 0.024, -0.054, 0.006)), Vector((side * 0.2, -1.0, 0.0)),
				(0.0, 0.0, 1.0)))
		geo.merge(skull, socket)
		horn = geo.tube([Vector((side * 0.046, 0.0, 0.030)), Vector((side * 0.090, 0.010, 0.060)),
				Vector((side * 0.100, 0.030, 0.110))], [0.016, 0.011, 0.0], seg(lod, 6, 4), row("bone"), sharp=SMOOTH)
		geo.merge(skull, horn)
	if lod == 0:
		for k in range(5):
			a = math.radians(-60 + 30 * k)
			d = Vector((math.sin(a), 0.4, math.cos(a))).normalized()
			root = Vector((0.0, 0.040, 0.020))
			geo.merge(skull, geo.tube([root, root + d * 0.08, root + d * 0.15], [0.010, 0.022, 0.0], 4, sharp=SMOOTH,
					flatten=0.25, up=(1.0, 0.0, 0.0), ring_swatches=[row("robe_dark"), row("fur_red")]))
	glow = geo.ellipsoid(0.030, 0.030, 0.030, seg(lod, 8, 6), 4, row("arcane"), sharp=SMOOTH)
	geo.translate(glow, (0.0, -0.010, 0.090))
	geo.merge(skull, glow)
	geo.transform(skull, Matrix.Translation(top + Vector((0.0, -0.006, 0.050))) @ Matrix.Scale(1.35, 4))
	geo.merge(bm, skull)
	return bm


# --- the Crab ---------------------------------------------------------------

CRAB_SEAT = 0.50


def crab(b, lod):
	"""A giant coral crab to ride: a broad domed shell with a knobbly rim,
	eyes on stalks (the shared eyes), three jointed legs a side splayed
	wide on black tips, two huge claws raised in front."""
	g = b.base_height
	bm = geo.new_bm()
	shell = geo.ellipsoid(0.330, 0.270, 0.170, seg(lod, 16, 10), seg(lod, 7, 5), row("coat"), sharp=SMOOTH,
			squash_bottom=0.45)
	for v in shell.verts:
		front = max(0.0, -v.co.y / 0.27)
		v.co.z -= 0.040 * front * front
	geo.translate(shell, (0.0, 0.020, g + 0.300))
	geo.merge(bm, shell)
	belly = geo.ellipsoid(0.290, 0.230, 0.080, seg(lod, 14, 9), 4, row("coat_dark"), sharp=SMOOTH)
	geo.translate(belly, (0.0, 0.020, g + 0.230))
	geo.merge(bm, belly)
	if lod == 0:
		for k in range(10):
			a = -math.pi / 2.0 + (k + 0.5) * 2.0 * math.pi / 10.0
			knob = geo.ellipsoid(0.034, 0.034, 0.024, 6, 3, row("coat_dark"), sharp=SMOOTH)
			geo.translate(knob, (math.cos(a) * 0.300, 0.020 + math.sin(a) * 0.245, g + 0.300))
			geo.merge(bm, knob)
	# Legs: three a side, each a knee up high and a pointed black tip.
	for side in (-1.0, 1.0):
		for k, (y, spread) in enumerate(((-0.090, 0.0), (0.040, 0.10), (0.170, 0.22))):
			hip = Vector((side * 0.260, y + 0.020, g + 0.260))
			knee = Vector((side * 0.440, y + spread * 0.5, g + 0.360))
			foot = Vector((side * 0.540, y + spread, g + 0.010))
			geo.merge(bm, geo.tube([hip, knee], [0.040, 0.034], seg(lod, 7, 5), row("coat"), sharp=SMOOTH))
			geo.merge(bm, geo.tube([knee, knee.lerp(foot, 0.6), foot], [0.034, 0.026, 0.004], seg(lod, 7, 5),
					sharp=SMOOTH, ring_swatches=[row("coat"), row("hoof")]))
	# Claws: big pincers held up in front.
	for side in (-1.0, 1.0):
		shoulder = Vector((side * 0.200, -0.200, g + 0.290))
		elbow = Vector((side * 0.300, -0.360, g + 0.380))
		wrist = Vector((side * 0.220, -0.470, g + 0.450))
		geo.merge(bm, geo.tube([shoulder, elbow, wrist], [0.044, 0.040, 0.044], seg(lod, 8, 6), row("coat"),
				sharp=SMOOTH))
		palm = geo.ellipsoid(0.080, 0.110, 0.070, seg(lod, 10, 7), seg(lod, 5, 4), row("coat"), sharp=SMOOTH)
		geo.translate(palm, wrist + Vector((0.0, -0.070, 0.020)))
		geo.merge(bm, palm)
		for k, (dz, lean) in enumerate(((0.050, 0.25), (-0.030, -0.15))):
			base = wrist + Vector((side * -0.010, -0.150, 0.020 + dz))
			finger = geo.tube([base, base + Vector((side * -0.030, -0.080, lean * 0.08)),
					base + Vector((side * -0.060, -0.130, lean * 0.04))], [0.040, 0.028, 0.004], seg(lod, 7, 5),
					sharp=SMOOTH, ring_swatches=[row("coat"), row("hoof")])
			geo.merge(bm, finger)
	# Eyes on stalks over the front of the shell.
	for side in (-1.0, 1.0):
		root = Vector((side * 0.080, -0.180, g + 0.400))
		tip = root + Vector((side * 0.020, -0.030, 0.140))
		geo.merge(bm, geo.tube([root, tip], [0.022, 0.018], seg(lod, 6, 4), row("coat"), sharp=SMOOTH))
		ball = geo.ellipsoid(0.044, 0.042, 0.046, seg(lod, 9, 6), seg(lod, 5, 4), row("cream"), sharp=SMOOTH)
		geo.translate(ball, tip + Vector((0.0, 0.0, 0.030)))
		geo.merge(bm, ball)
		pupil = geo.disc(0.024, 0.030, seg(lod, 8, 6), row("eye"), dome=0.006)
		geo.transform(pupil, geo.frame(tip + Vector((0.0, -0.040, 0.034)), (0.0, -1.0, 0.15), (0.0, 0.0, 1.0)))
		geo.merge(bm, pupil)
		if lod == 0:
			glint = geo.disc(0.008, 0.008, 5, row("glint"), dome=0.002, depth=0.0015, simple=True)
			geo.transform(glint, geo.frame(tip + Vector((0.008, -0.046, 0.046)), (0.0, -1.0, 0.15), (0.0, 0.0, 1.0)))
			geo.merge(bm, glint)
	return bm


def crab_saddle(b, lod):
	"""The team's saddle cloth draped over the shell, a leather saddle on it
	and reins to the eye stalks."""
	g = b.base_height
	bm = geo.new_bm()
	cloth = geo.ellipsoid(0.230, 0.200, 0.060, seg(lod, 14, 9), 4, row("team_cloth"), sharp=SMOOTH)
	for v in cloth.verts:
		d = math.hypot(v.co.x / 0.23, v.co.y / 0.20)
		v.co.z -= 0.060 * d * d
	geo.delete_faces(cloth, lambda f: f.calc_center_median().z < -0.020)
	geo.translate(cloth, (0.0, 0.050, g + 0.455))
	geo.merge(bm, cloth)
	geo.merge(bm, geo.flipped(cloth, row("team_cloth_dark"), inset=0.004))
	seat = geo.ellipsoid(0.100, 0.120, 0.036, seg(lod, 10, 7), 4, row("leather"), sharp=SMOOTH, squash_bottom=0.4)
	geo.translate(seat, (0.0, 0.050, g + CRAB_SEAT - 0.020))
	geo.merge(bm, seat)
	return bm


# --- the Cannon Cart --------------------------------------------------------

## A small ship's gun, grown to a siege engine's size (they tower over men).
CART_SCALE = 1.75


## The cart's axles [(y, z), ...] before it is grown, and its wheels' radius.
CART_AXLES = [(-0.55, 0.26), (0.45, 0.26)]
CART_WHEEL_RADIUS = 0.26


def cannon_cart(lod, part=None):
	"""A stubby black ship's cannon on a wooden truck carriage with four
	small chunky wheels, the carriage cheeks painted in the team's colour,
	a powder keg and a pyramid of cannonballs at its tail."""
	from siege import _wheel, _cyl, _beam, _ring
	from beasts import _grow
	bm = geo.new_bm()
	wheels = []
	for y, z in CART_AXLES:
		axle = _cyl((-0.56, y, z), (0.56, y, z), 0.05, "plate_dark", lod)
		for x in (-0.48, 0.48):
			geo.merge(axle, _wheel(lod, x, y, z, CART_WHEEL_RADIUS, 0.12, 1.0 if x > 0 else -1.0, segs=(16, 10)))
		wheels.append(axle)
	bed = geo.box(0.80, 1.85, 0.14, row("wood"), HARD, bevel=0.03)
	geo.translate(bed, (0.0, 0.17, 0.40))
	geo.merge(bm, bed)
	for side in (-1.0, 1.0):
		cheek = geo.plate([(-0.70, 0.0), (0.55, 0.0), (0.55, 0.30), (0.20, 0.42), (-0.10, 0.42), (-0.30, 0.30),
				(-0.70, 0.20)], 0.10, row("team_paint"), sharp=HARD)
		geo.rotate(cheek, 90.0, 'Z')
		geo.translate(cheek, (side * 0.33, 0.0, 0.46))
		geo.merge(bm, cheek)
		edge = _beam((side * 0.33, -0.70, 0.47), (side * 0.33, 0.55, 0.47), 0.12, 0.06, "brass")
		geo.merge(bm, edge)
	barrel = geo.lathe([(0.0, -0.10), (0.16, -0.10), (0.20, -0.06), (0.21, 0.10), (0.18, 0.60), (0.15, 0.95),
			(0.18, 1.00), (0.18, 1.08), (0.10, 1.10)], seg(lod, 16, 10), row("plate_dark"), sharp=SMOOTH,
			phase=0.0, cap_end=row("boot"))
	for z, r in ((0.10, 0.22), (0.55, 0.19)):
		geo.merge(barrel, _ring(r, z, 0.03, "plate_dark", lod, proud=0.02))
	knob = geo.ellipsoid(0.07, 0.07, 0.07, seg(lod, 8, 6), 4, row("plate_dark"), sharp=SMOOTH)
	geo.translate(knob, (0.0, 0.0, -0.16))
	geo.merge(barrel, knob)
	geo.transform(barrel, geo.frame(Vector((0.0, 0.25, 0.90)), Vector((0.0, -1.0, 0.18)), (0.0, 0.0, 1.0)))
	geo.merge(bm, barrel)
	trunnion = _cyl((-0.36, 0.15, 0.86), (0.36, 0.15, 0.86), 0.06, "plate_dark", lod)
	geo.merge(bm, trunnion)
	keg = geo.lathe([(0.0, 0.0), (0.15, 0.0), (0.18, 0.12), (0.15, 0.26), (0.0, 0.26)], seg(lod, 12, 8), row("wood"),
			sharp=SMOOTH, phase=0.0)
	geo.merge(keg, _ring(0.16, 0.04, 0.02, "plate_dark", lod, proud=0.012))
	geo.merge(keg, _ring(0.16, 0.22, 0.02, "plate_dark", lod, proud=0.012))
	geo.translate(keg, (0.22, 0.85, 0.47))
	geo.merge(bm, keg)
	for k, (x, y, z) in enumerate(((-0.22, 0.80, 0.55), (-0.08, 0.80, 0.55), (-0.15, 0.92, 0.55), (-0.15, 0.85, 0.66))):
		ball = geo.ellipsoid(0.07, 0.07, 0.07, seg(lod, 8, 6), 4, row("plate_dark"), sharp=SMOOTH)
		geo.translate(ball, (x, y, z))
		geo.merge(bm, ball)
	from siege import split_wheels
	return split_wheels(bm, wheels, part, CART_SCALE)
