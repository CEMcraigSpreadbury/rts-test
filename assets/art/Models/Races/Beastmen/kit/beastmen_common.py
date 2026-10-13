# Beastmen helpers on top of the Aldmere kit (TownBuildings/kit/common.py).
#
# The Beastmen look: everything sits on a round earth mound ringed with fat
# boulders; walls are stacked logs or ochre daub on log posts lashed with rope;
# roofs are shaggy golden thatch with scalloped eaves (cones on round huts,
# stepped courses on long lodges) under a team-coloured hide draped over the
# ridge or tied round the crown; and carved totem posts with bear, boar, wolf
# and stag heads, antlered skulls, tusks and claw-marked team hides mark every
# building.
#
# A script does `from beastmen_common import *` (which also brings in all of
# common), builds, then export(name), which writes ../<Name>.glb.
import sys, os
_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.normpath(os.path.join(_HERE, '..', '..', '..', 'TownBuildings', 'kit')))
import common
from common import *
from common import _finish, _placed, _rot


def _bm_out_path(name):
	if '--' in sys.argv and len(sys.argv) > sys.argv.index('--') + 1:
		return sys.argv[sys.argv.index('--') + 1]
	return os.path.join(os.path.dirname(_HERE), name + '.glb')


common.out_path = _bm_out_path

# Warm, saturated wild colours (linear). TeamColor stays the kit's blue, the
# only thing in the team shader's hue window; nothing else here is blue.
common.COLOURS.update({
	'Thatch': (0.62, 0.34, 0.065), 'ThatchDark': (0.37, 0.175, 0.035),
	'Log': (0.24, 0.095, 0.035), 'LogB': (0.31, 0.135, 0.05), 'LogEnd': (0.69, 0.42, 0.17),
	'Daub': (0.52, 0.31, 0.13), 'Wattle': (0.34, 0.17, 0.06), 'Earth': (0.29, 0.17, 0.075),
	'Fur': (0.17, 0.085, 0.04), 'Hide': (0.62, 0.4, 0.19), 'Moss': (0.11, 0.3, 0.045),
	'Dirt': (0.17, 0.105, 0.05), 'Rope': (0.6, 0.42, 0.17), 'Berry': (0.48, 0.017, 0.05),
	'Steel': (0.36, 0.36, 0.36), 'Spirit': (0.08, 0.75, 0.3),
	'Leaf': (0.08, 0.3, 0.05), 'Leaf2': (0.045, 0.18, 0.03),
	'Stone': (0.33, 0.3, 0.265), 'StoneDark': (0.21, 0.19, 0.17),
})
common.GLOSSY = common.GLOSSY + ('Spirit', 'Steel')

# Mound top: where buildings stand.
MZ = 0.18


def _rz(deg):
	return Matrix.Rotation(math.radians(deg), 4, 'Z')


def _ry(deg):
	return Matrix.Rotation(math.radians(deg), 4, 'Y')


def _rx(deg):
	return Matrix.Rotation(math.radians(deg), 4, 'X')


def _t(x, y, z):
	return Matrix.Translation((x, y, z))


def _mesh_obj(bm, name='part'):
	mesh = bpy.data.meshes.new(name)
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
	bm.to_mesh(mesh)
	bm.free()
	obj = bpy.data.objects.new(name, mesh)
	bpy.context.scene.collection.objects.link(obj)
	return obj


def ring_solid(rb, rt, h, loc, mat_name, n=12, amp=0.0, sx=1.0, sy=1.0, bevel=0.03, angle=40, matrix=None, rot_z=0.0):
	"""A round (oval with sx/sy) solid standing on `loc`, radius rb at its foot
	and rt at its top, `h` tall. With `amp` its outline swells into n rounded
	lobes, like the trees' scallops; rt 0 makes a point."""
	bm = bmesh.new()
	k = 3 if amp else 1
	cnt = n * k
	bot, top = [], []
	for i in range(cnt):
		a = 2 * math.pi * i / cnt
		bump = math.sin(math.pi * (i % k) / k) if amp else 0.0
		r0 = rb + amp * bump
		r1 = rt + amp * bump * (rt / rb if rb > 0 else 0)
		bot.append(bm.verts.new((math.cos(a) * r0 * sx, math.sin(a) * r0 * sy, 0.0)))
		if rt > 0.001:
			top.append(bm.verts.new((math.cos(a) * r1 * sx, math.sin(a) * r1 * sy, h)))
	if rt > 0.001:
		for i in range(cnt):
			j = (i + 1) % cnt
			bm.faces.new((bot[i], bot[j], top[j], top[i]))
		bm.faces.new(top)
	else:
		apex = bm.verts.new((0, 0, h))
		for i in range(cnt):
			bm.faces.new((bot[i], bot[(i + 1) % cnt], apex))
	bm.faces.new(list(reversed(bot)))
	obj = _mesh_obj(bm, 'ring')
	_placed_m(obj, loc, rot_z, matrix)
	return _finish(obj, mat_name, bevel, 2, angle=angle)


