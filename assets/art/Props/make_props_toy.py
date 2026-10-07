# Builds the map scenery props in the toy-plastic style of the pines
# (Trees/make_tree_toy.py): bushes of round glossy puffs, ribbed logs with
# ringed cut ends, rooted stumps and bent sticks. Plain colours shaded by
# vertex colours; PlasticMaterial puts them on plastic_prop.gdshader. They
# stand in for the AmiPolyGon pack's bush/log/stick/trunk models at the same
# sizes, a few hundred triangles each since maps scatter hundreds.
#
#   "C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" --background
#       --factory-startup --python make_props_toy.py
import bpy, bmesh, math, random, os
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
# Linear colours, the brightest tone of each (the pines' greens and bark).
COLOURS = {
	'Leaf': (0.05, 0.27, 0.034), 'LeafDark': (0.012, 0.1, 0.016), 'Bark': (0.24, 0.09, 0.032),
	'LogEnd': (0.6, 0.36, 0.14),
}
ROUGH = {'Leaf': 0.5, 'LeafDark': 0.7, 'Bark': 0.6, 'LogEnd': 0.6}


class Builder:
	def __init__(self, seed):
		self.rng = random.Random(seed)
		bpy.ops.wm.read_factory_settings(use_empty=True)
		self.mesh = bpy.data.meshes.new('Prop')
		self.obj = bpy.data.objects.new('Prop', self.mesh)
		bpy.context.scene.collection.objects.link(self.obj)
		self.index = {}
		for name, c in COLOURS.items():
			m = bpy.data.materials.new(name)
			m.use_nodes = True
			b = m.node_tree.nodes['Principled BSDF']
			b.inputs['Base Color'].default_value = (*c, 1.0)
			b.inputs['Roughness'].default_value = ROUGH[name]
			self.index[name] = len(self.mesh.materials)
			self.mesh.materials.append(m)
		self.bm = bmesh.new()
		self.shade = {}
		self.creases = []

	def ring(self, points, shades):
		verts = [self.bm.verts.new(p) for p in points]
		for v, s in zip(verts, shades):
			self.shade[v] = s
		return verts

	def band(self, lo, hi, mat):
		n = len(lo)
		for i in range(n):
			j = (i + 1) % n
			f = self.bm.faces.new((lo[i], lo[j], hi[j], hi[i]))
			f.material_index = self.index[mat]
			f.smooth = True

	def fan(self, centre, rim, mat, flip=False):
		n = len(rim)
		for i in range(n):
			j = (i + 1) % n
			f = self.bm.faces.new((centre, rim[j], rim[i]) if flip else (centre, rim[i], rim[j]))
			f.material_index = self.index[mat]
			f.smooth = True

	def mound(self, cx, cy, rad, rim_z, apex_z, lobes, tier):
		"""One scalloped tier as on the pines, but low and domed: a rounded
		crown, a skirt hanging in broad plates over a dark rolled lip."""
		rng = self.rng
		per = 3
		m = lobes * per
		spin = rng.uniform(0, math.tau)
		drop = apex_z - rim_z
		lobe_tone = [rng.uniform(0.82, 1.06) for _ in range(lobes)]
		tier_tone = 1.0 - 0.12 * tier

		def lobe(k):
			return math.sin((k % per) / per * math.pi) ** 0.7

		def at(k, r, z, depth=1.0):
			a = spin + k / m * math.tau
			s = 1.0 - depth * (1.0 - (0.8 + 0.2 * lobe(k)))
			return (cx + math.cos(a) * r * s, cy + math.sin(a) * r * s, z)

		def tone(k, crown, notch):
			v = (notch + (crown - notch) * lobe(k)) * tier_tone * lobe_tone[k // per]
			cool = (1.0 - lobe(k)) * 0.12
			return (min(v * (1.0 - cool), 1.0), min(v, 1.0), min(v * (1.0 + cool), 1.0))

		apex = self.bm.verts.new((cx, cy, apex_z))
		self.shade[apex] = (1.0, 1.0, 0.95)
		crown = self.ring([at(k, rad * 0.55, apex_z - drop * 0.25, depth=0.2) for k in range(m)], [tone(k, 1.0, 0.8) for k in range(m)])
		flank = self.ring([at(k, rad * 0.9, rim_z + drop * 0.3 - 0.06 * lobe(k)) for k in range(m)], [tone(k, 0.92, 0.5) for k in range(m)])
		edge = self.ring([at(k, rad, rim_z - 0.1 * lobe(k)) for k in range(m)], [tone(k, 0.85, 0.5) for k in range(m)])
		lip = self.ring([at(k, rad * 0.88, rim_z - 0.16 - 0.1 * lobe(k)) for k in range(m)], [tone(k, 0.9, 0.65) for k in range(m)])
		under = self.ring([at(k, rad * 0.5, rim_z - 0.08, depth=0.3) for k in range(m)], [tone(k, 0.45, 0.35) for k in range(m)])
		self.fan(apex, crown, 'Leaf', flip=True)
		self.band(flank, crown, 'Leaf')
		self.band(edge, flank, 'Leaf')
		self.band(lip, edge, 'LeafDark')
		self.band(under, lip, 'LeafDark')
		centre = self.bm.verts.new((cx, cy, rim_z - 0.05))
		self.shade[centre] = (0.4, 0.4, 0.4)
		self.fan(centre, under, 'LeafDark')
		for k in range(0, m, per):
			self.creases.append((flank[k], edge[k]))

	def puff(self, centre, radius, squash, tone):
		"""A round glossy puff of leaves, dark underneath, lit on top."""
		matrix = Matrix.Translation(centre) @ Matrix.Diagonal((1.0, 1.0, squash, 1.0))
		made = bmesh.ops.create_uvsphere(self.bm, u_segments=10, v_segments=7, radius=radius, matrix=matrix)
		for v in made['verts']:
			t = max(0.0, min(1.0, (v.co.z - (centre[2] - radius * squash)) / (2 * radius * squash)))
			s = (0.45 + 0.55 * t) * tone
			self.shade[v] = (min(s * (1.0 + 0.05 * t), 1.0), min(s, 1.0), min(s * (1.0 + 0.1 * (1 - t)), 1.0))
		faces = {f for v in made['verts'] for f in v.link_faces}
		for f in faces:
			f.material_index = self.index['Leaf']
			f.smooth = True

	def ribbed(self, frame, specs, ribs, cap=None, root=0.0):
		"""A ribbed bark cylinder along `frame`'s Z, rings at (radius, z). Ridges
		lit, grooves dark and creased. `cap` closes the top end with a ringed
		cut face ('top'), both ends ('both'), or neither."""
		per = 3
		sides = ribs * per
		spin = self.rng.uniform(0, math.tau)
		tone = [self.rng.uniform(0.85, 1.08) for _ in range(ribs)]
		rings = []
		for r, z in specs:
			pts, shades = [], []
			for i in range(sides):
				rib, slot = divmod(i, per)
				a = spin + i / sides * math.tau
				groove = slot == 0
				spread = root * max(0.0, 1.0 - z / 0.2) if rib % 2 == 0 and not groove else 0.0
				rr = r * (0.84 if groove else 1.0) * (1.0 + spread)
				pts.append(frame @ Vector((math.cos(a) * rr, math.sin(a) * rr, z)))
				v = (0.5 if groove else 1.0) * tone[rib]
				shades.append((min(v, 1.0), min(v * 0.97, 1.0), min(v * 0.94, 1.0)))
			rings.append(self.ring(pts, shades))
		for lo, hi in zip(rings, rings[1:]):
			self.band(lo, hi, 'Bark')
			for i in range(0, sides, per):
				self.creases.append((lo[i], hi[i]))
		ends = {'top': [(-1, rings[-1], specs[-1])], 'both': [(-1, rings[-1], specs[-1]), (1, rings[0], specs[0])]}.get(cap, [])
		for flip, edge, (r, z) in ends:
			# Bark lip, a pale cut face, and a darker growth ring inside it.
			inner = self.ring([frame @ Vector((math.cos(spin + i / sides * math.tau) * r * 0.78,
					math.sin(spin + i / sides * math.tau) * r * 0.78, z - flip * 0.015)) for i in range(sides)],
					[(1.0, 1.0, 1.0)] * sides)
			core = self.ring([frame @ Vector((math.cos(spin + i / sides * math.tau) * r * 0.4,
					math.sin(spin + i / sides * math.tau) * r * 0.4, z - flip * 0.02)) for i in range(sides)],
					[(0.72, 0.68, 0.64)] * sides)
			if flip < 0:
				self.band(edge, inner, 'LogEnd')
				self.band(inner, core, 'LogEnd')
			else:
				self.band(inner, edge, 'LogEnd')
				self.band(core, inner, 'LogEnd')
			centre = self.bm.verts.new(frame @ Vector((0, 0, z - flip * 0.02)))
			self.shade[centre] = (0.8, 0.76, 0.7)
			self.fan(centre, core, 'LogEnd', flip=flip > 0)

	def export(self, name):
		bm = self.bm
		bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
		for a, b in self.creases:
			e = bm.edges.get((a, b))
			if e is not None:
				e.smooth = False
		colour = bm.loops.layers.color.new('Col')
		for f in bm.faces:
			for loop in f.loops:
				loop[colour] = (*self.shade[loop.vert], 1.0)
		bm.to_mesh(self.mesh)
		bm.free()
		self.obj.select_set(True)
		bpy.context.view_layer.objects.active = self.obj
		tris = sum(len(p.vertices) - 2 for p in self.mesh.polygons)
		print('BUILT', name, tris, 'tris', 'dims', tuple(round(d, 2) for d in self.obj.dimensions))
		bpy.ops.export_scene.gltf(filepath=os.path.join(HERE, name + '.glb'), export_format='GLB',
				use_selection=True, export_vertex_color='ACTIVE')


def bush(name, seed, width, height):
	"""Two scalloped mounds stacked like a squat pine's tiers, the top one
	nudged off centre."""
	b = Builder(seed)
	rng = b.rng
	r = width / 2
	b.mound(0, 0, r, height * 0.32, height * 0.62, 8, 1)
	ox, oy = rng.uniform(-0.06, 0.06) * width, rng.uniform(-0.06, 0.06) * width
	b.mound(ox, oy, r * 0.68, height * 0.66, height, 6, 0)
	b.export(name)


def log(name, seed, length, radius):
	b = Builder(seed)
	bend = b.rng.uniform(-0.04, 0.04)
	frame = Matrix.Translation((-length / 2, 0, radius * 0.92)) @ Matrix.Rotation(math.radians(90), 4, 'Y')
	b.ribbed(frame, [(radius, 0.0), (radius * 0.97, length * 0.5), (radius * 0.94, length)], 4, cap='both')
	# A broken-off branch stub on top.
	stub = Matrix.Translation((length * 0.15, 0, radius * 1.7)) @ Matrix.Rotation(math.radians(-35 + bend * 100), 4, 'Y')
	b.ribbed(stub, [(radius * 0.32, -0.05), (radius * 0.28, radius * 0.7)], 2, cap='top')
	b.export(name)


def stump(name, seed, radius, height):
	b = Builder(seed)
	b.ribbed(Matrix.Identity(4), [(radius * 1.05, 0.0), (radius * 0.9, 0.12), (radius * 0.84, height * 0.6),
			(radius * 0.82, height)], 6, cap='top', root=0.28)
	b.export(name)


def stick(name, seed, length):
	b = Builder(seed)
	rng = b.rng
	r = 0.045
	half = length / 2
	frame = Matrix.Translation((-half, 0, r)) @ Matrix.Rotation(math.radians(90), 4, 'Y') @ Matrix.Rotation(math.radians(rng.uniform(-8, 8)), 4, 'X')
	b.ribbed(frame, [(r, 0.0), (r * 0.9, length * 0.55)], 2, cap='both')
	frame2 = Matrix.Translation((-half + length * 0.52, 0, r)) @ Matrix.Rotation(math.radians(90), 4, 'Z') \
		@ Matrix.Rotation(math.radians(70), 4, 'X') @ Matrix.Rotation(math.radians(rng.uniform(-30, 30)), 4, 'Y')
	b.ribbed(Matrix.Translation((-half + length * 0.5, 0, r)) @ Matrix.Rotation(math.radians(90 + rng.uniform(10, 25)), 4, 'Y'),
			[(r * 0.88, 0.0), (r * 0.7, length * 0.48)], 2, cap='both')
	b.ribbed(frame2, [(r * 0.6, 0.0), (r * 0.45, length * 0.22)], 2, cap='top')
	b.export(name)


bush('bush_1', 11, 1.45, 1.32)
bush('bush_2', 12, 1.0, 0.9)
bush('bush_3', 13, 1.5, 1.32)
bush('bush_4', 14, 1.0, 0.9)
log('log_1', 21, 2.05, 0.28)
log('log_2', 22, 1.45, 0.2)
stump('stump_1', 31, 0.32, 0.52)
stump('stump_2', 32, 0.46, 0.47)
stick('stick_1', 41, 0.85)
stick('stick_2', 42, 1.0)
