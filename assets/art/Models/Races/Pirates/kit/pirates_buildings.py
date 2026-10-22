# Builds every Pirates building (Races/Pirates/*.glb) on top of the Aldmere kit
# (TownBuildings/kit/common.py): a toy pirate playset. Everything stands on a
# plank deck over a sand bank; walls are horizontal ship's boards, roofs are
# patched sail canvas in the team's colour, and every building carries the
# race's props: barrels, rope, portholes, cannons, palm trees, treasure, the
# Jolly Roger. The Town Centre is a beached galleon.
#
#	blender --background --factory-startup --python pirates_buildings.py [-- Name ...]
#
# With no names every building is built.
import sys, os
_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.normpath(os.path.join(_HERE, '..', '..', '..', 'TownBuildings', 'kit')))
import common
from common import *
from common import _finish, _placed, _rot
import bmesh


def _out_path(name):
	return os.path.join(os.path.dirname(_HERE), name + '.glb')


common.out_path = _out_path

# Linear colours. TeamColor stays the kit's blue, alone in the team shader's
# hue window: no sea, no blue paint. The gables' 'Plaster' is sun-bleached
# plank here, the plinth 'Stone' sandstone.
common.COLOURS.update({
	'Sand': (0.62, 0.47, 0.25), 'SandDark': (0.43, 0.3, 0.15),
	'Plank': (0.3, 0.15, 0.06), 'PlankLight': (0.46, 0.27, 0.11), 'PlankDark': (0.15, 0.07, 0.025),
	'Plaster': (0.46, 0.27, 0.11), 'Canvas': (0.8, 0.73, 0.56), 'Rope': (0.6, 0.42, 0.17),
	'Black': (0.025, 0.022, 0.025), 'Palm': (0.07, 0.3, 0.04), 'PalmDark': (0.04, 0.18, 0.025),
	'Trunk': (0.33, 0.19, 0.08), 'Coconut': (0.17, 0.08, 0.03), 'Shell': (0.85, 0.55, 0.45),
	'Juju': (0.34, 0.08, 0.69), 'Coral': (0.85, 0.24, 0.05), 'Fish': (0.6, 0.62, 0.6), 'Ember': (1.0, 0.25, 0.02),
	'Stone': (0.4, 0.33, 0.22), 'StoneDark': (0.26, 0.21, 0.14),
})
common.GLOSSY = common.GLOSSY + ('Juju', 'Fish')

DZ = 0.28


def _t(x, y, z):
	return Matrix.Translation((x, y, z))


def _rz(d):
	return Matrix.Rotation(math.radians(d), 4, 'Z')


# --- ground ----------------------------------------------------------------

def deck(px, py, cx=0.0, cy=0.0, posts=True):
	"""A sand bank under a plank deck: planks along X with a gap between, a
	dark frame round the edge and stubby round posts at the corners."""
	box((px * 2 + 0.3, py * 2 + 0.3, 0.14), (cx, cy, 0.07), 'Sand', bevel=0.07)
	for i in range(7):
		a = random.uniform(0, 6.28)
		r = random.uniform(0.85, 1.05)
		sphere(random.uniform(0.07, 0.12), (cx + math.cos(a) * (px + 0.12) * r, cy + math.sin(a) * (py + 0.12) * r, 0.1),
				'SandDark' if i % 2 else 'Shell')
	box((px * 2, py * 2, 0.08), (cx, cy, 0.18), 'PlankDark', bevel=0.03)
	n = max(3, round(py * 2 / 0.3))
	w = py * 2 / n
	for i in range(n):
		y = cy - py + w * (i + 0.5)
		box((px * 2 - 0.08, w - 0.035, 0.07), (cx, y, DZ - 0.04), 'Plank' if i % 3 else 'PlankLight', bevel=0.02, segments=2)
	if posts:
		for sx in (-1, 1):
			for sy in (-1, 1):
				cylinder(0.09, 0.36, (cx + sx * (px - 0.02), cy + sy * (py - 0.02), 0.2), 'PlankDark', verts=8, bevel=0.02)
	return DZ


# --- walls and roofs ---------------------------------------------------------

def plank_walls(hx, hy, top, cx=0.0, cy=0.0, z0=DZ, board=0.22):
	"""A box of horizontal ship's boards, each a little proud and a little
	askew, dark corner posts with rope lashings."""
	box((hx * 2, hy * 2, top - z0), (cx, cy, (top + z0) / 2), 'PlankDark', bevel=0.03)
	rows = max(2, round((top - z0) / board))
	h = (top - z0) / rows
	for side in ('-y', '+y', '-x', '+x'):
		half_w = hx if side in ('-y', '+y') else hy
		f = face(cx + (hx if side == '+x' else -hx if side == '-x' else 0),
				cy + (hy if side == '+y' else -hy if side == '-y' else 0), 0, side)
		for r in range(rows):
			m = ('Plank', 'PlankLight', 'Plank')[r % 3]
			box((half_w * 2 - 0.04, 0.07, h - 0.025), (random.uniform(-0.02, 0.02), -0.02, z0 + h * (r + 0.5)), m,
					rot=(0, random.uniform(-1.2, 1.2), 0), bevel=0.02, segments=2, matrix=f)
	for sx in (-1, 1):
		for sy in (-1, 1):
			x, y = cx + sx * hx, cy + sy * hy
			cylinder(0.1, top - z0 + 0.12, (x, y, (top + z0) / 2 + 0.06), 'PlankDark', verts=8, bevel=0.02)
			for z in (z0 + 0.35, top - 0.25):
				cylinder(0.115, 0.07, (x, y, z), 'Rope', verts=8, bevel=0.01)


def sail_roof(length, hy, wall_top, cx=0.0, cy=0.0, pitch=36.0, over=0.28, hx=None):
	"""A gable roof of patched sail canvas in the team's colour, a ridge
	pole and plank gables."""
	ridge = gable_roof(length, hy, wall_top, cx=cx, cy=cy, pitch=pitch, over=over, tile_rows=3, hx=hx,
			tile_mats=('TeamColor', 'TeamColor', 'Canvas'))
	return ridge


def tarp(w, d, z, cx, cy, sag=0.12, posts=True, mat='TeamColor'):
	"""A canvas awning on four posts, its middle sagging."""
	mesh = bpy.data.meshes.new('tarp')
	bm = bmesh.new()
	nx, ny = 6, 5
	vs = {}
	for i in range(nx + 1):
		for j in range(ny + 1):
			u, v = i / nx, j / ny
			s = math.sin(math.pi * u) * math.sin(math.pi * v)
			vs[i, j] = bm.verts.new((cx - w / 2 + w * u, cy - d / 2 + d * v, z - sag * s))
	for i in range(nx):
		for j in range(ny):
			bm.faces.new((vs[i, j], vs[i + 1, j], vs[i + 1, j + 1], vs[i, j + 1]))
	bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=0.05)
	bm.to_mesh(mesh)
	bm.free()
	obj = bpy.data.objects.new('tarp', mesh)
	bpy.context.scene.collection.objects.link(obj)
	_finish(obj, mat, 0.015, 2)
	if posts:
		for sx in (-1, 1):
			for sy in (-1, 1):
				cylinder(0.06, z - DZ, (cx + sx * (w / 2 - 0.05), cy + sy * (d / 2 - 0.05), (z + DZ) / 2), 'PlankDark',
						verts=8, bevel=0.0)