def _placed_m(obj, loc, rot_z, matrix):
	local = _t(*loc) @ _rz(rot_z)
	obj.matrix_world = (matrix @ local) if matrix is not None else local


def scallop_slab(length, depth, thick, mat_name, frame, n=None, amp=0.08, bevel=0.035, lobes_back=False):
	"""A slab centred on `frame` in its XY plane, `thick` along Z, its -Y edge
	cut into n rounded lobes poking `amp` out (thatch bundle ends, a hide's
	ragged hem)."""
	n = n or max(2, round(length / 0.34))
	pts = [(length / 2, depth / 2), (-length / 2, depth / 2)]
	k = 4
	for i in range(n):
		for j in range(k):
			t = j / k
			pts.append((-length / 2 + length * (i + t) / n, -depth / 2 - amp * math.sin(math.pi * t)))
	pts.append((length / 2, -depth / 2))
	bm = bmesh.new()
	vs = [bm.verts.new((x, y, -thick / 2)) for x, y in pts]
	f = bm.faces.new(vs)
	ext = bmesh.ops.extrude_face_region(bm, geom=[f])
	for v in [g for g in ext['geom'] if isinstance(g, bmesh.types.BMVert)]:
		v.co.z += thick
	obj = _mesh_obj(bm, 'slab')
	obj.matrix_world = frame
	return _finish(obj, mat_name, bevel, 2, angle=35)


def boulder(x, y, z, size, mat_name='Stone', tilt=True):
	"""A fat rounded stone sitting on z."""
	rot = (random.uniform(-8, 8) if tilt else 0, random.uniform(-8, 8) if tilt else 0, random.uniform(0, 180))
	return box(size, (x, y, z + size[2] * 0.42), mat_name, rot=rot, bevel=0.42 * min(size), segments=2)


def mound(rx, ry, cx=0.0, cy=0.0, h=MZ, gap=None):
	"""The earth mound a building stands on, ringed with boulders; `gap` is an
	angle range (degrees) left clear of boulders, e.g. a doorway path."""
	ring_solid(1.0, 1.0 - 0.14 / min(rx, ry), h, (cx, cy, 0), 'Dirt', n=22, sx=rx, sy=ry, bevel=0.06, angle=30)
	ring_solid(1.0, 1.0, 0.04, (cx, cy, h - 0.02), 'Earth', n=22, sx=rx - 0.2, sy=ry - 0.2, bevel=0.02, angle=30)
	per = math.pi * (rx + ry)
	cnt = max(8, round(per / 0.5))
	for i in range(cnt):
		a = 360.0 * (i + random.uniform(-0.15, 0.15)) / cnt
		if gap and gap[0] <= (a % 360) <= gap[1]:
			continue
		ar = math.radians(a)
		s = random.uniform(0.85, 1.15)
		sz = (0.36 * s, 0.28 * s, random.uniform(0.2, 0.3))
		bx, by = cx + math.cos(ar) * (rx - 0.04), cy + math.sin(ar) * (ry - 0.04)
		boulder(bx, by, -0.04, sz, 'Stone' if random.random() < 0.6 else 'StoneDark')
		if random.random() < 0.22:
			box((sz[0] * 0.7, sz[1] * 0.7, 0.07), (bx, by, sz[2] * 0.8), 'Moss', bevel=0.03, segments=2)
	return h


def rope_band(r, x, y, z, h=0.06, n=8):
	ring_solid(r, r, h, (x, y, z - h / 2), 'Rope', n=n, bevel=0.015, angle=60)


