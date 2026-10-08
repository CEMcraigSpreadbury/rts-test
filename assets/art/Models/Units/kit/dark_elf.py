"""Dark elf parts: the human chibi (parts.Body, head, face and hair) with
long pointed ears, in black-violet lacquered plate (plate_dark) edged and
spiked in silver (the dark_elves palette's steel, trim and brass), with
violet arcane inlays (arcane). The team's colour is on the tabard and the
shield's face, as the humans' rule has it.

Head pieces are built upright and tipped back by the recipe (units._head).
"""
import math

from mathutils import Matrix, Vector

import geo
from geo import FLAT, HARD, SMOOTH
from palette import row
import parts
from parts import seg


# --- head -------------------------------------------------------------------

def ears(b, lod):
	"""Long leaf-shaped pointed ears, out through the hair and swept up and
	back, flat to the front so they read from the camera."""
	bm = geo.new_bm()
	c = b.head_centre
	for side in (-1.0, 1.0):
		root = Vector((side * 0.130, c.y + 0.010, c.z - 0.010))
		pts = [root, root + Vector((side * 0.080, 0.018, 0.024)), root + Vector((side * 0.150, 0.036, 0.060)),
				root + Vector((side * 0.200, 0.050, 0.094))]
		ear = geo.tube(pts, [0.030, 0.032, 0.020, 0.0], seg(lod, 7, 5), row("skin"), sharp=SMOOTH,
				cap_start=row("skin"), flatten=0.38, up=(0.0, 1.0, 0.0))
		geo.merge(bm, ear)
		if lod == 0:
			inner = [p + Vector((0.0, -0.006, 0.0)) for p in pts[1:3]]
			geo.merge(bm, geo.tube([inner[0] - Vector((side * 0.02, 0.0, 0.006)), inner[0], inner[1]],
					[0.0, 0.014, 0.0], 5, row("blush"), flatten=0.4, up=(0.0, 1.0, 0.0)))
	return bm


def long_hair(b, lod):
	"""White hair falling long down the back from under the helm."""
	c = b.head_centre
	pts = [(0.0, c.y + 0.090, c.z + 0.040), (0.0, c.y + 0.140, c.z - 0.080), (0.0, c.y + 0.150, c.z - 0.190),
			(0.0, c.y + 0.135, c.z - 0.270)]
	return geo.tube(pts, [0.120, 0.110, 0.080, 0.0], seg(lod, 9, 6), row("hair"), sharp=SMOOTH,
			cap_start=row("hair"), flatten=0.45, up=(0.0, 1.0, 0.0))


def spiked_helm(b, lod):
	"""A black-violet half helm: a pointed skullcap dipping to a widow's
	peak over the brow, a silver band with a violet gem, a tall swept-back
	blade crest and two silver horns swept back from the temples. It leaves
	the ears and the hair at the sides free."""
	bm = geo.new_bm()
	segs = seg(lod, 16, 10)
	z = b.brow_z
	sy = 0.95
	prof = [(0.171, z - 0.006), (0.175, z + 0.034), (0.163, z + 0.082), (0.130, z + 0.126), (0.074, z + 0.160),
			(0.0, z + 0.182)]
	if lod > 0:
		prof = [prof[i] for i in (0, 1, 3, 5)]

	def warp(theta, r, zz):
		front = max(0.0, -math.sin(theta))
		if zz < z:
			zz -= 0.050 * front ** 10
		return (r * math.cos(theta), r * math.sin(theta) * sy, zz)

	geo.merge(bm, geo.lathe(prof, segs, row("plate_dark"), sharp=40, warp=warp, cap_start=row("lining")))
	band = geo.lathe([(0.176, z + 0.004), (0.180, z + 0.016), (0.172, z + 0.026)], segs, row("trim"), sharp=40,
			sy=sy)
	geo.merge(bm, band)
	gem = geo.disc(0.020, 0.026, seg(lod, 8, 5), row("arcane"), dome=0.010, depth=0.004)
	geo.merge(bm, gem, geo.frame((0.0, -0.180 * sy, z + 0.006), (0.0, -1.0, 0.12), (0.0, 0.0, 1.0)))
	# The blade crest, front to back over the crown (outline in y, z).
	crest = [(-0.090, z + 0.120), (-0.010, z + 0.190), (0.070, z + 0.250), (0.190, z + 0.250), (0.110, z + 0.200),
			(0.140, z + 0.150), (0.060, z + 0.120)]
	fin = geo.plate(crest, 0.020, row("plate_dark"), side=row("steel"), sharp=FLAT)
	geo.rotate(fin, 90.0, 'Z')
	geo.merge(bm, fin)
	for side in (-1.0, 1.0):
		root = Vector((side * 0.150, -0.040, z + 0.040))
		pts = [root, root + Vector((side * 0.060, 0.050, 0.070)), root + Vector((side * 0.085, 0.140, 0.150))]
		geo.merge(bm, geo.tube(pts, [0.030, 0.020, 0.0], seg(lod, 7, 5), row("steel"), sharp=40,
				cap_start=row("steel")))
	geo.translate(bm, (b.head_centre.x, b.head_centre.y + 0.004, 0.0))
	return bm


