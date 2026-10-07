# Shared kit for the Aldmere buildings (TownBuildings/*.glb): chunky toy
# blocks in the diorama style. Every part is a bevelled block with smooth
# normals, so faces swell softly into rounded edges and catch the sun.
#
# Material names and colours match the old exports, so TeamColorMaterial keeps
# recolouring TeamColor/TeamColorDark; only the stone is warmed, from
# blue-grey toward the reference's sandy grey.
#
# Blender is Z up with a building's front facing -Y, which exports to Godot +Z.
# A building script does `from common import *`, builds, then export(name).
import bpy, bmesh, sys, os, math, random
from mathutils import Matrix, Vector

KIT_DIR = os.path.dirname(os.path.abspath(__file__))

# Linear base colours.
COLOURS = {
	'Stone': (0.31, 0.285, 0.255), 'StoneDark': (0.2, 0.182, 0.165),
	'Plaster': (0.711, 0.656, 0.538), 'Wood': (0.187, 0.068, 0.02),
	'WoodDark': (0.055, 0.02, 0.007), 'Window': (0.009, 0.009, 0.01),
	'Iron': (0.342, 0.367, 0.42), 'IronDark': (0.047, 0.047, 0.059),
	'TeamColor': (0.033, 0.119, 0.692), 'TeamColorDark': (0.017, 0.064, 0.448),
	'Gold': (0.828, 0.477, 0.04), 'Hay': (0.711, 0.477, 0.107), 'Red': (0.523, 0.022, 0.013),
	'Sack': (0.57, 0.42, 0.196), 'Ember': (1.0, 0.171, 0.01), 'Arcane': (0.342, 0.084, 0.692),
	'Bone': (0.787, 0.711, 0.507), 'Meat': (0.393, 0.033, 0.025), 'Log': (0.263, 0.107, 0.033),
	'LogEnd': (0.692, 0.42, 0.171), 'Cloth': (0.828, 0.787, 0.674), 'Apple': (0.604, 0.033, 0.02),
	'Greens': (0.1, 0.319, 0.051), 'Antler': (0.748, 0.638, 0.42), 'BloodRed': (0.342, 0.01, 0.01),
	'Horn': (0.711, 0.604, 0.42), 'Orb': (0.89, 0.033, 0.02),
}
GLOSSY = ('Gold', 'Iron', 'IronDark', 'Orb', 'Arcane')

MATS = {}
PARTS = []
# The plinth top every building stands on.
PZ = 0.3


def out_path(name):
	"""The GLB to write: the first argument after `--`, else the building's own
	file next to this kit."""
	if '--' in sys.argv and len(sys.argv) > sys.argv.index('--') + 1:
		return sys.argv[sys.argv.index('--') + 1]
	return os.path.join(os.path.dirname(KIT_DIR), name + '.glb')


def new_scene(seed=7):
	random.seed(seed)
	bpy.ops.wm.read_factory_settings(use_empty=True)
	MATS.clear()
	PARTS.clear()


def mat(name):
	if name not in MATS:
		m = bpy.data.materials.new(name)
		m.use_nodes = True
		b = m.node_tree.nodes['Principled BSDF']
		b.inputs['Base Color'].default_value = (*COLOURS[name], 1.0)
		b.inputs['Roughness'].default_value = 0.4 if name in GLOSSY else 0.85
		MATS[name] = m
	return MATS[name]


def _finish(obj, mat_name, bevel, segments, angle=None):
	obj.data.materials.append(mat(mat_name))
	for p in obj.data.polygons:
		p.use_smooth = True
	if bevel > 0.0:
		mod = obj.modifiers.new('Bevel', 'BEVEL')
		mod.width = bevel
		mod.segments = segments
		mod.use_clamp_overlap = True
		# Not hardened: each face's normals curve gently into its rounded edges,
		# like slightly inflated moulded plastic, so flat faces still catch a
		# moving highlight the way the trees' curved scallops do.
		mod.harden_normals = False
		if angle is not None:
			mod.limit_method = 'ANGLE'
			mod.angle_limit = math.radians(angle)
		else:
			mod.limit_method = 'NONE'
	PARTS.append(obj)
	return obj


def _auto_bevel(size, cap=0.05):
	return min(cap, 0.28 * min(size))


