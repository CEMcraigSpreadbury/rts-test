# Builds tree_pine_low.glb / tree_pine_low_2.glb: a chunky toy pine, like a
# moulded plastic playset tree. A grooved, rooted trunk under four
# stacked tiers, each a smooth cone whose rim hangs in rounded scallops over a
# thick rolled lip in a darker green. Plain colours (no texture); TreeWind puts
# them on tree_wind_lit.gdshader. Vertex colours shade the grooves, undersides
# and lower tiers, and the notches carry hard creases. Forests draw thousands
# of these, so it stays near 1,400 triangles. The second variant is smaller
# and seeded differently.
#
#   "C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" --background
#       --factory-startup --python make_tree_toy.py
import bpy, bmesh, math, random, os

HERE = os.path.dirname(os.path.abspath(__file__))
# (file, seed, uniform scale)
VARIANTS = [('tree_pine_low.glb', 7, 1.0), ('tree_pine_low_2.glb', 21, 0.8)]
# Linear colours, the brightest tone of each: vertex colours shade them down
# into the grooves, the undersides and the lower tiers.
COLOURS = {
	'Leaf': (0.05, 0.27, 0.034), 'LeafDark': (0.012, 0.1, 0.016), 'Bark': (0.24, 0.09, 0.032),
}
# Rim radius, rim height, apex height, scallops; top to bottom (Blender Z up).
TIERS = [(0.82, 4.6, 6.0, 7), (1.16, 3.72, 5.15, 8), (1.45, 2.86, 4.55, 9), (1.72, 2.0, 3.95, 10)]
# Samples per scallop round the rings: a notch, then two across a broad,
# flat-topped plate.
PER_LOBE = 3


def materials():
	out = {}
	for name, c in COLOURS.items():
		m = bpy.data.materials.new(name)
		m.use_nodes = True
		b = m.node_tree.nodes['Principled BSDF']
		b.inputs['Base Color'].default_value = (*c, 1.0)
		# A satin moulded-plastic finish; the undersides duller.
		b.inputs['Roughness'].default_value = {'Leaf': 0.5, 'LeafDark': 0.7, 'Bark': 0.6}[name]
		out[name] = m
	return out


