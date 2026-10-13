# Dark Elf helpers on top of the Aldmere kit (TownBuildings/kit/common.py),
# borrowing the generic shape helpers (ring_solid, scallop_slab, frames) from
# the Beastmen kit.
#
# The Dark Elf look: everything stands on a sharp octagonal dais of glossy
# violet-black obsidian with a silver rim, its corners set with curved thorns;
# walls are tall tapering octagonal towers and blade-sided halls banded in
# silver and pierced by narrow pointed slit windows glowing magenta; roofs
# are concave, swooping team-coloured spires whose eave corners curl up into
# points, each topped by a silver needle carrying a crescent blade cradling a
# magenta crystal. Venom-green lanterns hang from hooked silver arms, silver
# spiders and webs mark doors and banners, and crescent blades crown posts.
# Where the Beastmen are warm, round and low, this is cold, sharp and tall.
#
# A script does `from darkelves_common import *` (which also brings in all of
# common and the Beastmen helpers), builds, then export(name), which writes
# ../<Name>.glb.
import sys, os
_DE_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.normpath(os.path.join(_DE_HERE, '..', '..', 'Beastmen', 'kit')))
from beastmen_common import *
import common
from beastmen_common import _rz, _rx, _ry, _t, _mesh_obj, _placed_m
from common import _finish, _placed, _rot

# Public frame helpers for the building scripts (star imports skip _names).
tr, rz, rx, ry = _t, _rz, _rx, _ry


def _de_out_path(name):
	if '--' in sys.argv and len(sys.argv) > sys.argv.index('--') + 1:
		return sys.argv[sys.argv.index('--') + 1]
	return os.path.join(os.path.dirname(_DE_HERE), name + '.glb')


# beastmen_common points export() at the Beastmen folder; point it here.
common.out_path = _de_out_path

# Cold jewel colours (linear). Every violet sits at hue 0.76 or above (plum
# side), well clear of the team shader's blue window (about 0.52-0.68);
# silver is near-neutral with a plum cast. TeamColor stays the kit blue.
common.COLOURS.update({
	'Obsidian': (0.115, 0.062, 0.155), 'ObsidianDark': (0.06, 0.032, 0.08),
	'ObsidianLight': (0.2, 0.12, 0.25), 'Plum': (0.27, 0.05, 0.2), 'PlumDark': (0.13, 0.022, 0.1),
	'Silver': (0.62, 0.58, 0.62), 'SilverDark': (0.3, 0.27, 0.3),
	'Crystal': (0.9, 0.05, 0.5), 'Venom': (0.2, 0.9, 0.06), 'VenomDark': (0.05, 0.3, 0.02),
	'DarkWood': (0.07, 0.035, 0.055), 'Web': (0.72, 0.7, 0.72), 'Silk': (0.78, 0.74, 0.76),
})
common.GLOSSY = common.GLOSSY + ('Obsidian', 'ObsidianDark', 'ObsidianLight', 'Plum', 'PlumDark', 'Silver',
		'SilverDark', 'Crystal', 'Venom', 'TeamColor', 'TeamColorDark')

# Dais top: where buildings stand.
DZ = 0.26


def octo(rb, rt, h, loc, mat_name, sx=1.0, sy=1.0, bevel=0.035, matrix=None, sides=8):
	"""An octagonal (or `sides`) solid with flat faces toward the axes, radius
	rb at its foot and rt at its top (to the corners)."""
	return ring_solid(rb, rt, h, loc, mat_name, n=sides, sx=sx, sy=sy, bevel=bevel, angle=30, matrix=matrix,
			rot_z=180.0 / sides)


def apothem(r, sides=8):
	return r * math.cos(math.pi / sides)