def canvas_roof(w, d, z_eave, cx, cy, pitch=24.0):
	"""A peaked canvas roof on four posts: a ridge along X, patched sail cloth
	in the team's colour."""
	ridge = gable_roof(w, d / 2 - 0.1, z_eave, cx=cx, cy=cy, pitch=pitch, over=0.1, tile_rows=2,
			tile_mats=('TeamColor', 'TeamColor', 'Canvas'))
	for sx in (-1, 1):
		for sy in (-1, 1):
			cylinder(0.06, z_eave - DZ, (cx + sx * (w / 2 - 0.08), cy + sy * (d / 2 - 0.12), (z_eave + DZ) / 2),
					'PlankDark', verts=8, bevel=0.0)
	return ridge


def porthole(frame, r=0.17):
	"""A round window in a thick brass ring."""
	torus(r, 0.045, (0, -0.04, 0), 'Gold', rot=(90, 0, 0), matrix=frame)
	cylinder(r, 0.06, (0, -0.0, 0), 'Window', verts=14, rot=(90, 0, 0), bevel=0.0, matrix=frame)


def plank_door(frame, w=0.6, h=0.95):
	door(frame, w=w, h=h)


# --- props ------------------------------------------------------------------

def jolly_roger(x, y, z, pole=1.1, size=0.5):
	"""A tall pole flying the black flag: a bone skull over crossed bones."""
	cylinder(0.04, pole, (x, y, z + pole / 2), 'PlankDark', verts=8, bevel=0.0)
	sphere(0.06, (x, y, z + pole + 0.04), 'Gold')
	fz = z + pole - size * 0.4
	box((size, 0.035, size * 0.66), (x + size / 2 + 0.04, y, fz), 'Black', bevel=0.012)
	f = Matrix.Translation((x + size / 2 + 0.04, y - 0.025, fz))
	sphere(size * 0.13, (0, 0, size * 0.06), 'Bone', matrix=f)
	box((size * 0.16, 0.03, size * 0.1), (0, 0, -size * 0.05), 'Bone', bevel=0.01, matrix=f)
	for a in (35, -35):
		box((size * 0.5, 0.03, size * 0.06), (0, 0, -size * 0.12), 'Bone', rot=(0, a, 0), bevel=0.01, matrix=f)
	for side in (-1, 1):
		box((size * 0.05, 0.04, size * 0.05), (side * size * 0.05, -0.005, size * 0.07), 'Black', bevel=0.005, matrix=f)


def chest(x, y, z, rot=0.0, gold=True):
	"""A treasure chest, its lid thrown back over a heap of gold."""
	f = _t(x, y, z) @ _rz(rot)
	box((0.5, 0.34, 0.26), (0, 0, 0.13), 'Plank', bevel=0.04, matrix=f)
	for xx in (-0.17, 0.17):
		box((0.06, 0.36, 0.28), (xx, 0, 0.14), 'Gold', bevel=0.015, matrix=f)
	box((0.5, 0.1, 0.32), (0, 0.2, 0.36), 'Plank', rot=(-20, 0, 0), bevel=0.04, matrix=f)
	if gold:
		for i in range(7):
			sphere(random.uniform(0.06, 0.09), (random.uniform(-0.17, 0.17), random.uniform(-0.1, 0.1), 0.26 +
					random.uniform(0, 0.06)), 'Gold', matrix=f)
		sphere(0.05, (0.0, -0.03, 0.36), 'Orb', matrix=f)


def palm(x, y, z, h=2.3, lean=12.0, seed=0):
	"""A toy palm: a curved trunk of stacked rings, a crown of drooping
	fronds and coconuts under them."""
	rng = random.Random(seed)
	n = 8
	dirx = math.cos(math.radians(seed * 77))
	diry = math.sin(math.radians(seed * 77))
	top = None
	for i in range(n):
		t = (i + 0.5) / n
		off = math.sin(math.radians(lean)) * h * t * t
		p = (x + dirx * off, y + diry * off, z + h * t)
		cylinder(0.12 - 0.035 * t, h / n + 0.02, p, 'Trunk' if i % 2 else 'Plank', verts=8, bevel=0.03,
				rot=(lean * t * diry * -1, lean * t * dirx, 0))
		top = p
	cx, cy, cz = top[0], top[1], top[2] + 0.08
	for k in range(7):
		a = k * 360.0 / 7 + rng.uniform(-10, 10)
		f = _t(cx, cy, cz) @ _rz(a)
		box((0.75, 0.22, 0.05), (0.38, 0, -0.08), 'Palm' if k % 2 else 'PalmDark', rot=(0, 22, 0), bevel=0.02, matrix=f)
		box((0.45, 0.16, 0.05), (0.85, 0, -0.32), 'Palm' if k % 2 else 'PalmDark', rot=(0, 48, 0), bevel=0.02, matrix=f)
	for k in range(3):
		a = math.radians(k * 120 + 30)
		sphere(0.09, (cx + math.cos(a) * 0.13, cy + math.sin(a) * 0.13, cz - 0.12), 'Coconut')


def cannon(x, y, z, rot=0.0, scale=1.0):
	"""A black ship's cannon on a little wooden truck, muzzle to the front."""
	s = scale
	f = _t(x, y, z) @ _rz(rot)
	box((0.36 * s, 0.6 * s, 0.16 * s), (0, 0, 0.16 * s), 'Plank', bevel=0.03, matrix=f)
	for xx in (-0.2 * s, 0.2 * s):
		for yy in (-0.2 * s, 0.2 * s):
			cylinder(0.1 * s, 0.07 * s, (xx, yy, 0.1 * s), 'PlankDark', verts=10, rot=(0, 90, 0), bevel=0.01, matrix=f)
	cylinder(0.13 * s, 0.75 * s, (0, -0.15 * s, 0.34 * s), 'IronDark', verts=12, radius2=0.1 * s, rot=(90, 0, 0),
			bevel=0.02, matrix=f)
	torus(0.11 * s, 0.03 * s, (0, -0.52 * s, 0.34 * s), 'IronDark', rot=(90, 0, 0), matrix=f)
	sphere(0.09 * s, (0, 0.24 * s, 0.34 * s), 'IronDark', matrix=f)


def rope_coil(x, y, z):
	for k in range(3):
		torus(0.16 - k * 0.02, 0.035, (x, y, z + 0.035 + k * 0.05), 'Rope')


def lantern(x, y, z):
	box((0.14, 0.14, 0.18), (x, y, z), 'Ember', bevel=0.03)
	box((0.18, 0.18, 0.04), (x, y, z + 0.11), 'IronDark', bevel=0.015)
	box((0.16, 0.16, 0.03), (x, y, z - 0.1), 'IronDark', bevel=0.01)