def build(seed, scale):
	rng = random.Random(seed)
	bpy.ops.wm.read_factory_settings(use_empty=True)
	mats = materials()
	mesh = bpy.data.meshes.new('Tree')
	obj = bpy.data.objects.new('Tree', mesh)
	bpy.context.scene.collection.objects.link(obj)
	for name in ('Leaf', 'LeafDark', 'Bark'):
		mesh.materials.append(mats[name])
	index = {'Leaf': 0, 'LeafDark': 1, 'Bark': 2}
	bm = bmesh.new()
	# Each vertex's shade (multiplied into its material's colour), and the
	# vertical creases to keep hard.
	shade = {}
	creases = []

	def ring(points, shades=None):
		verts = [bm.verts.new(p) for p in points]
		for i, v in enumerate(verts):
			shade[v] = shades[i] if shades else (1.0, 1.0, 1.0)
		return verts

	def band(lo, hi, mat):
		n = len(lo)
		for i in range(n):
			j = (i + 1) % n
			f = bm.faces.new((lo[i], lo[j], hi[j], hi[i]))
			f.material_index = index[mat]
			f.smooth = True

	def fan(centre, rim, mat, flip=False):
		n = len(rim)
		for i in range(n):
			j = (i + 1) % n
			f = bm.faces.new((centre, rim[j], rim[i]) if flip else (centre, rim[i], rim[j]))
			f.material_index = index[mat]
			f.smooth = True

	# Trunk: seven broad ribs of bark, each a ridge (two samples) between
	# hard-creased grooves. Every other rib spreads into a root at the foot; the
	# whole thing twists and wobbles a little as it rises into the bottom tier.
	ribs, per_rib = 7, 3
	sides = ribs * per_rib
	spin = rng.uniform(0, math.tau)
	# (radius, height, root spread at this height)
	specs = [(0.78, 0.0, 0.55), (0.66, 0.14, 0.32), (0.56, 0.42, 0.1), (0.5, 0.85, 0.0),
			(0.47, 1.35, 0.0), (0.45, 1.9, 0.0), (0.43, 2.45, 0.0)]
	rib_tone = [rng.uniform(0.85, 1.08) for _ in range(ribs)]
	rib_bulge = [rng.uniform(0.94, 1.06) for _ in range(ribs)]
	rings = []
	for r, z, spread in specs:
		twist = 0.18 * z / 2.45
		pts, shades = [], []
		for i in range(sides):
			rib, slot = divmod(i, per_rib)
			a = spin + twist + i / sides * math.tau
			groove = slot == 0
			root = 1.0 + (spread if rib % 2 == 0 and not groove else spread * 0.3)
			radius = r * (0.84 if groove else rib_bulge[rib]) * root * rng.uniform(0.98, 1.02)
			pts.append((math.cos(a) * radius, math.sin(a) * radius, z))
			# Ridges catch the light, grooves sink dark; the foot darkens into
			# the ground and the top into the canopy's shade.
			v = (0.5 if groove else 1.0) * rib_tone[rib]
			v *= 0.72 + 0.28 * min(z / 0.6, 1.0)
			v *= 1.0 - 0.3 * max(0.0, (z - 1.6) / 0.85)
			shades.append((min(v, 1.0), min(v * 0.97, 1.0), min(v * 0.94, 1.0)))
		rings.append(ring(pts, shades))
	for lo, hi in zip(rings, rings[1:]):
		band(lo, hi, 'Bark')
		for i in range(0, sides, per_rib):
			creases.append((lo[i], hi[i]))

	# Tiers. A scallop's radius swells round its middle and dips into a notch
	# between it and the next; its rim also hangs lower at the middle.
	for t, (rad, rim_z, apex_z, lobes) in enumerate(TIERS):
		spin = rng.uniform(0, math.tau)
		m = lobes * PER_LOBE
		drop = apex_z - rim_z
		lean = (rng.uniform(-0.03, 0.03), rng.uniform(-0.03, 0.03))

		def lobe(k):
			# 0 in a notch, 1 at a scallop's middle.
			# Samples land on the notch (0) and the crown (middle), so each
			# scallop comes out rounded rather than flat-topped.
			phase = (k % PER_LOBE) / PER_LOBE
			return math.sin(phase * math.pi) ** 0.7

		def at(k, r, z, depth=1.0):
			a = spin + k / m * math.tau
			s = 1.0 - depth * (1.0 - (0.8 + 0.2 * lobe(k)))
			return (lean[0] * (z - rim_z) + math.cos(a) * r * s, lean[1] * (z - rim_z) + math.sin(a) * r * s, z)

		# Lower tiers sit a little deeper in shade; each scallop is a touch
		# lighter or darker than its neighbours.
		tier_shade = 1.0 - 0.1 * t
		lobe_shade = [rng.uniform(0.82, 1.06) for _ in range(lobes)]

		def tone(k, crown, notch, warm=0.0):
			v = (notch + (crown - notch) * lobe(k)) * tier_shade * lobe_shade[k // PER_LOBE]
			# Sunlit crowns warm a touch; shaded notches cool toward blue-green.
			cool = (1.0 - lobe(k)) * 0.12
			return (min(v * (1.0 + warm - cool), 1.0), min(v, 1.0), min(v * (1.0 - warm * 0.5 + cool), 1.0))

		apex = bm.verts.new((lean[0] * drop, lean[1] * drop, apex_z))
		shade[apex] = (1.0, 1.0, 0.9)
		upper = ring([at(k, rad * 0.45, apex_z - drop * 0.5, depth=0.2) for k in range(m)],
				[tone(k, 1.0, 0.72, 0.04) for k in range(m)])
		flank = ring([at(k, rad * 0.88, rim_z + drop * 0.15 - 0.1 * lobe(k)) for k in range(m)],
				[tone(k, 0.92, 0.48) for k in range(m)])
		# The swell rounds each scallop out over its lip, like a moulded edge.
		swell = ring([at(k, rad * 0.99, rim_z + 0.06 - 0.14 * lobe(k)) for k in range(m)],
				[tone(k, 1.0, 0.55, 0.05) for k in range(m)])
		edge = ring([at(k, rad * 0.97, rim_z - 0.16 - 0.18 * lobe(k)) for k in range(m)],
				[tone(k, 0.82, 0.5) for k in range(m)])
		lip = ring([at(k, rad * 0.88, rim_z - 0.26 - 0.17 * lobe(k)) for k in range(m)],
				[tone(k, 0.9, 0.65) for k in range(m)])
		under = ring([at(k, rad * 0.58, rim_z - 0.1, depth=0.3) for k in range(m)],
				[tone(k, 0.45, 0.35) for k in range(m)])
		fan(apex, upper, 'Leaf', flip=True)
		band(flank, upper, 'Leaf')
		band(swell, flank, 'Leaf')
		band(edge, swell, 'Leaf')
		band(lip, edge, 'LeafDark')
		band(under, lip, 'LeafDark')
		centre = bm.verts.new((0, 0, rim_z - 0.05))
		shade[centre] = (0.4, 0.4, 0.4)
		fan(centre, under, 'LeafDark')
		# A crisp moulded crease up from every notch, over the skirt only; the
		# cone above stays smooth.
		for k in range(0, m, PER_LOBE):
			for lo, hi in ((flank, swell), (swell, edge)):
				creases.append((lo[k], hi[k]))

	bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
	bmesh.ops.scale(bm, vec=(scale, scale, scale), verts=bm.verts)
	for a, b in creases:
		e = bm.edges.get((a, b))
		if e is not None:
			e.smooth = False
	colour = bm.loops.layers.color.new('Col')
	for f in bm.faces:
		for loop in f.loops:
			loop[colour] = (*shade[loop.vert], 1.0)
	bm.to_mesh(mesh)
	bm.free()
	return obj


for name, seed, scale in VARIANTS:
	obj = build(seed, scale)
	obj.select_set(True)
	bpy.context.view_layer.objects.active = obj
	tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
	print('BUILT', name, tris, 'tris', 'dims', tuple(round(d, 2) for d in obj.dimensions))
	bpy.ops.export_scene.gltf(filepath=os.path.join(HERE, name), export_format='GLB', use_selection=True,
			export_vertex_color='ACTIVE')
