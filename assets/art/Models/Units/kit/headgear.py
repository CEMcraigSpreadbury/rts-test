"""Headgear, hair and beards beyond the Soldier's kettle helmet. Each is built
on the upright head (the recipe tips it back with the rest of the head, see
parts.Body.head_matrix). Painted headgear wears the team rows: helmets
team_paint, cloth team_cloth.
"""
import math

from mathutils import Vector

import geo
from geo import FLAT, SMOOTH
from palette import row
from parts import seg


def _over_head(b, bm):
	geo.translate(bm, (b.head_centre.x, b.head_centre.y + 0.004, 0.0))
	return bm


def _brow_band(b, lod, z, sy, segs):
	return geo.lathe([(0.176, z - 0.034), (0.178, z - 0.010), (0.170, z - 0.002)], segs, row("steel"), sharp=40,
			sy=sy)


def _crest_ridge(b, dome, z, sy, lod, steps, width=0.022):
	"""A steel ridge over the crown, front to back."""
	tree = geo.bvh(dome)
	centre = Vector((0.0, 0.0, z + 0.02))
	pts, nrms = [], []
	for i in range(steps):
		a = math.pi * i / (steps - 1)
		out = Vector((0.0, -math.cos(a) * sy, math.sin(a)))
		loc, nrm = geo.project(tree, centre + out * 0.6, -out)
		if loc is None or loc.z < z + 0.005:
			continue
		pts.append(loc)
		nrms.append(nrm)
	if len(pts) < 2:
		return geo.new_bm()
	return geo.ribbon(pts, nrms, width, 0.0070, row("trim"), sharp=40, embed=0.003)


def conical_helm(b, lod):
	"""A tall pointed helm painted in the team's colour, faceted like beaten
	plates, on a riveted steel band with a ridge to its point."""
	z = b.brow_z - 0.02
	sy = 0.95
	segs = seg(lod, 10, 8)
	prof = [(0.172, z - 0.012), (0.176, z + 0.030), (0.164, z + 0.090), (0.128, z + 0.165), (0.072, z + 0.235),
			(0.0, z + 0.285)]
	dome = geo.lathe(prof, segs, row("team_paint"), sharp=34, sy=sy, cap_start=row("lining"))
	bm = geo.new_bm()
	geo.merge(bm, dome)
	geo.merge(bm, _brow_band(b, lod, z + 0.024, sy, segs))
	geo.merge(bm, _crest_ridge(b, dome, z, sy, lod, seg(lod, 13, 7)))
	if lod == 0:
		for k in range(8):
			theta = -math.pi / 2.0 + k * math.pi / 4.0
			rivet = geo.ellipsoid(0.0068, 0.0068, 0.0068, 4, 2, row("brass"), sharp=40)
			geo.translate(rivet, (math.cos(theta) * 0.179, math.sin(theta) * 0.179 * sy, z + 0.012))
			geo.merge(bm, rivet)
	return _over_head(b, bm)


def round_helm(b, lod, cheek_guards=False):
	"""A rounded helm (a spangenhelm) painted in the team's colour on a steel
	band, a steel ridge over it; leather cheek guards if wanted."""
	z = b.brow_z
	sy = 0.95
	segs = seg(lod, 12, 9)
	prof = [(0.172, z - 0.036), (0.177, z + 0.015), (0.169, z + 0.068), (0.143, z + 0.118), (0.098, z + 0.150),
			(0.0, z + 0.164)]
	if lod > 0:
		prof = [prof[i] for i in (0, 1, 3, 5)]
	dome = geo.lathe(prof, segs, row("team_paint"), sharp=50, sy=sy, cap_start=row("lining"))
	bm = geo.new_bm()
	geo.merge(bm, dome)
	geo.merge(bm, _brow_band(b, lod, z, sy, segs))
	geo.merge(bm, _crest_ridge(b, dome, z, sy, lod, seg(lod, 13, 7)))
	knob = geo.ellipsoid(0.016, 0.016, 0.014, seg(lod, 6, 5), 3, row("brass"), sharp=40)
	geo.translate(knob, (0.0, 0.0, z + 0.168))
	geo.merge(bm, knob)
	if cheek_guards:
		for side in (-1.0, 1.0):
			guard = geo.box(0.016, 0.075, 0.10, row("leather"), 40, bevel=0.006 if lod == 0 else 0.0)
			for v in guard.verts:
				if v.co.z < 0.0:
					v.co.y *= 0.7
			geo.rotate(guard, side * -8.0, 'Y')
			geo.translate(guard, (side * 0.168, 0.005, z - 0.075))
			geo.merge(bm, guard)
	return _over_head(b, bm)