def barrels(x, y, z, n=3, seed=1):
	rng = random.Random(seed)
	for i in range(n):
		a = i * 2.1
		barrel(x + math.cos(a) * 0.22 * (i > 0), y + math.sin(a) * 0.22 * (i > 0), z=z, r=0.17, h=0.4)
	if n >= 3:
		barrel(x + 0.1, y + 0.05, z=z + 0.4, r=0.16, h=0.36)


def skull_post(x, y, z, h=0.9):
	cylinder(0.05, h, (x, y, z + h / 2), 'PlankDark', verts=8, bevel=0.0)
	sphere(0.12, (x, y, z + h + 0.06), 'Bone')
	box((0.13, 0.1, 0.08), (x, y - 0.03, z + h - 0.03), 'Bone', bevel=0.02)
	for side in (-1, 1):
		sphere(0.035, (x + side * 0.045, y - 0.1, z + h + 0.07), 'Black')


def mast(x, y, z, h, yard=1.4, sail=True, nest=True, flag=True):
	"""A mast with a yard, a square team sail bellied forward, a crow's nest."""
	cylinder(0.09, h, (x, y, z + h / 2), 'Plank', verts=10, bevel=0.02)
	yz = z + h * 0.72
	cylinder(0.05, yard, (x, y, yz), 'PlankDark', verts=8, rot=(0, 90, 0), bevel=0.0)
	if sail:
		mesh = bpy.data.meshes.new('sail')
		bm = bmesh.new()
		nx, nz = 6, 5
		sh = h * 0.42
		vs = {}
		for i in range(nx + 1):
			for j in range(nz + 1):
				u, v = i / nx, j / nz
				belly = 0.22 * math.sin(math.pi * u) * math.sin(math.pi * v * 0.9 + 0.2)
				vs[i, j] = bm.verts.new((x - yard * 0.45 + yard * 0.9 * u, y - 0.1 - belly, yz - 0.06 - sh * v))
		for i in range(nx):
			for j in range(nz):
				bm.faces.new((vs[i, j], vs[i, j + 1], vs[i + 1, j + 1], vs[i + 1, j]))
		bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=0.04)
		bm.to_mesh(mesh)
		bm.free()
		obj = bpy.data.objects.new('sail', mesh)
		bpy.context.scene.collection.objects.link(obj)
		_finish(obj, 'TeamColor', 0.012, 2)
		# A bone-white skull painted on the sail.
		f = _t(x, y - 0.36, yz - sh * 0.45)
		sphere(0.13, (0, 0, 0.03), 'Bone', matrix=f)
		for a in (35, -35):
			box((0.42, 0.03, 0.05), (0, 0, -0.12), 'Bone', rot=(0, a, 0), bevel=0.01, matrix=f)
	if nest:
		nz_ = z + h - 0.25
		cylinder(0.3, 0.26, (x, y, nz_), 'Plank', verts=12, bevel=0.03)
		torus(0.3, 0.035, (x, y, nz_ + 0.13), 'Rope')
	if flag:
		jolly_roger(x, y, z + h, pole=0.5, size=0.45)


# --- buildings ---------------------------------------------------------------

# --- the Pirate Haven: a galleon beached on its side ---------------------------

def _mesh_obj(name, verts, faces, mat_name, bevel=0.0):
	mesh = bpy.data.meshes.new(name)
	mesh.from_pydata(verts, [], faces)
	mesh.update()
	obj = bpy.data.objects.new(name, mesh)
	bpy.context.scene.collection.objects.link(obj)
	return _finish(obj, mat_name, bevel, 2)


class Galleon:
	"""A toy galleon's hull shape in its own space: the keel along X at z 0
	(bow toward +X), the deck's edge at `depth` rising toward bow and stern."""

	def __init__(self, length, beam, depth):
		self.L, self.B, self.D = length, beam, depth

	def half_width(self, t):
		"""Across the beam at t (-1 stern .. 1 bow): blunt at the stern, a
		pointed bow."""
		if t >= 0.0:
			return self.B * 0.5 * max(0.0, 1.0 - t ** 1.7) ** 0.75
		return self.B * 0.5 * max(0.0, 1.0 - abs(t) ** 4.0) ** 0.5 * (0.82 + 0.18 * (1.0 + t))

	def deck_z(self, t):
		return self.D + 0.28 * t * t + (0.18 * t * t if t < 0.0 else 0.0)

	def keel_z(self, t):
		return 0.35 * abs(t) ** 3.0

	def point(self, t, a):
		"""The hull's surface at t, round its cross-section by a (-pi/2 port
		rail, 0 keel, pi/2 starboard rail)."""
		x = t * self.L * 0.5
		y = math.sin(a) * self.half_width(t)
		top, bottom = self.deck_z(t), self.keel_z(t)
		z = top - math.cos(a) * (top - bottom)
		return (x, y, z)


# Bands down the hull from the rail, as fractions of its depth (cos a): a
# dark gunwale, the team's stripe, a dark wale; planking between in two tones.
HULL_BANDS = [(0.0, 0.10, 'PlankDark'), (0.10, 0.22, 'Plank'), (0.22, 0.32, 'TeamColor'), (0.32, 0.46, 'PlankLight'),
		(0.46, 0.54, 'PlankDark'), (0.54, 0.72, 'Plank'), (0.72, 1.0, 'PlankLight')]


def galleon_hull(g, nt=28, na=10):
	"""The hull in its bands (one object each, so each takes its material),
	each band a little proud of the one below it, and a keel strip."""
	ts = [-0.995 + 1.99 * i / nt for i in range(nt + 1)]
	for c0, c1, mat_name in HULL_BANDS:
		proud = 0.025 if mat_name in ('PlankDark', 'TeamColor') else 0.0
		verts, faces = [], []
		steps = max(2, round((c1 - c0) * na))
		for side in (-1.0, 1.0):
			base = len(verts)
			for i, t in enumerate(ts):
				for j in range(steps + 1):
					c = c0 + (c1 - c0) * j / steps
					a = side * math.acos(max(-1.0, min(1.0, c)))
					x, y, z = g.point(t, a)
					w = g.half_width(t)
					verts.append((x, y + side * proud * (1.0 if w > 0.05 else 0.0), z))
			cols = steps + 1
			for i in range(nt):
				for j in range(steps):
					v0 = base + i * cols + j
					quad = (v0, v0 + cols, v0 + cols + 1, v0 + 1)
					faces.append(quad if side > 0 else tuple(reversed(quad)))
		_mesh_obj('hull', verts, faces, mat_name)
	keel = [(t * g.L * 0.5, 0.0, g.keel_z(t) - 0.04) for t in ts]
	for p0, p1 in zip(keel, keel[1:]):
		d = Vector(p1) - Vector(p0)
		box((0.1, d.length + 0.02, 0.1), ((p0[0] + p1[0]) / 2, 0, (p0[2] + p1[2]) / 2), 'PlankDark',
				rot=(0, -math.degrees(math.atan2(d.z, d.x)), 90), bevel=0.02)


