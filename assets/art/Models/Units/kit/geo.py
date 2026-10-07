"""Mesh building blocks for the figure kit.

Every part of a figure is a small bmesh whose faces carry a palette row in the
int face layer SWATCH (see palette.py). Parts are built round the origin, then
placed and merged into one mesh by figure.py. Blender axes: Z up, a figure
faces -Y (Blender's front view), which the glTF export turns into Godot's +Z.

All lengths are metres.
"""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

SWATCH = "swatch"
## Faces this many degrees or more apart get a hard edge; under it they shade
## smooth. Parts pick their own (armour and blades low, cloth and skin high).
SMOOTH = 70.0
HARD = 28.0
FLAT = 1.0


def new_bm():
	bm = bmesh.new()
	bm.faces.layers.int.new(SWATCH)
	bm.faces.layers.int.new("sharp_deg")
	return bm


def _layers(bm):
	sw = bm.faces.layers.int.get(SWATCH) or bm.faces.layers.int.new(SWATCH)
	sh = bm.faces.layers.int.get("sharp_deg") or bm.faces.layers.int.new("sharp_deg")
	return sw, sh


def paint(bm, swatch, sharp=SMOOTH, faces=None):
	"""Sets the palette row and hard-edge angle of `faces` (default all)."""
	sw, sh = _layers(bm)
	for f in (faces if faces is not None else bm.faces):
		f[sw] = swatch
		f[sh] = int(sharp)
	return bm


def transform(bm, matrix):
	bmesh.ops.transform(bm, matrix=matrix, verts=bm.verts)
	return bm


def translate(bm, offset):
	return transform(bm, Matrix.Translation(Vector(offset)))


def scale(bm, sx, sy, sz):
	return transform(bm, Matrix.Diagonal((sx, sy, sz, 1.0)))


def rotate(bm, angle_deg, axis):
	return transform(bm, Matrix.Rotation(math.radians(angle_deg), 4, axis))


def frame(origin, z_axis, y_hint=(0.0, 0.0, 1.0)):
	"""A matrix placing a part built along local +Z at `origin`, local +Z
	pointing along `z_axis` and local +Y as close to `y_hint` as it can be."""
	z = Vector(z_axis).normalized()
	y_hint = Vector(y_hint)
	x = y_hint.cross(z)
	if x.length < 1e-6:
		x = Vector((1.0, 0.0, 0.0)).cross(z)
	x.normalize()
	y = z.cross(x).normalized()
	m = Matrix((
		(x.x, y.x, z.x, origin[0]),
		(x.y, y.y, z.y, origin[1]),
		(x.z, y.z, z.z, origin[2]),
		(0.0, 0.0, 0.0, 1.0),
	))
	return m


def merge(dst, src, matrix=None):
	"""Appends `src` into `dst` (faces, smoothing, swatches), optionally moved."""
	sw_s, sh_s = _layers(src)
	sw_d, sh_d = _layers(dst)
	vmap = {}
	for v in src.verts:
		co = v.co.copy() if matrix is None else matrix @ v.co
		vmap[v] = dst.verts.new(co)
	for f in src.faces:
		try:
			nf = dst.faces.new([vmap[v] for v in f.verts])
		except ValueError:
			continue
		nf.smooth = True
		nf[sw_d] = f[sw_s]
		nf[sh_d] = f[sh_s]
	return dst


def lathe(profile, segments, swatch=0, sharp=SMOOTH, warp=None, cap_start=None, cap_end=None,
		ring_swatches=None, phase=-math.pi / 2.0, sx=1.0, sy=1.0):
	"""Revolves `profile` [(r, z), ...] round local Z.

	A point with r == 0 is a pole. `warp(theta, r, z) -> (x, y, z)` reshapes the
	surface freely (default an ellipse sx by sy). The profile walks so that the
	surface's outside is on its right going up (bottom to top for a body); a
	start/end cap is an n-gon painted `cap_start`/`cap_end` (None = open).
	`ring_swatches[k]` paints the band between profile points k and k+1.
	The default phase puts a vertex dead ahead (-Y), so a part is symmetric.
	"""
	bm = new_bm()
	sw, sh = _layers(bm)
	if warp is None:
		def warp(theta, r, z):
			return (r * math.cos(theta) * sx, r * math.sin(theta) * sy, z)
	rings = []
	for r, z in profile:
		if r <= 1e-7:
			rings.append([bm.verts.new(warp(0.0, 0.0, z))])
			continue
		ring = []
		for i in range(segments):
			theta = phase + 2.0 * math.pi * i / segments
			ring.append(bm.verts.new(warp(theta, r, z)))
		rings.append(ring)

	def put(verts, row):
		try:
			f = bm.faces.new(verts)
		except ValueError:
			return None
		f.smooth = True
		f[sw] = row
		f[sh] = int(sharp)
		return f

	for k in range(len(rings) - 1):
		a, b = rings[k], rings[k + 1]
		row = ring_swatches[k] if ring_swatches is not None else swatch
		for i in range(segments):
			j = (i + 1) % segments
			if len(a) == 1 and len(b) == 1:
				continue
			if len(a) == 1:
				put([a[0], b[j], b[i]], row)
			elif len(b) == 1:
				put([a[i], a[j], b[0]], row)
			else:
				put([a[i], a[j], b[j], b[i]], row)
	if cap_start is not None and len(rings[0]) > 2:
		put(list(reversed(rings[0])), cap_start)
	if cap_end is not None and len(rings[-1]) > 2:
		put(list(rings[-1]), cap_end)
	return bm