def plume(b, lod, top_z, lean=1.0, height=0.20):
	"""A tall feather plume in the team's colour rising from a helmet's crown
	and curving back, in a brass holder."""
	bm = geo.new_bm()
	holder = geo.lathe([(0.012, top_z - 0.01), (0.016, top_z + 0.02), (0.011, top_z + 0.035)], seg(lod, 6, 5),
			row("brass"), sharp=40, phase=0.0)
	geo.merge(bm, holder)
	steps = seg(lod, 8, 5)
	for feather, (dx, scale) in enumerate(((0.0, 1.0), (-0.016, 0.82), (0.016, 0.82))):
		if lod > 0 and feather > 0:
			break
		pts, radii = [], []
		for i in range(steps):
			t = i / (steps - 1)
			pts.append(Vector((dx * t, 0.02 + lean * 0.16 * t * t * scale, top_z + 0.02 + height * scale * math.sin(t * 1.35))))
			radii.append((0.012 + 0.034 * math.sin(math.pi * min(1.0, t * 1.05))) * scale)
		radii[-1] = 0.0
		geo.merge(bm, geo.tube(pts, radii, seg(lod, 6, 4), row("team_cloth"), sharp=SMOOTH, flatten=0.42,
				up=(1.0, 0.0, 0.0)))
	return _over_head(b, bm)


def hood(b, lod, row_name="team_cloth", lining="team_cloth_dark"):
	"""A cloth hood drawn up round the face, its tip falling back, over a
	short capelet on the shoulders; lined inside."""
	c = b.head_centre
	shell = geo.ellipsoid(0.192, 0.180, 0.192, seg(lod, 12, 9), seg(lod, 8, 6), row(row_name), sharp=SMOOTH)
	for v in shell.verts:
		up = max(0.0, v.co.z / 0.192)
		back = max(0.0, v.co.y / 0.180)
		v.co.y += 0.075 * up * up * (0.4 + back)
		v.co.z += 0.03 * up * up * back
	geo.translate(shell, (c.x, c.y + 0.012, c.z + 0.016))

	# The opening frames the face as the Soldier's helmet does: its top on
	# the helmet brim's line, wide enough to show the hair over the ears.
	def opening(f):
		m = f.calc_center_median()
		return (m.y < c.y - 0.04 and abs(m.x - c.x) < 0.168 and c.z - 0.135 < m.z < b.brow_z - 0.012) \
				or m.z < c.z - 0.150

	geo.delete_faces(shell, opening)
	bm = geo.new_bm()
	geo.merge(bm, shell)
	geo.merge(bm, geo.flipped(shell, row(lining), inset=0.007))
	n = b.neck_z
	s = b.shoulder_z
	cape = geo.lathe([(0.196, s - 0.080), (0.198, s - 0.050), (0.180, s + 0.000), (0.138, n - 0.010), (0.104, n + 0.030)],
			seg(lod, 12, 9), row(row_name), sharp=50, sy=0.84, cap_start=row(lining))
	if lod == 0:
		# A dagged hem: points round the capelet's edge.
		for k in range(10):
			theta = -math.pi / 2.0 + (k + 0.5) * 2.0 * math.pi / 10.0
			out = Vector((math.cos(theta) * 0.196, math.sin(theta) * 0.196 * 0.84, s - 0.078))
			dag = geo.plate([(-0.032, 0.0), (0.032, 0.0), (0.0, -0.040)], 0.006, row(row_name), sharp=50)
			flat = Vector((out.x, out.y, 0.0)).normalized()
			geo.transform(dag, geo.orient(out + flat * 0.002, flat, (0.0, 0.0, 1.0)))
			geo.merge(cape, dag)
	geo.merge(bm, cape)
	return bm