def galleon_deck(g, nt=24):
	"""Deck planks inside the rail, a hand's depth below it, laid along X in
	strakes of two tones."""
	strakes = 6
	for s in range(strakes):
		u0, u1 = -1.0 + 2.0 * s / strakes, -1.0 + 2.0 * (s + 1) / strakes
		verts, faces = [], []
		for i in range(nt + 1):
			t = -0.97 + 1.94 * i / nt
			w = g.half_width(t) * 0.94
			z = g.deck_z(t) - 0.16
			verts += [(t * g.L * 0.5, u0 * w, z), (t * g.L * 0.5, u1 * w, z)]
		for i in range(nt):
			faces.append((2 * i, 2 * i + 2, 2 * i + 3, 2 * i + 1))
		_mesh_obj('deck', verts, faces, 'PlankLight' if s % 2 else 'Plank')


def galleon_rails(g):
	"""Stubby rail posts round the deck's edge."""
	for i in range(22):
		t = -0.9 + 1.75 * i / 21
		for side in (-1.0, 1.0):
			x, y, z = g.point(t, side * math.pi / 2)
			cylinder(0.045, 0.24, (x, y - side * 0.03, z + 0.08), 'PlankDark', verts=6, bevel=0.0)


def rope(p0, p1, r=0.02):
	d = Vector(p1) - Vector(p0)
	rot = d.to_track_quat('Z', 'Y').to_euler()
	cylinder(r, d.length, (Vector(p0) + Vector(p1)) / 2, 'Rope', verts=5, bevel=0.0,
			rot=tuple(math.degrees(v) for v in rot))


def ship_wheel(x, y, z, rot=0.0):
	f = _t(x, y, z) @ _rz(rot)
	box((0.1, 0.1, 0.6), (0, 0.06, -0.3), 'PlankDark', matrix=f)
	torus(0.24, 0.035, (0, 0, 0), 'Plank', rot=(90, 0, 0), matrix=f)
	for k in range(8):
		a = k * 45
		box((0.035, 0.035, 0.66), (0, -0.01, 0), 'PlankLight', rot=(0, a, 0), bevel=0.0, matrix=f)
	sphere(0.06, (0, -0.03, 0), 'Gold', matrix=f)


def rowboat(x, y, rot=0.0):
	"""A little rowboat drawn up on the sand, oars across it."""
	f = _t(x, y, 0.0) @ _rz(rot)
	bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, radius=1.0)
	obj = bpy.context.active_object
	bm = bmesh.new()
	bm.from_mesh(obj.data)
	for v in bm.verts:
		if v.co.x > 0:
			v.co.y *= 1.0 - 0.5 * v.co.x * v.co.x
	bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z > 0.01], context='VERTS')
	bm.to_mesh(obj.data)
	bm.free()
	obj.matrix_world = f @ _t(0, 0, 0.3) @ Matrix.Diagonal((0.85, 0.4, 0.36, 1.0))
	_finish(obj, 'Plank', 0.0, 0)
	for xx in (-0.3, 0.25):
		box((0.08, 0.7, 0.05), (xx, 0, 0.26), 'PlankLight', bevel=0.01, matrix=f)
	torus(0.85, 0.035, (0, 0, 0.3), 'TeamColor', matrix=f @ Matrix.Diagonal((1.0, 0.45, 1.0, 1.0)))
	for s in (-1, 1):
		box((1.4, 0.05, 0.04), (0.0, s * 0.12, 0.34), 'PlankLight', rot=(0, 0, s * 8), bevel=0.01, matrix=f)
		box((0.22, 0.04, 0.12), (0.7, s * 0.12 + s * 0.1, 0.34), 'PlankLight', rot=(0, 0, s * 8), bevel=0.01, matrix=f)


def town_centre():
	new_scene(31)
	g = Galleon(5.0, 2.45, 1.45)
	first = len(PARTS)
	galleon_hull(g)
	galleon_deck(g)
	galleon_rails(g)
	dz = g.deck_z(0.0) - 0.16
	# The stern castle: a plank cabin, a sail-cloth roof, gold stern windows.
	sx = -1.55
	sz = g.deck_z(-0.62) - 0.16
	plank_walls(0.55, 0.72, sz + 1.05, cx=sx, cy=0.0, z0=sz)
	sail_roof(1.5, 0.72, sz + 1.05, cx=sx, cy=0.0, pitch=30.0, hx=0.55)
	porthole(face(sx, -0.73, sz + 0.6, '-y'), r=0.15)
	for y in (-0.35, 0.35):
		f = face(sx - 0.56, y, sz + 0.55, '-x')
		box((0.3, 0.06, 0.38), (0, 0, 0), 'Window', bevel=0.03, matrix=f)
		box((0.38, 0.08, 0.06), (0, -0.03, 0.22), 'Gold', bevel=0.02, matrix=f)
		box((0.38, 0.08, 0.06), (0, -0.03, -0.22), 'Gold', bevel=0.02, matrix=f)
	lantern(sx - 0.68, 0.0, sz + 1.0)
	ship_wheel(sx + 0.75, 0.0, sz + 0.55, rot=90)
	# Two masts: the main with its team sail, crow's nest and the Jolly Roger,
	# a shorter foremast with a second sail.
	mast(0.15, 0.0, dz, 3.2, yard=1.8)
	mast(1.35, 0.0, g.deck_z(0.54) - 0.16, 2.3, yard=1.3, nest=False, flag=False)
	# Rigging from the mastheads down to the rails.
	for mx, top in ((0.15, dz + 3.0), (1.35, g.deck_z(0.54) + 2.0)):
		for t in (mx / 2.5 - 0.35, mx / 2.5 + 0.25):
			for side in (-1.0, 1.0):
				rope((mx, 0.0, top), g.point(t, side * math.pi / 2))
	# The bowsprit, rigged to the foremast, a gold skull figurehead under it.
	bx, by, bz = g.point(0.99, 0.0)
	bz = g.deck_z(0.99)
	cylinder(0.07, 1.5, (bx + 0.55, 0, bz + 0.2), 'Plank', verts=8, rot=(0, 72, 0), bevel=0.0)
	rope((bx + 1.2, 0, bz + 0.42), (1.35, 0.0, g.deck_z(0.54) + 1.6))
	sphere(0.17, (bx + 0.05, 0, bz - 0.25), 'Gold')
	box((0.14, 0.18, 0.1), (bx + 0.13, 0, bz - 0.38), 'Gold', bevel=0.03)
	# Gun ports and cannons along the side toward the front.
	for t in (-0.32, 0.0, 0.32):
		x, y, z = g.point(t, -math.acos(0.42))
		box((0.34, 0.08, 0.3), (x, y + 0.02, z), 'Black', rot=(-15, 0, 0), bevel=0.03)
		cannon(x, y + 0.25, z - 0.18, scale=0.75)
	# An anchor hung at the bow.
	ax, ay, az = g.point(0.72, -math.acos(0.3))
	cylinder(0.04, 0.6, (ax, ay - 0.06, az - 0.15), 'IronDark', verts=6, bevel=0.0)
	torus(0.18, 0.04, (ax, ay - 0.06, az - 0.45), 'IronDark', rot=(90, 0, 0))
	# Heel her over onto her front side, bow up a little, and settle her
	# keel into the sand.
	ship = PARTS[first:]
	tilt = Matrix.Rotation(math.radians(13.0), 4, 'X') @ Matrix.Rotation(math.radians(-3.0), 4, 'Y')
	for obj in ship:
		obj.matrix_world = tilt @ obj.matrix_world
	bpy.context.view_layer.update()
	low = min((obj.matrix_world @ Vector(c)).z for obj in ship for c in obj.bound_box)
	settle = Matrix.Translation((0.1, 0.35, -low - 0.28))
	for obj in ship:
		obj.matrix_world = settle @ obj.matrix_world
	# Sand heaped round where she lies.
	for i in range(14):
		t = -0.9 + 1.8 * i / 13
		x = t * g.L * 0.5 + 0.1
		for side in (-1.0, 1.0):
			y = 0.35 + side * g.half_width(t) * 0.75 + (-0.25 if side < 0 else 0.1)
			sphere(random.uniform(0.32, 0.5), (x, y, 0.0), 'Sand' if (i + (side > 0)) % 3 else 'SandDark')
			PARTS[-1].scale = (1.3, 0.9, 0.35)
	# The gangplank up from the sand to her low rail.
	deck_edge = settle @ tilt @ Vector(g.point(0.12, -math.pi / 2))
	foot = Vector((deck_edge.x, deck_edge.y - 1.35, 0.06))
	rope_len = (deck_edge - foot).length
	mid = (deck_edge + foot) / 2
	angle = math.degrees(math.atan2(deck_edge.z - foot.z, deck_edge.y - foot.y))
	box((0.6, rope_len, 0.07), mid, 'PlankLight', rot=(angle, 0, 0), bevel=0.02)
	for k in range(5):
		p = foot.lerp(deck_edge, (k + 0.5) / 5)
		box((0.62, 0.05, 0.04), (p.x, p.y, p.z + 0.05), 'PlankDark', rot=(angle, 0, 0), bevel=0.01)
	rowboat(1.9, -1.8, rot=-25)
	lantern(-0.3, -2.1, 0.0)
	chest(-1.2, -1.95, 0.0, rot=15)
	barrels(-2.2, -1.2, 0.0, 3, 2)
	palm(-2.1, 1.9, 0.0, h=2.8, lean=16, seed=3)
	rope_coil(0.55, -2.25, 0.0)
	export('TownCentre')