def _rot(rot):
	return Matrix.Rotation(math.radians(rot[2]), 4, 'Z') @ Matrix.Rotation(math.radians(rot[1]), 4, 'Y') \
		@ Matrix.Rotation(math.radians(rot[0]), 4, 'X')


def box(size, loc, mat_name, rot=(0, 0, 0), bevel=None, segments=None, matrix=None):
	"""A bevelled block `size` (x, y, z) centred on `loc`, rotated `rot`
	degrees (XYZ); `matrix` (a frame) is applied on top when given."""
	mesh = bpy.data.meshes.new('box')
	bm = bmesh.new()
	bmesh.ops.create_cube(bm, size=1.0)
	bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
	bm.to_mesh(mesh)
	bm.free()
	obj = bpy.data.objects.new('box', mesh)
	bpy.context.scene.collection.objects.link(obj)
	local = Matrix.Translation(loc) @ _rot(rot)
	obj.matrix_world = (matrix @ local) if matrix is not None else local
	b = _auto_bevel(size) if bevel is None else bevel
	return _finish(obj, mat_name, b, segments or (3 if min(size) > 0.25 else 2))


def _placed(obj, loc, rot, matrix):
	local = Matrix.Translation(loc) @ _rot(rot)
	obj.matrix_world = (matrix @ local) if matrix is not None else local


def cylinder(radius, depth, loc, mat_name, verts=12, rot=(0, 0, 0), bevel=0.03, matrix=None, radius2=None):
	if radius2 is None:
		bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth)
	else:
		bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=radius, radius2=radius2, depth=depth)
	obj = bpy.context.active_object
	_placed(obj, loc, rot, matrix)
	return _finish(obj, mat_name, bevel, 2, angle=50)


def pyramid(base, height, loc, mat_name, sides=4, matrix=None):
	"""A spire standing on `loc` (its base centre)."""
	bpy.ops.mesh.primitive_cone_add(vertices=sides, radius1=base * (0.7071 if sides == 4 else 0.5),
			radius2=0.0, depth=height)
	obj = bpy.context.active_object
	_placed(obj, (loc[0], loc[1], loc[2] + height / 2), (0, 0, 45 if sides == 4 else 0), matrix)
	return _finish(obj, mat_name, 0.05, 3, angle=30)


def sphere(radius, loc, mat_name, matrix=None):
	bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=radius)
	obj = bpy.context.active_object
	_placed(obj, loc, (0, 0, 0), matrix)
	return _finish(obj, mat_name, 0.0, 0)


def torus(major, minor, loc, mat_name, rot=(0, 0, 0), matrix=None):
	bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=16, minor_segments=6)
	obj = bpy.context.active_object
	_placed(obj, loc, rot, matrix)
	return _finish(obj, mat_name, 0.0, 0)


# --- faces ------------------------------------------------------------------
# A face frame puts local -Y out of a wall: build in it as if on the front.
FACE_ANGLE = {'-y': 0, '+x': 90, '+y': 180, '-x': 270}


def face(x, y, z, side):
	return Matrix.Translation((x, y, z)) @ Matrix.Rotation(math.radians(FACE_ANGLE[side]), 4, 'Z')


def emblem(size, frame):
	"""The team emblem: a gold saltire, on the face in front of `frame`."""
	for a in (45, -45):
		box((size * 0.22, 0.03, size), (0, -0.02, 0), 'Gold', rot=(0, a, 0), bevel=0.012, segments=2, matrix=frame)


def banner(w, h, frame, swallow=True):
	"""A team cloth hanging from a wooden bar whose centre is `frame`."""
	box((w + 0.16, 0.08, 0.08), (0, 0, 0), 'Wood', matrix=frame)
	box((w, 0.05, h), (0, -0.02, -h / 2 - 0.02), 'TeamColor', bevel=0.02, matrix=frame)
	if swallow:
		for side in (-1, 1):
			box((w * 0.42, 0.05, 0.16), (side * w * 0.29, -0.02, -h - 0.08), 'TeamColor', bevel=0.02, matrix=frame)
	box((w, 0.055, 0.06), (0, -0.025, -0.1), 'TeamColorDark', bevel=0.015, matrix=frame)
	emblem(min(w, h) * 0.55, frame @ Matrix.Translation((0, -0.02, -h * 0.5)))