def thorn(frame, length=0.5, r=0.07, bend=28, segs=3, mat_name='Silver'):
	"""A curved thorn growing up local +Z from `frame`, bending toward -Y."""
	cur = frame
	ln = length / (segs + 0.6)
	for i in range(segs):
		cylinder(r, ln * 1.05, (0, 0, ln / 2), mat_name, verts=6, bevel=0.0, radius2=r * 0.72, matrix=cur)
		cur = cur @ _t(0, 0, ln) @ _rx(bend / segs)
		r *= 0.72
	cylinder(r, ln * 0.9, (0, 0, ln * 0.45), mat_name, verts=6, bevel=0.0, radius2=0.0, matrix=cur)


def dais(rx, ry=None, cx=0.0, cy=0.0, h=DZ, thorns=True, steps=True):
	"""The obsidian dais a building stands on: an octagonal slab with a silver
	rim, a stepped skirt and curved silver-tipped thorns at its corners."""
	ry = ry or rx
	k = 1.0 / math.cos(math.pi / 8)
	octo(1.0, 1.0, h * 0.55, (cx, cy, 0), 'ObsidianDark', sx=(rx + 0.12) * k, sy=(ry + 0.12) * k, bevel=0.05)
	octo(1.0, 1.0, h * 0.5, (cx, cy, h * 0.5), 'Obsidian', sx=rx * k, sy=ry * k, bevel=0.04)
	octo(1.0, 1.0, 0.05, (cx, cy, h - 0.03), 'Silver', sx=(rx - 0.06) * k, sy=(ry - 0.06) * k, bevel=0.02)
	octo(1.0, 1.0, 0.05, (cx, cy, h - 0.01), 'ObsidianLight', sx=(rx - 0.16) * k, sy=(ry - 0.16) * k, bevel=0.02)
	if steps:
		# A front step down to the ground.
		box((min(1.2, rx), 0.34, h * 0.5), (cx, cy - ry - 0.2, h * 0.25), 'Obsidian', bevel=0.04)
	if thorns:
		for a in (45, 135, 225, 315):
			ar = math.radians(a)
			x = cx + math.cos(ar) * (rx + 0.04) * 0.92
			y = cy + math.sin(ar) * (ry + 0.04) * 0.92
			f = _t(x, y, h * 0.5) @ _rz(a + 90)
			thorn(f, 0.55, 0.09, bend=-38, mat_name='ObsidianLight')
	return h


def band(r, z, h=0.07, cx=0.0, cy=0.0, mat_name='Silver', sides=8, sx=1.0, sy=1.0):
	octo(r, r, h, (cx, cy, z - h / 2), mat_name, sx=sx, sy=sy, bevel=0.02, sides=sides)


def crystal(loc, h=0.4, r=0.09, mat_name='Crystal', matrix=None, tilt=(0, 0)):
	"""A hexagonal crystal: a long point up, a short one down."""
	m = (matrix or Matrix.Identity(4)) @ _t(*loc) @ _rx(tilt[0]) @ _ry(tilt[1])
	cylinder(r, h * 0.72, (0, 0, h * 0.36), mat_name, verts=6, bevel=0.0, radius2=0.0, matrix=m)
	cylinder(r, h * 0.22, (0, 0, -h * 0.11 + 0.002), mat_name, verts=6, bevel=0.0, radius2=0.0,
			matrix=m @ _rx(180))


def crystal_cluster(x, y, z, s=1.0, mat_name='Crystal'):
	crystal((x, y, z + 0.05 * s), 0.55 * s, 0.1 * s, mat_name)
	for a, t in ((20, 26), (150, 30), (260, 22)):
		f = _t(x, y, z) @ _rz(a)
		crystal((0.07 * s, 0, 0.03 * s), 0.34 * s, 0.07 * s, mat_name, matrix=f, tilt=(0, t))


