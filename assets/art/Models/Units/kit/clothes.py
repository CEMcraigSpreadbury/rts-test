"""Clothes beyond the Soldier's gambeson: robes and their wide sleeves, capes,
a plain collar, trim. Undyed by default (the team colour is for headgear,
shields, hems and the cloth a recipe picks it for).
"""
import math

from mathutils import Vector

import geo
from geo import SMOOTH
from palette import row
from parts import seg, _limb


def robe(b, lod, cloth="cloth", hem="team_dark"):
	"""A long robe from the shoulders to the ground, flaring at the foot,
	its hem in the team's colour, a rope belt at the waist."""
	g, w, s, n = b.base_height, b.waist_z, b.shoulder_z, b.neck_z
	prof = [(0.186, g + 0.004), (0.194, g + 0.018), (0.190, g + 0.046), (0.178, g + 0.080), (0.160, g + 0.170),
			(0.146, w), (0.152, w + 0.060), (0.152, w + 0.110), (0.142, s - 0.012), (0.120, s + 0.022), (0.076, n),
			(0.0, n + 0.004)]
	bands = [row(hem), row(hem), row(hem)] + [row(cloth)] * (len(prof) - 4)
	if lod > 0:
		keep = (0, 2, 3, 5, 7, 8, 9, 10, 11)
		prof = [prof[i] for i in keep]
		bands = [row(hem), row(hem)] + [row(cloth)] * (len(prof) - 3)
	bm = geo.lathe(prof, seg(lod, 14, 9), sharp=SMOOTH, sy=0.86, ring_swatches=bands, cap_start=row("lining"))
	r = 0.150
	belt = geo.lathe([(r - 0.004, w - 0.012), (r + 0.010, w - 0.008), (r + 0.010, w + 0.008), (r - 0.004, w + 0.012)],
			seg(lod, 12, 8), row("string"), sharp=SMOOTH, sy=0.86)
	geo.merge(bm, belt)
	if lod == 0:
		knot = geo.tube([Vector((0.06, -0.140, w)), Vector((0.07, -0.150, w - 0.06)), Vector((0.06, -0.152, w - 0.12))],
				[0.010, 0.009, 0.006], 4, row("string"), sharp=SMOOTH)
		geo.merge(bm, knot)
	return bm


def robe_trim(b, lod, swatch="robe_trim"):
	"""Gold bands round a robe's foot and down its front."""
	g, n = b.base_height, b.neck_z
	bm = geo.lathe([(0.193, g + 0.050), (0.197, g + 0.056), (0.193, g + 0.074), (0.186, g + 0.080)],
			seg(lod, 14, 9), row(swatch), sharp=40, sy=0.86)
	if lod == 0:
		pts = [Vector((0.0, -0.172, g + 0.06)), Vector((0.0, -0.150, b.waist_z - 0.02)),
				Vector((0.0, -0.128, b.shoulder_z)), Vector((0.0, -0.075, n - 0.01))]
		nrms = [Vector((0.0, -1.0, -0.05)), Vector((0.0, -1.0, 0.0)), Vector((0.0, -1.0, 0.3)), Vector((0.0, -0.7, 0.7))]
		geo.merge(bm, geo.ribbon(pts, nrms, 0.034, 0.004, row(swatch), sharp=40, embed=0.003))
	return bm


def wide_sleeves(b, lod, cloth="cloth"):
	"""Robe sleeves: a plain upper arm, a bell sleeve flaring to the wrist,
	a bare hand."""
	bm = geo.new_bm()
	segs = seg(lod, 7, 5)
	for shoulder, elbow, wrist, fist in ((b.r_shoulder, b.r_elbow, b.r_wrist, b.r_fist),
			(b.l_shoulder, b.l_elbow, b.l_wrist, b.l_fist)):
		upper = (elbow - shoulder).length
		geo.merge(bm, _limb(shoulder, elbow, [(0.050, -0.01), (0.055, 0.006), (0.050, upper), (0.0, upper + 0.03)],
				segs, row(cloth)))
		lower = (wrist - elbow).length
		geo.merge(bm, _limb(elbow, wrist, [(0.046, -0.02), (0.050, 0.02), (0.066, lower - 0.006), (0.060, lower + 0.004),
				(0.030, lower - 0.004)], segs, row(cloth), sharp=50))
		hand = geo.box(1.0, 1.0, 1.0, row("skin"), SMOOTH)
		if lod == 0:
			hand = geo.subdivided(hand, 1)
		geo.fit(hand, (0.058, 0.062, 0.064))
		geo.paint(hand, row("skin"), SMOOTH)
		geo.merge(bm, hand, geo.frame(fist, wrist - elbow, (0.0, 0.0, 1.0)))
	return bm