def ellipsoid(rx, ry, rz, segments=8, rings=5, swatch=0, sharp=SMOOTH, squash_bottom=1.0):
	"""An ellipsoid round the origin; `squash_bottom` < 1 flattens its lower half."""
	profile = []
	for k in range(rings + 1):
		phi = math.pi * k / rings
		z = -math.cos(phi)
		if z < 0.0:
			z *= squash_bottom
		profile.append((math.sin(phi), z))
	bm = lathe(profile, segments, swatch, sharp, sx=rx, sy=ry)
	scale(bm, 1.0, 1.0, rz)
	return bm


def box(sx, sy, sz, swatch=0, sharp=HARD, bevel=0.0, bevel_segments=1, profile=0.5):
	"""A box sx by sy by sz centred on the origin, its edges optionally bevelled."""
	bm = new_bm()
	bmesh.ops.create_cube(bm, size=1.0)
	scale(bm, sx, sy, sz)
	if bevel > 0.0:
		bmesh.ops.bevel(bm, geom=list(bm.edges) + list(bm.verts), offset=bevel, offset_type='OFFSET',
				segments=bevel_segments, profile=profile, affect='EDGES', clamp_overlap=True)
	for f in bm.faces:
		f.smooth = True
	return paint(bm, swatch, sharp)


def subdivided(bm, levels):
	"""Catmull-Clark `levels` deep, through a throwaway object (bmesh has none)."""
	mesh = bpy.data.meshes.new("_subd")
	bm.to_mesh(mesh)
	obj = bpy.data.objects.new("_subd", mesh)
	bpy.context.scene.collection.objects.link(obj)
	mod = obj.modifiers.new("subd", 'SUBSURF')
	mod.levels = levels
	mod.render_levels = levels
	mod.quality = 3
	deps = bpy.context.evaluated_depsgraph_get()
	evaluated = obj.evaluated_get(deps)
	out = bmesh.new()
	out.from_mesh(evaluated.to_mesh())
	_layers(out)
	evaluated.to_mesh_clear()
	bpy.data.objects.remove(obj)
	bpy.data.meshes.remove(mesh)
	for f in out.faces:
		f.smooth = True
	return out


def fit(bm, size, centre=(0.0, 0.0, 0.0)):
	"""Rescales and moves `bm` so its bounds are `size` round `centre`."""
	lo = Vector((min(v.co[i] for v in bm.verts) for i in range(3)))
	hi = Vector((max(v.co[i] for v in bm.verts) for i in range(3)))
	mid = (lo + hi) * 0.5
	ext = hi - lo
	for v in bm.verts:
		for i in range(3):
			v.co[i] = centre[i] + (v.co[i] - mid[i]) * (size[i] / max(ext[i], 1e-9))
	return bm


def bvh(bm):
	bm.normal_update()
	return BVHTree.FromBMesh(bm)


def project(tree, origin, direction):
	"""(point, normal) where a ray from `origin` along `direction` meets `tree`."""
	loc, nrm, _i, _d = tree.ray_cast(Vector(origin), Vector(direction).normalized())
	if loc is None:
		return None, None
	return loc, nrm