def crescent(frame, r=0.3, thick=0.06, mat_name='Silver', span=150, width=0.45):
	"""A horns-up crescent blade in `frame`'s XZ plane, its belly at the
	origin, `thick` along Y."""
	n = 14
	a0, a1 = math.radians(270 - span / 2 - 15), math.radians(270 + span / 2 + 15)
	outer, inner = [], []
	for i in range(n + 1):
		s = i / n
		a = a0 + (a1 - a0) * s
		f = 0.07 + 0.93 * math.sin(math.pi * s)
		ox, oz = r * math.cos(a), r * math.sin(a) + r
		outer.append((ox, oz))
		inner.append((ox * (1 - width * f), r + (oz - r) * (1 - width * f) + r * width * f * 0.15))
	pts = outer + list(reversed(inner[1:-1]))
	bm = bmesh.new()
	vs = [bm.verts.new((x, -thick / 2, z)) for x, z in pts]
	fc = bm.faces.new(vs)
	ext = bmesh.ops.extrude_face_region(bm, geom=[fc])
	for v in [g for g in ext['geom'] if isinstance(g, bmesh.types.BMVert)]:
		v.co.y += thick
	obj = _mesh_obj(bm, 'crescent')
	obj.matrix_world = frame
	return _finish(obj, mat_name, min(0.02, thick * 0.3), 2, angle=40)


def finial(x, y, z, h=0.6, s=1.0, gem='Crystal', rot=0.0):
	"""A silver needle on the tip of a spire, carrying a crescent blade that
	cradles a crystal. Returns its top."""
	cylinder(0.06 * s, 0.14 * s, (x, y, z + 0.05 * s), 'Silver', verts=8, bevel=0.015)
	sphere(0.075 * s, (x, y, z + 0.15 * s), 'Silver')
	cylinder(0.04 * s, h * s, (x, y, z + 0.15 * s + h * s / 2), 'Silver', verts=6, bevel=0.0, radius2=0.025 * s)
	top = z + 0.15 * s + h * s
	f = _t(x, y, top - 0.06 * s) @ _rz(rot)
	crescent(f, 0.2 * s, 0.05 * s)
	crystal((0, 0, 0.16 * s), 0.3 * s, 0.065 * s, gem, matrix=f)
	return top + 0.3 * s


def swoop_spire(r, h, z, cx=0.0, cy=0.0, sides=8, flare=0.3, lift=0.3, power=2.1, rings=9, mat_name='TeamColor',
		rot=0.0, tip=True, gem='Crystal', sx=1.0, sy=1.0, finial_h=0.5):
	"""A concave witch-hat spire: its sides sweep in from a wide eave to a
	needle point, and the eave's corners flare out and curl up into thorny
	points. A silver rim runs under the eave. Returns the spire's tip."""
	bm = bmesh.new()
	rings_v = []
	cnt = sides * 2
	for i in range(rings):
		t = i / rings
		rad = r * (1 - t) ** power
		amp = (1 - t) ** 3
		ring = []
		for j in range(cnt):
			a = 2 * math.pi * j / cnt + math.radians(rot) + math.pi / sides
			corner = j % 2 == 0
			rr = rad + (flare * r * amp if corner else 0.0)
			zz = z + h * t + (lift * amp if corner else 0.0)
			ring.append(bm.verts.new((cx + math.cos(a) * rr * sx, cy + math.sin(a) * rr * sy, zz)))
		rings_v.append(ring)
	apex = bm.verts.new((cx, cy, z + h))
	for i in range(rings - 1):
		a_, b_ = rings_v[i], rings_v[i + 1]
		for j in range(cnt):
			k = (j + 1) % cnt
			bm.faces.new((a_[j], a_[k], b_[k], b_[j]))
	top = rings_v[-1]
	for j in range(cnt):
		bm.faces.new((top[j], top[(j + 1) % cnt], apex))
	# A shallow underside so the eave has some thickness.
	under = bm.verts.new((cx, cy, z + 0.12))
	bot = rings_v[0]
	for j in range(cnt):
		bm.faces.new((bot[(j + 1) % cnt], bot[j], under))
	_finish(_mesh_obj(bm, 'spire'), mat_name, 0.02, 2, angle=35)
	# Silver drops on the curled eave tips.
	for j in range(0, cnt, 2):
		a = 2 * math.pi * j / cnt + math.radians(rot) + math.pi / sides
		rr = r * (1 + flare) + 0.01
		sphere(0.055 * max(0.7, r), (cx + math.cos(a) * rr * sx, cy + math.sin(a) * rr * sy, z + lift + 0.01), 'Silver')
	if tip:
		return finial(cx, cy, z + h - 0.06, h=finial_h, s=max(0.7, min(1.3, r)), gem=gem, rot=rot)
	return z + h