def wizard_hat(b, lod):
	"""A wide-brimmed pointed hat in the team's colour, its tip bent back, a
	cream band round its crown."""
	z = b.brow_z - 0.02
	bm = geo.new_bm()

	def droop(theta, r, zz):
		return (r * math.cos(theta), r * math.sin(theta) * 0.96, zz - 0.18 * max(0.0, r - 0.16) ** 1.2)

	brim = geo.lathe([(0.150, z - 0.004), (0.250, z - 0.016), (0.256, z - 0.006), (0.150, z + 0.012)],
			seg(lod, 16, 11), row("team_cloth"), sharp=40, warp=droop)
	geo.merge(bm, brim)
	steps = seg(lod, 9, 5)
	pts, radii = [], []
	for i in range(steps):
		t = i / (steps - 1)
		bend = max(0.0, t - 0.45) / 0.55
		pts.append(Vector((0.0, 0.10 * bend * bend, z + 0.30 * t - 0.04 * bend * bend)))
		radii.append(0.158 * (1.0 - t) ** 1.15 + 0.004)
	radii[-1] = 0.0
	cone = geo.tube(pts, radii, seg(lod, 12, 9), row("team_cloth"), sharp=50, cap_start=row("lining"))
	geo.merge(bm, cone)
	band = geo.lathe([(0.158, z + 0.002), (0.162, z + 0.012), (0.156, z + 0.034), (0.150, z + 0.040)],
			seg(lod, 12, 9), row("cream"), sharp=40)
	geo.merge(bm, band)
	if lod == 0:
		star = geo.plate([(0.0, 0.022), (0.006, 0.006), (0.022, 0.0), (0.006, -0.006), (0.0, -0.022),
				(-0.006, -0.006), (-0.022, 0.0), (-0.006, 0.006)], 0.005, row("robe_trim"), sharp=40)
		geo.translate(star, (0.0, -0.118, z + 0.10))
		geo.rotate(star, 0.0, 'Z')
		geo.merge(bm, star)
	return _over_head(b, bm)


def crown(b, lod):
	"""A gold crown of five points, red gems at the front, over the hair."""
	z = b.brow_z - 0.03
	sy = 0.95
	segs = seg(lod, 15, 10)
	bm = geo.lathe([(0.168, z - 0.006), (0.172, z + 0.004), (0.172, z + 0.045), (0.166, z + 0.052)], segs,
			row("brass"), sharp=40, sy=sy)
	for k in range(5):
		theta = -math.pi / 2.0 + k * 2.0 * math.pi / 5.0
		point = geo.plate([(-0.030, 0.0), (0.030, 0.0), (0.012, 0.045), (0.0, 0.075), (-0.012, 0.045)], 0.012,
				row("brass"), sharp=40)
		ball = geo.ellipsoid(0.011, 0.011, 0.011, 5, 3, row("brass"), sharp=40)
		geo.translate(ball, (0.0, 0.0, 0.082))
		geo.merge(point, ball)
		out = Vector((math.cos(theta), math.sin(theta) * sy, 0.0))
		geo.transform(point, geo.orient(Vector((0.0, 0.0, z + 0.046)) + out * 0.168, out))
		geo.merge(bm, point)
		if lod == 0:
			gem = geo.disc(0.012, 0.012, 6, row("gem"), dome=0.005, depth=0.002)
			geo.transform(gem, geo.frame(Vector((0.0, 0.0, z + 0.024)) + out * 0.173, out, (0.0, 0.0, 1.0)))
			geo.merge(bm, gem)
	return _over_head(b, bm)


def hair_cap(b, lod, row_name="hair"):
	"""The top of the head's hair, for headgear that leaves it showing."""
	z = b.brow_z
	cap = geo.lathe([(0.168, z - 0.050), (0.171, z - 0.005), (0.158, z + 0.040), (0.118, z + 0.082), (0.0, z + 0.102)],
			seg(lod, 12, 9), row(row_name), sharp=SMOOTH, sy=0.94)
	if lod == 0:
		# A few locks falling over the brow.
		for x, drop in ((-0.07, 0.035), (-0.02, 0.05), (0.04, 0.04), (0.09, 0.03)):
			lock = geo.ellipsoid(0.034, 0.02, drop, 5, 3, row(row_name), sharp=SMOOTH)
			geo.translate(lock, (x, -0.148, z - 0.012))
			geo.merge(cap, lock)
	return _over_head(b, cap)