def post(x, y, z0, h, r=0.07, mat_name='Log', tip=False, verts=8, lean=(0, 0)):
	"""An upright log, optionally sharpened."""
	m = _t(x, y, z0) @ _rx(lean[0]) @ _ry(lean[1])
	cylinder(r, h, (0, 0, h / 2), mat_name, verts=verts, bevel=0.02, matrix=m)
	if tip:
		cylinder(r, r * 2.2, (0, 0, h + r * 1.1), mat_name, verts=verts, bevel=0.0, radius2=0.0, matrix=m)
	return m


def log_x(x0, x1, y, z, r=0.1, mat_name='Log', verts=8):
	cylinder(r, x1 - x0, ((x0 + x1) / 2, y, z), mat_name, verts=verts, rot=(0, 90, 0), bevel=0.02)


def log_y(y0, y1, x, z, r=0.1, mat_name='Log', verts=8):
	cylinder(r, y1 - y0, (x, (y0 + y1) / 2, z), mat_name, verts=verts, rot=(90, 0, 0), bevel=0.02)


def log_wall_box(hx, hy, z0, z1, cx=0.0, cy=0.0, r=0.1, ext=0.14):
	"""Four walls of stacked horizontal logs, crossing at the corners like a
	cabin's, round a filled core."""
	box((hx * 2 - 0.1, hy * 2 - 0.1, z1 - z0), (cx, cy, (z0 + z1) / 2), 'Log', bevel=0.04)
	step = 2 * r * 0.95
	n = max(2, int((z1 - z0 - 2 * r) / step) + 1)
	for i in range(n):
		z = z0 + r + i * step
		m = 'LogB' if i % 2 else 'Log'
		for s in (-1, 1):
			log_x(cx - hx - ext, cx + hx + ext, cy + s * hy, z, r, m)
		if z + step / 2 < z1 - r * 0.5:
			for s in (-1, 1):
				log_y(cy - hy - ext, cy + hy + ext, cx + s * hx, z + step / 2, r, 'LogB' if i % 2 == 0 else 'Log')
	return z0 + r + (n - 1) * step + r


def thatch_cone(r, h, z, cx=0.0, cy=0.0, tiers=2, n=10, collar=True, sticks=True, rot=0.0):
	"""A shaggy conical thatch: stacked tiers, each with a scalloped eave that
	laps over the one below, a team hide tied round the crown, and smoke-hole
	sticks poking out of the top. Returns the apex height."""
	for i in range(tiers):
		y0 = h * 0.82 * i / tiers
		y1 = h * 0.82 * (i + 1) / tiers if i < tiers - 1 else h * 0.92
		rb = r * (1 - y0 / h) + (0.06 if i else 0.0)
		rt = r * (1 - y1 / h) * 0.9
		ring_solid(rb, rt, (y1 - y0) + 0.04, (cx, cy, z + y0), 'Thatch' if i % 2 == 0 else 'ThatchDark',
				n=max(6, round(n * rb / r)), amp=0.07 if i == 0 else 0.055, bevel=0.03, angle=35, rot_z=rot + i * 13)
	top_r = r * 0.08 * 0.9 + 0.04
	apex = z + h * 0.92 + 0.04
	if collar:
		# A team hide over the top tier, hugging its slope, ragged at the hem.
		def surf(y):
			return rb + (rt - rb) * (y - y0) / (y1 + 0.04 - y0)
		ya, yb = y0 + (y1 - y0) * 0.14, y0 + (y1 - y0) * 0.66
		ring_solid(surf(ya) + 0.035, surf(yb) + 0.03, yb - ya, (cx, cy, z + ya), 'TeamColor', n=max(6, round(n * 0.7)),
				amp=0.06, bevel=0.025, angle=40, rot_z=rot + 20)
		rope_band(surf(yb) + 0.04, cx, cy, z + yb, h=0.05)
	if sticks:
		for k in range(4):
			a = rot + 45 + 90 * k
			m = _t(cx, cy, apex - 0.22) @ _rz(a) @ _ry(16)
			cylinder(0.035, 0.6, (0, 0, 0.3), 'Log', verts=6, bevel=0.0, matrix=m)
	ring_solid(top_r, top_r * 0.6, 0.08, (cx, cy, apex - 0.04), 'ThatchDark', n=6, bevel=0.02)
	return apex + 0.1