def tower(r, z0, z1, cx=0.0, cy=0.0, taper=0.85, sides=8, bands=(), mat_name='Obsidian'):
	"""A tapering octagonal tower body with silver bands at the given heights
	(fractions). Returns the top radius."""
	octo(r, r * taper, z1 - z0, (cx, cy, z0), mat_name, bevel=0.04, sides=sides)
	for f in bands:
		rr = r + (r * taper - r) * f
		band(rr + 0.035, z0 + (z1 - z0) * f, cx=cx, cy=cy, sides=sides)
	return r * taper


def slit(frame, w=0.16, h=0.5, glow='Crystal'):
	"""A narrow pointed slit window, lit from inside, on the face in front of
	`frame` (its centre)."""
	box((w + 0.1, 0.06, h + 0.06), (0, 0.0, 0), 'SilverDark', bevel=0.02, segments=2, matrix=frame)
	box((w, 0.08, h), (0, -0.01, 0), 'Window', bevel=0.02, segments=2, matrix=frame)
	box((w * 0.45, 0.09, h * 0.8), (0, -0.02, -h * 0.02), glow, bevel=0.015, segments=2, matrix=frame)
	for s in (-1, 1):
		box((w * 0.85, 0.08, 0.06), (s * w * 0.3, -0.03, h / 2 + w * 0.22), 'Silver', rot=(0, s * 38, 0), bevel=0.015,
				segments=2, matrix=frame)
	box((w + 0.16, 0.1, 0.06), (0, -0.03, -h / 2 - 0.03), 'Silver', bevel=0.02, segments=2, matrix=frame)


def arch_door(frame, w=0.6, h=0.9, glow='Crystal', thorns=True, leaves=True):
	"""A tall pointed-arch doorway standing on `frame` (bottom centre): a
	silver frame round two plum leaves, a crystal at the arch's point and
	thorns rising either side."""
	box((w, 0.1, h), (0, 0.02, h / 2), 'Window', bevel=0.03, segments=2, matrix=frame)
	box((w * 0.72, 0.1, w * 0.72), (0, 0.02, h), 'Window', rot=(0, 45, 0), bevel=0.03, segments=2, matrix=frame)
	for s in (-1, 1):
		if leaves:
			box((w * 0.44, 0.06, h * 0.96), (s * w * 0.235, -0.03, h * 0.48), 'Plum', bevel=0.025, segments=2, matrix=frame)
			box((0.04, 0.07, h * 0.8), (s * w * 0.06, -0.06, h * 0.46), 'Silver', bevel=0.01, segments=2, matrix=frame)
		box((0.11, 0.14, h + 0.02), (s * (w / 2 + 0.05), -0.05, h / 2), 'Silver', bevel=0.03, segments=2, matrix=frame)
		box((0.11, 0.14, w * 0.82), (s * w * 0.27, -0.05, h + w * 0.25), 'Silver', rot=(0, s * 45, 0), bevel=0.03,
				segments=2, matrix=frame)
		if thorns:
			thorn(frame @ _t(s * (w / 2 + 0.1), -0.07, h - 0.02) @ _rz(90 * s), 0.46, 0.06, bend=-30)
	crystal((0, -0.09, h + w * 0.52), 0.28, 0.07, glow, matrix=frame)


