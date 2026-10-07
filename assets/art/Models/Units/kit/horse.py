"""The horse, and what seats a rider on it. A chibi horse: a round barrel on
short straight legs, a big head, a thick mane and tail, built to fit the
1 m formation slot (about 1 m from muzzle to tail). Its legs stand a little
splayed, front ones forward and hind ones back, like a toy's: FigureBatcher
rocks it into a gallop.

Built in a figure's standing space: the ground at Body.base_height, facing -Y.
"""
import math

from mathutils import Vector

import geo
from geo import SMOOTH
from palette import row
from parts import seg, _limb

## How much shorter in the leg than a real horse's proportions (chibi):
## everything above the legs is built at full height and lowered this much.
DROP = 0.075
## Where the saddle's seat is, above the ground.
SEAT = 0.640 - DROP
BARREL_Z = 0.455 - DROP


def horse(b, lod, coat="coat", coat_dark="coat_dark", mane="mane"):
	g = b.base_height
	bm = geo.new_bm()
	legs = geo.new_bm()
	segs = seg(lod, 12, 8)
	# The barrel, built along local Z and turned to lie along -Y.
	prof = [(0.0, -0.335), (0.075, -0.328), (0.118, -0.300), (0.138, -0.240), (0.143, -0.120), (0.140, 0.0),
			(0.136, 0.120), (0.130, 0.215), (0.106, 0.275), (0.055, 0.300), (0.0, 0.304)]
	if lod > 0:
		prof = [prof[i] for i in (0, 2, 3, 5, 7, 8, 10)]
	barrel = geo.lathe(prof, segs, row(coat), sharp=SMOOTH, sy=1.10)
	geo.rotate(barrel, 90.0, 'X')
	geo.translate(barrel, (0.0, 0.015, g + BARREL_Z + DROP))
	geo.merge(bm, barrel)
	# Legs: front a little forward, hind a little back.
	for x in (-0.078, 0.078):
		for y, lean in ((-0.180, -0.10), (0.205, 0.10)):
			top = Vector((x, y, g + 0.40 - DROP))
			foot = Vector((x * 1.08, y + lean * 0.22, g + 0.035))
			leg = geo.tube([top, top.lerp(foot, 0.55), foot], [0.064, 0.052, 0.046], seg(lod, 7, 5), row(coat),
					sharp=SMOOTH)
			geo.merge(legs, leg)
			hoof = geo.lathe([(0.0, 0.0), (0.044, 0.0), (0.042, 0.022), (0.036, 0.040)], seg(lod, 7, 5),
					row("hoof"), sharp=40, phase=0.0, cap_start=row("hoof"))
			geo.scale(hoof, 1.15, 1.15, 1.0)
			geo.translate(hoof, (foot.x, foot.y, g))
			geo.merge(legs, hoof)
			if lod == 0:
				tuft = geo.lathe([(0.040, 0.040), (0.046, 0.060), (0.034, 0.085)], 7, row(mane), sharp=SMOOTH, phase=0.0)
				geo.scale(tuft, 1.15, 1.15, 1.0)
				geo.translate(tuft, (foot.x, foot.y, g))
				geo.merge(legs, tuft)
	# Neck and head.
	neck_base = Vector((0.0, -0.200, g + 0.540))
	neck_top = Vector((0.0, -0.330, g + 0.760))
	neck = geo.tube([neck_base, neck_base.lerp(neck_top, 0.5) + Vector((0.0, 0.0, 0.01)), neck_top],
			[0.092, 0.078, 0.066], seg(lod, 9, 7), row(coat), sharp=SMOOTH, flatten=0.82, up=(0.0, 1.0, 0.3))
	geo.merge(bm, neck)
	head = geo.box(1.0, 1.0, 1.0, row(coat), SMOOTH)
	head = geo.subdivided(head, seg(lod, 2, 1))
	geo.fit(head, (0.130, 0.250, 0.135))
	for v in head.verts:
		front = max(0.0, -v.co.y / 0.125)
		v.co.x *= 1.0 - 0.22 * front
		v.co.z *= 1.0 - 0.12 * front
	geo.paint(head, row(coat), SMOOTH)
	muzzle = geo.ellipsoid(0.056, 0.060, 0.056, seg(lod, 8, 6), 4, row(coat_dark), sharp=SMOOTH)
	geo.translate(muzzle, (0.0, -0.105, -0.008))
	geo.merge(head, muzzle)
	if lod == 0:
		for side in (-1.0, 1.0):
			nostril = geo.disc(0.010, 0.014, 6, row("mane"), dome=0.001, depth=0.003)
			geo.transform(nostril, geo.frame(Vector((side * 0.026, -0.160, 0.008)), Vector((side * 0.3, -1.0, 0.2)),
					(0.0, 0.0, 1.0)))
			geo.merge(head, nostril)
	for side in (-1.0, 1.0):
		eye = geo.disc(0.016, 0.019, seg(lod, 8, 5), row("eye"), dome=0.004)
		geo.transform(eye, geo.frame(Vector((side * 0.060, 0.015, 0.028)), Vector((side, -0.25, 0.15)), (0.0, 0.0, 1.0)))
		geo.merge(head, eye)
		if lod == 0:
			glint = geo.disc(0.006, 0.006, 5, row("glint"), dome=0.0015, depth=0.0015, simple=True)
			geo.transform(glint, geo.frame(Vector((side * 0.0635, 0.008, 0.036)), Vector((side, -0.25, 0.15)),
					(0.0, 0.0, 1.0)))
			geo.merge(head, glint)
		ear = geo.lathe([(0.020, 0.0), (0.018, 0.03), (0.0, 0.065)], 5, row(coat), sharp=40, phase=0.0, sy=0.6)
		geo.rotate(ear, side * -14.0, 'Y')
		geo.rotate(ear, -18.0, 'X')
		geo.translate(ear, (side * 0.036, 0.078, 0.052))
		geo.merge(head, ear)
	forelock = geo.ellipsoid(0.03, 0.04, 0.02, 6, 3, row(mane), sharp=SMOOTH)
	geo.translate(forelock, (0.0, 0.045, 0.068))
	geo.merge(head, forelock)
	geo.rotate(head, 26.0, 'X')
	geo.translate(head, (0.0, -0.430, g + 0.770))
	geo.merge(bm, head)
	# The mane, in chunky locks down the neck's crest.
	steps = seg(lod, 6, 4)
	for i in range(steps):
		t = i / (steps - 1)
		p = Vector((0.0, -0.350, g + 0.835)).lerp(Vector((0.0, -0.140, g + 0.610)), t)
		lock = geo.ellipsoid(0.026, 0.050, 0.040, 6, 3, row(mane), sharp=SMOOTH)
		geo.rotate(lock, -40.0 + 15.0 * t, 'X')
		geo.translate(lock, p + Vector((0.012 * (1 if i % 2 else -1), 0.0, 0.0)))
		geo.merge(bm, lock)
	# The tail, swept back and down.
	tail_pts = [Vector((0.0, 0.300, g + 0.540)), Vector((0.0, 0.370, g + 0.520)), Vector((0.0, 0.420, g + 0.420)),
			Vector((0.0, 0.430, g + 0.290)), Vector((0.0, 0.415, g + 0.200))]
	geo.merge(bm, geo.tube(tail_pts, [0.030, 0.048, 0.056, 0.046, 0.0], seg(lod, 7, 5), row(mane), sharp=SMOOTH,
			flatten=0.7, up=(1.0, 0.0, 0.0)))
	geo.translate(bm, (0.0, 0.0, -DROP))
	geo.merge(bm, legs)
	return bm