def thatch_gable(length, hy, wall_top, cx=0.0, cy=0.0, pitch=46.0, over=0.32, layers=3, hx=None,
		saddle=0.38, barge=True):
	"""A long lodge's thatch: on each slope `layers` stepped courses with
	scalloped feet, a rolled thatch ridge, a team hide draped over it (covering
	`saddle` of each slope) and crossed barge boards at the gables. Returns the
	ridge height."""
	half_span = hy + over
	rise = half_span * math.tan(math.radians(pitch))
	base = wall_top - roof_drop(over, pitch)
	ridge = base + rise
	slope_len = half_span / math.cos(math.radians(pitch))
	for s in (-1, 1):
		frame = _t(cx, cy + s * half_span / 2, base + rise / 2 + 0.08) @ _rx(pitch * -s)
		if s == 1:
			frame = frame @ _rz(180)
		for k in range(layers):
			depth = (slope_len + 0.08) * (1 - 0.27 * k)
			v = (slope_len + 0.08) / 2 - depth / 2
			scallop_slab(length + 0.04 - 0.02 * k, depth, 0.16, 'Thatch' if k % 2 == 0 else 'ThatchDark',
					frame @ _t(0, v, 0.075 * k), amp=0.09)
		if saddle:
			depth = slope_len * saddle
			v = slope_len / 2 - depth / 2 + 0.04
			scallop_slab(length * 0.62, depth, 0.07, 'TeamColor', frame @ _t(0, v, 0.075 * (layers - 1) + 0.1),
					n=4, amp=0.13)
	cylinder(0.17, length + 0.1, (cx, cy, ridge + 0.12), 'ThatchDark', verts=10, rot=(0, 90, 0), bevel=0.05)
	for x in (-length * 0.31, 0.0, length * 0.31):
		cylinder(0.19, 0.08, (cx + x, cy, ridge + 0.12), 'Rope', verts=10, rot=(0, 90, 0), bevel=0.02)
	for end in (-1, 1):
		if hx is not None:
			bm = bmesh.new()
			pts = [(cy - hy, wall_top - 0.02), (cy + hy, wall_top - 0.02),
					(cy, wall_top + hy * math.tan(math.radians(pitch)))]
			vs = [bm.verts.new((cx + end * (hx - 0.02), py, pz)) for py, pz in pts]
			f = bm.faces.new(vs)
			ext = bmesh.ops.extrude_face_region(bm, geom=[f])
			for v in [g for g in ext['geom'] if isinstance(g, bmesh.types.BMVert)]:
				v.co.x += end * 0.08
			_finish(_mesh_obj(bm, 'gable'), 'Daub', 0.02, 2)
		if barge:
			x = cx + end * (length / 2 + 0.05)
			for s in (-1, 1):
				# Each board runs up its slope and on past the ridge, so the
				# pair cross in an X over the gable.
				m = _t(x, cy + s * half_span / 2, base + rise / 2 + 0.12) @ _rx(pitch * -s)
				box((0.13, slope_len + 0.75, 0.13), (0, -s * 0.33, 0), 'Log', bevel=0.04, matrix=m)
	return ridge


def thatch_shed(width, run, x, y, z_high, side='-y', pitch=22.0, saddle=True):
	"""A lean-to thatch running down from a high edge at (x, y, z_high) out
	toward `side`. Returns the low edge height."""
	rise = run * math.tan(math.radians(pitch))
	slope_len = run / math.cos(math.radians(pitch))
	frame = face(x, y, z_high, side) @ _t(0, -run / 2, -rise / 2 + 0.07) @ _rx(pitch)
	for k in range(2):
		depth = (slope_len + 0.1) * (1 - 0.35 * k)
		v = (slope_len + 0.1) / 2 - depth / 2
		scallop_slab(width - 0.03 * k, depth, 0.15, 'Thatch' if k == 0 else 'ThatchDark', frame @ _t(0, v, 0.075 * k), amp=0.09)
	if saddle:
		scallop_slab(width * 0.3, slope_len * 0.85, 0.06, 'TeamColor', frame @ _t(0, 0.05, 0.17), n=2, amp=0.14)
	return z_high - rise