# --- body -------------------------------------------------------------------

def spiked_pauldrons(b, lod):
	"""Black-violet layered shoulder plates edged in silver, each crowned
	with silver spikes."""
	bm = parts.pauldrons(b, lod, "plate_dark", "trim")
	for side, shoulder in ((-1.0, b.r_shoulder), (1.0, b.l_shoulder)):
		spikes = ((0.0, 0.110, 0.026),) if lod > 0 else ((0.0, 0.120, 0.026), (0.045, 0.075, 0.018))
		for back, length, radius in spikes:
			root = shoulder + Vector((side * 0.030, back, 0.070))
			d = Vector((side * 0.55, 0.10 + back, 1.0)).normalized()
			geo.merge(bm, geo.tube([root, root + d * length * 0.5, root + d * length], [radius, radius * 0.6, 0.0],
					seg(lod, 6, 4), row("steel"), sharp=40, cap_start=row("steel")))
	return bm


def gorget(b, lod):
	"""A pointed plate collar, black-violet with a silver edge."""
	n = b.neck_z
	prof = [(0.132, n - 0.034), (0.124, n - 0.010), (0.100, n + 0.010), (0.088, n + 0.028)]

	def warp(theta, r, zz):
		front = max(0.0, -math.sin(theta))
		if zz < n - 0.02:
			zz -= 0.040 * front ** 6
		return (r * math.cos(theta), r * math.sin(theta) * 0.92, zz)

	return geo.lathe(prof, seg(lod, 12, 8), sharp=30, warp=warp,
			ring_swatches=[row("trim"), row("plate_dark"), row("plate_dark")])


# --- arms in hand -----------------------------------------------------------

def curved_blade(b, lod):
	"""A huge curved dark-steel sword up in the right fist: a broad silver
	blade with a hooked back spike and a clipped, curling tip, a violet
	rune line down its middle, a black crescent guard swept up in spikes,
	a dark grip and a spiked silver pommel."""
	bm = geo.lathe([(0.0, -0.080), (0.017, -0.075), (0.017, 0.055), (0.0, 0.060)], seg(lod, 6, 4),
			row("leather_dark"), sharp=40, phase=0.0)
	pommel = geo.tube([(0.0, 0.0, -0.075), (0.0, 0.0, -0.100), (0.0, 0.0, -0.135)], [0.026, 0.020, 0.0],
			seg(lod, 6, 4), row("steel"), sharp=40, cap_start=row("steel"))
	geo.merge(bm, pommel)
	guard = geo.tube([(-0.110, 0.0, 0.120), (-0.070, 0.0, 0.070), (0.0, 0.0, 0.055), (0.070, 0.0, 0.070),
			(0.110, 0.0, 0.120)], [0.0, 0.016, 0.024, 0.016, 0.0], seg(lod, 6, 4), row("plate_dark"), sharp=40)
	geo.merge(bm, guard)
	edge = [(-0.042, 0.060), (0.046, 0.060), (0.062, 0.200), (0.078, 0.340), (0.066, 0.470), (0.030, 0.580),
			(-0.040, 0.650), (-0.020, 0.560), (-0.034, 0.470), (-0.040, 0.380), (-0.080, 0.330), (-0.040, 0.300)]
	geo.merge(bm, geo.plate(edge, 0.024, row("blade"), side=row("steel"), sharp=FLAT))
	rune = [(-0.009, 0.110), (0.009, 0.110), (0.012, 0.420), (0.0, 0.460), (-0.010, 0.420)]
	geo.merge(bm, geo.plate(rune, 0.028, row("arcane"), side=row("arcane"), sharp=FLAT))
	geo.transform(bm, geo.frame(b.r_fist, b.sword_axis, parts.edge_down(b.sword_axis)))
	return bm