def shield(size, frame):
	"""A gold-rimmed team shield centred on `frame`."""
	box((size, 0.06, size * 0.95), (0, 0, 0), 'Gold', bevel=0.03, matrix=frame)
	box((size * 0.84, 0.07, size * 0.8), (0, -0.02, 0.01), 'TeamColor', bevel=0.03, matrix=frame)
	box((size * 0.6, 0.07, size * 0.4), (0, -0.02, -size * 0.48), 'TeamColor', rot=(0, 45, 0), bevel=0.03, matrix=frame)
	emblem(size * 0.6, frame @ Matrix.Translation((0, -0.04, -0.02)))


def window(frame, w=0.34, h=0.4, shutters=True):
	"""A dark window with sill, lintel and team shutters, centred on `frame`."""
	box((w, 0.06, h), (0, 0.02, 0), 'Window', bevel=0.02, matrix=frame)
	box((w + 0.12, 0.1, 0.07), (0, -0.03, h / 2 + 0.04), 'Wood', matrix=frame)
	box((w + 0.12, 0.12, 0.08), (0, -0.04, -h / 2 - 0.03), 'Wood', matrix=frame)
	box((0.07, 0.1, h), (0, -0.02, 0), 'Wood', bevel=0.02, matrix=frame)
	if shutters:
		for side in (-1, 1):
			box((w * 0.38, 0.07, h + 0.02), (side * (w / 2 + w * 0.2), -0.03, 0), 'TeamColorDark', bevel=0.02, matrix=frame)


def door(frame, w=0.6, h=1.0, arch='wood'):
	"""A planked door standing on `frame` (bottom centre), framed in wood or
	stone."""
	box((w, 0.08, h), (0, 0.01, h / 2), 'WoodDark', bevel=0.03, matrix=frame)
	planks = max(2, round(w / 0.22))
	pw = w / planks
	for i in range(planks):
		box((pw - 0.03, 0.06, h - 0.06), (-w / 2 + pw * (i + 0.5), -0.03, h / 2), 'Wood', bevel=0.02, matrix=frame)
	for z in (h * 0.25, h * 0.75):
		box((w + 0.02, 0.05, 0.07), (0, -0.07, z), 'Iron', bevel=0.02, matrix=frame)
	sphere(0.045, (w * 0.3, -0.1, h * 0.5), 'Gold', matrix=frame)
	if arch == 'stone':
		for side in (-1, 1):
			for k in range(3):
				bw = 0.24 if k % 2 else 0.3
				box((bw, 0.2, h / 3 - 0.02), (side * (w / 2 + bw / 2 - 0.02), -0.04, h / 6 + k * h / 3),
						'StoneDark' if k == 1 else 'Stone', matrix=frame)
		box((w + 0.5, 0.22, 0.24), (0, -0.04, h + 0.12), 'Stone', matrix=frame)
	else:
		for side in (-1, 1):
			box((0.13, 0.14, h + 0.1), (side * (w / 2 + 0.06), -0.04, h / 2 + 0.05), 'Wood', matrix=frame)
		box((w + 0.3, 0.16, 0.14), (0, -0.05, h + 0.08), 'Wood', matrix=frame)


# --- structures -------------------------------------------------------------
def plinth(px, py, cx=0.0, cy=0.0, pz=PZ):
	"""A base slab ringed with uneven chunky stones, half-extents px, py."""
	box((px * 2 - 0.1, py * 2 - 0.1, pz), (cx, cy, pz / 2), 'StoneDark', bevel=0.06)
	box((px * 2 - 0.3, py * 2 - 0.3, 0.06), (cx, cy, pz + 0.02), 'Stone', bevel=0.02)

	def run(start, end, axis, fixed, outward):
		length = end - start
		n = max(2, round(length / 0.55))
		step = length / n
		for i in range(n):
			c = start + step * (i + 0.5) + random.uniform(-0.03, 0.03)
			w = step - 0.04
			h = pz + random.uniform(-0.04, 0.06)
			d = 0.3 + random.uniform(-0.03, 0.03)
			m = 'Stone' if random.random() < 0.65 else 'StoneDark'
			if axis == 'y':
				box((w, d, h), (cx + c, cy + fixed + outward * d * 0.3, h / 2), m)
			else:
				box((d, w, h), (cx + fixed + outward * d * 0.3, cy + c, h / 2), m)
	run(-px, px, 'y', -py, -1)
	run(-px, px, 'y', py, 1)
	run(-py + 0.3, py - 0.3, 'x', -px, -1)
	run(-py + 0.3, py - 0.3, 'x', px, 1)
	return pz