# --- ornaments ------------------------------------------------------------
def antlers(frame, s=1.0, mat_name='Antler'):
	"""A pair of branching antlers rising from `frame`'s origin."""
	for side in (-1, 1):
		b = frame @ _t(side * 0.06 * s, 0, 0) @ _ry(side * 38)
		box((0.085 * s, 0.085 * s, 0.85 * s), (0, 0, 0.42 * s), mat_name, bevel=0.03 * s, segments=2, matrix=b)
		for zz, ang, fwd in ((0.3, -55, 25), (0.58, -48, 0)):
			tine = b @ _t(0, 0, zz * s) @ _ry(-side * ang) @ _rx(fwd)
			box((0.07 * s, 0.07 * s, 0.34 * s), (0, 0, 0.16 * s), mat_name, bevel=0.025 * s, segments=2, matrix=tine)
		tip = b @ _t(0, 0, 0.82 * s) @ _ry(side * 22)
		box((0.07 * s, 0.07 * s, 0.3 * s), (0, 0, 0.14 * s), mat_name, bevel=0.025 * s, segments=2, matrix=tip)


def tusk(frame, s=1.0, side=1, mat_name='Bone'):
	"""A curling tusk growing out toward `side` and up."""
	cur = frame @ _ry(side * 75)
	r = 0.06 * s
	for i in range(3):
		ln = 0.16 * s
		cylinder(r, ln, (0, 0, ln / 2), mat_name, verts=6, bevel=0.0, radius2=r * 0.72, matrix=cur)
		cur = cur @ _t(0, 0, ln * 0.92) @ _ry(-side * 38)
		r *= 0.72
	cylinder(r, 0.12 * s, (0, 0, 0.06 * s), mat_name, verts=6, bevel=0.0, radius2=0.0, matrix=cur)


def skull(frame, s=1.0, horns='antlers'):
	"""A bleached beast skull facing out of `frame` (-Y), antlered or tusked."""
	box((0.5 * s, 0.46 * s, 0.4 * s), (0, 0, 0), 'Bone', bevel=0.12 * s, segments=2, matrix=frame)
	box((0.3 * s, 0.4 * s, 0.24 * s), (0, -0.34 * s, -0.08 * s), 'Bone', bevel=0.08 * s, segments=2, matrix=frame)
	for sx in (-1, 1):
		box((0.13 * s, 0.05 * s, 0.11 * s), (sx * 0.13 * s, -0.22 * s, 0.03 * s), 'Window', bevel=0.03 * s,
				segments=2, matrix=frame)
	box((0.12 * s, 0.05 * s, 0.06 * s), (0, -0.53 * s, -0.04 * s), 'Window', bevel=0.02 * s, segments=2, matrix=frame)
	if horns == 'antlers':
		antlers(frame @ _t(0, 0.02 * s, 0.16 * s), s * 0.7)
	elif horns == 'tusks':
		for sx in (-1, 1):
			tusk(frame @ _t(sx * 0.13 * s, -0.42 * s, -0.12 * s), s * 0.8, sx)


def claw_marks(frame, h=0.4, mat_name='Bone'):
	"""Three raked slashes across the face in front of `frame`."""
	for i in (-1, 0, 1):
		box((0.05, 0.03, h * (0.85 if i else 1.0)), (i * h * 0.26, -0.035, i * -0.02), mat_name, rot=(0, 22, 0),
				bevel=0.012, segments=2, matrix=frame)


def hide_banner(w, h, frame, claws=True):
	"""A team-dyed hide hanging from a log bar whose centre is `frame`: ragged
	foot, pelt legs at the corners, raked with claw marks."""
	cylinder(0.05, w + 0.24, (0, 0, 0), 'Log', verts=8, rot=(0, 90, 0), bevel=0.02, matrix=frame)
	for sx in (-1, 1):
		box((0.07, 0.13, 0.13), (sx * (w / 2 - 0.05), 0, 0), 'Rope', bevel=0.025, segments=2, matrix=frame)
	scallop_slab(w, h, 0.05, 'TeamColor', frame @ _t(0, -0.01, -h / 2 - 0.03) @ _rx(-90), n=3, amp=0.1)
	for sx in (-1, 1):
		box((0.1, 0.05, 0.22), (sx * (w / 2 - 0.02), -0.01, -h - 0.06), 'TeamColor', rot=(0, -sx * 18, 0), bevel=0.02,
				segments=2, matrix=frame)
	if claws:
		claw_marks(frame @ _t(0, -0.01, -h * 0.52), h=min(w, h) * 0.6)