def spiked_shield(b, lod):
	"""A tall angular shield on the left forearm: a face in the team's
	colour, crowned with three points and tapering to a point below, on a
	black-violet backing that shows as a rim, a silver spike boss."""
	outline = [(0.0, -0.220), (0.118, -0.020), (0.124, 0.110), (0.060, 0.090), (0.0, 0.165), (-0.060, 0.090),
			(-0.124, 0.110), (-0.118, -0.020)]
	face = geo.plate(outline, 0.014, row("team"), back=row("plate_dark"), side=row("team_dark"), sharp=FLAT,
			bend=0.9)
	bm = geo.new_bm()
	geo.merge(bm, face)
	backing = geo.plate([(x * 1.14, z * 1.12 + 0.002) for x, z in outline], 0.016, row("plate_dark"),
			side=row("trim"), sharp=FLAT, bend=0.9)
	geo.translate(backing, (0.0, 0.009, 0.0))
	geo.merge(bm, backing)
	boss = geo.lathe([(0.040, 0.0), (0.040, 0.012), (0.020, 0.040), (0.0, 0.085)], seg(lod, 8, 5), row("steel"),
			sharp=40, phase=0.0)
	geo.merge(bm, boss, geo.frame((0.0, -0.006, 0.010), (0.0, -1.0, 0.0), (0.0, 0.0, 1.0)))
	if lod == 0:
		for x in (-1.0, 1.0):
			stripe = geo.plate([(x * 0.010, -0.170), (x * 0.026, -0.150), (x * 0.098, 0.0), (x * 0.098, 0.070),
					(x * 0.080, 0.070), (x * 0.010, -0.120)], 0.004, row("trim"), sharp=FLAT, bend=0.9)
			geo.translate(stripe, (0.0, -0.008, 0.0))
			geo.merge(bm, stripe)
	forearm_mid = (b.l_elbow + b.l_wrist) * 0.5
	centre = forearm_mid + b.shield_normal * 0.060
	geo.transform(bm, geo.orient(centre, b.shield_normal, (0.0, 0.0, 1.0)))
	return bm


# --- archer and assassin ----------------------------------------------------

def face_mask(b, lod, row_name="cloth_dark"):
	"""A cloth mask over the nose, mouth and chin, up to just under the eyes,
	wrapped round the cheeks to the ears."""
	c = b.head_centre
	half = b.head_size * 0.5
	top = c.z - 0.048
	prof = [(0.60, c.z - 0.168), (0.86, c.z - 0.148), (0.97, c.z - 0.112), (1.02, c.z - 0.078), (0.99, top)]
	n = 2.6

	def warp(theta, r, zz):
		co, si = math.cos(theta), math.sin(theta)
		se = (abs(co) ** n + abs(si) ** n) ** (-1.0 / n)
		below = max(0.0, (c.z - zz) / half.z)
		return (c.x + r * half.x * se * co * (1.0 - 0.15 * below * below),
				c.y + r * half.y * se * si * (1.0 - 0.05 * below), zz)

	shell = geo.lathe(prof, seg(lod, 18, 12), row(row_name), sharp=SMOOTH, warp=warp)
	geo.delete_faces(shell, lambda f: f.calc_center_median().y > c.y + 0.030)
	bm = geo.new_bm()
	geo.merge(bm, shell)
	geo.merge(bm, geo.flipped(shell, row(row_name), inset=0.004))
	return bm


def topknot(b, lod):
	"""White hair gathered high on the crown in a silver ring and falling
	back in a long thick tail."""
	bm = geo.new_bm()
	c = b.head_centre
	z = b.brow_z
	bun = geo.ellipsoid(0.062, 0.062, 0.054, seg(lod, 9, 6), seg(lod, 5, 4), row("hair"), sharp=SMOOTH)
	geo.translate(bun, (0.0, c.y + 0.050, z + 0.118))
	geo.merge(bm, bun)
	ring = geo.lathe([(0.046, -0.016), (0.052, 0.0), (0.046, 0.016)], seg(lod, 9, 6), row("trim"), sharp=40)
	geo.transform(ring, geo.frame((0.0, c.y + 0.092, z + 0.140), (0.0, 1.0, 0.35), (0.0, 0.0, 1.0)))
	geo.merge(bm, ring)
	pts = [(0.0, c.y + 0.095, z + 0.145), (0.0, c.y + 0.180, z + 0.130), (0.0, c.y + 0.240, z + 0.040),
			(0.0, c.y + 0.260, z - 0.080), (0.0, c.y + 0.240, z - 0.200)]
	geo.merge(bm, geo.tube(pts, [0.045, 0.054, 0.048, 0.034, 0.0], seg(lod, 9, 6), row("hair"), sharp=SMOOTH,
			flatten=0.7, up=(0.0, 1.0, 0.0)))
	return bm


