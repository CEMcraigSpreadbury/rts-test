"""Turns a figure's merged parts into the mesh the game draws, and exports it.

finish() hardens edges per part, collapses each face's UVs onto its palette
row (U from which way the corner faces, see palette.py), and bakes into the
vertex colours what a single material cannot know by itself:

	COLOR.r  ambient occlusion (the figure's own crevices, its feet on the
	         base, the base on the ground) times a gentle top-to-toe
	         falloff, as a miniature's zenithal undercoat gives it
	COLOR.g  shine: 0 matte cloth and skin .. 1 polished steel, for the
	         game shader's roughness and specular

One mesh, one material, no textures in the GLB: the palette image is the
game's (assets/art/Models/Units/palettes/), handed to the shader there.
"""
import math
import random

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

import geo
import palette

SHINE = {
	"steel": 1.0, "trim": 0.7, "blade": 1.0, "brass": 0.85, "metal_paint": 0.45, "mail": 0.55,
	"eye": 0.7, "glint": 0.7, "leather": 0.25, "leather_dark": 0.2, "boot": 0.3, "sole": 0.1,
	"plate_dark": 0.6, "arcane": 0.3,
	"team": 0.15, "team_light": 0.15, "team_dark": 0.15,
}

AO_SAMPLES = 96
AO_REACH = 0.16
AO_STRENGTH = 0.9
AO_FLOOR = 0.32
## The zenithal falloff: this much darker at the base than at the helmet.
ZENITH_DARKEN = 0.16


def harden(bm):
	"""Hard edges where the faces either side meet at a sharper angle than
	the part they belong to allows (geo.SMOOTH, HARD, FLAT...)."""
	_sw, sh = geo._layers(bm)
	bm.normal_update()
	for f in bm.faces:
		f.smooth = True
	for e in bm.edges:
		if len(e.link_faces) != 2:
			e.smooth = len(e.link_faces) < 2
			continue
		f0, f1 = e.link_faces
		limit = math.radians(min(f0[sh], f1[sh]))
		e.smooth = e.calc_face_angle(0.0) < limit


def _hemisphere(count, seed=3):
	"""Cosine-weighted directions round +Z, fixed so every build bakes alike."""
	rng = random.Random(seed)
	dirs = []
	golden = math.pi * (3.0 - math.sqrt(5.0))
	for i in range(count):
		u = (i + 0.5) / count
		r = math.sqrt(u)
		phi = i * golden + rng.uniform(-0.1, 0.1)
		dirs.append(Vector((r * math.cos(phi), r * math.sin(phi), math.sqrt(max(0.0, 1.0 - u)))))
	return dirs


def _bake_ao(mesh, tree, top_z):
	dirs = _hemisphere(AO_SAMPLES)
	cache = {}
	values = [1.0] * len(mesh.loops)
	normals = mesh.corner_normals
	for poly in mesh.polygons:
		for li in poly.loop_indices:
			vi = mesh.loops[li].vertex_index
			n = Vector(normals[li].vector).normalized()
			key = (vi, round(n.x, 2), round(n.y, 2), round(n.z, 2))
			if key in cache:
				values[li] = cache[key]
				continue
			co = mesh.vertices[vi].co
			origin = co + n * 0.0015
			# Any frame round n will do for a fixed hemisphere pattern.
			t = n.orthogonal().normalized()
			bt = n.cross(t)
			occlusion = 0.0
			for d in dirs:
				w = t * d.x + bt * d.y + n * d.z
				hit_dist = None
				loc, _nrm, _i, dist = tree.ray_cast(origin, w, AO_REACH)
				if loc is not None:
					hit_dist = dist
				# The ground the figure stands on.
				if w.z < -1e-4:
					ground = -origin.z / w.z
					if ground < AO_REACH and (hit_dist is None or ground < hit_dist):
						hit_dist = ground
				if hit_dist is not None:
					occlusion += 1.0 - (hit_dist / AO_REACH) ** 2
			ao = 1.0 - AO_STRENGTH * occlusion / len(dirs)
			ao = max(AO_FLOOR, ao)
			height = min(1.0, max(0.0, co.z / max(top_z, 1e-6)))
			ao *= 1.0 - ZENITH_DARKEN * (1.0 - height * height * (3.0 - 2.0 * height))
			cache[key] = ao
			values[li] = ao
	return values