def head(kind, frame, s=0.36):
	"""One carved, painted totem head sitting on `frame`'s origin, facing -Y.
	Returns its height."""
	col = {'bear': 'Fur', 'boar': 'Red', 'wolf': 'Stone', 'stag': 'Daub'}[kind]
	hh = s * 0.82
	box((s, s * 0.86, hh), (0, 0, hh / 2), col, bevel=0.07 * s / 0.36, segments=2, matrix=frame)
	for sx in (-1, 1):
		box((s * 0.17, 0.04, s * 0.1), (sx * s * 0.21, -s * 0.43, hh * 0.64), 'Bone', bevel=0.012, segments=2, matrix=frame)
		box((s * 0.07, 0.04, s * 0.07), (sx * s * 0.21, -s * 0.45, hh * 0.64), 'Window', bevel=0.01, segments=2, matrix=frame)
	if kind == 'bear':
		box((s * 0.46, s * 0.3, s * 0.3), (0, -s * 0.5, hh * 0.3), 'Daub', bevel=0.05 * s / 0.36, segments=2, matrix=frame)
		box((s * 0.16, 0.06, s * 0.1), (0, -s * 0.66, hh * 0.38), 'Window', bevel=0.02, segments=2, matrix=frame)
		for sx in (-1, 1):
			cylinder(s * 0.15, s * 0.12, (sx * s * 0.36, 0, hh + s * 0.08), col, verts=10, rot=(90, 0, 0), bevel=0.02, matrix=frame)
	elif kind == 'boar':
		cylinder(s * 0.17, s * 0.26, (0, -s * 0.52, hh * 0.32), 'Daub', verts=10, rot=(90, 0, 0), bevel=0.02, matrix=frame)
		for sx in (-1, 1):
			tusk(frame @ _t(sx * s * 0.2, -s * 0.5, hh * 0.18), s * 1.5, sx)
			pyramid(s * 0.22, s * 0.26, (sx * s * 0.34, 0, hh - 0.01), col, matrix=frame)
	elif kind == 'wolf':
		box((s * 0.34, s * 0.46, s * 0.26), (0, -s * 0.58, hh * 0.3), col, bevel=0.04 * s / 0.36, segments=2, matrix=frame)
		box((s * 0.14, 0.06, s * 0.1), (0, -s * 0.82, hh * 0.38), 'Window', bevel=0.02, segments=2, matrix=frame)
		for sx in (-1, 1):
			pyramid(s * 0.28, s * 0.36, (sx * s * 0.3, 0, hh - 0.01), col, matrix=frame)
	elif kind == 'stag':
		box((s * 0.3, s * 0.36, s * 0.3), (0, -s * 0.5, hh * 0.32), col, bevel=0.04 * s / 0.36, segments=2, matrix=frame)
		box((s * 0.14, 0.06, s * 0.1), (0, -s * 0.69, hh * 0.4), 'Window', bevel=0.02, segments=2, matrix=frame)
		antlers(frame @ _t(0, 0, hh - 0.02), s * 1.4)
	# A war-paint stripe across the brow.
	box((s * 1.02, s * 0.88, s * 0.07), (0, 0, hh * 0.86), 'Thatch' if col == 'Red' else 'Red', bevel=0.02, segments=2,
			matrix=frame)
	return hh


def totem(x, y, z0, heads, s=0.36, side='-y', top=None, band=True):
	"""A carved post of stacked animal heads, bottom to top, with a team band
	and an optional crown ('antlers', 'skull', 'hide'). Returns its top."""
	f = face(x, y, z0, side)
	z = 0.32
	cylinder(s * 0.36, z + 0.05, (0, 0, (z + 0.05) / 2), 'Log', verts=10, bevel=0.02, matrix=f)
	for i, k in enumerate(heads):
		z += head(k, f @ _t(0, 0, z), s) + 0.01
		if band and i == len(heads) - 2:
			ring_solid(s * 0.5, s * 0.5, s * 0.16, (0, 0, z), 'TeamColor', n=10, bevel=0.02, angle=45, matrix=f)
			z += s * 0.16
	if top == 'antlers':
		antlers(f @ _t(0, 0, z), s * 1.5)
	elif top == 'skull':
		skull(f @ _t(0, 0, z + s * 0.2), s * 1.1)
	return z0 + z