def recurve_bow(b, lod):
	"""A big black-violet recurve bow upright in the left fist, its tips
	flicking forward into silver blade points, a silver-banded grip with a
	violet gem; a long nocked arrow with a venom-green head."""
	grip = b.l_fist
	steps = seg(lod, 13, 7)
	cant = math.radians(48.0)
	back = Vector((math.sin(cant), math.cos(cant), 0.0))
	pts, radii = [], []
	for i in range(steps):
		t = -1.0 + 2.0 * i / (steps - 1)
		y = 0.130 * t * t - 1.5 * max(0.0, abs(t) - 0.62) ** 2
		pts.append(grip + back * y + Vector((0.0, 0.0, 0.03 + t * 0.31)))
		radii.append(0.036 * (1.0 - 0.5 * abs(t)))
	bm = geo.tube(pts, radii, seg(lod, 5, 4), row("plate_dark"), sharp=40, flatten=0.7, up=(1.0, 0.0, 0.0))
	for tip, before in ((pts[-1], pts[-2]), (pts[0], pts[1])):
		d = (tip - before).normalized()
		geo.merge(bm, geo.tube([tip - d * 0.03, tip + d * 0.035, tip + d * 0.085], [0.022, 0.016, 0.0], seg(lod, 5, 4),
				row("steel"), sharp=40, cap_start=row("steel")))
	wrap = geo.lathe([(0.032, -0.060), (0.036, -0.040), (0.033, 0.0), (0.036, 0.040), (0.032, 0.060)],
			seg(lod, 6, 4), sharp=40, phase=0.0,
			ring_swatches=[row("trim"), row("leather_dark"), row("leather_dark"), row("trim")])
	geo.translate(wrap, grip)
	geo.merge(bm, wrap)
	gem = geo.disc(0.018, 0.024, seg(lod, 7, 5), row("arcane"), dome=0.008, depth=0.004)
	geo.merge(bm, gem, geo.frame(grip - back * 0.036, -back, (0.0, 0.0, 1.0)))
	geo.merge(bm, geo.tube([pts[0], pts[-1]], [0.005, 0.005], 3, row("mail"), sharp=SMOOTH))
	# The arrow: nock at the right fist, past the grip toward the target.
	nock = b.r_fist + Vector((0.0, 0.0, 0.010))
	d = (grip - nock).normalized()
	head_at = grip + d * 0.120
	geo.merge(bm, geo.tube([nock, head_at], [0.008, 0.008], seg(lod, 4, 3), row("leather_dark"), sharp=40))
	head = geo.plate([(-0.030, 0.0), (0.030, 0.0), (0.0, 0.085)], 0.012, row("crystal"), side=row("crystal"),
			sharp=FLAT)
	geo.merge(bm, head, geo.frame(head_at, d, (0.0, 0.0, 1.0)))
	if lod == 0:
		for a in (0.0, 90.0):
			fl = geo.plate([(0.0, 0.0), (0.022, 0.012), (0.018, 0.060), (0.0, 0.070)], 0.004, row("arcane"),
					sharp=FLAT)
			geo.rotate(fl, a, 'Z')
			geo.merge(bm, fl, geo.frame(nock + d * 0.008, d, (0.0, 0.0, 1.0)))
	return bm