def cloth_cap(b, lod, cloth="hood", roll_row="leather_dark"):
	"""A soft undyed cloth cap with a rolled brim, its crown
	slumped a little to one side. The roll sits on the Soldier's helmet brim
	line, so the face shows exactly as his does."""
	z = b.brow_z + 0.016

	def slump(theta, r, zz):
		top = max(0.0, (zz - z) / 0.12)
		return (r * math.cos(theta) + 0.03 * top * top, r * math.sin(theta) * 0.95 + 0.012 * top, zz)

	bm = geo.lathe([(0.176, z - 0.024), (0.184, z + 0.025), (0.172, z + 0.070), (0.126, z + 0.110), (0.0, z + 0.124)],
			seg(lod, 12, 9), row(cloth), sharp=SMOOTH, warp=slump, cap_start=row("lining"))
	roll = geo.lathe([(0.174, z - 0.040), (0.190, z - 0.032), (0.192, z - 0.008), (0.176, z + 0.000)],
			seg(lod, 12, 9), row(roll_row), sharp=50, sy=0.95)
	geo.merge(bm, roll)
	return _over_head(b, bm)


def beard(b, lod, long=True, row_name="beard"):
	"""A full beard from the cheeks (long: down over the chest) and a
	moustache over where the mouth would be."""
	c = b.head_centre
	if long:
		bm = geo.ellipsoid(0.120, 0.070, 0.135, seg(lod, 10, 7), seg(lod, 6, 4), row(row_name), sharp=SMOOTH)
		for v in bm.verts:
			low = max(0.0, -v.co.z / 0.135)
			v.co.x *= 1.0 - 0.55 * low * low
			v.co.y -= 0.03 * low
		geo.translate(bm, (c.x, c.y - 0.112, c.z - 0.170))
	else:
		bm = geo.ellipsoid(0.125, 0.060, 0.070, seg(lod, 10, 7), seg(lod, 5, 4), row(row_name), sharp=SMOOTH)
		for v in bm.verts:
			low = max(0.0, -v.co.z / 0.07)
			v.co.x *= 1.0 - 0.35 * low
		geo.translate(bm, (c.x, c.y - 0.112, c.z - 0.112))
	for side in (-1.0, 1.0):
		tache = geo.ellipsoid(0.034, 0.018, 0.013, 6, 3, row(row_name), sharp=SMOOTH)
		geo.rotate(tache, side * -18.0, 'Y')
		geo.translate(tache, (c.x + side * 0.024, c.y - 0.140, c.z - 0.056))
		geo.merge(bm, tache)
	return bm


# --- plain steel helmets, one silhouette per unit type ---------------------
# Drawn chibi-large (big brims and crests) so the shape reads from above.

def _rivets(bm, lod, r, z, sy, count=8):
	if lod > 0:
		return
	for k in range(count):
		theta = -math.pi / 2.0 + k * 2.0 * math.pi / count
		rivet = geo.ellipsoid(0.0068, 0.0068, 0.0068, 4, 2, row("brass"), sharp=40)
		geo.translate(rivet, (math.cos(theta) * r, math.sin(theta) * r * sy, z))
		geo.merge(bm, rivet)


def morion(b, lod):
	"""A morion: a round steel crown under a tall half-moon comb, front to
	back, and a boat-shaped brim curling up to points fore and aft."""
	z = b.brow_z
	sy = 0.95
	segs = seg(lod, 16, 10)
	prof = [(0.170, z - 0.004), (0.174, z + 0.040), (0.160, z + 0.092), (0.122, z + 0.136), (0.062, z + 0.160),
			(0.0, z + 0.166)]
	if lod > 0:
		prof = [prof[i] for i in (0, 1, 3, 5)]
	bm = geo.new_bm()
	geo.merge(bm, geo.lathe(prof, segs, row("steel"), sharp=50, sy=sy, cap_start=row("lining")))

	def boat(theta, r, zz):
		fore_aft = abs(math.sin(theta))
		side = abs(math.cos(theta))
		out = max(0.0, r - 0.170) / 0.085
		r = 0.170 + (r - 0.170) * (0.55 + 0.80 * fore_aft ** 2)
		zz += 0.105 * out * fore_aft ** 4 - 0.014 * out * side
		return (r * math.cos(theta), r * math.sin(theta) * sy, zz)

	brim = geo.lathe([(0.168, z - 0.010), (0.255, z - 0.018), (0.255, z - 0.008), (0.168, z + 0.008)], segs,
			sharp=40, warp=boat, ring_swatches=[row("steel"), row("trim"), row("steel")])
	geo.merge(bm, brim)
	steps = seg(lod, 13, 7)
	outline = []
	for i in range(steps):
		a = math.pi * i / (steps - 1)
		outline.append((math.cos(a) * 0.150, z + 0.050 + math.sin(a) * 0.215))
	comb = geo.plate(outline, 0.018, row("steel"), side=row("trim"), sharp=40)
	geo.rotate(comb, 90.0, 'Z')
	geo.merge(bm, comb)
	_rivets(bm, lod, 0.176, z + 0.014, sy)
	return _over_head(b, bm)