def finish(bm, name):
	"""A Blender mesh `name` from the merged figure, painted and baked."""
	harden(bm)
	mesh = bpy.data.meshes.new(name)
	bm.to_mesh(mesh)
	mesh.update()
	sw_attr = mesh.attributes["swatch"]
	swatches = [d.value for d in sw_attr.data]

	uv_layer = mesh.uv_layers.new(name="UVMap")
	normals = mesh.corner_normals
	for poly in mesh.polygons:
		name_row = palette.LAYOUT[swatches[poly.index]]
		for li in poly.loop_indices:
			nz = normals[li].vector[2]
			uv_layer.data[li].uv = palette.uv(name_row, 0.5 + 0.5 * nz)

	verts = [v.co.copy() for v in mesh.vertices]
	polys = [list(p.vertices) for p in mesh.polygons]
	tree = BVHTree.FromPolygons(verts, polys)
	top_z = max(v.z for v in verts)
	ao = _bake_ao(mesh, tree, top_z)

	colour = mesh.color_attributes.new("Color", 'FLOAT_COLOR', 'CORNER')
	for poly in mesh.polygons:
		shine = SHINE.get(palette.LAYOUT[swatches[poly.index]], 0.0)
		for li in poly.loop_indices:
			colour.data[li].color = (ao[li], shine, 0.0, 1.0)
	mesh.color_attributes.active_color = colour
	mesh.color_attributes.render_color_index = mesh.color_attributes.find("Color")
	# The working layers are not for the game.
	for attr in ("swatch", "sharp_deg"):
		if attr in mesh.attributes:
			mesh.attributes.remove(mesh.attributes[attr])
	return mesh


def triangles(mesh):
	return sum(len(p.vertices) - 2 for p in mesh.polygons)


def preview_material(palette_png, name="Figure"):
	"""Blender-only: the palette times the baked AO, shine as roughness —
	what the game's shader does, near enough to judge a render by."""
	mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
	mat.use_nodes = True
	nt = mat.node_tree
	nt.nodes.clear()
	out = nt.nodes.new("ShaderNodeOutputMaterial")
	bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
	tex = nt.nodes.new("ShaderNodeTexImage")
	tex.image = bpy.data.images.load(str(palette_png), check_existing=True)
	tex.interpolation = 'Linear'
	tex.extension = 'EXTEND'
	attr = nt.nodes.new("ShaderNodeAttribute")
	attr.attribute_name = "Color"
	attr.attribute_type = 'GEOMETRY'
	sep = nt.nodes.new("ShaderNodeSeparateColor")
	mul = nt.nodes.new("ShaderNodeMix")
	mul.data_type = 'RGBA'
	mul.blend_type = 'MULTIPLY'
	mul.inputs[0].default_value = 1.0
	rough = nt.nodes.new("ShaderNodeMapRange")
	rough.inputs["To Min"].default_value = 0.8
	rough.inputs["To Max"].default_value = 0.32
	nt.links.new(attr.outputs["Color"], sep.inputs["Color"])
	nt.links.new(tex.outputs["Color"], mul.inputs[6])
	nt.links.new(sep.outputs[0], mul.inputs[7])
	nt.links.new(mul.outputs[2], bsdf.inputs["Base Color"])
	nt.links.new(sep.outputs[1], rough.inputs["Value"])
	nt.links.new(rough.outputs["Result"], bsdf.inputs["Roughness"])
	nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
	return mat


def export_glb(obj, path):
	bpy.ops.object.select_all(action='DESELECT')
	obj.select_set(True)
	bpy.context.view_layer.objects.active = obj
	bpy.ops.export_scene.gltf(
		filepath=str(path), export_format='GLB', use_selection=True,
		export_image_format='NONE', export_materials='EXPORT',
		export_vertex_color='ACTIVE', export_all_vertex_colors=False,
		export_normals=True, export_texcoords=True, export_tangents=False,
		export_yup=True, export_apply=False, export_cameras=False, export_lights=False,
		export_extras=False, export_animations=False, export_skins=False, export_morph=False,
	)