def fang_dagger(b, lod, fist, axis, size=1.0):
	"""A big curved fang dagger: a broad silver blade curving to a hooked
	tip with a venom-green groove, a black crescent guard, a dark grip and
	a silver spike pommel."""
	k = size
	bm = geo.lathe([(0.0, -0.065), (0.016, -0.060), (0.016, 0.040), (0.0, 0.045)], seg(lod, 6, 4),
			row("leather_dark"), sharp=40, phase=0.0)
	geo.merge(bm, geo.tube([(0.0, 0.0, -0.060), (0.0, 0.0, -0.085), (0.0, 0.0, -0.115)], [0.022, 0.016, 0.0],
			seg(lod, 6, 4), row("steel"), sharp=40, cap_start=row("steel")))
	geo.merge(bm, geo.tube([(-0.080, 0.0, 0.085), (-0.050, 0.0, 0.052), (0.0, 0.0, 0.044), (0.050, 0.0, 0.052),
			(0.080, 0.0, 0.085)], [0.0, 0.014, 0.020, 0.014, 0.0], seg(lod, 6, 4), row("plate_dark"), sharp=40))
	edge = [(-0.034, 0.050), (0.038, 0.050), (0.060, 0.160), (0.062, 0.260), (0.040, 0.340), (-0.010, 0.400),
			(-0.020, 0.330), (-0.034, 0.240), (-0.040, 0.140)]
	geo.merge(bm, geo.plate([(x * k, 0.050 + (z - 0.050) * k) for x, z in edge], 0.022, row("blade"),
			side=row("steel"), sharp=FLAT))
	groove = [(-0.008, 0.085), (0.010, 0.085), (0.018, 0.250), (0.004, 0.320), (-0.012, 0.250)]
	geo.merge(bm, geo.plate([(x * k, 0.050 + (z - 0.050) * k) for x, z in groove], 0.026, row("crystal"),
			side=row("crystal"), sharp=FLAT))
	geo.transform(bm, geo.frame(fist, axis, parts.edge_down(axis)))
	return bm


def waist_sash(b, lod):
	"""A sash in the team's colour knotted round the waist, two tails
	hanging at the left hip."""
	w = b.waist_z
	r = b.torso_radius(w)
	bm = geo.lathe([(r - 0.004, w - 0.026), (r + 0.010, w - 0.020), (r + 0.010, w + 0.020), (r - 0.004, w + 0.026)],
			seg(lod, 12, 8), row("team_cloth"), sharp=40, sy=b.torso_depth)
	knot = Vector((r * 0.80, -r * b.torso_depth * 0.62, w))
	geo.merge(bm, geo.ellipsoid(0.030, 0.024, 0.028, seg(lod, 7, 5), 3, row("team_cloth"), sharp=SMOOTH),
			Matrix.Translation(knot))
	for dx, length in ((-0.012, 0.150), (0.026, 0.120)):
		tail = geo.plate([(-0.022, 0.0), (0.022, 0.0), (0.026, -length), (0.0, -length - 0.025),
				(-0.026, -length)], 0.008, row("team_cloth"), back=row("team_cloth_dark"), sharp=SMOOTH)
		geo.transform(tail, geo.orient(knot + Vector((dx, -0.010, -0.010)), (0.55, -0.80, 0.0)))
		geo.merge(bm, tail)
	return bm


# --- guard and rider --------------------------------------------------------

def glaive(b, lod, length=1.18, below=0.26, radius=0.024):
	"""A tall glaive stood upright in the right fist: a black shaft banded in
	silver, a huge single-edged silver blade sweeping back to a hooked tip,
	edge down (parts.edge_down), a back spike and a violet gem at its root."""
	top = length - below
	bm = geo.lathe([(radius, -below), (radius, top - 0.10)], seg(lod, 6, 5), row("plate_dark"), sharp=40,
			phase=0.0, cap_start=row("steel"), cap_end=row("plate_dark"))
	for z in (-below + 0.02, 0.18, top - 0.14):
		geo.merge(bm, geo.lathe([(radius * 1.35, z - 0.022), (radius * 1.5, z), (radius * 1.35, z + 0.022)],
				seg(lod, 6, 5), row("trim"), sharp=40, phase=0.0))
	edge = [(-0.020, top - 0.140), (0.030, top - 0.120), (0.092, top - 0.030), (0.120, top + 0.090),
			(0.104, top + 0.200), (0.060, top + 0.300), (0.010, top + 0.360), (0.020, top + 0.250),
			(0.006, top + 0.120), (-0.024, top + 0.020), (-0.070, top - 0.010), (-0.030, top - 0.050)]
	geo.merge(bm, geo.plate(edge, 0.024, row("blade"), side=row("steel"), sharp=FLAT))
	rune = [(0.020, top - 0.060), (0.040, top - 0.060), (0.072, top + 0.090), (0.060, top + 0.180),
			(0.040, top + 0.090)]
	geo.merge(bm, geo.plate(rune, 0.028, row("arcane"), side=row("arcane"), sharp=FLAT))
	gem = geo.disc(0.020, 0.026, seg(lod, 8, 5), row("arcane"), dome=0.010, depth=0.004)
	geo.merge(bm, gem, geo.frame((0.0, -0.016, top - 0.110), (0.0, -1.0, 0.0), (0.0, 0.0, 1.0)))
	# The blade's flat to the camera, its edge out to the right.
	axis = Vector(b.pole_axis).normalized()
	geo.transform(bm, geo.frame(b.r_fist, axis, axis.cross(Vector((-1.0, 0.0, 0.0)))))
	return bm