def nasal_helm(b, lod):
	"""A nasal helm: a tall pointed steel cone of beaten facets on a dark
	riveted band, a broad nasal bar down over the nose."""
	z = b.brow_z - 0.010
	sy = 0.95
	segs = seg(lod, 8, 8)
	prof = [(0.172, z - 0.022), (0.177, z + 0.024), (0.163, z + 0.090), (0.120, z + 0.170), (0.060, z + 0.240),
			(0.0, z + 0.290)]
	dome = geo.lathe(prof, segs, row("steel"), sharp=34, sy=sy, cap_start=row("lining"))
	bm = geo.new_bm()
	geo.merge(bm, dome)
	band = geo.lathe([(0.180, z - 0.026), (0.182, z - 0.002), (0.176, z + 0.006)], seg(lod, 16, 8), row("trim"),
			sharp=40, sy=sy)
	geo.merge(bm, band)
	geo.merge(bm, _crest_ridge(b, dome, z, sy, lod, seg(lod, 13, 7)))
	_rivets(bm, lod, 0.183, z - 0.014, sy)
	nasal = geo.plate([(-0.022, 0.012), (0.022, 0.012), (0.017, -0.080), (0.0, -0.094), (-0.017, -0.080)], 0.012,
			row("steel"), side=row("trim"), sharp=40)
	geo.rotate(nasal, 11.0, 'X')
	geo.translate(nasal, (0.0, -0.172, z - 0.012))
	geo.merge(bm, nasal)
	return _over_head(b, bm)


def sallet(b, lod):
	"""An open sallet: a rounded steel bowl over a ridge, its rim a small lip
	at the brow that sweeps down and out behind into a long flared tail."""
	z = b.brow_z
	sy = 0.95
	segs = seg(lod, 16, 10)
	prof = [(0.240, z - 0.150), (0.212, z - 0.090), (0.186, z - 0.030), (0.176, z + 0.010), (0.174, z + 0.044),
			(0.158, z + 0.098), (0.116, z + 0.142), (0.058, z + 0.162), (0.0, z + 0.168)]
	if lod > 0:
		prof = [prof[i] for i in (0, 1, 3, 4, 6, 8)]

	def tail(theta, r, zz):
		back = min(1.0, max(0.0, (math.sin(theta) + 0.35) / 1.35)) ** 1.6
		if zz < z + 0.010:
			depth = z + 0.010 - zz
			zz = z + 0.010 - depth * (0.10 + 0.90 * back)
			r = 0.176 + (r - 0.176) * (0.30 + 0.70 * back)
		return (r * math.cos(theta), r * math.sin(theta) * sy, zz)

	bands = [row("trim")] + [row("steel")] * (len(prof) - 2)
	shell = geo.lathe(prof, segs, sharp=50, warp=tail, ring_swatches=bands)
	bm = geo.new_bm()
	geo.merge(bm, shell)
	geo.merge(bm, geo.flipped(shell, row("lining"), inset=0.006))
	geo.merge(bm, _crest_ridge(b, shell, z + 0.02, sy, lod, seg(lod, 13, 7), width=0.026))
	_rivets(bm, lod, 0.178, z + 0.022, sy)
	return _over_head(b, bm)


