"""What figures carry: polearms, shields, bows, crossbows, staves, lances,
standards and work tools. Each is built along its own local axis and set in
the pose's hand (see poses.py), in the figure's standing space.
"""
import math

from mathutils import Matrix, Vector

import geo
from geo import FLAT, HARD, SMOOTH
from palette import row
import parts
from parts import seg


def _pole(length, radius, segments, swatch, below, tip_radius=None):
	"""A shaft along local +Z from -below to length - below."""
	tip = radius if tip_radius is None else tip_radius
	return geo.lathe([(radius, -below), (tip, length - below)], segments, swatch, sharp=40, phase=0.0,
			cap_start=swatch, cap_end=swatch)


def _place(bm, b, fist, axis, side_hint=(1.0, 0.0, 0.0)):
	"""Puts a part built along local +Z (its blade or head across local X)
	into `fist`, along `axis`, its local X as near `side_hint` as it can be."""
	axis = Vector(axis).normalized()
	hint = Vector(side_hint)
	y_hint = axis.cross(hint)
	geo.transform(bm, geo.frame(fist, axis, y_hint))
	return bm


def grow(bm, pivot, factor):
	"""Scales a held part round `pivot` (its fist): weapons are drawn larger
	than life so they read from the game camera."""
	pivot = Vector(pivot)
	geo.transform(bm, Matrix.Translation(pivot) @ Matrix.Scale(factor, 4) @ Matrix.Translation(-pivot))
	return bm


# --- polearms ---------------------------------------------------------------

def spear(b, lod, length=1.30, below=0.30, radius=0.0125, head=1.0):
	"""An ash spear, stood upright: a steel leaf head on a socket, a butt cap.
	`head` scales the head and socket round the shaft's top."""
	top = length - below
	r, k = radius, head
	bm = _pole(length - 0.12 * k, r, seg(lod, 6, 5), row("wood"), below)
	socket = geo.lathe([(r, top - 0.14 * k), (r * 1.36, top - 0.12 * k), (r * 1.04, top - 0.095 * k)],
			seg(lod, 6, 5), row("steel"), sharp=40, phase=0.0)
	geo.merge(bm, socket)
	blade = geo.plate([(0.0, top - 0.105 * k), (0.034 * k, top - 0.045 * k), (0.024 * k, top), (0.0, top + 0.075 * k),
			(-0.024 * k, top), (-0.034 * k, top - 0.045 * k)], 0.010 * k, row("blade"), sharp=FLAT)
	geo.merge(bm, blade)
	cap = geo.lathe([(0.0, -below - 0.012), (r * 1.2, -below - 0.006), (r * 1.2, -below + 0.03)], seg(lod, 6, 5),
			row("steel"), sharp=40, phase=0.0)
	geo.merge(bm, cap)
	return _place(bm, b, b.r_fist, b.pole_axis)


def halberd(b, lod, length=1.42, below=0.30, radius=0.022, head=1.5):
	"""A halberd: a crescent axe blade, edge down (parts.edge_down), a back
	hook and a top spike, steel langets down the shaft."""
	top = length - below
	bm = _pole(length - 0.08, radius, seg(lod, 6, 5), row("wood"), below)
	hd = geo.new_bm()
	blade = geo.plate([(-0.010, top - 0.215), (-0.060, top - 0.250), (-0.115, top - 0.232), (-0.142, top - 0.160),
			(-0.132, top - 0.085), (-0.092, top - 0.048), (-0.010, top - 0.075)], 0.012, row("blade"),
			side=row("steel"), sharp=FLAT)
	geo.merge(hd, blade)
	hook = geo.plate([(0.010, top - 0.165), (0.065, top - 0.140), (0.092, top - 0.094), (0.050, top - 0.112),
			(0.010, top - 0.115)], 0.011, row("steel"), sharp=FLAT)
	geo.merge(hd, hook)
	spike = geo.plate([(0.0, top - 0.09), (0.018, top - 0.02), (0.0, top + 0.10), (-0.018, top - 0.02)], 0.011,
			row("blade"), sharp=FLAT)
	geo.merge(hd, spike)
	geo.merge(bm, grow(hd, (0.0, 0.0, top - 0.14), head))
	collar = geo.lathe([(radius * 1.25, top - 0.30), (radius * 1.4, top - 0.27), (radius * 1.25, top - 0.06)], seg(lod, 6, 5),
			row("steel"), sharp=40, phase=0.0)
	geo.merge(bm, collar)
	if lod == 0:
		for side in (-1.0, 1.0):
			pts = [Vector((0.0, side * radius, top - 0.46)), Vector((0.0, side * radius, top - 0.28))]
			geo.merge(bm, geo.ribbon(pts, [Vector((0.0, side, 0.0))] * 2, 0.010, 0.003, row("steel"), sharp=40,
					embed=0.002))
	geo.transform(bm, geo.frame(b.r_fist, b.pole_axis, parts.edge_down(b.pole_axis, (-1.0, 0.0))))
	return bm