def spiked_round_shield(b, lod):
	"""A round shield on the left forearm: a face in the team's colour with a
	thick silver rim ringed by short silver spikes, a black-violet backing
	and a silver spike boss."""
	bm = geo.new_bm()
	segs = seg(lod, 16, 10)
	radius = 0.130
	face = geo.lathe([(0.0, -0.012), (radius - 0.010, -0.012), (radius, -0.004), (radius * 0.6, 0.014),
			(0.0, 0.020)], segs, sharp=40, phase=0.0,
			ring_swatches=[row("plate_dark"), row("plate_dark"), row("team"), row("team")])
	geo.merge(bm, face)
	geo.merge(bm, geo.lathe([(radius + 0.010, -0.012), (radius + 0.012, 0.004), (radius - 0.022, 0.010)], segs,
			row("steel"), sharp=40, phase=0.0))
	geo.merge(bm, geo.lathe([(0.040, 0.012), (0.040, 0.024), (0.020, 0.050), (0.0, 0.095)], seg(lod, 8, 5),
			row("steel"), sharp=40, phase=0.0))
	for k in range(seg(lod, 8, 6)):
		a = (k + 0.5) * 2.0 * math.pi / seg(lod, 8, 6)
		d = Vector((math.cos(a), math.sin(a), 0.0))
		root = d * (radius + 0.004)
		geo.merge(bm, geo.tube([root, root + d * 0.030, root + d * 0.058], [0.016, 0.010, 0.0], seg(lod, 5, 4),
				row("steel"), sharp=40, cap_start=row("steel")))
	forearm_mid = (b.l_elbow + b.l_wrist) * 0.5
	centre = forearm_mid + b.shield_normal * 0.066
	geo.transform(bm, geo.frame(centre, b.shield_normal, (0.0, 0.0, 1.0)))
	return bm


def mount_spines(lod, g):
	"""A crest of silver-blue spines down the dark horse's neck, between
	the ears and along the mane (horse.py's mane line)."""
	import horse
	bm = geo.new_bm()
	steps = seg(lod, 6, 4)
	for i in range(steps):
		t = i / (steps - 1)
		p = Vector((0.0, -0.360, g + 0.850)).lerp(Vector((0.0, -0.130, g + 0.610)), t)
		p.z -= horse.DROP
		d = Vector((0.0, 0.55, 1.0)).normalized()
		length = 0.110 - 0.040 * t
		geo.merge(bm, geo.tube([p, p + d * length * 0.5, p + d * length], [0.026, 0.016, 0.0], seg(lod, 5, 4),
				row("mane"), sharp=40, cap_start=row("mane"), flatten=0.5, up=(1.0, 0.0, 0.0)))
	return bm


# --- sorceress and spellstealer ---------------------------------------------

def thorn_tiara(b, lod):
	"""The Sorceress's crown: a silver circlet with a violet gem at the brow
	and five tall black-violet spires, silver-edged, fanned up and out over
	the front of the head, the middle one tallest."""
	bm = geo.new_bm()
	z = b.brow_z - 0.010
	sy = 0.95
	segs = seg(lod, 16, 10)
	geo.merge(bm, geo.lathe([(0.172, z - 0.012), (0.178, z + 0.002), (0.176, z + 0.022), (0.168, z + 0.030)], segs,
			row("trim"), sharp=40, sy=sy))
	for k, h in ((-2, 0.120), (-1, 0.170), (0, 0.235), (1, 0.170), (2, 0.120)):
		theta = -math.pi / 2.0 + k * 0.50
		out = Vector((math.cos(theta), math.sin(theta) * sy, 0.0))
		w = 0.036 if k == 0 else 0.030
		spire = geo.plate([(-w, 0.0), (w, 0.0), (w * 0.45, h * 0.55), (0.0, h), (-w * 0.45, h * 0.55)], 0.018,
				row("plate_dark"), side=row("steel"), sharp=FLAT)
		up = Vector((0.0, 0.0, 1.0)) + out * (0.30 + 0.10 * abs(k))
		geo.transform(spire, geo.orient(Vector((0.0, 0.0, z + 0.010)) + out * 0.172, out, up))
		geo.merge(bm, spire)
		if k == 0 or lod == 0:
			r = 0.024 if k == 0 else 0.012
			gem = geo.disc(r, r * 1.25, seg(lod, 8, 5), row("arcane"), dome=r * 0.45, depth=0.004)
			geo.merge(bm, gem, geo.frame(Vector((0.0, 0.0, z + 0.018 + (0.012 if k == 0 else 0.0)))
					+ out * 0.184, out, (0.0, 0.0, 1.0)))
	geo.translate(bm, (b.head_centre.x, b.head_centre.y + 0.004, 0.0))
	return bm