def cape(b, lod, outside="team_cloth", lining="team_cloth_dark", collar="ermine"):
	"""A long cape from the shoulders to the ankles, in the team's colour,
	lined, under a fur collar."""
	g, s, n = b.base_height, b.shoulder_z, b.neck_z
	prof = [(0.250, g + 0.060), (0.232, g + 0.180), (0.205, b.waist_z), (0.180, s - 0.050), (0.160, s + 0.010),
			(0.112, n + 0.004)]
	shell = geo.lathe(prof, seg(lod, 16, 10), row(outside), sharp=SMOOTH, sy=0.82)
	for v in shell.verts:
		# Hung back from the shoulders, falling clear of the legs.
		low = max(0.0, (s - v.co.z) / (s - g))
		v.co.y += 0.05 + 0.07 * low
	geo.delete_faces(shell, lambda f: f.calc_center_median().y < 0.035 + 0.02 * max(0.0, (s - f.calc_center_median().z)))
	bm = geo.new_bm()
	geo.merge(bm, shell)
	geo.merge(bm, geo.flipped(shell, row(lining), inset=0.006))
	if collar:
		fur = geo.lathe([(0.118, n - 0.042), (0.160, n - 0.030), (0.164, n - 0.005), (0.120, n + 0.020), (0.090, n + 0.018)],
				seg(lod, 12, 9), row(collar), sharp=SMOOTH, sy=0.9)
		geo.merge(bm, fur)
	return bm


def cloth_collar(b, lod, swatch="cloth"):
	"""A plain turned-down collar at the neck, for unarmoured figures."""
	n = b.neck_z
	return geo.lathe([(0.118, n - 0.028), (0.110, n - 0.006), (0.092, n + 0.012), (0.082, n + 0.022)], seg(lod, 10, 7),
			row(swatch), sharp=SMOOTH, sy=0.9)


def surcoat_trim(b, lod):
	"""Gold trim at the hem and the neck of a tunic (the Lord's)."""
	h = b.hem_z
	bm = geo.lathe([(0.169, h + 0.034), (0.172, h + 0.040), (0.168, h + 0.054), (0.162, h + 0.058)], seg(lod, 12, 8),
			row("robe_trim"), sharp=40, sy=b.torso_depth)
	return bm


def tabard(b, lod, back=True, half_width=0.082):
	"""A tabard in the team's colour over the undyed tunic: a yoke on the
	shoulders, a panel down the front (and back) to below the skirt, open at
	the sides, under the belt line, its hem darker. back=False: an apron."""
	h, w, s, n = b.hem_z, b.waist_z, b.shoulder_z, b.neck_z
	prof = [(0.186, h - 0.014), (0.183, h + 0.020), (0.182, h + 0.046), (0.160, w - 0.050), (0.146, w - 0.006),
			(0.146, w + 0.006), (0.157, w + 0.055), (0.160, w + 0.105), (0.151, s - 0.012), (0.127, s + 0.022),
			(0.100, n - 0.020)]
	bands = [row("team_cloth_dark")] + [row("team_cloth")] * (len(prof) - 2)
	shell = geo.lathe(prof, seg(lod, 24, 16), sharp=SMOOTH, sy=b.torso_depth, ring_swatches=bands)

	def cut(f):
		m = f.calc_center_median()
		if m.z > s - 0.030:
			return not back and m.y > 0.0 and m.z < s + 0.010
		return abs(m.x) > half_width or (not back and m.y > 0.0)

	geo.delete_faces(shell, cut)
	bm = geo.new_bm()
	geo.merge(bm, shell)
	geo.merge(bm, geo.flipped(shell, row("team_cloth_dark"), inset=0.004))
	return bm