# --- shields ----------------------------------------------------------------

def _heater_outline(w, h, steps):
	half = w * 0.5
	top = h * 0.5
	pts = [(-half, top), (half, top), (half, top - h * 0.42)]
	# The two curves meeting at the point, from the right side round.
	for i in range(1, steps + 1):
		t = i / (steps + 1)
		a = t * math.pi * 0.5
		pts.append((half * math.cos(a), (top - h * 0.42) - (h * 0.58) * math.sin(a) ** 1.25))
	pts.append((0.0, -top))
	for i in range(steps, 0, -1):
		t = i / (steps + 1)
		a = t * math.pi * 0.5
		pts.append((-half * math.cos(a), (top - h * 0.42) - (h * 0.58) * math.sin(a) ** 1.25))
	pts.append((-half, top - h * 0.42))
	return pts


def tower_shield(b, lod, w=0.30, h=0.46):
	"""A tall heater shield on the left arm: a steel-rimmed board, its face
	in the team's colour with a cream chevron and a brass boss."""
	steps = seg(lod, 4, 2)
	outline = _heater_outline(w, h, steps)
	bm = geo.plate(outline, 0.026, row("steel"), back=row("wood"), side=row("steel"), sharp=40, bend=0.9)
	face = geo.plate([(x * 0.88, z * 0.9 - 0.004) for x, z in outline], 0.008, row("team"), sharp=40, bend=0.9)
	geo.translate(face, (0.0, -0.013, 0.0))
	geo.merge(bm, face)
	chevron = geo.plate([(-0.105, 0.035), (0.0, 0.115), (0.105, 0.035), (0.105, -0.005), (0.0, 0.075),
			(-0.105, -0.005)], 0.006, row("cream"), sharp=40, bend=0.9)
	geo.translate(chevron, (0.0, -0.0185, -0.01))
	geo.merge(bm, chevron)
	boss = geo.lathe([(0.032, 0.0), (0.033, 0.006), (0.020, 0.020), (0.0, 0.025)], seg(lod, 8, 6), row("brass"),
			sharp=40, phase=0.0)
	geo.rotate(boss, 90.0, 'X')
	geo.translate(boss, (0.0, -0.016, -0.05))
	geo.merge(bm, boss)
	geo.transform(bm, geo.orient(b.shield_centre, b.shield_normal))
	return bm


# --- bows -------------------------------------------------------------------

def longbow(b, lod):
	"""A bow upright in the left fist, bellied toward the target, its string
	back toward the archer; a leather grip."""
	grip = b.l_fist
	steps = seg(lod, 11, 6)
	# Its curve turned partly toward the viewer, so it reads as a bow and
	# not a stick from the game's camera in front.
	cant = math.radians(48.0)
	back = Vector((math.sin(cant), math.cos(cant), 0.0))
	pts, radii = [], []
	for i in range(steps):
		t = -1.0 + 2.0 * i / (steps - 1)
		z = t * 0.43
		y = 0.115 * t * t - 0.026 * t ** 8
		pts.append(grip + back * y + Vector((0.0, 0.0, z)))
		radii.append(0.0270 * (1.0 - 0.5 * abs(t)))
	bm = geo.tube(pts, radii, seg(lod, 5, 4), row("wood"), sharp=40, flatten=0.75, up=(1.0, 0.0, 0.0))
	wrap = geo.lathe([(0.026, -0.045), (0.028, 0.0), (0.026, 0.045)], seg(lod, 6, 4), row("leather_dark"),
			sharp=40, phase=0.0)
	geo.translate(wrap, grip)
	geo.merge(bm, wrap)
	string = geo.tube([pts[0], pts[-1]], [0.0055, 0.0055], 3, row("string"), sharp=SMOOTH)
	geo.merge(bm, string)
	return bm