def ribbon(points, normals, width, thickness, swatch=0, sharp=HARD, embed=0.002, widths=None, closed_ends=True,
		bottom=False):
	"""A strap of rectangular section laid along `points` on a surface whose
	normals there are `normals`: straps, helmet ribs, shield emblems.

	It sits `embed` into the surface so it never floats or flickers. `widths`
	gives a width per point instead of one. Without `bottom` the underside
	(always buried) is left out.
	"""
	bm = new_bm()
	sw, sh = _layers(bm)
	n = len(points)
	stations = []
	for i in range(n):
		p = Vector(points[i])
		nrm = Vector(normals[i]).normalized()
		if i == 0:
			t = Vector(points[1]) - p
		elif i == n - 1:
			t = p - Vector(points[i - 1])
		else:
			t = Vector(points[i + 1]) - Vector(points[i - 1])
		t.normalize()
		side = t.cross(nrm).normalized()
		w = (widths[i] if widths is not None else width) * 0.5
		base = p - nrm * embed
		top = p + nrm * thickness
		stations.append([
			bm.verts.new(base - side * w),
			bm.verts.new(base + side * w),
			bm.verts.new(top + side * w),
			bm.verts.new(top - side * w),
		])

	def put(verts):
		f = bm.faces.new(verts)
		f.smooth = True
		f[sw] = swatch
		f[sh] = int(sharp)

	for i in range(n - 1):
		a, b = stations[i], stations[i + 1]
		sides = [(0, 1), (1, 2), (2, 3), (3, 0)] if bottom else [(1, 2), (2, 3), (3, 0)]
		for s0, s1 in sides:
			put([a[s0], b[s0], b[s1], a[s1]])
	if closed_ends:
		put([stations[0][0], stations[0][1], stations[0][2], stations[0][3]])
		put([stations[-1][3], stations[-1][2], stations[-1][1], stations[-1][0]])
	return bm


def disc(radius_x, radius_y, segments, swatch, dome=0.0, depth=0.004, sharp=SMOOTH, simple=False):
	"""A lens lying on local XY facing +Z: rim `depth` below z=0 (to bury it in
	the surface it sits on), centre `dome` above. Eyes, blush, decals.
	`simple` drops the middle ring, for the tiny ones."""
	profile = [(1.0, -depth), (0.0, dome)] if simple else [(1.0, -depth), (0.55, dome * 0.75), (0.0, dome)]
	return lathe(profile, segments, swatch, sharp, sx=radius_x, sy=radius_y, phase=0.0)


def tri_count(bm):
	return sum(len(f.verts) - 2 for f in bm.faces)


def loft(sections, segments, swatch=0, sharp=SMOOTH, cap_start=None, cap_end=None, ring_swatches=None,
		phase=-math.pi / 2.0):
	"""Like lathe(), but every ring is its own horizontal ellipse:
	`sections` [((cx, cy, z), rx, ry), ...] bottom to top. Boots, scabbards."""
	def warp_for(k):
		(cx, cy, cz), rx, ry = sections[k]
		return lambda theta, r, z: (cx + rx * r * math.cos(theta), cy + ry * r * math.sin(theta), cz)

	bm = new_bm()
	sw, sh = _layers(bm)
	rings = []
	for k, ((cx, cy, cz), rx, ry) in enumerate(sections):
		if rx <= 1e-7 and ry <= 1e-7:
			rings.append([bm.verts.new((cx, cy, cz))])
			continue
		ring = []
		for i in range(segments):
			theta = phase + 2.0 * math.pi * i / segments
			ring.append(bm.verts.new((cx + rx * math.cos(theta), cy + ry * math.sin(theta), cz)))
		rings.append(ring)

	def put(verts, row):
		try:
			f = bm.faces.new(verts)
		except ValueError:
			return
		f.smooth = True
		f[sw] = row
		f[sh] = int(sharp)

	for k in range(len(rings) - 1):
		a, b = rings[k], rings[k + 1]
		row = ring_swatches[k] if ring_swatches is not None else swatch
		for i in range(segments):
			j = (i + 1) % segments
			if len(a) == 1:
				put([a[0], b[j], b[i]], row)
			elif len(b) == 1:
				put([a[i], a[j], b[0]], row)
			else:
				put([a[i], a[j], b[j], b[i]], row)
	if cap_start is not None and len(rings[0]) > 2:
		put(list(reversed(rings[0])), cap_start)
	if cap_end is not None and len(rings[-1]) > 2:
		put(list(rings[-1]), cap_end)
	return bm


def delete_faces(bm, predicate):
	"""Removes faces `predicate(face)` picks (ones buried inside other parts)."""
	doomed = [f for f in bm.faces if predicate(f)]
	bmesh.ops.delete(bm, geom=doomed, context='FACES')
	return bm