def bays(half_w):
	return max(1, round(half_w * 2 / 1.0))


def bay_centres(half_w):
	"""Where doors and windows go along a hall wall of half-width `half_w`:
	the middle of each bay between its posts."""
	n = bays(half_w)
	step = (half_w * 2 - 0.14) / n
	return [-half_w + 0.07 + step * (i + 0.5) for i in range(n)]


def hall(hx, hy, wall_top, cx=0.0, cy=0.0, z0=PZ, braces=True, faces=('-y', '+y', '-x', '+x'), mid_z=None):
	"""Plaster walls in a timber frame on a stone footing course. Returns the
	height of the middle beam (`mid_z`, else just under halfway up)."""
	box((hx * 2, hy * 2, wall_top - z0), (cx, cy, (wall_top + z0) / 2), 'Plaster', bevel=0.04)
	box((hx * 2 + 0.08, hy * 2 + 0.08, 0.3), (cx, cy, z0 + 0.15), 'Stone', bevel=0.05)
	mid = mid_z if mid_z is not None else z0 + 0.3 + (wall_top - z0 - 0.3) * 0.45
	for side in faces:
		half_w, depth = (hx, hy) if side in ('-y', '+y') else (hy, hx)
		f = face(cx + (hx if side == '+x' else -hx if side == '-x' else 0),
				cy + (hy if side == '+y' else -hy if side == '-y' else 0), 0, side)
		box((half_w * 2 + 0.1, 0.16, 0.16), (0, -0.04, mid), 'Wood', matrix=f)
		box((half_w * 2 + 0.1, 0.18, 0.18), (0, -0.05, wall_top - 0.06), 'Wood', matrix=f)
		n = bays(half_w)
		for i in range(n + 1):
			x = -half_w + 0.07 + (half_w * 2 - 0.14) * i / n
			box((0.15, 0.14, wall_top - z0 - 0.3), (x, -0.04, (wall_top + z0 + 0.3) / 2), 'Wood', matrix=f)
		if braces and n >= 2:
			bay = (half_w * 2 - 0.14) / n
			for x0, a in ((-half_w + 0.07 + bay / 2, 38), (half_w - 0.07 - bay / 2, -38)):
				box((0.11, 0.12, (mid - z0 - 0.3) / math.cos(math.radians(38)) * 0.95),
						(x0, -0.035, (mid + z0 + 0.3) / 2), 'WoodDark', rot=(0, a, 0), matrix=f)
	return mid


def roof_drop(over, pitch):
	"""How far a gable roof's frame sits below its wall tops: the rise across
	the eave overhang, less what the slab's own thickness takes back. Without
	it the slab starts at wall height at the eave and floats above the walls."""
	return over * math.tan(math.radians(pitch)) - 0.014