def barbute(b, lod):
	"""A barbute, chibi-sized: a tall egg-shaped steel bowl rising to a
	ridged peak, falling low round the sides and back like a bell, and cut
	away in a wide T at the face so the face shows."""
	z = b.brow_z
	sy = 0.97
	segs = seg(lod, 16, 10)
	prof = [(0.192, z - 0.150), (0.190, z - 0.080), (0.184, z - 0.010), (0.182, z + 0.050), (0.164, z + 0.120),
			(0.118, z + 0.196), (0.056, z + 0.246), (0.0, z + 0.262)]
	if lod > 0:
		prof = [prof[i] for i in (0, 2, 4, 5, 7)]
	def bell(theta, r, zz):
		# Full depth behind, half down the cheeks at the sides (the side
		# hair shows below), cut up to the brow over the face.
		d = ((math.sin(theta) + 1.0) * 0.5) ** 1.4
		if zz < z + 0.006:
			zz = z + 0.006 - (z + 0.006 - zz) * d
			r = 0.180 + (r - 0.180) * d
		return (r * math.cos(theta), r * math.sin(theta) * sy, zz)

	bands = [row("trim")] + [row("steel")] * (len(prof) - 2)
	shell = geo.lathe(prof, segs, sharp=50, warp=bell, ring_swatches=bands)
	bm = geo.new_bm()
	geo.merge(bm, shell)
	geo.merge(bm, geo.flipped(shell, row("lining"), inset=0.006))
	geo.merge(bm, _crest_ridge(b, shell, z + 0.03, sy, lod, seg(lod, 13, 7), width=0.024))
	_rivets(bm, lod, 0.186, z + 0.020, sy)
	return _over_head(b, bm)


def burgonet(b, lod):
	"""A burgonet, chibi-sized: a round steel skull under a tall rolled comb,
	a peak jutting out over the brow, hinged cheek plates down the sides and a
	flared neck guard behind."""
	z = b.brow_z
	sy = 0.95
	segs = seg(lod, 16, 10)
	prof = [(0.172, z - 0.004), (0.176, z + 0.040), (0.162, z + 0.094), (0.124, z + 0.140), (0.064, z + 0.164),
			(0.0, z + 0.170)]
	if lod > 0:
		prof = [prof[i] for i in (0, 1, 3, 5)]
	bm = geo.new_bm()
	geo.merge(bm, geo.lathe(prof, segs, row("steel"), sharp=50, sy=sy, cap_start=row("lining")))

	def peak(theta, r, zz):
		front = max(0.0, -math.sin(theta))
		back = max(0.0, math.sin(theta))
		out = max(0.0, r - 0.170) / 0.110
		r = 0.170 + (r - 0.170) * (0.10 + 0.85 * front ** 3 + 0.75 * back ** 2)
		zz += 0.040 * out * front ** 3 - 0.070 * out * back ** 2
		return (r * math.cos(theta), r * math.sin(theta) * sy, zz)

	brim = geo.lathe([(0.168, z - 0.010), (0.280, z - 0.006), (0.280, z + 0.004), (0.168, z + 0.010)], segs,
			sharp=40, warp=peak, ring_swatches=[row("steel"), row("trim"), row("steel")])
	geo.merge(bm, brim)
	steps = seg(lod, 13, 7)
	outline = []
	for i in range(steps):
		a = math.pi * i / (steps - 1)
		outline.append((math.cos(a) * 0.130, z + 0.080 + math.sin(a) * 0.150))
	comb = geo.plate(outline, 0.030, row("steel"), side=row("trim"), sharp=40)
	geo.rotate(comb, 90.0, 'Z')
	geo.merge(bm, comb)
	for side in (-1.0, 1.0):
		cheek = geo.plate([(-0.050, 0.0), (0.050, 0.0), (0.040, -0.085), (0.0, -0.110), (-0.030, -0.080)], 0.012,
				row("steel"), side=row("trim"), sharp=40)
		geo.rotate(cheek, 90.0, 'Z')
		geo.rotate(cheek, side * 10.0, 'Y')
		geo.translate(cheek, (side * 0.186, 0.010, z - 0.004))
		geo.merge(bm, cheek)
		if lod == 0:
			hinge = geo.ellipsoid(0.012, 0.012, 0.012, 6, 3, row("brass"), sharp=40)
			geo.translate(hinge, (side * 0.192, 0.010, z - 0.010))
			geo.merge(bm, hinge)
	_rivets(bm, lod, 0.178, z + 0.016, sy)
	return _over_head(b, bm)