def quiver(b, lod):
	"""A leather quiver slung across the back, fletched arrows standing out."""
	bottom = Vector((0.075, 0.150, 0.215))
	top = Vector((-0.055, 0.165, 0.485))
	axis = (top - bottom).normalized()
	length = (top - bottom).length
	bm = geo.lathe([(0.0, 0.0), (0.038, 0.004), (0.042, 0.03), (0.040, length - 0.02), (0.046, length - 0.01),
			(0.046, length)], seg(lod, 7, 5), sharp=40, phase=0.0,
			ring_swatches=[row("leather_dark"), row("leather"), row("leather"), row("leather_dark"),
					row("leather_dark")], cap_end=row("lining"))
	arrows = 4
	for i in range(arrows):
		a = 2.0 * math.pi * i / arrows + 0.4
		base = Vector((math.cos(a) * 0.018, math.sin(a) * 0.018, length - 0.01))
		shaft = geo.lathe([(0.004, 0.0), (0.004, 0.05)], 3, row("wood_light"), sharp=40, phase=0.0)
		geo.translate(shaft, base)
		geo.merge(bm, shaft)
		fletch = geo.plate([(0.0, 0.03), (0.012, 0.045), (0.0, 0.085), (-0.012, 0.045)], 0.004, row("fletch"),
				sharp=40)
		geo.rotate(fletch, math.degrees(a), 'Z')
		geo.translate(fletch, base)
		geo.merge(bm, fletch)
	geo.transform(bm, geo.frame(bottom, axis, (0.0, 1.0, 0.0)))
	return bm


CROSSBOW_SCALE = 1.75


def crossbow(b, lod):
	"""A crossbow levelled forward: a wooden stock, a steel prod and its
	string, a stirrup at the nose and a bolt laid in the groove."""
	rear, front = b.stock_rear, b.stock_front
	forward = (front - rear).normalized()
	length = (front - rear).length
	mid = (front + rear) * 0.5
	bm = geo.box(0.034, length, 0.040, row("wood"), 40, bevel=0.006 if lod == 0 else 0.0)
	butt = geo.box(0.040, 0.08, 0.060, row("wood"), 40, bevel=0.006 if lod == 0 else 0.0)
	geo.translate(butt, (0.0, length * 0.5 - 0.02, -0.012))
	geo.merge(bm, butt)
	tip = -length * 0.5 + 0.03
	pts = []
	steps = seg(lod, 7, 5)
	for i in range(steps):
		t = -1.0 + 2.0 * i / (steps - 1)
		pts.append(Vector((t * 0.16, tip + 0.045 * t * t, 0.012)))
	prod = geo.tube(pts, [0.016 * (1.0 - 0.35 * abs(-1.0 + 2.0 * i / (steps - 1))) for i in range(steps)],
			seg(lod, 4, 3), row("steel"), sharp=40, flatten=0.6)
	geo.merge(bm, prod)
	nut = Vector((0.0, tip + 0.15, 0.024))
	for end in (pts[0], pts[-1]):
		geo.merge(bm, geo.tube([end, nut], [0.0040, 0.0040], 3, row("string"), sharp=SMOOTH))
	if lod == 0:
		stirrup = geo.tube([Vector((-0.025, tip, 0.0)), Vector((-0.03, tip - 0.05, -0.005)),
				Vector((0.0, tip - 0.07, -0.006)), Vector((0.03, tip - 0.05, -0.005)), Vector((0.025, tip, 0.0))],
				[0.006] * 5, 4, row("steel"), sharp=40)
		geo.merge(bm, stirrup)
		bolt = geo.lathe([(0.006, 0.0), (0.006, 0.16), (0.012, 0.165), (0.0, 0.19)], 4, sharp=40, phase=0.0,
				ring_swatches=[row("wood_light"), row("steel"), row("steel")])
		geo.rotate(bolt, 90.0, 'X')
		geo.translate(bolt, (0.0, tip + 0.15, 0.024))
		geo.merge(bm, bolt)
		lever = geo.box(0.008, 0.10, 0.012, row("steel"), 40)
		geo.rotate(lever, 12.0, 'X')
		geo.translate(lever, (0.0, length * 0.25, -0.032))
		geo.merge(bm, lever)
	geo.transform(bm, geo.orient(mid, forward))
	# Grown round the stock under the right fist, so both hands stay on it.
	pivot = rear + forward * (b.r_fist - rear).dot(forward)
	return grow(bm, pivot, CROSSBOW_SCALE)