def gable_roof(length, hy, wall_top, cx=0.0, cy=0.0, pitch=42.0, over=0.3, tile_rows=5, hx=None,
		gables=True, ridge_beam=True, tile_mats=('TeamColor', 'TeamColorDark'), slab_mat='TeamColorDark'):
	"""A tiled gable roof, ridge along X, over walls of half-depth `hy`.
	`hx` is the half-length of the walls under it, where the plaster gables
	close the ends. Returns the ridge height."""
	half_span = hy + over
	rise = half_span * math.tan(math.radians(pitch))
	base = wall_top - roof_drop(over, pitch)
	ridge = base + rise
	slope_len = half_span / math.cos(math.radians(pitch))
	count = max(2, round(length / 0.44))
	tw = length / count
	for s in (-1, 1):
		frame = Matrix.Translation((cx, cy + s * half_span / 2, base + rise / 2 + 0.08)) \
			@ Matrix.Rotation(math.radians(pitch * -s), 4, 'X')
		box((length, slope_len + 0.06, 0.14), (0, 0, 0), slab_mat, bevel=0.05, matrix=frame)
		for r in range(tile_rows):
			# Along the slab from the eave (row 0) up to the ridge.
			v = s * (slope_len / 2 - (r + 0.5) * slope_len / tile_rows)
			offset = (tw / 2) if r % 2 else 0.0
			for i in range(count + (1 if r % 2 else 0)):
				x = -length / 2 + tw * (i + 0.5) - offset
				lo, hi = max(x - tw / 2, -length / 2), min(x + tw / 2, length / 2)
				if hi - lo < 0.12:
					continue
				m = tile_mats[0] if random.random() < 0.8 else tile_mats[-1]
				# Each row overlaps the one below and tips out a little at its foot.
				box((hi - lo - 0.035, slope_len / tile_rows + 0.05, 0.09),
						((lo + hi) / 2, v, 0.1 + random.uniform(0.0, 0.015)), m,
						rot=(s * 4.0, 0, 0), bevel=0.03, segments=2, matrix=frame)
	if ridge_beam:
		box((length + 0.2, 0.22, 0.22), (cx, cy, ridge + 0.14), 'Wood', bevel=0.05)
	for end in (-1, 1):
		x = cx + end * (length / 2 + 0.02)
		if gables and hx is not None:
			mesh = bpy.data.meshes.new('gable')
			bm = bmesh.new()
			pts = [(cy - hy, wall_top), (cy + hy, wall_top), (cy, wall_top + hy * math.tan(math.radians(pitch)))]
			vs = [bm.verts.new((cx + end * (hx - 0.02), py, pz)) for py, pz in pts]
			bm.faces.new(vs)
			bmesh.ops.extrude_face_region(bm, geom=bm.faces[:])
			bm.verts.ensure_lookup_table()
			for v in bm.verts[3:]:
				v.co.x += end * 0.08
			bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
			bm.to_mesh(mesh)
			bm.free()
			g = bpy.data.objects.new('gable', mesh)
			bpy.context.scene.collection.objects.link(g)
			_finish(g, 'Plaster', 0.02, 2)
			box((0.1, 0.12, 0.7), (cx + end * (hx + 0.05), cy, wall_top + 0.45), 'Wood')
		for s in (-1, 1):
			box((0.14, slope_len + 0.1, 0.16), (x, cy + s * half_span / 2, base + rise / 2 + 0.02), 'Wood',
					rot=(pitch * -s, 0, 0))
	return ridge


def shed_roof(x, y, z_high, width, run, side, pitch=24.0, tile_rows=None, tile_mats=('TeamColor', 'TeamColorDark')):
	"""A single tiled slope running down and out from a wall line: its high
	edge is centred on (x, y, z_high), `width` along the wall, `run` out toward
	`side`. Returns the height of its low edge."""
	rise = run * math.tan(math.radians(pitch))
	slope_len = run / math.cos(math.radians(pitch))
	# Rows about the size of the gable roofs' tiles.
	tile_rows = tile_rows or max(2, round(slope_len / 0.36))
	# Down the slope is the face frame's -Y.
	frame = face(x, y, z_high, side) @ Matrix.Translation((0, -run / 2, -rise / 2 + 0.07)) \
		@ Matrix.Rotation(math.radians(pitch), 4, 'X')
	box((width, slope_len + 0.06, 0.14), (0, 0, 0), 'TeamColorDark', bevel=0.05, matrix=frame)
	count = max(2, round(width / 0.44))
	tw = width / count
	for r in range(tile_rows):
		v = -slope_len / 2 + (r + 0.5) * slope_len / tile_rows
		offset = (tw / 2) if r % 2 else 0.0
		for i in range(count + (1 if r % 2 else 0)):
			cx = -width / 2 + tw * (i + 0.5) - offset
			lo, hi = max(cx - tw / 2, -width / 2), min(cx + tw / 2, width / 2)
			if hi - lo < 0.12:
				continue
			m = tile_mats[0] if random.random() < 0.8 else tile_mats[-1]
			box((hi - lo - 0.035, slope_len / tile_rows + 0.05, 0.09), ((lo + hi) / 2, v, 0.1 + random.uniform(0.0, 0.015)),
					m, rot=(-4.0, 0, 0), bevel=0.03, segments=2, matrix=frame)
	box((width + 0.12, 0.16, 0.16), (0, 0, 0.04), 'Wood', matrix=face(x, y, z_high, side))
	return z_high - rise