def house():
	new_scene(32)
	deck(1.2, 0.95)
	plank_walls(0.82, 0.62, 1.55)
	sail_roof(1.95, 0.62, 1.55, pitch=40.0, hx=0.82)
	plank_door(face(-0.25, -0.69, DZ, '-y'), w=0.48, h=0.86)
	porthole(face(0.4, -0.66, 1.0, '-y'), r=0.15)
	for side in ('-x', '+x'):
		porthole(face(0.84 if side == '+x' else -0.84, 0, 1.0, side), r=0.13)
	barrels(-1.0, -1.0, DZ, 2, 4)
	rope_coil(0.95, -0.85, DZ)
	palm(1.3, 0.85, 0.12, h=2.2, lean=14, seed=5)
	export('House')


def barracks():
	new_scene(33)
	CY = 0.15
	deck(1.85, 1.15, cy=CY)
	plank_walls(1.5, 0.85, 1.85, cy=CY)
	ridge = sail_roof(3.4, 0.85, 1.85, cy=CY, pitch=38.0, hx=1.5)
	jolly_roger(1.45, CY, ridge, pole=0.8)
	plank_door(face(0.0, CY - 0.92, DZ, '-y'), w=0.8, h=1.0)
	for x in (-0.9, 0.9):
		porthole(face(x, CY - 0.88, 1.2, '-y'), r=0.17)
	# The tavern sign: a gold tankard on a board hung from a bracket.
	f = face(-0.95, CY - 0.88, 1.75, '-y')
	box((0.08, 0.6, 0.08), (0, -0.3, 0), 'PlankDark', matrix=f)
	box((0.5, 0.06, 0.38), (0, -0.55, -0.26), 'PlankLight', bevel=0.02, matrix=f)
	box((0.16, 0.08, 0.2), (0, -0.6, -0.26), 'Gold', bevel=0.03, matrix=f)
	box((0.18, 0.09, 0.05), (0, -0.6, -0.13), 'Canvas', bevel=0.02, matrix=f)
	barrels(1.35, -1.2, DZ, 3, 6)
	box((0.9, 0.4, 0.06), (-1.2, -1.25, 0.6), 'Plank', bevel=0.02)
	for x in (-1.55, -0.85):
		box((0.08, 0.3, 0.32), (x, -1.25, 0.44), 'PlankDark')
	for x in (-1.4, -1.0):
		box((0.1, 0.1, 0.14), (x, -1.25, 0.7), 'Gold', bevel=0.02)
	export('Barracks')


def archery_range():
	new_scene(34)
	deck(2.0, 1.6, cy=-0.15)
	# The gun deck: a bulwark along the front pierced by three gun ports.
	for x in (-1.5, -0.5, 0.5, 1.5):
		box((0.5, 0.18, 0.62), (x, -1.45, DZ + 0.31), 'Plank', bevel=0.03)
	box((4.0, 0.22, 0.12), (0, -1.45, DZ + 0.66), 'PlankDark', bevel=0.03)
	for x in (-1.0, 0.0, 1.0):
		cannon(x, -1.2, DZ, scale=1.0)
	canvas_roof(3.6, 1.8, 2.0, 0.0, -0.15)
	# A bullseye target in the team's rings, and powder kegs behind.
	f = face(1.65, 1.0, DZ + 0.9, '-y')
	for k, (r, m) in enumerate(((0.45, 'Canvas'), (0.36, 'TeamColor'), (0.24, 'Canvas'), (0.12, 'TeamColor'))):
		cylinder(r, 0.06 + k * 0.02, (0, -k * 0.015, 0), m, verts=18, rot=(90, 0, 0), bevel=0.0, matrix=f)
	for x in (1.45, 1.85):
		box((0.07, 0.07, 1.0), (x, 1.05, DZ + 0.5), 'PlankDark', rot=(15, 0, 0))
	barrels(-1.5, 0.8, DZ, 3, 8)
	for i in range(3):
		sphere(0.09, (-0.4 + i * 0.2, 0.6, DZ + 0.09), 'IronDark')
	sphere(0.09, (-0.3, 0.6, DZ + 0.24), 'IronDark')
	export('ArcheryRange')