def venom_staff(b, lod, below=0.32):
	"""A tall black staff banded in silver, its head three silver claws
	curling up round a big venom-green orb."""
	axis = Vector(b.pole_axis).normalized()
	fist = b.r_fist
	foot = fist - axis * below
	top = fist + axis * 0.74
	bm = geo.tube([foot, top], [0.022, 0.026], seg(lod, 6, 5), row("plate_dark"), sharp=40,
			cap_start=row("steel"))
	for t in (0.05, 0.55):
		p = fist + axis * t
		geo.merge(bm, geo.lathe([(0.032, -0.020), (0.036, 0.0), (0.032, 0.020)], seg(lod, 6, 5), row("trim"),
				sharp=40, phase=0.0), geo.frame(p, axis))
	geo.merge(bm, geo.lathe([(0.026, -0.030), (0.046, -0.004), (0.040, 0.016), (0.026, 0.024)], seg(lod, 8, 5),
			row("steel"), sharp=40, phase=0.0), geo.frame(top, axis))
	side = axis.cross(Vector((1.0, 0.0, 0.0))).normalized()
	other = axis.cross(side).normalized()
	for k in range(3):
		a = math.radians(90.0 + 120.0 * k)
		out = side * math.cos(a) + other * math.sin(a)
		pts = [top + out * 0.030, top + out * 0.095 + axis * 0.060, top + out * 0.085 + axis * 0.160,
				top + out * 0.030 + axis * 0.235]
		geo.merge(bm, geo.tube(pts, [0.022, 0.020, 0.014, 0.0], seg(lod, 6, 4), row("steel"), sharp=40,
				cap_start=row("steel")))
	orb = geo.ellipsoid(0.072, 0.072, 0.072, seg(lod, 10, 6), seg(lod, 6, 4), row("crystal"), sharp=SMOOTH)
	geo.translate(orb, top + axis * 0.120)
	geo.merge(bm, orb)
	return bm


def crescent_circlet(b, lod):
	"""The Spellstealer's crown: a silver circlet with a big violet gem at
	the brow and two great silver crescent horns sweeping up from the
	temples and curling in over the head, like a horned moon."""
	bm = geo.new_bm()
	z = b.brow_z - 0.010
	sy = 0.95
	geo.merge(bm, geo.lathe([(0.172, z - 0.012), (0.178, z + 0.002), (0.176, z + 0.022), (0.168, z + 0.030)],
			seg(lod, 16, 10), row("steel"), sharp=40, sy=sy))
	for side in (-1.0, 1.0):
		pts = [Vector((side * 0.160, -0.060, z + 0.010)), Vector((side * 0.215, -0.050, z + 0.090)),
				Vector((side * 0.225, -0.030, z + 0.190)), Vector((side * 0.180, -0.010, z + 0.275)),
				Vector((side * 0.105, 0.0, z + 0.320))]
		geo.merge(bm, geo.tube(pts, [0.026, 0.034, 0.030, 0.018, 0.0], seg(lod, 7, 5), row("steel"), sharp=40,
				cap_start=row("steel"), flatten=0.6, up=(0.0, 1.0, 0.0)))
	gem = geo.lathe([(0.034, 0.0), (0.030, 0.012), (0.0, 0.026)], seg(lod, 8, 5), row("arcane"), sharp=40,
			cap_start=row("trim"))
	geo.merge(bm, gem, geo.frame(Vector((0.0, -0.176 * sy, z + 0.014)), (0.0, -1.0, 0.10), (0.0, 0.0, 1.0)))
	geo.translate(bm, (b.head_centre.x, b.head_centre.y + 0.004, 0.0))
	return bm