def horseshoe(size, frame, mat_name='Iron'):
	"""A U-shaped horseshoe, open end up, centred on `frame`'s face."""
	n = 7
	for i in range(n):
		# Round from upper left, under the bottom, to upper right; the gap is at the top.
		a = math.radians(150 + 240 * i / (n - 1))
		# Tangent to the arc: a block's long (z) axis turned by -a about Y.
		box((size * 0.22, 0.06, size * 0.24), (math.cos(a) * size * 0.4, -0.02, math.sin(a) * size * 0.4), mat_name,
				rot=(0, -math.degrees(a), 0), bevel=0.02, segments=2, matrix=frame)


def chimney(x, y, z0, top):
	box((0.42, 0.42, top - z0), (x, y, (top + z0) / 2), 'Stone', bevel=0.05)
	box((0.52, 0.52, 0.12), (x, y, top), 'StoneDark', bevel=0.04)


def quoins(x, y, z0, z1, size=0.3):
	"""Alternating stone blocks up a building's corner at (x, y)."""
	n = max(2, round((z1 - z0) / 0.36))
	step = (z1 - z0) / n
	for k in range(n):
		sx, sy = (size + 0.12, size) if k % 2 == 0 else (size, size + 0.12)
		box((sx, sy, step - 0.04), (x, y, z0 + step * (k + 0.5)), 'StoneDark' if k % 3 == 1 else 'Stone', bevel=0.05)


def flag(x, y, z_base, pole):
	cylinder(0.045, pole, (x, y, z_base + pole / 2), 'Wood', verts=8, bevel=0.0)
	sphere(0.07, (x, y, z_base + pole + 0.04), 'Gold')
	box((0.5, 0.04, 0.32), (x + 0.27, y, z_base + pole - 0.2), 'TeamColor', bevel=0.015)
	box((0.1, 0.045, 0.32), (x + 0.47, y, z_base + pole - 0.2), 'TeamColorDark', bevel=0.015)


# --- props ------------------------------------------------------------------
def barrel(x, y, z=PZ, r=0.2, h=0.46):
	cylinder(r, h, (x, y, z + h / 2), 'Wood', verts=12, bevel=0.04)
	for t in (0.22, 0.78):
		cylinder(r + 0.015, 0.05, (x, y, z + h * t), 'Iron', verts=12, bevel=0.012)


def crate(x, y, z, size, rot=0.0):
	box((size, size, size), (x, y, z + size / 2), 'Wood', rot=(0, 0, rot), bevel=0.04)
	box((size + 0.02, size + 0.02, 0.06), (x, y, z + size / 2), 'WoodDark', rot=(0, 0, rot), bevel=0.02)


def sack(x, y, z, rot=0.0):
	box((0.3, 0.22, 0.34), (x, y, z + 0.17), 'Sack', rot=(0, 0, rot), bevel=0.09, segments=3)
	box((0.12, 0.12, 0.08), (x, y, z + 0.37), 'Sack', rot=(0, 0, rot), bevel=0.03)


def hay_bale(x, y, z, rot=0.0):
	frame = Matrix.Translation((x, y, z)) @ Matrix.Rotation(math.radians(rot), 4, 'Z')
	box((0.5, 0.34, 0.32), (0, 0, 0.16), 'Hay', bevel=0.07, segments=3, matrix=frame)
	for t in (-0.12, 0.12):
		box((0.035, 0.36, 0.335), (t, 0, 0.16), 'WoodDark', bevel=0.012, matrix=frame)


def fence(x0, y0, x1, y1, z=0.0, h=0.55):
	"""A rail fence from (x0, y0) to (x1, y1)."""
	length = math.hypot(x1 - x0, y1 - y0)
	ang = math.degrees(math.atan2(y1 - y0, x1 - x0))
	n = max(1, round(length / 0.7))
	for i in range(n + 1):
		t = i / n
		box((0.1, 0.1, h), (x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, z + h / 2), 'Wood', rot=(0, 0, ang))
	for zz in (h * 0.4, h * 0.8):
		box((length, 0.06, 0.08), ((x0 + x1) / 2, (y0 + y1) / 2, z + zz), 'Wood', rot=(0, 0, ang), bevel=0.02)


# --- export -----------------------------------------------------------------
def export(name):
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
	out = out_path(name)
	print('BUILT', name, 'faces', len(keep.data.polygons), 'dims', tuple(round(d, 2) for d in keep.dimensions), '->', out)
	bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=True)