def stables():
	new_scene(35)
	deck(2.1, 1.25, cy=0.1, posts=False)
	# The crab pen: a ring of stakes roped together, a nest of netting.
	for k in range(16):
		a = math.radians(k * 360 / 16)
		x, y = 0.9 + math.cos(a) * 1.0, 0.1 + math.sin(a) * 1.0
		if -0.1 < y - 0.1 < 0.1 and x < 0.9:
			continue
		h = 0.7 + random.uniform(-0.05, 0.08)
		cylinder(0.07, h, (x, y, DZ + h / 2), 'Plank', verts=6, bevel=0.0)
		bpy.ops.mesh.primitive_cone_add(vertices=6, radius1=0.07, radius2=0.0, depth=0.14)
		_placed(bpy.context.active_object, (x, y, DZ + h + 0.07), (0, 0, 0), None)
		_finish(bpy.context.active_object, 'Plank', 0.0, 0)
	torus(1.0, 0.03, (0.9, 0.1, DZ + 0.45), 'Rope')
	torus(1.0, 0.03, (0.9, 0.1, DZ + 0.62), 'Rope')
	# A huge crab shell propped as the keeper's hut roof.
	plank_walls(0.65, 0.6, 1.3, cx=-1.2, cy=0.2)
	sphere(1.0, (-1.2, 0.2, 1.3), 'Coral')
	PARTS[-1].scale = (0.95, 0.85, 0.42)
	for side in (-1, 1):
		sphere(0.2, (-1.2 + side * 0.85, -0.45, 1.25), 'Coral')
		PARTS[-1].scale = (1.0, 1.6, 0.7)
	plank_door(face(-1.2, -0.42, DZ, '-y'), w=0.5, h=0.8)
	f = _t(0.9, 0.1, DZ)
	for k in range(5):
		a = math.radians(k * 72)
		box((0.6, 0.6, 0.04), (math.cos(a) * 0.25, math.sin(a) * 0.25, 0.04 + k * 0.01), 'Rope', rot=(0, 0, k * 30),
				bevel=0.015, matrix=f)
	barrels(1.8, -1.0, DZ, 2, 9)
	box((0.5, 0.35, 0.3), (-1.75, -0.85, DZ + 0.15), 'Plank', bevel=0.04)
	for i in range(4):
		box((0.18, 0.06, 0.06), (-1.85 + (i % 2) * 0.2, -0.85, DZ + 0.34 + 0.07 * (i // 2)), 'Fish', bevel=0.025)
	flag(-1.9, 0.9, DZ, 1.9)
	export('Stables')


def arcane_sanctum():
	new_scene(36)
	box((3.6, 3.0, 0.16), (0.25, -0.15, 0.08), 'Sand', bevel=0.08)
	# A tall round hut on stilts over the sand, a team cloth cone roof.
	for k in range(6):
		a = math.radians(k * 60)
		cylinder(0.08, 1.0, (math.cos(a) * 0.95, math.sin(a) * 0.95, 0.6), 'PlankDark', verts=8, bevel=0.0)
	cylinder(1.15, 0.12, (0, 0, 1.1), 'Plank', verts=16, bevel=0.03)
	cylinder(0.95, 1.4, (0, 0, 1.86), 'Plank', verts=14, bevel=0.03)
	for z in (1.4, 2.2):
		torus(0.96, 0.04, (0, 0, z), 'Rope')
	bpy.ops.mesh.primitive_cone_add(vertices=14, radius1=1.35, radius2=0.08, depth=1.9)
	_placed(bpy.context.active_object, (0, 0, 3.45), (0, 0, 0), None)
	_finish(bpy.context.active_object, 'TeamColor', 0.04, 2, angle=50)
	bpy.ops.mesh.primitive_cone_add(vertices=14, radius1=1.38, radius2=1.1, depth=0.25)
	_placed(bpy.context.active_object, (0, 0, 2.62), (0, 0, 0), None)
	_finish(bpy.context.active_object, 'TeamColorDark', 0.03, 2, angle=50)
	# A juju skull crowning the cone, glowing violet.
	sphere(0.28, (0, 0, 4.55), 'Bone')
	box((0.3, 0.2, 0.16), (0, -0.08, 4.36), 'Bone', bevel=0.04)
	for side in (-1, 1):
		sphere(0.08, (side * 0.11, -0.22, 4.6), 'Juju')
		bpy.ops.mesh.primitive_cone_add(vertices=8, radius1=0.08, radius2=0.0, depth=0.45)
		_placed(bpy.context.active_object, (side * 0.3, 0, 4.85), (0, side * -35, 0), None)
		_finish(bpy.context.active_object, 'Bone', 0.0, 0)
	sphere(0.12, (0, 0, 5.2), 'Juju')
	plank_door(face(0, -0.95, 1.16, '-y'), w=0.5, h=0.85)
	box((0.7, 1.42, 0.07), (0, -1.5, 0.66), 'PlankLight', rot=(45, 0, 0), bevel=0.02)
	for k in range(4):
		box((0.72, 0.05, 0.04), (0, -1.9 + k * 0.27, 0.3 + k * 0.27), 'PlankDark', bevel=0.01)
	# Skull posts and violet candles round the hut.
	for x, y in ((-1.4, -1.2), (1.6, -1.1), (1.9, 0.9)):
		skull_post(x, y, 0.16, h=1.0)
	for x, y in ((-0.9, -1.4), (0.9, -1.4), (1.3, -0.4)):
		cylinder(0.06, 0.22, (x, y, 0.27), 'Canvas', verts=8, bevel=0.0)
		sphere(0.06, (x, y, 0.42), 'Juju')
	palm(-1.3, 0.9, 0.16, h=2.4, lean=14, seed=7)
	export('ArcaneSanctum')


def siege_workshop():
	new_scene(37)
	deck(2.15, 1.65, cy=0.08)
	# A slipway with a hull half built in its ribs, a crane over it.
	for k in range(7):
		x = -1.5 + k * 0.42
		w = 1.1 * (1.0 - abs(k - 3) / 5.0)
		for side in (-1, 1):
			box((0.1, 0.1, 1.2), (x, 0.3 + side * w * 0.5, DZ + 0.55), 'PlankLight', rot=(side * -18, 0, 0), bevel=0.02)
	box((3.0, 0.14, 0.14), (-0.2, 0.3, DZ + 0.05), 'PlankDark', bevel=0.03)
	for x in (-1.9, 1.7):
		cylinder(0.1, 2.6, (x, 1.3, DZ + 1.3), 'PlankDark', verts=8, bevel=0.02)
	cylinder(0.08, 3.8, (-0.1, 1.3, DZ + 2.55), 'Plank', verts=8, rot=(0, 90, 0), bevel=0.0)
	cylinder(0.02, 1.1, (0.3, 1.3, DZ + 2.0), 'Rope', verts=6, bevel=0.0)
	box((0.3, 0.3, 0.2), (0.3, 1.3, DZ + 1.35), 'Plank', bevel=0.04)
	canvas_roof(1.4, 1.2, 1.9, 1.35, -0.9)
	cannon(1.35, -0.9, DZ, rot=20, scale=1.1)
	for i in range(4):
		box((1.3, 0.18, 0.07), (-1.3, -1.2, DZ + 0.04 + i * 0.08), 'PlankLight' if i % 2 else 'Plank',
				rot=(0, 0, random.uniform(-6, 6)), bevel=0.02)
	barrels(-0.2, -1.2, DZ, 2, 11)
	export('SiegeWorkshop')


def blacksmith():
	new_scene(38)
	deck(1.6, 1.15, cx=0.35)
	plank_walls(1.0, 0.8, 1.75, cx=0.0)
	sail_roof(2.3, 0.8, 1.75, pitch=36.0, hx=1.0)
	chimney(0.6, 0.45, 1.6, 3.0)
	plank_door(face(-0.3, -0.87, DZ, '-y'), w=0.6, h=0.9)
	# Crossed cutlasses on a team shield over the door.
	shield(0.5, face(0.4, -0.86, 1.25, '-y'))
	# An open forge out the side: an anvil, a glowing hearth, a cutlass rack.
	box((0.7, 0.8, 0.5), (1.5, -0.1, DZ + 0.25), 'Stone', bevel=0.06)
	box((0.5, 0.6, 0.08), (1.5, -0.1, DZ + 0.52), 'Ember', bevel=0.03)
	box((0.32, 0.16, 0.24), (1.35, -0.8, DZ + 0.12), 'IronDark', bevel=0.03)
	box((0.46, 0.18, 0.1), (1.35, -0.8, DZ + 0.29), 'IronDark', bevel=0.03)
	box((0.9, 0.1, 0.08), (-1.2, -0.9, DZ + 0.7), 'PlankDark')
	for i in range(4):
		box((0.05, 0.03, 0.6), (-1.5 + i * 0.2, -0.95, DZ + 0.62), 'Iron', rot=(0, 10, 0), bevel=0.01)
		box((0.12, 0.05, 0.05), (-1.48 + i * 0.2, -0.95, DZ + 0.36), 'Gold', bevel=0.01)
	barrels(2.05, 0.8, DZ, 2, 12)
	export('Blacksmith')


def library():
	new_scene(39)
	deck(1.9, 1.3)
	plank_walls(1.2, 0.9, 1.6)
	box((2.3, 1.7, 0.1), (0, 0, 1.65), 'PlankDark', bevel=0.03)
	plank_walls(0.9, 0.7, 2.75, z0=1.68)
	ridge = sail_roof(2.1, 0.7, 2.75, pitch=38.0, hx=0.9)
	plank_door(face(0, -0.97, DZ, '-y'), w=0.6, h=0.95)
	for x in (-0.75, 0.75):
		porthole(face(x, -0.93, 1.0, '-y'), r=0.16)
	porthole(face(0, -0.73, 2.2, '-y'), r=0.18)
	# A great globe on a brass stand over the ridge, and a telescope.
	cylinder(0.04, 0.4, (-0.6, 0, ridge + 0.1), 'Gold', verts=8, bevel=0.0)
	sphere(0.32, (-0.6, 0, ridge + 0.6), 'Canvas')
	torus(0.37, 0.03, (-0.6, 0, ridge + 0.6), 'Gold', rot=(90, 20, 0))
	for a in (0, 120, 240):
		box((0.22, 0.05, 0.16), (-0.6 + math.cos(math.radians(a)) * 0.2, -0.24, ridge + 0.6 + math.sin(math.radians(a)) * 0.15),
				'Palm', rot=(0, a, 0), bevel=0.02)
	cylinder(0.06, 0.8, (0.8, -0.6, 1.9), 'Gold', verts=10, rot=(55, 0, 30), bevel=0.01)
	for i in range(3):
		cylinder(0.06, 0.5, (1.5, -1.0 + i * 0.13, DZ + 0.06 + i * 0.0), 'Canvas', verts=8, rot=(0, 90, 0), bevel=0.0)
	barrels(-1.55, -1.0, DZ, 1, 13)
	export('Library')


def mill():
	new_scene(40)
	deck(1.4, 1.1)
	plank_walls(0.85, 0.7, 1.5)
	sail_roof(2.0, 0.7, 1.5, pitch=36.0, hx=0.85)
	plank_door(face(0, -0.77, DZ, '-y'), w=0.55, h=0.88)
	# The galley's cook pot over a fire, and a tall mast strung with fish.
	box((0.5, 0.5, 0.1), (1.05, -0.75, DZ + 0.05), 'Stone', bevel=0.04)
	box((0.36, 0.36, 0.06), (1.05, -0.75, DZ + 0.12), 'Ember', bevel=0.02)
	cylinder(0.24, 0.32, (1.05, -0.75, DZ + 0.36), 'IronDark', verts=14, bevel=0.03)
	cylinder(0.2, 0.04, (1.05, -0.75, DZ + 0.52), 'Fish', verts=14, bevel=0.0)
	cylinder(0.08, 3.9, (-0.95, 0.55, DZ + 1.95), 'Plank', verts=10, bevel=0.02)
	cylinder(0.05, 1.6, (-0.95, 0.55, DZ + 3.2), 'PlankDark', verts=8, rot=(90, 0, 0), bevel=0.0)
	for side in (-1, 1):
		for i in range(3):
			y = 0.55 + side * (0.25 + i * 0.22)
			cylinder(0.01, 0.4, (-0.95, y, DZ + 2.95), 'Rope', verts=4, bevel=0.0)
			box((0.08, 0.06, 0.26), (-0.95, y, DZ + 2.68), 'Fish', bevel=0.03)
	jolly_roger(-0.95, 0.55, DZ + 3.9, pole=0.25, size=0.4)
	for i in range(3):
		box((0.5, 0.35, 0.22), (0.95, 0.6, DZ + 0.11 + i * 0.0), 'Plank', bevel=0.04)
	sack(-0.9, -0.9, DZ, 15)
	export('Mill')


def mine():
	new_scene(41)
	# In front of the gold deposit (the deposit sits at the origin): a
	# treasure dig with a hoist over the hole and the spoil heaped up.
	box((2.5, 2.2, 0.14), (0.1, -1.5, 0.07), 'Sand', bevel=0.07)
	cylinder(0.6, 0.06, (-0.1, -1.3, 0.15), 'Black', verts=16, bevel=0.0)
	for k in range(8):
		a = math.radians(k * 45)
		box((0.3, 0.12, 0.12), (-0.1 + math.cos(a) * 0.62, -1.3 + math.sin(a) * 0.62, 0.2), 'PlankDark', rot=(0, 0, k * 45 + 90),
				bevel=0.02)
	for x in (-0.75, 0.55):
		cylinder(0.06, 1.3, (x, -1.3, 0.8), 'Plank', verts=8, rot=(0, (1 if x < 0 else -1) * 12, 0), bevel=0.0)
	cylinder(0.05, 1.5, (-0.1, -1.3, 1.38), 'PlankDark', verts=8, rot=(0, 90, 0), bevel=0.0)
	cylinder(0.12, 0.3, (-0.1, -1.3, 1.38), 'Rope', verts=10, rot=(0, 90, 0), bevel=0.0)
	cylinder(0.015, 0.6, (-0.1, -1.3, 1.05), 'Rope', verts=4, bevel=0.0)
	cylinder(0.14, 0.2, (-0.1, -1.3, 0.72), 'Plank', verts=10, bevel=0.02)
	# A red X marks the spot, the spoil heap and an overflowing chest.
	for a in (45, -45):
		box((0.7, 0.12, 0.03), (0.75, -2.2, 0.15), 'Red', rot=(0, 0, a), bevel=0.01)
	sphere(0.45, (-0.75, -2.15, 0.14), 'SandDark')
	PARTS[-1].scale = (1.0, 0.8, 0.5)
	chest(0.85, -0.65, 0.14, rot=25)
	for x, a in ((-0.95, 20), (-0.75, -15)):
		cylinder(0.025, 0.7, (x, -0.65, 0.45), 'Plank', verts=6, rot=(a, 0, 0), bevel=0.0)
		box((0.14, 0.03, 0.18), (x, -0.65 - math.sin(math.radians(a)) * 0.33, 0.12), 'Iron', bevel=0.01)
	export('Mine')


def storehouse():
	new_scene(42)
	deck(1.6, 1.15, cx=0.1, cy=0.15)
	plank_walls(1.1, 0.8, 1.7, cx=0.1, cy=0.2)
	sail_roof(2.5, 0.8, 1.7, cx=0.1, cy=0.2, pitch=32.0, hx=1.1)
	# Big double doors and the loot piled outside.
	plank_door(face(0.1, -0.67, DZ, '-y'), w=0.95, h=1.05)
	crate(-1.05, -0.8, DZ, 0.36, 10)
	crate(-1.0, -0.75, DZ + 0.36, 0.28, -15)
	chest(0.95, -0.85, DZ, rot=-10)
	barrels(1.55, 0.7, DZ, 3, 14)
	sack(-1.35, 0.6, DZ, 30)
	export('Storehouse')


def watchtower():
	new_scene(43)
	box((2.0, 2.0, 0.16), (0, 0, 0.08), 'Sand', bevel=0.08)
	for k in range(6):
		a = math.radians(k * 60 + 15)
		sphere(0.24, (math.cos(a) * 0.62, math.sin(a) * 0.62, 0.22), 'Stone' if k % 2 else 'StoneDark')
	cylinder(0.16, 4.6, (0, 0, 2.45), 'Plank', verts=10, bevel=0.02)
	for z in (1.0, 2.2, 3.4):
		torus(0.17, 0.04, (0, 0, z), 'Rope')
	# The crow's nest: a barrel lookout high on the mast.
	cylinder(0.6, 0.6, (0, 0, 4.55), 'Plank', verts=14, bevel=0.04)
	for z in (4.32, 4.78):
		torus(0.61, 0.04, (0, 0, z), 'IronDark')
	cylinder(0.65, 0.08, (0, 0, 4.25), 'PlankDark', verts=14, bevel=0.02)
	# A rope ladder up the front.
	for side in (-1, 1):
		cylinder(0.018, 4.0, (side * 0.18, -0.25, 2.2), 'Rope', verts=4, rot=(4, 0, 0), bevel=0.0)
	for i in range(10):
		box((0.38, 0.05, 0.04), (0, -0.25 + i * 0.007, 0.5 + i * 0.38), 'PlankLight', bevel=0.01)
	cannon(0.0, -0.25, 4.82, scale=0.6)
	jolly_roger(0, 0.1, 4.85, pole=0.9, size=0.45)
	export('Watchtower')


def wall_segment():
	new_scene(44)
	# A palisade of pointed stakes lashed with rope.
	for i in range(8):
		x = -0.88 + i * 0.25
		h = 1.5 + random.uniform(-0.06, 0.08)
		cylinder(0.12, h, (x, random.uniform(-0.03, 0.03), h / 2), 'Plank' if i % 2 else 'PlankLight', verts=8, bevel=0.02)
		bpy.ops.mesh.primitive_cone_add(vertices=8, radius1=0.12, radius2=0.0, depth=0.3)
		_placed(bpy.context.active_object, (x, 0, h + 0.15), (0, 0, 0), None)
		_finish(bpy.context.active_object, 'PlankLight', 0.02, 2, angle=50)
	for z in (0.45, 1.15):
		box((2.0, 0.27, 0.07), (0, 0, z), 'Rope', bevel=0.02)
	export('WallSegment')


def wall_corner():
	new_scene(45)
	cylinder(0.4, 2.4, (0, 0, 1.2), 'PlankDark', verts=12, bevel=0.03)
	for z in (0.5, 1.3, 2.1):
		torus(0.41, 0.05, (0, 0, z), 'Rope')
	bpy.ops.mesh.primitive_cone_add(vertices=12, radius1=0.42, radius2=0.0, depth=0.5)
	_placed(bpy.context.active_object, (0, 0, 2.65), (0, 0, 0), None)
	_finish(bpy.context.active_object, 'Plank', 0.02, 2, angle=50)
	lantern(0, -0.45, 1.85)
	export('WallCorner')


def wall_gate():
	new_scene(46)
	for side in (-1, 1):
		cylinder(0.24, 2.4, (side * 0.92, 0, 1.2), 'PlankDark', verts=10, bevel=0.03)
		bpy.ops.mesh.primitive_cone_add(vertices=10, radius1=0.25, radius2=0.0, depth=0.35)
		_placed(bpy.context.active_object, (side * 0.92, 0, 2.57), (0, 0, 0), None)
		_finish(bpy.context.active_object, 'Plank', 0.02, 2, angle=50)
		for z in (0.6, 1.5):
			torus(0.25, 0.04, (side * 0.92, 0, z), 'Rope')
	box((2.2, 0.3, 0.22), (0, 0, 2.1), 'Plank', bevel=0.04)
	# A skull grinning over the way in.
	sphere(0.18, (0, -0.15, 2.35), 'Bone')
	box((0.2, 0.12, 0.1), (0, -0.2, 2.2), 'Bone', bevel=0.03)
	for side in (-1, 1):
		sphere(0.05, (side * 0.07, -0.31, 2.38), 'Black')
		box((0.5, 0.06, 0.07), (side * 0.0, -0.18, 2.35), 'Bone', rot=(0, side * 35, 0), bevel=0.02)
	export('WallGate')


BUILDINGS = {
	'TownCentre': town_centre, 'House': house, 'Barracks': barracks, 'ArcheryRange': archery_range,
	'Stables': stables, 'ArcaneSanctum': arcane_sanctum, 'SiegeWorkshop': siege_workshop,
	'Blacksmith': blacksmith, 'Library': library, 'Mill': mill, 'Mine': mine, 'Storehouse': storehouse,
	'Watchtower': watchtower, 'WallSegment': wall_segment, 'WallCorner': wall_corner, 'WallGate': wall_gate,
}

if __name__ == '__main__':
	names = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
	for name in names or list(BUILDINGS):
		BUILDINGS[name]()