def high_collar(b, lod):
	"""A tall flared black-violet collar standing up behind the head, open
	at the front, lined in violet and edged in silver."""
	n = b.neck_z
	prof = [(0.110, n - 0.040), (0.128, n + 0.010), (0.168, n + 0.090), (0.215, n + 0.165)]

	def warp(theta, r, zz):
		back = max(0.0, math.sin(theta))
		if zz > n + 0.05:
			zz += 0.050 * back * (zz - n) / 0.165
		return (r * math.cos(theta), r * math.sin(theta) * 0.90 + 0.020, zz)

	shell = geo.lathe(prof, seg(lod, 16, 10), row("plate_dark"), sharp=40, warp=warp)
	geo.delete_faces(shell, lambda f: f.calc_center_median().y < -0.030)
	bm = geo.new_bm()
	geo.merge(bm, shell)
	geo.merge(bm, geo.flipped(shell, row("arcane"), inset=0.006))
	return bm


def siphon_orb(b, lod):
	"""A big violet orb of stolen magic held up on the left palm, cupped in
	three silver claws and circled by two tilted silver rings."""
	bm = geo.new_bm()
	centre = b.l_fist + Vector((0.010, -0.040, 0.120))
	geo.merge(bm, geo.ellipsoid(0.092, 0.092, 0.092, seg(lod, 10, 6), seg(lod, 6, 4), row("arcane"), sharp=SMOOTH),
			Matrix.Translation(centre))
	for k in range(3):
		a = math.radians(-90.0 + 120.0 * k)
		out = Vector((math.cos(a), math.sin(a), 0.0))
		root = b.l_fist + Vector((0.0, 0.0, 0.020))
		pts = [root + out * 0.020, root + out * 0.085 + Vector((0.0, 0.0, 0.040)),
				centre + out * 0.090 + Vector((0.0, 0.0, 0.020)), centre + out * 0.050 + Vector((0.0, 0.0, 0.075))]
		geo.merge(bm, geo.tube(pts, [0.016, 0.016, 0.011, 0.0], seg(lod, 5, 4), row("steel"), sharp=40,
				cap_start=row("steel")))
	for tilt in ((0.55, 0.0, 1.0), (-0.55, 0.30, 1.0)):
		ring = geo.lathe([(0.122, -0.010), (0.129, 0.0), (0.122, 0.010), (0.115, 0.0)], seg(lod, 16, 10),
				row("steel"), sharp=40)
		geo.merge(bm, ring, geo.frame(centre, tilt))
	return bm


def hook_wand(b, lod):
	"""A short black rod up in the right fist, crowned with a big silver
	crescent hook (edge down, parts.edge_down) and a violet gem."""
	bm = geo.lathe([(0.0, -0.090), (0.020, -0.085), (0.020, 0.260), (0.0, 0.265)], seg(lod, 6, 4),
			row("plate_dark"), sharp=40, phase=0.0)
	geo.merge(bm, geo.tube([(0.0, 0.0, -0.085), (0.0, 0.0, -0.110), (0.0, 0.0, -0.140)], [0.028, 0.022, 0.0],
			seg(lod, 6, 4), row("steel"), sharp=40, cap_start=row("steel")))
	top = 0.250
	cx, cz = 0.010, top + 0.110
	outer, inner = [], []
	steps = seg(lod, 11, 7)
	for i in range(steps):
		a = math.radians(-100.0 + 250.0 * i / (steps - 1))
		outer.append((cx + math.cos(a) * 0.130, cz + math.sin(a) * 0.130))
		inner.append((cx - 0.035 + math.cos(a) * 0.088, cz + 0.020 + math.sin(a) * 0.088))
	edge = outer + list(reversed(inner[1:-1]))
	geo.merge(bm, geo.plate(edge, 0.024, row("blade"), side=row("steel"), sharp=FLAT))
	gem = geo.ellipsoid(0.032, 0.020, 0.032, seg(lod, 7, 5), 3, row("arcane"), sharp=40)
	geo.translate(gem, (0.0, 0.0, top + 0.010))
	geo.merge(bm, gem)
	geo.transform(bm, geo.frame(b.r_fist, b.sword_axis, parts.edge_down(b.sword_axis)))
	return bm