def bolt_case(b, lod):
	"""A square bolt case on the right hip, the bolts' ends showing."""
	bm = geo.box(0.050, 0.040, 0.090, row("leather"), 40, bevel=0.006 if lod == 0 else 0.0)
	if lod == 0:
		for i in range(3):
			end = geo.box(0.010, 0.010, 0.030, row("fletch"), 40)
			geo.translate(end, (-0.015 + i * 0.015, 0.0, 0.055))
			geo.merge(bm, end)
	geo.rotate(bm, -30.0, 'Z')
	geo.translate(bm, (-0.150, 0.050, b.waist_z - 0.055))
	return bm


# --- staves -----------------------------------------------------------------

STAFF_HEAD_SCALE = 1.45


def wizard_staff(b, lod, below=0.32):
	"""A gnarled wooden staff, its head curling round a pale blue crystal."""
	axis = b.pole_axis
	fist = b.r_fist
	foot = fist - axis * below
	top = fist + axis * 0.70
	bm = geo.tube([foot, fist, top], [0.022, 0.024, 0.027], seg(lod, 6, 5), row("wood"), sharp=40)
	hd = geo.new_bm()
	steps = seg(lod, 7, 4)
	curl = []
	for i in range(steps):
		a = math.pi * 1.5 * i / (steps - 1)
		curl.append(top + Vector((-math.sin(a) * 0.06, 0.0, (1.0 - math.cos(a)) * 0.055 + i * 0.004)))
	geo.merge(hd, geo.tube(curl, [0.018 * (1.0 - 0.45 * i / (steps - 1)) for i in range(steps)], seg(lod, 5, 4),
			row("wood"), sharp=40))
	gem = geo.ellipsoid(0.034, 0.034, 0.05, 4, 2, row("crystal"), sharp=FLAT)
	geo.translate(gem, top + Vector((-0.045, 0.0, 0.085)))
	geo.merge(hd, gem)
	geo.merge(bm, grow(hd, top, STAFF_HEAD_SCALE))
	return bm


def arch_staff(b, lod, below=0.32):
	"""A tall gilded staff topped by a crescent cradling a crystal orb."""
	axis = b.pole_axis
	fist = b.r_fist
	foot = fist - axis * below
	top = fist + axis * 0.78
	bm = geo.tube([foot, top], [0.021, 0.024], seg(lod, 6, 5), row("robe_trim"), sharp=40)
	hd = geo.new_bm()
	knop = geo.ellipsoid(0.024, 0.024, 0.02, seg(lod, 6, 5), 3, row("robe_trim"), sharp=40)
	geo.translate(knop, top)
	geo.merge(hd, knop)
	steps = seg(lod, 9, 5)
	centre = top + Vector((0.0, 0.0, 0.075))
	arc, radii = [], []
	for i in range(steps):
		t = i / (steps - 1)
		a = math.radians(150.0 + 240.0 * t)
		arc.append(centre + Vector((math.cos(a) * 0.075, 0.0, math.sin(a) * 0.075)))
		radii.append(0.005 + 0.012 * math.sin(math.pi * t))
	geo.merge(hd, geo.tube(arc, radii, seg(lod, 5, 4), row("robe_trim"), sharp=40))
	orb = geo.ellipsoid(0.042, 0.042, 0.042, seg(lod, 8, 6), seg(lod, 5, 4), row("crystal"), sharp=SMOOTH)
	geo.translate(orb, centre)
	geo.merge(hd, orb)
	geo.merge(bm, grow(hd, top, STAFF_HEAD_SCALE))
	return bm