def tack(b, lod, cloth="team_cloth"):
	"""Saddle, saddle cloth in the team's colour, girth and bridle."""
	g = b.base_height
	bm = geo.new_bm()
	cloth_band = geo.lathe([(0.147, -0.125), (0.150, -0.110), (0.150, 0.130), (0.147, 0.145)], seg(lod, 16, 10),
			row(cloth), sharp=50, sy=1.10)
	geo.rotate(cloth_band, 90.0, 'X')
	geo.translate(cloth_band, (0.0, 0.015, g + BARREL_Z))
	geo.delete_faces(cloth_band, lambda f: f.calc_center_median().z < g + BARREL_Z + 0.02)
	geo.merge(bm, cloth_band)
	girth = geo.lathe([(0.146, -0.020), (0.150, -0.012), (0.150, 0.012), (0.146, 0.020)], seg(lod, 12, 8),
			row("leather_dark"), sharp=40, sy=1.10)
	geo.rotate(girth, 90.0, 'X')
	geo.translate(girth, (0.0, 0.015, g + BARREL_Z))
	geo.merge(bm, girth)
	seat = geo.ellipsoid(0.105, 0.130, 0.040, seg(lod, 10, 7), 4, row("leather"), sharp=SMOOTH, squash_bottom=0.4)
	for v in seat.verts:
		v.co.z += 0.045 * (v.co.y / 0.13) ** 2 if v.co.z > 0.0 else 0.0
	geo.translate(seat, (0.0, 0.010, g + SEAT - 0.028))
	geo.merge(bm, seat)
	if lod == 0:
		# Bridle: a noseband and a cheek strap each side.
		for side in (-1.0, 1.0):
			pts = [Vector((side * 0.060, -0.395, g + 0.840 - DROP)), Vector((side * 0.066, -0.455, g + 0.770 - DROP)),
					Vector((side * 0.052, -0.505, g + 0.700 - DROP))]
			geo.merge(bm, geo.ribbon(pts, [Vector((side, 0.0, 0.1))] * 3, 0.013, 0.004, row("leather_dark"), sharp=40,
					embed=0.004))
		nose = geo.lathe([(0.062, -0.012), (0.066, 0.0), (0.062, 0.012)], 8, row("leather_dark"), sharp=40,
				phase=0.0, sx=0.85, sy=1.0)
		geo.transform(nose, geo.frame(Vector((0.0, -0.510, g + 0.715 - DROP)), Vector((0.0, -0.45, -1.0)), (0.0, 1.0, 0.0)))
		geo.merge(bm, nose)
	return bm