def armet(b, lod):
	"""An armet, chibi-sized: a round steel skull with a low ridge, cheek
	plates closing down the sides to the jaw, and a pointed sparrow-beak
	visor raised high above the brow on brass pivots, so the face shows."""
	z = b.brow_z
	sy = 0.95
	segs = seg(lod, 16, 10)
	prof = [(0.186, z - 0.120), (0.184, z - 0.060), (0.180, z + 0.000), (0.176, z + 0.050), (0.156, z + 0.108),
			(0.110, z + 0.150), (0.052, z + 0.168), (0.0, z + 0.172)]
	if lod > 0:
		prof = [prof[i] for i in (0, 2, 4, 5, 7)]

	def cheeks(theta, r, zz):
		# Closed down the sides and back to the jaw, cut up to the brow over
		# the face (a narrower cut than the barbute's T).
		front = max(0.0, -math.sin(theta)) ** 3
		if zz < z + 0.004:
			zz = z + 0.004 - (z + 0.004 - zz) * (1.0 - 0.97 * front)
		return (r * math.cos(theta), r * math.sin(theta) * sy, zz)

	bands = [row("trim")] + [row("steel")] * (len(prof) - 2)
	shell = geo.lathe(prof, segs, sharp=50, warp=cheeks, ring_swatches=bands)
	bm = geo.new_bm()
	geo.merge(bm, shell)
	geo.merge(bm, geo.flipped(shell, row("lining"), inset=0.006))
	geo.merge(bm, _crest_ridge(b, shell, z + 0.02, sy, lod, seg(lod, 13, 7), width=0.020))

	# The visor: the front of a beaked band, swung up round the pivots.
	def beak(theta, r, zz):
		front = max(0.0, -math.sin(theta))
		r = r + 0.11 * front ** 6 * (1.0 - abs(zz - (z - 0.050)) / 0.070)
		return (r * math.cos(theta), r * math.sin(theta) * sy, zz)

	vsegs = seg(lod, 20, 12)
	visor = geo.lathe([(0.196, z - 0.120), (0.200, z - 0.050), (0.194, z + 0.020)], vsegs, sharp=40, warp=beak,
			ring_swatches=[row("steel"), row("steel")])
	geo.delete_faces(visor, lambda f: f.calc_center_median().y > -0.035)
	geo.merge(visor, geo.flipped(visor, row("lining"), inset=0.004))
	pivot = Vector((0.0, 0.0, z - 0.010))
	geo.translate(visor, -pivot)
	geo.rotate(visor, -68.0, 'X')
	geo.translate(visor, pivot)
	geo.merge(bm, visor)
	for side in (-1.0, 1.0):
		boss = geo.ellipsoid(0.016, 0.016, 0.016, seg(lod, 6, 5), 3, row("brass"), sharp=40)
		geo.translate(boss, (side * 0.196, 0.0, z - 0.010))
		geo.merge(bm, boss)
	_rivets(bm, lod, 0.182, z + 0.016, sy)
	return _over_head(b, bm)


def great_helm(b, lod):
	"""A great helm, chibi-sized: a closed flat-topped steel barrel over the
	whole head, a dark eye slit across the front and a raised brass cross
	(the brow band and a strip down the face). The one helm that hides the
	face: the heavy knight."""
	z = b.brow_z
	sy = 0.96
	segs = seg(lod, 16, 10)
	prof = [(0.206, z - 0.170), (0.198, z - 0.110), (0.194, z - 0.030), (0.196, z + 0.050), (0.192, z + 0.112),
			(0.150, z + 0.138), (0.0, z + 0.146)]
	if lod > 0:
		prof = [prof[i] for i in (0, 2, 4, 5, 6)]
	bands = [row("trim")] + [row("steel")] * (len(prof) - 2)
	shell = geo.lathe(prof, segs, sharp=50, sy=sy, ring_swatches=bands)
	bm = geo.new_bm()
	geo.merge(bm, shell)
	geo.merge(bm, geo.flipped(shell, row("lining"), inset=0.006))
	# Eye slit: a dark band set into the front, split by the cross.
	for side in (-1.0, 1.0):
		slit = geo.box(0.120, 0.030, 0.026, row("base_dark"))
		geo.rotate(slit, side * 20.0, 'Z')
		geo.translate(slit, (side * 0.074, -0.180, z + 0.006))
		geo.merge(bm, slit)
	strip = geo.box(0.030, 0.030, 0.230, row("brass"), bevel=0.006 if lod == 0 else 0.0)
	geo.translate(strip, (0.0, -0.195 * sy, z - 0.050))
	geo.merge(bm, strip)
	band = geo.lathe([(0.200, z - 0.010), (0.204, z + 0.000), (0.204, z + 0.024), (0.200, z + 0.034)], segs,
			row("brass"), sharp=40, sy=sy)
	geo.delete_faces(band, lambda f: f.calc_center_median().y > 0.06)
	geo.merge(bm, band)
	_rivets(bm, lod, 0.198, z + 0.080, sy)
	return _over_head(b, bm)