# --- lances and standards -----------------------------------------------------

def lance(b, lod, length=1.65, below=0.40, pennant=True, side_hint=(0.0, -1.0, 0.0)):
	"""A lance: a tapering shaft, a steel vamplate guarding the hand, a steel
	head, and (if wanted) a swallow-tailed pennant in the team's colour."""
	top = length - below
	bm = geo.lathe([(0.028, -below), (0.031, -0.05), (0.025, top - 0.16), (0.017, top - 0.14)], seg(lod, 6, 5),
			row("wood_light"), sharp=40, phase=0.0, cap_start=row("wood_light"))
	vamp = geo.lathe([(0.020, 0.03), (0.075, 0.075), (0.070, 0.085), (0.018, 0.11)], seg(lod, 8, 6), row("steel"),
			sharp=40, phase=0.0)
	geo.merge(bm, vamp)
	head = geo.lathe([(0.020, top - 0.15), (0.036, top - 0.08), (0.0, top + 0.07)], 4, row("blade"), sharp=FLAT,
			phase=0.0)
	geo.merge(bm, head)
	if pennant:
		flag = geo.plate([(0.0, top - 0.16), (0.0, top - 0.33), (-0.27, top - 0.32), (-0.19, top - 0.245),
				(-0.29, top - 0.17)], 0.010, row("team_cloth"), sharp=40)
		geo.merge(bm, flag)
	return _place(bm, b, b.r_fist, b.pole_axis, side_hint=side_hint)


def back_banner(b, lod):
	"""A regiment's standard on a pole at the officer's back: a crossbar and
	a swallow-tailed flag in the team's colour with a cream cross."""
	foot = Vector((0.0, 0.135, 0.30))
	tip = Vector((0.0, 0.16, 1.30))
	bm = geo.tube([foot, tip], [0.021, 0.021], seg(lod, 6, 4), row("wood"), sharp=40)
	finial = geo.ellipsoid(0.034, 0.034, 0.042, seg(lod, 6, 5), 3, row("brass"), sharp=40)
	geo.translate(finial, tip + Vector((0.0, 0.0, 0.035)))
	geo.merge(bm, finial)
	bar = geo.tube([tip + Vector((-0.17, 0.0, -0.06)), tip + Vector((0.17, 0.0, -0.06))], [0.014, 0.014], 4,
			row("wood"), sharp=40)
	geo.merge(bm, bar)
	flag = geo.plate([(-0.16, 0.0), (0.16, 0.0), (0.16, -0.34), (0.08, -0.27), (0.0, -0.34), (-0.08, -0.27),
			(-0.16, -0.34)], 0.010, row("team_cloth"), sharp=40, bend=-0.6)
	if lod == 0:
		for outline in ([(-0.020, -0.04), (0.020, -0.04), (0.020, -0.26), (-0.020, -0.26)],
				[(-0.11, -0.13), (0.11, -0.13), (0.11, -0.17), (-0.11, -0.17)]):
			for face in (-1.0, 1.0):
				cross = geo.plate(outline, 0.004, row("cream"), sharp=40, bend=-0.6)
				geo.translate(cross, (0.0, face * 0.006, 0.0))
				geo.merge(flag, cross)
	geo.translate(flag, tip + Vector((0.0, 0.0, -0.06)))
	geo.merge(bm, flag)
	return bm


# --- work tools -------------------------------------------------------------

def _tool_handle(lod, length=0.32, below=0.07):
	return geo.lathe([(0.0, -below), (0.012, -below + 0.004), (0.013, 0.0), (0.012, length - below)],
			seg(lod, 6, 5), row("wood_light"), sharp=40, phase=0.0)