def plate(outline, thickness, front, back=None, side=None, sharp=HARD, bend=0.0):
	"""A flat slab: `outline` [(x, z), ...] in the local XZ plane, `thickness`
	deep along Y (centred). The face toward -Y is painted `front`, the one
	toward +Y `back`, the edges `side`. `bend` curls it back (+Y) toward its
	left and right edges, as a shield's face curves. Flags, blades, shields."""
	back = front if back is None else back
	side = back if side is None else side
	bm = new_bm()
	sw, sh = _layers(bm)
	half = thickness * 0.5
	fr = [bm.verts.new((x, -half + bend * x * x, z)) for x, z in outline]
	bk = [bm.verts.new((x, half + bend * x * x, z)) for x, z in outline]
	faces = []
	try:
		faces.append(bm.faces.new(fr))
		faces.append(bm.faces.new(list(reversed(bk))))
	except ValueError:
		pass
	n = len(outline)
	for i in range(n):
		j = (i + 1) % n
		try:
			faces.append(bm.faces.new([fr[i], bk[i], bk[j], fr[j]]))
		except ValueError:
			pass
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	bm.normal_update()
	for f in bm.faces:
		f.smooth = True
		f[sh] = int(sharp)
		if f.normal.y < -0.5:
			f[sw] = front
		elif f.normal.y > 0.5:
			f[sw] = back
		else:
			f[sw] = side
	return bm


def tube(points, radii, segments, swatch=0, sharp=SMOOTH, cap_start=None, cap_end=None, flatten=1.0,
		up=(0.0, 0.0, 1.0), ring_swatches=None):
	"""A tube along the polyline `points`, `radii[i]` round each, its rings
	kept square to the line (parallel-transported frames, so it never
	twists). `flatten` < 1 squeezes it across `up`: a mane, a feather, a
	bow limb. A radius of 0 is a point. Tails, plumes, necks, limbs."""
	bm = new_bm()
	sw, sh = _layers(bm)
	pts = [Vector(p) for p in points]
	n = len(pts)
	tangents = []
	for i in range(n):
		if i == 0:
			t = pts[1] - pts[0]
		elif i == n - 1:
			t = pts[-1] - pts[-2]
		else:
			t = pts[i + 1] - pts[i - 1]
		tangents.append(t.normalized())
	normal = Vector(up).cross(tangents[0])
	if normal.length < 1e-6:
		normal = Vector((1.0, 0.0, 0.0)).cross(tangents[0])
	normal.normalize()
	rings = []
	for i in range(n):
		if i > 0:
			axis = tangents[i - 1].cross(tangents[i])
			if axis.length > 1e-6:
				angle = tangents[i - 1].angle(tangents[i])
				normal = Matrix.Rotation(angle, 3, axis.normalized()) @ normal
		binormal = tangents[i].cross(normal).normalized()
		r = radii[i]
		if r <= 1e-7:
			rings.append([bm.verts.new(pts[i])])
			continue
		ring = []
		for k in range(segments):
			a = 2.0 * math.pi * k / segments
			ring.append(bm.verts.new(pts[i] + normal * (math.cos(a) * r) + binormal * (math.sin(a) * r * flatten)))
		rings.append(ring)

	def put(verts, row):
		try:
			f = bm.faces.new(verts)
		except ValueError:
			return
		f.smooth = True
		f[sw] = row
		f[sh] = int(sharp)

	for i in range(n - 1):
		a, b = rings[i], rings[i + 1]
		row = ring_swatches[i] if ring_swatches is not None else swatch
		for k in range(segments):
			j = (k + 1) % segments
			if len(a) == 1 and len(b) == 1:
				continue
			if len(a) == 1:
				put([a[0], b[k], b[j]], row)
			elif len(b) == 1:
				put([a[k], b[0], a[j]], row)
			else:
				put([a[k], b[k], b[j], a[j]], row)
	if cap_start is not None and len(rings[0]) > 2:
		put(list(rings[0]), cap_start)
	if cap_end is not None and len(rings[-1]) > 2:
		put(list(reversed(rings[-1])), cap_end)
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	return bm


def flipped(bm, swatch=None, inset=0.0):
	"""An inside-out copy of `bm` (its faces turned to look inward), pulled
	`inset` along its own normals: the lining of a hood or a cape."""
	out = new_bm()
	merge(out, bm)
	out.normal_update()
	if inset:
		for v in out.verts:
			v.co -= v.normal * inset
	bmesh.ops.reverse_faces(out, faces=out.faces)
	if swatch is not None:
		sw, _sh = _layers(out)
		for f in out.faces:
			f[sw] = swatch
	return out


def orient(origin, forward, up=(0.0, 0.0, 1.0)):
	"""A matrix putting a part built facing -Y (and up +Z) at `origin`, its
	front turned to `forward`, its top as near `up` as it can be."""
	y = -Vector(forward).normalized()
	up = Vector(up)
	z = up - y * up.dot(y)
	if z.length < 1e-6:
		z = Vector((0.0, 0.0, 1.0)) - y * y.z
	z.normalize()
	x = y.cross(z).normalized()
	return Matrix((
		(x.x, y.x, z.x, origin[0]),
		(x.y, y.y, z.y, origin[1]),
		(x.z, y.z, z.z, origin[2]),
		(0.0, 0.0, 0.0, 1.0),
	))