def doorway(frame, w=0.5, h=0.75, flap=True):
	"""A dark opening in a log frame on `frame` (bottom centre), a hide flap
	half drawn aside and an antlered skull over the lintel."""
	box((w, 0.08, h), (0, 0.02, h / 2), 'Window', bevel=0.03, matrix=frame)
	for sx in (-1, 1):
		cylinder(0.07, h + 0.1, (sx * (w / 2 + 0.05), -0.04, (h + 0.1) / 2), 'Log', verts=8, bevel=0.02, matrix=frame)
	cylinder(0.08, w + 0.34, (0, -0.05, h + 0.08), 'Log', verts=8, rot=(0, 90, 0), bevel=0.02, matrix=frame)
	if flap:
		box((w * 0.5, 0.05, h * 0.92), (-w * 0.26, -0.06, h * 0.52), 'Fur', rot=(0, 0, 6), bevel=0.025, segments=2,
				matrix=frame)
		box((w * 0.16, 0.06, h * 0.7), (w * 0.4, -0.06, h * 0.55), 'Fur', bevel=0.025, segments=2, matrix=frame)
		box((0.06, 0.08, 0.08), (w * 0.3, -0.1, h * 0.5), 'Rope', bevel=0.02, segments=2, matrix=frame)


def firepit(x, y, z):
	for k in range(7):
		a = 2 * math.pi * k / 7
		boulder(x + math.cos(a) * 0.24, y + math.sin(a) * 0.24, z - 0.02, (0.15, 0.13, 0.12), 'StoneDark', tilt=False)
	for a in (0, 60, 120):
		box((0.42, 0.07, 0.07), (x, y, z + 0.07), 'Log', rot=(0, 0, a), bevel=0.025, segments=2)
	ring_solid(0.14, 0.0, 0.26, (x, y, z + 0.05), 'Ember', n=6, amp=0.04, bevel=0.0)


def log_pile(x, y, z, length, rows=3, r=0.1, axis='x'):
	"""Logs stacked in a pyramid, cut ends showing."""
	for row in range(rows):
		cnt = rows - row
		for i in range(cnt):
			o = (i - (cnt - 1) / 2) * r * 2.02
			zz = z + r + row * r * 1.75
			if axis == 'x':
				cylinder(r, length, (x, y + o, zz), 'Log' if (i + row) % 2 else 'LogB', verts=8, rot=(0, 90, 0), bevel=0.02)
				for e in (-1, 1):
					cylinder(r * 0.82, 0.02, (x + e * (length / 2 + 0.004), y + o, zz), 'LogEnd', verts=8, rot=(0, 90, 0), bevel=0.0)
			else:
				cylinder(r, length, (x + o, y, zz), 'Log' if (i + row) % 2 else 'LogB', verts=8, rot=(90, 0, 0), bevel=0.02)
				for e in (-1, 1):
					cylinder(r * 0.82, 0.02, (x + o, y + e * (length / 2 + 0.004), zz), 'LogEnd', verts=8, rot=(90, 0, 0), bevel=0.0)


def basket(x, y, z, r=0.17, h=0.22, fill='Berry'):
	ring_solid(r * 0.85, r, h, (x, y, z), 'Wattle', n=8, bevel=0.02, angle=50)
	rope_band(r * 0.96, x, y, z + h * 0.7, h=0.035)
	if fill:
		for k in range(4):
			a = 2 * math.pi * k / 4 + 0.4
			sphere(r * 0.38, (x + math.cos(a) * r * 0.45, y + math.sin(a) * r * 0.45, z + h), fill)
		sphere(r * 0.4, (x, y, z + h + r * 0.2), fill)


def stakes(x0, y0, x1, y1, z0, h, spacing=0.24, r=0.07, rails=True):
	"""A row of sharpened stakes lashed to two rope rails."""
	length = math.hypot(x1 - x0, y1 - y0)
	n = max(2, round(length / spacing) + 1)
	for i in range(n):
		t = i / (n - 1)
		hh = h * random.uniform(0.88, 1.06)
		post(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, z0, hh, r=r, mat_name='Log' if i % 2 else 'LogB', tip=True, verts=6)
	if rails:
		ang = math.degrees(math.atan2(y1 - y0, x1 - x0))
		for zz in (h * 0.3, h * 0.7):
			box((length, r * 2.6, 0.06), ((x0 + x1) / 2, (y0 + y1) / 2, z0 + zz), 'Rope', rot=(0, 0, ang), bevel=0.02, segments=2)