def hammer(b, lod):
	"""A builder's hammer: an ash handle, a squared steel head."""
	bm = _tool_handle(lod, 0.30)
	head = geo.box(0.11, 0.040, 0.040, row("steel"), 40, bevel=0.005 if lod == 0 else 0.0)
	geo.translate(head, (0.0, 0.0, 0.215))
	geo.merge(bm, head)
	face = geo.box(0.02, 0.046, 0.046, row("steel"), 40)
	geo.translate(face, (-0.060, 0.0, 0.215))
	geo.merge(bm, face)
	return _place(bm, b, b.r_fist, b.sword_axis)


def axe(b, lod):
	"""A woodsman's axe, its bearded blade edge down (parts.edge_down)."""
	bm = _tool_handle(lod, 0.36)
	blade = geo.plate([(-0.008, 0.31), (-0.040, 0.322), (-0.095, 0.335), (-0.105, 0.27), (-0.085, 0.215),
			(-0.040, 0.245), (-0.008, 0.255)], 0.014, row("blade"), side=row("steel"), sharp=FLAT)
	geo.merge(bm, blade)
	poll = geo.box(0.035, 0.026, 0.06, row("steel"), 40)
	geo.translate(poll, (0.010, 0.0, 0.285))
	geo.merge(bm, poll)
	geo.transform(bm, geo.frame(b.r_fist, b.sword_axis, parts.edge_down(b.sword_axis, (-1.0, 0.0))))
	return bm


def pick(b, lod):
	"""A miner's pick: a curved double-pointed steel head."""
	bm = _tool_handle(lod, 0.34)
	steps = seg(lod, 7, 5)
	pts = []
	for i in range(steps):
		t = -1.0 + 2.0 * i / (steps - 1)
		pts.append(Vector((t * 0.15, 0.0, 0.27 - 0.05 * t * t)))
	radii = [0.017 * (1.0 - 0.8 * abs(-1.0 + 2.0 * i / (steps - 1)) ** 1.5) + 0.002 for i in range(steps)]
	geo.merge(bm, geo.tube(pts, radii, seg(lod, 5, 4), row("steel"), sharp=40, flatten=0.8))
	eye = geo.box(0.032, 0.032, 0.040, row("steel"), 40)
	geo.translate(eye, (0.0, 0.0, 0.27))
	geo.merge(bm, eye)
	return _place(bm, b, b.r_fist, b.sword_axis)


def basket(b, lod):
	"""A wicker basket of apples on the bent left arm."""
	fist = b.l_fist
	centre = fist + Vector((0.020, -0.005, -0.13))
	bm = geo.lathe([(0.0, -0.055), (0.050, -0.055), (0.066, -0.02), (0.075, 0.02), (0.082, 0.03), (0.074, 0.032)],
			seg(lod, 10, 7), sharp=40, phase=0.0,
			ring_swatches=[row("wicker"), row("wicker"), row("wicker"), row("wood_light"), row("wood_light")],
			cap_start=row("wicker"))
	inner = geo.lathe([(0.072, 0.02), (0.0, 0.01)], seg(lod, 10, 7), row("lining"), sharp=40, phase=0.0)
	geo.merge(bm, inner)
	fruit = [((0.025, 0.010), "fruit"), ((-0.022, -0.016), "fruit"), ((-0.010, 0.030), "fruit_green")]
	if lod == 0:
		fruit.append(((0.030, -0.030), "fruit"))
	for (x, y), name in fruit:
		apple = geo.ellipsoid(0.026, 0.026, 0.024, seg(lod, 7, 5), seg(lod, 4, 3), row(name), sharp=SMOOTH)
		geo.translate(apple, (x, y, 0.035))
		geo.merge(bm, apple)
	handle = geo.tube([Vector((-0.074, 0.0, 0.03)), Vector((-0.060, 0.0, 0.10)), Vector((0.0, 0.0, 0.135)),
			Vector((0.060, 0.0, 0.10)), Vector((0.074, 0.0, 0.03))], [0.007] * 5, 4, row("wicker"), sharp=40)
	geo.merge(bm, handle)
	geo.rotate(bm, 90.0, 'Z')
	geo.translate(bm, centre)
	return bm