def spider(frame, s=1.0, mat_name='Silver', mark='Crystal'):
	"""A spider sprawled on the face in front of `frame` (its centre), head up."""
	box((0.26 * s, 0.1 * s, 0.32 * s), (0, -0.05 * s, -0.1 * s), mat_name, bevel=0.1 * s, segments=2, matrix=frame)
	box((0.17 * s, 0.1 * s, 0.17 * s), (0, -0.05 * s, 0.13 * s), mat_name, bevel=0.06 * s, segments=2, matrix=frame)
	box((0.06 * s, 0.03 * s, 0.13 * s), (0, -0.1 * s, -0.1 * s), mark, rot=(0, 0, 0), bevel=0.012, segments=2,
			matrix=frame @ _t(0, 0, 0))
	for sx in (-1, 1):
		for k, (ang, dz) in enumerate(((55, 0.19), (20, 0.15), (-15, 0.11), (-50, 0.07))):
			b = frame @ _t(sx * 0.07 * s, -0.04 * s, dz * s) @ _ry(-sx * (90 - ang))
			box((0.035 * s, 0.035 * s, 0.24 * s), (0, 0, 0.12 * s), mat_name, bevel=0.0, matrix=b)
			knee = b @ _t(0, 0, 0.23 * s) @ _ry(sx * (55 if ang > 0 else 70))
			box((0.03 * s, 0.03 * s, 0.24 * s), (0, 0, 0.12 * s), mat_name, bevel=0.0, matrix=knee)


def web(frame, r=0.4, spokes=7, rings=(0.4, 0.75), mat_name='Web', thick=0.025, arc=None):
	"""A spider web on the face in front of `frame` (its hub). With `arc`
	(degrees, e.g. (0, 180)) only that fan, for a web in a corner or arch."""
	a0, a1 = arc or (0, 360)
	full = arc is None
	n = spokes if full else spokes - 1
	angs = [math.radians(a0 + (a1 - a0) * i / (spokes if full else spokes - 1)) for i in range(spokes)]
	for a in angs:
		box((thick, thick, r), (math.cos(a) * r / 2, -0.02, math.sin(a) * r / 2), mat_name,
				rot=(0, 90 - math.degrees(a), 0), bevel=0.0, matrix=frame)
	for f in rings:
		rr = r * f
		for i in range(n):
			p = angs[i]
			q = angs[(i + 1) % spokes]
			x0, z0 = math.cos(p) * rr, math.sin(p) * rr
			x1, z1 = math.cos(q) * rr, math.sin(q) * rr
			ln = math.hypot(x1 - x0, z1 - z0)
			ang = math.degrees(math.atan2(z1 - z0, x1 - x0))
			box((ln, thick, thick), ((x0 + x1) / 2, -0.025, (z0 + z1) / 2), mat_name, rot=(0, -ang, 0), bevel=0.0,
					matrix=frame)


def lantern(frame, drop=0.3, s=1.0, glow='Venom', arm=0.32):
	"""A hooked silver arm sticking out of a wall at `frame`, a lantern of
	glowing glass in a silver cage hanging from it."""
	box((0.05 * s, arm * s, 0.05 * s), (0, -arm * s / 2, 0), 'Silver', bevel=0.0, matrix=frame)
	thorn(frame @ _t(0, -arm * s, 0), 0.16 * s, 0.03 * s, bend=-60, segs=2)
	cylinder(0.012 * s, drop * s, (0, -arm * s + 0.02 * s, -drop * s / 2), 'Silver', verts=4, bevel=0.0, matrix=frame)
	lan = frame @ _t(0, -arm * s + 0.02 * s, -drop * s)
	cylinder(0.1 * s, 0.08 * s, (0, 0, -0.03 * s), 'Silver', verts=6, bevel=0.0, radius2=0.025 * s, matrix=lan)
	cylinder(0.075 * s, 0.2 * s, (0, 0, -0.16 * s), glow, verts=6, bevel=0.0, matrix=lan)
	for k in range(3):
		a = math.radians(60 * k + 30)
		box((0.02 * s, 0.17 * s, 0.22 * s), (0, 0, -0.16 * s), 'Silver', rot=(0, 0, math.degrees(a)), bevel=0.0,
				matrix=lan)
	cylinder(0.08 * s, 0.1 * s, (0, 0, 0.05 * s), 'Silver', verts=6, bevel=0.0, radius2=0.0, matrix=lan @ _t(0, 0, -0.26 * s) @ _rx(180))