def reins(b, lod):
	"""Reins from the bit to the rider's left fist."""
	g = b.base_height
	bm = geo.new_bm()
	fist = b.l_fist
	for side in (-1.0, 1.0):
		bit = Vector((side * 0.050, -0.515, g + 0.700 - DROP))
		mid = bit.lerp(fist, 0.5) + Vector((0.0, 0.0, -0.04))
		geo.merge(bm, geo.tube([bit, mid, fist], [0.0045] * 3, 3, row("leather_dark"), sharp=40))
	return bm


def caparison(b, lod, cloth="team_cloth", border="team_cloth_dark"):
	"""A knight's caparison in the team's colour, hung over the horse to its
	knees, a darker border and a cream cross on each flank."""
	g = b.base_height
	sections = [
		((0.0, 0.020, g + 0.235), 0.178, 0.360),
		((0.0, 0.020, g + 0.265), 0.180, 0.362),
		((0.0, 0.020, g + 0.420), 0.172, 0.350),
		((0.0, 0.020, g + 0.560), 0.150, 0.315),
		((0.0, 0.020, g + 0.615), 0.100, 0.240),
	]
	bands = [row(border), row(cloth), row(cloth), row(cloth)]
	bm = geo.loft(sections, seg(lod, 16, 10), sharp=SMOOTH, ring_swatches=bands, cap_end=row(cloth))
	if lod == 0:
		tree = geo.bvh(bm)
		for side in (-1.0, 1.0):
			loc, nrm = geo.project(tree, (side * 0.6, 0.02, g + 0.42), (-side, 0.0, 0.0))
			if loc is None:
				continue
			for outline in ([(-0.018, -0.07), (0.018, -0.07), (0.018, 0.07), (-0.018, 0.07)],
					[(-0.06, -0.018), (0.06, -0.018), (0.06, 0.018), (-0.06, 0.018)]):
				cross = geo.plate(outline, 0.006, row("cream"), sharp=40)
				geo.transform(cross, geo.orient(loc + nrm * 0.001, nrm))
				geo.merge(bm, cross)
	return bm


def chanfron(b, lod):
	"""A steel face plate down the horse's forehead."""
	g = b.base_height
	plate = geo.plate([(-0.045, 0.0), (0.045, 0.0), (0.040, -0.10), (0.022, -0.17), (-0.022, -0.17), (-0.040, -0.10)],
			0.010, row("steel"), sharp=40, bend=6.0)
	geo.rotate(plate, -90.0 + 26.0, 'X')
	geo.translate(plate, (0.0, -0.382, g + 0.845 - DROP))
	return plate


def rider_legs(b, lod):
	"""A rider's legs astride: thighs down the horse's sides, boots in steel
	stirrups."""
	g = b.base_height
	bm = geo.new_bm()
	segs = seg(lod, 7, 5)
	for side in (-1.0, 1.0):
		hip = Vector((side * 0.085, 0.010, g + SEAT + 0.035))
		knee = Vector((side * 0.170, -0.075, g + SEAT - 0.070))
		ankle = Vector((side * 0.180, -0.020, g + SEAT - 0.200))
		geo.merge(bm, _limb(hip, knee, [(0.052, -0.02), (0.056, 0.01), (0.048, (knee - hip).length + 0.02)], segs,
				row("cloth_dark")))
		geo.merge(bm, _limb(knee, ankle, [(0.046, -0.02), (0.044, 0.02), (0.050, (ankle - knee).length - 0.02),
				(0.044, (ankle - knee).length + 0.02)], segs, row("boot"), sharp=48))
		toe = geo.ellipsoid(0.040, 0.070, 0.032, segs, 4, row("boot"), sharp=48, squash_bottom=0.5)
		geo.translate(toe, ankle + Vector((0.0, -0.035, -0.030)))
		geo.merge(bm, toe)
		stirrup = geo.tube([ankle + Vector((0.0, 0.03, 0.08)), ankle + Vector((0.0, 0.005, -0.055)),
				ankle + Vector((0.0, -0.05, -0.055))], [0.006] * 3, 4, row("steel"), sharp=40)
		geo.merge(bm, stirrup)
	return bm