def pennant(w, h, frame, spider_mark=True):
	"""A team pennant hanging from a silver bar (centre `frame`) with crescent
	finials, cut to one long sharp point, a silver spider on it."""
	box((w + 0.12, 0.06, 0.06), (0, 0, 0), 'Silver', bevel=0.015, segments=2, matrix=frame)
	for sx in (-1, 1):
		crescent(frame @ _t(sx * (w / 2 + 0.08), 0, 0.0) @ _ry(sx * 60), 0.08, 0.035)
	bm = bmesh.new()
	pts = [(-w / 2, -0.02), (w / 2, -0.02), (w / 2, -h * 0.72), (0, -h), (-w / 2, -h * 0.72)]
	vs = [bm.verts.new((x, 0.02, z)) for x, z in pts]
	fc = bm.faces.new(vs)
	ext = bmesh.ops.extrude_face_region(bm, geom=[fc])
	for v in [g for g in ext['geom'] if isinstance(g, bmesh.types.BMVert)]:
		v.co.y -= 0.05
	obj = _mesh_obj(bm, 'pennant')
	obj.matrix_world = frame
	_finish(obj, 'TeamColor', 0.02, 2, angle=30)
	box((w + 0.01, 0.06, 0.07), (0, -0.01, -0.1), 'TeamColorDark', bevel=0.015, segments=2, matrix=frame)
	if spider_mark:
		spider(frame @ _t(0, -0.03, -h * 0.45), min(w, h) * 0.7)


def blade_post(x, y, z0, h, r=0.07, s=1.0, mat_name='ObsidianLight', side='-y'):
	"""A slim octagonal post crowned by a silver crescent blade."""
	octo(r, r * 0.8, h, (x, y, z0), mat_name, bevel=0.015)
	f = face(x, y, z0 + h, side)
	crescent(f, 0.2 * s, 0.05)
	return z0 + h


def blade_fin(frame, h=1.2, depth=0.35, thick=0.08, mat_name='Plum'):
	"""A tall curved blade-shaped buttress standing out from a wall at
	`frame` (its foot), sweeping up to a point; it lies in local YZ."""
	n = 8
	pts = []
	for i in range(n + 1):
		t = i / n
		pts.append((-depth * (1 - t) ** 1.4 - 0.02 * (1 - t), h * t))
	pts.append((0.02, h * 0.9))
	pts.append((0.02, 0.0))
	bm = bmesh.new()
	vs = [bm.verts.new((-thick / 2, y, z)) for y, z in pts]
	fc = bm.faces.new(vs)
	ext = bmesh.ops.extrude_face_region(bm, geom=[fc])
	for v in [g for g in ext['geom'] if isinstance(g, bmesh.types.BMVert)]:
		v.co.x += thick
	obj = _mesh_obj(bm, 'fin')
	obj.matrix_world = frame
	return _finish(obj, mat_name, 0.02, 2, angle=35)


def hall_box(hx, hy, z0, z1, cx=0.0, cy=0.0, mat_name='Obsidian'):
	"""A rectangular hall body with chamfered corners, a plum plinth course and
	a silver cornice. Returns its top."""
	k = 1.0 / math.cos(math.pi / 8)
	box((hx * 2, hy * 2, z1 - z0), (cx, cy, (z0 + z1) / 2), mat_name, bevel=0.12, segments=2)
	box((hx * 2 + 0.08, hy * 2 + 0.08, 0.16), (cx, cy, z0 + 0.08), 'PlumDark', bevel=0.05, segments=2)
	box((hx * 2 + 0.12, hy * 2 + 0.12, 0.1), (cx, cy, z1 - 0.02), 'Silver', bevel=0.035, segments=2)
	return z1 + 0.03


def swoop_gable(length, hy, base, cx=0.0, cy=0.0, rise=None, over=0.3, end_lift=0.45, thick=0.1,
		mat_name='TeamColor', nu=12, nv=8, crest=True, power=1.7):
	"""A long saddle roof whose slopes sweep concave from a flat eave up to a
	sharp ridge, and whose ridge and eaves curl up at both ends into horns.
	`base` is the eave height at the middle. Returns the ridge height."""
	half = hy + over
	rise = rise if rise is not None else half * 1.1
	L = length + 2 * over * 0.6
	bm = bmesh.new()

	def zf(u, v):
		e = (abs(u) / (L / 2)) ** 4
		return base + rise * (1 - abs(v)) ** power + end_lift * e * (0.5 + 0.5 * abs(v))

	top, bot = [], []
	for i in range(nu + 1):
		u = -L / 2 + L * i / nu
		rt_, rb_ = [], []
		for j in range(nv + 1):
			v = -1 + 2 * j / nv
			x, y, z = cx + u, cy + v * half, zf(u, v)
			rt_.append(bm.verts.new((x, y, z + thick)))
			rb_.append(bm.verts.new((x, y, z)))
		top.append(rt_)
		bot.append(rb_)
	for i in range(nu):
		for j in range(nv):
			bm.faces.new((top[i][j], top[i + 1][j], top[i + 1][j + 1], top[i][j + 1]))
			bm.faces.new((bot[i][j + 1], bot[i + 1][j + 1], bot[i + 1][j], bot[i][j]))
	for i in range(nu):
		for j in (0, nv):
			bm.faces.new((top[i][j], bot[i][j], bot[i + 1][j], top[i + 1][j]))
	for j in range(nv):
		for i in (0, nu):
			bm.faces.new((top[i][j], top[i][j + 1], bot[i][j + 1], bot[i][j]))
	_finish(_mesh_obj(bm, 'gable'), mat_name, 0.02, 2, angle=35)
	ridge = base + rise + thick
	# Silver drops on the four curled eave corners, crescents on the horns.
	for su in (-1, 1):
		for sv in (-1, 1):
			sphere(0.06, (cx + su * L / 2, cy + sv * half, zf(su * L / 2, sv) + thick * 0.5), 'Silver')
		f = face(cx + su * L / 2, cy, zf(su * L / 2, 0) + thick, '-y') @ _rz(90)
		crescent(f @ _t(0, 0, -0.02), 0.2, 0.05)
	cylinder(0.05, L * 0.9, (cx, cy, ridge + 0.01), 'Silver', verts=8, rot=(0, 90, 0), bevel=0.0)
	if crest:
		n = max(2, int(length / 0.45))
		for k in range(n):
			u = -length * 0.38 + length * 0.76 * k / max(1, n - 1)
			box((0.07, 0.06, 0.2), (cx + u, cy, zf(u, 0) + thick + 0.07), 'Silver', rot=(0, 0, 0), bevel=0.0)
			box((0.1, 0.06, 0.1), (cx + u, cy, zf(u, 0) + thick + 0.17), 'Silver', rot=(0, 45, 0), bevel=0.0)
	return ridge


def export(name, extras=()):
	"""common.export, also writing `extras` (empties such as a BeastSpot)."""
	for obj in PARTS:
		bpy.context.view_layer.objects.active = obj
		for mod in list(obj.modifiers):
			bpy.ops.object.modifier_apply(modifier=mod.name)
	bpy.ops.object.select_all(action='DESELECT')
	for obj in PARTS:
		obj.select_set(True)
	bpy.context.view_layer.objects.active = PARTS[0]
	bpy.ops.object.join()
	keep = bpy.context.active_object
	keep.name = name
	keep.data.name = name
	bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
	for e in extras:
		e.select_set(True)
	out = common.out_path(name)
	print('BUILT', name, 'faces', len(keep.data.polygons), 'dims', tuple(round(d, 2) for d in keep.dimensions), '->', out)
	bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=True)
